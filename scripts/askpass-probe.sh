#!/bin/bash
# Phase 2's gate: **where does ssh put the host-key question when askpass is
# forced?**
#
# The app answers a password through SSH_ASKPASS. ssh puts *every* prompt of a
# connection through that helper, the "are you sure you want to continue
# connecting?" among them — and `Terminal/HostKey.swift` now owns that
# question on the pty. Forcing askpass could take it away from the dialog the
# app already has.
#
# This needs no valid password: **the host-key question comes before
# authentication**, so an sshd that would refuse us anyway still asks it.
# macOS's own sshd on a loopback port, the shape `LocalSSHD` uses, with a
# known_hosts that does not hold its key.
#
# Three variants:
#   A  REQUIRE=force, the helper answers questions          → who is asked?
#   B  REQUIRE=force, the helper declines (exit 1)          → does ssh fall back?
#   C  REQUIRE unset, a pty present                         → is askpass used at all?
set -uo pipefail

root="${TMPDIR:-/tmp}/shellhand-askpass-probe"
rm -rf "$root" 2>/dev/null
mkdir -p "$root"

say() { printf '\n== %s ==\n' "$*"; }

# --- a server of its own --------------------------------------------------
ssh-keygen -q -t ed25519 -N '' -f "$root/host" </dev/null
ssh-keygen -q -t ed25519 -N '' -f "$root/client" </dev/null
cp "$root/client.pub" "$root/authorized_keys"
port=$(/usr/bin/python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')

cat > "$root/sshd_config" <<EOF
ListenAddress 127.0.0.1
Port $port
HostKey $root/host
PidFile $root/sshd.pid
AuthorizedKeysFile $root/authorized_keys
PubkeyAuthentication no
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM no
StrictModes no
AllowUsers $(id -un)
PrintLastLog no
PrintMotd no
EOF

/usr/sbin/sshd -D -E "$root/sshd.log" -f "$root/sshd_config" &
sshd_pid=$!
stop() { kill "$sshd_pid" 2>/dev/null; }
trap stop EXIT
for _ in $(seq 1 50); do
    grep -q "Server listening on 127.0.0.1 port $port" "$root/sshd.log" 2>/dev/null && break
    sleep 0.2
done
grep -q "Server listening" "$root/sshd.log" 2>/dev/null \
    || { echo "sshd did not start:"; tail -5 "$root/sshd.log"; exit 1; }
echo "sshd listening on 127.0.0.1:$port (password auth on, pubkey off)"

# --- the helper ssh would ask ---------------------------------------------
cat > "$root/askpass.sh" <<'EOF'
#!/bin/sh
printf 'PROMPT: %s\n' "$*" >> "$ASKPASS_LOG"
if [ "${ASKPASS_MODE:-answer}" = "decline" ]; then
    printf 'DECLINED (exit 1)\n' >> "$ASKPASS_LOG"
    exit 1
fi
case "$*" in
    *"(yes/no"*|*"'yes'"*) printf 'ANSWERED yes\n' >> "$ASKPASS_LOG"; echo yes ;;
    *) printf 'ANSWERED with a password\n' >> "$ASKPASS_LOG"; echo not-the-real-password ;;
esac
EOF
chmod +x "$root/askpass.sh"

# ssh with a known_hosts that does not hold this server's key, so the question
# is asked — and with everything of the user's kept out, as the suite does.
common=(
    -F /dev/null
    -o "UserKnownHostsFile=$root/known_hosts"
    -o GlobalKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=ask
    -o UpdateHostKeys=no
    -o IdentityAgent=none
    -o IdentitiesOnly=yes
    -o ControlMaster=no
    -o ControlPath=none
    -o NumberOfPasswordPrompts=1
    -o ConnectTimeout=5
    -p "$port"
)

run() { # run <name> <require> <mode>
    local name="$1" require="$2" mode="$3"
    : > "$root/$name.askpass.log"
    rm -f "$root/known_hosts"
    local env=(
        "SSH_ASKPASS=$root/askpass.sh"
        "ASKPASS_LOG=$root/$name.askpass.log"
        "ASKPASS_MODE=$mode"
    )
    [ -n "$require" ] && env+=("SSH_ASKPASS_REQUIRE=$require")
    # Under a pty, as the app runs it: SwiftTerm starts ssh on one, and
    # whether a pty is present is exactly what decides this.
    /usr/bin/env "${env[@]}" \
        /usr/bin/script -q "$root/$name.tty.txt" \
        /usr/bin/perl -e 'alarm 20; exec @ARGV' \
        /usr/bin/ssh "${common[@]}" "$(id -un)@127.0.0.1" true </dev/null >/dev/null 2>&1
    echo "   ssh exit: $?"
    echo "   helper saw:"
    if [ -s "$root/$name.askpass.log" ]; then sed 's/^/     /' "$root/$name.askpass.log"
    else echo "     (never called)"; fi
    echo "   the pty saw:"
    tr -d '\r' < "$root/$name.tty.txt" | grep -viE '^script (started|done)|^$' | sed 's/^/     /' | head -8
    echo "   known_hosts after: $( [ -s "$root/known_hosts" ] && echo 'written' || echo 'empty')"
}

say "A — askpass forced, helper answers"
run A force answer

say "B — askpass forced, helper declines the question"
run B force decline

say "C — askpass set but not forced, a pty present"
run C "" answer

# **Why C does not call the helper is not the pty alone.** ssh wants no tty
# *and* `DISPLAY` set before it will use a helper, and these two separate the
# conditions — which matters, because a GUI app on macOS has no `DISPLAY`, so
# an unattended child without `force` never runs the helper at all and dies
# at preauth with "Permission denied". Reading C as "no tty is enough" cost a
# connection that looked like a bad password.
notty() { # notty <name> <extra env…>
    local name="$1"; shift
    : > "$root/$name.askpass.log"
    rm -f "$root/known_hosts"
    /usr/bin/env "SSH_ASKPASS=$root/askpass.sh" "ASKPASS_LOG=$root/$name.askpass.log" \
        "ASKPASS_MODE=answer" "$@" \
        /usr/bin/perl -e 'alarm 20; exec @ARGV' \
        /usr/bin/ssh "${common[@]}" "$(id -un)@127.0.0.1" true </dev/null >/dev/null 2>&1
    if [ -s "$root/$name.askpass.log" ]; then echo "   helper CALLED"
    else echo "   helper not called"; fi
}

say "D — no tty at all, no DISPLAY, not forced"
notty D

say "E — no tty at all, DISPLAY set, not forced"
notty E DISPLAY=:0

say "F — no tty at all, forced"
notty F SSH_ASKPASS_REQUIRE=force
