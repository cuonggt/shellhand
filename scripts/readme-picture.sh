#!/bin/bash
# Takes the README's picture: the host window on a list of its own, sized to
# the picture's 1220×798, with db-01 in the inspector — the host that inherits
# its user, key and palette from Production and its jump host from US, which is
# the whole point of the picture.
#
#   ./scripts/readme-picture.sh [path]       (default docs/screenshot.png)
#     --keep   leave the window open and the scratch directory behind
#
# This was a drive done by hand twice, on 2026-10-29 and 2026-10-31, and the
# notes list five things that go wrong. They are all handled here rather than
# remembered: every other copy refused rather than driven, the preference
# domain borrowed and given back, `XCTestSessionIdentifier` set so that nothing
# of the user's `~/.ssh/config` reaches a public image, the window sized before
# anything is arrowed, and the picture taken with `-l` on a CoreGraphics window
# number so it is that window and nothing over it.
#
# The one thing it cannot do is take the screen politely: `screencapture` wants
# the app frontmost, so this steals focus for a few seconds. Don't run it while
# somebody is typing. → docs/notes/driving.md#taking-the-readmes-picture
set -uo pipefail
cd "$(dirname "$0")/.."

keep=0
out=docs/screenshot.png
for argument in "$@"; do
    case $argument in
        --keep) keep=1 ;;
        -*) echo "usage: $0 [--keep] [path]" >&2; exit 2 ;;
        *) out=$argument ;;
    esac
done

app=${SHELLHAND_APP:-build/Build/Products/Debug/Shellhand.app}
binary="$app/Contents/MacOS/Shellhand"
width=1220
height=798
fail() { echo "readme-picture: $*" >&2; exit 1; }
say() { echo "readme-picture: $*"; }

[ -x "$binary" ] || fail "no build at $app — build the Debug scheme first"

# --- the same two guards window-check keeps, for the same reasons ----------

# Every copy shares the preference domain this borrows, and System Events
# addresses a process by name, so two copies make every lookup ambiguous.
# Never quit the user's: refuse and say so.
if pgrep -f 'Shellhand.app/Contents/MacOS/Shellhand' > /dev/null; then
    pgrep -lf 'Shellhand.app/Contents/MacOS/Shellhand' >&2
    fail "another copy of Shellhand is running. Quit it first — it shares the
       preference domain this borrows, and with two copies System Events
       cannot tell which window it is looking at."
fi

locked=$(/usr/bin/python3 -I - <<'LOCKED'
import plistlib, subprocess

raw = subprocess.run(
    ["/usr/sbin/ioreg", "-n", "Root", "-d1", "-a"], capture_output=True).stdout


def locked(node):
    if isinstance(node, dict):
        for session in node.get("IOConsoleUsers") or []:
            if isinstance(session, dict) and session.get("CGSSessionScreenIsLocked"):
                return True
        return any(locked(value) for value in node.values())
    if isinstance(node, list):
        return any(locked(value) for value in node)
    return False


try:
    print("yes" if locked(plistlib.loads(raw)) else "no")
except Exception:
    print("unknown")
LOCKED
)
[ "$locked" = yes ] && fail "the screen is locked. Behind the lock System Events
       reports no windows for any process, and screencapture photographs the
       lock — the failure would read as the app never launching."
say "locked: $locked; frontmost: $(osascript -e 'tell application "System Events" to return (name of first application process whose frontmost is true)' 2>/dev/null)"

# --- the user's preferences, borrowed and given back ----------------------

scratch=$(mktemp -d /tmp/shellhand-readme-picture.XXXXXX)
saved="$scratch/defaults.plist"
defaults export com.shellhand.Shellhand "$saved" 2>/dev/null || :
restore() {
    [ -f "$saved" ] && defaults import com.shellhand.Shellhand "$saved" 2>/dev/null || :
    [ "$keep" -eq 1 ] || rm -rf "$scratch"
}
trap restore EXIT

db="$scratch/shellhand.sqlite"
config="$scratch/config.yml"
: > "$config"

# --- a list of its own, made by the app and seeded behind it --------------

