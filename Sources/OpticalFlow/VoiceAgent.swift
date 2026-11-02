import AppKit
import AVFoundation
import CoreAudio
import Speech
import SwiftData
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

    /// A long run in a worktree: edits allowed, capped by turns and dollars, commits but never pushes.
    func handoffArguments(prompt: String) -> [String] {
        switch self {
        case .builtin: []
        case .claude: ["-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
                       "--max-turns", "80", "--max-budget-usd", "5",
                       "--allowedTools", "Bash,Read,Edit,Write,MultiEdit,Glob,Grep,LS",
                       "--disallowedTools", "WebFetch,WebSearch,Bash(git push:*),Bash(git merge:*),Bash(git checkout:*),Bash(git switch:*)"]
        case .codex: ["exec", "--json", "--skip-git-repo-check", "-s", "workspace-write", "--color", "never", prompt]
        }
    }

    func arguments(prompt: String, workdir: String) -> [String] {
        switch self {
        case .builtin: []
        case .claude: ["-p", prompt, "--output-format", "stream-json", "--verbose", "--model", "haiku",
                       "--allowedTools", "Bash(opticalflow:*)", "--disallowedTools", "Edit,Write,NotebookEdit,WebFetch,WebSearch"]
        // The workspace sandbox blocks all network, which includes the app's socket; this lets the socket through.
        case .codex: ["exec", "--json", "--skip-git-repo-check", "-s", "workspace-write", "-c", "sandbox_workspace_write.network_access=true",
                      "-C", workdir, "--color", "never", prompt]
        }
    }
}

/// One request handed to Claude Code or Codex. It runs in the background; the panel may close.
@Observable
final class AgentJob: Identifiable {
    let id = UUID()
    let request: String
    let orchestrator: Orchestrator
    let startedAt = Date.now
    var finishedAt: Date?
    var steps: [String] = []
    var reply = ""
    var error: String?
    /// 8-character task ids the agent touched, read from its commands as they run.
    var taskIDs: Set<String> = []
    /// The task selected when the request was made, if any.
    var contextTaskID: String?
    /// A hand-off: the repo and worktree the agent works in. nil for a plain voice request.
    var repo: String?
    var worktree: URL?
    var costUSD: Double?
    @ObservationIgnored var process: Process?

    init(request: String, orchestrator: Orchestrator, contextTaskID: String?) {
        self.request = request
        self.orchestrator = orchestrator
        self.contextTaskID = contextTaskID
    }

    var isHandoff: Bool { repo != nil }

    var running: Bool { finishedAt == nil }
    var seconds: Int { Int((finishedAt ?? .now).timeIntervalSince(startedAt)) }

    func cancel() {
        process?.terminate()
        if finishedAt == nil { error = "Stopped."; finishedAt = .now }
    }
}

/// Control-Option-Space: listen, show the words, send them to the orchestrator, show its answer.
/// Speech runs on this Mac when the language supports it.
@Observable
final class VoiceAgent {
    var orchestrator: Orchestrator {
        didSet { Prefs.store.set(orchestrator.rawValue, forKey: "voice.orchestrator") }
    }
    var transcript = ""
    var reply = ""
    var error: String?
    var listening = false
    var busy = false
    /// What the orchestrator has done so far, one line per step.
    var steps: [String] = []
    var startedAt: Date?
    /// True after the last sentence was handled by the built-in parser.
    var handledLocally = false
    /// Requests handed to the AI, newest last. They outlive the panel.
    var jobs: [AgentJob] = []
    /// The job the panel is showing.
    var current: AgentJob?
    var runningJobs: [AgentJob] { jobs.filter(\.running) }
    /// Off while a CLI probe listens, so nothing acts on noise.
    var autoSend = true
    /// What the last listen found, for `opticalflow agent diagnose`.
    private(set) var diagnostics: [String: String] = [:]

