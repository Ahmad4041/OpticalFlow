import SwiftData
import SwiftUI
import OpticalFlowKit

/// A project as four columns. Drag a card to move it; the card's flags follow the column.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    let project: Project

    private func cards(in column: BoardColumn) -> [TaskItem] {
        tasks.filter { $0.project == project && $0.boardColumn == column && (column != .done || $0.completedAt.map { $0 > Date.now.addingTimeInterval(-7 * 86_400) } == true) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.md) {
                ForEach(BoardColumn.allCases, id: \.self) { column in
                    BoardColumnView(column: column, cards: cards(in: column), project: project)
                        .dropDestination(for: String.self) { ids, _ in
                            model.move(ids, toColumn: column)
                            return true
                        }
                }
            }
            .padding(Space.lg)
        }
        .gridArea("board", inset: Space.lg)
    }
}

struct BoardColumnView: View {
    @Environment(AppModel.self) private var model
    let column: BoardColumn
    let cards: [TaskItem]
    let project: Project
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var accent: Color { project.color }
    private var drafting: Bool { model.draftTitle != nil && model.draftColumn == column }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Label(column.title, systemImage: column.symbol)
                    .font(.headline)
                Spacer()
                Text(cards.count, format: .number)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("New Task", systemImage: "plus") {
                    model.draftColumn = column
                    model.draftTitle = ""
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Add a task to \(column.title)")
            }
            .padding(.horizontal, Space.xs)
            if drafting {
                TextField("New task, then a date: fri, 5 nov", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($draftFocused)
                    .padding(Space.sm)
                    .background(.background, in: RoundedRectangle(cornerRadius: Space.sm))
                    .overlay(RoundedRectangle(cornerRadius: Space.sm).strokeBorder(.tint, lineWidth: 2))
                    .onSubmit {
                        model.addTask(title: draft, project: project, column: column)
                        draft = ""
                        model.draftTitle = nil
                    }
                    .onExitCommand {
                        draft = ""
                        model.draftTitle = nil
                    }
                    .onAppear { draftFocused = true }
            }
            if cards.isEmpty && !drafting {
                Text(column == .doing ? "Drag a task here, or start a session." : "Nothing here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(cards) { task in
                BoardCard(task: task, accent: accent)
                    .draggable(task.uuid.uuidString)
                    .onTapGesture { model.selection = task.id }
            }
            Spacer(minLength: Space.lg)
        }
        .padding(Space.sm)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Space.md))
        .gridProbe("column-\(column.rawValue)", area: "board", edge: nil)
    }
}

struct BoardCard: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let accent: Color
    @State private var hovering = false

    private var selected: Bool { model.selection == task.id }
    private var overdue: Bool { task.due.map { !task.isDone && $0 < Calendar.current.startOfDay(for: .now) } ?? false }
    private var progress: (done: Int, total: Int) { Checklist.progress(task.subtasks) }
    private var firstNoteLine: String? {
        task.notes.split(whereSeparator: \.isNewline).first.map(String.init)
    }
    private var aiWorking: Bool {
        let id = String(task.agentID.prefix(8))
        return model.voice.runningJobs.contains { $0.taskIDs.contains(id) || $0.contextTaskID == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: Space.xs)
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Button {
                        if task.isDone { model.undoComplete() } else { model.complete(task) }
                    } label: {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || task.isDone ? 1 : 0.4)
                    .help(task.isDone ? "Done" : "Complete")
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(3)
                }
                if let line = firstNoteLine, !task.isDone {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if aiWorking {
                    Label("AI working on it", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)
                } else if let reply = task.agentReply, !reply.isEmpty {
                    Label(reply, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(task.agentReplyAt.map { "AI, \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "AI")
                }
                if progress.total > 0 {
                    HStack(spacing: Space.sm) {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                        Text("\(progress.done)/\(progress.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .help("\(progress.done) of \(progress.total) subtasks done")
                }
                HStack(spacing: Space.sm) {
                    if let due = task.due {
                        Label(DayGroup.label(for: due) + (task.hasDueTime ? ", " + due.formatted(.dateTime.hour().minute()) : ""), systemImage: "calendar")
                            .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if model.session?.task == task {
                        Label("Live", systemImage: "timer").foregroundStyle(.tint)
                    }
                    if task.recordsSession {
                        Label("Records", systemImage: "record.circle")
                            .foregroundStyle(.red)
                            .labelStyle(.iconOnly)
                            .help("Sessions on this task record the screen")
                    }
                    if task.priority != .none {
                        PriorityFlag(priority: task.priority)
                            .labelStyle(.iconOnly)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(Space.sm)
        .padding(.trailing, Space.xs)
        .fixedSize(horizontal: false, vertical: true)   // the stripe has no height of its own; the text sets the card's
        .background(.background, in: RoundedRectangle(cornerRadius: Space.sm))
        .overlay(RoundedRectangle(cornerRadius: Space.sm).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.04), radius: hovering ? Space.sm : 2, y: 1)
        .onHover { hovering = $0 }
        .animation(.default, value: hovering)
        .popover(isPresented: Binding(get: { selected }, set: { if !$0, selected { model.selection = nil } }), arrowEdge: .trailing) {
            TaskDetail(task: task)
                .frame(width: 380, height: 560)
        }
        .contextMenu {
            Button("Complete") { model.complete(task) }.disabled(task.isDone)
            Button("Start Session") { model.startSession(on: task) }
            Button(task.recordsSession ? "Stop Recording Sessions" : "Record Sessions") { task.recordsSession.toggle(); model.save() }
            PriorityMenu(task: task)
            Divider()
            ForEach(BoardColumn.allCases.filter { $0 != task.boardColumn }, id: \.self) { column in
                Button("Move to \(column.title)") { model.move([task.uuid.uuidString], toColumn: column) }
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(task) }
        }
    }
}

/// A flag in the priority's colour: high red, medium orange, low the accent.
struct PriorityFlag: View {
    let priority: Priority

    var body: some View {
        Label(priority.title, systemImage: "flag.fill")
            .foregroundStyle(priority == .high ? AnyShapeStyle(.red) : priority == .medium ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
            .help("\(priority.title) priority")
    }
}

/// Priority picker for context menus.
struct PriorityMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Picker("Priority", selection: Binding(get: { task.priority }, set: { task.priority = $0; model.save() })) {
            ForEach(Priority.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }
}
