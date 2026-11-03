import AppKit
import Foundation
import SwiftData
import OpticalFlowKit

/// Everything an agent can do in opticalflow. Each `run` is on the main actor with the app's model,
/// and calls the same functions the window's buttons call.
enum AgentCommands {
    static let pages = "inbox, today, upcoming, someday, sessions, recordings, or a project id"

    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "The open page, task counts, the running session, and whether a recording runs.",
                     example: "opticalflow status --json", readOnly: true) { _, model in
            let tasks = try model.context.fetch(FetchDescriptor<TaskItem>())
            var result: JSONObject = ["running": true, "page": pageName(model.sidebar),
                                      "open": tasks.filter { !$0.isDone }.count,
                                      "today": tasks.filter { $0.isIn(.today) }.count,
                                      "recording": model.recorder.isRecording]
            if let session = model.session {
                result["session"] = ["task": session.task?.title ?? "", "taskId": session.task.map { String($0.agentID.prefix(8)) } ?? "",
                                     "label": model.menuLabel ?? "", "paused": model.paused, "elapsedSeconds": model.elapsed]
            }
            return result
        },

        // MARK: Tasks
        AgentCommand(name: "tasks list", summary: "List tasks. Default: open tasks on every page.",
                     params: [.init(name: "page", help: "inbox, today, upcoming, someday"),
                              .init(name: "project", help: "a project id or name"),
                              .init(name: "column", help: "board column: backlog, todo, doing, done"),
                              .init(name: "search", help: "words that must appear in the title or notes"),
                              .init(name: "done", kind: .boolean, help: "completed tasks instead of open ones"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "opticalflow tasks list --page today --json", readOnly: true) { args, model in
            var tasks = try model.context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
            let done = try args.bool("done") ?? false
            tasks = tasks.filter { $0.isDone == done }
            if let name = args.string("page") {
                guard let list = SmartList(rawValue: name) else { throw AgentError.usage("no page \"\(name)\". Pages: inbox, today, upcoming, someday") }
                tasks = tasks.filter { $0.isIn(list, asOpen: done) }
            }
            if let project = args.string("project") { let p = try findProject(project, in: model); tasks = tasks.filter { $0.project == p } }
            if let column = args.string("column") {
                guard let c = BoardColumn(rawValue: column) else { throw AgentError.usage("no column \"\(column)\". Columns: backlog, todo, doing, done") }
                tasks = tasks.filter { $0.boardColumn == c }
            }
            if let text = args.string("search") { tasks = tasks.filter { $0.title.localizedStandardContains(text) || $0.notes.localizedStandardContains(text) } }
            return page(tasks.map(\.agentJSON), args: args, key: "tasks")
        },
        AgentCommand(name: "tasks show", summary: "Show one task with its sessions.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id (first 8 characters are enough)")],
                     example: "opticalflow tasks show 3f2a9c1e --json", readOnly: true) { args, model in
            let task = try findTask(try args.required("id"), in: model)
            var json = task.agentJSON
            let sessions = try model.context.fetch(FetchDescriptor<Session>()).filter { $0.task == task }
            json["sessions"] = sessions.map { ["startedAt": JSON.date($0.startedAt), "seconds": $0.seconds, "planned": $0.plannedMinutes] }
            return json
        },
        AgentCommand(name: "tasks add", summary: "Add a task and select it in the window.",
                     params: [.init(name: "title", required: true, help: "the title; may end with a date like \"tomorrow\" or \"fri\""),
                              .init(name: "notes", help: "notes under the title"),
                              .init(name: "project", help: "a project id or name"),
                              .init(name: "due", help: "the day to do it: today, tomorrow at 3pm, fri, in 3 days, 5 nov, or 2026-11-05"),
                              .init(name: "deadline", help: "the hard date, same words, or \"none\""),
                              .init(name: "repeat", help: "daily, weekdays, weekly, monthly, yearly, or none"),
                              .init(name: "someday", kind: .boolean, help: "park it in Someday"),
                              .init(name: "priority", help: "none, low, medium, or high (urgent)"),
                              .init(name: "subtasks", help: "steps separated by ; (\"write test; run it\")"),
                              .init(name: "record", kind: .boolean, help: "record the screen during its sessions")],
                     example: "opticalflow tasks add --title \"Fix the login loop\" --project OpticalFlow --due tomorrow --json") { args, model in
            guard let task = model.addTask(title: try args.required("title"), on: .list(.inbox)) else { throw AgentError.invalid("--title cannot be empty") }
            try apply(args, to: task, in: model)
            model.save()
            return task.agentJSON
        },
        AgentCommand(name: "tasks update", summary: "Change a task. Only the options you give change.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id"),
                              .init(name: "title", help: "new title"),
                              .init(name: "notes", help: "new notes"),
                              .init(name: "project", help: "a project id or name, or \"none\""),
                              .init(name: "due", help: "the day to do it, or \"none\" to clear it"),
                              .init(name: "deadline", help: "the hard date, or \"none\""),
                              .init(name: "repeat", help: "daily, weekdays, weekly, monthly, yearly, or none"),
                              .init(name: "someday", kind: .boolean, help: "true or false"),
                              .init(name: "doing", kind: .boolean, help: "on the board's Doing column"),
                              .init(name: "priority", help: "none, low, medium, or high (urgent)"),
                              .init(name: "subtasks", help: "add steps separated by ;"),
                              .init(name: "check", help: "mark a subtask done, by its number or words in its title"),
                              .init(name: "uncheck", help: "mark a subtask not done, by number or words"),
                              .init(name: "record", kind: .boolean, help: "record the screen during its sessions")],
                     example: "opticalflow tasks update 3f2a9c1e --due fri --record true --json") { args, model in
            let task = try findTask(try args.required("id"), in: model)
            if let title = args.string("title") {
                guard let clean = TaskTitle.clean(title) else { throw AgentError.invalid("--title cannot be empty") }
                task.title = clean
            }
            try apply(args, to: task, in: model)
            model.save()
            return task.agentJSON
        },
        AgentCommand(name: "tasks complete", summary: "Complete a task (adds a chapter if a recording runs).",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id")],
                     example: "opticalflow tasks complete 3f2a9c1e --json") { args, model in
            let task = try findTask(try args.required("id"), in: model)
            model.complete(task)
            return task.agentJSON
        },
        AgentCommand(name: "tasks reopen", summary: "Reopen a completed task.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id")],
                     example: "opticalflow tasks reopen 3f2a9c1e --json") { args, model in
            let task = try findTask(try args.required("id"), in: model)
            task.completedAt = nil
            model.save()
            return task.agentJSON
        },
        AgentCommand(name: "tasks move", summary: "Move a task to a board column or a page.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id"),
                              .init(name: "to", required: true, help: "backlog, todo, doing, done, inbox, today, upcoming, someday, or a project id")],
                     example: "opticalflow tasks move 3f2a9c1e --to doing --json") { args, model in
            let task = try findTask(try args.required("id"), in: model)
            let to = try args.required("to")
            if let column = BoardColumn(rawValue: to) {
                model.move([task.uuid.uuidString], toColumn: column)
            } else if let list = SmartList(rawValue: to) {
                model.move([task.uuid.uuidString], to: .list(list))
            } else {
                model.move([task.uuid.uuidString], to: .project(try findProject(to, in: model).uuid))
            }
            return task.agentJSON
        },
        AgentCommand(name: "tasks handoff", summary: "Hand a task to Claude Code or Codex in its own git worktree of the project's repository. Progress and the result land on the card; read them with agent jobs.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id")],
                     example: "opticalflow tasks handoff 3f2a9c1e --json") { args, model in
            let task = try findTask(try args.required("id"), in: model)
            do { try model.voice.handoff(task) } catch { throw AgentError.invalid(error.localizedDescription) }
            return ["started": true, "branch": task.agentBranch ?? "", "orchestrator": model.voice.jobs.last?.orchestrator.rawValue ?? ""]
        },
        AgentCommand(name: "tasks delete", summary: "Delete a task.",
                     params: [.init(name: "id", required: true, positional: true, help: "the task id")],
                     example: "opticalflow tasks delete 3f2a9c1e --yes --json", destructive: true) { args, model in
            let task = try findTask(try args.required("id"), in: model)
            let shown = task.agentJSON
            guard args.confirmed else { return ["deleted": false, "wouldDelete": shown, "hint": "add --yes to delete it"] }
            if model.selection == task.id { model.selection = nil }
            model.context.delete(task)
            model.save()
            return ["deleted": true, "task": shown]
        },

        // MARK: Projects
        AgentCommand(name: "projects list", summary: "List projects with open counts.",
                     example: "opticalflow projects list --json", readOnly: true) { _, model in
            ["projects": model.projects.map(\.agentJSON), "total": model.projects.count]
        },
        AgentCommand(name: "projects add", summary: "Create a project.",
                     params: [.init(name: "name", required: true, help: "the project name")],
                     example: "opticalflow projects add --name \"Stream setup\" --json") { args, model in
            model.projectPrompt = .new
            model.commitProjectPrompt(name: try args.required("name"))
            guard case .project(let id)? = model.sidebar, let project = model.project(id) else { throw AgentError.invalid("--name cannot be empty") }
            return project.agentJSON
        },
        AgentCommand(name: "projects update", summary: "Change a project: its repository folder for agent hand-offs.",
                     params: [.init(name: "id", required: true, positional: true, help: "a project id or name"),
                              .init(name: "repo", help: "path of the git repository, or \"none\"")],
                     example: "opticalflow projects update OpticalFlow --repo ~/code/opticalflow --json") { args, model in
            let project = try findProject(try args.required("id"), in: model)
            if let repo = args.string("repo") {
                let path = (repo as NSString).expandingTildeInPath
                if repo != "none", !Worktree.isRepository(path) { throw AgentError.invalid("\(path) is not a git repository") }
                model.setRepository(repo == "none" ? nil : path, for: project)
            }
            return project.agentJSON
        },
        AgentCommand(name: "projects board", summary: "A project's board: tasks per column.",
                     params: [.init(name: "id", required: true, positional: true, help: "a project id or name")],
                     example: "opticalflow projects board OpticalFlow --json", readOnly: true) { args, model in
            let project = try findProject(try args.required("id"), in: model)
            var board: JSONObject = ["project": project.agentJSON]
            for column in BoardColumn.allCases { board[column.rawValue] = project.tasks.filter { $0.boardColumn == column }.map(\.agentJSON) }
            return board
        },

        // MARK: Sessions and breaks
        AgentCommand(name: "session start", summary: "Start a focus session on a task (opens the recorder when the task records).",
                     params: [.init(name: "task", help: "the task id; default: the selected task")],
                     example: "opticalflow session start --task 3f2a9c1e --json") { args, model in
            let task = try args.string("task").map { try findTask($0, in: model) } ?? model.selectedTask
            guard let task else { throw AgentError.usage("no task selected. Give --task <id>") }
            model.startSession(on: task)
            return sessionJSON(model)
        },
        AgentCommand(name: "session stop", summary: "Stop the running session and any recording.",
                     example: "opticalflow session stop --json") { _, model in
            let json = sessionJSON(model)
            model.stopSession()
            return json
        },
        AgentCommand(name: "session pause", summary: "Pause the session.", example: "opticalflow session pause") { _, model in
            model.pause(); return sessionJSON(model)
        },
        AgentCommand(name: "session resume", summary: "Resume the session.", example: "opticalflow session resume") { _, model in
            model.resume(); return sessionJSON(model)
        },
        AgentCommand(name: "break start", summary: "Start a break; stops the session first.",
                     params: [.init(name: "minutes", kind: .integer, help: "length (default 5)")],
                     example: "opticalflow break start --minutes 15") { args, model in
            model.startBreak(minutes: try args.int("minutes", default: 5))
            return ["break": true, "remainingSeconds": model.breakRemaining]
        },
        AgentCommand(name: "sessions list", summary: "Past sessions, newest first.",
                     params: [.init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many")],
                     example: "opticalflow sessions list --limit 10 --json", readOnly: true) { args, model in
            let sessions = try model.context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            return page(sessions.map { ["task": $0.task?.title ?? "", "taskId": $0.task.map { String($0.agentID.prefix(8)) } ?? "",
                                        "startedAt": JSON.date($0.startedAt), "seconds": $0.seconds, "planned": $0.plannedMinutes,
                                        "running": $0.endedAt == nil] }, args: args, key: "sessions")
        },

        // MARK: Recordings
        AgentCommand(name: "record start", summary: "Open the system picker to start a screen recording. A person picks what to capture.",
                     example: "opticalflow record start") { _, model in
            guard !model.recorder.isRecording else { throw AgentError.invalid("a recording is already running") }
            model.recorder.pick()
            return ["pickerShown": true, "hint": "the recording starts when the person picks a display or window"]
        },
        AgentCommand(name: "record mark", summary: "Add a chapter marker at this moment of the running recording.",
                     params: [.init(name: "title", help: "the chapter title; default \"Marker N\"")],
                     example: "opticalflow record mark --title \"The bug appears\" --json") { args, model in
            guard let mark = model.mark(args.string("title")) else { throw AgentError.unavailable("no recording is running") }
            return ["title": mark.title, "offset": Int(mark.offset), "clock": Countdown.clock(Int(mark.offset), padded: false)]
        },
        AgentCommand(name: "record stop", summary: "Stop the running screen recording.",
                     example: "opticalflow record stop --json") { _, model in
            guard model.recorder.isRecording else { throw AgentError.invalid("no recording runs") }
            let name = model.recorder.recording?.url.lastPathComponent ?? ""
            model.toggleRecording()
            return ["stopped": true, "file": name]
        },
        AgentCommand(name: "recordings list", summary: "Recordings, newest first.",
                     params: [.init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many")],
                     example: "opticalflow recordings list --json", readOnly: true) { args, model in
            let recordings = try model.context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            return page(recordings.map(\.agentJSON), args: args, key: "recordings")
        },
        AgentCommand(name: "recordings chapters", summary: "The YouTube chapter list of a recording.",
                     params: [.init(name: "id", required: true, positional: true, help: "the recording id")],
                     example: "opticalflow recordings chapters 9c1e3f2a", readOnly: true) { args, model in
            let recording = try findRecording(try args.required("id"), in: model)
            return ["id": String(recording.agentID.prefix(8)), "chapters": recording.chapterText]
        },
        AgentCommand(name: "recordings export", summary: "Export a trimmed copy; the new file appears in Recordings when done.",
                     params: [.init(name: "id", required: true, positional: true, help: "the recording id"),
                              .init(name: "start", help: "start second (default 0)"),
                              .init(name: "end", help: "end second (default the length)"),
                              .init(name: "camera", kind: .boolean, help: "composite the camera in its corner"),
                              .init(name: "follow-cursor", kind: .boolean, help: "2x zoom following the pointer"),
                              .init(name: "youtube", kind: .boolean, help: "1080p H.264 preset (default true)"),
                              .init(name: "silence", kind: .boolean, help: "cut every pause of a second or more")],
                     example: "opticalflow recordings export 9c1e3f2a --start 10 --end 120 --camera --silence --json") { args, model in
            let recording = try findRecording(try args.required("id"), in: model)
            let start = Double(args.string("start") ?? "0") ?? 0
            let end = Double(args.string("end") ?? "") ?? recording.duration
            guard end - start >= 1 else { throw AgentError.invalid("--end must be at least one second after --start") }
            let camera = try args.bool("camera") ?? false, cursor = try args.bool("follow-cursor") ?? false, youtube = try args.bool("youtube") ?? true
            let silence = try args.bool("silence") ?? false
            Task { @MainActor in _ = try? await model.trim(recording, start: start, end: end, withCamera: camera, followCursor: cursor, youtube: youtube, removeSilence: silence) }
            return ["started": true, "from": String(recording.agentID.prefix(8)), "start": start, "end": end,
                    "hint": "run `opticalflow recordings list` in a minute to see the new file"]
        },

        // MARK: Voice
        AgentCommand(name: "agent say", summary: "Send a sentence to the voice agent, as if spoken. The built-in orchestrator answers at once; Claude Code or Codex answer in the panel.",
                     params: [.init(name: "text", required: true, positional: true, help: "what to do, in plain words"),
                              .init(name: "builtin", kind: .boolean, help: "use the built-in parser whatever Settings says")],
                     example: "opticalflow agent say \"make the login loop urgent\" --json") { args, model in
            let text = try args.required("text")
            if try args.bool("builtin") == true || model.voice.orchestrator == .builtin {
                let intent = VoiceIntent.parse(text)
                return ["intent": "\(intent)", "reply": model.perform(intent)]
            }
            model.voice.send(text)
            if model.voice.handledLocally { return ["fast": true, "reply": model.voice.reply] }
            return ["sentTo": model.voice.orchestrator.title, "reply": "pending; poll agent state for steps and reply"]
        },

        AgentCommand(name: "agent listen", summary: "Open the voice panel and listen. With --probe nothing is sent; read the result with agent state.",
                     params: [.init(name: "probe", kind: .boolean, help: "listen without acting, for diagnosis"),
                              .init(name: "microphone", help: "words from a microphone's name, or \"default\"; remembered for recordings too")],
                     example: "opticalflow agent listen --probe --json") { args, model in
            let probe = try args.bool("probe") == true
            if let name = args.string("microphone") {
                if name == "default" { Microphone.preferredUID = nil }
                else if let device = Microphone.devices().first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { Microphone.preferredUID = device.uid }
                else { throw AgentError.invalid("no microphone matches \"\(name)\": \(Microphone.devices().map(\.name).joined(separator: ", "))") }
            }
            model.voice.show(listening: false)
            model.voice.autoSend = !probe
            Task { await model.voice.startListening() }
            return ["listening": true, "probe": probe]
        },
        AgentCommand(name: "agent state", summary: "Permissions, availability, transcript, and errors of the voice agent.",
                     example: "opticalflow agent state --json", readOnly: true) { _, model in
            model.voice.state
        },
        AgentCommand(name: "agent transcribe", summary: "Diagnosis: recognize speech in a sound file; read the result with agent state.",
                     params: [.init(name: "file", required: true, positional: true, help: "an audio file path")],
                     example: "opticalflow agent transcribe /tmp/test.aiff --json") { args, model in
            model.voice.transcribe(file: URL(fileURLWithPath: try args.required("file")))
            return ["started": true]
        },
        AgentCommand(name: "agent jobs", summary: "AI requests running or finished in the background, with their steps and answers.",
                     example: "opticalflow agent jobs --json", readOnly: true) { _, model in
            ["jobs": model.voice.state["jobs"] ?? []]
        },
        AgentCommand(name: "agent close", summary: "Stop listening and close the voice panel.",
                     example: "opticalflow agent close --json") { _, model in
            model.voice.close()
            return ["closed": true]
        },

        // MARK: Window
        AgentCommand(name: "open", summary: "Show a page in the window.",
                     params: [.init(name: "page", required: true, positional: true, help: pages),
                              .init(name: "board", kind: .boolean, help: "show a project as a board")],
                     example: "opticalflow open today") { args, model in
            let name = try args.required("page")
            switch name {
            case "inbox", "today", "upcoming", "someday": model.sidebar = .list(SmartList(rawValue: name)!)
            case "sessions": model.sidebar = .sessions
            case "recordings": model.sidebar = .recordings
            default: model.sidebar = .project(try findProject(name, in: model).uuid)
            }
            if let board = try args.bool("board") { model.showsBoard = board }
            NSApp.activate()
            return ["page": pageName(model.sidebar)]
        },
    ]

    // MARK: Helpers

    static func pageName(_ page: Page?) -> String {
        switch page {
        case .list(let list)?: list.rawValue
        case .sessions?: "sessions"
        case .recordings?: "recordings"
        case .project(let id)?: "project:" + id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)
        case nil: "none"
        }
    }

    static func page(_ rows: [JSONObject], args: Args, key: String) -> JSONObject {
        let limit = (try? args.int("limit", default: 50)) ?? 50
        let offset = (try? args.int("offset", default: 0)) ?? 0
        let slice = rows.dropFirst(offset).prefix(limit)
        var result: JSONObject = [key: Array(slice), "total": rows.count]
        if offset + slice.count < rows.count { result["nextOffset"] = offset + slice.count }
        return result
    }

    static func sessionJSON(_ model: AppModel) -> JSONObject {
        guard let session = model.session else { return ["session": false] }
        return ["session": true, "task": session.task?.title ?? "", "taskId": session.task.map { String($0.agentID.prefix(8)) } ?? "",
                "label": model.menuLabel ?? "", "paused": model.paused, "elapsedSeconds": model.elapsed, "recording": model.recorder.isRecording]
    }

    /// Shared by add and update: project, due, someday, doing, record, notes.
    static func apply(_ args: Args, to task: TaskItem, in model: AppModel) throws {
        if let notes = args.string("notes") { task.notes = notes }
        if let project = args.string("project") { task.project = project == "none" ? nil : try findProject(project, in: model) }
        if let due = args.string("due") {
            if due == "none" { task.due = nil; task.hasDueTime = false }
            else { let parsed = try parseDue(due); task.due = parsed.date; task.hasDueTime = parsed.hasTime }
        }
        if let someday = try args.bool("someday") { task.isSomeday = someday }
        if let doing = try args.bool("doing") { task.isDoing = doing }
        if let record = try args.bool("record") { task.recordsSession = record }
        if let text = args.string("deadline") { task.deadline = text == "none" ? nil : try parseDue(text).date }
        if let text = args.string("repeat") {
            guard let rule = RepeatRule.parse(text) else { throw AgentError.usage("--repeat takes daily, weekdays, weekly, monthly, yearly, or none") }
            task.repeatRule = rule
        }
        if let text = args.string("subtasks") { task.subtasks += Checklist.parse(text) }
        for (key, done) in [("check", true), ("uncheck", false)] {
            guard let text = args.string(key) else { continue }
            guard let index = Checklist.index(of: text, in: task.subtasks) else { throw AgentError.invalid("no subtask matches \"\(text)\"") }
            task.subtasks[index].isDone = done
        }
        if let text = args.string("priority") {
            guard let priority = Priority.parse(text) else { throw AgentError.usage("--priority takes none, low, medium, or high") }
            task.priority = priority
        }
    }

    static func parseDue(_ text: String) throws -> (date: Date, hasTime: Bool) {
        let parsed = DueDateParser.parse("x \(text)")
        if let date = parsed.due { return (date, parsed.hasTime) }
        throw AgentError.usage("could not read the date \"\(text)\". Try today, tomorrow at 3pm, fri, in 3 days, 5 nov, or 2026-11-05")
    }

    static func findTask(_ id: String, in model: AppModel) throws -> TaskItem {
        try find(id, in: try model.context.fetch(FetchDescriptor<TaskItem>()), noun: "task", list: "tasks list")
    }

    static func findRecording(_ id: String, in model: AppModel) throws -> Recording {
        try find(id, in: try model.context.fetch(FetchDescriptor<Recording>()), noun: "recording", list: "recordings list")
    }

    /// A project by id prefix or by name (case-insensitive).
    static func findProject(_ key: String, in model: AppModel) throws -> Project {
        if let byName = model.projects.first(where: { $0.name.localizedCaseInsensitiveCompare(key) == .orderedSame }) { return byName }
        return try find(key, in: model.projects, noun: "project", list: "projects list")
    }

    static func find<T: AgentIdentified>(_ id: String, in rows: [T], noun: String, list: String) throws -> T {
        let matches = rows.filter { $0.agentID.hasPrefix(id.lowercased()) }
        guard let row = matches.first else { throw AgentError.notFound("no \(noun) with id \(id). Run `opticalflow \(list)`") }
        guard matches.count == 1 else { throw AgentError.usage("\(matches.count) \(noun)s start with \(id). Give more characters") }
        return row
    }
}

