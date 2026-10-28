import AppKit
import SwiftData
import SwiftUI
import OpticalFlowKit

struct RecordingList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Recording.startedAt, order: .reverse) private var recordings: [Recording]

    var body: some View {
        @Bindable var model = model
        List(recordings, selection: $model.selection) { recording in
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(recording.title)
                    Text(recording.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if recording == model.recorder.recording {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                }
                Text(Countdown.clock(Int(recording.duration), padded: false))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
        }
    }

    private func export() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let new = try await model.trim(recording, start: start, end: end, withCamera: withCamera)
                model.selection = new.id
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
