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
                    BoardColumnView(column: column, cards: cards(in: column), accent: project.color)
                        .dropDestination(for: String.self) { ids, _ in
                            model.move(ids, toColumn: column)
                            return true
                        }
                }
            }
            .padding(Space.lg)
        }
        .gridArea("board")
    }
}

struct BoardColumnView: View {
    @Environment(AppModel.self) private var model
    let column: BoardColumn
    let cards: [TaskItem]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Label(column.title, systemImage: column.symbol)
                    .font(.headline)
                Spacer()
                Text(cards.count, format: .number)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xs)
            if cards.isEmpty {
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
        .frame(width: 240, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Space.md))
        .gridProbe("column-\(column.rawValue)", area: "board")
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
        .background(.background, in: RoundedRectangle(cornerRadius: Space.sm))
        .overlay(RoundedRectangle(cornerRadius: Space.sm).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: selected ? 2 : 1))
        .contextMenu {
            Button("Start Session") { model.startSession(on: task) }
            Button(task.recordsSession ? "Stop Recording Sessions" : "Record Sessions") { task.recordsSession.toggle(); model.save() }
            Divider()
            ForEach(BoardColumn.allCases.filter { $0 != task.boardColumn }, id: \.self) { column in
                Button("Move to \(column.title)") { model.move([task.uuid.uuidString], toColumn: column) }
            }
        }
    }
}
