---
name: opticalflow
description: Drive the OpticalFlow app on this Mac from the shell with the `opticalflow` command: list, add, move, and complete tasks, run focus sessions and breaks, start or stop screen recordings, read a project's kanban board, and export recordings. Use when the user asks about their tasks, sessions, or recordings, or names OpticalFlow.
---

# OpticalFlow

`opticalflow` runs commands in the OpticalFlow app. Changes show in its window at once.
If the app is closed, the command opens it in the background.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and `error.message`, and do what the message says.
- Find ids with `opticalflow tasks list` or `--search`. An id is 8 characters. Projects also go by name.
- `tasks delete` only reports what it would do. Show the user that report and ask before you run it again with `--yes`.
- `record start` shows the system picker: a person must pick what to capture. Never loop on it.
- To try something without real data, add `APP_STORE=/tmp/opticalflow-test.store` in front of the command.

## Main commands

| Command | Does |
| --- | --- |
| `opticalflow status --json` | Open page, counts, the running session, recording state |
| `opticalflow tasks list [--page today] [--project P] [--column doing] [--search T] --json` | Find tasks |
| `opticalflow tasks add --title T [--project P] [--due tomorrow] [--priority high] [--record] --json` | Add one |
| `opticalflow tasks update <id> [--priority high] [--notes "…"] [--due fri] --json` | Change one; urgent means `--priority high` |
| `opticalflow agent say "make the login loop urgent" --json` | Send a sentence to the voice agent |
| `opticalflow tasks move <id> --to doing` | Board column or page: backlog, todo, doing, done, inbox, today, someday, a project |
| `opticalflow session start --task <id> --json` | Start a focus session (and the recorder when the task records) |
| `opticalflow projects board <name> --json` | A project's board, tasks per column |
| `opticalflow recordings chapters <id>` | The YouTube chapter list |
| `opticalflow open <page> [--board]` | Show a page in the window |

Everything else: `opticalflow help`, and `opticalflow help <command>` for its options.

## MCP (Claude Desktop)

```
claude mcp add --scope user opticalflow -- ~/Applications/OpticalFlow.app/Contents/MacOS/OpticalFlow mcp
```
