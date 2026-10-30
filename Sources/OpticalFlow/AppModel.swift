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
    /// Command-F. Non-empty: every page shows matching open tasks instead of its own list.
    var search = ""
    /// Non-nil while the inline new-task row is open.
    var draftTitle: String?
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
    private(set) var paused = false
    private var resumedAt: Date?
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
            return recording
        }
        recorder.onStop = { [weak self] recording, duration in
            recording.duration = duration
            self?.save()
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

    /// The selected row as its type. nil for another type (SwiftData aborts on a typed lookup of the
    /// wrong entity) and nil once the row is deleted (a deleted model asserts on access).
    private func selected<T: PersistentModel>(_ type: T.Type) -> T? {
        guard let selection, selection.entityName == String(describing: T.self),
              let model: T = context.registeredModel(for: selection), !model.isDeleted else { return nil }
        return model
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

    /// Open tasks whose title or notes contain the words of `search`, any order, case-insensitive.
    func matches(_ task: TaskItem) -> Bool {
        let words = search.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        let text = (task.title + " " + task.notes).lowercased()
        return !task.isDone && words.allSatisfy { text.contains($0) }
    }

    func complete(_ task: TaskItem) {
        guard !task.isDone else { return }
        task.completedAt = .now
        undoCompleted.append(task)
        if let recording = recorder.recording {
            recording.chapters.append(ChapterMark(title: task.title, offset: Date.now.timeIntervalSince(recording.startedAt)))
        }
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

    func deleteProject(_ project: Project) {
        if sidebar == .project(project.uuid) { sidebar = .list(.inbox) }
        context.delete(project)
        save()
    }

    /// The first row of a page, for snapshots.
    func firstID(for page: Page) -> PersistentIdentifier? {
        switch page {
        case .recordings: (try? context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first?.id
        case .sessions: nil
        default: tasks(for: page).first?.id
        }
    }

    // MARK: Session

    var plannedMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "plannedMinutes")
        return stored > 0 ? stored : 25
    }

    var elapsed: Int {
        guard let session else { return 0 }
        let live = resumedAt.map { now.timeIntervalSince($0) } ?? 0
        return session.seconds + Int(live)
    }

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
        session = new
        paused = false
        notifiedDone = false
        resumedAt = .now
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
        if let idleSince, let session { session.seconds += Int(Date.now.timeIntervalSince(idleSince)) }
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
        if let session, !notifiedDone, elapsed >= session.plannedMinutes * 60 {
            notifiedDone = true
            if !Store.isOverridden { Notifier.post("Session done", session.task?.title ?? "", category: Notifier.sessionDone) }
        }
        if let breakUntil, breakUntil <= now {
            endBreak()
            if !Store.isOverridden { Notifier.post("Break over", "Pick the next task.") }
        }
    }

    /// Moves live time into the session record.
    private func bank() {
        if let resumedAt, let session { session.seconds += Int(Date.now.timeIntervalSince(resumedAt)) }
        resumedAt = nil
    }

    func pause() {
        guard session != nil, !paused else { return }
        bank()
        paused = true
    }

    func resume() {
        guard session != nil, paused else { return }
        resumedAt = .now
        now = .now
        paused = false
    }

    func stopSession() {
        guard let session else { return }
        bank()
        session.endedAt = .now
        save()
        self.session = nil
        paused = false
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
        session?.seconds += seconds
        tick()
    }
}
