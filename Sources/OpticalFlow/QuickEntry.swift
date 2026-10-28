import AppKit
import SwiftUI
import OpticalFlowKit

/// The quick-entry panel: Control-Space anywhere, type a task, Return saves it to Inbox.
/// The frontmost app's name (and the page URL in Safari or Chrome) goes into the notes.
final class QuickEntry {
    private var panel: NSPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func toggle() {
        if let panel, panel.isVisible { close(); return }
        show()
    }

    func show() {
        let context = FrontmostContext.capture()
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: QuickEntryView(context: context, onSave: { [weak self] title in
            self?.save(title: title, context: context)
        }, onCancel: { [weak self] in self?.close() }))
        panel.center()
        if let screen = NSScreen.main {
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(x: frame.origin.x, y: screen.visibleFrame.midY + screen.visibleFrame.height * 0.15))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func save(title: String, context: FrontmostContext) {
        guard let task = model.addTask(title: title, on: .list(.inbox)) else { return }
        task.notes = context.notes
        model.save()
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }
}

/// What was in front when the panel opened.
struct FrontmostContext {
    var appName: String
    var url: String?

    /// "From Safari: https://…" or "From Xcode", empty when OpticalFlow itself was in front.
    var notes: String {
        if appName.isEmpty { return "" }
        return "From \(appName)" + (url.map { ": \($0)" } ?? "")
    }

    static func capture() -> FrontmostContext {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return FrontmostContext(appName: "") }
        let name = app.localizedName ?? ""
        let script: String? = switch app.bundleIdentifier {
        case "com.apple.Safari": "tell application \"Safari\" to get URL of front document"
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser":
            "tell application id \"\(app.bundleIdentifier!)\" to get URL of active tab of front window"
        default: nil
        }
        // ponytail: AppleScript needs an Automation grant per browser; the first use prompts once.
        let url = script.flatMap { NSAppleScript(source: $0)?.executeAndReturnError(nil).stringValue }
        return FrontmostContext(appName: name, url: url)
    }
}

struct QuickEntryView: View {
    let context: FrontmostContext
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                TextField("New task, then a date: tomorrow, fri, in 3 days", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { onSave(title) }
                    .onExitCommand(perform: onCancel)
            }
            if !context.notes.isEmpty {
                Text(context.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("Return saves to Inbox. Escape cancels.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Space.xl)
        .frame(width: 520)
        .onAppear { focused = true }
    }
}
