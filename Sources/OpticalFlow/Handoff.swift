import AppKit
import Foundation
import OpticalFlowKit

/// Git worktrees for agent hand-offs: one branch and folder per task, outside the repo,
/// so a long run never touches the checkout you are working in. All calls are synchronous
/// git commands; they take well under a second.
enum Worktree {
    static var root: URL {
        if Store.isOverridden { return URL(fileURLWithPath: "/tmp/OpticalFlow-worktrees") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpticalFlow/worktrees")
    }

    static func branch(for id: String) -> String { "opticalflow/\(id)" }
    static func folder(for id: String) -> URL { root.appending(path: id) }

    /// Creates the branch from the repo's current HEAD and checks it out in its own folder.
    /// Reuses an existing worktree for the same id.
    static func create(repo: String, id: String) throws -> URL {
        let folder = folder(for: id)
        if FileManager.default.fileExists(atPath: folder.appending(path: ".git").path) { return folder }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let branch = branch(for: id)
        let exists = (try? git(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo)) != nil
        var args = ["worktree", "add"]
        if !exists { args += ["-b", branch] }
        args.append(folder.path)
        if exists { args.append(branch) }
        try git(args, in: repo)
        return folder
    }

    /// Commits on the branch that the base does not have, and the diff stat: "3 files changed, +40 -2".
    static func summary(repo: String, id: String) -> (commits: Int, stat: String, base: String) {
        let branch = branch(for: id)
        let base = (try? git(["symbolic-ref", "--short", "HEAD"], in: repo)) ?? "main"
        let log = (try? git(["rev-list", "--count", "\(base)..\(branch)"], in: repo)) ?? "0"
        let stat = (try? git(["diff", "--shortstat", "\(base)...\(branch)"], in: repo)) ?? ""
        return (Int(log) ?? 0, stat.trimmingCharacters(in: .whitespacesAndNewlines), base)
    }

    /// Removes the folder and the branch. Work that was never committed is lost; the caller confirms.
    static func discard(repo: String, id: String) {
        _ = try? git(["worktree", "remove", "--force", folder(for: id).path], in: repo)
        _ = try? git(["branch", "-D", branch(for: id)], in: repo)
    }

    /// Pushes the branch and opens a draft pull request in the browser with `gh`.
    static func openPullRequest(repo: String, id: String) throws {
        let branch = branch(for: id)
        try git(["push", "-u", "origin", branch], in: repo)
        guard let gh = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw HandoffError.message("gh is not installed. The branch \(branch) is pushed; open the pull request on GitHub.")
        }
        try run(gh, ["pr", "create", "--draft", "--fill", "--head", branch, "--web"], in: folder(for: id).path)
    }

    static func isRepository(_ path: String) -> Bool {
        (try? git(["rev-parse", "--is-inside-work-tree"], in: path)) == "true"
    }

    @discardableResult
    static func git(_ args: [String], in dir: String) throws -> String {
        try run("/usr/bin/git", args, in: dir)
    }

    @discardableResult
    static func run(_ executable: String, _ args: [String], in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HandoffError.message(errors.split(separator: "\n").last.map(String.init) ?? "\(args.first ?? "") failed")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HandoffError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The brief an agent gets when a task is handed over.
enum HandoffPrompt {
    static func text(task: TaskItem, project: Project) -> String {
        var brief = "Task: \(task.title)\n"
        if !task.notes.isEmpty { brief += "Notes:\n\(task.notes)\n" }
        if !task.subtasks.isEmpty {
            brief += "Steps:\n" + task.subtasks.map { "- [\($0.isDone ? "x" : " ")] \($0.title)" }.joined(separator: "\n") + "\n"
        }
        return """
        You are working in a git worktree on the branch for this task in the project “\(project.name)”. \
        Do the task below. Keep changes focused. Run the project's tests or build if there is one. \
        Commit your work on this branch with clear messages; do not push, do not merge, do not switch branches, \
        and do not touch files outside this worktree. When finished, reply with three short lines: what you changed, \
        what you verified, and anything left for a human.

        \(brief)
        """
    }
}
