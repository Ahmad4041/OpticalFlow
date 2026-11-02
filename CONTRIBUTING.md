# Contributing to OpticalFlow

Thanks for helping. This page is the whole workflow. If something here is wrong, fixing it is a welcome first pull request.

## Before you start

- You need macOS 26 and Xcode 26. Open the folder in any editor; there is no Xcode project, it is a Swift package.
- Check [docs/STORIES.md](docs/STORIES.md). Most work is a story there. If yours is not, open an issue first so we agree on the behavior before you build it.
- Bugs: open an issue with the steps, what you expected, and the crash report from Console if there is one. Attach the output of `opticalflow status --json`.

## The rules the code follows

Short version of [CLAUDE.md](CLAUDE.md), which is the file the maintainers and their agents work from:

- **Native only.** Apple's controls and system styles. The only custom color is the accent. No fixed grays, no hard-coded radii or durations in views. Spacing comes from `Space` in `Sources/OpticalFlow/UI/Grid.swift`, on a 4 pt grid.
- **Logic goes in the Kit.** Anything that can be a plain function with plain values lives in `Sources/OpticalFlowKit/` with a unit test. The app target is main-actor and holds views and I/O.
- **Every action has a menu item and a shortcut.** `Label` for icon and text, SF Symbols for icons, `ContentUnavailableView` for empty states.
- **Settings:** one tab per topic, one grouped Form per tab.
- **SwiftData changes:** new attributes are optional or have a default, or the store will not open for existing users. Relationships declare their inverse on both sides.
- **Never touch the real database** in `~/Library/Application Support/OpticalFlow/`. Tests, seed data and snapshots refuse to run unless `APP_STORE` points into `/tmp`.

## Workflow

1. Fork and branch from `main`.
2. Build with `./build.sh`. It stages the bundle and installs it only when the app is not running. `./build.sh --open` quits and relaunches. Fix every warning the build prints.
3. Make the change. One story or one fix per pull request.
4. Run the checks in [TESTING.md](TESTING.md). A change is done when the build has no errors, unit tests and the self-test pass, the grid checks print PASS, and you looked at the light and dark snapshots of every page you touched.
5. If you added a feature with logic, add a self-test check in `Sources/OpticalFlow/SelfTest.swift` and a unit test if the logic is in the Kit. If you added a story, mark its status in `docs/STORIES.md`.
6. If you fixed a bug, add an entry to [docs/FIXLOG.md](docs/FIXLOG.md): date, symptom, cause, fix, and a one-line `Rule:` so it does not come back.
7. Commit with a message that says what the user can now do, not what you changed in the code. Example: `Deadline apart from the planned day, and repeat rules that move a task forward on completion`.
8. Open the pull request with the template filled in. CI builds the package and runs the unit tests. The self-test and snapshots need a desktop session, so run them locally and paste the last lines.

## What is not accepted

- A new dependency when a few lines of Swift do the job.
- Custom chrome: title bars, toolbars, sidebars, sheets and menus stay system.
- Anything that sends data off the Mac without the user choosing it.
- Screenshots or code copied from other apps. References come from Apple's documentation and public writing.

## Review

A maintainer reviews within a week. Expect questions about the story, the tests and the snapshots. Small pull requests merge fast.
