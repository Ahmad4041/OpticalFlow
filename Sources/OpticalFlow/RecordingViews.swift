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
                Button("Copy Chapters", systemImage: "doc.on.doc") { recording.copyChapters() }
                    .help("Copy the chapter list for a YouTube description")
            }
            Section("Preview") {
                if let player {
                    VideoPlayer(player: player)
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
            player?.pause()
            player = recording.fileExists ? AVPlayer(url: recording.url) : nil
        }
        .onDisappear { player?.pause() }
    }

    private func export() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let new = try await model.trim(recording, start: start, end: end, withCamera: withCamera, followCursor: followCursor, youtube: youtube)
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