nonisolated protocol AgentIdentified { var agentID: String { get } }

extension TaskItem: AgentIdentified {
    nonisolated var agentID: String { uuid.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    nonisolated var agentJSON: JSONObject {
        var json: JSONObject = ["id": String(agentID.prefix(8)), "title": title, "notes": notes, "done": isDone,
                                "someday": isSomeday, "doing": isDoing, "records": recordsSession, "column": boardColumn.rawValue,
                                "priority": priority.title.lowercased(),
                                "subtasks": subtasks.map { ["title": $0.title, "done": $0.isDone] as JSONObject }, "hasDueTime": hasDueTime,
                                "createdAt": JSON.date(createdAt)]
        if let due { json["due"] = JSON.date(due) }
        if let deadline { json["deadline"] = JSON.date(deadline) }
        if repeatRule != .none { json["repeat"] = repeatRule.rawValue }
        if let agentBranch { json["branch"] = agentBranch }
        if let project { json["project"] = project.name; json["projectId"] = String(project.agentID.prefix(8)) }
        if let completedAt { json["completedAt"] = JSON.date(completedAt) }
        return json
    }
}

extension Project: AgentIdentified {
    nonisolated var agentID: String { uuid.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    nonisolated var agentJSON: JSONObject {
        var json: JSONObject = ["id": String(agentID.prefix(8)), "name": name, "color": colorName, "open": openCount]
        if let repoPath { json["repo"] = repoPath }
        return json
    }
}

extension Recording: AgentIdentified {
    nonisolated var agentID: String { uuid.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    nonisolated var agentJSON: JSONObject {
        ["id": String(agentID.prefix(8)), "task": title, "file": url.path, "exists": fileExists, "startedAt": JSON.date(startedAt),
         "seconds": Int(duration), "chapters": chapters.count, "camera": hasCamera, "cursorTrack": cursorURL != nil]
    }
}
