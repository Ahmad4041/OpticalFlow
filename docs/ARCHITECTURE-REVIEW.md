# Architecture check-in after M2 (2026-10-29)

## Done now (Strong)
- AppModel moved out of Models.swift into AppModel.swift. Pure move, behavior unchanged (self-test 41/41).

## Left for the user
- AppModel (≈300 lines) holds tasks, sessions, projects, and export. If M3 adds idle detection and breaks, pull the session clock into a `SessionClock` type with its own self-test. Medium.
- ContentView.swift (320 lines) holds the sidebar, task list, and task detail. Split `TaskViews.swift` when M4 adds search and the quick-entry panel. Medium.
- Recorder.start builds the stream config inline. A `RecordingPreset` (width cap, fps, codec) would make a 4K/60 setting a one-line change. Weak until asked.
- Undo replaces the Edit menu's Undo item and only knows task completion; text fields lose Command-Z while the window has focus on a list. Fix: register completion with the window's UndoManager instead. Medium, M6.
