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
    /// On the board's Doing column. Set when a session starts on it.
    var isDoing: Bool = false
    /// Starting a session on this task opens the screen recorder too.
    var recordsSession: Bool = false
    /// Priority.rawValue; 0 is none.
    var priorityRaw: Int = 0
    /// Subtasks, in order.
    var checklist: [ChecklistItem] = []
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    var project: Project?

    init(title: String) {
        self.title = title
    }

    var isDone: Bool { completedAt != nil }
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    var boardColumn: BoardColumn { BoardColumn.column(someday: isSomeday, doing: isDoing, done: isDone) }

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
    /// Seconds the camera's first frame came after the screen's start (negative: before). Default 0.
    var cameraOffset: TimeInterval = 0
    /// JSON sidecar with the pointer path, for the follow-cursor zoom. Optional for older databases.
    var cursorPath: String?
    var uuid: UUID = UUID()
    var session: Session?

    init(url: URL, session: Session?) {
        self.path = url.path
        self.session = session
    }

    var url: URL { URL(fileURLWithPath: path) }
    var cameraURL: URL? { cameraPath.map { URL(fileURLWithPath: $0) } }
    var cursorURL: URL? { cursorPath.map { URL(fileURLWithPath: $0) } }
    var cursorTrack: CursorTrack? {
        cursorURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(CursorTrack.self, from: $0) }
    }
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

    /// Title and hint for an empty page.
    var emptyState: (title: String, hint: String) {
        switch self {
        case .list(.inbox): ("Inbox Zero", "Nothing waiting. Control-Space adds a task from anywhere.")
        case .list(.today): ("Nothing Due Today", "Drag a task here, or select one and press Command-T.")
        case .list(.upcoming): ("Nothing Scheduled", "End a new task with a date: tomorrow, fri, in 3 days, 5 nov.")
        case .list(.someday): ("No Someday Ideas", "Park a task here when it is not for now.")
        case .project: ("No Tasks Here", "Press Command-N to add one to this project.")
        default: ("Nothing Here", "")
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
