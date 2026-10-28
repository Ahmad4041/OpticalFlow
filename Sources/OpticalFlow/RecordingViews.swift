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
    let recording: Recording

    var body: some View {
        Form {
            LabeledContent("Task", value: recording.title)
            LabeledContent("Recorded", value: recording.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
            LabeledContent("Length", value: Countdown.clock(Int(recording.duration), padded: false))
            LabeledContent("File", value: recording.url.lastPathComponent)
            Section("Chapters") {
                Text(recording.chapterText)
                    .monospacedDigit()
                    .textSelection(.enabled)
                Button("Copy Chapters", systemImage: "doc.on.doc") { recording.copyChapters() }
                    .help("Copy the chapter list for a YouTube description")
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
    }
}
