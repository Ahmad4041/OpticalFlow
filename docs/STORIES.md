# OpticalFlow stories

Built from docs/BRIEF.md and docs/research/. No reference app; Screens: name the snapshot pages that show the story.

## M1 Core loop: task -> session -> recording -> chapters

### S-001 Add a task from the list
As the user, I press Command-N (or click +) on any list, type a title, and press Return to add a task to that list.
Screens: inbox, today
Acceptance:
- [snap] Inbox shows the new task row at the bottom with an empty checkbox.
- [self] A task added on Today has due = today; on Inbox has no project and no due; on Someday has someday = true.
- [unit] An empty or whitespace title is rejected.
- [self] The task is still there after the app restarts.
UX: Inline editor row at the end of the list, focused on open. Escape cancels. The field placeholder is "New task". No sheet.
Status: done

### S-002 Complete a task with the keyboard
As the user, I select a task and press Command-K (or click its checkbox) to complete it, and Command-Z brings it back.
Screens: today
Depends: S-001
Acceptance:
- [snap] The checkbox fills; the row dims and stays until the list is left or 2 s pass.
- [self] Completed at is set; Command-Z clears it.
- [unit] Completing an already done task is a no-op.
UX: Menu item Task > Complete, Command-K. Undo via the Edit menu's standard Undo. No "Undo" banner.
Status: done

### S-003 Sidebar with smart lists and projects
As the user, I move between Inbox, Today, Upcoming, Someday, Sessions, Recordings, and my projects in the sidebar with Command-1 to 6.
Screens: inbox, today, upcoming, someday, sessions, recordings, project
Depends: S-001
Acceptance:
- [snap] Sidebar shows the six fixed pages, a "Projects" section, and each project with its color dot and count.
- [self] Command-2 selects Today; Today lists tasks due today or overdue, sorted by due then order.
- [unit] Smart list predicates: Inbox = no project and not someday; Upcoming = due after today; Someday = someday flag.
UX: NavigationSplitView. Sidebar symbols: tray, star, calendar, archivebox, timer, record.circle. Projects get a filled circle in their color. New project via File > New Project (Command-Shift-N), inline rename on double-click.
Status: done

### S-004 Move a task to a project or set its date
As the user, I pick a project from the task's detail panel, and set or clear a due date, or mark it Someday.
Screens: task-detail
Depends: S-003
Acceptance:
- [snap] Selecting a task shows a detail panel on the right: title, notes, project picker, due date picker, Someday toggle.
- [self] Setting due = today moves the task into Today; picking a project removes it from Inbox.
- [self] Command-T sets due to today; Command-Shift-T clears it.
UX: Detail panel inline (third column), not a sheet. Date picker is the native graphical DatePicker. Notes is a plain TextEditor.
Status: done

### S-005 Start a focus session on a task
As the user, I select a task and press Command-Return (or the Start button in the toolbar) to start a session with a planned length, and the menu bar shows the countdown.
Screens: session-running, menubar
Depends: S-002
Acceptance:
- [snap] Toolbar shows the running task title and a "Stop" button; the menu bar label reads "24:59" in monospaced digits.
- [self] A Session is saved with task, planned minutes (default 25, from Settings), started = now, ended = nil.
- [self] After the planned time the label shows "+0:05" overflow and a notification "Session done: <task>" is posted; the session keeps running.
- [self] Starting while a session runs stops the current one first.
UX: One session at a time. Length comes from Settings > Sessions (default 25). No modal at the end, only the notification and the overflow label. Menu bar label: "25:00" running, "⏸ 12:30" paused, the app symbol when idle.
Status: done

### S-006 Pause, resume, and stop from the menu bar or hotkey
As the user, I open the menu bar timer to Pause, Resume, or Stop, and press Control-Option-Command-S anywhere to start or stop the session on the selected task.
Screens: menubar
Depends: S-005
Acceptance:
- [snap] Menu bar popover shows task title, big countdown, Pause/Resume and Stop buttons, and "Record" toggle.
- [self] Pause stops the clock; Resume continues; Stop sets ended and pauses recording if any.
- [self] Hotkey with no session starts one on the selected task; with a session, stops it. Works while another app is frontmost (Carbon RegisterEventHotKey).
- [self] Sessions page lists the session with task, start, length, overflow.
UX: MenuBarExtra window style. Hotkey shown in Settings > Sessions, changeable later. Stop never asks "are you sure".
Status: done

