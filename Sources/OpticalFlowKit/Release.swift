import Foundation

/// A dotted version like "0.2.0" or a tag like "v0.2.0". Missing parts count as 0, so "0.2" == "0.2.0".
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(_ count: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, count - parts.count)) }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n) == b.padded(n)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n).lexicographicallyPrecedes(b.padded(n))
    }
}

/// The parts of a GitHub release the updater needs: its version, notes, page, the app zip and its checksum file.
public struct Release: Equatable, Sendable {
    public var version: AppVersion
    public var notes: String
    public var page: URL?
    public var zip: URL
    public var checksum: URL

    public init(version: AppVersion, notes: String, page: URL?, zip: URL, checksum: URL) {
        self.version = version
        self.notes = notes
        self.page = page
        self.zip = zip
        self.checksum = checksum
    }

    /// Reads the JSON of `GET /repos/{owner}/{repo}/releases/latest`. Nil for a draft, a prerelease,
    /// or a release without `<name>.zip` and `<name>.zip.sha256` assets.
    public static func parse(github json: Data) -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Body: Decodable {
            let tag_name: String
            let body: String?
            let html_url: URL?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Body.self, from: json),
              release.draft != true, release.prerelease != true,
              let version = AppVersion(release.tag_name),
              let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let sum = release.assets.first(where: { $0.name == zip.name + ".sha256" })
        else { return nil }
        return Release(version: version, notes: summary(release.body ?? ""), page: release.html_url,
                       zip: zip.browser_download_url, checksum: sum.browser_download_url)
    }

    /// The notes up to the Install section, which says how to install by hand.
    static func summary(_ body: String) -> String {
        let cut = body.range(of: "\n## Install").map { String(body[..<$0.lowerBound]) } ?? body
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The hex digest in a `shasum -a 256` line ("<hex>  <name>"), lowercased; nil when there is none.
    public static func digest(inChecksumFile text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first, first.count == 64,
              first.allSatisfy(\.isHexDigit) else { return nil }
        return first.lowercased()
    }
}
