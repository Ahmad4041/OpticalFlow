import SwiftUI
import OpticalFlowKit

/// The menu bar timer's panel: countdown, Pause/Resume, Stop, Record.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var recorder = model.recorder
        VStack(spacing: Space.md) {
            if let session = model.session {
                Text(session.task?.title ?? "Session")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.menuLabel ?? "")
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if let idleSince = model.idleSince {
                    Text("Away since \(idleSince.formatted(date: .omitted, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        Button("Keep Time") { model.keepIdleTime() }
                        Button("Discard") { model.discardIdleTime() }
                    }
                    .controlSize(.small)
                }
                HStack(spacing: Space.sm) {
                    Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                        if model.paused { model.resume() } else { model.pause() }
                    }
                    Button("Stop", systemImage: "stop.fill") { model.stopSession() }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.breakUntil != nil {
                Text("Break").font(.headline)
                Text(Countdown.clock(model.breakRemaining))
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Button("End Break", systemImage: "stop.fill") { model.endBreak() }
            } else {
                Text(model.selectedTask?.title ?? "Select a task to start a session")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Button("Start Session", systemImage: "play.fill") { model.startSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedTask == nil)
                HStack(spacing: Space.sm) {
                    Button("Break 5") { model.startBreak(minutes: 5) }
                    Button("Break 15") { model.startBreak(minutes: 15) }
                }
                .controlSize(.small)
            }
            Divider()
            Toggle("Record screen", systemImage: "record.circle", isOn: Binding(
                get: { model.recorder.isRecording },
                set: { _ in model.toggleRecording() }))
            Toggle("Microphone", systemImage: "mic", isOn: $recorder.micEnabled)
                .disabled(model.recorder.isRecording)
            Toggle("Camera", systemImage: "web.camera", isOn: $recorder.cameraEnabled)
                .disabled(model.recorder.isRecording)
            if let error = model.recorder.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open OpticalFlow") {
                    NSApp.activate()
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .toggleStyle(.switch)
        .padding(Space.lg)
        .frame(width: 300)
    }
}
