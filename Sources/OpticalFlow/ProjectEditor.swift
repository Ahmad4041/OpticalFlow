import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpticalFlowKit

/// What the project sheet edits. Copied from the project on open, written back on Save.
struct ProjectDraft: Equatable {
    var name = ""
    var color: ProjectColor = .blue
    var symbol = ProjectSymbol.default
    var imageData: Data?
}

/// SF Symbols offered for a project. Anything else from SF Symbols works too, through the CLI.
enum ProjectSymbol {
    static let `default` = "circle.fill"
    static let all = [
        "circle.fill", "star.fill", "folder.fill", "briefcase.fill", "hammer.fill", "wrench.and.screwdriver.fill", "terminal.fill",
        "chevron.left.forwardslash.chevron.right", "app.fill", "video.fill", "mic.fill", "camera.fill", "paintbrush.fill", "pencil",
        "book.fill", "graduationcap.fill", "lightbulb.fill", "globe", "house.fill", "cart.fill", "heart.fill",
        "leaf.fill", "flame.fill", "bolt.fill", "music.note", "gamecontroller.fill", "airplane", "dumbbell.fill",
    ]
}

/// A project's mark: its image when it has one, else its symbol in its color.
struct ProjectIcon: View {
    let symbol: String
    let color: Color
    let imageData: Data?
    var size: CGFloat = 16

    init(project: Project, size: CGFloat = 16) {
        self.init(symbol: project.symbol, color: project.color, imageData: project.imageData, size: size)
    }

    init(symbol: String, color: Color, imageData: Data?, size: CGFloat = 16) {
        self.symbol = symbol
        self.color = color
        self.imageData = imageData
        self.size = size
    }

    var body: some View {
        // ponytail: decodes the 128 px thumbnail on every render; cache by data hash if a profile shows it
        if let imageData, let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size / 4))
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

/// Name, color, icon or image, and repository, in one sheet. File > New Project and Edit Project open it.
struct ProjectEditor: View {
    @Environment(AppModel.self) private var model
    let prompt: ProjectPrompt
    @State private var draft = ProjectDraft()
    @State private var dropTargeted = false
    @FocusState private var nameFocused: Bool

