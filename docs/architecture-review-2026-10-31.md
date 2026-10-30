# Architecture review, 2026-10-31 (end of M7, 32 stories done)

Survey: hottest files are SelfTest (18 commits), ContentView and AppModel (13 each). Largest: ContentView 434, AppModel 430, Recorder 337 lines. No drifted private structs. Fix log: two of six entries are SwiftData lookups on `selection`; two are camera visibility.

## Session clock as a plain value  [Strong]  — done in this check-in
Files: Sources/OpticalFlow/AppModel.swift (Session section, 140 lines)
Signal: pure logic inside a @MainActor store; the same area in three stories (S-005, S-006, S-015) and one subtle bug (break rounding).
Problem: elapsed, pause, resume, overflow, and idle banking were spread over `paused`, `resumedAt`, and `session.seconds`, testable only through the in-app self-test.
Proposal: `SessionClock { planned, banked, resumedAt; elapsed(at:), pause(at:), resume(at:), stop(at:) }` in the Kit.
Proof: the self-test's S-005/S-006/S-014/S-015 checks before and after (83 both), plus a unit test for the clock.

## Task views out of ContentView  [Worth exploring]  — done 2026-10-31
Files: ContentView.swift (434 lines: Sidebar, TaskList, TaskRow, TaskDetail, SessionList, RecordingOptionsMenu).
Signal: file over 400 lines, touched by 13 commits.
Proposal: `TaskViews.swift` (TaskList, TaskRow, TaskDetail) and `SessionViews.swift`; ContentView keeps the split view and toolbar. Pure move.
Plan: one commit per file.

## Recorder split: capture vs. cursor/display following  [Worth exploring]
Files: Recorder.swift (337 lines).
Problem: the pointer tracker and display follower live inside the ScreenCaptureKit wrapper; both grow with M7 ideas (click zoom, idle zoom-out).
Proposal: `PointerTracker` (samples, capturedRect, onLeaveDisplay) owned by Recorder.

## Export options as one value  [Speculative]
`trim(_:start:end:withCamera:followCursor:youtube:)` has three Bools; a fourth (click zoom) would tip it. Proposal: `ExportOptions` struct passed through to `Exporter`.

## Considered, not recommended
- Replacing the URL scheme with App Intents: needs an XcodeGen project; only when Shortcuts parameters are wanted.
- A protocol in front of Recorder for tests: the self-test exercises it through synthesized files already; one conformer would be a hypothetical seam.

Top recommendation: the session clock (done). Next: split ContentView when the next task story lands.
