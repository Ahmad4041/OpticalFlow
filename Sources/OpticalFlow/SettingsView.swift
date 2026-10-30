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
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Sessions"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "timer"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("plannedMinutes") private var plannedMinutes = 25

    var body: some View {
        @Bindable var recorder = model.recorder
        Section("Sessions") {
            Stepper("Length: \(plannedMinutes) minutes", value: $plannedMinutes, in: 5...180, step: 5)
            LabeledContent("Start or stop anywhere", value: "⌃⌥⌘S")
            LabeledContent("Quick entry anywhere", value: "⌃Space")
        }
        Section("Recording") {
            Toggle("Microphone on", isOn: $recorder.micEnabled)
            Toggle("Camera on, as a second file", isOn: $recorder.cameraEnabled)
            LabeledContent("Saved to", value: "~/Movies/OpticalFlow")
        }
        Section("Camera") {
            CameraLayoutControls(layout: $recorder.cameraLayout)
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
