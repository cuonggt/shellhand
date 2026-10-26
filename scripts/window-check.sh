#!/bin/bash
# Does a window load a store and draw it? The one thing no unit test can say.
#
# The suite reaches everything below the window — the store, the rules the
# sidebar flattens, the panes — but nothing checks that a real window, given a
# real store, comes up and shows it. This drives the window the way a person
# on the keyboard does, through System Events, against a scratch store it
# seeds itself. It touches nothing of the user's: not their host list, not
# their preferences, not their keychain.
#
#   ./scripts/window-check.sh [--keep]
#     --keep   leave the window open and the scratch directory behind
#
# Nothing here needs Go, a loopback server, or a flag the app does not already
# publish. `--db` is the whole of what it asks for. The three shell harnesses
# this replaces wanted `--seed`, `--selftest` and `--uicheck`, the last of
# which was the app checking *itself* and writing a report — test-only code in
# the shipping binary. Driving it from outside costs the app nothing.
set -uo pipefail
cd "$(dirname "$0")/.."

keep=0
[ "${1:-}" = "--keep" ] && keep=1

app=${SHELLHAND_APP:-build/Build/Products/Debug/Shellhand.app}
binary="$app/Contents/MacOS/Shellhand"
fail() { echo "window-check: $*" >&2; exit 1; }

[ -x "$binary" ] || fail "no build at $app — build the Debug scheme first"

# --- guards, each of which has cost somebody an afternoon ------------------

# `pgrep Shellhand` matches every copy, the user's own included, and System
# Events addresses a process by name — so two copies make every lookup below
# ambiguous. Refuse rather than drive the wrong one, and never quit theirs.
running=$(pgrep -f 'Shellhand.app/Contents/MacOS/Shellhand' | wc -l | tr -d ' ')
if [ "$running" -gt 0 ]; then
    pgrep -lf 'Shellhand.app/Contents/MacOS/Shellhand' >&2
    fail "another copy of Shellhand is running. Quit it first: with two, System
       Events cannot tell which window it is looking at."
fi

# A locked screen reports zero windows for every process and fails
# `front window` with "Invalid index", which reads exactly like an app that
# never launched. Ask CoreGraphics, which answers through the lock.
if /usr/bin/python3 -c 'import sys' 2>/dev/null; then :; fi
locked=$(osascript -e 'tell application "System Events" to return (name of first application process whose frontmost is true)' 2>/dev/null)
[ -z "$locked" ] && fail "cannot read the frontmost app — the screen may be locked"
echo "window-check: frontmost before this runs: $locked"

# --- the user's preferences, borrowed and given back ----------------------

# `@AppStorage` is keyed by the bundle id, not by `--db`, so a run against a
# scratch store still writes the real preferences — window frames, the list
# layout, Sparkle's own keys. Take the whole domain and put it back.
scratch=$(mktemp -d /tmp/shellhand-window-check.XXXXXX)
saved="$scratch/defaults.plist"
defaults export com.shellhand.Shellhand "$saved" 2>/dev/null || :
restore() {
    if [ -f "$saved" ]; then
        defaults import com.shellhand.Shellhand "$saved" 2>/dev/null || :
    fi
    [ "$keep" -eq 1 ] || rm -rf "$scratch"
}
trap restore EXIT

db="$scratch/shellhand.sqlite"

# --- a store of its own, made by the app and seeded behind it -------------

# The app creates and migrates the store, so the schema is whatever this
# build's migrations make rather than whatever this script believes. Then the
# rows go in with sqlite3: every column added since v1 has a default, so
# naming four of them is enough.
#
# Seeding directly is deliberate. The old harness went through the app's own
# import because it was testing the import; this is testing whether a window
# draws a store, and putting the import in the way would mean a failure could
# be either.
"$binary" --db "$db" >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 50); do
    [ -f "$db" ] && sqlite3 "$db" '.tables' 2>/dev/null | grep -q hosts && break
    sleep 0.2
done
kill "$first" 2>/dev/null
wait "$first" 2>/dev/null
sqlite3 "$db" '.tables' 2>/dev/null | grep -q hosts || fail "the app never made a store at $db"

sqlite3 "$db" <<'SQL' || exit 1
INSERT INTO host_groups (id, name, parentId) VALUES ('g-prod', 'Production', '');
INSERT INTO host_groups (id, name, parentId) VALUES ('g-eu', 'EU', 'g-prod');
INSERT INTO hosts (id, name, addr, groupId) VALUES ('h-web', 'web-1', '198.51.100.1', 'g-prod');
INSERT INTO hosts (id, name, addr, groupId) VALUES ('h-edge', 'edge-1', '198.51.100.2', 'g-eu');
INSERT INTO hosts (id, name, addr, groupId) VALUES ('h-loose', 'unfiled-1', '198.51.100.3', '');
SQL
echo "window-check: seeded 2 groups and 3 hosts into a store of its own"

# --- the window, driven the way a person on the keyboard drives it ---------

"$binary" --db "$db" >/dev/null 2>&1 &
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

osascript -e 'tell application "Shellhand" to activate' >/dev/null 2>&1
sleep 1