### S-007 Record the screen during a session
As the user, I click Record in the session popover or toolbar, pick a display or window in the system picker, and the screen with system audio and mic is written to a file until I stop.
Screens: recording-running, recordings
Depends: S-005
Acceptance:
- [self] Record opens SCContentSharingPicker; after a pick, SCRecordingOutput writes an .mp4 (HEVC, 1080p30 max, mic + system audio) under ~/Movies/OpticalFlow/.
- [self] A Recording row is saved with session, file URL, started; stop sets duration.
- [self] Stopping the session stops the recording. Quitting the app stops and finalizes the file.
- [manual] A 2-minute recording with mic on opens in QuickTime with audio (checks the corruption report).
- [snap] Recordings page lists recordings with task title, date, duration, and a "Show in Finder" button.
UX: Red dot in the toolbar and the menu bar label while recording ("● 24:10"). Mic and camera on by default; toggles in the toolbar's Recording Options menu, the menu bar panel, and Settings, all disabled while recording. Camera sidecar is S-011.
Status: doing (built; the [manual] QuickTime check of a real capture is still open)

### S-008 Export a chapter list from completed tasks
As the user, I complete tasks while recording, then on the Recordings page I click "Copy chapters" and get a YouTube description list.
Screens: recordings, recording-detail
Depends: S-007, S-002
Acceptance:
- [self] Completing a task while a recording runs appends a Chapter(title, offset) to the recording.
- [unit] Chapter text is "0:00 <session task>" first, then "m:ss Title" per chapter; chapters under 10 s apart are merged into the later one; offsets over an hour use "h:mm:ss".
- [snap] Recording detail shows the chapter list and the "Copy chapters" button.
- [self] Copy puts the text on the pasteboard.
UX: The first chapter is always the session's task at 0:00 so YouTube accepts the list. No embedded chapter track.
Status: done

## M2 Edit and camera

### S-009 Trim a recording
As the user, I set a start and end on a recording and export a trimmed MP4.
Screens: recording-detail
Depends: S-007
Acceptance:
- [self] AVMutableComposition + AVAssetExportSession passthrough writes a new file next to the original; chapter offsets shift by the trimmed start.
- [snap] The detail has a Trim section with Start and End sliders, their times, and an Export Trimmed button.
- [self] The new file appears as its own row in Recordings and is selected.
UX: Trim lives in the detail, not a sheet. Sliders with m:ss labels; Export Trimmed is disabled under one second or while exporting. The original is never changed. Output name: "<original> <start> to <end>.mp4".
Status: done

### S-010 Open a recording in QuickTime or Finder
As the user, I open a recording in QuickTime Player from its row, its context menu, or its detail, or reveal the file in Finder.
Screens: recordings, recording-detail
Depends: S-007
Acceptance:
- [snap] Each row has an Open button; the detail has Open and Show in Finder, disabled when the file is missing.
- [manual] Open launches the default player for the file (QuickTime Player).
UX: "Open" (not "Play") because the system player opens. Both actions in the row's context menu too.
Status: done

### S-011 Camera sidecar
As the user, I toggle the camera in the popover and a second .mov of the camera is recorded alongside the screen.
Screens: recording-detail, menubar
Depends: S-007
Acceptance:
- [manual] AVCaptureMovieFileOutput writes <recording>-camera.mov; both start within 100 ms.
- [snap] The detail shows a Camera row with the sidecar file name when one exists.
- [self] Recording.cameraPath is optional and defaults to nil, so M1 databases keep loading.
UX: "Camera" toggle under "Microphone" in the menu bar panel, the toolbar's Recording Options, and Settings > Recording. On by default. While recording, a round camera bubble floats bottom-right, always on top and draggable, so a display capture shows you live; the sidecar stays for the export composite and for window captures, which cannot see the bubble.
Status: done

### S-012 Composite camera bubble into the export
As the user, I export a recording with the camera laid over the bottom-right corner.
Screens: recording-detail
Depends: S-011, S-009
Acceptance:
- [self] The export has one video track, the screen's size, and the chosen range; the file name ends in "with camera".
- [snap] The Trim section shows "Include the camera in the corner" when the recording has a sidecar.
- [manual] The camera sits bottom-right at a quarter of the width with a small margin.
UX: One toggle in the Trim section, on by default, disabled when the sidecar file is missing. A rectangle for now; a round bubble and position choice are later polish.
Status: done

