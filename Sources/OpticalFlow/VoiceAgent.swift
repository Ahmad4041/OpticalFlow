import AppKit
import AVFoundation
import Speech
import SwiftUI
import OpticalFlowKit

/// Which program turns a sentence into opticalflow commands.
enum Orchestrator: String, CaseIterable, Identifiable {
    case builtin, claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtin: "Built in (no AI)"
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var blurb: String {
        switch self {
        case .builtin: "Understands add, complete, start, stop, priority, and notes. Anything else becomes a new task."
        case .claude: "Runs `claude -p` with only the opticalflow command allowed. It reads your tasks, adds, updates, and sets priority as you asked."
        case .codex: "Runs `codex exec` in its workspace sandbox, with network on so it reaches the app. It reads your tasks, adds, updates, and sets priority as you asked."
        }
    }

    private var binary: String? {
        switch self {
        case .builtin: nil
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    /// The executable on this Mac, looked up in the usual install folders.
    var path: String? {
        guard let binary else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin", "\(home)/.claude/local", "\(home)/.npm-global/bin"]
            .map { "\($0)/\(binary)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isInstalled: Bool { self == .builtin || path != nil }

    func arguments(prompt: String, workdir: String) -> [String] {
        switch self {
        case .builtin: []
        case .claude: ["-p", prompt, "--output-format", "text", "--allowedTools", "Bash(opticalflow:*)",
                       "--disallowedTools", "Edit,Write,NotebookEdit,WebFetch,WebSearch"]
        // The workspace sandbox blocks all network, which includes the app's socket; this lets the socket through.
        case .codex: ["exec", "--skip-git-repo-check", "-s", "workspace-write", "-c", "sandbox_workspace_write.network_access=true",
                      "-C", workdir, "--color", "never", prompt]
        }
    }
}

/// Control-Option-Space: listen, show the words, send them to the orchestrator, show its answer.
/// Speech runs on this Mac when the language supports it.
@Observable
final class VoiceAgent {
    var orchestrator: Orchestrator {
        didSet { UserDefaults.standard.set(orchestrator.rawValue, forKey: "voice.orchestrator") }
    }
    var transcript = ""
    var reply = ""
    var error: String?
    var listening = false
    var busy = false

    private let model: AppModel
    private var panel: NSPanel?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var process: Process?

    init(model: AppModel) {
        self.model = model
        let saved = UserDefaults.standard.string(forKey: "voice.orchestrator").flatMap(Orchestrator.init(rawValue:))
        orchestrator = saved.map { $0.isInstalled ? $0 : .builtin } ?? (Orchestrator.claude.isInstalled ? .claude : .builtin)
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// Hotkey: open and listen; press again to send what was heard; a third press closes.
    func toggle() {
        if isShown {
            if listening, !transcript.isEmpty { send(transcript) } else { close() }
            return
        }
        show(listening: !Store.isOverridden)
    }

    func show(listening: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        transcript = ""
        reply = ""
        error = nil
        panel.center()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: screen.visibleFrame.midY + screen.visibleFrame.height * 0.15))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if listening { Task { await startListening() } }
    }

    func close() {
        stopListening()
        process?.terminate()
        busy = false
        panel?.orderOut(nil)
    }

    // MARK: Speech

    private func startListening() async {
        let speech = await withCheckedContinuation { cont in SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) } }
        guard speech == .authorized else {
            error = "Allow Speech Recognition for OpticalFlow in System Settings > Privacy & Security. You can type instead."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "Allow the microphone for OpticalFlow in System Settings > Privacy & Security. You can type instead."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition is not available for your language right now. You can type instead."
            return
        }
        nonisolated(unsafe) let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = "No microphone input: \(error.localizedDescription)"
            return
        }
        listening = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil && result == nil
            Task { @MainActor [weak self] in
                guard let self, self.listening else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.restartSilenceTimer()
                }
                if final { self.send(self.transcript) }
                if failed { self.stopListening() }
            }
        }
    }

    /// Sends after a pause in speech, so nobody has to press Return.
    private func restartSilenceTimer() {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self, self.listening else { return }
            self.send(self.transcript)
        }
    }

    private func stopListening() {
        silence?.cancel()
        silence = nil
        guard listening else { return }
        listening = false
        recognition?.finish()
        recognition = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: Orchestrator

    /// Runs the sentence through the chosen orchestrator and shows the answer.
    func send(_ text: String) {
        stopListening()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !busy else { return }
        transcript = clean
        error = nil
        if orchestrator == .builtin || !orchestrator.isInstalled {
            reply = model.perform(VoiceIntent.parse(clean))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.busy == false, self?.listening == false { self?.close() }
            }
            return
        }
        busy = true
        let prompt = prompt(for: clean)
        let which = orchestrator
        Task { [weak self] in
            do {
                let answer = try await self?.run(which, prompt: prompt) ?? ""
                self?.reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                self?.error = error.localizedDescription
            }
            self?.busy = false
        }
    }

    private func prompt(for text: String) -> String {
        var context = "Open page: \(model.sidebar?.title ?? "none")."
        if let task = model.selectedTask { context += " Selected task: “\(task.title)” (id \(task.agentID.prefix(8)))." }
        return """
        You control the OpticalFlow task app on this Mac through the `opticalflow` command (run `opticalflow help` for the list; always add --json). \
        The user said, by voice: "\(text)". \(context) \
        Do what they asked with opticalflow commands only: find tasks with `tasks list --search`, add with `tasks add`, change with `tasks update` \
        (--priority high for urgent, --notes to guide the work, --due for dates), `tasks complete`, `session start --task <id>`, `session stop`. \
        Never delete anything. Then answer in one short spoken sentence, plain text, no markdown.
        """
    }

    private func run(_ which: Orchestrator, prompt: String) async throws -> String {
        guard let path = which.path else { throw VoiceError.notInstalled(which.title) }
        let workdir = Store.isOverridden ? "/tmp/OpticalFlow-agent"
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpticalFlow/agent").path
        try? FileManager.default.createDirectory(atPath: workdir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = which.arguments(prompt: prompt, workdir: workdir)
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [env["PATH"] ?? "/usr/bin:/bin", "\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"].joined(separator: ":")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        self.process = process
        nonisolated(unsafe) let outHandle = out.fileHandleForReading
        nonisolated(unsafe) let errHandle = err.fileHandleForReading
        async let stdout = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let stderr = Task.detached { errHandle.readDataToEndOfFile() }.value
        let (output, errors) = await (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
        process.waitUntilExit()
        self.process = nil
        guard process.terminationStatus == 0 || !output.isEmpty else {
            throw VoiceError.failed(which.title, errors.split(separator: "\n").suffix(3).joined(separator: " "))
        }
        return output
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 140),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("VoicePanel")
        panel.contentView = NSHostingView(rootView: VoiceView().environment(model).themed())
        return panel
    }
}

enum VoiceError: LocalizedError {
    case notInstalled(String), failed(String, String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) is not installed. Pick another orchestrator in Settings > Agent."
        case .failed(let name, let detail): "\(name) failed: \(detail)"
        }
    }
}

struct VoiceView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var voice = model.voice
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: voice.listening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: voice.listening)
                    .foregroundStyle(voice.listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: Space.xxl)
                TextField("Say or type what to do", text: $voice.transcript)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { voice.send(voice.transcript) }
                    .onExitCommand { voice.close() }
            }
            if voice.busy {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(voice.orchestrator.title)…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let error = voice.error {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if !voice.reply.isEmpty {
                Label(voice.reply, systemImage: "checkmark.circle")
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Text(voice.listening ? "Listening. Pause to send, or press Return. Escape cancels."
                 : "Return sends to \(voice.orchestrator.title). Escape closes. Change it in Settings > Agent.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Space.xl)
        .frame(width: 520)
        .onAppear { focused = true }
    }
}
