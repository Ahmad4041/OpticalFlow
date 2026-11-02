import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/OpticalFlow.app/Contents/MacOS/OpticalFlow
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=inbox,today limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// nil while snapshots run, so a capture never lands mid-transition. `.default` otherwise.
    static let animation: Animation? = ProcessInfo.processInfo.environment["APP_SNAPSHOT"] == nil ? .default : nil

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        setlinebuf(stdout)   // the log is a file, not a terminal: show each capture as it happens
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                let pages = Page.fixed + model.projects.prefix(1).map { Page.project($0.uuid) }
                for page in pages where only?.contains(page.snapshotName) ?? true {
                    model.sidebar = page
                    model.selection = model.firstID(for: page)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.snapshotName)-\(mode).png")
                }
            }
            if only == nil || only?.contains("board") == true, let project = model.projects.first {
                model.sidebar = .project(project.uuid)
                model.showsBoard = true
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/board-\(mode).png")
                }
                model.showsBoard = false
            }
            if only == nil || only?.contains("focus") == true {
                // The detail column with nothing selected: idle, then a running session.
                model.sidebar = .list(.today)
                model.selection = nil
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/focus-\(mode).png")
                }
                model.startSession(on: model.upNext)
                model.selection = nil
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/focus-running-\(mode).png")
                }
                model.stopSession()
            }
            if only == nil || only?.contains("quickentry") == true {
                model.quickEntry.show()
                try? await Task.sleep(for: .seconds(0.8))
                let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible && $0.level == .floating }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.4))
                    capture(to: "\(dir)/quickentry-\(mode).png", window: panel)
                }
                model.quickEntry.close()
            }
            if only == nil || only?.contains("voice") == true {
                model.voice.show(listening: false)
                model.voice.transcript = "Make the login loop urgent and add a note: repro needs a fresh profile"
                model.voice.busy = true
                model.voice.startedAt = .now.addingTimeInterval(-7)
                model.voice.steps = ["tasks list --search login", "tasks update 0bc72e97 --priority high"]
                try? await Task.sleep(for: .seconds(0.8))
                let panel = NSApp.windows.first { $0.frameAutosaveName == "VoicePanel" }
                panel?.makeFirstResponder(nil)
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.4))
                    capture(to: "\(dir)/voice-\(mode).png", window: panel)
                }
                // One request from start to finish, a frame per state, for the animated picture in the README.
                let request = "Make the login loop urgent and add a note: repro needs a fresh profile"
                let frames: [(VoiceAgent) -> Void] = [
                    { $0.listening = true; $0.busy = false; $0.transcript = ""; $0.steps = []; $0.reply = "" },
                    { $0.transcript = "Make the login loop urgent" },
                    { $0.listening = false; $0.transcript = request; $0.busy = true; $0.startedAt = .now },
                    { $0.steps = ["tasks list --search login"]; $0.startedAt = .now.addingTimeInterval(-2) },
                    { $0.steps.append("tasks update 0bc72e97 --priority high"); $0.startedAt = .now.addingTimeInterval(-4) },
                    { $0.steps.append("tasks update 0bc72e97 --notes \"Repro needs a fresh profile\""); $0.startedAt = .now.addingTimeInterval(-6) },
                    { $0.busy = false; $0.handledLocally = false; $0.reply = "Set “Fix the login redirect loop” to high priority and added the note. It is in Doing, due today." },
                ]
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for (index, frame) in frames.enumerated() {
                        frame(model.voice)
                        panel?.makeFirstResponder(nil)
                        // The steps list fades and the panel resizes; the first and last frames change the most.
                        try? await Task.sleep(for: .seconds(index == 0 || index == frames.count - 1 ? 1.2 : 0.7))
                        capture(to: "\(dir)/voice-frame\(index)-\(mode).png", window: panel)
                    }
                }
                model.voice.busy = false
                model.voice.listening = false
                model.voice.reply = ""
                model.voice.close()
            }
            if only == nil || only?.contains("agentjobs") == true {
                // The toolbar sparkles popover: one job running, one finished, one hand-off.
                let voice = model.voice
                let login = model.tasks(for: .list(.today)).first.map { String($0.agentID.prefix(8)) }
                let running = AgentJob(request: "Make the login loop urgent and add a note: repro needs a fresh profile", orchestrator: .claude, contextTaskID: login)
                running.steps = ["tasks list --search login", "tasks update \(login ?? "0bc72e97") --priority high"]
                let done = AgentJob(request: "Plan the chapter export for Friday", orchestrator: .claude, contextTaskID: nil)
                done.steps = ["tasks add --title \"Write the chapter export\" --due fri"]
                done.reply = "Added “Write the chapter export” for Friday in OpticalFlow."
                done.finishedAt = .now
                let handoff = AgentJob(request: "Work on “Try the new ScreenCaptureKit picker API”", orchestrator: .claude, contextTaskID: nil)
                handoff.repo = "/Users/you/Code/OpticalFlow"
                handoff.steps = ["Read Sources/OpticalFlow/Recorder.swift", "Edit Recorder.swift", "Bash(swift build)", "Bash(git commit -m …)"]
                handoff.reply = "1 commit on opticalflow/3f9a2c1e, 1 file changed, 24 insertions(+), 6 deletions(-), $0.04."
                handoff.costUSD = 0.04
                handoff.finishedAt = .now
                voice.jobs = [handoff, done, running]
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 8), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                panel.titleVisibility = .hidden
                panel.titlebarAppearsTransparent = true
                let host = NSHostingView(rootView: AgentJobsList().environment(model).frame(width: 360))
                panel.contentView = host
                panel.setContentSize(host.fittingSize)
                panel.center()
                panel.orderFront(nil)
                try? await Task.sleep(for: .seconds(0.6))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.4))
                    capture(to: "\(dir)/agentjobs-\(mode).png", window: panel)
                }
                panel.close()
                voice.jobs = []
            }
            if only == nil || only?.contains("minitimer") == true {
                model.selection = model.firstID(for: .list(.today))
                model.startSession()
                model.miniTimer.show()
                try? await Task.sleep(for: .seconds(0.8))
                let mini = NSApp.windows.first { $0.frameAutosaveName == "MiniTimer" }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.4))
                    capture(to: "\(dir)/minitimer-\(mode).png", window: mini)
                }
                model.miniTimer.hide()
                model.stopSession()
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        // The menu bar extra owns a visible window too; Settings is the one at normal level.
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.level == .normal }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
