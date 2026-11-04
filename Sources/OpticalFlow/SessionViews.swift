import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct SessionList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    private var days: [SessionStats.Day] {
        SessionStats.perDay(sessions.map { ($0.startedAt, $0 == model.session ? model.elapsed : $0.seconds) })
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
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
                                    .fixedSize()
                            }
                            .frame(width: Space.lg)
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
            .tag(session.id)
            .contextMenu {
                if let task = session.task {
                    Button("Start Another Session on \(task.title)") { model.requestSession(on: task) }
                    Button("Show Task") { model.sidebar = .list(.inbox); model.showTask(task) }
                }
                Divider()
                Button("Delete", role: .destructive) { model.deleteSession(session) }
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

/// One session: task, times, overflow, notes, and the recordings made during it.
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: Session

    private var seconds: Int { session == model.session ? model.elapsed : session.seconds }

    var body: some View {
        Form {
            Section {
                LabeledContent("Task", value: session.task?.title ?? "No task")
                if let project = session.task?.project { LabeledContent("Project", value: project.name) }
                LabeledContent("Started", value: session.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended, format: .dateTime.hour().minute())
                } else {
                    LabeledContent("Status", value: model.paused ? "Paused" : "Running")
                }
                LabeledContent("Worked", value: Countdown.clock(seconds, padded: false))
                LabeledContent("Planned", value: "\(session.plannedMinutes) min")
                if seconds > session.plannedMinutes * 60 {
                    LabeledContent("Overflow", value: "+" + Countdown.clock(seconds - session.plannedMinutes * 60, padded: false))
                }
            }
            Section("Notes") {
                TextEditor(text: $session.notes)
                    .frame(minHeight: 100)
            }
            if !session.recordings.isEmpty {
                Section("Recordings") {
                    ForEach(session.recordings) { recording in
                        HStack {
                            Text(recording.url.lastPathComponent)
                            Spacer()
                            Text(Countdown.clock(Int(recording.duration), padded: false)).monospacedDigit().foregroundStyle(.secondary)
                            Button("Show") { model.sidebar = .recordings; model.selection = recording.id }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section {
                HStack {
                    if session == model.session {
                        Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") { model.paused ? model.resume() : model.pause() }
                        Button("Stop", systemImage: "stop.fill") { model.stopSession() }
                    } else if let task = session.task {
                        Button("Start Another Session", systemImage: "play.fill") { model.requestSession(on: task) }
                            .disabled(model.session != nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
