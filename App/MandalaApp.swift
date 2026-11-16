import SwiftUI
import UniformTypeIdentifiers
import UIKit
import MandalaCore

@main
struct MandalaThinkApp: App {
    @AppStorage("mandala.language") private var language = AppLanguage.system.rawValue
    @StateObject private var workspace = Workspace()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            let preference = AppLanguage(rawValue: language) ?? .system
            let words = Words(language: preference)
            MainScreen(language: $language)
                .environmentObject(workspace)
                .environment(\.words, words)
                .environment(\.locale, words.locale)
                .tint(.mandalaInk)
                .onOpenURL { url in
                    Task {
                        if url.scheme?.lowercased() == "mandala-think" { await workspace.openReminderURL(url) }
                        else { await workspace.open(url) }
                    }
                }
                .onChange(of: phase, initial: true) { _, phase in
                    if phase == .background { workspace.setBackground(true) }
                    if phase == .active {
                        workspace.setBackground(false)
                        workspace.updateSyncState()
                        Task { await workspace.refreshCloudLibrary() }
                    }
                }
        }
    }
}

extension Color {
    static let mandalaInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.76, blue: 0.71, alpha: 1)
                                           : UIColor(red: 0.10, green: 0.31, blue: 0.29, alpha: 1)
    })

    static let mandalaPaper = Color(uiColor: .systemGroupedBackground)
    static let mandalaCard = Color(uiColor: .secondarySystemGroupedBackground)
}

extension UTType {
    static let mandalaPackage = UTType(exportedAs: "org.mandalathink.project", conformingTo: .package)
    static let mandalaShare = UTType(exportedAs: "org.mandalathink.share", conformingTo: .zip)
    static let mandalaLegacy = UTType(importedAs: "org.mandalathink.legacy", conformingTo: .zip)
}

