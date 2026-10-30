# Contributing

Shellhand is small and kept by one person, so a clear report is the most
useful thing to send. Code is welcome too; this says how to send it so that it
lands.

## Before you write anything

- **A problem**: Help ▸ Report a Problem… in the app opens
  [the issue form](https://github.com/cuonggt/shellhand/issues/new/choose) with
  your version filled in. Issues are public, so leave out host names,
  addresses and keys.
- **A security problem**: never an issue. [SECURITY.md](SECURITY.md) says
  where it goes.
- **A question or an idea**:
  [Discussions](https://github.com/cuonggt/shellhand/discussions).
- **A feature**: start a Discussion before you write it. Shellhand was cut back
  to an MVP on purpose — key management, credentials, snippets and port
  forwarding were all built and taken out again — and what comes back is
  decided by people asking for it. A pull request for a feature nobody has
  talked about may be closed however good it is, which would waste your
  afternoon.

A fix for a bug that has an issue needs no asking first.

## Building

macOS 26 or later, Xcode 26 or later, Swift 6 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.40 or later. The Xcode
project is generated from `project.yml` and committed: run `xcodegen generate`
after adding or removing a file or editing `project.yml`, and commit what it
writes along with your change.

`project.yml` signs with the project's own Developer ID, which you will not
have, so sign ad hoc instead:

```bash
xcodebuild build -project Shellhand.xcodeproj -scheme Shellhand \
  -configuration Debug -destination "platform=macOS" \
  -derivedDataPath build -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
```

`-skipPackagePluginValidation` is there because SwiftTerm carries a build
plugin that Xcode otherwise asks a human to trust.

## Testing

```bash
xcodebuild test -project Shellhand.xcodeproj -scheme Shellhand \
  -configuration Debug -destination "platform=macOS" \
  -derivedDataPath build -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
```

That is what [the Tests workflow](workflows/tests.yml) runs on GitHub's macOS
runner for every pull request that touches the code, and it has to pass there.
Worth knowing before you run it:

- Every test is swift-testing, so xcodebuild's own *"Executed 0 tests"* line
  says nothing either way. Ask the result bundle instead:
  `xcrun xcresulttool get test-results summary --path <bundle>`.
- The suite reaches nothing outside your Mac and stays off your own `~/.ssh`:
  `ssh` is tested against macOS's own `sshd` on `127.0.0.1`, and SFTP against
  OpenSSH's `sftp-server`.
- Quit any copy of Shellhand you launched from `build/` first, or the test host
  may not start. A copy in `/Applications` can stay open.
- `scripts/window-check.sh` is the one check that drives a real window, through
  System Events, against a host list of its own. It uses the app you built into
  `build/`, refuses to run beside any other copy, `/Applications` included, and
  macOS asks once to let your terminal control the computer.

A change that adds behaviour adds a test for it. The rules that decide what the
app does live outside the views, in types that keep no state —
`Views/Panes.swift`, `Views/QuickConnect.swift`, `Core/Validation.swift` and
their neighbours — so that each is a test with a couple of values rather than
a window to drive. Put a new rule there too.

## The notes

[CLAUDE.md](../CLAUDE.md) holds every convention and every trap found the hard
way, a rule at a time, and [docs/notes/](../docs/notes) the story behind each.
Read the rule about the part you are changing before you change it: most of
them exist because the obvious version was tried first.

## Sending it

- One change per pull request, with its tests, on top of the latest `main`.
- Commit messages are one line, saying what the change does.
- Shellhand is licensed under the GNU GPL, version 3 or later, and so is what
  you contribute. There is no agreement to sign, and your copyright stays
  yours.
