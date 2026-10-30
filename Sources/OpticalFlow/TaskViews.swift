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
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(project.color)
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
                           displayedComponents: task.hasDueTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Time", isOn: $task.hasDueTime)
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
            if let reply = task.agentReply, !reply.isEmpty {
                Section {
                    Text(reply).textSelection(.enabled)
                    Button("Clear", systemImage: "xmark") { task.agentReply = nil; task.agentReplyAt = nil }
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
            }
        }
        .formStyle(.grouped)
    }
}
