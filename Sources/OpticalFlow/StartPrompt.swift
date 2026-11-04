import AppKit
import SwiftUI
import OpticalFlowKit

/// Asks before a session starts from the app: confirm the length, then Start Timer, or Record and Start,
/// which opens the system picker for what to record. A floating panel, so it works from the menu bar,
/// the mini timer, and the Touch Bar too. Off in Settings > Sessions.
final class StartPrompt {
    static let askKey = "askBeforeSession"
    static var asks: Bool {
        get { Prefs.store.object(forKey: askKey) as? Bool ?? true }
        set { Prefs.store.set(newValue, forKey: askKey) }
    }

    private var panel: NSPanel?
    private let model: AppModel
    /// The task the panel is open for, nil when closed.
    private(set) var task: TaskItem?

    init(model: AppModel) {
        self.model = model
    }

    func show(for task: TaskItem) {
        self.task = task
        let panel = self.panel ?? makePanel()
        let host = NSHostingView(rootView: StartPromptView(task: task, minutes: model.plannedMinutes,
                                                           record: task.recordsSession,
                                                           onStart: { [weak self] minutes, record, dontAsk in self?.start(minutes: minutes, record: record, dontAsk: dontAsk) },
                                                           onCancel: { [weak self] in self?.close() })
            .environment(model).themed())
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.panel = panel
    }

    func close() {
        task = nil
        panel?.orderOut(nil)
    }

    var isShown: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }

    private func start(minutes: Int, record: Bool, dontAsk: Bool) {
        guard let task else { return }
        if dontAsk { Self.asks = false }
        close()
        model.startSession(on: task, minutes: minutes, record: record)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }
}

struct StartPromptView: View {
    let task: TaskItem
    @State var minutes: Int
    /// Which button Return presses: the task's "record sessions" setting picks it.
    let record: Bool
    let onStart: (_ minutes: Int, _ record: Bool, _ dontAsk: Bool) -> Void
    let onCancel: () -> Void
    @State private var dontAsk = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Start a session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let project = task.project {
                    Label { Text(project.name) } icon: { ProjectIcon(project: project, size: 12) }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $minutes, in: 5...180, step: 5) {
                Label("\(minutes) minutes", systemImage: "timer")
                    .monospacedDigit()
            }
            Text("Record the screen too? Record and Start lets you choose a display or a window.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Don't ask again", isOn: $dontAsk)
                .toggleStyle(.checkbox)
                .help("Start right away next time. Turn asking back on in Settings > Sessions.")
            HStack(spacing: Space.sm) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if record {
                    Button("Start Timer") { onStart(minutes, false, dontAsk) }
                    Button("Record and Start…", systemImage: "record.circle") { onStart(minutes, true, dontAsk) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Record and Start…", systemImage: "record.circle") { onStart(minutes, true, dontAsk) }
                    Button("Start Timer", systemImage: "play.fill") { onStart(minutes, false, dontAsk) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(Space.margin)
        .frame(width: 440)
        .gridArea("startprompt")
    }
}
