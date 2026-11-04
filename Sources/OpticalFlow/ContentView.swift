import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    @State private var bootstrapped = false

    var body: some View {
        Group {
            if case .project(let id) = model.sidebar, model.showsBoard, let project = model.project(id) {
                // Board mode: two columns, so the board gets the whole width. Cards open a popover.
                NavigationSplitView {
                    Sidebar()
                } detail: {
                    VStack(spacing: 0) {
                        ProjectHeader(project: project)
                        BoardView(project: project)
                    }
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
        .touchBar { TouchBarStrip() }
        .sheet(item: Binding(get: { model.projectPrompt.map(ProjectPromptItem.init) },
                             set: { if $0 == nil { model.projectPrompt = nil } })) { item in
            ProjectEditor(prompt: item.prompt)
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


    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let session = model.session {
                // One item: two Text items share one glass capsule with no gap between them.
                HStack(spacing: Space.sm) {
                    Text(session.task?.title ?? "Session")
                        .lineLimit(1)
                        .frame(maxWidth: 200)
                    Text(model.menuLabel ?? "")
                        .monospacedDigit()
                }
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
            Button("Voice Command", systemImage: "mic.fill") { model.voice.toggle() }
                .help("Say what to do: add, complete, start, set priority, add a note (Control-Option-Space)")
            AgentActivityButton()
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
                        ProjectIcon(project: project)
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
                        Button("Edit Project…") { model.projectPrompt = .edit(project) }
                        Button(project.repoPath == nil ? "Set Repository Folder…" : "Change Repository Folder…") { model.chooseRepository(for: project) }
                        if let repo = project.repoPath {
                            Button("Forget Repository (\((repo as NSString).lastPathComponent))") { model.setRepository(nil, for: project) }
                        }
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

/// The Touch Bar while the window is in front: timer, Pause, Stop, Record, Voice, and Complete or Start.
struct TouchBarStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session {
            Text((model.clockLabel ?? "") + "  " + (session.task?.title ?? ""))
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: 240)
                .touchBarItemPrincipal()
            Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                if model.paused { model.resume() } else { model.pause() }
            }
            Button("Stop", systemImage: "stop.fill") { model.stopSession() }
            if let task = session.task, !task.isDone {
                Button("Done", systemImage: "checkmark") { model.complete(task); model.stopSession() }
            }
        } else if model.breakUntil != nil {
            Text("Break " + Countdown.clock(model.breakRemaining)).monospacedDigit().touchBarItemPrincipal()
            Button("End Break", systemImage: "xmark") { model.endBreak() }
        } else {
            if let next = model.upNext {
                Button("Start: \(next.title)", systemImage: "play.fill") { model.startSession(on: next) }
                    .touchBarItemPrincipal()
            }
            if let task = model.selectedTask, !task.isDone {
                Button("Complete", systemImage: "checkmark") { model.complete(task) }
            }
        }
        Button(model.recorder.isRecording ? "Stop Recording" : "Record",
               systemImage: model.recorder.isRecording ? "stop.circle.fill" : "record.circle") { model.toggleRecording() }
            .foregroundStyle(.red)
        Button("Voice", systemImage: "mic.fill") { model.voice.toggle() }
    }
}
