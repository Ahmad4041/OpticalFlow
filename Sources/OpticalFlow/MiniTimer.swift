import AppKit
import SwiftUI
import OpticalFlowKit

/// A small always-on-top timer, for when the menu bar is crowded or hidden. Window > Mini Timer.
final class MiniTimer {
    private var panel: NSPanel?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? hide() : show() }

    func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 72),
                                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                                backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: MiniTimerView().environment(model).themed())
            panel.setFrameAutosaveName("MiniTimer")
            if let screen = NSScreen.main, panel.frame.origin == .zero {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 240, y: screen.visibleFrame.maxY - 92))
            }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

struct MiniTimerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.menuLabel ?? (model.recorder.isRecording ? "● REC" : "--:--"))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(model.recorder.isRecording && model.session == nil ? "Recording" : (model.session?.task?.title ?? (model.breakUntil != nil ? "Break" : "No session")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            if model.recorder.isRecording {
                Button("Stop Recording", systemImage: "stop.circle.fill") { model.toggleRecording() }
                    .foregroundStyle(.red)
                    .help("Stop recording")
            }
            if model.session != nil {
                Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                    if model.paused { model.resume() } else { model.pause() }
                }
                Button("Stop", systemImage: "stop.fill") { model.stopSession() }
            } else {
                Button("Start", systemImage: "play.fill") { model.startSession() }
                    .disabled(model.selectedTask == nil)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(width: 220)
    }
}
