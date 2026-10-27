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
# never launched.
#
# This guard used to ask System Events for the frontmost app and fail only if
# the answer came back empty — while its comment claimed it asked
# CoreGraphics. It never fired: behind a lock the app that *was* frontmost
# goes on being reported as frontmost (measured, with `loginwindow` at layer
# 2004 over everything and another app still named). So the run went through
# the guard and died further down, on the zero windows, reading as a launch
# that failed. A comment is evidence of what somebody intended, never of what
# the code does.
#
# The window server's own session dictionary is the thing that answers through
# the lock: `CGSSessionScreenIsLocked` is present and true while locked and
# absent otherwise.
locked=$(/usr/bin/python3 - <<'LOCKED'
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
       reports no windows for any process, so this check cannot see the window
       it drives — and the failure would read as the app never launching."
frontmost=$(osascript -e 'tell application "System Events" to return (name of first application process whose frontmost is true)' 2>/dev/null)
echo "window-check: locked: $locked; frontmost: ${frontmost:-unknown}"

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

# The pane draws rows or cards, and only the rows are a `List` with a
# selection of its own — a `LazyVGrid` has none, so grid mode has buttons and
# no `AXOutline` at all. This machine's preference happens to be `grid`, which
# is exactly how the pane-list assertion below first failed against a build
# that was perfectly correct. The whole domain is already borrowed and given
# back, so choosing here costs the user nothing.
defaults write com.shellhand.Shellhand libraryLayout -string list
# And the inspector, for the same reason and the same trap twice in one day:
# `hostInspector` is a preference like any other, so a user who shut the
# inspector hands this check a window with no inspector in it and the
# assertion below fails against a build that is perfectly correct. Pin every
# preference the assertions depend on, not just the one that bit first.
defaults write com.shellhand.Shellhand hostInspector -bool true

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

# --- the pane and the inspector -------------------------------------------

# The pane keeps the host list and the **inspector** says what a host is —
# before that, selecting a host replaced the pane with its details. Two things
# make this checkable from outside, and the first is the discriminator: the
# pane now holds an `AXOutline` of its own, where it used to be a scroll area
# full of `AXButton`s. So a window with fewer than two outlines in it is the
# old layout, and this section cannot pass against it.
#
# `findNthOutline` counts through a **property** rather than threading a
# counter, because a handler here may return a single element reference —
# `findOutline` above does — but a **list** of them does not survive the
# return. That cost an afternoon to learn the other way round.
read -r -d '' PANE <<'APPLESCRIPT'
property seen : 0

on findNthOutline(el, depth, want)
	if depth > 12 then return missing value
	tell application "System Events"
		try
			if role of el is "AXOutline" then
				set seen to seen + 1
				if seen is want then return el
			end if
		end try
		try
			repeat with child in UI elements of el
				set found to my findNthOutline(child, depth + 1, want)
				if found is not missing value then return found
			end repeat
		end try
	end tell
	return missing value
end findNthOutline

on textsIn(el, depth)
	set out to {}
	-- Deep enough to reach "What will run", which sits below the facts grid.
	-- At 8 the dump stopped at "Jump host" and the assertion below failed
	-- against an inspector that was in fact drawing everything.
	if depth > 16 then return out
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
		set seen to 0
		set pane to my findNthOutline(front window, 0, 2)
		if pane is missing value then return "NO-PANE-LIST"
		set rowCount to count of UI elements of pane
		set focused of pane to true
		delay 0.4
		repeat 2 times
			key code 125
			delay 0.4
		end repeat
		delay 0.8
		set said to my joinText(my textsIn(front window, 0), " | ")
		return (rowCount as text) & linefeed & said
	end tell
end tell
APPLESCRIPT

paned=$(osascript -e "$PANE" 2>&1)
case "$paned" in
    NO-PANE-LIST*)
        fail "the pane has no list of its own — it is drawing host details, not the hosts" ;;
esac
pane_rows=$(printf '%s' "$paned" | head -1)
pane_said=$(printf '%s' "$paned" | tail -n +2)
[ "$pane_rows" -gt 0 ] 2>/dev/null || fail "the pane has a list with no rows in it: $pane_rows"
echo "window-check: the pane holds a list of its own, $pane_rows rows"

# "What will run" is drawn by `HostDetailView` and by nothing else, so seeing
# it proves both halves at once: the inspector is open — it comes up open now,
# since the details have nowhere else to be — and it is describing a host
# rather than sitting on "Nothing selected".
printf '%s' "$pane_said" | grep -q "What will run" \
    || fail "the inspector is not describing a host: $pane_said"
echo "window-check: the inspector is open and describing the host selected"

echo "window-check: PASSED — a window loaded a store of its own and drew it"
