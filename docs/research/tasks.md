# Tasks and to-do

Research for OpticalFlow. Done 2026-10-29.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.
Reddit was blocked; opinions come from Mac App Store, Capterra, G2, HN, switcher blogs.

## Findings
- Things 3: $49.99 Mac one-time, Apple only, no web. Today/Upcoming/Anytime/Someday, projects + headings, checklists, Markdown notes, Quick Entry with Autofill. [V](https://apps.apple.com/us/app/things-3/id904280696?mt=12)
- Things shortcuts people cite: Ctrl+Space Quick Entry, Ctrl+Opt+Space Autofill, Cmd+1..6 lists, Cmd+S when, Cmd+K complete, Shift+Cmd+M move, Type Travel. [V](https://culturedcode.com/things/support/articles/2785159/)
- Todoist: free, Pro $5/mo. Electron shell with native bridges for hotkeys [U]. Opt+Space global Quick Add, Q, Cmd+K, 1-4 priority, E complete. [V](https://www.todoist.com/help/todoist/features/use-keyboard-shortcuts-in-todoist-Wyovn2)
- Apple Reminders: free, smart lists, tags, sections, subtasks. No global quick-entry panel. Cmd+T today, Opt+Cmd+T tomorrow, Shift+Cmd+C complete. [V](https://support.apple.com/guide/reminders/keyboard-shortcuts-remn19b3424c/mac)
- OmniFocus 4: $74.99 / $149.99 one-time. Defer + due, Forecast, Review, tags. Quick Entry Ctrl+Opt+Space. [V](https://www.omnigroup.com/omnifocus/buy)
- TickTick: free, Premium $49.99/yr. Pomodoro, habits, Eisenhower, menu-bar mini window Cmd+Shift+O, Cmd+Shift+A quick add. [V](https://ticktick.com/mac?language=en_us)

## Likes and dislikes
| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Things 3 | best quick capture on Mac; design coherence; one-time price; depth revealed gradually; Shortcuts | no collaboration; no attachments; no web; slow innovation; headings/areas confusing; limited repeat rules | MAS, asianefficiency, Capterra |
| Todoist | cross-platform; NLP dates; tags and filters; low learning curve | Electron feel; clunky date clicks; no undo on delete; no defer dates; subscription | MAS, HN 14367878, HN 44864134 |
| Reminders | free; Siri and calendar; good enough for many | odd recurrence model; weak nagging; no global quick entry; iCloud only | HN, TechRadar |
| OmniFocus 4 | perspectives and Forecast; reliable sync; defer + Review | overwhelming; price; v4 UI regressions; crashes with big DBs | MAS, Capterra |
| TickTick | all-in-one with pomodoro and habits; menu-bar capture; Eisenhower | weak keyboard shortcuts; privacy worries; sync glitches; free-tier limits | MAS, Trustpilot, AlternativeTo |

Patterns: must have = global quick-entry panel, full keyboard model (Cmd+1..n, single-key complete/date/move), Today/Upcoming/Someday, one-time price feel. Our chance = native speed (Todoist/TickTick complaints), timer linked to a task (TickTick's draw, Things' gap), undo on delete.

## Feature matrix
| Feature | Things | Todoist | Reminders | OmniFocus | TickTick | Version one? |
| --- | --- | --- | --- | --- | --- | --- |
| Inbox / Today / Upcoming / Someday | Y | Y (filters) | Y (smart lists) | Y (Forecast) | Y | yes |
| Projects | Y | Y | lists | Y | Y | yes |
| Headings / sections | Y | Y | Y | Y | Y | later |
| Checklists / subtasks | Y | Y | Y | Y | Y | later |
| Notes on a task | Y (Markdown) | Y | Y | Y | Y | yes (plain) |
| Due date | Y | Y | Y | Y | Y | yes |
| Defer / start date | Y (when) | N | N | Y | N | later |
| Tags | Y | labels | Y | Y | Y | later |
| Repeat | Y | Y | Y | Y | Y | later |
| Global quick entry | Y | Y | N | Y | Y | yes |
| Keyboard: complete, date, move | Y | Y | Y | Y | weak | yes |
| Undo delete | Y | N | Y | Y | ? | yes |
| Pomodoro linked to task | N | N | N | N | Y | yes (differentiator) |
| Collaboration, attachments, sync | mixed | Y | Y | Y | Y | no |

## Decisions
1. Data model is Task(title, notes, due, done, project) + Project. Smart lists Inbox/Today/Upcoming/Someday filter the one model, because every leader ships exactly this set [V Things, Reminders] and OmniFocus users abandon for "too much" [V Capterra].
2. Global quick-entry panel on a hotkey is in M1, because it is the single most-praised feature across Things, OmniFocus, Todoist [V].
3. Keyboard-first: Cmd+1..4 lists, Cmd+K complete, Cmd+T today, Cmd+Z undo delete, because TickTick's top complaint is weak hotkeys and Todoist's is no undo [V MAS].
4. A focus session links to a task (the OpticalFlow differentiator), because TickTick wins users on it and Things lacks it [V].

## Open questions
- [U] Whether Todoist Mac is Electron. Irrelevant to us; we are native.
- [U] Will EventKit (Reminders) as the store give sync for free? See platform.md.
