#!/bin/bash
# Does the app actually work as ssh's askpass helper?
#
# The suite holds which prompt is a question and what a connection carries;
# what it cannot hold is the app **being** the helper — a SwiftUI `@main`
# answering on stdout and exiting out of `init()` before any window exists.
# That is the riskiest unproven part of the SFTP password path, and it is
# cheap to check by hand.
#
# The item goes under a service of this run's own with `-A`, so the keychain
# does not stop to ask whether this binary may read what `security` wrote.
# Removed again at the end, whatever happens.
set -uo pipefail
app=${SHELLHAND_APP:-$(cd "$(dirname "$0")/.." && pwd)/build/Build/Products/Debug/Shellhand.app}
binary="$app/Contents/MacOS/Shellhand"
[ -x "$binary" ] || { echo "no build at $app — build the Debug scheme first"; exit 1; }
svc="Shellhand helper check $$"
id="identity-$$"
pw="correct-horse-battery-staple"

cleanup() { security delete-generic-password -s "$svc" -a "$id" >/dev/null 2>&1; }
trap cleanup EXIT

security add-generic-password -s "$svc" -a "$id" -w "$pw" -A -U >/dev/null 2>&1 \
    || { echo "could not put a password in the keychain"; exit 1; }
echo "put a password under a service of this run's own"

ask() { # ask <prompt>
    SHELLHAND_ASKPASS_ACCOUNT="$id" SHELLHAND_KEYCHAIN_SERVICE="$svc" \
        /usr/bin/perl -e 'alarm 20; exec @ARGV' "$binary" "$1" 2>"$svc.err"
    local status=$?
    # To stderr, not stdout: the caller captures stdout, which is the
    # helper's answer and must hold nothing else — the same reason ssh takes
    # whatever it finds there.
    echo "   exit $status" >&2
    [ -s "$svc.err" ] && sed 's/^/   stderr: /' "$svc.err" >&2
    rm -f "$svc.err"
    return $status
}

echo "— a password prompt —"
got=$(ask "cuonggt@10.0.9.2's password: ")
if [ "$got" = "$pw" ]; then echo "   ANSWERED with the stored password ✓"
else echo "   said: '$got' — expected the stored password ✗"; fi

echo "— ssh's question about a new host key —"
got=$(ask "Are you sure you want to continue connecting (yes/no/[fingerprint])? ")
if [ "$got" = "no" ]; then echo "   ANSWERED no ✓ — nobody can read a fingerprint in a window with no terminal"
else echo "   said: '$got' — expected no ✗"; fi

echo "— an account with nothing stored —"
got=$(SHELLHAND_ASKPASS_ACCOUNT="nobody-$$" SHELLHAND_KEYCHAIN_SERVICE="$svc" \
    /usr/bin/perl -e 'alarm 20; exec @ARGV' "$binary" "password: " 2>&1)
echo "   said: '$got'"

echo "— and no window was opened —"
sleep 1
pgrep -lf 'Debug/Shellhand.app/Contents/MacOS/Shellhand' || echo "   nothing left running ✓"
