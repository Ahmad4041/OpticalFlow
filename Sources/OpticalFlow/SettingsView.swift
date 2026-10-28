import SwiftUI

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
    @AppStorage("plannedMinutes") private var plannedMinutes = 25
    @AppStorage("micEnabled") private var micEnabled = true

    var body: some View {
        Section("Sessions") {
            Stepper("Length: \(plannedMinutes) minutes", value: $plannedMinutes, in: 5...180, step: 5)
            LabeledContent("Start or stop anywhere", value: "⌃⌥⌘S")
        }
        Section("Recording") {
            Toggle("Microphone on", isOn: $micEnabled)
            LabeledContent("Saved to", value: "~/Movies/OpticalFlow")
        }
    }
}
