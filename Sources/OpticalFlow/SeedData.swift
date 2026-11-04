import Foundation
import SwiftData
import OpticalFlowKit

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty store.
/// Only what a person can create in the app.
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.context
        guard ((try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0) == 0 else { return }
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: .now)! }

        let app = Project(name: "OpticalFlow", color: .blue)
        let stream = Project(name: "Stream setup", color: .purple)
        app.symbol = "hammer.fill"
        stream.symbol = "video.fill"
        context.insert(app)
        context.insert(stream)

        @discardableResult
        func task(_ title: String, project: Project? = nil, due: Date? = nil, someday: Bool = false,
                  done: Bool = false, notes: String = "", age: Int) -> TaskItem {
            let item = TaskItem(title: title)
            item.project = project
            item.due = due
            item.isSomeday = someday
            item.notes = notes
            item.createdAt = Date.now.addingTimeInterval(Double(-age) * 3_600)
            if done { item.completedAt = Date.now.addingTimeInterval(-3_600) }
            context.insert(item)
            return item
        }
        task("Reply to the sponsor email", age: 9)
        task("Order a second SSD for recordings", notes: "2 TB, NVMe, for the Thunderbolt dock.", age: 8)
        let login = task("Fix the login redirect loop", project: app, due: .now,
                         notes: "Repro: sign out, open /settings, sign in. Lands on / instead of /settings.", age: 7)
        login.isDoing = true
        login.recordsSession = true
        login.priority = .high
        login.agentReply = "Moved to Doing and set to high priority. The repro note is attached."
        login.agentReplyAt = .now.addingTimeInterval(-600)
        login.deadline = day(3)
        let rent = task("Pay the studio rent", project: stream, due: day(1), age: 6)
        rent.repeatRule = .monthly
        login.subtasks = [ChecklistItem(title: "Reproduce with a fresh profile", isDone: true),
                           ChecklistItem(title: "Write the regression test"),
                           ChecklistItem(title: "Fix the redirect")]
        task("Write the chapter export", project: app, due: day(-1), age: 6)
        let walkthrough = task("Record the SwiftData walkthrough", project: stream, due: .now, done: true, age: 5)
        task("Set up the OBS scene for the Mac stream", project: stream, due: day(2), age: 4).recordsSession = true
        task("Try the new ScreenCaptureKit picker API", project: app, due: day(5), age: 3)
        task("Publish the session recording", project: stream, due: day(1), age: 3)
        task("Write show notes for the stream", project: stream, due: day(2), age: 3)
        task("Learn Metal shaders for the intro animation", someday: true, age: 2)
        task("Build a Stream Deck plugin", project: stream, someday: true, age: 1)

        let first = Session(task: login, plannedMinutes: 25)
        first.startedAt = Date.now.addingTimeInterval(-3 * 3_600)
        first.endedAt = first.startedAt.addingTimeInterval(1_680)
        first.seconds = 1_620
        context.insert(first)

        let second = Session(task: walkthrough, plannedMinutes: 25)
        second.startedAt = day(-1).addingTimeInterval(-2 * 3_600)
        second.endedAt = second.startedAt.addingTimeInterval(1_750)
        second.seconds = 1_710
        context.insert(second)

        let recordingURL = Recorder.directory.appending(path: "2026-10-28 14.02.11.mp4")
        // A real short clip, so the detail's player and the row's thumbnail render in snapshots.
        Task {
            try? FileManager.default.createDirectory(at: Recorder.directory, withIntermediateDirectories: true)
            try? await TestVideo.make(at: recordingURL, seconds: 4)
        }
        let recording = Recording(url: recordingURL, session: second)
        recording.startedAt = second.startedAt
        recording.duration = 1_710
        recording.cameraPath = Recorder.directory.appending(path: "2026-10-28 14.02.11-camera.mov").path
        recording.chapters = [
            ChapterMark(title: "Add the model", offset: 312),
            ChapterMark(title: "Query in the list", offset: 905),
            ChapterMark(title: "Wrap up", offset: 1_600),
        ]
        context.insert(recording)
        try? context.save()
    }
}
