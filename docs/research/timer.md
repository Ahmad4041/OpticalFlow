# Focus timer and time tracking

Research for OpticalFlow. Done 2026-10-29.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.
Reddit blocked; stayinsession.com pricing blocked (used App Store). Forest has no Mac app, Focus (heyfocus) used instead.

## Findings
- Session: free, Pro $39.99/yr. Menu bar minutes remaining, pause/complete/abandon from menu bar, global hotkeys, Mini Player always-on-top (added because crowded menu bars hide the icon), overflow timer keeps counting past the end, intention + reflection per session, Things/Linear/Reminders preview, Apple Focus via Shortcuts only. [V](https://www.stayinsession.com/changelog-naked)
- Flow: free, $39.99 lifetime. Pure menu bar app, no dock icon, presets free, custom durations Pro. [V](https://www.flow.app/pricing)
- Toggl Track: account required, timer disabled offline. Menu bar running entry, 3 global shortcuts, idle detection with keep/discard/adjust, autotracker rules. [V](https://docs.toggl.com/toggl-2-0-desktop-app)
- Timing: $10/mo. Automatic tracking via Accessibility, Ctrl+Opt+Cmd+T start/stop, idle >= 5 min asks "what did you do", auto-stop timers on sleep. [V](https://timingapp.com/help/preferences)
- Focus (heyfocus): $49 one-time. App/site blocking, pomodoro loop, hardcore mode, scripts on start/end, stats. [V](https://heyfocus.com/)

## Likes and dislikes
| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Session | intention + reflection habit; automations; extend/pause without losing the record; responsive dev | "comically expensive for a timer"; no task tracking; no retroactive logging; stop hidden in a menu; end-of-session overlay disruptive | MAS, zapier, timingapp blog |
| Flow | clean, unobtrusive; cheap lifetime; dev replies | sync lag, stats loss; battery hog; fixed presets on free; icon vanishes in crowded menu bar; rigid cycle | MAS, justuseapp |
| Toggl | idle reminder splits time; sync | crashes, duplicate entries; sign-in loops; idle popup nags; forgotten timer = lost time; no task mgmt | MAS, workyard, trick-tack |
| Timing | zero-effort auto tracking; rules; local data | subscription only; no mobile; overwhelming settings | HN 35308349, chronoid |
| Focus | hardest to bypass; scripting; one-time | no allow-list; no schedule insight; setup involved | HN, aftertone |

Patterns: must have = menu bar countdown, global start/stop, start/pause/stop without opening a window, session record tied to a task, overflow instead of hard stop. Our chance = task-linked sessions (Session's and Toggl's top gap), retroactive logging, no forced overlay, idle detection so a session or recording never runs overnight.

## Feature matrix
| Feature | Session | Flow | Toggl | Timing | Focus | Version one? |
| --- | --- | --- | --- | --- | --- | --- |
| Menu bar countdown | Y | Y | elapsed | totals | Y | yes |
| Global start/stop hotkey | Y | Y | Y | Y | Y | yes |
| Start/pause/stop from menu bar | Y | Y | Y | Y | Y | yes |
| Timer linked to a task | preview only | title | project | rules | profiles | yes |
| Overflow past planned length | Y | N | n/a | n/a | N | yes |
| Break reminders | Y | Y | pomodoro | N | Y | later |
| Session log (history) | Y Pro | Y | Y | Y | Y | yes |
| Daily/weekly stats | Y Pro | Y | Y | Y | Y | later |
| Idle detection | nudge | N | Y | Y | N | later |
| Always-on-top mini player | Y | N | N | N | N | later |
| App blocking | Pro | Y | N | N | Y | no |
| Apple Focus mode | Shortcuts | U | N | N | N | later (App Intents) |

## Decisions
1. Session = Task + start + end + planned minutes + notes, saved even when stopped early, because "no task tracking" and "no retroactive logging" are Session's top complaints [V MAS].
2. Menu bar shows remaining time and offers Start/Pause/Stop; a global hotkey toggles it, because every leader has it and Session had to add a mini player when the icon hid [V changelog].
3. Timer overflows past the planned end with a notification, never a modal overlay, because the overlay is the top UX complaint [V timingapp blog].
4. Idle detection and auto-stop on sleep go in M2, because Toggl's "forgotten timer" is the main lost-time pain [V]. Planned test: CGEventSource seconds-since-last-event probe plus NSWorkspace sleep notification.

## Open questions
- [U] MenuBarExtra label updating every second: CPU cost. Test with a 1 s Timer and Activity Monitor.
