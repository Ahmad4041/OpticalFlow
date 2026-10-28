import Foundation
import SwiftData
import SwiftUI
import OpticalFlowKit

@Model
final class Project {
    var name: String
    var colorName: String = ProjectColor.blue.rawValue
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem] = []

    init(name: String, color: ProjectColor = .blue) {
        self.name = name
        self.colorName = color.rawValue
    }

    var color: Color { ProjectColor(rawValue: colorName)?.color ?? .accentColor }
    var openCount: Int { tasks.filter { !$0.isDone }.count }
}

nonisolated enum ProjectColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

/// A task. Called "Task" in the UI; TaskItem in code because Swift has its own Task.
@Model
final class TaskItem {
    var title: String
    var notes: String = ""
    var due: Date?
    var completedAt: Date?
    var isSomeday: Bool = false
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    var project: Project?

    init(title: String) {
        self.title = title
    }

    var isDone: Bool { completedAt != nil }

    /// `asOpen` evaluates the list rule as if the task were not done (a just-completed row that still shows).
    func isIn(_ list: SmartList, asOpen: Bool = false) -> Bool {
        list.contains(hasProject: project != nil, due: due, someday: isSomeday, done: asOpen ? false : isDone)
    }
}

/// A timed stretch of work on one task.
@Model
final class Session {
    var plannedMinutes: Int
    var startedAt: Date = Date.now
    var endedAt: Date?
    /// Worked seconds, pauses excluded. Banked on pause and stop.
    var seconds: Int = 0
    var notes: String = ""
    var uuid: UUID = UUID()
    var task: TaskItem?
    @Relationship(deleteRule: .nullify, inverse: \Recording.session) var recordings: [Recording] = []

    init(task: TaskItem?, plannedMinutes: Int) {
        self.task = task
        self.plannedMinutes = plannedMinutes
    }

    var overflow: Int { max(0, seconds - plannedMinutes * 60) }
}

/// A screen capture tied to a session.
@Model
final class Recording {
    var path: String
    var startedAt: Date = Date.now
    var duration: TimeInterval = 0
    var chapters: [ChapterMark] = []
    /// The camera sidecar, when the camera was on. Optional so older databases keep loading.
    var cameraPath: String?
    var uuid: UUID = UUID()
    var session: Session?

    init(url: URL, session: Session?) {
        self.path = url.path
        self.session = session
    }

    var url: URL { URL(fileURLWithPath: path) }
    var cameraURL: URL? { cameraPath.map { URL(fileURLWithPath: $0) } }
    var hasCamera: Bool { cameraURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    var title: String { session?.task?.title ?? "Recording" }
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
    var chapterText: String { ChapterList.text(opening: title, marks: chapters) }

    @MainActor func open() { NSWorkspace.shared.open(url) }
    @MainActor func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    @MainActor func copyChapters() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(chapterText, forType: .string)
    }
}

/// The sidebar pages. Snapshot mode walks the fixed ones plus the first project.
enum Page: Hashable {
    case list(SmartList), sessions, recordings, project(UUID)

    static let fixed: [Page] = SmartList.allCases.map { .list($0) } + [.sessions, .recordings]

    var title: String {
        switch self {
        case .list(let list): list.title
        case .sessions: "Sessions"
        case .recordings: "Recordings"
        case .project: "Project"
        }
    }

    var symbol: String {
        switch self {
        case .list(let list): list.symbol
        case .sessions: "timer"
        case .recordings: "record.circle"
        case .project: "circle.fill"
        }
    }

    var snapshotName: String {
        switch self {
        case .list(let list): list.rawValue
        case .sessions: "sessions"
        case .recordings: "recordings"
        case .project: "project"
        }
    }

    var showsTasks: Bool {
        switch self {
        case .list, .project: true
        default: false
        }
    }
}

enum ProjectPrompt: Equatable {
    case new, rename(Project)
}

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

    /// Writes "<name>-<start>-<end>.mp4" next to the recording and returns its row, chapters shifted.
    func trim(_ recording: Recording, start: TimeInterval, end: TimeInterval) async throws -> Recording {
        let stem = recording.url.deletingPathExtension().lastPathComponent
        let suffix = "\(Countdown.clock(Int(start))) to \(Countdown.clock(Int(end)))".replacingOccurrences(of: ":", with: ".")
        let output = recording.url.deletingLastPathComponent().appending(path: "\(stem) \(suffix).mp4")
        try await Exporter.export(screen: recording.url, start: start, end: end, to: output)
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
