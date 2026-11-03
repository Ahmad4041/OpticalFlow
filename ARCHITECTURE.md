# OpticalFlow architecture

Two targets, one direction of dependency: `OpticalFlow` (app) depends on `OpticalFlowKit` (rules). Nothing in the Kit imports SwiftUI, SwiftData, or AppKit.

## OpticalFlowKit (plain values, unit tested)
- `TaskTitle`, `SmartList`, `DayGroup`, `DueDateParser`: task rules.
- `SessionClock`, `Countdown`, `SessionStats`: time rules and labels.
- `ChapterList`, `CameraLayout`, `CursorTrack`, `SilenceCut`: export rules.

## OpticalFlow (main actor by default)
- `App.swift`: scenes (window, menu bar extra, settings), menus, `AppDelegate` (notifications, quit while recording), `Store`.
- `AppModel`: the one observable store. Tasks and projects, the session (owns a `SessionClock`, a 1 s ticker, idle and break state), export entry points, URL commands. Owns `Recorder`, `QuickEntry`, `MiniTimer`.
- `Recorder`: ScreenCaptureKit stream + `SCRecordingOutput`, `CameraRecorder` (sidecar + `CameraBubble`), pointer tracking, display following. Callbacks `onStart`/`onStop` create and finish `Recording` rows.
- `Exporter` + `StudioCompositor`: trim, camera overlay, blur, follow-cursor zoom, YouTube preset. `nonisolated`, runs on AVFoundation's queues.
- `VoiceAgent`: the orchestrator choice, `AgentJob`, speech recognition, the agent runner (`claude -p` or `codex exec` as a `Process`), and the floating panel. `VoiceViews`: the panel's SwiftUI, the toolbar activity button, the jobs list, the microphone picker. `Handoff`: git worktrees and the brief.
- Views: `ContentView` (split view, sidebar, toolbar), `TaskViews`, `SessionViews`, `RecordingViews`, `BoardView`, `MenuBarPanel`, `MiniTimer`, `QuickEntry`, `SettingsView`.
- Agent hooks: `SeedData`, `SelfTest`, `Snapshot`, all gated on `APP_STORE` in /tmp.

## Seams
- `Store.url` (APP_STORE) swaps the database.
- `Recorder.directory` swaps the movie folder under test.
- `AppModel.idleOverride` swaps the idle source.
- `Exporter.export(...)` and `Exporter.levels(of:)` take URLs and values only, so the self-test feeds them synthesized clips (silent, or with a tone and a pause).
- `Orchestrator.environment(from:)` takes the base environment, so the self-test checks what an agent inherits without starting one.

## Rules that came from bugs (docs/FIXLOG.md)
- Resolve `selection` only through `AppModel.selected(_:)`.
- Take a start lock before the first `await` in any once-only async start.
- Launch the app for checks through `open`, never by exec'ing the binary.
- Keep an `AVAsset` alive while any of its tracks is in use.