struct MainScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Binding var language: String
    @State private var newProject = false
    @State private var filePicker = false
    @State private var revealedProject: URL?
    @State private var draggedRow: (url: URL, offset: CGFloat)?
    private static let deleteWidth: CGFloat = 72

    var body: some View {
        NavigationStack {
            Group {
                if workspace.project != nil { BoardScreen() }
                else { home }
            }
            .background(Color.mandalaPaper)
            .navigationTitle(workspace.project?.manifest.title ?? "MandalaThink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay {
                if workspace.isBusy {
                    ProgressView(words("working")).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("workspace-progress")
                }
            }
        }
        .task {
            workspace.refresh()
            #if DEBUG
            if let filename = UserDefaults.standard.string(forKey: "mandala.fixture"),
               (filename as NSString).lastPathComponent == filename,
               filename.hasSuffix(".mandala"),
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                await workspace.open(documents.appendingPathComponent(filename))
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSMetadataQueryDidFinishGathering,
                                                          object: workspace.cloudProjects)) { _ in workspace.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate,
                                                          object: workspace.cloudProjects)) { _ in workspace.refresh() }
        .fileImporter(isPresented: $filePicker,
                      allowedContentTypes: [.mandalaPackage, .mandalaShare, .mandalaLegacy, .zip]) { result in
            switch result {
            case .success(let url): Task { await workspace.open(url) }
            case .failure(let error): workspace.error = error
            }
        }
        .sheet(isPresented: $newProject) { NewProjectScreen() }
        .onChange(of: workspace.reminderDestination) { _, destination in
            if destination != nil { newProject = false }
        }
        .sheet(item: $workspace.pendingImport) { ImportScreen(preview: $0) }
        .sheet(item: $workspace.share) { item in ShareScreen(url: item.url) }
        .alert(words("error.title"), isPresented: Binding(get: { workspace.error != nil },
                                                          set: { if !$0 { workspace.error = nil } })) {
            Button(words("ok"), role: .cancel) { workspace.error = nil }
        } message: {
            if let error = workspace.error { Text(verbatim: words.error(error)) }
        }
    }

    private var home: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { homeButtons }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 12) { homeButtons }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            List {
                ForEach(workspace.projects, id: \.self) { url in
                    projectRow(url)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 8, for: .scrollContent)
            .refreshable { await workspace.refreshCloudLibrary() }
        }
    }

    private func projectRow(_ url: URL) -> some View {
        let revealed = revealedProject == url
        let offset = draggedRow?.url == url ? draggedRow?.offset ?? 0 : revealed ? Self.deleteWidth : 0
        return Button {
            revealedProject = nil
            Task { await workspace.open(url) }
        } label: {
            Label {
                Text(verbatim: url.deletingPathExtension().lastPathComponent)
            } icon: {
                Image(systemName: "square.grid.3x3")
            }
            .lineLimit(1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(Color.mandalaCard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project-row")
        .accessibilityAction(named: Text(words("delete"))) { deleteProject(url) }
        .offset(x: -offset)
        .background(alignment: .trailing) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
                .frame(width: Self.deleteWidth)
                .background(Color(uiColor: .systemRed))
                .accessibilityHidden(true)
                .overlay {
                    if revealed {
                        Button(role: .destructive) {
                            deleteProject(url)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(words("delete"))
                        .accessibilityIdentifier("delete-project")
                    }
                }
        }
        .clipped()
        .background(ProjectRowSwipe { event in
            let start = revealed ? Self.deleteWidth : 0
            switch event {
            case .dragged(let distance):
                if distance < 0, !revealed, revealedProject != nil {
                    withAnimation(.easeOut(duration: 0.2)) { revealedProject = nil }
                }
                draggedRow = (url, min(Self.deleteWidth, max(0, start - distance)))
            case .ended(let distance):
                withAnimation(.easeOut(duration: 0.22)) {
                    if start - distance >= Self.deleteWidth / 2 {
                        revealedProject = url
                    } else if revealed {
                        revealedProject = nil
                    }
                    draggedRow = nil
                }
            case .cancelled:
                withAnimation(.easeOut(duration: 0.22)) { draggedRow = nil }
            }
        })
    }

    private func deleteProject(_ url: URL) {
        revealedProject = nil
        Task { await workspace.deleteProject(at: url) }
    }

    @ViewBuilder
    private var homeButtons: some View {
        Button { newProject = true } label: {
            Label(words("home.new"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("new-project")
        Button { filePicker = true } label: {
            Label(words("home.open"), systemImage: "folder")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("open-project")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if workspace.project != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await workspace.close() } } label: {
                    Label(words("library.projects"), systemImage: "books.vertical")
                }
                .accessibilityIdentifier("close-project")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(words("language"), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { choice in
                        Text(choice == .system ? words(choice.name) : choice.name).tag(choice.rawValue)
                    }
                }
            } label: { Label(words("language"), systemImage: "globe") }
            .accessibilityIdentifier("language-menu")
        }
    }
}

private struct ProjectRowSwipe: UIViewRepresentable {
    enum Event {
        case dragged(CGFloat)
        case ended(CGFloat)
        case cancelled
    }

    let onSwipe: (Event) -> Void

    func makeUIView(context: Context) -> GestureRegion {
        let view = GestureRegion()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: GestureRegion, context: Context) { view.onSwipe = onSwipe }

    final class GestureRegion: UIView, UIGestureRecognizerDelegate {
        var onSwipe: ((Event) -> Void)?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            pan.view?.removeGestureRecognizer(pan)
            window?.addGestureRecognizer(pan)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard bounds.contains(touch.location(in: self)), let touchedView = touch.view else { return false }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    return touchedView.isDescendant(of: scroll)
                }
                ancestor = view.superview
            }
            return false
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }

        @objc private func swiped(_ recognizer: UIPanGestureRecognizer) {
            let distance = recognizer.translation(in: self).x
            switch recognizer.state {
            case .changed:
                onSwipe?(.dragged(distance))
            case .ended:
                let projectedDistance = distance + min(24, max(-24, recognizer.velocity(in: self).x * 0.08))
                onSwipe?(.ended(projectedDistance))
            case .cancelled:
                onSwipe?(.cancelled)
            default:
                break
            }
        }
    }
}

