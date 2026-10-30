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

## M7 Studio: camera, editor, and multi-display

### S-028 Camera corner, size, and shape
As the user, I choose which corner the camera sits in, how big it is, and whether it is a circle or a rounded rectangle, and both the live bubble and the export follow.
Screens: settings-general, recording-detail
Depends: S-011, S-012
Acceptance:
- [unit] CameraLayout.frame: bottom-right medium circle on 1920x1080 is a 480 pt square 38 pt from the edges; top-left small rounded is 320x180.
- [self] An export with top-left, large, rounded renders through the Core Image compositor and keeps its length; the layout is saved.
- [manual] Changing the corner while recording moves the live bubble at once.
UX: Controls in Settings > Sessions > Camera and in the toolbar's Recording Options; the menu bar panel has a four-corner segmented control for speed. The live bubble shows the layout at half the export size so it does not hide your work. Dragging the bubble is still allowed for the moment; the export uses the chosen corner.
Status: done

### S-029 Blur the background behind you
As the user, I turn on "Blur the background behind you" and the export keeps me sharp while blurring the room.
Screens: settings-general
Depends: S-028
Acceptance:
- [self] A blurred export completes (Vision person segmentation per frame in the compositor).
- [manual] In the export the person is sharp and the background is blurred; a frame with no person is fully blurred.
UX: Export only. The live bubble shows the raw camera because per-frame segmentation on the live preview would cost the CPU that the screen capture needs on an Intel Mac. Said in the toggle's help text.
Status: done

### S-030 Preview a recording in the editor
As the user, I play the recording in the detail and set the trim start and end from the playhead.
Screens: recording-detail
Depends: S-009
Acceptance:
- [snap] A Preview section with the system player above Trim; Set Start Here, Set End Here, Play from Start.
- [manual] Set Start Here takes the playhead time; Play from Start seeks to the trim start.
UX: AVKit's VideoPlayer, no custom scrubber. Sliders stay for fine moves.
Status: done

### S-031 Follow the cursor in the export
As the user, I turn on "Follow the cursor (2x zoom)" and the export shows half the frame around my pointer, gliding as it moves.
Screens: recording-detail
Depends: S-009
Acceptance:
- [unit] CursorTrack.viewport centers on the pointer and clamps to the frame; smoothing moves samples toward the previous one.
- [self] Every recording writes a <name>-cursor.json sidecar (10 samples a second); a zoomed export keeps the frame size and range and is named "zoomed".
- [manual] The zoom follows the pointer smoothly without snapping at the edges.
UX: Fixed 2x zoom, always on when the toggle is on. Auto zoom-in on clicks and zoom-out when idle are later; said in the help text.
Status: done

### S-032 Follow the pointer to another display
As the user recording a whole display, I move the pointer to my other monitor and the recording switches to it.
Screens: settings-general
Depends: S-007
Acceptance:
- [unit] CursorTrack.normalize maps a point on a second display into that display's rect.
- [manual] With the toggle on and a display picked, moving the pointer to another display switches the capture within half a second; a window capture never switches; the first use asks for Screen Recording permission.
UX: Off by default and explained in the toggle's help, because it needs the Screen Recording permission the picker avoids. The file keeps one size; a display with another aspect is scaled by ScreenCaptureKit.
Status: done

### S-033 Recording thumbnails and richer session rows
As the user, I recognise recordings by a still from the video and sessions by their project colour and done state.
Screens: recordings, sessions
Acceptance:
- [snap] Each recording row shows a 64x36 still; each session row shows the project dot (or a check when the task is done) and the project name.
UX: Thumbnails come from AVAssetImageGenerator at one second in, cached for the app's run. A missing file shows a film symbol.
Status: done

## M8 Board and agents

### S-034 Kanban board for a project
As the user, I switch a project to Board and see Backlog, To Do, Doing, and Done columns, and drag cards between them.
Screens: board
Depends: S-003, S-023
Acceptance:
- [unit] BoardColumn.column: done wins, then doing, then someday, else to do.
- [self] Dropping on Doing sets the flag; Backlog flags someday; Done completes; To Do reopens; completing clears doing.
- [snap] Four 240 pt columns with cards: colour stripe, title, due, Records and Live badges; the Done column shows the last seven days.
UX: List/Board segmented control in the toolbar of project pages, remembered; Command-Option-B toggles. The board fills the detail column and the list stays in the middle; clicking a card opens its detail as a popover, so the board never moves. Columns are the project's own state, not a new field per column.
Status: done

### S-035 Record sessions per task
As the user, I flag a task "Record the screen during sessions" and starting a session on it opens the recorder; a session also moves the task to Doing.
Screens: today, board
Depends: S-005, S-007
Acceptance:
- [self] Starting a session sets doing; without the flag the recorder is not asked; with the flag the picker is requested once.
- [snap] A red record badge on the row and a "Records" badge on the card.
UX: Toggle in the detail's Sessions section, the row's context menu, and the card's context menu. Nothing starts without the picker: the user still chooses what to capture.
Status: done

