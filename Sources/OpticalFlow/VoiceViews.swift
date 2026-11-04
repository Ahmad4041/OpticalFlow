import AppKit
import AVFoundation
import CoreAudio
import Speech
import SwiftData
import SwiftUI
import OpticalFlowKit

/// The voice panel, the toolbar activity button, the jobs list, and the microphone picker.
/// State lives in `VoiceAgent`; these only read it and call its public functions.
struct VoiceView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    private var firstName: String { NSFullUserName().split(separator: " ").first.map(String.init) ?? "there" }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning, \(firstName)."
        case 12..<18: "Good afternoon, \(firstName)."
        default: "Good evening, \(firstName)."
        }
    }

    private func headline(_ voice: VoiceAgent) -> String {
        if voice.busy { return "Working on it" }
        if voice.listening { return "Listening" }
        if !voice.reply.isEmpty { return voice.handledLocally ? "Done" : "Done, with \(voice.orchestrator.title)" }
        if voice.error != nil { return "Something is off" }
        return greeting
    }

    var body: some View {
        @Bindable var voice = model.voice
        HStack(alignment: .top, spacing: Space.md) {
            VoiceAvatar(listening: voice.listening, busy: voice.busy, done: !voice.reply.isEmpty, failed: voice.error != nil)
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headline(voice))
                        .font(.headline)
                        .contentTransition(.opacity)
                    Spacer()
                    Button("Close", systemImage: "xmark.circle.fill") { voice.close() }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .help(voice.busy ? "Close (Escape). The job keeps running under the toolbar sparkles." : "Close (Escape)")
                }
                TextField("Say or type what to do", text: $voice.transcript, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1...3)
                    .focused($focused)
                    .onSubmit { voice.send(voice.transcript) }
                    .onExitCommand { voice.close() }
                if voice.busy || !voice.steps.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(voice.steps.enumerated()), id: \.offset) { _, step in
                            Label(step, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if voice.busy {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                HStack(spacing: Space.sm) {
                                    ProgressView().controlSize(.mini)
                                    Text(voice.steps.isEmpty ? "Thinking" : "Thinking about the next step")
                                    Text("\(Int(context.date.timeIntervalSince(voice.startedAt ?? context.date))) s")
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .transition(.opacity)
                }
                if let error = voice.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if !voice.reply.isEmpty {
                    Text(voice.reply)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)   // selectable text truncates to one line without this
                        .textSelection(.enabled)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, Space.sm)
                        .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Space.md))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Text(footer(voice))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.xl)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { voice.fit(height: $0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()   // the panel's title bar is transparent; draw under it
        .animation(Snapshot.animation, value: voice.steps.count)
        .animation(Snapshot.animation, value: voice.reply)
        .onAppear { focused = true }
    }

    private func footer(_ voice: VoiceAgent) -> String {
        if voice.listening { return "Pause to send, or press Return. Escape cancels." }
        if voice.busy { return "\(voice.orchestrator.title) is working. Close or click away; the result lands on the task and under the toolbar sparkles." }
        return "Clear commands run at once. Longer requests go to \(voice.orchestrator.title). Settings > Agent."
    }
}

/// A round accent avatar that breathes while listening, sparkles while thinking, and ticks when done.
struct VoiceAvatar: View {
    let listening: Bool
    let busy: Bool
    let done: Bool
    let failed: Bool

    private var symbol: String {
        if failed { return "exclamationmark" }
        if done { return "checkmark" }
        if busy { return "sparkles" }
        if listening { return "waveform" }
        return "mic.fill"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if listening {
                Circle()
                    .stroke(Palette.accent.opacity(0.35), lineWidth: Space.xs)
                    .scaleEffect(1.25)
                    .symbolEffect(.pulse)
            }
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.onAccent)
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .symbolEffect(.pulse, isActive: busy)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// Which microphone the voice panel and the screen recorder read. nil follows the system default.
enum Microphone {
    static var preferredUID: String? {
        get { Prefs.store.string(forKey: "microphone.uid") }
        set { Prefs.store.set(newValue, forKey: "microphone.uid") }
    }

    /// (uid, name) for every input device.
    static func devices() -> [(uid: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { ($0.uniqueID, $0.localizedName) }
    }

    /// The preferred device when it is present, else nil (the system default).
    static var active: (uid: String, name: String)? {
        guard let uid = preferredUID else { return nil }
        return devices().first { $0.uid == uid }
    }

    /// CoreAudio id for a device uid.
    static func deviceID(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPointer, &size, &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Points an audio engine's input at the preferred device. Call before the engine starts.
    static func apply(to engine: AVAudioEngine) {
        guard let active, let id = deviceID(for: active.uid), let unit = engine.inputNode.audioUnit else { return }
        var deviceID = id
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}

/// System default or one input device. Shared by Settings > Agent and Settings > Sessions > Recording.
struct MicrophonePicker: View {
    @State private var uid: String? = Microphone.preferredUID
    @State private var devices = Microphone.devices()

    var body: some View {
        Picker("Microphone", selection: $uid) {
            Text("System default").tag(String?.none)
            ForEach(devices, id: \.uid) { device in
                Text(device.name).tag(Optional(device.uid))
            }
        }
        .onChange(of: uid) { Microphone.preferredUID = uid }
        .onAppear { devices = Microphone.devices(); uid = Microphone.preferredUID }
        .help("Used by the voice panel and by screen recordings")
    }
}

/// Toolbar sparkles: pulses while a job runs; click for the list of jobs.
struct AgentActivityButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        let voice = model.voice
        let running = voice.runningJobs.count
        if !voice.jobs.isEmpty {
            Button {
                shown.toggle()
            } label: {
                Label(running > 0 ? "AI working" : "AI results", systemImage: "sparkles")
                    .symbolEffect(.pulse, isActive: running > 0)
                    .foregroundStyle(running > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help(running > 0 ? "\(running) AI request\(running == 1 ? "" : "s") running in the background" : "AI results")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                AgentJobsList()
                    .environment(model)
                    .frame(width: 360)
            }
        }
    }
}

struct AgentJobsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let voice = model.voice
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(voice.jobs.reversed()) { job in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        Image(systemName: job.running ? "sparkles" : job.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(job.running ? AnyShapeStyle(.tint) : job.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                            .symbolEffect(.pulse, isActive: job.running)
                        Text(job.request).lineLimit(2)
                        if job.isHandoff { Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary).help("In a worktree") }
                        Spacer()
                        Text(job.running ? "\(job.seconds) s" : job.orchestrator.title).font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(Array(job.steps.enumerated()), id: \.offset) { _, step in
                        Text(step).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if !job.reply.isEmpty || job.error != nil {
                        Text(job.error ?? job.reply).font(.callout).textSelection(.enabled)
                    }
                    HStack {
                        Button("Open") { voice.show(job: job) }.buttonStyle(.link)
                        if job.running { Button("Stop") { job.cancel() }.buttonStyle(.link) }
                    }
                    .font(.caption)
                }
                .padding(.vertical, Space.xs)
                Divider()
            }
            Button("Clear finished") { voice.clearFinishedJobs() }
                .disabled(voice.jobs.allSatisfy(\.running))
        }
        .padding(Space.lg)
    }
}
