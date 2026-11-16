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
                        if url.scheme == "mandala-think" { await workspace.openReminderURL(url) }
                        else { await workspace.open(url) }
                    }
                }
                .onChange(of: phase) { _, phase in
                    if phase == .background { workspace.setBackground(true) }
                    if phase == .active { workspace.setBackground(false); workspace.updateSyncState() }
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
                    Button { Task { await workspace.open(url) } } label: {
                        Label {
                            Text(verbatim: url.deletingPathExtension().lastPathComponent)
                        } icon: {
                            Image(systemName: "square.grid.3x3")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await workspace.deleteProject(at: url) }
                        } label: {
                            Label(words("delete"), systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("project-row")
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 8, for: .scrollContent)
            .refreshable { workspace.refresh() }
        }
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

struct NewProjectScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.words) private var words
    @State private var title = ""
    @State private var center = ""
    @State private var template: ProjectTemplate?
    @State private var destination: URL?
    @State private var folderPicker = false
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
                Button { folderPicker = true } label: {
                    LabeledContent(words("file.location"), value: destination?.lastPathComponent ?? words("file.local"))
                }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(words("project.new"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("project.create")) {
                        Task {
                            await workspace.create(title: title, center: center, template: template, directory: destination)
                            if let error = workspace.error {
                                errorMessage = words.error(error)
                                workspace.error = nil
                            } else if workspace.project != nil { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.isBusy)
                    .accessibilityIdentifier("create-project")
                }
            }
            .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { destination = url }
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
    @State private var folderPicker = false
    @State private var errorMessage: String?
    @State private var destination: URL?

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
                    Button { folderPicker = true } label: {
                        LabeledContent(words("file.location"), value: destination?.lastPathComponent ?? words("file.local"))
                    }
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
                            await workspace.acceptImport(preview, asBackup: restore, directory: destination)
                            if let error = workspace.error {
                                errorMessage = words.error(error)
                                workspace.error = nil
                            }
                        }
                    }.disabled(workspace.isBusy).accessibilityIdentifier("accept-import")
                }
            }
            .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { destination = url }
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