    private var editing: Project? {
        if case .edit(let project) = prompt { return project }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: Space.md) {
                        ProjectIcon(symbol: draft.symbol, color: draft.color.color, imageData: draft.imageData, size: 40)
                        TextField("Name", text: $draft.name, prompt: Text("Project name"))
                            .labelsHidden()
                            .font(.title3)
                            .focused($nameFocused)
                            .onSubmit(save)
                    }
                }
                Section("Color") {
                    HStack(spacing: Space.sm) {
                        ForEach(ProjectColor.allCases) { color in
                            Button {
                                draft.color = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 20, height: 20)
                                    .padding(Space.xs / 2)
                                    .overlay(Circle().strokeBorder(draft.color == color ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(color.title)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(draft.color == color ? .isSelected : [])
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: Space.xs), count: 11), alignment: .leading, spacing: Space.xs) {
                        ForEach(ProjectSymbol.all, id: \.self) { symbol in
                            Button {
                                draft.symbol = symbol
                                draft.imageData = nil
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(selected(symbol) ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(draft.color.color))
                                    .background(selected(symbol) ? AnyShapeStyle(draft.color.color) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                                in: .rect(cornerRadius: Space.sm))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(selected(symbol) ? .isSelected : [])
                        }
                    }
                    .opacity(draft.imageData == nil ? 1 : 0.4)
                }
                Section {
                    HStack(spacing: Space.md) {
                        Group {
                            if draft.imageData != nil {
                                ProjectIcon(symbol: draft.symbol, color: draft.color.color, imageData: draft.imageData, size: 28)
                            } else {
                                Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 28, height: 28)
                            }
                        }
                        .background(dropTargeted ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: Space.sm))
                        Button("Choose Image…") { chooseImage() }
                        if draft.imageData != nil {
                            Button("Remove Image") { draft.imageData = nil }
                        }
                        Spacer()
                        Text("or drop a logo here").font(.callout).foregroundStyle(.secondary)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, let data = ProjectImage.thumbnail(of: url) else { return false }
                        draft.imageData = data
                        return true
                    } isTargeted: { dropTargeted = $0 }
                } header: {
                    Text("Image")
                }
                .help("A logo or picture replaces the icon. Drop a file here or choose one.")
                if let editing {
                    Section("Agent hand-off") {
                        LabeledContent("Repository") {
                            HStack(spacing: Space.sm) {
                                Text(editing.repoPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(editing.repoPath == nil ? "Choose…" : "Change…") { model.chooseRepository(for: editing) }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            Divider()
            HStack {
                if let editing {
                    Button("Delete Project…", role: .destructive) { model.projectPrompt = nil; model.deleteProject(editing) }
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.projectPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(TaskTitle.clean(draft.name) == nil)
            }
            .padding(Space.margin)
        }
        .frame(width: 440)
        .modifier(OpenFocus(focusName: editing == nil, focused: $nameFocused))
        .onAppear { draft = model.draft(for: prompt) }
    }

    private func selected(_ symbol: String) -> Bool { draft.imageData == nil && draft.symbol == symbol }

    private func save() {
        guard TaskTitle.clean(draft.name) != nil else { return }
        model.commitProjectPrompt(draft)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Image"
        panel.message = "A logo or picture for the project. It is copied into the app, so the file can move later."
        guard panel.runModal() == .OK, let url = panel.url, let data = ProjectImage.thumbnail(of: url) else { return }
        draft.imageData = data
    }
}

/// A new project focuses its name, since typing it is the first thing to do. Editing opens calm.
private struct OpenFocus: ViewModifier {
    let focusName: Bool
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if focusName {
            content.onAppear { focused.wrappedValue = true }
        } else {
            content.noInitialFocus()
        }
    }
}

/// Project pictures are stored as a small square PNG in the database, not as a path that can break.
enum ProjectImage {
    static let side: CGFloat = 128

    /// The image at `url` cropped to its centered square and scaled to 128 px, as PNG. Nil for a file that is not an image.
    static func thumbnail(of url: URL) -> Data? {
        guard let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let crop = min(cg.width, cg.height)
        guard crop > 0, let square = cg.cropping(to: CGRect(x: (cg.width - crop) / 2, y: (cg.height - crop) / 2, width: crop, height: crop)),
              let context = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}

/// The top of a project page, above the list or the board: icon, name, counts, repository, Edit.
struct ProjectHeader: View {
    @Environment(AppModel.self) private var model
    let project: Project
    /// In the narrow list column: the counts on one line and an icon-only Edit button.
    var compact = false

    private var doneThisWeek: Int {
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        return project.tasks.filter { $0.isDone && ($0.completedAt ?? .distantPast) > weekAgo }.count
    }

    var body: some View {
        HStack(spacing: Space.md) {
            ProjectIcon(project: project, size: 40)
                .padding(Space.sm)
                .background(project.color.opacity(project.imageData == nil ? 0.15 : 0), in: .rect(cornerRadius: Space.md))
                .gridProbe("project-icon", area: "project-header", edge: nil)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(project.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: Space.sm) {
                    Text(compact ? "\(project.openCount) open · \(doneThisWeek) done" : "\(project.openCount) open · \(doneThisWeek) done this week")
                    if let repo = project.repoPath {
                        Label((repo as NSString).lastPathComponent, systemImage: "arrow.triangle.branch")
                            .help("Hand-offs work in \(repo)")
                    }
                }
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit Project…", systemImage: "slider.horizontal.3") { model.projectPrompt = .edit(project) }
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .help("Name, color, icon or image, repository (Shift-Command-E)")
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.md)
        .gridArea("project-header", inset: Space.sm)
    }
}

/// Lets one button switch between icon-only and title-and-icon.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init(_ style: some LabelStyle) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
