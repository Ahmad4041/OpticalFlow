import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

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

    private var pageProject: Project? {
        if case .project(let id) = page { return projects.first { $0.uuid == id } }
        return nil
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
            .draggable(task.uuid.uuidString)
            .contextMenu {
                Button("Complete") { model.complete(task) }
                Button("Start Session") { model.startSession(on: task) }
                Toggle("Record Sessions", isOn: Binding(get: { task.recordsSession }, set: { task.recordsSession = $0; model.save() }))
                PriorityMenu(task: task)
                HandoffButton(task: task)
                Divider()
                Button("Due Today") { model.move([task.uuid.uuidString], to: .list(.today)) }
                Button("Due Tomorrow") { model.move([task.uuid.uuidString], to: .list(.upcoming)) }
                Button("Someday") { model.move([task.uuid.uuidString], to: .list(.someday)) }
                Button("Clear Due Date") { task.due = nil; model.save() }.disabled(task.due == nil)
                Menu("Move to Project") {
                    Button("None") { model.move([task.uuid.uuidString], to: .list(.inbox)) }
                    ForEach(projects) { project in
                        Button(project.name) { model.move([task.uuid.uuidString], to: .project(project.uuid)) }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { model.delete(task) }
            }
    }

    private var isProjectPage: Bool {
        if case .project = page { return true }
        return false
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let project = pageProject, !searching {
                ProjectHeader(project: project, compact: true)
                Divider()
            }
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
                        ContentUnavailableView(page.emptyState.title, systemImage: page.symbol,
                                               description: Text(page.emptyState.hint))
                    }
                }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search tasks")
        .navigationTitle(searching ? "Search" : title)
        .toolbar {
            if isProjectPage { ViewModeToolbar() }
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
                Text(task.hasDueTime ? due.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : due.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.callout)
                    .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            if let deadline = task.deadline {
                let missed = !task.isDone && deadline < Calendar.current.startOfDay(for: .now)
                Label(deadline.formatted(.dateTime.month(.abbreviated).day()), systemImage: "flag.checkered")
                    .font(.callout)
                    .foregroundStyle(missed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .help("Deadline \(deadline.formatted(date: .long, time: .omitted))")
            }
            if task.repeatRule != .none {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(task.repeatRule.title)
            }
            if task.recordsSession {
                Image(systemName: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help("Sessions on this task record the screen")
            }
            if task.priority != .none {
                PriorityFlag(priority: task.priority)
                    .labelStyle(.iconOnly)
                    .font(.caption)
            }
            if task.agentReply?.isEmpty == false {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(task.agentReply ?? "")
            }
            if !task.subtasks.isEmpty {
                let progress = Checklist.progress(task.subtasks)
                Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(progress.done == progress.total ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .help("\(progress.done) of \(progress.total) subtasks done")
            }
            if showProject, let project = task.project {
                ProjectIcon(project: project, size: 12)
                    .help(project.name)
            }
        }
        .opacity(task.isDone ? 0.5 : 1)
    }
}

struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Bindable var task: TaskItem
    @State private var newSubtask = ""
    @State private var confirmDiscard = false
    @State private var handoffError: String?

    var body: some View {
        Form {
            TextField("Title", text: $task.title)
            Picker("Project", selection: $task.project) {
                Text("None").tag(Project?.none)
                ForEach(projects) { project in
                    Label { Text(project.name) } icon: { ProjectIcon(project: project) }.tag(Optional(project))
                }
            }
            Toggle("Due date", isOn: Binding(get: { task.due != nil }, set: { task.due = $0 ? .now : nil }))
            if task.due != nil {
                DatePicker("Due", selection: Binding(get: { task.due ?? .now }, set: { task.due = $0 }),
                           displayedComponents: task.hasDueTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Time", isOn: $task.hasDueTime)
            }
            Toggle("Deadline", isOn: Binding(get: { task.deadline != nil }, set: { task.deadline = $0 ? (task.due ?? .now) : nil }))
            if task.deadline != nil {
                DatePicker("Deadline", selection: Binding(get: { task.deadline ?? .now }, set: { task.deadline = $0 }), displayedComponents: [.date])
            }
            Picker("Repeat", selection: $task.repeatRule) {
                ForEach(RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Someday", isOn: $task.isSomeday)
            Picker("Priority", selection: $task.priority) {
                ForEach(Priority.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Section {
                ForEach($task.subtasks) { $item in
                    HStack(spacing: Space.sm) {
                        Toggle("Done", isOn: $item.isDone)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        TextField("Subtask", text: $item.title, prompt: Text("Subtask"))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                        Button("Remove", systemImage: "xmark.circle.fill") { task.subtasks.removeAll { $0.id == item.id } }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                            .help("Remove this subtask")
                    }
                }
                HStack(spacing: Space.sm) {
                    Image(systemName: "plus.circle").foregroundStyle(.tertiary)
                    TextField("Add a subtask", text: $newSubtask, prompt: Text("Add a subtask, Return to save"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if let clean = TaskTitle.clean(newSubtask) { task.subtasks.append(ChecklistItem(title: clean)) }
                            newSubtask = ""
                        }
                }
            } header: {
                let progress = Checklist.progress(task.subtasks)
                HStack {
                    Text("Subtasks")
                    Spacer()
                    if progress.total > 0 { Text("\(progress.done) of \(progress.total)").foregroundStyle(.secondary) }
                }
            }
            Section("Sessions") {
                Toggle("Record the screen during sessions", isOn: $task.recordsSession)
                Toggle("Doing (on the board)", isOn: $task.isDoing)
            }
            if task.agentBranch != nil || task.agentReply?.isEmpty == false {
                Section {
                    if let reply = task.agentReply, !reply.isEmpty { Text(reply).textSelection(.enabled) }
                    if let branch = task.agentBranch {
                        let summary = model.branchSummary(for: task)
                        LabeledContent("Branch", value: branch)
                        if let summary {
                            LabeledContent("Changes", value: summary.commits == 0 ? "No commits yet" : "\(summary.commits) commits. \(summary.stat)")
                        }
                        HStack {
                            Button("Open Pull Request", systemImage: "arrow.triangle.pull") {
                                do { try model.openPullRequest(for: task) } catch { handoffError = error.localizedDescription }
                            }
                            .disabled((summary?.commits ?? 0) == 0)
                            Button("Reveal Worktree", systemImage: "folder") { model.revealWorktree(for: task) }
                            Button("Discard Branch", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                        }
                        .confirmationDialog("Discard the branch and worktree? Uncommitted work is lost.", isPresented: $confirmDiscard) {
                            Button("Discard", role: .destructive) { model.discardBranch(for: task) }
                        }
                        if let handoffError { Text(handoffError).foregroundStyle(.red).font(.callout) }
                    } else {
                        Button("Clear", systemImage: "xmark") { task.agentReply = nil; task.agentReplyAt = nil }
                    }
                } header: {
                    HStack {
                        Label("AI", systemImage: "sparkles")
                        Spacer()
                        if let at = task.agentReplyAt { Text(at, format: .dateTime.hour().minute()).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Notes") {
                TextEditor(text: $task.notes)
                    .frame(minHeight: 120)
            }
            Section {
                Button("Start Session", systemImage: "play.fill") { model.startSession(on: task) }
                    .disabled(model.session?.task == task)
                HandoffButton(task: task)
            }
        }
        .formStyle(.grouped)
    }
}

/// "Hand to Agent": starts a worktree run on this task, or explains what is missing.
struct HandoffButton: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var error: String?

    private var running: Bool {
        let id = String(task.agentID.prefix(8))
        return model.voice.runningJobs.contains { $0.isHandoff && $0.contextTaskID == id }
    }

    var body: some View {
        Button(running ? "Agent Is Working…" : "Hand to Agent", systemImage: "sparkles") {
            do { try model.voice.handoff(task) } catch { self.error = error.localizedDescription }
        }
        .disabled(running || task.isDone)
        .help(task.project?.repoPath == nil ? "Set the project's repository folder first (right-click the project)" : "Run Claude Code or Codex on this task in its own git worktree")
        .alert("Cannot hand off", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}
