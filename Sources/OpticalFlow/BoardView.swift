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

    private var selected: Bool { model.selection == task.id }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: Space.xs)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .lineLimit(3)
                HStack(spacing: Space.sm) {
                    if let due = task.due {
                        Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                    }
                    if task.recordsSession {
                        Label("Records", systemImage: "record.circle")
                            .foregroundStyle(.red)
                    }
                    if task.priority != .none {
                        PriorityFlag(priority: task.priority)
                    }
                    if model.session?.task == task {
                        Label("Live", systemImage: "timer").foregroundStyle(.tint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .fixedSize(horizontal: false, vertical: true)   // the stripe has no height of its own; the text sets the card's
        .background(.background, in: RoundedRectangle(cornerRadius: Space.sm))
        .overlay(RoundedRectangle(cornerRadius: Space.sm).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: selected ? 2 : 1))
        .popover(isPresented: Binding(get: { selected }, set: { if !$0, selected { model.selection = nil } }), arrowEdge: .trailing) {
            TaskDetail(task: task)
                .frame(width: 380, height: 520)
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