# The app creates and migrates the store, so the schema is this build's rather
# than whatever this script believes it to be.
"$binary" --db "$db" --config "$config" -ApplePersistenceIgnoreState YES > /dev/null 2>&1 &
first=$!
for _ in $(seq 1 50); do
    [ -f "$db" ] && sqlite3 "$db" '.tables' 2>/dev/null | grep -q hosts && break
    sleep 0.2
done
kill "$first" 2>/dev/null
wait "$first" 2>/dev/null
sqlite3 "$db" '.tables' 2>/dev/null | grep -q hosts || fail "the app never made a store at $db"

# Every address is from RFC 5737 and RFC 3849's documentation ranges, so
# nothing here names a machine anybody owns. `osSeen` is stamped now on every
# host, the one with no `os` included: the stamp records the *asking*, so a
# host already asked today is not asked again — and `askHostsWhatTheyRun` is
# off below as well, because a second login to a documentation address is a
# connection that would sit there timing out behind the picture.
now=$(date +%s)
sqlite3 "$db" <<SQL || fail "could not seed the list"
INSERT INTO host_groups (id, name, parentId, user, identity, theme)
     VALUES ('g-prod', 'Production', '', 'deploy', '~/.ssh/id_ed25519', 'Gruvbox Dark');
INSERT INTO host_groups (id, name, parentId) VALUES ('g-eu', 'EU', 'g-prod');
INSERT INTO host_groups (id, name, parentId, proxyJump)
     VALUES ('g-us', 'US', 'g-prod', 'bastion');
INSERT INTO host_groups (id, name, parentId, user) VALUES ('g-stage', 'Staging', '', 'ubuntu');

INSERT INTO hosts (id, name, addr, groupId, os, osName, osSeen, tags) VALUES
  ('h-web',   'web-1',    '203.0.113.10', 'g-prod',  'debian',    'Debian GNU/Linux 12',  $now, '["web","live"]'),
  ('h-edge',  'edge-1',   '203.0.113.21', 'g-eu',    'alpine',    'Alpine Linux v3.20',   $now, '["edge","eu"]'),
  ('h-apieu', 'api-eu-1', '203.0.113.22', 'g-eu',    'ubuntu',    'Ubuntu 24.04.1 LTS',   $now, '["api","eu"]'),
  ('h-db',    'db-01',    '203.0.113.31', 'g-us',    'almalinux', 'AlmaLinux 9.4',        $now, '["db","us"]'),
  ('h-apius', 'api-us-1', '203.0.113.32', 'g-us',    'fedora',    'Fedora Linux 40',      $now, '["api","us"]'),
  ('h-stage', 'stage-1',  '198.51.100.11','g-stage', 'arch',      'Arch Linux',           $now, '["web"]'),
  ('h-bast',  'bastion',  '192.0.2.1',    '',        'openbsd',   'OpenBSD 7.5',          $now, '["jump"]'),
  ('h-nas',   'nas',      '192.0.2.7',    '',        'freebsd',   'FreeBSD 14.1',         $now, '["storage"]'),
  ('h-old',   'old-box',  '192.0.2.9',    '',        '',          '',                     $now, '[]');
SQL
say "seeded 4 groups and 9 hosts, eight marks and one host that never answered"

# Every preference an assertion or the picture leans on, pinned: the pane as a
# list, the inspector open, and nothing asking a documentation address what it
# runs. The whole domain is borrowed and given back, so this costs the user
# nothing.
defaults write com.shellhand.Shellhand libraryLayout -string list
defaults write com.shellhand.Shellhand hostInspector -bool true
defaults write com.shellhand.Shellhand askHostsWhatTheyRun -bool false

# --- the window ----------------------------------------------------------

# `XCTestSessionIdentifier` is `TestRun`'s switch, and it is here for one
# reason: a copy launched the ordinary way reads the real `~/.ssh/config` into
# the inspector, and a `Host *` block there would put somebody's own bastion or
# ProxyCommand into a public image. `--db` and `--config` still win, so the
# list above is the list.
XCTestSessionIdentifier=readme-picture \
    "$binary" --db "$db" --config "$config" -ApplePersistenceIgnoreState YES > /dev/null 2>&1 &
