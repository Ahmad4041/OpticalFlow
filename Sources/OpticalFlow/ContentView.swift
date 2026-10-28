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
        } label: {
            Label("Recording Options", systemImage: "slider.horizontal.3")
        }
        .disabled(model.recorder.isRecording)
        .help("Microphone and camera for the next recording")
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

    private var visible: [TaskItem] { tasks.filter { model.visible($0, on: page) } }

    private var title: String {
        if case .project(let id) = page { return projects.first { $0.uuid == id }?.name ?? "Project" }
        return page.title
    }

    private var isProjectPage: Bool {
        if case .project = page { return true }
        return false
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(visible) { task in
                TaskRow(task: task, showProject: !isProjectPage)
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
            if model.draftTitle != nil {
                HStack(spacing: Space.sm) {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                    TextField("New task", text: $draft)
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
                ContentUnavailableView("No Tasks", systemImage: page.symbol,
                                       description: Text("Press Command-N to add one."))
            }
        }
        .navigationTitle(title)
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

    var body: some View {
        List(sessions) { session in
            let seconds = session == model.session ? model.elapsed : session.seconds
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(session.task?.title ?? "No task")
                    Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
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
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "timer",
                                       description: Text("Select a task and press Command-Return."))
            }
        }
        .navigationTitle("Sessions")
    }
}