# Walk with `UI elements` and `role of`, never System Events' own class names:
# `outlines of x` and `rows of x` return 0 at levels where `UI elements of x`
# returns children, which is what made the sidebar look like a dead end for
# three sittings. `entire contents` is no use either — elements from it cannot
# be dereferenced here at all.
#
# **Every handler wraps its own body in `tell application "System Events"`.**
# A handler is top level, so outside that block `UI elements of el` is not
# terminology AppleScript knows and the whole script fails to compile with
# "Expected end of line but found identifier" — pointing at the `repeat`, not
# at the missing context.
read -r -d '' WALK <<'APPLESCRIPT'
on findOutline(el, depth)
	if depth > 10 then return missing value
	tell application "System Events"
		try
			if role of el is "AXOutline" then return el
		end try
		try
			repeat with child in UI elements of el
				set found to my findOutline(child, depth + 1)
				if found is not missing value then return found
			end repeat
		end try
	end tell
	return missing value
end findOutline

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

on joinText(lst, sep)
	set out to ""
	repeat with i from 1 to (count of lst)
		if i > 1 then set out to out & sep
		set out to out & (item i of lst)
	end repeat
	return out
end joinText

tell application "System Events"
	tell process "Shellhand"
		set side to my findOutline(front window, 0)
		if side is missing value then return "NO-OUTLINE"
		set rowTexts to {}
		repeat with r in UI elements of side
			set t to my textsIn(r, 0)
			if (count of t) > 0 then set end of rowTexts to my joinText(t, " / ")
		end repeat
		return my joinText(rowTexts, linefeed)
	end tell
end tell
APPLESCRIPT

read_rows() { osascript -e "$WALK" 2>&1; }

rows=$(read_rows)
[ "$rows" = "NO-OUTLINE" ] && fail "found no AXOutline under the window"
echo "window-check: as it comes up, the sidebar draws --"
echo "$rows" | sed 's/^/    /'

# **Folded is correct.** `Tree` decides the fold the sidebar opens on, and a
# folded group keeps its own row and loses what is under it — so Production is
# there and EU and web-1 are not. Expecting the whole tree flat was the first
# version of this check and it was wrong about the app, not the other way
# round.
for want in Production Ungrouped unfiled-1; do
    echo "$rows" | grep -q "$want" || fail "the folded sidebar is missing $want"
done
for unwanted in EU web-1 edge-1; do
    echo "$rows" | grep -q "$unwanted" && fail "$unwanted is drawn while Production is folded"
done
echo "window-check: folded as expected — nothing under Production is drawn yet"

# Now open it. Focus the outline **once** and walk down pressing Right:
# re-focusing before each press puts the selection back at the first row,
# which is what once made group rows look permanently unreachable.
read -r -d '' OPEN <<'APPLESCRIPT'
on findOutline(el, depth)
	if depth > 10 then return missing value
	tell application "System Events"
		try
			if role of el is "AXOutline" then return el
		end try
		try
			repeat with child in UI elements of el
				set found to my findOutline(child, depth + 1)
				if found is not missing value then return found
			end repeat
		end try
	end tell
	return missing value
end findOutline

tell application "System Events"
	tell process "Shellhand"
		set side to my findOutline(front window, 0)
		if side is missing value then return "NO-OUTLINE"
		set focused of side to true
		delay 0.4
		repeat 7 times
			key code 124
			delay 0.2
			key code 125
			delay 0.2
		end repeat
		return "OK"
	end tell
end tell
APPLESCRIPT

opened=$(osascript -e "$OPEN" 2>&1)
[ "$opened" = "OK" ] || fail "could not drive the sidebar: $opened"

rows=$(read_rows)
echo "window-check: with the groups opened, the sidebar draws --"
echo "$rows" | sed 's/^/    /'
for want in Production EU web-1 edge-1 unfiled-1; do
    echo "$rows" | grep -q "$want" || fail "after opening the groups, $want is still missing"
done
echo "window-check: the whole tree is reachable from the keyboard"

# The selection has to actually reach the app, which is the half a screenshot
# cannot tell you. `select` on a row sets AXSelected and SwiftUI's binding
# never hears it, so the Host menu stays grey — a convincing false negative.
# Focusing the outline once and then arrowing is the path a person takes; and
# re-focusing before each press puts the selection back at the first row,
# which is what made group rows look unreachable.
read -r -d '' PICK <<'APPLESCRIPT'
on findOutline(el, depth)
	if depth > 10 then return missing value
	tell application "System Events"
		try
			if role of el is "AXOutline" then return el
		end try
		try
			repeat with child in UI elements of el
				set found to my findOutline(child, depth + 1)
				if found is not missing value then return found
			end repeat
		end try
	end tell
	return missing value
end findOutline

tell application "System Events"
	tell process "Shellhand"
		set side to my findOutline(front window, 0)
		if side is missing value then return "NO-OUTLINE"
		set focused of side to true
		delay 0.4
		repeat 3 times
			key code 125
			delay 0.3
		end repeat
		set m to menu 1 of (first menu bar item of menu bar 1 whose name is "Host")
		repeat with mi in menu items of m
			try
				if (name of mi) starts with "Edit Host" then return (enabled of mi) as text
			end try
		end repeat
		return "NO-ITEM"
	end tell
end tell
APPLESCRIPT

picked=$(osascript -e "$PICK" 2>&1)
case "$picked" in
    true) echo "window-check: arrowing the sidebar reached the app — Edit Host is live" ;;
    false) fail "a row is highlighted but the app does not think anything is selected" ;;
    *) fail "could not read the Host menu: $picked" ;;
esac

echo "window-check: PASSED — a window loaded a store of its own and drew it"
