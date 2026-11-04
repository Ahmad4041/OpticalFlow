import AppKit
import CryptoKit
import Foundation
import OpticalFlowKit

/// Updates from GitHub Releases, without a framework: read the latest release, download its zip, check the
/// zip against the release's .sha256 file and the app inside against this one (bundle id, version, signature),
/// then quit, swap the bundle, and open the new one.
@Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate, available(Release), installing, failed(String)
    }

    static let feed = URL(string: ProcessInfo.processInfo.environment["APP_UPDATE_FEED"]
                          ?? "https://api.github.com/repos/Ahmad4041/OpticalFlow/releases/latest")!
    static let autoKey = "checksForUpdates"

    private(set) var state = State.idle
    private var started = false
    var current: AppVersion { AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") ?? AppVersion("0")! }

    var checksAutomatically: Bool {
        get { Prefs.store.object(forKey: Self.autoKey) as? Bool ?? true }
        set { Prefs.store.set(newValue, forKey: Self.autoKey) }
    }

    /// Once at launch and every day after, unless turned off. Never in a test run.
    func startAutomaticChecks() {
        guard !Store.isOverridden, !started else { return }
        started = true
        Task {
            try? await Task.sleep(for: .seconds(10))
            while true {
                if checksAutomatically { await check(userInitiated: false) }
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }

    /// Reads the feed. Asked from the menu, it always answers; in the background it speaks only about a new version not skipped.
    func check(userInitiated: Bool) async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            var request = URLRequest(url: Self.feed)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let release = Release.parse(github: data) else { throw UpdateError.message("The latest release has no app download.") }
            if release.version > current {
                state = .available(release)
                if userInitiated || Prefs.store.string(forKey: "skippedVersion") != release.version.description { offer(release) }
            } else {
                state = .upToDate
                if userInitiated { inform("OpticalFlow \(current) is the latest version.") }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { inform("Could not check for updates", detail: error.localizedDescription) }
        }
    }

    private func offer(_ release: Release) {
        guard !Store.isOverridden else { return }
        let alert = NSAlert()
        alert.messageText = "OpticalFlow \(release.version) is available"
        alert.informativeText = "You have \(current).\n\n" + String(release.notes.prefix(700))
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: Prefs.store.set(release.version.description, forKey: "skippedVersion")
        default: break
        }
    }

    /// Downloads and checks the new app, then hands over to a small shell script that waits for this app to quit.
    func install(_ release: Release) async {
        state = .installing
        do {
            let target = URL(fileURLWithPath: Bundle.main.bundlePath)
            guard !target.path.contains("/AppTranslocation/"),
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.message("Move OpticalFlow to your Applications folder first, then update. It runs from a place it cannot replace.")
            }
            let app = try await prepare(release)
            guard !Store.isOverridden else { throw UpdateError.message("A test run never replaces the app.") }
            try relaunch(replacing: target, with: app)
        } catch {
            state = .failed(error.localizedDescription)
            inform("The update was not installed", detail: error.localizedDescription)
        }
    }

    /// The new OpticalFlow.app, unpacked in a temporary folder and verified. Throws for any mismatch.
    func prepare(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OpticalFlow-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (sumData, _) = try await URLSession.shared.data(from: release.checksum)
        guard let expected = Release.digest(inChecksumFile: String(decoding: sumData, as: UTF8.self)) else {
            throw UpdateError.message("The release's checksum file is not readable.")
        }
        let (download, _) = try await URLSession.shared.download(from: release.zip)
        let zip = folder.appending(path: "update.zip")
        try FileManager.default.moveItem(at: download, to: zip)
        let actual = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.message("The download does not match the release's checksum.") }
        try Worktree.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path], in: folder.path)
        let app = folder.appending(path: "OpticalFlow.app")
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.message("The download is not OpticalFlow.")
        }
        guard let version = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), version == release.version else {
            throw UpdateError.message("The app in the download is not version \(release.version).")
        }
        do { try Worktree.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], in: folder.path) }
        catch { throw UpdateError.message("The new app's signature does not verify.") }
        return app
    }

    /// Quits; a detached script waits for this process to end, moves the old bundle aside, moves the new one in
    /// (putting the old one back if that fails), deletes the old copy, and opens the app.
    /// Arguments: the pid to wait for, the installed bundle, the new bundle, and "open" to launch it after.
    static let swapScript = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/mv "$2" "$2.old" || exit 1
        if /bin/mv "$3" "$2"; then /bin/rm -r "$2.old"; else /bin/mv "$2.old" "$2"; exit 1; fi
        [ "$4" = open ] && /usr/bin/open "$2"
        exit 0
        """

    private func relaunch(replacing target: URL, with app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.swapScript, "updater", String(ProcessInfo.processInfo.processIdentifier), target.path, app.path, "open"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }

    private func inform(_ message: String, detail: String = "") {
        guard !Store.isOverridden else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
