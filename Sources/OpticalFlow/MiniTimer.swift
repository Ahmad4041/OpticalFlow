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
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 96),
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
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.setFrameAutosaveName("MiniTimer")
            if let screen = NSScreen.main, panel.frame.origin == .zero {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 300, y: screen.visibleFrame.maxY - 116))
            }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

struct MiniTimerView: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var overtime: Bool { (model.remaining ?? 0) < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                if let project = model.session?.task?.project ?? model.upNext?.project {
                    ProjectIcon(project: project, size: 12)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                if model.recorder.isRecording {
                    Label("REC", systemImage: "record.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
                if model.paused {
                    Label("Paused", systemImage: "pause.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Button("Hide", systemImage: "xmark.circle.fill") { model.miniTimer.hide() }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
                    .help("Hide the mini timer (Command-Option-M)")
            }
            HStack(alignment: .center, spacing: Space.md) {
                Text(model.clockLabel ?? (model.breakUntil != nil ? Countdown.clock(model.breakRemaining) : (model.recorder.isRecording ? "REC" : "--:--")))
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overtime ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                HStack(spacing: Space.xs) {
                    if model.recorder.isRecording {
                        Button("Mark Chapter", systemImage: "bookmark.fill") { model.mark() }
                            .help("Mark a chapter here (Control-Option-Command-M)")
                        Button("Stop Recording", systemImage: "stop.circle.fill") { model.toggleRecording() }
                            .tint(.red)
                            .help("Stop recording")
                    }
                    if model.session != nil {
                        Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                            if model.paused { model.resume() } else { model.pause() }
                        }
                        .help(model.paused ? "Resume" : "Pause")
                        Button("Stop", systemImage: "stop.fill") { model.stopSession() }
                            .help("Stop the session")
                    } else if model.breakUntil != nil {
                        Button("End Break", systemImage: "xmark") { model.endBreak() }
                    } else {
                        Button("Start", systemImage: "play.fill") { model.startSession(on: model.upNext) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.upNext == nil)
                            .help(model.upNext.map { "Start a session on “\($0.title)”" } ?? "Add a task first")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .labelStyle(.iconOnly)
            }
            if model.session != nil {
                ProgressView(value: overtime ? 1 : model.sessionProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(overtime ? .red : nil)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(width: 280)
        .ignoresSafeArea()   // the panel's title bar is transparent; draw under it
        .onHover { hovering = $0 }
        .animation(.default, value: hovering)
    }

    private var title: String {
        if let task = model.session?.task { return task.title }
        if model.breakUntil != nil { return "Break" }
        if model.recorder.isRecording { return "Recording" }
        if let next = model.upNext { return "Up next: \(next.title)" }
        return "No task to start"
    }
}