    private let model: AppModel
    private var panel: NSPanel?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        let saved = Prefs.store.string(forKey: "voice.orchestrator").flatMap(Orchestrator.init(rawValue:))
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
        autoSend = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        transcript = ""
        reply = ""
        error = nil
        steps = []
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
        panel?.orderOut(nil)   // a running job keeps going; the toolbar sparkles show it
    }

    /// Shows a job in the panel (from the toolbar list).
    func show(job: AgentJob) {
        show(listening: false)
        current = job
        transcript = job.request
        handledLocally = false
        mirror(job)
    }

    /// Copies a job's progress into the panel state when it is the one on screen.
    private func mirror(_ job: AgentJob) {
        guard current === job else { return }
        steps = job.steps
        reply = job.reply
        error = job.error
        busy = job.running
        startedAt = job.startedAt
    }

    func clearFinishedJobs() { jobs.removeAll { !$0.running } }

    // MARK: Speech

    func startListening() async {
        diagnostics = ["locale": Locale.current.identifier]
        // These three callbacks arrive on background queues; @Sendable keeps them off the main actor (the app's default).
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in cont.resume(returning: status) }
        }
        diagnostics["speechAuthorization"] = "\(speech.rawValue)"
        guard speech == .authorized else {
            error = "Allow Speech Recognition for OpticalFlow in System Settings > Privacy & Security > Speech Recognition. You can type instead."
            return
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        diagnostics["microphone"] = "\(mic)"
        guard mic else {
            error = "Allow the microphone for OpticalFlow in System Settings > Privacy & Security > Microphone. You can type instead."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer() else {
            error = "No speech recognizer for \(Locale.current.identifier). You can type instead."
            return
        }
        diagnostics["available"] = "\(recognizer.isAvailable)"
        diagnostics["onDevice"] = "\(recognizer.supportsOnDeviceRecognition)"
        guard recognizer.isAvailable else {
            error = "Speech recognition is off. Turn on Dictation in System Settings > Keyboard, or check the network. You can type instead."
            return
        }
        nonisolated(unsafe) let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Project names and task words are rarely dictionary words; this teaches the recognizer them.
        request.contextualStrings = model.projects.map(\.name) + model.recentTitles(limit: 60)
        // On this Mac the on-device model may be missing even when supported; the server path still works.
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        let input = engine.inputNode
        Microphone.apply(to: engine)
        let format = input.outputFormat(forBus: 0)
        diagnostics["inputFormat"] = "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch, \(format.commonFormat == .pcmFormatFloat32 ? "float" : "int")"
        diagnostics["inputDevice"] = Microphone.active?.name ?? ((AVCaptureDevice.default(for: .audio)?.localizedName ?? "none") + " (system default)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "No microphone input device. Pick one in System Settings > Sound > Input. You can type instead."
            return
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) var peak: Float = 0
        nonisolated(unsafe) var buffers = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            request.append(buffer)
            // Loudest sample so far, so a silent transcript can be told apart from a silent microphone.
            if let data = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            }
            buffers += 1
            if buffers % 20 == 0 {
                let level = peak, count = buffers
                Task { @MainActor in
                    guard let self else { return }
                    self.diagnostics["inputPeak"] = String(format: "%.4f", level)
                    self.diagnostics["inputBuffers"] = "\(count)"
                    // Two seconds of exact zeros is a dead or muted microphone, not a quiet room.
                    if count == 80, level == 0, self.listening, self.error == nil {
                        self.error = "The microphone “\(self.diagnostics["inputDevice"] ?? "")” is silent. Pick another in Settings > Agent, or type instead."
                    }
                }
            }
        }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = "No microphone input: \(error.localizedDescription)"
            diagnostics["engine"] = error.localizedDescription
            return
        }
        listening = true
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = (error as NSError?).map { (code: $0.code, text: "\($0.domain) \($0.code): \($0.localizedDescription)") }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.diagnostics["transcript"] = text
                    if self.listening, self.autoSend { self.restartSilenceTimer() }
                }
                if let failure {
                    self.diagnostics["recognizerError"] = failure.text
                    // 216 is the cancel we cause by finishing; 1110 is "no speech" after silence.
                    if self.listening, failure.code != 216, failure.code != 1110 {
                        self.error = "Speech recognition failed: \(failure.text). You can type instead."
                    }
                    self.stopListening()
                    return
                }
                if final, self.listening, self.autoSend { self.send(self.transcript) }
            }
        }
    }

    /// Diagnosis: recognizes a sound file, to tell a microphone problem from a recognition problem.
    func transcribe(file: URL) {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer() else { diagnostics["fileTranscript"] = "no recognizer"; return }
        diagnostics["fileTranscript"] = "pending"
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = false
        recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = (error as NSError?).map { "\($0.domain) \($0.code): \($0.localizedDescription)" }
            Task { @MainActor in
                if let text, final || self?.diagnostics["fileTranscript"] == "pending" { self?.diagnostics["fileTranscript"] = text }
                if let failure { self?.diagnostics["fileError"] = failure }
            }
        }
    }

    /// For the CLI: what the last listen saw.
    var state: [String: Any] {
        var json: [String: Any] = diagnostics
        json["listening"] = listening
        json["busy"] = busy
        json["transcript"] = transcript
        json["reply"] = reply
        json["orchestrator"] = orchestrator.rawValue
        json["hotkeyTaken"] = Hotkey.voiceTaken
        json["steps"] = steps
        json["handledLocally"] = handledLocally
        json["jobs"] = jobs.map { ["request": $0.request, "running": $0.running, "steps": $0.steps, "reply": $0.reply, "error": $0.error ?? "", "tasks": Array($0.taskIDs)] as [String: Any] }
        json["microphones"] = Microphone.devices().map(\.name)
        json["microphone"] = Microphone.active?.name ?? "system default"
        if let panel {
            json["panelVisible"] = panel.isVisible
            json["panelFrame"] = "\(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)) \(Int(panel.frame.width))x\(Int(panel.frame.height))"
            json["panelOnScreen"] = panel.screen != nil
            json["panelKey"] = panel.isKeyWindow
        } else {
            json["panelVisible"] = false
        }
        json["screens"] = NSScreen.screens.map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        if let error { json["error"] = error }
        return json
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

    func stopListening() {
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
        guard !clean.isEmpty else { return }
        transcript = clean
        error = nil
        reply = ""
        steps = []
        // Fast path: a clear command runs here in a few milliseconds. Compound sentences, sentences no rule
        // matched, and misses ("no task matches") go to the AI, which can search and reason.
        let intent = VoiceIntent.parse(clean)
        let matched = intent != .add(title: clean)
        let compound = clean.range(of: #"\b(and|then|also)\b|[,;]"#, options: .regularExpression) != nil
        if orchestrator == .builtin || !orchestrator.isInstalled || (matched && !compound) {
            let answer = model.perform(intent)
            if orchestrator == .builtin || !orchestrator.isInstalled || !answer.hasPrefix("No open task") {
                handledLocally = true
                reply = answer
                steps = []
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2.5))
                    if self?.busy == false, self?.listening == false { self?.close() }
                }
                return
            }
        }
        handledLocally = false
        let job = AgentJob(request: clean, orchestrator: orchestrator, contextTaskID: model.selectedTask.map { String($0.agentID.prefix(8)) })
        jobs.append(job)
        current = job
        mirror(job)
        let prompt = prompt(for: clean)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(job, prompt: prompt)
            } catch {
                job.error = error.localizedDescription
            }
            job.finishedAt = .now
            self.attach(job)
            self.mirror(job)
        }
    }

    /// Hands a task to the agent in its own git worktree of the project's repository.
    /// Progress and the answer land on the card like any job; the branch stays for the user to open or discard.
    func handoff(_ task: TaskItem) throws {
        guard let project = task.project, let repo = project.repoPath else {
            throw HandoffError.message("Set the project's repository folder first (right-click the project in the sidebar).")
        }
        guard Worktree.isRepository(repo) else { throw HandoffError.message("\(repo) is not a git repository.") }
        let which = orchestrator == .builtin ? (Orchestrator.claude.isInstalled ? Orchestrator.claude : .codex) : orchestrator
        guard which.isInstalled else { throw VoiceError.notInstalled(which.title) }
        let id = String(task.agentID.prefix(8))
        let folder = try Worktree.create(repo: repo, id: id)
        let job = AgentJob(request: "Work on “\(task.title)”", orchestrator: which, contextTaskID: id)
        job.repo = repo
        job.worktree = folder
        job.taskIDs = [id]
        jobs.append(job)
        task.agentBranch = Worktree.branch(for: id)
        task.agentReply = nil
        task.isDoing = true
        model.save()
        let prompt = HandoffPrompt.text(task: task, project: project)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(job, prompt: prompt)
            } catch {
                job.error = error.localizedDescription
            }
            job.finishedAt = .now
            // Done is what the branch says, not what the agent says.
            let summary = Worktree.summary(repo: repo, id: id)
            if summary.commits == 0, job.error == nil {
                job.error = "The agent finished without committing anything. " + job.reply
            } else if job.error == nil {
                job.reply = "\(summary.commits) commit\(summary.commits == 1 ? "" : "s") on \(Worktree.branch(for: id))" +
                    (summary.stat.isEmpty ? "" : ", \(summary.stat)") +
                    (job.costUSD.map { String(format: ", $%.2f", $0) } ?? "") + ".\n" + job.reply
            }
            self.attach(job)
            self.mirror(job)
        }
    }

    /// Writes the job's answer onto the tasks it touched (ids in its commands, the selected task,
    /// and tasks it created), and tells the user when the panel is closed.
    func attach(_ job: AgentJob) {
        var ids = job.taskIDs
        if let context = job.contextTaskID { ids.insert(context) }
        let all = (try? model.context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var touched = all.filter { task in ids.contains(String(task.agentID.prefix(8))) || task.createdAt >= job.startedAt }
        if touched.isEmpty, let context = model.selectedTask { touched = [context] }
        let text = job.error ?? job.reply
        guard !text.isEmpty else { return }
        for task in touched {
            task.agentReply = text
            task.agentReplyAt = .now
        }
        model.save()
        if !Store.isOverridden, !isShown || current !== job {
            Notifier.post(job.error == nil ? "AI done" : "AI could not finish", text)
        }
    }

    private func prompt(for text: String) -> String {
        var context = "Open page: \(model.sidebar?.title ?? "none"). Projects: \(model.projects.map(\.name).joined(separator: ", ")). " +
            "Spoken project or task names may be misheard; match them to the closest real name."
        if let task = model.selectedTask { context += " Selected task: “\(task.title)” (id \(task.agentID.prefix(8)))." }
        return """
        You control the OpticalFlow task app on this Mac through the `opticalflow` command (run `opticalflow help` for the list; always add --json). \
        The user said, by voice: "\(text)". \(context) \
        Do what they asked with opticalflow commands only: find tasks with `tasks list --search`, add with `tasks add`, change with `tasks update` \
        (--priority high for urgent, --notes to guide the work, --due for dates), `tasks complete`, `session start --task <id>`, `session stop`. \
        Never delete anything. Then answer in one short spoken sentence, plain text, no markdown.
        """
    }

    private func run(_ job: AgentJob, prompt: String) async throws {
        let which = job.orchestrator
        guard let path = which.path else { throw VoiceError.notInstalled(which.title) }
        let workdir = Store.isOverridden ? "/tmp/OpticalFlow-agent"
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpticalFlow/agent").path
        try? FileManager.default.createDirectory(atPath: workdir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = job.isHandoff ? which.handoffArguments(prompt: prompt) : which.arguments(prompt: prompt, workdir: workdir)
        process.currentDirectoryURL = job.worktree ?? URL(fileURLWithPath: workdir)
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [env["PATH"] ?? "/usr/bin:/bin", "\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"].joined(separator: ":")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        job.process = process
        let errHandle = err.fileHandleForReading
        async let stderr = Task.detached { errHandle.readDataToEndOfFile() }.value
        // Both agents stream one JSON event per line; each command they run becomes a step on screen.
        var answer = ""
        for try await line in out.fileHandleForReading.bytes.lines {
            guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let step = Self.step(in: event), job.steps.last != step {   // the stream repeats a message event
                job.steps.append(step)
                for match in step.matches(of: /\b[0-9a-f]{8}\b/) { job.taskIDs.insert(String(match.output)) }
                mirror(job)
            }
            if let final = Self.answer(in: event) { answer = final }
            if event["type"] as? String == "result", let cost = event["total_cost_usd"] as? Double { job.costUSD = cost }
            if event["type"] as? String == "turn.completed", let usage = event["usage"] as? [String: Any], let tokens = usage["output_tokens"] as? Int {
                job.steps.append("\(tokens) output tokens")
            }
        }
        let errors = String(decoding: await stderr, as: UTF8.self)
        process.waitUntilExit()
        job.process = nil
        guard process.terminationStatus == 0 || !answer.isEmpty else {
            throw VoiceError.failed(which.title, errors.split(separator: "\n").suffix(3).joined(separator: " "))
        }
        job.reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A command the agent ran, as a short line: "tasks update 3f2a --priority high".
    private static func step(in event: [String: Any]) -> String? {
        var command: String?
        if event["type"] as? String == "assistant",
           let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] {
            command = content.lazy.compactMap { ($0["input"] as? [String: Any])?["command"] as? String }.first
        }
        if event["type"] as? String == "item.started" || event["type"] as? String == "item.completed",
           let item = event["item"] as? [String: Any], item["type"] as? String == "command_execution" {
            if event["type"] as? String == "item.completed" { return nil }
            command = item["command"] as? String
        }
        guard var text = command else { return nil }
        text = text.replacingOccurrences(of: "opticalflow ", with: "").replacingOccurrences(of: " --json", with: "")
        text = text.replacingOccurrences(of: #"^(/bin/)?(ba|z)?sh -lc '?|'?$"#, with: "", options: .regularExpression)
        return text.count > 90 ? String(text.prefix(90)) + "…" : text
    }

    /// The agent's final sentence.
    private static func answer(in event: [String: Any]) -> String? {
        if event["type"] as? String == "result", let text = event["result"] as? String { return text }
        if event["type"] as? String == "item.completed", let item = event["item"] as? [String: Any],
           item["type"] as? String == "agent_message", let text = item["text"] as? String { return text }
        return nil
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 160),
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

    /// The panel follows its content's height, keeping its top edge where it is.
    func fit(height: CGFloat) {
        guard let panel, height > 0 else { return }
        let target = ceil(height)
        let current = panel.contentRect(forFrameRect: panel.frame).height
        guard abs(current - target) > 1 else { return }
        var frame = panel.frame
        frame.origin.y -= target - current
        frame.size.height += target - current
        panel.setFrame(frame, display: true, animate: panel.isVisible)
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
                Text(headline(voice))
                    .font(.headline)
                    .contentTransition(.opacity)
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
        .animation(.default, value: voice.steps.count)
        .animation(.default, value: voice.reply)
        .onAppear { focused = true }
    }

    private func footer(_ voice: VoiceAgent) -> String {
        if voice.listening { return "Pause to send, or press Return. Escape cancels." }
        if voice.busy { return "\(voice.orchestrator.title) is working. Escape closes this; the result lands on the task and under the toolbar sparkles." }
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
