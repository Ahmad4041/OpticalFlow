import AppKit
import AVFoundation
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
        guard let today = model.addTask(title: "Due today", on: .list(.today)) else { return check("S-001 Today add", false) }
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
        let banked = model.session?.seconds ?? -1
        model.idleOverride = 0
        model.keepIdleTime()
        check("S-015 Keep adds the idle time and resumes", !model.paused && (model.session?.seconds ?? 0) >= banked + 399, "\(model.session?.seconds ?? -1) vs \(banked)")
        model.idleOverride = 400
        model.debugAdvance(seconds: 0)
        let beforeDiscard = model.session?.seconds ?? -1
        model.idleOverride = 0
        model.discardIdleTime()
        check("S-015 Discard resumes without the idle time", !model.paused && model.session?.seconds == beforeDiscard)
        model.stopSession()

        // S-016
        let fromXcode = FrontmostContext(appName: "Xcode", url: nil)
        check("S-016 the frontmost app goes into the notes", fromXcode.notes == "From Xcode")
        let fromSafari = FrontmostContext(appName: "Safari", url: "https://example.com")
        check("S-016 a browser URL goes into the notes", fromSafari.notes == "From Safari: https://example.com")
        check("S-016 OpticalFlow itself adds nothing", FrontmostContext(appName: "").notes.isEmpty)

        // S-008
        let recording = Recording(url: URL(fileURLWithPath: "/tmp/OpticalFlow-movies/selftest.mp4"), session: nil)
        recording.startedAt = Date.now.addingTimeInterval(-95)
        context.insert(recording)
        model.recorder.recording = recording
        model.complete(today)
        model.recorder.recording = nil
        check("S-008 completing a task while recording adds a chapter",
              recording.chapters.count == 1 && abs((recording.chapters.first?.offset ?? 0) - 95) < 2)
        check("S-008 the chapter list starts at 0:00", recording.chapterText == "0:00 Recording\n1:35 Due today", recording.chapterText)
        recording.copyChapters()
        check("S-008 Copy puts the list on the pasteboard", NSPasteboard.general.string(forType: .string) == recording.chapterText)

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
            let composite = try await model.trim(original, start: 1, end: 3, withCamera: true)
            let asset = AVURLAsset(url: composite.url)
            let compositeSeconds = try await asset.load(.duration).seconds
            let size = try await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
            check("S-012 the composite keeps the screen size and range", abs(compositeSeconds - 2) < 0.3 && size == CGSize(width: 320, height: 240), "\(compositeSeconds) \(size)")
            check("S-012 the composite is named with camera", composite.url.lastPathComponent.hasSuffix("with camera.mp4"))
            check("S-012 the composite has one video track", try await asset.loadTracks(withMediaType: .video).count == 1)
            original.cameraOffset = 2.5   // camera woke up late: only its first 0.5 s overlap the 1...3 range
            let late = try await model.trim(original, start: 1, end: 3, withCamera: true)
            let lateSeconds = try await AVURLAsset(url: late.url).load(.duration).seconds
            check("S-012 a late camera keeps the screen's length", abs(lateSeconds - 2) < 0.3, "\(lateSeconds)")
        } catch {
            check("S-009/S-012 export", false, "\(error)")
        }
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

/// A short silent clip with a keyframe on every frame, so a passthrough trim is exact.
enum TestVideo {
    static func make(at url: URL, seconds: Int, width: Int = 320, height: Int = 240) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
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
}
