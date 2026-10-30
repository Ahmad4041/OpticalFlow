import SwiftData
import SwiftUI
import OpticalFlowKit

/// The detail column when nothing is selected: the running session as a large ring,
/// or, when idle, today's progress and the next task with one Start button.
/// Every row spans the column, so each row is a grid probe with one leading edge.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var tasks: [TaskItem]

    var body: some View {
        VStack(spacing: Space.section) {
            Spacer(minLength: 0)
            if let session = model.session {
                running(session)
            } else if model.breakUntil != nil {
                onBreak
            } else {
                idle
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.margin)
        .gridArea("focus")
    }

    // MARK: Running

    private func running(_ session: Session) -> some View {
        let planned = session.plannedMinutes * 60
        let remaining = planned - model.elapsed
        let recording = model.recorder.isRecording
        return VStack(spacing: Space.xl) {
            taskHeader(session.task)
                .gridProbe("focus.task", area: "focus")
            ring(progress: min(1, Double(model.elapsed) / Double(max(1, planned))), overtime: remaining < 0) {
                Text(remaining >= 0 ? Countdown.clock(remaining) : "+" + Countdown.clock(-remaining))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(model.paused ? "Paused" : remaining < 0 ? "Overtime" : "\(session.plannedMinutes) min session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if recording {
                    Label("REC", systemImage: "record.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(.red.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Recording")
                }
            }
            .gridProbe("focus.ring", area: "focus")
            HStack(spacing: Space.md) {
                Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                    if model.paused { model.resume() } else { model.pause() }
                }
                .help(model.paused ? "Resume the session" : "Pause the session")
                Button("Stop", systemImage: "stop.fill") { model.stopSession() }
                    .help("Stop the session (Command-Return)")
                Button(recording ? "Stop Recording" : "Record", systemImage: recording ? "stop.circle.fill" : "record.circle") {
                    model.toggleRecording()
                }
                .tint(recording ? .red : nil)
                .help(recording ? "Stop recording" : "Record the screen (Shift-Command-R)")
                if let task = session.task, !task.isDone {
                    Button("Done", systemImage: "checkmark") {
                        model.complete(task)
                        model.stopSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Complete the task and stop the session")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .gridProbe("focus.controls", area: "focus")
        }
    }

    // MARK: Break

    private var onBreak: some View {
        VStack(spacing: Space.xl) {
            ring(progress: 1, overtime: false) {
                Text(Countdown.clock(model.breakRemaining))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Label("Break", systemImage: "cup.and.saucer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .gridProbe("focus.ring", area: "focus")
            Button("End Break", systemImage: "xmark") { model.endBreak() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .gridProbe("focus.controls", area: "focus")
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: Space.xxl) {
            stats
                .gridProbe("focus.stats", area: "focus")
            if let task = model.upNext {
                upNext(task)
                    .gridProbe("focus.next", area: "focus")
            } else {
                ContentUnavailableView("Nothing to Start", systemImage: "play.circle",
                                       description: Text("Add a task with Command-N, or Control-Space from anywhere."))
                    .gridProbe("focus.next", area: "focus")
            }
        }
    }

    private var stats: some View {
        let today = sessions.filter { Calendar.current.isDateInToday($0.startedAt) }
        let focused = today.reduce(0) { $0 + ($1 == model.session ? model.elapsed : $1.seconds) }
        let done = tasks.filter { $0.completedAt.map(Calendar.current.isDateInToday) ?? false }.count
        return HStack(spacing: Space.md) {
            statTile("Focused today", SessionStats.hours(focused), symbol: "timer")
            statTile("Sessions", "\(today.count)", symbol: "play.circle")
            statTile("Done", "\(done)", symbol: "checkmark.circle")
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private func statTile(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Space.md))
    }

    private func upNext(_ task: TaskItem) -> some View {
        @Bindable var task = task
        return VStack(alignment: .leading, spacing: Space.lg) {
            Text("Up next")
                .font(.caption)
                .foregroundStyle(.secondary)
            taskHeader(task)
            HStack(spacing: Space.md) {
                Button("Start \(model.plannedMinutes) min Session", systemImage: "play.fill") {
                    model.startSession(on: task)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Start a session on this task")
                Spacer()
                Toggle("Record", systemImage: "record.circle", isOn: $task.recordsSession)
                    .toggleStyle(.switch)
                    .help("Record the screen during sessions on this task")
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: 480)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Space.md))
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    /// Title, then project, due, and record badge. Centered, shared by the running and idle states.
    private func taskHeader(_ task: TaskItem?) -> some View {
        VStack(spacing: Space.xs) {
            Text(task?.title ?? "Session")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: Space.sm) {
                if let project = task?.project {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(project.color)
                    Text(project.name)
                }
                if let task, let due = task.due {
                    Text(task.hasDueTime ? due.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : due.formatted(.dateTime.month(.abbreviated).day()))
                }
                if task?.recordsSession == true {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .help("Sessions on this task record the screen")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func ring<Content: View>(progress: Double, overtime: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: Space.md)
            Circle()
                .trim(from: 0, to: overtime ? 1 : progress)
                .stroke(overtime ? AnyShapeStyle(.red) : AnyShapeStyle(.tint),
                        style: StrokeStyle(lineWidth: Space.md, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 || overtime ? 1 : 0)   // a round cap at zero draws a dot
                .animation(.default, value: progress)
            VStack(spacing: Space.sm) { content() }
        }
        .frame(width: 240, height: 240)
        .frame(maxWidth: .infinity)
    }
}
