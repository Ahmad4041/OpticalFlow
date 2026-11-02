<p align="center"><img src="docs/screenshots/hero.png" alt="OpticalFlow" width="100%"></p>

<p align="center">
  <a href="https://github.com/Ahmad4041/OpticalFlow/actions/workflows/ci.yml"><img src="https://github.com/Ahmad4041/OpticalFlow/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-brightgreen" alt="Local only">
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#use">Use</a> ·
  <a href="#voice-and-ai">Voice and AI</a> ·
  <a href="#hand-a-task-to-an-agent">Agent hand-off</a> ·
  <a href="#cli-and-mcp">CLI and MCP</a> ·
  <a href="docs/STORIES.md">Stories</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

**The AI productivity app for Mac.** Speak a task and it is filed with its date, priority and project. Focus on it with a timer that follows you to the menu bar, the mini timer and the Touch Bar. Record the screen while you work and export it with YouTube chapters. Hand the task to Claude Code or Codex and get back a branch with commits, not a promise.

Native SwiftUI, one local database, no account, no server, no telemetry. The AI runs through the CLIs you already have installed and logged in. Screenshots below follow your GitHub theme.

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/focus-running-dark.png"><img src="docs/screenshots/focus-running-light.png" alt="A running focus session with the countdown ring"></picture>

<table>
<tr>
<td width="50%"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/today-dark.png"><img src="docs/screenshots/today-light.png" alt="Today list with the task detail"></picture></td>
<td width="50%"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/board-dark.png"><img src="docs/screenshots/board-light.png" alt="Kanban board with Backlog, To Do, Doing and Done"></picture></td>
</tr>
<tr>
<td align="center"><b>Today</b>: priority, deadline, repeat, subtasks</td>
<td align="center"><b>Board</b>: every project is also a kanban</td>
</tr>
<tr>
<td width="50%"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/recordings-dark.png"><img src="docs/screenshots/recordings-light.png" alt="A recording with its YouTube chapter list"></picture></td>
<td width="50%"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/sessions-dark.png"><img src="docs/screenshots/sessions-light.png" alt="The session log with this week's bars"></picture></td>
</tr>
<tr>
<td align="center"><b>Recordings</b>: chapters from finished tasks and markers</td>
<td align="center"><b>Sessions</b>: planned, worked, overflow</td>
</tr>
<tr>
<td width="50%" align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/voice-dark.png"><img src="docs/screenshots/voice-light.png" alt="The voice panel showing the agent's steps" width="420"></picture></td>
<td width="50%" align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/minitimer-dark.png"><img src="docs/screenshots/minitimer-light.png" alt="The floating mini timer" width="280"></picture></td>
</tr>
<tr>
<td align="center"><b>Voice</b>: one sentence becomes tasks, dates and priorities</td>
<td align="center"><b>Mini timer</b>: floats over everything</td>
</tr>
</table>

## AI, in real time

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/ai-realtime-dark.png"><img src="docs/screenshots/ai-realtime-light.png" alt="Voice panel with the agent's steps, the background jobs list, and the result on the task card"></picture>

Three levels, and you pick how far it goes:

1. **On-device.** "Add fix the login loop to Fordan, due Friday at 3, high priority, repeat weekly." Dates, times, deadlines, repeats, priority, project and subtasks are parsed on the Mac. Nothing leaves it.
2. **Orchestrator.** Anything the parser cannot settle goes to Claude Code or Codex, which drive the app through its own `opticalflow` CLI. Every command shows as it runs. Close the panel and keep working; the toolbar sparkles pulse until the answer lands on the card and a notification arrives.
3. **Hand-off.** Give a task to the agent for real. It works on a branch in its own git worktree, the card shows commits, diff size and cost, and you open a draft pull request or discard the branch. The app never merges.

## Touch Bar

![Touch Bar: Record and Voice when idle, the countdown with Pause, Stop and Done during a session, and the Control Strip item next to brightness and volume while another app is in front](docs/screenshots/touchbar.png)

In OpticalFlow the bar has the session controls. In any other app a Control Strip item keeps the countdown next to brightness and volume; tap it for Pause, Stop, Done, Record and Voice without switching apps. Turn it off in Settings > Sessions.

## What it does

- **Voice and AI.** Press Control-Option-Space and say "add fix the login loop to Fordan, due Friday, high priority". Clear commands run at once on-device. Compound requests go to Claude Code or Codex, installed on your Mac, which call the app's own CLI. Answers land on the task card while you keep working.
- **Hand a task to an agent.** Set a project's repository folder, choose Hand to Agent, and the app creates a branch and worktree, runs the agent with the task as its brief, then shows commits, diff size and cost on the card. Open a draft pull request or discard the branch. The app never merges.
- **Tasks.** Inbox, Today, Upcoming, Someday and projects, keyboard first. Priority, subtasks, a planned day and a separate deadline, repeat rules, notes. Each project has a list and a kanban board (Backlog, To Do, Doing, Done).
- **Focus sessions.** A countdown on a task from the window, the menu bar, a floating mini timer, or the Touch Bar. Pause, overtime, breaks, idle detection, a session log.
- **Recording.** Screen, system audio, microphone and camera through ScreenCaptureKit. Chapter markers while you record. Trim, camera bubble, follow the pointer, blur, YouTube preset on export. The chapter list comes from the tasks you completed and the markers you set.
- **CLI and MCP.** `opticalflow` drives the running app from any shell. The same binary is an MCP server for Claude Desktop.