### S-036 Select a session
As the user, I click a session row and see its task, times, overflow, notes, and recordings, with pause, stop, or start-another buttons.
Screens: sessions
Depends: S-006
Acceptance:
- [self] Selecting the first session resolves a Session, not a task; Delete removes it and clears the selection; Show Task selects the task on its page.
- [snap] Sessions page with the first row selected and its detail on the right.
UX: Context menu on the row: Start Another Session, Show Task, Delete. Notes are editable after the fact (retroactive logging was a top complaint in research).
Status: done

### S-037 Agent CLI
As the user, I let Claude Code or a script drive the app with `opticalflow <noun> <verb> --json` against the running app.
Screens: none
Acceptance:
- [self] check-agent-cli.sh prints PASS agent CLI; every read command returns JSON; delete reports until --yes.
UX: 25 commands; the skill file in .claude/skills/opticalflow tells agents the rules. MCP registration is one line, documented there.
Status: done

### S-038 Focus view in the detail column
As the user, with nothing selected I see the running session as a large ring with Pause, Stop, Record, and Done, or, when idle, today's focused time, sessions, and tasks done, and the next task with one Start button.
Screens: focus, focus-running
Depends: S-005, S-035
Acceptance:
- [self] upNext is the Doing task on the page, else the first open task, else Today's, else Inbox's.
- [snap] focus and focus-running, light and dark.
UX: replaces the "No Selection" placeholder. Start on the card runs the session; the Record switch flags the task. Done completes the task and stops the session.
Status: done

### S-039 Add tasks on the board
As the user, on the board I click + in a column header, or press Command-N, type a title, and the card appears in that column of this project.
Screens: board
Depends: S-034
Acceptance:
- [self] addTask(title:project:column:) sets the project and the column's flags; Backlog adds are Someday.
- [self] Delete on a card removes it.
UX: + on every column; the toolbar + and Command-N open the draft in To Do. Cards also get Complete, Priority, and Delete in their menu.
Status: done

### S-040 Priority
As the user, I give a task a priority (None, Low, Medium, High) and see a flag on its row and card; the Focus view offers the most urgent task first.
Screens: today, board
Depends: S-038
Acceptance:
- [unit] Priority.parse reads high, urgent, asap, p1, medium, low, none.
- [self] priority round-trips through the model; upNext prefers the urgent task.
- [self] CLI: tasks add and update take --priority; JSON carries priority.
UX: Picker in the detail; Priority submenu in row and card menus; red, orange, or accent flag.
Status: done

### S-041 Voice agent
As the user, I press Control-Option-Space anywhere, say what I want ("make the login loop urgent", "add a note to the chapter export: use the YouTube preset", "start the OBS scene"), and an orchestrator does it in the app and answers in one sentence.
Screens: voice, settings-agent
Depends: S-037, S-040
Acceptance:
- [unit] VoiceIntent.parse maps add, complete, start, stop, priority, and note phrasings; anything else is a new task.
- [self] perform() adds with a date, sets priority, appends a note, starts and stops a session, completes, and reports a miss without changing anything.
- [self] `opticalflow agent say "…"` runs the same path, so a Shortcut with Dictate Text works too.
UX: On-device speech when the language supports it; a pause sends. Microphone picker in Settings > Agent, shared with recordings; the panel says when a microphone is silent. Orchestrator in Settings > Agent: Built in (no AI), Claude Code (`claude -p`, only the opticalflow command allowed), or Codex (`codex exec`, workspace sandbox). ChatGPT has no command line on the Mac, so it is not offered.
Status: done

### S-043 Subtasks and richer cards
As the user, I break a task into subtasks in its detail, tick them off, and see "2/5" on the row and a progress bar on the card. Cards also show the first line of notes, a complete circle on hover, an overdue date in red, and a shadow on hover.
Screens: board, today
Depends: S-034, S-040
Acceptance:
- [unit] Checklist.parse splits on ; and newlines; progress counts; index finds by number or words.
- [self] subtasks persist with their done state; "add a subtask to X: Y" appends one.
- [self] CLI: tasks add --subtasks, tasks update --subtasks, --check, --uncheck; JSON carries subtasks.
Status: done

### S-044 Dates and times in plain words
As the user, I type or say "call the bank tomorrow at 3pm", "standup at 9:30 on Monday", or "pay rent on the 5th of November", and the task gets that date and time while the title keeps only the words that matter.
Screens: today, board
Depends: S-001, S-041
Acceptance:
- [unit] the parser finds a date and a time anywhere in the sentence: weekdays, ordinals, month names, "tonight", "at 3", "noon", ISO dates; "call 3 friends" and "sort 2 decks" stay untouched.
- [self] a timed task keeps hasDueTime, shows its time on rows and cards, and lists in Upcoming.
UX: Detail has a Time switch next to the date; the CLI --due takes the same words.
Status: done

### S-045 Project names by voice
As the user, I say "add buy pizza in Fordan" or "add a task to Fordan: order stickers" and the task lands in that project, even when the recognizer hears "for than".
Screens: voice
Depends: S-041
Acceptance:
- [unit] edit distance.
- [self] project(matching:) finds a project within a couple of letters and rejects unrelated words; "in <project>" and "to <project>:" file the task there.
UX: project names and recent task titles go to the recognizer as vocabulary; the AI prompt lists the projects.
Status: done

