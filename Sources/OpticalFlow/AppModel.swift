import AppKit
import CoreGraphics
import Foundation
import SwiftData
import OpticalFlowKit

/// App-wide state that menus, toolbars, the menu bar, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    var sidebar: Page? = .list(.inbox) {
        didSet { hideDoneBefore = .now; selection = nil }
    }
    var selection: PersistentIdentifier?
    /// Project pages show the board instead of the list.
    var showsBoard = UserDefaults.standard.bool(forKey: "showsBoard") {
        didSet { UserDefaults.standard.set(showsBoard, forKey: "showsBoard") }
    }
    /// Command-F. Non-empty: every page shows matching open tasks instead of its own list.
    var search = ""
    /// Non-nil while the inline new-task row is open.
    var draftTitle: String?
    /// Which board column shows the draft row.
    var draftColumn: BoardColumn = .todo
    /// Done tasks completed after this still show, dimmed, for two seconds.
    var hideDoneBefore = Date.now
    var projectPrompt: ProjectPrompt?
    private var undoCompleted: [TaskItem] = []

    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    // Session
    private(set) var session: Session?
    private var clock: SessionClock?
    var paused: Bool { clock?.isPaused ?? false }
    private var now = Date.now
    private var ticker: Task<Void, Never>?
    private var notifiedDone = false
    /// A break runs after a session: the menu bar counts it down.
    private(set) var breakUntil: Date?
    /// Set when the session paused itself after five idle minutes; the user keeps or discards that time.
    private(set) var idleSince: Date?
    static let idleLimit: TimeInterval = 300
    /// Tests only.
    var idleOverride: TimeInterval?
    let recorder = Recorder()
    @ObservationIgnored private var _miniTimer: MiniTimer?
    var miniTimer: MiniTimer {
        if let _miniTimer { return _miniTimer }
        let timer = MiniTimer(model: self)
        _miniTimer = timer
        return timer
    }
    @ObservationIgnored private var _voice: VoiceAgent?
    var voice: VoiceAgent {
        if let _voice { return _voice }
        let agent = VoiceAgent(model: self)
        _voice = agent
        return agent
    }
    @ObservationIgnored private var _quickEntry: QuickEntry?
    var quickEntry: QuickEntry {
        if let _quickEntry { return _quickEntry }
        let entry = QuickEntry(model: self)
        _quickEntry = entry
        return entry
    }

    init(container: ModelContainer) {
        self.container = container
        recorder.onStart = { [weak self] url in
            guard let self else { return nil }
            let recording = Recording(url: url, session: session)
            context.insert(recording)
            save()
            // Floating controls while recording, like a capture bar: timer, pause, stop recording.
            miniTimer.show()
            return recording
        }
        recorder.onStop = { [weak self] recording, duration in
            recording.duration = duration
            self?.save()
            if self?.session == nil { self?.miniTimer.hide() }
        }
        // A sleeping Mac never works; stop the session and any recording.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopSession() }
        }
    }

    func save() { try? context.save() }

    // MARK: Tasks

    var selectedTask: TaskItem? { selected(TaskItem.self) }
    var selectedRecording: Recording? { selected(Recording.self) }
    var selectedSession: Session? { selected(Session.self) }

    /// Shows a task on a page that lists it and selects it.
    func showTask(_ task: TaskItem) {
        if let project = task.project { sidebar = .project(project.uuid) }
        else if task.isIn(.today) { sidebar = .list(.today) }
        else if task.isIn(.someday) { sidebar = .list(.someday) }
        else if task.isIn(.upcoming) { sidebar = .list(.upcoming) }
        else { sidebar = .list(.inbox) }
        selection = task.id
    }

    func delete(_ task: TaskItem) {
        if session?.task == task { stopSession() }
        if selection == task.id { selection = nil }
        undoCompleted.removeAll { $0 == task }
        for session in task.sessions { session.task = nil }   // keep the time record, drop the pointer
        context.delete(task)
        save()
    }


    func deleteSession(_ session: Session) {
        if session == self.session { stopSession() }
        if selection == session.id { selection = nil }
        context.delete(session)
        save()
    }

    /// The selected row as its type. nil for another type (SwiftData aborts on a typed lookup of the
    /// wrong entity) and nil once the row is deleted. A fetch, not `registeredModel`, because a row
    /// nothing else holds is unregistered even though it exists.
    private func selected<T: PersistentModel>(_ type: T.Type) -> T? {
        guard let selection, selection.entityName == String(describing: T.self) else { return nil }
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == selection })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    var projects: [Project] {
        (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func project(_ id: UUID) -> Project? {
        projects.first { $0.uuid == id }
    }

    /// Adds a task to a page. Today sets due = today, Upcoming tomorrow, Someday the flag, a project the project.
    /// nil when the title is empty.
    @discardableResult
    func addTask(title: String, on page: Page? = nil) -> TaskItem? {
        guard let clean = TaskTitle.clean(title) else { return nil }
        let parsed = DueDateParser.parse(clean)
        let task = TaskItem(title: parsed.title)
        task.due = parsed.due
        task.hasDueTime = parsed.hasTime
        task.deadline = parsed.deadline
        task.repeatRule = parsed.repeatRule
        switch page ?? sidebar ?? .list(.inbox) {
        case .list(.today): task.due = task.due ?? .now
        case .list(.upcoming): task.due = task.due ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)
        case .list(.someday): task.isSomeday = true
        case .project(let id): task.project = project(id)
        default: break
        }
        context.insert(task)
        save()
        selection = task.id
        return task
    }

    func visible(_ task: TaskItem, on page: Page) -> Bool {
        let fresh = task.completedAt.map { $0 > hideDoneBefore } ?? false
        switch page {
        case .list(let list): return task.isIn(list, asOpen: fresh)
        case .project(let id): return task.project?.uuid == id && (!task.isDone || fresh)
        default: return false
        }
    }

    func tasks(for page: Page) -> [TaskItem] {
        let all = (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { visible($0, on: page) }
    }

    /// The task the Focus view offers to start: a Doing task, else the first open task,
    /// on the current page, then Today, then Inbox.
    var upNext: TaskItem? {
        var pages: [Page] = [.list(.today), .list(.inbox)]
        if let sidebar, sidebar.showsTasks { pages.insert(sidebar, at: 0) }
        for page in pages {
            let open = tasks(for: page).filter { !$0.isDone }
            if let task = open.first(where: \.isDoing) ?? open.max(by: { $0.priority < $1.priority }) { return task }
        }
        return nil
    }

    /// Open tasks whose title or notes contain the words of `search`, any order, case-insensitive.
    func matches(_ task: TaskItem) -> Bool {
        let words = search.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        let text = (task.title + " " + task.notes).lowercased()
        return !task.isDone && words.allSatisfy { text.contains($0) }
    }

    func complete(_ task: TaskItem) {
        guard !task.isDone else { return }
        if let recording = recorder.recording {
            recording.chapters.append(ChapterMark(title: task.title, offset: Date.now.timeIntervalSince(recording.startedAt)))
        }
        // A repeating task comes back on its next day instead of closing.
        if task.repeatRule != .none, let next = task.repeatRule.next(after: task.due ?? .now) {
            if let deadline = task.deadline { task.deadline = task.repeatRule.next(after: deadline) }
            task.due = next
            task.isDoing = false
            for index in task.subtasks.indices { task.subtasks[index].isDone = false }
            save()
            return
        }
        task.completedAt = .now
        task.isDoing = false
        undoCompleted.append(task)
        save()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.hideDoneBefore = .now
        }
    }

    func completeSelected() {
        if let task = selectedTask { complete(task) }
    }

    /// Undoes the last completion. False when there is nothing to undo.
    @discardableResult
    func undoComplete() -> Bool {
        guard let task = undoCompleted.popLast() else { return false }
        task.completedAt = nil
        save()
        return true
    }

    /// Drop or "Move to": tasks by uuid string onto a page. Inbox clears project and Someday; Today and
    /// Upcoming set the date; Someday flags it and clears the date; a project assigns it.
    func move(_ ids: [String], to page: Page) {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in all where uuids.contains(task.uuid) {
            switch page {
            case .list(.inbox): task.project = nil; task.isSomeday = false
            case .list(.today): task.due = .now; task.isSomeday = false
            case .list(.upcoming):
                if !task.isIn(.upcoming, asOpen: true) { task.due = Calendar.current.date(byAdding: .day, value: 1, to: .now) }
                task.isSomeday = false
            case .list(.someday): task.isSomeday = true; task.due = nil
            case .project(let id): task.project = project(id)
            default: break
            }
        }
        save()
    }

    /// Adds a task to a project in one board column.
    @discardableResult
    func addTask(title: String, project: Project, column: BoardColumn) -> TaskItem? {
        guard let task = addTask(title: title, on: .project(project.uuid)) else { return nil }
        move([task.uuid.uuidString], toColumn: column)
        return task
    }

    /// The open task whose title best matches spoken words: a title containing the words,
    /// else the one sharing the most words. The current page wins ties.
    func task(matching text: String) -> TaskItem? {
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !["the", "a", "an", "task", "my", "on", "to"].contains($0) })
        guard !words.isEmpty else { return nil }
        let all = ((try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).filter { !$0.isDone }
        func score(_ task: TaskItem) -> Int {
            let title = task.title.lowercased()
            let titleWords = Set(title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let overlap = words.intersection(titleWords).count
            let onPage = sidebar.map { visible(task, on: $0) } ?? false
            return (title.contains(text.lowercased()) ? 100 : 0) + overlap * 10 + (onPage ? 1 : 0)
        }
        let best = all.max { score($0) < score($1) }
        return best.flatMap { score($0) >= 10 ? $0 : nil }
    }

    /// Titles of open tasks, newest first, for the speech recognizer's vocabulary.
    func recentTitles(limit: Int) -> [String] {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.completedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(\.title)
    }

    /// The project whose name sounds like `text`: exact, contained, or within a couple of letters,
    /// so "for than" still finds "Fordan".
    func project(matching text: String) -> Project? {
        func key(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }
        let wanted = key(text)
        guard !wanted.isEmpty else { return nil }
        let scored = projects.map { project -> (Project, Int) in
            let name = key(project.name)
            if name == wanted { return (project, 0) }
            if name.contains(wanted) || wanted.contains(name) { return (project, 1) }
            return (project, TaskTitle.distance(name, wanted))
        }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        return best.1 <= max(1, key(best.0.name).count / 3) ? best.0 : nil
    }

    /// Splits "buy pizza in Fordan" or "to Fordan: buy pizza" into the title and its project.
    func splitProject(from title: String) -> (title: String, project: Project?) {
        let joiners = "(?:in|into|to|under|for|on|inside)"
        // 1: "buy pizza in Fordan"  2: "to Fordan: buy pizza"  3: "Fordan: buy pizza" (the intent rule ate the "to")
        let patterns = [
            #"^(.+?)\s+\#(joiners)\s+(?:the\s+)?(?:project\s+)?(.+?)(?:\s+project)?$"#,
            #"^\#(joiners)\s+(?:the\s+)?(?:project\s+)?(.+?)(?:\s+project)?[:,]\s*(.+)$"#,
            #"^(?:the\s+)?(?:project\s+)?([^:,]+?)(?:\s+project)?[:,]\s*(.+)$"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let a = Range(m.range(at: 1), in: title), let b = Range(m.range(at: 2), in: title) else { continue }
            let (rest, name) = index == 0 ? (String(title[a]), String(title[b])) : (String(title[b]), String(title[a]))
            if let project = project(matching: name), !rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return (rest.trimmingCharacters(in: .whitespaces), project)
            }
        }
        return (title, nil)
    }

    /// A chapter marker in the running recording, "mark that" while streaming. Returns the mark.
    @discardableResult
    func mark(_ title: String? = nil) -> ChapterMark? {
        guard let recording = recorder.recording else { return nil }
        let offset = Date.now.timeIntervalSince(recording.startedAt)
        let mark = ChapterMark(title: title ?? "Marker \(recording.chapters.count + 1)", offset: offset)
        recording.chapters.append(mark)
        save()
        return mark
    }

    /// Runs one built-in voice intent and returns what to say back.
    func perform(_ intent: VoiceIntent) -> String {
        func found(_ match: String) -> TaskItem? {
            let task = self.task(matching: match)
            if let task { selection = task.id }
            return task
        }
        switch intent {
        case .add(let title):
            let split = splitProject(from: title)
            guard let task = addTask(title: split.title, on: split.project.map { .project($0.uuid) } ?? .list(.inbox)) else { return "Nothing to add." }
            let when = task.due.map { ", due " + (task.hasDueTime ? $0.formatted(date: .abbreviated, time: .shortened) : $0.formatted(date: .abbreviated, time: .omitted)) } ?? ""
            return "Added “\(task.title)” to \(split.project?.name ?? "Inbox")\(when)."
        case .complete(let match):
            guard let task = found(match) else { return "No open task matches “\(match)”." }
            complete(task)
            return "Completed “\(task.title)”."
        case .start(let match):
            guard let task = found(match) else { return "No open task matches “\(match)”." }
            startSession(on: task)
            return "Started a \(plannedMinutes) minute session on “\(task.title)”."
        case .stop:
            guard session != nil else { return "No session is running." }
            stopSession()
            return "Session stopped."
        case .mark(let title):
            guard let mark = mark(title) else { return "No recording is running." }
            return "Marked “\(mark.title)” at \(Countdown.clock(Int(mark.offset), padded: false))."
        case .setPriority(let match, let priority):
            guard let task = found(match) else { return "No open task matches “\(match)”." }
            task.priority = priority
            save()
            return "“\(task.title)” is now \(priority.title.lowercased()) priority."
        case .addSubtask(let match, let title):
            guard let task = found(match) else { return "No open task matches “\(match)”." }
            guard let clean = TaskTitle.clean(title) else { return "Nothing to add." }
            task.subtasks.append(ChecklistItem(title: clean))
            save()
            return "Added “\(clean)” under “\(task.title)”."
        case .addNote(let match, let note):
            guard let task = found(match) else { return "No open task matches “\(match)”." }
            task.notes = task.notes.isEmpty ? note : task.notes + "\n" + note
            save()
            return "Added a note to “\(task.title)”."
        }
    }

    /// A board drop. Backlog = someday; To Do = open; Doing = the doing flag; Done = completed.
    func move(_ ids: [String], toColumn column: BoardColumn) {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in all where uuids.contains(task.uuid) {
            switch column {
            case .backlog: task.isSomeday = true; task.isDoing = false; task.completedAt = nil
            case .todo: task.isSomeday = false; task.isDoing = false; task.completedAt = nil
            case .doing: task.isSomeday = false; task.isDoing = true; task.completedAt = nil
            case .done: if !task.isDone { complete(task) }
            }
        }
        save()
    }

    func setDue(_ date: Date?) {
        selectedTask?.due = date
        save()
    }

    func commitProjectPrompt(name: String) {
        defer { projectPrompt = nil }
        guard let clean = TaskTitle.clean(name) else { return }
        switch projectPrompt {
        case .new:
            let project = Project(name: clean, color: ProjectColor.allCases[projects.count % ProjectColor.allCases.count])
            context.insert(project)
            save()
            sidebar = .project(project.uuid)
        case .rename(let project):
            project.name = clean
            save()
        case nil: break
        }
    }

    /// Asks for the project's repository folder with the system open panel.
    func chooseRepository(for project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use This Repository"
        panel.message = "The git repository agents work in for “\(project.name)”."
        if let current = project.repoPath { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRepository(url.path, for: project)
    }

    func setRepository(_ path: String?, for project: Project) {
        project.repoPath = path
        save()
    }

    /// Branch summary for a task an agent worked on, nil when there is none.
    func branchSummary(for task: TaskItem) -> (commits: Int, stat: String, base: String)? {
        guard task.agentBranch != nil, let repo = task.project?.repoPath else { return nil }
        return Worktree.summary(repo: repo, id: String(task.agentID.prefix(8)))
    }

    func openPullRequest(for task: TaskItem) throws {
        guard let repo = task.project?.repoPath else { return }
        try Worktree.openPullRequest(repo: repo, id: String(task.agentID.prefix(8)))
    }

    func discardBranch(for task: TaskItem) {
        guard let repo = task.project?.repoPath else { return }
        Worktree.discard(repo: repo, id: String(task.agentID.prefix(8)))
        task.agentBranch = nil
        save()
    }

    func revealWorktree(for task: TaskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([Worktree.folder(for: String(task.agentID.prefix(8)))])
    }

    func deleteProject(_ project: Project) {
        if sidebar == .project(project.uuid) { sidebar = .list(.inbox) }
        context.delete(project)
        save()
    }

    /// The first row of a page, for snapshots.
    func firstID(for page: Page) -> PersistentIdentifier? {
        switch page {
        case .recordings: (try? context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first?.id
        case .sessions: (try? context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first?.id
        default: tasks(for: page).first?.id
        }
    }

    // MARK: Session

    var plannedMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "plannedMinutes")
        return stored > 0 ? stored : 25
    }

    var elapsed: Int { clock?.elapsed(at: now) ?? 0 }

    /// The menu bar text. nil when nothing runs.
    var menuLabel: String? {
        if let session {
            return Countdown.label(planned: session.plannedMinutes * 60, elapsed: elapsed, paused: paused, recording: recorder.isRecording)
        }
        if let breakUntil {
            return "☕ " + Countdown.clock(breakRemaining)
        }
        return nil
    }

    var breakRemaining: Int { breakUntil.map { max(0, Int(ceil($0.timeIntervalSince(now)))) } ?? 0 }

    /// Seconds left in the session; negative in overtime. nil without a session.
    var remaining: Int? { session.map { $0.plannedMinutes * 60 - elapsed } }
    /// "24:59" or "+00:05", with no symbols, for large displays.
    var clockLabel: String? { remaining.map { $0 >= 0 ? Countdown.clock($0) : "+" + Countdown.clock(-$0) } }
    /// 0 to 1 through the planned time.
    var sessionProgress: Double { session.map { min(1, Double(elapsed) / Double(max(1, $0.plannedMinutes * 60))) } ?? 0 }

    /// Stops the session if one runs, then counts down a break.
    func startBreak(minutes: Int) {
        stopSession()
        breakUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        now = .now
        runTicker()
    }

    func endBreak() {
        breakUntil = nil
        if session == nil { ticker?.cancel(); ticker = nil }
    }

    private func runTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func startSession(on task: TaskItem? = nil) {
        guard let task = task ?? selectedTask else { return }
        if session != nil { stopSession() }
        let new = Session(task: task, plannedMinutes: plannedMinutes)
        context.insert(new)
        save()
        task.isDoing = true
        if task.recordsSession, !recorder.isRecording { recorder.pick() }
        session = new
        clock = SessionClock(planned: new.plannedMinutes * 60, startedAt: .now)
        notifiedDone = false
        now = .now
        breakUntil = nil
        runTicker()
        if !Store.isOverridden { Notifier.requestAuthorization() }
    }

    /// Seconds since the last key or mouse event on this Mac.
    private var idleSeconds: TimeInterval {
        if let idleOverride { return idleOverride }
        return [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    /// Keep: the idle time counts as work. Discard: it does not. Both resume.
    func keepIdleTime() {
        if let idleSince { clock?.banked += Int(Date.now.timeIntervalSince(idleSince)) }
        idleSince = nil
        resume()
    }

    func discardIdleTime() {
        idleSince = nil
        resume()
    }

    private func tick() {
        now = .now
        if session != nil, !paused, idleSince == nil, idleSeconds >= Self.idleLimit {
            idleSince = now.addingTimeInterval(-idleSeconds)
            pause()
            if !Store.isOverridden { Notifier.post("Away for 5 minutes", "Keep that time in the session, or discard it?", category: Notifier.idle) }
        }
        if let session, let clock, !notifiedDone, clock.isOver(at: now) {
            notifiedDone = true
            if !Store.isOverridden { Notifier.post("Session done", session.task?.title ?? "", category: Notifier.sessionDone) }
        }
        if let breakUntil, breakUntil <= now {
            endBreak()
            if !Store.isOverridden { Notifier.post("Break over", "Pick the next task.") }
        }
    }

    func pause() {
        guard session != nil else { return }
        clock?.pause(at: .now)
        session?.seconds = clock?.banked ?? 0
    }

    func resume() {
        guard session != nil else { return }
        now = .now
        clock?.resume(at: now)
    }

    func stopSession() {
        guard let session else { return }
        session.seconds = clock?.stop(at: .now) ?? session.seconds
        session.endedAt = .now
        save()
        self.session = nil
        clock = nil
        if breakUntil == nil { ticker?.cancel(); ticker = nil }
        if recorder.isRecording { Task { await recorder.stop() } }
    }

    /// The hotkey: start on the selected task, or stop.
    func toggleSession() {
        if session == nil { startSession() } else { stopSession() }
    }

    func toggleRecording() {
        if recorder.isRecording { Task { await recorder.stop() } } else { recorder.pick() }
    }

    // MARK: Export

    /// Writes "<name> <start> to <end>[ with camera].mp4" next to the recording and returns its row, chapters shifted.
    /// With the camera, the sidecar is laid over the bottom-right corner and the file is re-encoded.
    func trim(_ recording: Recording, start: TimeInterval, end: TimeInterval, withCamera: Bool = false, followCursor: Bool = false, youtube: Bool = false) async throws -> Recording {
        let stem = recording.url.deletingPathExtension().lastPathComponent
        let camera = withCamera && recording.hasCamera ? recording.cameraURL : nil
        let cursor = followCursor ? recording.cursorTrack : nil
        var suffix = "\(Countdown.clock(Int(start))) to \(Countdown.clock(Int(end)))".replacingOccurrences(of: ":", with: ".")
        if camera != nil { suffix += " with camera" }
        if cursor != nil { suffix += " zoomed" }
        if youtube { suffix += " youtube" }
        let output = recording.url.deletingLastPathComponent().appending(path: "\(stem) \(suffix).mp4")
        try await Exporter.export(screen: recording.url, camera: camera, cameraOffset: recording.cameraOffset, layout: recorder.cameraLayout, cursor: cursor, youtube: youtube, start: start, end: end, to: output)
        let new = Recording(url: output, session: recording.session)
        new.startedAt = recording.startedAt.addingTimeInterval(start)
        new.duration = end - start
        new.chapters = ChapterList.trimmed(recording.chapters, start: start, end: end)
        new.cursorPath = cursor == nil ? nil : recording.cursorPath   // ponytail: offsets are not re-based; a second zoom of a zoom is unsupported
        context.insert(new)
        save()
        return new
    }

    // MARK: URL commands (Shortcuts, Apple Focus automations, scripts)

    /// opticalflow://start[?task=<title>]  opticalflow://stop  opticalflow://pause  opticalflow://resume
    /// opticalflow://break?minutes=5  opticalflow://record  opticalflow://add?title=<title>
    /// Returns false for an unknown command.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "opticalflow" else { return false }
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .compactMap { item in item.value.map { (item.name, $0) } })
        switch url.host {
        case "start":
            if let title = query["task"]?.lowercased(),
               let match = tasks(for: .list(.today)).first(where: { $0.title.lowercased().contains(title) })
                ?? ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).first(where: { !$0.isDone && $0.title.lowercased().contains(title) }) {
                startSession(on: match)
            } else {
                startSession()
            }
        case "stop": stopSession()
        case "pause": pause()
        case "resume": resume()
        case "break": startBreak(minutes: Int(query["minutes"] ?? "") ?? 5)
        case "record": toggleRecording()
        case "mini": miniTimer.toggle()
        case "add": addTask(title: query["title"] ?? "", on: .list(.inbox))
        default: return false
        }
        return true
    }

    /// Tests only: pretend time passed.
    func debugAdvance(seconds: Int) {
        clock?.banked += seconds
        tick()
    }
}
