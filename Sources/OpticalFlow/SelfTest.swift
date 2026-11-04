import AppKit
import AVFoundation
import CryptoKit
import SwiftData
import OpticalFlowKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/OpticalFlow-self.store ~/Applications/OpticalFlow.app/Contents/MacOS/OpticalFlow --selftest
/// (tools/selftest.sh does this.) One check per acceptance line that has logic.
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            await run(model: model)
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func run(model: AppModel) async {
        let context = model.context
        // The Mac may really be idle while this runs; only S-015 sets idle on purpose.
        model.idleOverride = 0
        func taskCount() -> Int { (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? -1 }
        func sessionCount() -> Int { (try? context.fetchCount(FetchDescriptor<Session>())) ?? -1 }

        // S-001
        let before = taskCount()
        model.sidebar = .list(.inbox)
        guard let task = model.addTask(title: "  Write   tests ") else { return check("S-001 Return adds a task", false) }
        check("S-001 Return adds a task", taskCount() == before + 1)
        check("S-001 the title is cleaned", task.title == "Write tests")
        check("S-001 an Inbox task has no project and no due", task.project == nil && task.due == nil)
        check("S-001 an empty title is rejected", model.addTask(title: "   ") == nil && taskCount() == before + 1)
        guard let today = model.addTask(title: "Ship the build", on: .list(.today)) else { return check("S-001 Today add", false) }
        check("S-001 a Today task is due today", Calendar.current.isDateInToday(today.due ?? .distantPast))
        guard let someday = model.addTask(title: "Later", on: .list(.someday)) else { return check("S-001 Someday add", false) }
        check("S-001 a Someday task is flagged", someday.isSomeday)
        try? context.save()
        let reopened = (try? ModelContext(model.container).fetchCount(FetchDescriptor<TaskItem>())) ?? -1
        check("S-001 tasks survive a reopen", reopened == before + 3, "\(reopened) vs \(before + 3)")

        // S-002
        model.selection = task.id
        model.completeSelected()
        let completedAt = task.completedAt
        check("S-002 Command-K completes the selected task", completedAt != nil)
        model.complete(task)
        check("S-002 completing again is a no-op", task.completedAt == completedAt)
        check("S-002 a fresh done task still shows in its list", model.tasks(for: .list(.inbox)).contains(task))
        check("S-002 Command-Z restores the task", model.undoComplete() && task.completedAt == nil)
        check("S-002 nothing left to undo", !model.undoComplete())

        // S-003
        check("S-003 Today lists the task due today", model.tasks(for: .list(.today)).contains(today))
        check("S-003 Inbox hides a Someday task", !model.tasks(for: .list(.inbox)).contains(someday))
        check("S-003 Someday lists it", model.tasks(for: .list(.someday)).contains(someday))
        model.sidebar = Page.fixed[1]
        check("S-003 Command-2 selects Today", model.sidebar == .list(.today))

        // S-004
        model.projectPrompt = .new
        model.commitProjectPrompt(name: "Test project")
        guard case .project(let projectID)? = model.sidebar, let project = model.project(projectID) else {
            return check("S-004 New Project creates and selects a project", false)
        }
        check("S-004 New Project creates and selects a project", project.name == "Test project")

        // S-052: the editor opens with the project's values and saves name, color, icon, and image together.
        model.projectPrompt = .edit(project)
        var projectDraft = model.draft(for: .edit(project))
        check("S-052 Edit opens with the current name", projectDraft.name == "Test project" && projectDraft.symbol == ProjectSymbol.default)
        projectDraft.name = "Renamed project"
        projectDraft.color = .teal
        projectDraft.symbol = "hammer.fill"
        model.commitProjectPrompt(projectDraft)
        check("S-052 Save renames, recolors, and sets the icon",
              project.name == "Renamed project" && project.colorName == "teal" && project.symbol == "hammer.fill" && model.projectPrompt == nil)
        let logo = Recorder.directory.appending(path: "selftest-logo.png")
        let wide = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        try? FileManager.default.createDirectory(at: Recorder.directory, withIntermediateDirectories: true)
        try? wide?.representation(using: .png, properties: [:])?.write(to: logo)
        let thumb = ProjectImage.thumbnail(of: logo).flatMap { NSBitmapImageRep(data: $0) }
        check("S-052 a picture becomes a 128 px square", thumb?.pixelsWide == 128 && thumb?.pixelsHigh == 128, "\(String(describing: thumb?.size))")
        check("S-052 a file that is not an image is refused", ProjectImage.thumbnail(of: Store.url) == nil)
        model.projectPrompt = .edit(project)
        projectDraft.imageData = ProjectImage.thumbnail(of: logo)
        model.commitProjectPrompt(projectDraft)
        check("S-052 the image is kept with the project", project.imageData != nil)
        model.projectPrompt = .edit(project)
        model.commitProjectPrompt(name: "   ")
        check("S-052 an empty name changes nothing", project.name == "Renamed project" && project.imageData != nil)
        check("S-052 an old color name still resolves", ProjectColor(rawValue: "purple") != nil && ProjectColor(rawValue: "blue") != nil)
        check("S-052 every offered icon is a real SF Symbol", ProjectSymbol.all.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
        model.sidebar = .project(project.uuid)
        check("S-052 Edit Project acts on the page shown", model.currentProject == project)
        task.project = project
        check("S-004 picking a project removes the task from Inbox", !model.tasks(for: .list(.inbox)).contains(task))
        check("S-004 the project page lists it", model.tasks(for: .project(projectID)).contains(task))
        model.selection = task.id
        model.setDue(.now)
        check("S-004 Command-T puts it in Today", model.tasks(for: .list(.today)).contains(task))
        model.setDue(nil)
        check("S-004 Shift-Command-T clears the due date", task.due == nil)

        // S-005
        model.selection = task.id
        model.startSession()
        guard let session = model.session else { return check("S-005 Command-Return starts a session", false) }
        check("S-005 the session has the task and no end", session.task == task && session.endedAt == nil)
        check("S-005 planned length comes from Settings", session.plannedMinutes == model.plannedMinutes)
        check("S-005 the menu bar shows the countdown", model.menuLabel == Countdown.clock(model.plannedMinutes * 60), model.menuLabel ?? "nil")
        model.debugAdvance(seconds: model.plannedMinutes * 60 + 5)
        check("S-005 overflow shows +00:05", model.menuLabel == "+00:05", model.menuLabel ?? "nil")
        model.startSession(on: today)
        check("S-005 starting again stops the first", session.endedAt != nil && model.session?.task == today)

        // S-006
        model.pause()
        check("S-006 Pause stops the clock", model.paused && model.menuLabel?.hasPrefix("⏸") == true)
        model.resume()
        check("S-006 Resume continues", !model.paused)
        let sessions = sessionCount()
        model.stopSession()
        check("S-006 Stop ends the session", model.session == nil && sessionCount() == sessions)
        model.toggleSession()
        check("S-006 the hotkey with no session starts one on the selected task", model.session?.task == task)
        model.toggleSession()
        check("S-006 the hotkey with a session stops it", model.session == nil)
        check("S-006 Sessions page lists every session", sessionCount() == 3, "\(sessionCount())")

        // S-014
        model.startBreak(minutes: 5)
        check("S-014 Break 5 counts down in the menu bar", model.session == nil && model.menuLabel == "☕ 05:00", model.menuLabel ?? "nil")
        model.startSession(on: task)
        check("S-014 starting a session ends the break", model.breakUntil == nil && model.session != nil)
        model.startBreak(minutes: 15)
        check("S-014 a break from a running session stops it first", model.session == nil && model.breakRemaining == 900)
        model.endBreak()
        check("S-014 End Break clears the label", model.menuLabel == nil)

        // S-015
        model.startSession(on: task)
        model.idleOverride = 400
        model.debugAdvance(seconds: 0)
        check("S-015 five idle minutes pause the session", model.paused && model.idleSince != nil)
        let banked = model.elapsed
        model.idleOverride = 0
        model.keepIdleTime()
        check("S-015 Keep adds the idle time and resumes", !model.paused && model.elapsed >= banked + 399, "\(model.elapsed) vs \(banked)")
        model.idleOverride = 400
        model.debugAdvance(seconds: 0)
        let beforeDiscard = model.elapsed
        model.idleOverride = 0
        model.discardIdleTime()
        check("S-015 Discard resumes without the idle time", !model.paused && model.elapsed - beforeDiscard <= 1)
        model.stopSession()

        // S-016
        let fromXcode = FrontmostContext(appName: "Xcode", url: nil)
        check("S-016 the frontmost app goes into the notes", fromXcode.notes == "From Xcode")
        let fromSafari = FrontmostContext(appName: "Safari", url: "https://example.com")
        check("S-016 a browser URL goes into the notes", fromSafari.notes == "From Safari: https://example.com")
        check("S-016 OpticalFlow itself adds nothing", FrontmostContext(appName: "").notes.isEmpty)

        // S-017
        model.search = "WRITE tests"
        check("S-017 search matches title words in any case", model.matches(task))
        check("S-017 search skips other tasks", !model.matches(today))
        task.notes = "see the spec"
        model.search = "spec"
        check("S-017 search covers notes", model.matches(task))
        model.search = ""
        check("S-017 an empty search matches nothing", !model.matches(task))

        // S-019
        if let parsed = model.addTask(title: "Call the sponsor tomorrow", on: .list(.inbox)) {
            check("S-019 a trailing date word sets due and is cut from the title",
                  parsed.title == "Call the sponsor" && Calendar.current.isDateInTomorrow(parsed.due ?? .distantPast))
            check("S-019 the task shows in Upcoming", model.tasks(for: .list(.upcoming)).contains(parsed))
            context.delete(parsed)
        }
        if let plain = model.addTask(title: "Buy milk", on: .list(.inbox)) {
            check("S-019 a plain title keeps no due", plain.due == nil)
            context.delete(plain)
        }
        try? context.save()
        check("S-019 a deleted selection resolves to nil instead of crashing", model.selectedTask == nil)
        model.selection = task.id

        // S-020
        model.selection = task.id
        check("S-020 opticalflow://start starts a session on the selected task", model.handle(URL(string: "opticalflow://start")!) && model.session?.task == task)
        check("S-020 opticalflow://pause pauses", model.handle(URL(string: "opticalflow://pause")!) && model.paused)
        check("S-020 opticalflow://stop stops", model.handle(URL(string: "opticalflow://stop")!) && model.session == nil)
        check("S-020 start?task= finds a task by title", model.handle(URL(string: "opticalflow://start?task=ship%20the")!) && model.session?.task == today)
        model.stopSession()
        check("S-020 break?minutes=15 starts a break", model.handle(URL(string: "opticalflow://break?minutes=15")!) && model.breakRemaining == 900)
        model.endBreak()
        let added = taskCount()
        check("S-020 add?title= adds to Inbox", model.handle(URL(string: "opticalflow://add?title=From%20Shortcuts")!) && taskCount() == added + 1)
        check("S-020 an unknown command is refused", !model.handle(URL(string: "opticalflow://dance")!))
        model.selection = task.id

        // S-021
        model.miniTimer.show()
        check("S-021 the mini timer shows as a floating panel", model.miniTimer.isShown)
        model.miniTimer.hide()
        check("S-021 and hides", !model.miniTimer.isShown)

        // S-023
        model.move([task.uuid.uuidString], to: .list(.someday))
        check("S-023 dropping on Someday flags it and clears the date", task.isSomeday && task.due == nil)
        model.move([task.uuid.uuidString], to: .list(.today))
        check("S-023 dropping on Today sets due today and unflags", !task.isSomeday && model.tasks(for: .list(.today)).contains(task))
        model.move([task.uuid.uuidString], to: .list(.inbox))
        check("S-023 dropping on Inbox clears the project", task.project == nil && model.tasks(for: .list(.inbox)).contains(task))
        model.move([task.uuid.uuidString], to: .project(projectID))
        check("S-023 dropping on a project assigns it", task.project == project)
        check("S-025 each page has its own empty state", Page.list(.inbox).emptyState.title != Page.list(.today).emptyState.title)

        // S-034 / S-035
        model.move([task.uuid.uuidString], toColumn: .doing)
        check("S-034 Doing column sets the doing flag", task.boardColumn == .doing && task.isDoing)
        model.move([task.uuid.uuidString], toColumn: .backlog)
        check("S-034 Backlog column flags someday and clears doing", task.boardColumn == .backlog && task.isSomeday && !task.isDoing)
        model.move([task.uuid.uuidString], toColumn: .done)
        check("S-034 Done column completes", task.isDone)
        model.move([task.uuid.uuidString], toColumn: .todo)
        check("S-034 To Do column reopens", !task.isDone && !task.isSomeday && task.boardColumn == .todo)
        // S-038: the Focus view offers the Doing task on the current page, else the first open one.
        model.sidebar = .project(projectID)
        model.selection = nil
        check("S-038 Focus offers the first open task on the page", model.upNext == task, model.upNext?.title ?? "nil")
        model.move([task.uuid.uuidString], toColumn: .doing)
        check("S-038 a Doing task comes first", model.upNext == task && task.isDoing)
        model.sidebar = .sessions
        check("S-038 pages without tasks fall back to Today", model.upNext.map { model.tasks(for: .list(.today)).contains($0) } == true, model.upNext?.title ?? "nil")
        model.sidebar = .project(projectID)

        // S-039: the board adds tasks into a column.
        guard let boardProject = model.project(projectID),
              let card = model.addTask(title: "Board card fri", project: boardProject, column: .doing) else { return check("S-039 board add", false) }
        check("S-039 a board add lands in its column with the project", card.project == boardProject && card.boardColumn == .doing && card.due != nil)
        model.addTask(title: "Parked", project: boardProject, column: .backlog)
        check("S-039 Backlog adds are Someday", model.tasks(for: .list(.someday)).contains { $0.title == "Parked" })
        model.delete(card)
        check("S-039 Delete on a card removes it", !model.tasks(for: .project(projectID)).contains(card))

        // S-040: priority.
        task.priority = .high
        check("S-040 priority round-trips", task.priority == .high && task.priorityRaw == 3)
        check("S-040 Focus prefers the urgent task", model.upNext == task || model.upNext?.isDoing == true)
        task.priority = .none

        // S-041: the built-in voice orchestrator.
        model.sidebar = .list(.inbox)
        var reply = model.perform(VoiceIntent.parse("add a task call the bank tomorrow"))
        let bank = model.tasks(for: .list(.upcoming)).first { $0.title == "Call the bank" || $0.title == "call the bank" }
        check("S-041 'add a task' adds it with its date", bank != nil && reply.hasPrefix("Added"), reply)
        reply = model.perform(.setPriority(match: "call the bank", .high))
        check("S-041 'make X urgent' sets high priority", bank?.priority == .high, reply)
        reply = model.perform(.addNote(match: "the bank", note: "ask about the card"))
        check("S-041 a note lands on the matching task", bank?.notes.contains("ask about the card") == true, reply)
        reply = model.perform(.start(match: "bank"))
        check("S-041 'start X' starts a session on it", model.session?.task == bank, reply)
        reply = model.perform(.stop)
        check("S-041 'stop the session' stops it", model.session == nil, reply)
        reply = model.perform(.complete(match: "call the bank"))
        check("S-041 'complete X' completes it", bank?.isDone == true, reply)
        reply = model.perform(.complete(match: "zebra quantum"))
        check("S-041 no match is reported, nothing changes", reply.hasPrefix("No open task"), reply)
        check("S-041 orchestrators report install state", Orchestrator.builtin.isInstalled)

        // S-044: dates and times in plain words.
        guard let bank = model.addTask(title: "Call the bank tomorrow at 3pm", on: .list(.inbox)) else { return check("S-044 add", false) }
        let threeTomorrow = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)!
        check("S-044 'tomorrow at 3pm' leaves the title and sets date and time", bank.title == "Call the bank" && bank.hasDueTime && abs(bank.due!.timeIntervalSince(threeTomorrow)) < 60, "\(bank.title) \(String(describing: bank.due))")
        check("S-044 a timed task shows in Upcoming", model.tasks(for: .list(.upcoming)).contains(bank))
        model.delete(bank)

        // S-045: spoken project names, even misheard.
        model.projectPrompt = .new
        model.commitProjectPrompt(name: "Fordan")
        guard let fordan = model.projects.first(where: { $0.name == "Fordan" }) else { return check("S-045 project", false) }
        check("S-045 'for than' finds Fordan", model.project(matching: "for than") == fordan)
        check("S-045 an unrelated word finds nothing", model.project(matching: "groceries") == nil)
        var spoken = model.perform(VoiceIntent.parse("add a task buy pizza in for than"))
        check("S-045 'add X in <project>' files it there", model.tasks(for: .project(fordan.uuid)).contains { $0.title == "buy pizza" }, spoken)
        spoken = model.perform(VoiceIntent.parse("add a task to Fordan: order the stickers tomorrow"))
        check("S-045 'add a task to <project>: X' files it with its date", model.tasks(for: .project(fordan.uuid)).contains { $0.title == "order the stickers" && $0.due != nil }, spoken)
        model.sidebar = .list(.inbox)
        model.deleteProject(fordan)

        // S-046: deleting a task keeps its sessions, without a dead pointer.
        guard let doomed = model.addTask(title: "Doomed", on: .list(.inbox)) else { return check("S-046 add", false) }
        model.startSession(on: doomed)
        model.stopSession()
        let doomedSessions = (try? context.fetch(FetchDescriptor<Session>()))?.filter { $0.task == doomed } ?? []
        check("S-046 the session points at the task", doomedSessions.count == 1)
        model.delete(doomed)
        check("S-046 after delete the session has no task and reads safely", doomedSessions.first.map { $0.task == nil && ($0.task?.isDone ?? false) == false } == true)

        // S-047: an AI job's answer lands on the tasks it touched.
        guard let aiTask = model.addTask(title: "Agent target", on: .list(.inbox)) else { return check("S-047 add", false) }
        let job = AgentJob(request: "make agent target urgent", orchestrator: .claude, contextTaskID: nil)
        job.taskIDs = [String(aiTask.agentID.prefix(8))]
        job.reply = "Done, it is urgent now."
        job.finishedAt = .now
        model.voice.jobs.append(job)
        model.voice.attach(job)
        check("S-047 the reply is written on the touched task", aiTask.agentReply == "Done, it is urgent now." && aiTask.agentReplyAt != nil)
        check("S-047 finished jobs clear", { model.voice.clearFinishedJobs(); return model.voice.jobs.isEmpty }())
        // S-053: the updater reads a release, refuses a bad download, and accepts a good one without touching the app.
        await updateChecks(model)
        // S-051: an agent run never inherits another tool's API routing.
        let agentEnv = Orchestrator.environment(from: ["ANTHROPIC_BASE_URL": "http://proxy", "OPENAI_BASE_URL": "http://proxy", "OPENAI_API_BASE": "x", "HOME": "/h", "PATH": "/usr/bin"])
        check("S-051 base URLs are dropped and PATH gains the tool folders",
              agentEnv.keys.sorted() == ["HOME", "PATH"] && agentEnv["PATH"]!.hasPrefix("/usr/bin:") && agentEnv["PATH"]!.hasSuffix("/opt/homebrew/bin"), "\(agentEnv)")
        model.delete(aiTask)

        // S-048: chapter markers while recording.
        check("S-048 a mark without a recording says so", model.mark() == nil && model.perform(.mark(title: nil)).hasPrefix("No recording"))
        check("S-048 chapter issues are plain words", ChapterList.issues(opening: "Start", marks: []).first?.contains("at least 3") == true)

        // S-049: deadline separate from the plan, and repeats.
        guard let invoice = model.addTask(title: "Send the invoice by friday", on: .list(.inbox)) else { return check("S-049 add", false) }
        check("S-049 'by friday' is a deadline, not a plan", invoice.title == "Send the invoice" && invoice.deadline != nil && invoice.due == nil)
        check("S-049 a deadline alone lists in Upcoming", model.tasks(for: .list(.upcoming)).contains(invoice))
        guard let rent = model.addTask(title: "Pay rent every month on the 1st", on: .list(.inbox)) else { return check("S-049 add rent", false) }
        check("S-049 'every month on the 1st' repeats monthly", rent.repeatRule == .monthly && rent.due != nil, rent.repeatRaw)
        let firstDue = rent.due!
        model.complete(rent)
        check("S-049 completing a repeat moves it forward and keeps it open", !rent.isDone && rent.due! > firstDue, "\(String(describing: rent.due))")
        model.delete(invoice)
        model.delete(rent)

        // S-042: a hand-off's worktree, summary, and discard, on a throwaway repo.
        let repo = "/tmp/OpticalFlow-selftest-repo"
        try? FileManager.default.removeItem(atPath: repo)
        try? FileManager.default.removeItem(at: Worktree.root)
        try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = try? Worktree.git(["init", "-q", "-b", "main"], in: repo)
        _ = try? Worktree.git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"], in: repo)
        check("S-042 a folder with .git is a repository", Worktree.isRepository(repo) && !Worktree.isRepository("/tmp"))
        let wt = try? Worktree.create(repo: repo, id: "abcd1234")
        check("S-042 the worktree is outside the repo on its own branch", wt != nil && wt!.path.hasPrefix(Worktree.root.path) && (try? Worktree.git(["rev-parse", "--abbrev-ref", "HEAD"], in: wt!.path)) == "opticalflow/abcd1234")
        check("S-042 no commits means not done", Worktree.summary(repo: repo, id: "abcd1234").commits == 0)
        try? "hello".write(toFile: wt!.appending(path: "a.txt").path, atomically: true, encoding: .utf8)
        _ = try? Worktree.git(["add", "."], in: wt!.path)
        _ = try? Worktree.git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "work"], in: wt!.path)
        let summary = Worktree.summary(repo: repo, id: "abcd1234")
        check("S-042 the branch summary counts commits and files", summary.commits == 1 && summary.stat.contains("1 file"), "\(summary)")
        Worktree.discard(repo: repo, id: "abcd1234")
        check("S-042 discard removes the folder and the branch", !FileManager.default.fileExists(atPath: wt!.path) && (try? Worktree.git(["rev-parse", "--verify", "--quiet", "refs/heads/opticalflow/abcd1234"], in: repo)) == nil)
        guard let handed = model.addTask(title: "Agent task", on: .list(.inbox)) else { return check("S-042 add", false) }
        check("S-042 a task without a repository explains what to set", (try? model.voice.handoff(handed)) == nil)
        model.delete(handed)
        try? FileManager.default.removeItem(atPath: repo)

        // S-043: subtasks.
        guard let steps = model.addTask(title: "Ship the release", on: .list(.inbox)) else { return check("S-043 add", false) }
        steps.subtasks = Checklist.parse("Tag it; Build; Upload")
        steps.subtasks[0].isDone = true
        model.save()
        check("S-043 a task keeps its subtasks and progress", steps.subtasks.count == 3 && Checklist.progress(steps.subtasks) == (1, 3))
        reply = model.perform(VoiceIntent.parse("add a subtask to ship the release: write the notes"))
        check("S-043 'add a subtask to X' appends one", steps.subtasks.last?.title == "write the notes", reply)
        steps.subtasks[1].isDone = true
        model.save()
        let reopenedSteps = (try? context.fetch(FetchDescriptor<TaskItem>()))?.first { $0.title == "Ship the release" }
        check("S-043 subtasks survive a fetch", reopenedSteps?.subtasks.filter(\.isDone).count == 2)
        model.delete(steps)
        model.sidebar = .project(projectID)
        let picks = model.recorder.pickRequests
        model.startSession(on: task)
        check("S-035 a session puts the task in Doing", task.isDoing)
        check("S-035 a task without the flag does not open the recorder", model.recorder.pickRequests == picks)
        model.stopSession()
        task.recordsSession = true
        model.startSession(on: task)
        check("S-035 a task with Record Sessions opens the recorder", model.recorder.pickRequests == picks + 1)
        model.stopSession()
        task.recordsSession = false

        // S-055: Start from the app asks; the answer sets the length and whether the picker opens.
        model.requestSession(on: task)
        check("S-055 Start from the app opens the prompt", model.startPrompt.isShown && model.startPrompt.task == task && model.session == nil)
        model.startPrompt.close()
        model.startSession(on: task, minutes: 40, record: false)
        check("S-055 Start Timer starts the confirmed length and records nothing",
              model.session?.plannedMinutes == 40 && model.recorder.pickRequests == picks + 1)
        model.stopSession()
        model.startSession(on: task, minutes: 25, record: true)
        check("S-055 Record and Start opens the recording picker", model.recorder.pickRequests == picks + 2)
        model.stopSession()
        StartPrompt.asks = false
        model.requestSession(on: task)
        check("S-055 with asking off, Start begins at once", model.session != nil && !model.startPrompt.isShown)
        model.stopSession()
        StartPrompt.asks = true
        model.selection = task.id
        model.toggleSession()
        check("S-055 the global hotkey never asks", model.session != nil && !model.startPrompt.isShown)
        model.stopSession()

        // S-056: checking the last subtask completes the task; a half-done list does not.
        guard let list = model.addTask(title: "Checklist target", on: .list(.inbox)) else { return check("S-056 add", false) }
        list.subtasks = [ChecklistItem(title: "One"), ChecklistItem(title: "Two")]
        model.setSubtask(list.subtasks[0].id, of: list, done: true)
        check("S-056 one of two checked keeps the task open", !list.isDone)
        model.setSubtask(list.subtasks[1].id, of: list, done: true)
        check("S-056 the last subtask checked completes the task", list.isDone)
        guard let monthly = model.addTask(title: "Pay rent every month", on: .list(.inbox)) else { return check("S-056 add repeat", false) }
        monthly.subtasks = [ChecklistItem(title: "Transfer")]
        let dueBefore = monthly.due
        model.setSubtask(monthly.subtasks[0].id, of: monthly, done: true)
        check("S-056 a repeating task moves on and clears its checklist",
              !monthly.isDone && monthly.due != dueBefore && monthly.subtasks.allSatisfy { !$0.isDone }, "\(String(describing: monthly.due)) \(monthly.repeatRule)")
        model.delete(list)
        model.delete(monthly)
        model.complete(task)
        check("S-034 completing clears doing", !task.isDoing)
        model.undoComplete()

        // S-036
        model.sidebar = .sessions
        model.selection = model.firstID(for: .sessions)
        check("S-036 selecting a session shows it", model.selectedSession != nil && model.selectedTask == nil)
        if let s = model.selectedSession {
            let n = sessionCount()
            model.deleteSession(s)
            check("S-036 Delete removes the session", sessionCount() == n - 1 && model.selection == nil)
        }
        model.showTask(task)
        check("S-036 Show Task selects the task on its page", model.selectedTask == task)

        // S-008
        let recording = Recording(url: URL(fileURLWithPath: "/tmp/OpticalFlow-movies/selftest.mp4"), session: nil)
        recording.startedAt = Date.now.addingTimeInterval(-95)
        context.insert(recording)
        model.recorder.recording = recording
        model.complete(today)
        model.recorder.recording = nil
        check("S-008 completing a task while recording adds a chapter",
              recording.chapters.count == 1 && abs((recording.chapters.first?.offset ?? 0) - 95) < 2)
        check("S-008 the chapter list starts at 0:00", recording.chapterText == "0:00 Recording\n1:35 Ship the build", recording.chapterText)
        recording.copyChapters()
        check("S-008 Copy puts the list on the pasteboard", NSPasteboard.general.string(forType: .string) == recording.chapterText)
        model.selection = recording.id
        check("S-010 a selected recording is not a task and does not crash the Task menu", model.selectedTask == nil && model.selectedRecording == recording)
        try? context.save()
        model.sidebar = .recordings
        model.selection = model.firstID(for: .recordings)
        check("S-010 the first recording selected the snapshot way resolves", model.selectedRecording != nil,
              "entity \(model.selection?.entityName ?? "nil")")
        model.selection = task.id

        // S-007 fix: mic and camera default on; the picker may call back twice; only one capture may start.
        check("S-007 microphone and camera are on by default", model.recorder.micEnabled && model.recorder.cameraEnabled,
              "mic \(model.recorder.micEnabled) camera \(model.recorder.cameraEnabled)")
        check("S-007 the first start claims the lock", model.recorder.claimStart())
        check("S-007 a second start while starting is refused", !model.recorder.claimStart())

        // S-009
        let source = Recorder.directory.appending(path: "selftest-source.mp4")
        do {
            try FileManager.default.createDirectory(at: Recorder.directory, withIntermediateDirectories: true)
            try await TestVideo.make(at: source, seconds: 4)
            let original = Recording(url: source, session: nil)
            original.duration = 4
            original.chapters = [ChapterMark(title: "Early", offset: 0.5), ChapterMark(title: "Kept", offset: 2)]
            context.insert(original)
            let trimmed = try await model.trim(original, start: 1, end: 3)
            let seconds = try await AVURLAsset(url: trimmed.url).load(.duration).seconds
            check("S-009 Export Trimmed writes the chosen range", abs(seconds - 2) < 0.3, "\(seconds)")
            check("S-009 chapters shift by the trimmed start", trimmed.chapters == [ChapterMark(title: "Kept", offset: 1)])
            check("S-009 the trimmed file sits next to the original", trimmed.url.deletingLastPathComponent() == source.deletingLastPathComponent() && trimmed.fileExists)
            // S-012
            let cameraSource = Recorder.directory.appending(path: "selftest-camera.mov")
            try await TestVideo.make(at: cameraSource, seconds: 4, width: 160, height: 120)
            original.cameraPath = cameraSource.path
            let composite = try await model.trim(original, start: 1, end: 3, options: ExportOptions(camera: true))
            let asset = AVURLAsset(url: composite.url)
            let compositeSeconds = try await asset.load(.duration).seconds
            let size = try await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
            check("S-012 the composite keeps the screen size and range", abs(compositeSeconds - 2) < 0.3 && size == CGSize(width: 320, height: 240), "\(compositeSeconds) \(size)")
            check("S-012 the composite is named with camera", composite.url.lastPathComponent.hasSuffix("with camera.mp4"))
            check("S-012 the composite has one video track", try await asset.loadTracks(withMediaType: .video).count == 1)
            // S-028 / S-029: every corner, shape, and blur renders through the compositor.
            let saved = model.recorder.cameraLayout
            model.recorder.cameraLayout = CameraLayout(corner: .topLeft, size: .large, shape: .rounded, blurBackground: true)
            let styled = try await model.trim(original, start: 1, end: 2.5, options: ExportOptions(camera: true))
            let styledSeconds = try await AVURLAsset(url: styled.url).load(.duration).seconds
            check("S-028 a rounded top-left large camera with blur exports", abs(styledSeconds - 1.5) < 0.3, "\(styledSeconds)")
            check("S-028 the layout is remembered", Prefs.store.data(forKey: "cameraLayout") != nil)
            model.recorder.cameraLayout = saved
            // S-027: the YouTube preset re-encodes to H.264.
            let yt = try await model.trim(original, start: 0, end: 2, options: ExportOptions(youtube: true))
            let ytTrack = try await AVURLAsset(url: yt.url).loadTracks(withMediaType: .video).first
            let ytCodec = (try await ytTrack?.load(.formatDescriptions))?.first.map { CMFormatDescriptionGetMediaSubType($0) }
            check("S-027 the YouTube export is H.264", ytCodec == kCMVideoCodecType_H264 && yt.url.lastPathComponent.hasSuffix("youtube.mp4"), "\(String(describing: ytCodec))")

            // S-031: a zoomed export follows a cursor track.
            let cursorURL = Recorder.directory.appending(path: "selftest-cursor.json")
            try JSONEncoder().encode(CursorTrack(samples: [.init(t: 0, x: 0.9, y: 0.9), .init(t: 2, x: 0.1, y: 0.1)])).write(to: cursorURL)
            original.cursorPath = cursorURL.path
            let zoomed = try await model.trim(original, start: 0.5, end: 3, options: ExportOptions(followCursor: true))
            let zoomedAsset = AVURLAsset(url: zoomed.url)
            let zoomedSize = try await zoomedAsset.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
            let zoomedSeconds = try await zoomedAsset.load(.duration).seconds
            check("S-031 a follow-cursor export keeps the frame size and range", zoomedSize == CGSize(width: 320, height: 240) && abs(zoomedSeconds - 2.5) < 0.3, "\(zoomedSize) \(zoomedSeconds)")
            check("S-031 the zoomed file is named", zoomed.url.lastPathComponent.hasSuffix("zoomed.mp4"))
            original.cameraOffset = 2.5   // camera woke up late: only its first 0.5 s overlap the 1...3 range
            let late = try await model.trim(original, start: 1, end: 3, options: ExportOptions(camera: true))
            let lateSeconds = try await AVURLAsset(url: late.url).load(.duration).seconds
            check("S-012 a late camera keeps the screen's length", abs(lateSeconds - 2) < 0.3, "\(lateSeconds)")

            // S-050: a tone for 1 s, 3 s of silence, a tone for 2 s. The pause goes, minus 0.2 s kept on each side.
            let spoken = Recorder.directory.appending(path: "selftest-spoken.mp4")
            try await TestVideo.make(at: spoken, seconds: 6, tone: [0..<1, 4..<6])
            let talk = Recording(url: spoken, session: nil)
            talk.duration = 6
            talk.chapters = [ChapterMark(title: "Intro", offset: 0.5), ChapterMark(title: "Lost", offset: 2), ChapterMark(title: "After", offset: 5)]
            context.insert(talk)
            let levels = try await Exporter.levels(of: spoken) ?? []
            let keep = SilenceCut.keep(levels: levels, step: SilenceCut.step, start: 0, end: 6)
            check("S-050 levels find the one pause", keep.count == 2 && abs(SilenceCut.length(keep) - 3.4) < 0.15, "\(keep)")
            let cut = try await model.trim(talk, start: 0, end: 6, options: ExportOptions(removeSilence: true))
            let cutSeconds = try await AVURLAsset(url: cut.url).load(.duration).seconds
            check("S-050 the export is shorter by the pause", abs(cutSeconds - 3.4) < 0.3 && cut.url.lastPathComponent.hasSuffix("no silence.mp4"), "\(cutSeconds) \(cut.url.lastPathComponent)")
            check("S-050 chapters move with the cut", cut.chapters.map(\.title) == ["Intro", "After"] && abs((cut.chapters.last?.offset ?? 0) - 2.4) < 0.15, "\(cut.chapters)")
            check("S-050 a silent clip reports no audio", try await Exporter.levels(of: source) == nil)
        } catch {
            check("S-009/S-012 export", false, "\(error)")
        }
    }

    /// A fake release in /tmp: this app zipped, its checksum, and a feed pointing at both.
    private static func updateChecks(_ model: AppModel) async {
        let dir = URL(fileURLWithPath: "/tmp/OpticalFlow-update-test")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appending(path: "OpticalFlow.zip"), sum = dir.appending(path: "OpticalFlow.zip.sha256"), bad = dir.appending(path: "bad.sha256")
        try? FileManager.default.removeItem(at: zip)
        do { try Worktree.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", Bundle.main.bundlePath, zip.path], in: dir.path) }
        catch { return check("S-053 zip the app", false, "\(error)") }
        let hex = SHA256.hash(data: (try? Data(contentsOf: zip)) ?? Data()).map { String(format: "%02x", $0) }.joined()
        try? "\(hex)  OpticalFlow.zip\n".write(to: sum, atomically: true, encoding: .utf8)
        try? "\(String(repeating: "0", count: 64))  OpticalFlow.zip\n".write(to: bad, atomically: true, encoding: .utf8)
        let current = model.updater.current
        let good = Release(version: current, notes: "", page: nil, zip: zip, checksum: sum)
        check("S-053 a release of this version is not offered", !(good.version > current))
        check("S-053 a higher version is offered", AppVersion("\(current.description).1")! > current)
        do {
            let app = try await model.updater.prepare(good)
            check("S-053 a matching download unpacks and verifies", Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier)
        } catch { check("S-053 a matching download unpacks and verifies", false, "\(error)") }
        var tampered = good
        tampered.checksum = bad
        do { _ = try await model.updater.prepare(tampered); check("S-053 a wrong checksum is refused", false) }
        catch { check("S-053 a wrong checksum is refused", "\(error.localizedDescription)".contains("checksum"), error.localizedDescription) }
        var mislabeled = good
        mislabeled.version = AppVersion("99.0.0")!
        do { _ = try await model.updater.prepare(mislabeled); check("S-053 a version that does not match the release is refused", false) }
        catch { check("S-053 a version that does not match the release is refused", error.localizedDescription.contains("99.0.0"), error.localizedDescription) }
        await model.updater.install(Release(version: AppVersion("99.0.0")!, notes: "", page: nil, zip: zip, checksum: sum))
        check("S-053 a test run never replaces the app", FileManager.default.fileExists(atPath: Bundle.main.bundlePath) && NSApp.isRunning)
        check("S-053 no automatic checks in a test run", Store.isOverridden)

        // The swap itself, on throwaway folders: the new copy takes the old one's place, and a failed move puts the old one back.
        let swap = dir.appending(path: "swap"), installed = swap.appending(path: "Installed.app"), fresh = swap.appending(path: "New.app")
        try? FileManager.default.removeItem(at: swap)
        try? FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try? "old".write(to: installed.appending(path: "v"), atomically: true, encoding: .utf8)
        try? "new".write(to: fresh.appending(path: "v"), atomically: true, encoding: .utf8)
        func runSwap(_ newPath: String) -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", Updater.swapScript, "updater", "999999", installed.path, newPath, "noopen"]
            try? p.run(); p.waitUntilExit()
            return p.terminationStatus
        }
        let swapped = runSwap(fresh.path)
        check("S-053 the swap puts the new app in place and removes the old one",
              swapped == 0 && (try? String(contentsOf: installed.appending(path: "v"), encoding: .utf8)) == "new"
              && !FileManager.default.fileExists(atPath: installed.path + ".old"), "status \(swapped)")
        let failed = runSwap(swap.appending(path: "Missing.app").path)
        check("S-053 a failed swap keeps the installed app", failed != 0 && (try? String(contentsOf: installed.appending(path: "v"), encoding: .utf8)) == "new")
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

/// A short clip with a keyframe on every frame, so a passthrough trim is exact. Silent unless `tone`
/// lists the seconds that carry a 440 Hz tone; then there is an audio track, quiet elsewhere.
enum TestVideo {
    static func make(at url: URL, seconds: Int, width: Int = 320, height: Int = 240, tone: [Range<Int>]? = nil) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        if let tone { try writeTone(tone, seconds: seconds, to: writer) }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        try flushAudio()
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw Exporter.ExportError.noVideo }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, frame % 2 == 0 ? 0x40 : 0xC0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// Adds a mono AAC track: a sine where `loud` says, digital silence elsewhere. Written before the video starts.
    private static func writeTone(_ loud: [Range<Int>], seconds: Int, to writer: AVAssetWriter) throws {
        let rate = 16000
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48000,
        ])
        var asbd = AudioStreamBasicDescription(mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
                                               mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw Exporter.ExportError.noVideo }
        writer.add(input)
        pending.append((input, { frame in
            let second = frame / rate
            return loud.contains { $0.contains(second) } ? 0.5 * sin(Float(frame) * 2 * .pi * 440 / Float(rate)) : 0
        }, format, seconds * rate))
    }

    private static var pending: [(AVAssetWriterInput, (Int) -> Float, CMAudioFormatDescription, Int)] = []

    /// Feeds every queued audio track in one go (short clips, so the whole track fits in memory).
    private static func flushAudio() throws {
        for (input, sample, format, frames) in pending {
            let bytes = frames * 4
            var samples = (0..<frames).map(sample)
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                               offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block else { throw Exporter.ExportError.noVideo }
            try samples.withUnsafeMutableBytes { raw in
                guard CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) == noErr
                else { throw Exporter.ExportError.noVideo }
            }
            var buffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
                                                                 presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &buffer)
            guard let buffer, input.append(buffer) else { throw Exporter.ExportError.noVideo }
            input.markAsFinished()
        }
        pending = []
    }
}
