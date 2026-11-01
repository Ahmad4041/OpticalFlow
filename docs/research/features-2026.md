# What to build next (2026)

Research for OpticalFlow. Done 2026-11-01.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Question: which features add the most value next, and what user problem does each solve?
Decision it informs: the order of the next milestones after M8 (board, voice agent, background AI jobs).

## Findings

Tasks and focus
- Todoist split "deadline" from the day you plan to do it (Jan 2025); Things 3.23 made repeat edits humane (complete early, "one-time exception vs change the rule"). Both were the top requests for years. [V](https://www.todoist.com/help/todoist/product-updates/whats-new-january-december-2025-LGktDaLpV) [V](https://culturedcode.com/things/support/articles/1100684/)
- Todoist "Ramble" (Nov 2025) and Superwhisper modes parse project, date and priority from speech. Wispr Flow's cloud screenshots and keystroke logging caused a privacy backlash; local wins. [V](https://superwhisper.com/changelog) [V](https://en.wikipedia.org/wiki/Wispr_Flow)
- Rize 2.0 drafts time entries you approve; Sunsama shows planned versus actual. Both fix "I forgot to start the timer" without the nag overlays people hate in Session and Centered. [V](https://rize.io/changelog/rize-2-0) [V](https://setapp.com/apps/session/customer-reviews)
- Linear let users hand issues to Cursor, Codex and Copilot agents, with an Agent SDK that streams reasoning and clarifying questions. The Hacker News reaction: people want their own agent reading their data, not a bundled chatbot. Cap, Granola and Raycast all shipped MCP or CLI access for the same reason. [V](https://linear.app/changelog/2025-07-30-agent-interaction-guidelines-and-sdk) [V](https://news.ycombinator.com/item?id=47507253)

Recording and creators
- Screen Studio 4, Loom and Tella all ship edit-by-transcript and silence or filler removal; editing is the biggest time sink creators report. [V](https://screen.studio/4) [V](https://support.atlassian.com/loom/docs/loom-ai-features)
- YouTube chapters: the description list must start at 00:00, have at least three entries, each at least 10 s. Loom and Cap generate chapters from the transcript in the cloud; nobody generates them from what you were working on. [V](https://support.google.com/youtube/answer/9884579)
- YouTube upload now costs 1 quota unit in a 100-per-day bucket per API project, with `publishAt` on insert, but needs Google OAuth verification; a shared client id across users would exhaust the bucket. [V](https://developers.google.com/youtube/v3/determine_quota_cost) [V](https://developers.google.com/youtube/v3/docs/videos/insert)
- Recording reliability is the shared complaint: Cap crashes and multi-monitor, Tella wrong screen, Loom audio sync, Screen Studio 40 GB projects. [V](https://github.com/CapSoftware/Cap/releases) [V](https://www.producthunt.com/products/screen-studio)

Agents
- `claude -p --output-format stream-json` is the official headless path: NDJSON events, a final `result` with `total_cost_usd` and `session_id`; `--max-budget-usd` and `--max-turns` cap a run; `--worktree <name>` isolates it in `.claude/worktrees/<name>` on branch `worktree-<name>` and never cleans up. [V](https://code.claude.com/docs/en/headless) [V](https://code.claude.com/docs/en/worktrees)
- `codex exec --json --worktree -o out.md --output-schema s.json` does the same on the Codex side; it hangs on an open stdin pipe, so spawn with stdin closed (already done in VoiceAgent). [V](https://github.com/openai/codex/issues/48716)
- Every vendor stops at a branch or draft PR and never merges: Claude `--bg`, Copilot coding agent, Jules, Cursor cloud agents. Cloud runs give a PR link but no event stream an app can read. [V](https://code.claude.com/docs/en/agent-view) [V](https://jules.google/docs/faq.md)
- Reported failures: the agent says "done" without running tests (fix: a Stop hook that reruns the check); context exhaustion on long runs (fix: an outer loop of short `-p` phases with budgets); worktrees do not isolate `.env`, ports or databases; parallel agents burn plan limits in under an hour. [V](https://codingwithroby.substack.com/p/the-stop-hook-that-wont-let-claude) [V](https://news.ycombinator.com/item?id=47866750)

Platform (macOS 26)
- App Intents are the gate to Spotlight actions (the macOS 26 headline), Shortcuts tiles, Focus filters, Spotlight-indexed tasks and Controls. They work on Intel. But `swift build` does not run `appintentsmetadataprocessor`; other SwiftPM Mac apps run it by hand in their build script, which needs Xcode installed. [V](https://developer.apple.com/videos/play/wwdc2025/260/) [V](https://forums.swift.org/t/what-are-the-compiler-technologies-that-support-the-app-intents-framework/59981) [U until tested here]
- Foundation Models (on-device LLM with tool calling) and Writing Tools need Apple Intelligence, which is M1 or later. They never run on the 2019 Intel MacBook Pro. [V](https://support.apple.com/en-us/121115)
- SpeechTranscriber (macOS 26) is the better long-form transcriber; community reports say it is unavailable on Intel; `DictationTranscriber` is the fallback. [V](https://developer.apple.com/videos/play/wwdc2025/277/) [U](https://github.com/contorch/meeting-capture/pull/25)
- Widgets need a hand-assembled `.appex` without Xcode; Mac-originated Live Activities are macOS 27. ScreenCaptureKit is already at its feature ceiling. [V](https://developer.apple.com/videos/play/wwdc2025/278/)

## Likes and dislikes

| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Things 3 | Humane repeat edits; Spotlight and Siri capture; one-time price | No deadline vs do-date; no blocked-by; no collaboration | culturedcode.com/things/support/articles/1100684, capterra.com/p/119096/Things |
| Todoist | Deadline separate from do date; visual repeat scheduler; Ramble voice capture | Deadlines paid-only; price rise; one calendar at a time | todoist.com/help/todoist/product-updates |
| Linear | Hand issues to agents; Agent SDK streams reasoning | "Too much AI"; want own agent on own data | linear.app/changelog/2025-07-30, news.ycombinator.com/item?id=47507253 |
| Sunsama | Planning and shutdown rituals; planned vs actual | $16 to 20 a month; manual rescheduling | roadmap.sunsama.com/changelog |
| Session | Pulls tasks from Things and Linear; distraction nudge | Finish overlay steals the screen; subscription friction | stayinsession.com/changelog, setapp.com/apps/session |
| Centered | Mini player with task, time and current app | "Still on task?" fires on legitimate switches | every.to/superorganizers/review-centeredapp |
| Rize | AI-drafted time entries you approve | Misassigns browser time; duplicate entries | rize.io/changelog/rize-2-0 |
| Cap | Local MCP and CLI for Claude Code; window-follow; open source | Crashes; multi-monitor; slow studio exports | github.com/CapSoftware/Cap/releases |
| Screen Studio | Auto-zoom; edit by transcript; filler removal | Lifetime licence dropped; 40 GB projects; no voiceover | screen.studio/4 |
| Tella | Magic Trim pauses; publish to YouTube, Shorts, LinkedIn with scheduling | Records wrong screen; corrupted retakes | tella.tv/changelog |
| Loom | AI titles, summaries, chapters; edit by transcript | Price rise; AI gated at $24 a seat; audio sync | support.atlassian.com/loom |
| Raycast | MCP in AI chat; local models | Dictation moved behind Pro; AI credits | raycast.com/changelog |
| Superwhisper | Fully offline; per-app modes; Claude Code and Codex integrations | Overwhelming settings | superwhisper.com/changelog |
| Wispr Flow | Polish; per-app tone | Cloud screenshots and keystroke logging; 800 MB idle | trustpilot.com/review/wisprflow.ai |
| Granola | Notes without a bot; Recipes; MCP | Encrypted cache broke tools; API paid | granola.ai/updates |

Patterns. Must have: structured voice capture, done locally; expose data to the user's own agent; edit video by transcript with silence removal; passive time tracking the user approves; deadline distinct from do-date. Our chance: no subscription gating, no cloud exposure, timers that never interrupt, recording that is reliable before it is clever.

## Feature matrix

| Feature | Problem it solves | Who does it today | OpticalFlow today | Build? |
| --- | --- | --- | --- | --- |
| Hand a task to an agent in a worktree, progress on the card | "Start this while I do something else" with a safe result | Linear, Claude `--bg`, Cursor, Copilot (cloud, no stream) | AI jobs run commands only | Yes, next |
| Chapters validated for YouTube, markers while recording | Chapters typed by hand after the fact; scrubbing hours of VOD | Loom and Cap from transcript (cloud) | Chapters from tasks, no validation, no markers | Yes |
| Silence removal in trim | Dead air; editing is the biggest time sink | Screen Studio, Loom, Tella | Trim by hand | Yes |
| Local transcript and SRT | Captions, chapter titles, searchable timeline | Screen Studio, Cap (local); Descript (cloud) | None | Apple silicon first; Intel needs whisper.cpp or a "no captions" decision |
| Session log you approve, planned vs actual | "I forgot to start the timer"; no nag | Rize, Sunsama | Idle detection, stats | Yes |
| Deadline vs do-date, repeat rules | Due dates double as plans; repeats are rigid | Todoist, Things | One due date, no repeats | Yes, small |
| App Intents: Spotlight actions, Shortcuts, Focus filters | Add or start from Spotlight; Focus switches project | Things, Todoist | URL scheme only | After the build step is proven |
| Foundation Models on device | Private parsing and summaries with no agent running | Apple silicon apps | Claude or Codex path | Later; untestable on the dev Mac |
| Vertical 9:16 export of a marked segment | Shorts and Reels | Screen Studio, Opus, Tella | None | Later |
| Direct YouTube upload | Re-upload friction | Tella, Descript | Chapters to clipboard | Later; needs OAuth verification |
| Widgets, Live Activities | Timer on the desktop | Few on Mac | Menu bar, mini timer, Touch Bar | No for macOS 26 |
| Multi-platform publishing, AI clip scoring | One recording, five uploads | Tella, Opus | None | No; leave to those tools |

## Decisions

1. Build S-042 as a local worktree hand-off with `claude -p --worktree <task-id> --output-format stream-json --max-budget-usd --max-turns` (or `codex exec --json --worktree`), because only local runs stream events the card can show [V headless docs]. Done is a check the app runs: structured output naming branch, tests run and summary, plus `git log` on the branch. The user picks "Open PR" or "Discard worktree"; the app never merges. Planned test: Seatbelt with `allowLocalBinding` and `gh` on this Mac [U].
2. Validate chapters for YouTube and add a "mark that" hotkey during recording, because chapters from tasks are the one step no other tool can do and markers feed trim and clips [V YouTube rules]. Low effort.
3. Add silence removal to the trim editor from audio levels, because it is the most-shipped editing feature of 2025 and needs no transcript [V Loom, Screen Studio].
4. Add a session log you approve with planned versus actual, because Rize and Sunsama users love it and Session and Centered users hate interruptions [V]. Reuse idle detection.
5. Split deadline from do-date and add simple repeat rules, because both were the longest-standing requests at Todoist and Things [V]. Keep the "subtasks, tags, attachments" dropped line; this is two fields and a rule.
6. Add App Intents only after a probe proves `appintentsmetadataprocessor` runs from build.sh on this Mac [U]; then Spotlight actions, Shortcuts and a Focus filter follow cheaply, on Intel too.
7. Transcripts: ship SpeechTranscriber on Apple silicon behind `isAvailable`, DictationTranscriber as the fallback; decide between bundling whisper.cpp and "no captions on Intel" after measuring speed on this Mac [U].
8. Skip for now: widgets (hand-built appex), Live Activities (macOS 27), YouTube upload (OAuth verification and a per-project quota), multi-platform publishing and AI clip picking (cloud incumbents do it better).

## Ranked shortlist

| # | Feature | Problem | Value | Effort |
| --- | --- | --- | --- | --- |
| 1 | Hand a task to an agent in a worktree, progress and result on the card (S-042) | Long work blocks you; agents are unsafe without a gate | Turns the board into a dispatcher for Claude Code and Codex; what Linear users asked for, local | L |
| 2 | Chapters validated for YouTube plus "mark that" during recording | Hand-typed chapters; hours of scrubbing | Unique: nobody else knows what you worked on | S |
| 3 | Silence removal in trim | Dead air; editing time | The most-shipped editing feature of 2025 | M |
| 4 | Session log you approve, planned vs actual | Forgotten timers; nag overlays | Passive and honest stats | M |
| 5 | Deadline vs do-date, repeat rules | Due dates double as plans | Two fields, big relief | S |
| 6 | App Intents: Spotlight actions, Shortcuts, Focus filter | Capture and start from anywhere | macOS 26 headline, works on Intel | M, after a build probe |
| 7 | Local transcript and SRT (Apple silicon first) | Captions, chapter titles | Gate for filler removal later | M on Apple silicon, H on Intel |
| 8 | Vertical export of a marked segment | Shorts | Reuses markers and the compositor | M |
| 9 | Foundation Models for parsing and summaries | Privacy, no agent needed | Only on Apple silicon; untestable here | M |

## Open questions

- [U] Does Claude Code's Seatbelt sandbox let a worktree run reach the app socket (`allowLocalBinding`) and run `gh` on this Mac? Probe before S-042.
- [U] Does `xcrun appintentsmetadataprocessor` run from build.sh with the Xcode on this Mac and produce `Metadata.appintents`? Probe before any App Intent.
- [U] Is `SpeechTranscriber.isAvailable` false on Intel macOS 26? Check in the self-test on this Mac; a positive would simplify transcripts.
- [U] whisper.cpp speed on this Intel Mac for a 30-minute recording; decides captions on Intel.
