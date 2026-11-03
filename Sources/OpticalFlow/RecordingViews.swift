import AppKit
import AVKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct RecordingList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Recording.startedAt, order: .reverse) private var recordings: [Recording]

    var body: some View {
        @Bindable var model = model
        List(recordings, selection: $model.selection) { recording in
            HStack(spacing: Space.md) {
                RecordingThumbnail(url: recording.fileExists ? recording.url : nil)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(recording.title)
                        .lineLimit(2)
                    HStack(spacing: Space.xs) {
                        if recording == model.recorder.recording {
                            Image(systemName: "record.circle").foregroundStyle(.red)
                        }
                        Text(Countdown.clock(Int(recording.duration), padded: false))
                            .monospacedDigit()
                        Text("·")
                        Text(recording.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.xs)
                Button("Open", systemImage: "play.rectangle") { recording.open() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!recording.fileExists)
                    .help("Open in QuickTime Player")
            }
            .tag(recording.id)
            .contextMenu {
                Button("Open") { recording.open() }.disabled(!recording.fileExists)
                Button("Show in Finder") { recording.showInFinder() }.disabled(!recording.fileExists)
            }
        }
        .overlay {
            if recordings.isEmpty {
                ContentUnavailableView("No Recordings", systemImage: "record.circle",
                                       description: Text("Start a session and click Record."))
            }
        }
        .navigationTitle("Recordings")
    }
}

struct RecordingDetail: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var exporting = false
    @State private var withCamera = true
    @State private var followCursor = false
    @State private var youtube = true
    @State private var removeSilence = false
    /// Audio levels of the whole file, read once the toggle is on. Empty: the file has no audio.
    @State private var levels: [Float]?
    @State private var player: AVPlayer?
    @State private var exportError: String?

    var body: some View {
        Form {
            LabeledContent("Task", value: recording.title)
            LabeledContent("Recorded", value: recording.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
            LabeledContent("Length", value: Countdown.clock(Int(recording.duration), padded: false))
            LabeledContent("File", value: recording.url.lastPathComponent)
            if let cameraURL = recording.cameraURL {
                LabeledContent("Camera", value: cameraURL.lastPathComponent)
            }
            Section("Chapters") {
                Text(recording.chapterText)
                    .monospacedDigit()
                    .textSelection(.enabled)
                ForEach(ChapterList.issues(opening: recording.title, marks: recording.chapters, duration: recording.duration), id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Button("Copy Chapters", systemImage: "doc.on.doc") { recording.copyChapters() }
                    .help("Copy the chapter list for a YouTube description. Complete tasks or press Control-Option-Command-M while recording to add chapters.")
            }
            Section("Preview") {
                if let player {
                    PlayerView(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Button("Set Start Here", systemImage: "arrow.right.to.line") { start = player.currentTime().seconds; if end <= start { end = recording.duration } }
                        Button("Set End Here", systemImage: "arrow.left.to.line") { end = player.currentTime().seconds }
                        Spacer()
                        Button("Play from Start", systemImage: "play") {
                            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                            player.play()
                        }
                    }
                } else {
                    Text("The file is missing.").foregroundStyle(.secondary)
                }
            }
            Section("Trim") {
                LabeledContent("Start") {
                    Slider(value: $start, in: 0...max(1, recording.duration))
                    Text(Countdown.clock(Int(start), padded: false)).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                LabeledContent("End") {
                    Slider(value: $end, in: 0...max(1, recording.duration))
                    Text(Countdown.clock(Int(end), padded: false)).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                if recording.cameraURL != nil {
                    Toggle("Include the camera in the corner", isOn: $withCamera)
                        .disabled(!recording.hasCamera)
                }
                if recording.cursorURL != nil {
                    Toggle("Follow the cursor (2x zoom)", isOn: $followCursor)
                        .help("Crops to half the frame around the pointer and glides with it")
                }
                Toggle("YouTube preset (1080p H.264, AAC)", isOn: $youtube)
                    .help("Re-encodes to what YouTube recommends. Off keeps the original codec where possible.")
                Toggle(isOn: $removeSilence) {
                    Text("Remove silence")
                    if !silenceSummary.isEmpty { Text(silenceSummary) }
                }
                .disabled(levels?.isEmpty == true)
                .help("Cuts every pause of a second or more, keeping a moment on each side; chapters move with the cuts")
                .onChange(of: removeSilence) { if removeSilence, levels == nil { readLevels() } }
                HStack {
                    Button("Export Trimmed", systemImage: "scissors") { export() }
                        .disabled(exporting || !recording.fileExists || end - start < 1)
                        .help("Write a new file with only the part between Start and End")
                    if exporting { ProgressView().controlSize(.small) }
                    if let exportError { Text(exportError).foregroundStyle(.secondary) }
                }
            }
            Section {
                HStack {
                    Button("Open", systemImage: "play.rectangle") { recording.open() }
                        .help("Open in QuickTime Player")
                    Button("Show in Finder", systemImage: "folder") { recording.showInFinder() }
                }
                .disabled(!recording.fileExists)
            }
        }
        .formStyle(.grouped)
        .onChange(of: recording.uuid, initial: true) {
            start = 0
            end = recording.duration
            exportError = nil
            levels = nil
            removeSilence = false
            player?.pause()
            player = recording.fileExists ? AVPlayer(url: recording.url) : nil
        }
        .onDisappear { player?.pause() }
    }

    /// "3 pauses cut, 0:42 shorter", or why there is nothing to cut.
    private var silenceSummary: String {
        guard removeSilence else { return "" }
        guard let levels else { return "Listening…" }
        guard !levels.isEmpty else { return "No audio in this recording" }
        let keep = SilenceCut.keep(levels: levels, step: SilenceCut.step, start: start, end: end)
        let cuts = max(0, keep.count - 1) + (keep.first?.lowerBound ?? start > start ? 1 : 0) + (keep.last?.upperBound ?? end < end ? 1 : 0)
        guard cuts > 0 else { return "No pauses over a second" }
        return "\(cuts) \(cuts == 1 ? "pause" : "pauses") cut, \(Countdown.clock(Int((end - start - SilenceCut.length(keep)).rounded()), padded: false)) shorter"
    }

    private func readLevels() {
        let url = recording.url
        Task {
            let read = (try? await Exporter.levels(of: url)) ?? nil
            levels = read ?? []
            if read == nil { removeSilence = false }
        }
    }

    private func export() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let new = try await model.trim(recording, start: start, end: end, withCamera: withCamera, followCursor: followCursor, youtube: youtube,
                                               removeSilence: removeSilence && levels?.isEmpty == false)
                model.selection = new.id
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

/// A small still from the recording, loaded once and kept for the session.
struct RecordingThumbnail: View {
    let url: URL?
    @State private var image: NSImage?
    static let size = CGSize(width: 64, height: 36)
    nonisolated(unsafe) private static var cache: [URL: NSImage] = [:]   // ponytail: unbounded in-memory cache; one entry per recording row

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Space.xs).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Space.xs))
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = Self.cache[url] { image = cached; return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: Self.size.width * 2, height: Self.size.height * 2)
            if let cg = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image {
                let made = NSImage(cgImage: cg, size: Self.size)
                Self.cache[url] = made
                image = made
            }
        }
    }
}

/// AVKit's AppKit player, wrapped by hand. SwiftUI's VideoPlayer (_AVKit_SwiftUI) aborts in
/// getSuperclassMetadata when loaded from a Swift package build; AVPlayerView does not.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
