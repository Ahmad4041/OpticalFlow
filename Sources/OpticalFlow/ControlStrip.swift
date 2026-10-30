import AppKit
import OpticalFlowKit

/// A timer button in the Touch Bar's Control Strip, next to volume and brightness, that stays while
/// the app is in the background. Tapping it opens the full controls. Uses the same private
/// DFRFoundation calls as Pock and BetterTouchTool; harmless on a Mac without a Touch Bar.
final class ControlStrip: NSObject, NSTouchBarDelegate {
    static let shared = ControlStrip()
    static let enabledKey = "touchbar.strip"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let identifier = NSTouchBarItem.Identifier("com.ahmadnaeem.opticalflow.strip")
    private var model: AppModel?
    private var item: NSCustomTouchBarItem?
    private var button: NSButton?
    private var label: NSTextField?
    private var modal: NSTouchBar?
    private var timer: Timer?
    private var setPresence: (@convention(c) (NSString, Bool) -> Void)?

    /// True when the private framework loaded, which every Touch Bar Mac has.
    private(set) var available = false

    func install(model: AppModel) {
        self.model = model
        guard item == nil else { return }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW),
              let presence = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        setPresence = unsafeBitCast(presence, to: (@convention(c) (NSString, Bool) -> Void).self)
        if let closeBox = dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost") {
            unsafeBitCast(closeBox, to: (@convention(c) (Bool) -> Void).self)(true)
        }
        available = true

        let button = NSButton(title: "", image: Self.glyph, target: self, action: #selector(tapped))
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = button
        self.item = item
        self.button = button

        let cls: AnyObject = NSTouchBarItem.self
        _ = cls.perform(NSSelectorFromString("addSystemTrayItem:"), with: item)
        setPresence?(identifier.rawValue as NSString, true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func remove() {
        timer?.invalidate()
        timer = nil
        guard let item else { return }
        setPresence?(identifier.rawValue as NSString, false)
        let cls: AnyObject = NSTouchBarItem.self
        _ = cls.perform(NSSelectorFromString("removeSystemTrayItem:"), with: item)
        self.item = nil
        button = nil
    }

    /// The app's mark, a ring with a dot, as a template image so the Touch Bar tints it.
    static let glyph: NSImage = {
        let size = NSSize(width: 22, height: 22)   // grid: ok Touch Bar image, not layout
        let image = NSImage(size: size, flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 2.2
            NSColor.black.setStroke()
            ring.stroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "OpticalFlow"
        return image
    }()

    /// The strip button: the mark, with the countdown while a session runs; red while recording.
    private func refresh() {
        guard let model, let button else { return }
        let recording = model.recorder.isRecording
        button.image = Self.glyph
        button.contentTintColor = recording ? .systemRed : nil
        button.title = model.clockLabel.map { " " + $0 } ?? (model.breakUntil != nil ? " " + Countdown.clock(model.breakRemaining) : "")
        label?.stringValue = status
    }

    private var status: String {
        guard let model else { return "" }
        if let session = model.session { return (model.clockLabel ?? "") + "  " + (session.task?.title ?? "Session") }
        if model.breakUntil != nil { return "Break " + Countdown.clock(model.breakRemaining) }
        if let next = model.upNext { return "Up next: " + next.title }
        return "OpticalFlow"
    }

    // MARK: Modal bar

    @objc private func tapped() {
        let bar = NSTouchBar()
        bar.delegate = self
        var ids: [NSTouchBarItem.Identifier] = [.init("status")]
        if model?.session != nil { ids += [.init("pause"), .init("stop"), .init("done")] }
        else if model?.breakUntil != nil { ids += [.init("endbreak")] }
        else { ids += [.init("start")] }
        ids += [.init("record"), .init("voice"), .otherItemsProxy]
        bar.defaultItemIdentifiers = ids
        modal = bar
        let cls: AnyObject = NSTouchBar.self
        _ = cls.perform(NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"), with: bar, with: identifier.rawValue)
    }

    private func dismiss() {
        guard let modal else { return }
        let cls: AnyObject = NSTouchBar.self
        _ = cls.perform(NSSelectorFromString("dismissSystemModalTouchBar:"), with: modal)
        self.modal = nil
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        func button(_ title: String, _ symbol: String, _ action: Selector, tint: NSColor? = nil) -> NSButton {
            let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
            b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            b.contentTintColor = tint
            return b
        }
        switch identifier.rawValue {
        case "status":
            let field = NSTextField(labelWithString: status)
            field.lineBreakMode = .byTruncatingTail
            field.preferredMaxLayoutWidth = 320
            label = field
            item.view = field
        case "pause": item.view = button(model?.paused == true ? "Resume" : "Pause", model?.paused == true ? "play.fill" : "pause.fill", #selector(pause))
        case "stop": item.view = button("Stop", "stop.fill", #selector(stop))
        case "done": item.view = button("Done", "checkmark", #selector(done))
        case "endbreak": item.view = button("End Break", "xmark", #selector(endBreak))
        case "start":
            let title = model?.upNext.map { "Start: " + String($0.title.prefix(28)) } ?? "Start"
            let b = button(title, "play.fill", #selector(start))
            b.isEnabled = model?.upNext != nil
            item.view = b
        case "record":
            let recording = model?.recorder.isRecording == true
            item.view = button(recording ? "Stop Rec" : "Record", recording ? "stop.circle.fill" : "record.circle", #selector(record), tint: .systemRed)
        case "voice": item.view = button("Voice", "mic.fill", #selector(voice))
        default: return nil
        }
        return item
    }

    @objc private func pause() { if model?.paused == true { model?.resume() } else { model?.pause() }; tapped() }
    @objc private func stop() { model?.stopSession(); tapped() }
    @objc private func done() { if let task = model?.session?.task { model?.complete(task) }; model?.stopSession(); tapped() }
    @objc private func endBreak() { model?.endBreak(); tapped() }
    @objc private func start() { model?.startSession(on: model?.upNext); tapped() }
    @objc private func record() { model?.toggleRecording(); dismiss() }
    @objc private func voice() { model?.voice.toggle(); dismiss() }
}
