import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var projectName = ""

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } content: {
            ContentColumn()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        } detail: {
            DetailColumn()
        }
        .toolbar { sessionToolbar }
        .alert(promptTitle, isPresented: Binding(get: { model.projectPrompt != nil },
                                                  set: { if !$0 { model.projectPrompt = nil } })) {
            TextField("Name", text: $projectName)
            Button(isRename ? "Rename" : "Create") {
                model.commitProjectPrompt(name: projectName)
                projectName = ""
            }
            Button("Cancel", role: .cancel) { projectName = "" }
        }
        .onChange(of: model.projectPrompt) {
            if case .rename(let project) = model.projectPrompt { projectName = project.name }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var isRename: Bool {
        if case .rename = model.projectPrompt { return true }
        return false
    }

    private var promptTitle: String { isRename ? "Rename Project" : "New Project" }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let session = model.session {
                Text(session.task?.title ?? "Session")
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                Text(model.menuLabel ?? "")
                    .monospacedDigit()
                Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                    if model.paused { model.resume() } else { model.pause() }
                }
                .help(model.paused ? "Resume the session" : "Pause the session")
                Button("Stop", systemImage: "stop.fill") { model.stopSession() }
                    .help("Stop the session (Command-Return)")
            } else {
                Button("Start Session", systemImage: "play.fill") { model.startSession() }
                    .disabled(model.selectedTask == nil)
                    .help("Start a session on the selected task (Command-Return)")
            }
            Button(model.recorder.isRecording ? "Stop Recording" : "Record",
                   systemImage: model.recorder.isRecording ? "stop.circle.fill" : "record.circle") {
                model.toggleRecording()
            }
            .tint(model.recorder.isRecording ? .red : nil)
            .help(model.recorder.isRecording ? "Stop recording" : "Record the screen (Shift-Command-R)")
            RecordingOptionsMenu()
        }
    }
}

/// Microphone and camera, set before a recording starts.
struct RecordingOptionsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var recorder = model.recorder
        Menu {
            Toggle("Microphone", systemImage: "mic", isOn: $recorder.micEnabled)
            Toggle("Camera", systemImage: "web.camera", isOn: $recorder.cameraEnabled)
            Toggle("Follow Pointer Across Displays", systemImage: "rectangle.on.rectangle", isOn: $recorder.followsDisplay)
            Divider()
            CameraLayoutControls(layout: $recorder.cameraLayout)
        } label: {
            Label("Recording Options", systemImage: "slider.horizontal.3")
        }
        .help("Microphone, camera, and where the camera sits")
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Project.createdAt) private var projects: [Project]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section {
                ForEach(Page.fixed, id: \.self) { page in
                    Label(page.title, systemImage: page.symbol)
                        .tag(page)
                }
            }
            Section("Projects") {
                ForEach(projects) { project in
                    Label {
                        HStack {
                            Text(project.name)
                            Spacer()
                            Text(project.openCount, format: .number)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(project.color)
                    }
                    .tag(Page.project(project.uuid))
                    .contextMenu {
                        Button("Rename…") { model.projectPrompt = .rename(project) }
                        Button("Delete", role: .destructive) { model.deleteProject(project) }
                    }
                }
                Button("New Project…", systemImage: "plus") { model.projectPrompt = .new }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

struct ContentColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sidebar ?? .list(.inbox) {
        case .sessions: SessionList()
        case .recordings: RecordingList()
        case let page: TaskList(page: page)
        }
    }
}

