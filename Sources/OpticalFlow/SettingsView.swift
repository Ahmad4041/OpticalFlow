import SwiftUI
import OpticalFlowKit

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .agent: AgentSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, agent, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Sessions"
        case .agent: "Agent"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "timer"
        case .agent: "mic.fill"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("plannedMinutes", store: Prefs.store) private var plannedMinutes = 25
    @AppStorage(ControlStrip.enabledKey, store: Prefs.store) private var controlStrip = true

    var body: some View {
        @Bindable var recorder = model.recorder
        Section("Sessions") {
            Stepper("Length: \(plannedMinutes) minutes", value: $plannedMinutes, in: 5...180, step: 5)
            Toggle("Timer in the Touch Bar Control Strip", isOn: $controlStrip)
                .onChange(of: controlStrip) {
                    if controlStrip { ControlStrip.shared.install(model: model) } else { ControlStrip.shared.remove() }
                }
                .help("A timer button next to volume and brightness that stays while other apps are in front. Tap it for Pause, Stop, Record, and Voice.")
            LabeledContent("Start or stop anywhere", value: "⌃⌥⌘S")
            LabeledContent("Quick entry anywhere", value: "⌃Space")
            LabeledContent("Shortcuts and Focus") {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text("Open URL: opticalflow://start, stop, pause, resume")
                    Text("break?minutes=5, record, add?title=…, start?task=…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        Section("Recording") {
            Toggle("Microphone on", isOn: $recorder.micEnabled)
            MicrophonePicker()
            Toggle("Camera on, as a second file", isOn: $recorder.cameraEnabled)
            Toggle("Follow the pointer to another display", isOn: $recorder.followsDisplay)
                .help("When you record a whole display and move the pointer to another one, the recording switches there. Asks for Screen Recording permission once.")
            LabeledContent("Saved to", value: "~/Movies/OpticalFlow")
        }
        Section("Camera") {
            CameraLayoutControls(layout: $recorder.cameraLayout)
        }
        UpdateSettings()
    }
}

/// Version, automatic checks, and the update when one is waiting.
struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updater = model.updater
        Section("Updates") {
            Toggle("Check for updates every day", isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }))
                .help("Reads the latest release on GitHub. Nothing about you or your tasks is sent.")
            LabeledContent("Version") {
                HStack(spacing: Space.sm) {
                    Text(status).foregroundStyle(.secondary)
                    if case .available(let release) = updater.state {
                        Button("Install \(release.version.description) and Relaunch") { Task { await updater.install(release) } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                            .disabled(updater.state == .checking || updater.state == .installing)
                    }
                }
            }
        }
    }

    private var status: String {
        let current = "\(model.updater.current)"
        switch model.updater.state {
        case .idle: return current
        case .checking: return "\(current), checking…"
        case .upToDate: return "\(current), the latest"
        case .available(let release): return "\(current), \(release.version) is out"
        case .installing: return "Installing…"
        case .failed: return "\(current), check failed"
        }
    }
}

/// Which program turns a spoken sentence into opticalflow commands.
struct AgentSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var voice = model.voice
        Section("Voice") {
            Picker("Orchestrator", selection: $voice.orchestrator) {
                ForEach(Orchestrator.allCases) { which in
                    Text(which.title + (which.isInstalled ? "" : " (not installed)")).tag(which)
                        .selectionDisabled(!which.isInstalled)
                }
            }
            MicrophonePicker()
            LabeledContent("Speak anywhere") {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text("⌃⌥Space")
                    if Hotkey.voiceTaken {
                        Text("Another app owns this shortcut. Use the toolbar microphone, File > Voice Command, or the menu bar timer.")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text("Also: the toolbar microphone, File > Voice Command, the menu bar timer.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Text(model.voice.orchestrator.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section("From Shortcuts or a script") {
            LabeledContent("Command", value: "opticalflow agent say \"…\"")
                .textSelection(.enabled)
            Text("A Shortcut with Dictate Text, then Run Shell Script with that command, gives the same voice control from Siri or a hotkey.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section("Hand-off") {
            Text("Hand to Agent runs the orchestrator in a git worktree of the project's repository. Runs see your PATH plus ~/.local/bin, /usr/local/bin and /opt/homebrew/bin; any *_BASE_URL variable is dropped, so the agent talks to its own vendor.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Corner, size, shape, and blur. Shared by Settings and the toolbar's Recording Options.
struct CameraLayoutControls: View {
    @Binding var layout: CameraLayout

    var body: some View {
        Picker("Corner", selection: $layout.corner) {
            Label("Top left", systemImage: "arrow.up.left").tag(CameraLayout.Corner.topLeft)
            Label("Top right", systemImage: "arrow.up.right").tag(CameraLayout.Corner.topRight)
            Label("Bottom left", systemImage: "arrow.down.left").tag(CameraLayout.Corner.bottomLeft)
            Label("Bottom right", systemImage: "arrow.down.right").tag(CameraLayout.Corner.bottomRight)
        }
        Picker("Size", selection: $layout.size) {
            Text("Small").tag(CameraLayout.Size.small)
            Text("Medium").tag(CameraLayout.Size.medium)
            Text("Large").tag(CameraLayout.Size.large)
        }
        Picker("Shape", selection: $layout.shape) {
            Label("Circle", systemImage: "circle").tag(CameraLayout.Shape.circle)
            Label("Rounded", systemImage: "rectangle").tag(CameraLayout.Shape.rounded)
        }
        Toggle("Blur the background behind you", isOn: $layout.blurBackground)
    }
}
