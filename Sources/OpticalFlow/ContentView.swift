import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var projectName = ""

    @State private var bootstrapped = false

    var body: some View {
        Group {
            if case .project(let id) = model.sidebar, model.showsBoard, let project = model.project(id) {
                // Board mode: two columns, so the board gets the whole width. Cards open a popover.
                NavigationSplitView {
                    Sidebar()
                } detail: {
                    BoardView(project: project)
                        .navigationTitle(project.name)
                        .toolbar {
                            ViewModeToolbar()
                            ToolbarItem {
                                Button("New Task", systemImage: "plus") { model.draftColumn = .todo; model.draftTitle = "" }
                                    .help("Add a task to To Do (Command-N)")
                            }
                        }
                }
            } else {
                NavigationSplitView {
                    Sidebar()
                } content: {
                    ContentColumn()
                        .navigationSplitViewColumnWidth(min: 320, ideal: 400)
                } detail: {
                    DetailColumn()
                }
            }
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
            // The split view swaps between list and board mode; the hooks below run once.
            guard !bootstrapped else { return }
            bootstrapped = true
            AgentRouter.model = model
            AgentSocket.listen { AgentRouter.handle($0) }
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var boardShown: Bool {
        if case .project = model.sidebar { return model.showsBoard }
        return false
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
                        .dropDestination(for: String.self) { ids, _ in
                            guard page.showsTasks else { return false }
                            model.move(ids, to: page)
                            return true
                        }
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
                    .dropDestination(for: String.self) { ids, _ in
                        model.move(ids, to: .project(project.uuid))
                        return true
                    }
                    .contextMenu {
                        Button("New Task in \(project.name)") {
                            model.sidebar = .project(project.uuid)
                            model.draftTitle = ""
                        }
                        Button("Rename…") { model.projectPrompt = .rename(project) }
                        Divider()
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

struct DetailColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let task = model.selectedTask {
            TaskDetail(task: task)
        } else if let recording = model.selectedRecording {
            RecordingDetail(recording: recording)
        } else if let session = model.selectedSession {
            SessionDetail(session: session)
        } else {
            FocusView()
        }
    }
}

/// List or Board, on project pages.
struct ViewModeToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            @Bindable var model = model
            Picker("View", selection: $model.showsBoard) {
                Label("List", systemImage: "list.bullet").tag(false)
                Label("Board", systemImage: "rectangle.split.3x1").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("List or board (Command-Option-B)")
        }
    }
}