## Requirements

- macOS 26 or later.
- Xcode 26 (Swift 6.2) to build. There is no Xcode project. It is a Swift package.
- Optional: [Claude Code](https://docs.claude.com/en/docs/claude-code) or [Codex CLI](https://github.com/openai/codex) for the AI orchestrator and hand-offs. [`gh`](https://cli.github.com) to open pull requests from the app.

## Install

**Download:** open the `.dmg` from the [latest release](https://github.com/Ahmad4041/OpticalFlow/releases/latest) and drag OpticalFlow to Applications (a `.zip` is there too). The build is not notarized yet, so the first launch needs right-click, Open, or:

```sh
xattr -d com.apple.quarantine /Applications/OpticalFlow.app
```

**Build it yourself:**

```sh
git clone https://github.com/Ahmad4041/OpticalFlow.git
cd OpticalFlow
./build.sh --open
```

`build.sh` builds a release binary, signs it with your Apple Development certificate when you have one (ad hoc otherwise), stages the bundle under `~/Library/Developer/OpticalFlow/`, installs it to `~/Applications/OpticalFlow.app`, and links the CLI to `~/.local/bin/opticalflow`. Add `~/.local/bin` to your PATH if it is not.

macOS asks for Screen Recording the first time you record, Microphone and Speech Recognition the first time you use voice, and Camera when you turn the camera on. The app works without any of them.

## Use

| Action | Shortcut |
| --- | --- |
| New task | Command-N |
| Quick Entry from anywhere | Control-Space |
| Voice Command from anywhere | Control-Option-Space |
| Start or stop a session from anywhere | Control-Option-Command-S |
| Start or stop a session in the window | Command-Return |
| Pause or resume | Command-Option-P |
| Record the screen | Shift-Command-R |
| Mark a chapter while recording | Shift-Command-M (Control-Option-Command-M from anywhere) |
| Hand the task to an agent | Option-Command-H |
| List or board | Option-Command-B |
| Complete | Command-K |
| Due today | Command-T |

Every action is also a menu item. Settings has one tab per topic: Sessions (length, recording, Control Strip), Agent (orchestrator, microphone), Appearance (accent and light or dark).

### Voice and AI

Pick an orchestrator in Settings > Agent. Built-in understands dates, times, deadlines, repeats, priority, projects and subtasks in one sentence and never leaves the Mac. Claude Code and Codex handle anything else, with each command they run listed in the panel and on the toolbar sparkles while a job is in the background.

The built-in microphone on some MacBook Pro models delivers silence to apps. If the panel hears nothing, choose another microphone in Settings > Agent, or run `opticalflow agent listen --probe`.

### Hand a task to an agent

1. Right-click a project in the sidebar, Set Repository Folder, pick the git checkout.
2. On a task in that project, choose Hand to Agent.
3. The agent works on branch `opticalflow/<task id>` in a worktree under `~/Library/Application Support/OpticalFlow/worktrees/`. Your checkout is never touched. Runs stop at 80 turns or five dollars, and the agent may not push, merge or switch branches.
4. When it finishes the card shows the commit count and diff. The task detail has Open Pull Request, Reveal Worktree and Discard Branch.

### CLI and MCP

```sh
opticalflow status --json
opticalflow tasks add --title "Ship the release" --project Fordan --due fri --priority high --json
opticalflow agent say "move the login loop to doing" --json
opticalflow record mark --title "The bug appears" --json
opticalflow tasks handoff <id> --json
opticalflow help
```

For Claude Desktop or Claude Code:

```sh
claude mcp add --scope user opticalflow -- ~/Applications/OpticalFlow.app/Contents/MacOS/OpticalFlow mcp
```

The full command table is in [.claude/skills/opticalflow/SKILL.md](.claude/skills/opticalflow/SKILL.md).

## Privacy

Tasks, sessions and recordings are a SwiftData store and movie files under `~/Library/Application Support/OpticalFlow/`. Speech recognition runs on-device when macOS can, otherwise through Apple's speech service. Nothing is sent to Anthropic or OpenAI unless you choose Claude Code or Codex as the orchestrator and send a request or hand off a task. Those runs use your own CLI login and the app passes only the task title, notes and subtasks plus the commands' output.

## Layout

```
Sources/OpticalFlow/      the app: window, menus, views, recorder, exporter, voice, agent CLI
Sources/OpticalFlowKit/   rules with no UI: dates, repeats, priorities, voice intents, chapters
Tests/OpticalFlowKitTests unit tests for the Kit
tools/                    self-test, snapshots, grid lint, icon build
docs/                     brief, user stories, fix log, research, architecture reviews
.agents/skills/           the bama skills the app was built with (MIT, vendored)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the shape, [docs/STORIES.md](docs/STORIES.md) for every feature as a user story with its acceptance checks, and [docs/FIXLOG.md](docs/FIXLOG.md) for the bugs and the rule each one left behind.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and [TESTING.md](TESTING.md) for the checks every change runs. Be kind: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Credits

Built with [bama](https://github.com/daveebbelaar/bama) agent skills (MIT), vendored under `.agents/skills/`. The Touch Bar Control Strip item uses the same private DFRFoundation calls as Pock and BetterTouchTool.

## License

[MIT](LICENSE).
