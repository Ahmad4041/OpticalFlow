import AppKit
import AVFoundation
import OpticalFlowKit

/// An always-on-top camera preview shown while recording, so a display capture includes you,
/// like a streamer's webcam overlay. Its corner, size, and shape follow CameraLayout; you can
/// still drag it. Window captures do not include it; the export composite covers that case.
final class CameraBubble {
    private var panel: NSPanel?
    private var preview: AVCaptureVideoPreviewLayer?

    func show(session: AVCaptureSession, layout: CameraLayout) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .readOnly

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.masksToBounds = true
        preview.borderWidth = 3
        preview.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        let view = NSView()
        view.wantsLayer = true
        view.layer = preview
        panel.contentView = view
        self.panel = panel
        self.preview = preview
        apply(layout)
        panel.orderFrontRegardless()
    }

    /// Moves and reshapes the live bubble. No-op when it is not shown.
    func apply(_ layout: CameraLayout) {
        guard let panel, let preview else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        // Half the export size: the bubble is a preview, the export is the product.
        var frame = layout.frame(in: screen.size)
        frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height / 2)
        if layout.corner == .topLeft || layout.corner == .topRight { frame.origin.y = screen.maxY - frame.height - screen.width * CameraLayout.margin }
        if layout.corner == .topRight || layout.corner == .bottomRight { frame.origin.x = screen.maxX - frame.width - screen.width * CameraLayout.margin }
        frame.origin.x += screen.minX
        frame.origin.y += layout.corner == .topLeft || layout.corner == .topRight ? 0 : screen.minY
        panel.setFrame(frame, display: true)
        preview.frame = CGRect(origin: .zero, size: frame.size)
        preview.cornerRadius = layout.cornerRadius(for: frame)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        preview = nil
    }
}
