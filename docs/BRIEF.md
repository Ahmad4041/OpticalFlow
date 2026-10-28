# OpticalFlow

A native Mac app where a developer picks a task, runs a timed focus session on it, records the screen while working, and exports the recording with YouTube chapters made from the tasks they finished. For developers, vibe coders, and streamers.

Bundle id: com.ahmadnaeem.opticalflow. Folder: this one (OpticalFlowProductivity). Decided by the agent from docs/research/.

## Replaces
Things 3 + Session + Cap used side by side, and the habit of pasting timestamps into a YouTube description by hand.

## Main jobs
1. Capture and finish tasks: Inbox, Today, Upcoming, Someday, projects, keyboard-first.
2. Run a focus session on a task from the menu bar: countdown, pause, stop, overflow, session log.
3. Record the session (screen, system audio, mic, camera) and export an MP4 with a chapter list from completed tasks.

## Data
- Project: name, color, created
- Task: title, notes, due, completed at, someday flag, project, order
- Session: task, planned minutes, started, ended, notes
- Recording: session, file URL, started, duration, chapters (title + offset), camera file URL

## Shape
Sidebar window (Inbox, Today, Upcoming, Someday, Sessions, Recordings, projects) plus a menu bar extra with the live countdown and Start/Pause/Stop. macOS 26 or later. Local data. Works offline. No accounts.

## System hooks
Menu bar extra; global hotkey to start/stop a session (Carbon RegisterEventHotKey); ScreenCaptureKit picker and SCRecordingOutput; AVCaptureSession camera sidecar; UserNotifications for session end.

## Reference
None opened. Patterns from Things 3 (lists, shortcuts), Session (menu bar timer, overflow), Cap (record flow, trim). See docs/research/.

## Look
Native with the Mac's system accent. Decided by the agent: nothing in the research rewards a custom look, and reliability is the market's open wound.

## Not in version one
- Share links, cloud, AI chapters, transcripts, sync between Macs (later: iCloud)
- Auto-zoom, cursor smoothing, background padding, 9:16 presets
- App blocking, Apple Focus integration, habits, stats dashboards
- Collaboration, attachments, tags, repeat rules, nested subtasks
