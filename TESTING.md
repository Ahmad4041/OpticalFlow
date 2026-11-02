# Testing OpticalFlow

Four layers, fastest first. All of them run against stores in `/tmp`; the app refuses to seed, snapshot or self-test anywhere else, so your own data is safe.

## 1. Unit tests (seconds)

The Kit has no UI, so its rules are plain functions with plain tests: dates and times in sentences, deadlines, repeat rules, priorities, voice intents, checklists, chapter rules, edit distance.

```sh
swift test --scratch-path ~/Library/Developer/OpticalFlow/test-build
```

Add a test in `Tests/OpticalFlowKitTests/KitTests.swift` for every rule you add to `Sources/OpticalFlowKit/`.

## 2. Self-test (about a minute)

The app launches with `--selftest` on a fresh store, runs its real functions (add, move, complete, sessions, breaks, recording export with synthesized clips, voice intents, the worktree lifecycle on a throwaway repo) and prints one line per check.

```sh
./build.sh          # stage the bundle first
tools/selftest.sh   # exit 0 when every check passes
```

The log is in `/tmp/OpticalFlow-self.log`. Each story with logic has a check in `Sources/OpticalFlow/SelfTest.swift`; add one for yours, named after the story (`S-049 …`).

## 3. Snapshots and grid (about a minute)

Every sidebar page and Settings tab is captured in light and dark with seed data, then the layout is checked against the 4 pt grid.

```sh
tools/snap.sh
tools/grid-lint.sh
swift tools/check-layout.swift /tmp/OpticalFlow-shots/*-layout.json
```

Pictures land in `/tmp/OpticalFlow-shots/<page>-light.png` and `-dark.png`. Open them. A layout check that passes is not the same as a screen that looks right. Limit the run with `APP_SNAPSHOT_PAGES=all,settings tools/snap.sh`, or compare accents with `APP_ACCENT=<id>`.

For a panel, sheet or popover, add a capture to `Sources/OpticalFlow/Snapshot.swift` like the Settings loop.

## 4. By hand

Things no script can check: permissions prompts, the system picker, the Touch Bar, a real microphone, an agent run. Use a test instance so you never touch your own data:

```sh
app=~/Library/Developer/OpticalFlow/build/staged/OpticalFlow.app
open -n --env APP_STORE=/tmp/of-test.store --env APP_SEED=1 --env APP_AGENT_SOCKET=/tmp/of-test.sock "$app"
APP_AGENT_SOCKET=/tmp/of-test.sock "$app/Contents/MacOS/OpticalFlow" status --json
```

Use the staged binary as the CLI, as above. The `opticalflow` on your PATH points at the installed app.

### Touch Bar

`screencapture -b touchbar.png` photographs the real Touch Bar. Bring a test instance to the front for OpticalFlow's own bar. For the Control Strip item, add `--env APP_STRIP=1` to the test launch (test instances skip the strip otherwise, so they never replace yours), then activate another app and capture.

## CI

GitHub Actions builds the package and runs the unit tests on a macOS 26 runner. The self-test and snapshots need a logged-in desktop with ScreenCaptureKit, so they run locally; paste their last lines into the pull request.

## When something fails

- The build says the binary is older than a source file: a previous build was killed. Remove `~/Library/Developer/OpticalFlow/build/release` and `build.db`, then build again.
- The self-test or snapshot run hangs with no output: a crashed run left saved window state. The scripts clear it; if it still hangs, `pkill -f staged/OpticalFlow.app` and retry.
- The installed app quits silently while you build: a build replaced a running app's signed binary. `build.sh` now stages first and refuses to install over a running copy; use `./build.sh --open`.
- Every bug that gets fixed gets a line in [docs/FIXLOG.md](docs/FIXLOG.md) ending in `Rule:`.