struct TaskList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @State private var draft = ""
    @FocusState private var draftFocused: Bool
    let page: Page

    private var searching: Bool { !model.search.isEmpty }
    private var visible: [TaskItem] {
        searching ? tasks.filter { model.matches($0) } : tasks.filter { model.visible($0, on: page) }
    }

    private var title: String {
        if case .project(let id) = page { return projects.first { $0.uuid == id }?.name ?? "Project" }
        return page.title
    }

    /// Upcoming, one section per due day, soonest first.
    private var days: [(Date, [TaskItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.due ?? .distantFuture) }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }) }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task, showProject: !isProjectPage || searching)
            .tag(task.id)
            .contextMenu {
                Button("Complete") { model.complete(task) }
                Button("Start Session") { model.startSession(on: task) }
                Divider()
                Button("Delete", role: .destructive) {
                    context.delete(task)
                    try? context.save()
                }
            }
    }

    private var isProjectPage: Bool {
        if case .project = page { return true }
        return false
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            if page == .list(.upcoming) && !searching {
                ForEach(days, id: \.0) { day, tasks in
                    Section(DayGroup.label(for: day)) {
                        ForEach(tasks) { row($0) }
                    }
                }
            } else {
                ForEach(visible) { row($0) }
            }
            if model.draftTitle != nil {
                HStack(spacing: Space.sm) {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                    TextField("New task, then a date: tomorrow, fri, in 3 days, 5 nov", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($draftFocused)
                        .onSubmit {
                            model.addTask(title: draft, on: page)
                            draft = ""
                            model.draftTitle = nil
                        }
                        .onExitCommand {
                            draft = ""
                            model.draftTitle = nil
                        }
                }
                .onAppear { draftFocused = true }
            }
        }
        .overlay {
            if visible.isEmpty && model.draftTitle == nil {
                if searching {
                    ContentUnavailableView.search(text: model.search)
                } else {
                    ContentUnavailableView("No Tasks", systemImage: page.symbol,
                                           description: Text("Press Command-N to add one."))
                }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search tasks")
        .navigationTitle(searching ? "Search" : title)
        .toolbar {
            ToolbarItem {
                Button("New Task", systemImage: "plus") { model.draftTitle = "" }
                    .help("Add a task (Command-N)")
            }
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let showProject: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            Button {
                model.complete(task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help("Complete (Command-K)")
            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
            Spacer()
            if let due = task.due {
                let overdue = !task.isDone && due < Calendar.current.startOfDay(for: .now)
                Text(due, format: .dateTime.month(.abbreviated).day())
                    .font(.callout)
                    .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            if showProject, let project = task.project {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(project.color)
            }
        }
        .opacity(task.isDone ? 0.5 : 1)
    }
}

struct DetailColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let task = model.selectedTask {
            TaskDetail(task: task)
        } else if let recording = model.selectedRecording {
            RecordingDetail(recording: recording)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Bindable var task: TaskItem

    var body: some View {
        Form {
            TextField("Title", text: $task.title)
            Picker("Project", selection: $task.project) {
                Text("None").tag(Project?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project))
                }
            }
            Toggle("Due date", isOn: Binding(get: { task.due != nil }, set: { task.due = $0 ? .now : nil }))
            if task.due != nil {
                DatePicker("Due", selection: Binding(get: { task.due ?? .now }, set: { task.due = $0 }),
                           displayedComponents: .date)
            }
            Toggle("Someday", isOn: $task.isSomeday)
            Section("Notes") {
                TextEditor(text: $task.notes)
                    .frame(minHeight: 120)
            }
            Section {
                Button("Start Session", systemImage: "play.fill") { model.startSession(on: task) }
                    .disabled(model.session?.task == task)
            }
        }
        .formStyle(.grouped)
    }
}

struct SessionList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    private var days: [SessionStats.Day] {
        SessionStats.perDay(sessions.map { ($0.startedAt, $0 == model.session ? model.elapsed : $0.seconds) })
    }

    var body: some View {
        List {
            Section {
                let days = days
                HStack(spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Today").font(.caption).foregroundStyle(.secondary)
                        Text(SessionStats.hours(days.last?.seconds ?? 0)).font(.title2).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("This week").font(.caption).foregroundStyle(.secondary)
                        Text(SessionStats.hours(days.reduce(0) { $0 + $1.seconds })).font(.title2).monospacedDigit()
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: Space.xs) {
                        let top = max(1, days.map(\.seconds).max() ?? 1)
                        ForEach(days, id: \.date) { day in
                            VStack(spacing: Space.xs) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Calendar.current.isDateInToday(day.date) ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                                    .frame(width: Space.md, height: max(Space.xs, 40 * CGFloat(day.seconds) / CGFloat(top)))
                                Text(day.date, format: .dateTime.weekday(.narrow))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .help("\(day.date.formatted(.dateTime.weekday(.wide))): \(SessionStats.hours(day.seconds))")
                        }
                    }
                }
                .padding(.vertical, Space.xs)
            }
            ForEach(sessions) { session in
            let seconds = session == model.session ? model.elapsed : session.seconds
            HStack(spacing: Space.sm) {
                Image(systemName: session.task?.isDone == true ? "checkmark.circle.fill" : "circle.fill")
                    .foregroundStyle(session.task?.project?.color ?? Color.secondary)
                    .font(session.task?.isDone == true ? .body : .caption2)
                    .frame(width: Space.xl)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(session.task?.title ?? "No task")
                    HStack(spacing: Space.xs) {
                        if let project = session.task?.project { Text(project.name).foregroundStyle(project.color) }
                        Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if session.endedAt == nil {
                    Image(systemName: "timer").foregroundStyle(.tint)
                }
                Text(Countdown.clock(seconds, padded: false))
                    .monospacedDigit()
                if seconds > session.plannedMinutes * 60 {
                    Text("+" + Countdown.clock(seconds - session.plannedMinutes * 60, padded: false))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
            }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "timer",
                                       description: Text("Select a task and press Command-Return."))
            }
        }
        .navigationTitle("Sessions")
    }
}