## M3 Time
### S-013 Upcoming grouped by day
As the user, I open Upcoming and see tasks under one heading per day, soonest first.
Screens: upcoming
Depends: S-003
Acceptance:
- [snap] Upcoming shows sections headed "Tomorrow", then weekday names within a week, then dates.
- [unit] DayGroup.label gives Today, Tomorrow, "Saturday 31 Oct", "8 Nov 2026".
UX: Native List sections, no custom headers. Adding a task on Upcoming puts it under Tomorrow.
Status: done
### S-014 Session end reminder picks a break length
As the user, when a session reaches its planned length the notification offers "Break 5 min" and "Break 15 min", and the menu bar counts the break down.
Screens: menubar
Depends: S-005
Acceptance:
- [self] Starting a break stops any session and the menu bar shows "☕ 05:00"; starting a session ends a break; End Break clears the label.
- [manual] The session-done notification shows both break buttons; picking one starts that break; "Break over" arrives at the end.
UX: Breaks never block: no modal, only the menu bar label and a notification. The panel offers Break 5 / Break 15 when idle and End Break during a break.
Status: done
### S-015 Idle for 5 minutes asks keep or discard; auto-stop on sleep
As the user, when I walk away for five minutes the session pauses itself and asks whether to keep or discard that time; when the Mac sleeps the session and recording stop.
Screens: menubar
Depends: S-006
Acceptance:
- [self] Five idle minutes pause the session; Keep adds the idle time and resumes; Discard resumes without it.
- [manual] The "Away for 5 minutes" notification has Keep and Discard; the panel shows "Away since" with the same buttons.
- [manual] Closing the lid stops the session and finalizes any recording.
UX: Idle is measured from the last key or mouse event (CGEventSource, no permission). The pause never discards on its own: the user decides. Sleep stops, because a recording of a sleeping Mac is garbage.
Status: done

## M4 Speed
### S-016 Global quick-entry panel
As the user, I press Control-Space in any app, type a task, and press Return to save it to Inbox with the frontmost app (and browser URL) in its notes.
Screens: quickentry
Depends: S-001
Acceptance:
- [snap] A floating panel with one large field, the "From <app>" line, and the Return/Escape hint.
- [self] Notes read "From Xcode", or "From Safari: <url>"; nothing when OpticalFlow was in front.
- [manual] Control-Space works while another app is frontmost (Carbon hotkey, no permission); Escape or a click elsewhere closes it; the task appears in Inbox.
UX: One field, no project or date here: speed over options. The panel sits a little above center. Also in File > Quick Entry. The browser URL needs the Automation prompt once per browser.
Status: done
### S-017 Search across tasks
As the user, I press Command-F, type words, and every open task whose title or notes contain all of them is listed, whatever page I am on.
Screens: inbox
Depends: S-003
Acceptance:
- [self] Words match in any order and case, across title and notes; done tasks are left out; an empty field shows the page again.
- [snap] A search field in the toolbar; the list is headed "Search" while a query is active; no-match shows the system "No Results" view.
UX: Native `.searchable` in the toolbar, so Command-F and Escape behave like every Mac app. Results show the project dot.
Status: done
### S-018 Type-to-navigate the sidebar
As the user, I click the sidebar and type "up" to jump to Upcoming.
Screens: inbox
Acceptance:
- [manual] With the sidebar focused, typing a page or project name selects it (the native List type-select).
UX: Nothing custom: macOS lists already type-select. Documented here so the shortcut is known.
Status: done
### S-019 Natural-language due dates
As the user, I end a new task with "tomorrow", "fri", "in 3 days", "next week", or "5 nov" and the date is set and cut from the title.
Screens: inbox, quickentry
Depends: S-001, S-016
Acceptance:
- [unit] DueDateParser: today, tomorrow, weekday names (next one, never today), in N days/weeks, next week, "5 nov" and "mar 1" (next year once passed); a lone date word stays a title; "in sunlight" is not a date.
- [self] Adding "Call the sponsor tomorrow" on Inbox makes a task titled "Call the sponsor" due tomorrow; a plain title has no due.
UX: Only at the end of the title, so "Fix the friday report" is left alone... except "friday" at the very end, which the user sees in the row and can clear with Shift-Command-T. The field placeholders name the forms.
Status: done

## M5 System
### S-020 App Intents: start/stop session for Shortcuts and Apple Focus. Status: todo
### S-021 Always-on-top mini timer window. Status: todo
### S-022 Daily and weekly session stats. Status: todo

## M6 Polish
### S-023 Drag tasks between lists and projects. Status: todo
### S-024 Context menus on task and project rows. Status: todo
### S-025 Empty states per page. Status: todo
### S-026 App icon. Status: todo
### S-027 Export preset 1080p H.264 for YouTube. Status: todo

## Dropped
- Share links and cloud upload: needs a server.
- AI chapters and transcripts: chapters come from tasks instead.
- Auto-zoom, cursor smoothing, padding: polish after reliability; see research/recording.md.
- App blocking: Focus-app territory.
- Collaboration, attachments, tags, repeat rules, subtasks: Things/OmniFocus complaints say keep it small.
- iCloud sync: paid account and schema limits; later.
