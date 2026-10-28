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
    let recorder = Recorder()

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
    }

    func save() { try? context.save() }

    // MARK: Tasks

    var selectedTask: TaskItem? { selection.flatMap { context.model(for: $0) as? TaskItem } }
    var selectedRecording: Recording? { selection.flatMap { context.model(for: $0) as? Recording } }

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
        let task = TaskItem(title: clean)
        switch page ?? sidebar ?? .list(.inbox) {
        case .list(.today): task.due = .now
        case .list(.upcoming): task.due = Calendar.current.date(byAdding: .day, value: 1, to: .now)
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

    /// The menu bar text. nil when no session runs.
    var menuLabel: String? {
        session.map { Countdown.label(planned: $0.plannedMinutes * 60, elapsed: elapsed, paused: paused, recording: recorder.isRecording) }
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
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
        if !Store.isOverridden { Notifier.requestAuthorization() }
    }

    private func tick() {
        now = .now
        if let session, !notifiedDone, elapsed >= session.plannedMinutes * 60 {
            notifiedDone = true
            if !Store.isOverridden { Notifier.post("Session done", session.task?.title ?? "") }
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
        ticker?.cancel()
        ticker = nil
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
    func trim(_ recording: Recording, start: TimeInterval, end: TimeInterval, withCamera: Bool = false) async throws -> Recording {
        let stem = recording.url.deletingPathExtension().lastPathComponent
        let camera = withCamera && recording.hasCamera ? recording.cameraURL : nil
        var suffix = "\(Countdown.clock(Int(start))) to \(Countdown.clock(Int(end)))".replacingOccurrences(of: ":", with: ".")
        if camera != nil { suffix += " with camera" }
        let output = recording.url.deletingLastPathComponent().appending(path: "\(stem) \(suffix).mp4")
        try await Exporter.export(screen: recording.url, camera: camera, cameraOffset: recording.cameraOffset, start: start, end: end, to: output)
        let new = Recording(url: output, session: recording.session)
        new.startedAt = recording.startedAt.addingTimeInterval(start)
        new.duration = end - start
        new.chapters = ChapterList.trimmed(recording.chapters, start: start, end: end)
        context.insert(new)
        save()
        return new
    }

    /// Tests only: pretend time passed.
    func debugAdvance(seconds: Int) {
        session?.seconds += seconds
        tick()
    }
}