### S-047 AI works in the background
As the user, a long AI request keeps running after I close the voice panel; a sparkles icon in the toolbar pulses while it runs, the card says "AI working on it", and when it finishes the answer appears on the card and in the detail, with a notification.
Screens: board, voice
Depends: S-041
Acceptance:
- [self] attach() writes the answer onto the tasks the job touched; finished jobs clear.
- [snap] a card with an AI answer.
UX: Toolbar sparkles open the list of jobs with steps, answers, Open and Stop. `opticalflow agent jobs` lists them.
Status: done

### S-042 Hand a task to a sandboxed agent
As the user, I hand a task with its notes to an agent that works on it in a sandbox for the long run, and see its progress and result on the card.
Screens: board
Depends: S-041
Acceptance: to write with the user: which runtime (Claude Code or Codex in a container or a separate checkout), what "done" means, how results come back (notes, a recording, a PR link).
Status: planned

## M5 System
### S-020 Shortcuts and Apple Focus control
As the user, I start, stop, pause, or resume a session, start a break, toggle recording, or add a task from Shortcuts or a Focus automation with an Open URL action.
Screens: settings-general
Depends: S-005, S-014
Acceptance:
- [self] opticalflow://start starts on the selected task; start?task=<words> finds an open task by title; pause, stop, break?minutes=, add?title= work; an unknown host is refused.
- [manual] A Shortcuts automation "When Work Focus turns on → Open URL opticalflow://start" starts a session.
UX: URL scheme instead of App Intents, because App Intents metadata needs an Xcode project (see new-mac-app skill); the commands are listed in Settings > Sessions. ponytail: move to App Intents when the project goes XcodeGen.
Status: done
### S-021 Always-on-top mini timer
As the user, I show a small floating timer with pause and stop, so the countdown stays visible when the menu bar is crowded or hidden.
Screens: minitimer
Depends: S-005
Acceptance:
- [self] Window > Show Mini Timer (Option-Command-M) shows a floating panel; the same command hides it.
- [snap] A 220 pt wide panel: big countdown, task title, pause and stop.
UX: A non-activating utility panel on every Space, position remembered. Also from the menu bar panel and opticalflow://mini.
Status: done
### S-022 Daily and weekly session stats
As the user, I open Sessions and see today's and this week's focused time with a seven-day bar strip.
Screens: sessions
Depends: S-006
Acceptance:
- [unit] SessionStats.perDay buckets sessions into the last seven days, oldest first; hours() formats "1h 05m" and "45m".
- [snap] A stats row above the session list: Today, This week, and seven bars with weekday initials, today in the accent.
UX: Bars are plain rounded rectangles with hover help; no chart library. The running session counts live.
Status: done

## M6 Polish
### S-023 Drag tasks between lists and projects
As the user, I drag a task onto Inbox, Today, Upcoming, Someday, or a project in the sidebar and it moves there.
Screens: inbox
Depends: S-003
Acceptance:
- [self] Dropping on Someday flags it and clears the date; on Today sets due today; on Inbox clears the project; on a project assigns it.
- [manual] The sidebar row highlights while dragging over it; Sessions and Recordings refuse the drop.
UX: Native List drag (the task's id as text) and dropDestination on sidebar rows. The same moves live in the row's context menu for the keyboard-minded.
Status: done
### S-024 Context menus on task and project rows
Screens: inbox
Acceptance:
- [manual] Task row: Complete, Start Session, Due Today, Due Tomorrow, Someday, Clear Due Date, Move to Project ▸, Delete. Project row: New Task in <project>, Rename…, Delete.
Status: done
### S-025 Empty states per page
Screens: inbox, today, upcoming, someday, project
Acceptance:
- [self] Each page has its own title and hint (Inbox Zero; Nothing Due Today; Nothing Scheduled; No Someday Ideas; No Tasks Here).
- [snap] An empty page shows the system unavailable view with that text.
Status: done
### S-026 App icon
Screens: dock
Acceptance:
- [manual] tools/icon_review.sh shows a timer ring with a record dot over three flow arcs, readable at 16 pt, in default, dark, tinted, and clear looks.
Status: done
### S-027 YouTube export preset
As the user, I leave "YouTube preset" on and the export is 1080p H.264 with AAC, which YouTube recommends.
Screens: recording-detail
Depends: S-009
Acceptance:
- [self] The export's video track is H.264 and the file name ends in "youtube".
UX: On by default; off keeps passthrough (or HEVC when the compositor runs). File names say what was applied.
Status: done

## Dropped
- Share links and cloud upload: needs a server.
- AI chapters and transcripts: chapters come from tasks instead.
- Auto-zoom, cursor smoothing, padding: polish after reliability; see research/recording.md.
- App blocking: Focus-app territory.
- Collaboration, attachments, tags, repeat rules, subtasks: Things/OmniFocus complaints say keep it small.
- iCloud sync: paid account and schema limits; later.
