import AppKit
import SQLite3
import SwiftData
import SwiftUI
import UserNotifications

// OpticalFlow
//   OpticalFlow                      the app
//   APP_STORE=<file> OpticalFlow     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> OpticalFlow   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 OpticalFlow           fill an empty /tmp store with sample data (tools/snap.sh)
//   OpticalFlow --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> OpticalFlow      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 OpticalFlow           draw the 8 pt grid and the layout probes over the window

struct OpticalFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("OpticalFlow", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 860, minHeight: 520)
                .onOpenURL { model.handle($0) }
                .onAppear {
                    delegate.model = model
                    Hotkey.registerSession { model.toggleSession() }
                    Hotkey.registerQuickEntry { model.quickEntry.toggle() }
                    Hotkey.registerVoice { model.voice.toggle() }
                    Hotkey.registerMark { model.mark() }
                    if ControlStrip.enabled, !Store.isOverridden { ControlStrip.shared.install(model: model) }
                }
        }
        .modelContainer(model.container)
        // Always open at launch, even after the window was closed last time.
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 740)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Task") { model.draftTitle = "" }
                    .keyboardShortcut("n")
                Button("New Project…") { model.projectPrompt = .new }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Quick Entry") { model.quickEntry.toggle() }
                    .keyboardShortcut(.space, modifiers: .control)
                Button("Voice Command") { model.voice.toggle() }
                    .keyboardShortcut(.space, modifiers: [.control, .option])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    if !model.undoComplete() { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                }
                .keyboardShortcut("z")
                Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Task") {
                Button("Complete") { model.completeSelected() }
                    .keyboardShortcut("k")
                    .disabled(model.selectedTask == nil)
                Button("Due Today") { model.setDue(.now) }
                    .keyboardShortcut("t")
                    .disabled(model.selectedTask == nil)
                Button("Clear Due Date") { model.setDue(nil) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(model.selectedTask == nil)
                Divider()
                Button(model.session == nil ? "Start Session" : "Stop Session") { model.toggleSession() }
                    .keyboardShortcut(.return)
                    .disabled(model.session == nil && model.selectedTask == nil)
                Button(model.paused ? "Resume Session" : "Pause Session") {
                    if model.paused { model.resume() } else { model.pause() }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model.session == nil)
                Divider()
                Button(model.recorder.isRecording ? "Stop Recording" : "Record Screen…") { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Hand to Agent") { if let task = model.selectedTask { try? model.voice.handoff(task) } }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                    .disabled(model.selectedTask?.project?.repoPath == nil)
                Divider()
                Button("Mark Chapter Here") { model.mark() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(!model.recorder.isRecording)
            }
            CommandGroup(after: .windowArrangement) {
                Button(model.miniTimer.isShown ? "Hide Mini Timer" : "Show Mini Timer") { model.miniTimer.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Button(model.showsBoard ? "Show as List" : "Show as Board") { model.showsBoard.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
                ForEach(Array(Page.fixed.enumerated()), id: \.offset) { index, page in
                    Button(page.title) { model.sidebar = page }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .themed()
        } label: {
            if let label = model.menuLabel {
                Text(label).monospacedDigit()
            } else {
                Image(systemName: "timer")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // One-time: an earlier build widened the middle column for the board, and AppKit kept that width for every page.
        if !UserDefaults.standard.bool(forKey: "migrated.splitWidths.1") {
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames main, SidebarNavigationSplitView")
            UserDefaults.standard.set(true, forKey: "migrated.splitWidths.1")
        }
        if !Store.isOverridden { UNUserNotificationCenter.current().delegate = self }
    }

    /// "Break 5 min" / "Break 15 min" on the session-done notification.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Notifier.breakFive: model?.startBreak(minutes: 5)
            case Notifier.breakFifteen: model?.startBreak(minutes: 15)
            case Notifier.keepIdle: model?.keepIdleTime()
            case Notifier.discardIdle: model?.discardIdleTime()
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock click with the window closed: bring it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// A recording in progress is finalized before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.recorder.isRecording else { return .terminateNow }
        Task {
            await model.recorder.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Preferences. A test run (APP_STORE in /tmp) gets its own suite, emptied at launch,
/// so the self-test and snapshots never read or change the preferences of the person using the app.
enum Prefs {
    static let store: UserDefaults = {
        guard Store.isOverridden else { return .standard }
        let name = "com.ahmadnaeem.opticalflow.test"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }()
}

/// Where the data lives: ~/Library/Application Support/OpticalFlow/OpticalFlow.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "OpticalFlow", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "OpticalFlow.store")
    }

    static func makeContainer() -> ModelContainer {
        repair(url)
        do {
            return try ModelContainer(for: Project.self, TaskItem.self, Session.self, Recording.self,
                                      configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }

    /// Sessions from before `TaskItem.sessions` existed can point at a task row that was deleted.
    /// SwiftData aborts both reading and clearing such a pointer, so this clears it in SQL before the
    /// container opens. A missing table (a fresh store) is a no-op.
    static func repair(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "UPDATE ZSESSION SET ZTASK = NULL WHERE ZTASK IS NOT NULL AND ZTASK NOT IN (SELECT Z_PK FROM ZTASKITEM);", nil, nil, nil)
    }
}