window_pid=$!
stop() {
    kill "$window_pid" 2>/dev/null
    wait "$window_pid" 2>/dev/null
    restore
}
if [ "$keep" -eq 0 ]; then trap stop EXIT; fi

for _ in $(seq 1 60); do
    n=$(osascript -e 'tell application "System Events" to tell process "Shellhand" to return (count of windows)' 2>/dev/null)
    [ "${n:-0}" -gt 0 ] && break
    sleep 0.25
done
[ "${n:-0}" -gt 0 ] || fail "the window never came up"

osascript -e 'tell application "Shellhand" to activate' > /dev/null 2>&1
sleep 1

# Sized before anything is arrowed, or it comes up at whatever frame this Mac
# last saved and the picture is a different window from the last one.
sized=$(osascript -e "tell application \"System Events\" to tell process \"Shellhand\"
    set position of window 1 to {80, 80}
    set size of window 1 to {$width, $height}
    delay 0.5
    set s to size of window 1
    return ((item 1 of s) as text) & \"x\" & ((item 2 of s) as text)
end tell" 2>&1)
say "the window is ${sized}pt, asked for ${width}x${height}"

# Every one of these addresses the window as `window 1`, never `front window`:
# System Events hands back a reference spelled `window "Hosts"`, and the moment
# a selection retitles the window — which picking a host does, the subtitle
# saying "db-01 · Production / US" — that reference stops resolving. Both of
# this script's first two failures were that, and the drive read as the window
# never coming up.
#
# db-01 is picked by arrowing and then *reading back which row is selected*,
# never by counting presses: the list's order is not this script's to know, and
# a walk that miscounts photographs the wrong host's inheritance. Focus the
# outline once — re-focusing before each press puts the selection back at the
# first row — then open the tree and step down until the selected row is the
# one wanted. Down is safe in the sidebar; it is the *pane* whose list leads
# with its groups, which is why the notes say to arrow up through that one.
read -r -d '' PICK <<'APPLESCRIPT'
script counter
	property n : 0
end script

on findOutline(el, depth)
	if depth > 14 then return missing value
	tell application "System Events"
		try
			if role of el is "AXOutline" then return el
		end try
		try
			repeat with child in UI elements of el
				set f to my findOutline(child, depth + 1)
				if f is not missing value then return f
			end repeat
		end try
	end tell
	return missing value
end findOutline

on findKind(el, depth, kind, nth)
	tell application "System Events"
		if depth > 18 then return missing value
		try
			if role of el is kind then
				set counter's n to (counter's n) + 1
				if (counter's n) is nth then return el
			end if
		end try
		try
			repeat with child in UI elements of el
				set f to my findKind(child, depth + 1, kind, nth)
				if f is not missing value then return f
			end repeat
		end try
	end tell
	return missing value
end findKind

on firstOfKind(kind)
	set counter's n to 0
	tell application "System Events" to tell process "Shellhand"
		return my findKind(window 1, 0, kind, 1)
	end tell
end firstOfKind

on textsIn(el, depth)
	set out to {}
	if depth > 6 then return out
	tell application "System Events"
		try
			if role of el is "AXStaticText" then
				set v to value of el
				if v is not missing value then
					if (v as text) is not "" then set end of out to (v as text)
				end if
			end if
		end try
		try
			repeat with child in UI elements of el
				set out to out & my textsIn(child, depth + 1)
			end repeat
		end try
	end tell
	return out
end textsIn

on selectedWords(side)
	set words_ to ""
	tell application "System Events"
		repeat with r in UI elements of side
			try
				if (selected of r) then
					repeat with x in my textsIn(r, 0)
						set words_ to words_ & (x as text) & " "
					end repeat
				end if
			end try
		end repeat
	end tell
	return words_
end selectedWords

tell application "System Events"
	tell process "Shellhand"
		-- The pane as a list, by pressing the switch rather than trusting the
		-- preference. `libraryLayout` is written before this copy launches and
		-- still came up as a grid, and a grid is a LazyVGrid: no AXOutline, no
		-- rows, nothing to read — which reads exactly like a pane with no list.
		set listButton to my firstOfKind("AXRadioButton")
		if listButton is not missing value then
			click listButton
			delay 0.6
		end if

		set side to my findOutline(window 1, 0)
		if side is missing value then return "NO-SIDEBAR"
		set focused of side to true
		delay 0.4
		-- Open every group: right opens, down steps. Focus once and then
		-- arrow; re-focusing before each press puts the selection back at the
		-- first row, which once made group rows look unreachable.
		repeat 7 times
			key code 124
			delay 0.15
			key code 125
			delay 0.15
		end repeat
		repeat 30 times
			key code 126
			delay 0.04
		end repeat
		-- Down until the row that is selected is the one wanted. Never by
		-- counting presses: the order is not this script's to know, and a
		-- miscount photographs the wrong host's inheritance. The outline is
		-- found again each pass because a reference System Events hands back
		-- is spelled through `window "Hosts"`, and picking a host retitles the
		-- window, so every reference taken beforehand stops resolving.
		set got to ""
		repeat 40 times
			try
				set got to my selectedWords(my findOutline(window 1, 0))
			end try
			if got contains "db-01" then exit repeat
			key code 125
			delay 0.12
		end repeat
		if got does not contain "db-01" then return "NOT-FOUND"

		-- And back to the whole list. A group picked in the sidebar is *gone
		-- to*, so walking down to db-01 left the pane inside US: two hosts and
		-- a screenful of nothing. The breadcrumb's All Hosts is a link, and
		-- where the pane looks is kept apart from what is selected, so this
		-- brings the list back with db-01 still the subject.
		set crumb to my firstOfKind("AXLink")
		if crumb is missing value then return "NO-CRUMB"
		click crumb
		delay 1.0
		return "PICKED " & got
	end tell
end tell
APPLESCRIPT

picked=$(osascript -e "$PICK" 2>&1)
case "$picked" in
    PICKED*) say "the sidebar has ${picked#PICKED }selected" ;;
    *) fail "could not select db-01 in the sidebar: $picked" ;;