private struct ProjectSaveLocation: View {
    @Binding var selection: Workspace.SaveLocation?
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words

    var body: some View {
        let location = selection ?? workspace.defaultSaveLocation
        Menu {
            Button(words("file.iCloud")) { selection = .iCloud }
                .disabled(workspace.cloudDirectory == nil)
                .accessibilityIdentifier("save-to-icloud")
            Button(words("file.local")) { selection = .device }
                .accessibilityIdentifier("save-to-device")
        } label: {
            LabeledContent(words("file.location"),
                           value: words(workspace.checkingCloud && selection == nil ? "working"
                                        : location == .iCloud ? "file.iCloud" : "file.local"))
        }
        .accessibilityIdentifier("project-save-location")
        if !workspace.checkingCloud && workspace.cloudDirectory == nil {
            Text(words("file.iCloudUnavailable")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct NewProjectScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.words) private var words
    @State private var title = ""
    @State private var center = ""
    @State private var template: ProjectTemplate?
    @State private var saveLocation: Workspace.SaveLocation?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(words("project.title"), text: $title).accessibilityIdentifier("project-title")
                TextField(words("project.center"), text: $center).accessibilityIdentifier("project-center")
                Picker(words("template"), selection: $template) {
                    Text(words("template.blank")).tag(ProjectTemplate?.none)
                    Text(words("template.fiveW")).tag(ProjectTemplate?.some(.fiveW))
                    Text(words("template.time")).tag(ProjectTemplate?.some(.time))
                }
                ProjectSaveLocation(selection: $saveLocation)
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(words("project.new"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("project.create")) {
                        Task {
                            await workspace.create(title: title, center: center, template: template,
                                                   location: saveLocation ?? workspace.defaultSaveLocation)
                            if let error = workspace.error {
                                errorMessage = words.error(error)
                                workspace.error = nil
                            } else if workspace.project != nil { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.isBusy ||
                              (workspace.checkingCloud && saveLocation == nil))
                    .accessibilityIdentifier("create-project")
                }
            }
        }
    }
}

struct ImportScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.words) private var words
    let preview: Workspace.ImportPreview
    @State private var restore = false
    @State private var errorMessage: String?
    @State private var saveLocation: Workspace.SaveLocation?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: preview.project.manifest.title).font(.headline)
                    Text(words.count("grid.count", preview.project.cells.count)).foregroundStyle(.secondary)
                    if let path = preview.project.manifest.legacyPreviewPath,
                       let data = preview.project.assets[String(path.dropFirst(7))],
                       let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                            .accessibilityLabel(words("project.cover"))
                    }
                    if preview.isSharing { Toggle(words("file.restore"), isOn: $restore) }
                    ProjectSaveLocation(selection: $saveLocation)
                }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.red) }
                if !preview.notices.isEmpty {
                    Section(words("file.compatibility")) {
                        ForEach(Array(preview.notices.enumerated()), id: \.offset) { _, notice in
                            Text(verbatim: words.notice(notice, project: preview.project))
                        }
                    }
                }
            }
            .navigationTitle(words("project.import"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("project.import")) {
                        Task {
                            await workspace.acceptImport(preview, asBackup: restore,
                                                         location: saveLocation ?? workspace.defaultSaveLocation)
                            if let error = workspace.error {
                                errorMessage = words.error(error)
                                workspace.error = nil
                            }
                        }
                    }
                    .disabled(workspace.isBusy || (workspace.checkingCloud && saveLocation == nil))
                    .accessibilityIdentifier("accept-import")
                }
            }
        }
    }
}

struct ShareScreen: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
