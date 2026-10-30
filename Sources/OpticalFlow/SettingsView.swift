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
    @AppStorage("plannedMinutes") private var plannedMinutes = 25
    @AppStorage(ControlStrip.enabledKey) private var controlStrip = true

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
        Section("Next phase") {
            Text("Hand a task to an agent in a sandbox for the long run. Not built yet; the orchestrator above is the first step.")
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