esac
sleep 1

# --- the photograph ------------------------------------------------------

# `-l` photographs one window alone — the window and nothing over it,
# transparent corners and all — but only given a CoreGraphics window number.
# A window id from System Events is not one; this reads kCGWindowNumber out of
# CGWindowListCopyWindowInfo, filtered to this process and layer 0.
cat > "$scratch/window-id.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let wanted = pid_t(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []
for window in info {
    guard window[kCGWindowOwnerPID as String] as? pid_t == wanted,
          window[kCGWindowLayer as String] as? Int == 0,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, width > 400
    else { continue }
    print(number)
    exit(0)
}
exit(1)
SWIFT
id=$(DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} \
    xcrun swift "$scratch/window-id.swift" "$window_pid" 2>/dev/null)
[ -n "$id" ] || fail "no on-screen window of this copy at layer 0 — nothing to photograph"

# -R takes the screen at a rectangle, so whoever is frontmost ends up in the
# picture. -l takes the window, but the capture still wants this app in front:
# check immediately before and after, and throw the picture away if it was not.
front_before=$(osascript -e 'tell application "System Events" to return (name of first application process whose frontmost is true)' 2>/dev/null)
mkdir -p "$(dirname "$out")"
screencapture -x -o -l "$id" "$scratch/shot.png" || fail "screencapture refused window $id"
front_after=$(osascript -e 'tell application "System Events" to return (name of first application process whose frontmost is true)' 2>/dev/null)
if [ "$front_before" != "Shellhand" ] || [ "$front_after" != "Shellhand" ]; then
    fail "Shellhand was not frontmost through the capture (before: ${front_before:-none},
       after: ${front_after:-none}); the picture is thrown away"
fi
[ -s "$scratch/shot.png" ] || fail "screencapture wrote nothing"

size=$(/usr/bin/python3 -I -c '
import struct, sys
raw = open(sys.argv[1], "rb").read(33)
w, h = struct.unpack(">II", raw[16:24])
print(f"{w}x{h}")' "$scratch/shot.png")
cp "$scratch/shot.png" "$out"
say "wrote $out at $size pixels ($(du -h "$out" | cut -f1))"
say "now remake the site's images: swift tools/site-images.swift"
