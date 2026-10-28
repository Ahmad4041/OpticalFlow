import AppKit
import AVFoundation

/// A round, always-on-top camera preview shown while recording, so a display capture
/// includes you, like a streamer's webcam overlay. Drag it anywhere. Window captures do not
/// include it; the export composite covers that case.
final class CameraBubble {
    private var panel: NSPanel?
    static let diameter: CGFloat = 220

    func show(session: AVCaptureSession) {
        guard panel == nil else { return }
        let size = NSSize(width: Self.diameter, height: Self.diameter)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .readOnly

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = size.width / 2
        preview.masksToBounds = true
        preview.borderWidth = 3
        preview.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer = preview
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
