import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MandalaCore

@MainActor
final class Workspace: ObservableObject {
    enum SaveState: String { case clean, saving, failed, conflict }

    enum SaveLocation {
        case iCloud
        case device
    }

    enum StorageError: Error { case iCloudUnavailable }

    struct Draft: Identifiable {
        let id = UUID()
        var cellID: String?
        var parent: String?
        var slot: Slot?
        var cell: Cell
        var assets: [String: Data] = [:]
        var isNew: Bool { cellID == nil }
    }

    struct ImportPreview: Identifiable {
        let id = UUID()
        let project: Project
        let notices: [LegacyNotice]
        let isSharing: Bool
    }

    struct ShareItem: Identifiable {
        var id: URL { url }
        let url: URL
    }

    struct ReminderDestination: Equatable {
        let cellID: String
        let actionID: String?
    }

    private struct ReminderRoute {
        let projectID: String
        let cellID: String
        let actionID: String

        init?(_ url: URL) {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard url.host?.lowercased() == "project", parts.count == 4, parts[1] == "cell",
                  ShortID.isValid(parts[0]), ShortID.isValid(parts[2]), ShortID.isValid(parts[3]) else { return nil }
            projectID = parts[0]
            cellID = parts[2]
            actionID = parts[3]
        }
    }

    @Published var reminderDestination: ReminderDestination?
    @Published private(set) var project: Project?
    @Published private(set) var projectURL: URL?
    @Published private(set) var projects: [URL] = []
    @Published var draft: Draft?
    @Published private(set) var path: [String] = []
    @Published var selectedID: String?
    @Published var pendingImport: ImportPreview?
    @Published var share: ShareItem?
    @Published var error: Error?
    @Published private(set) var saveState: SaveState = .clean
    @Published private(set) var isBusy = false {
        didSet {
            if !isBusy, pendingReminder != nil { Task { await openPendingReminder() } }
        }
    }
    @Published private(set) var waitingForSync = false
    @Published private(set) var cloudDirectory: URL?
    @Published private(set) var checkingCloud = true

    private var autosave: Task<Void, Never>?
    private var writeTask: Task<Bool, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var heldScope: URL?
    private var recoverable: Project?
    private var pendingReminder: ReminderRoute?
    private let defaults = UserDefaults.standard
    let cloudProjects = NSMetadataQuery()
    private var cloudLookup: Task<Void, Never>?

    var defaultSaveLocation: SaveLocation { cloudDirectory == nil ? .device : .iCloud }

    var currentID: String? { path.last }
    var currentCell: Cell? { currentID.flatMap { project?.cells[$0] } }

    func asset(at path: String?) -> Data? {
        guard let path, path.hasPrefix("assets/") else { return nil }
        return project?.assets[String(path.dropFirst("assets/".count))]
    }

    func legacyCover(for id: String) -> Data? {
        guard let project, project.manifest.rootCellID == id,
              !(project.cells[id]?.resources ?? []).contains(where: { $0.kind == .image }) else { return nil }
        return asset(at: project.manifest.legacyPreviewPath)
    }

    func refreshCloudLibrary() async {
        if let cloudLookup {
            await cloudLookup.value
            return
        }
        let lookup = Task {
            let directory = await Task.detached { ProjectDisk.cloudDirectory() }.value
            if directory != cloudDirectory {
                cloudProjects.stop()
                cloudDirectory = directory
                if directory != nil {
                    cloudProjects.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
                    cloudProjects.predicate = NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".mprj")
                    cloudProjects.start()
                }
            }
            checkingCloud = false
            refresh()
            cloudLookup = nil
        }
        cloudLookup = lookup
        await lookup.value
    }

    func refresh() {
        do {
            var urls = Dictionary(uniqueKeysWithValues: try ProjectDisk.localProjects().map {
                ($0.standardizedFileURL.path, $0)
            })
            if let directory = cloudDirectory {
                for url in (try? ProjectDisk.projects(in: directory)) ?? [] {
                    urls[url.standardizedFileURL.path] = url
                }
                cloudProjects.disableUpdates()
                defer { cloudProjects.enableUpdates() }
                for case let item as NSMetadataItem in cloudProjects.results {
                    guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                          url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else {
                        continue
                    }
                    urls[url.standardizedFileURL.path] = url
                }
            }
            for value in defaults.array(forKey: "externalProjects") as? [Data] ?? [] {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: value, options: .withoutUI,
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    urls[url.standardizedFileURL.path] = url
                }
            }
            var ranks: [String: Int] = [:]
            for (index, path) in recentProjects.enumerated() where ranks[path] == nil {
                ranks[path] = index
            }
            projects = urls.values.sorted { left, right in
                let leftRank = ranks[left.standardizedFileURL.path] ?? Int.max
                let rightRank = ranks[right.standardizedFileURL.path] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
            }
        } catch { self.error = error }
    }

    private func saveDirectory(for location: SaveLocation) throws -> URL? {
        guard location == .iCloud else { return nil }
        guard let cloudDirectory else { throw StorageError.iCloudUnavailable }
        return cloudDirectory
    }

    private var recentProjects: [String] {
        get { defaults.stringArray(forKey: "recentProjects") ?? [] }
        set { defaults.set(newValue, forKey: "recentProjects") }
    }

    func deleteProject(at url: URL) async {
        guard !isBusy, projectURL == nil, projects.contains(url) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let deletedURL = url.standardizedFileURL
            var bookmarks = defaults.array(forKey: "externalProjects") as? [Data] ?? []
            bookmarks.removeAll { bookmark in
                var stale = false
                let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                                        relativeTo: nil, bookmarkDataIsStale: &stale)
                return resolved?.standardizedFileURL == deletedURL
            }
            try await Task.detached { try ProjectDisk.trash(url) }.value
            recentProjects.removeAll { $0 == deletedURL.path }
            defaults.set(bookmarks, forKey: "externalProjects")
            refresh()
        } catch { self.error = error }
    }

    func create(title: String, center: String, template: ProjectTemplate?, location: SaveLocation) async {
        guard !isBusy, await flush() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let new = try Project(title: title, center: center, template: template)
            let directory = try saveDirectory(for: location)
            let url = try await Task.detached { try ProjectDisk.create(new, in: directory) }.value
            setProject(new, at: url)
            refresh()
        } catch { self.error = error }
    }

    func open(_ url: URL) async {
        guard !isBusy, await flush() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if url.pathExtension.lowercased() == "mprj" {
                try await openPackage(url)
            } else {
                let ext = url.pathExtension.lowercased()
                let preview = try await Task.detached {
                    let data = try ProjectDisk.fileData(url)
                    if ext == "mandala" {
                        let imported = try LegacyMandala.read(data, filename: url.lastPathComponent)
                        return ImportPreview(project: imported.project, notices: imported.notices, isSharing: false)
                    }
                    guard ext == "mandalaprj" || ext == "zip" else {
                        throw ProjectError.invalidDocument(url.lastPathComponent)
                    }
                    return ImportPreview(project: try ProjectPackage.readSharingData(data), notices: [], isSharing: true)
                }.value
                pendingImport = preview
            }
        } catch { self.error = error }
    }

    func acceptImport(_ preview: ImportPreview, asBackup: Bool, location: SaveLocation) async {
        guard !isBusy, await flush() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var value = preview.project
            if preview.isSharing && !asBackup { try value.makeIndependentCopy() }
            let directory = try saveDirectory(for: location)
            let imported = value
            let existing = projects
            let url = try await Task.detached {
                if asBackup, existing.contains(where: { (try? ProjectDisk.read($0).manifest.projectID) == imported.manifest.projectID }) {
                    throw ProjectError.conflict
                }
                return try ProjectDisk.create(imported, in: directory)
            }.value
            pendingImport = nil
            setProject(value, at: url)
            refresh()
        } catch { self.error = error }
    }

    func close() async {
        guard !isBusy, await finishEditor() else { return }
        if let heldScope { heldScope.stopAccessingSecurityScopedResource() }
        heldScope = nil
        project = nil
        projectURL = nil
        path = []
        selectedID = nil
        reminderDestination = nil
        refresh()
    }

    @discardableResult
    func navigate(to id: String) async -> Bool {
        guard await finishEditor(), let route = project?.path(to: id) else { return false }
        path = route
        selectedID = id
        if let documentID = project?.manifest.projectID {
            defaults.set(id, forKey: "lastCell." + documentID)
        }
        return true
    }

    func select(_ id: String) async {
        guard await finishEditor() else { return }
        selectedID = id
    }

    func beginEdit(id: String) async -> Bool {
        guard await finishEditor(), let cell = project?.cells[id] else { return false }
        selectedID = id
        draft = Draft(cellID: id, cell: cell)
        return true
    }

    func beginEmpty(slot: Slot, in parentID: String? = nil) async {
        guard await finishEditor(), let parent = parentID ?? currentID,
              let cell = project?.cells[parent], cell.child(at: slot) == nil else { return }
        selectedID = nil
        draft = Draft(parent: parent, slot: slot, cell: Cell())
    }

    func changeDraft(_ update: (inout Draft) -> Void) {
        guard var value = draft else { return }
        update(&value)
        draft = value
        autosave?.cancel()
        autosave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            self?.startAutosave()
        }
    }

    private func startAutosave() {
        Task { await flush() }
    }

    func setBackground(_ background: Bool) {
        if background {
            guard backgroundTask == .invalid else { return }
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
            Task {
                _ = await flush()
                endBackgroundTask()
            }
        } else {
            Task { await refreshCurrentIfClean() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func refreshCurrentIfClean() async {
        guard let old = project, let url = projectURL, draft == nil, writeTask == nil else { return }
        guard let current = try? await Task.detached(operation: { try ProjectDisk.read(url) }).value,
              projectURL == url, draft == nil, writeTask == nil, project?.manifest.revision == old.manifest.revision,
              old.manifest.revision != current.manifest.revision else { return }
        project = current
        let target = current.path(to: path.last ?? "") ?? [current.manifest.rootCellID]
        path = target
        if current.cells[selectedID ?? ""] == nil { selectedID = target.last }
    }

    @discardableResult
    func finishEditor() async -> Bool {
        guard await flush() else { return false }
        draft = nil
        return true
    }

    @discardableResult
    func flush() async -> Bool {
        autosave?.cancel()
        autosave = nil
        while let task = writeTask {
            if !(await task.value) { return false }
            if Task.isCancelled { return false }
        }
        while let snapshot = draft, let original = project {
            if let id = snapshot.cellID, original.cells[id] == snapshot.cell && snapshot.assets.isEmpty { return true }
            if snapshot.cellID == nil && !snapshot.cell.containsContent { return true }
            var candidate = original
            do {
                let id: String
                var previousPaths = Set<String>()
                if let saved = snapshot.cellID, let current = candidate.cells[saved] {
                    previousPaths = Set((current.resources ?? []).compactMap(\.path))
                    var edited = snapshot.cell
                    edited.children = current.children
                    edited.legacyChildren = current.legacyChildren
                    candidate.cells[saved] = edited
                    id = saved
                } else if let parent = snapshot.parent, let slot = snapshot.slot {
                    id = try candidate.createChild(in: parent, at: slot, content: snapshot.cell)
                } else { throw ProjectError.conflict }
                let currentPaths = Set((snapshot.cell.resources ?? []).compactMap(\.path))
                for (filename, bytes) in snapshot.assets where currentPaths.contains("assets/" + filename) {
                    guard original.assets[filename] == nil else { throw ProjectError.conflict }
                    candidate.assets[filename] = bytes
                }
                let removedPaths = previousPaths.subtracting(currentPaths)
                if !removedPaths.isEmpty {
                    var inUse = Set(candidate.cells.values.flatMap { ($0.resources ?? []).compactMap(\.path) })
                    if let cover = candidate.manifest.legacyPreviewPath { inUse.insert(cover) }
                    for path in removedPaths.subtracting(inUse) {
                        candidate.assets.removeValue(forKey: String(path.dropFirst("assets/".count)))
                    }
                }

                let saved = await commit(candidate) {
                    guard self.draft?.id == snapshot.id else { return }
                    self.draft?.cellID = id
                    for key in snapshot.assets.keys { self.draft?.assets.removeValue(forKey: key) }
                    self.selectedID = id
                }
                guard saved else { return false }
            } catch {
                self.error = error
                saveState = .failed
                return false
            }
        }
        return true
    }

    func addFile(_ url: URL) async {
        guard let draftID = draft?.id else { return }
        do {
            let bytes = try await Task.detached { try ProjectDisk.fileData(url) }.value
            try addAttachment(bytes, named: url.lastPathComponent, to: draftID)
        } catch { self.error = error }
    }

    func addAttachment(_ bytes: Data, named name: String, type: UTType? = nil, to draftID: UUID) throws {
        guard let draft, draft.id == draftID else { return }
        let assets = project?.assets ?? [:]
        let stagedBytes = draft.assets.values.reduce(0) { $0 + $1.count }
        let savedBytes = assets.values.reduce(0) { $0 + $1.count }
        guard !bytes.isEmpty else { throw ProjectError.invalidResource(name) }
        guard bytes.count <= ProjectPackage.maximumBytes - stagedBytes - savedBytes else { throw ProjectError.tooLarge }

        let originalExtension = (name as NSString).pathExtension.lowercased()
        let suggestedExtension = type?.preferredFilenameExtension ?? originalExtension
        let ext = suggestedExtension.range(of: #"^[a-z0-9]{1,16}$"#, options: .regularExpression) == nil ? "dat" : suggestedExtension
        let assetIDs = Set((Array(assets.keys) + Array(draft.assets.keys)).map { String($0.split(separator: ".")[0]) })
        let filename = try ShortID.generate(excluding: assetIDs) + "." + ext
        let contentType = type ?? UTType(filenameExtension: ext)
        let kind: CellResource.Kind
        if contentType?.conforms(to: .image) == true { kind = .image }
        else if contentType?.conforms(to: .movie) == true { kind = .video }
        else if contentType?.conforms(to: .audio) == true { kind = .audio }
        else { kind = .file }
        changeDraft {
            $0.assets[filename] = bytes
            $0.cell.resources = ($0.cell.resources ?? []) +
                [.init(kind: kind, path: "assets/" + filename, originalFilename: name)]
        }
    }

    func move(_ id: String, to parent: String, slot: Slot) async {
        guard await finishEditor(), var candidate = project else { return }
        do {
            try candidate.move(id, to: parent, at: slot)
            _ = await commit(candidate)
        } catch { self.error = error }
    }

    func export(legacy: Bool, backup: Bool = false, includeLinks: Bool = false) async {
        guard !isBusy, await flush(), let value = project else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await Task.detached {
                let data = try legacy ? LegacyMandala.write(value, includeLinks: includeLinks)
                    : ProjectPackage.sharingData(for: value, backup: backup)
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(ProjectPackage.safeFilename(value.manifest.title))
                    .appendingPathExtension(legacy ? "mandala" : "mandalaprj")
                try data.write(to: file, options: .atomic)
                return file
            }.value
            share = ShareItem(url: url)
        } catch { self.error = error }
    }

    @discardableResult
    func setReminderLink(_ link: ReminderLink, for actionID: String) async -> Bool {
        guard await flush(), var candidate = project else { return false }
        candidate.reminderLinks[actionID] = link
        return await commit(candidate)
    }

    @discardableResult
    private func commit(_ value: Project, completion: @escaping @MainActor () -> Void = {}) async -> Bool {
        guard writeTask == nil, let original = project, let url = projectURL else { return false }
        var candidate = value
        do { try candidate.advanceRevision() } catch { self.error = error; return false }
        let next = candidate
        let revision = original.manifest.revision
        saveState = .saving
        let task = Task { @MainActor in
            defer { self.writeTask = nil }
            do {
                try await Task.detached {
                    try ProjectDisk.writeRecovery(next, baseRevision: revision)
                    try ProjectDisk.write(next, at: url, replacing: revision)
                    ProjectDisk.clearRecovery(next.manifest.projectID)
                }.value
                self.project = next
                self.recoverable = nil
                completion()
                self.saveState = .clean
                self.updateSyncState()
                return true
            } catch {
                self.recoverable = next
                self.saveState = (error as? ProjectError) == .conflict ? .conflict : .failed
                self.error = error
                return false
            }
        }
        writeTask = task
        return await task.value
    }

    func recoverAsCopy() async {
        guard writeTask == nil, let candidate = recoverable, let original = project else { return }
        do {
            var copy = candidate
            try copy.makeIndependentCopy()
            let value = copy
            let url = try await Task.detached { try ProjectDisk.create(value) }.value
            ProjectDisk.clearRecovery(original.manifest.projectID)
            recoverable = nil
            draft = nil
            setProject(copy, at: url)
            refresh()
        } catch { self.error = error }
    }

    private func resumeRecovery() async throws {
        guard let original = project, let url = projectURL,
              let pending = try await Task.detached(operation: {
                  try ProjectDisk.readRecovery(original.manifest.projectID)
              }).value else { return }
        if original.manifest.revision == pending.candidate.manifest.revision {
            ProjectDisk.clearRecovery(original.manifest.projectID)
        } else if original.manifest.revision == pending.base {
            try await Task.detached {
                try ProjectDisk.write(pending.candidate, at: url, replacing: pending.base)
                ProjectDisk.clearRecovery(original.manifest.projectID)
            }.value
            project = pending.candidate
        } else {
            recoverable = pending.candidate
            saveState = .conflict
            error = ProjectError.conflict
        }
    }

    private func setProject(_ value: Project, at url: URL) {
        if let heldScope { heldScope.stopAccessingSecurityScopedResource() }
        heldScope = url.startAccessingSecurityScopedResource() ? url : nil
        projectURL = url
        let openedPath = url.standardizedFileURL.path
        recentProjects = [openedPath] + recentProjects.filter { $0 != openedPath }
        reminderDestination = nil
        project = value
        draft = nil
        let last = defaults.string(forKey: "lastCell." + value.manifest.projectID)
        path = last.flatMap { value.path(to: $0) } ?? [value.manifest.rootCellID]
        selectedID = path.last
        saveState = .clean
        updateSyncState()
    }

    func updateSyncState() {
        guard let url = projectURL,
              let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey]) else {
            waitingForSync = false
            return
        }
        waitingForSync = values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == false
        if !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty { saveState = .conflict }
    }

    private func remember(_ url: URL) {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        guard parent != (try? ProjectDisk.library().standardizedFileURL.path),
              parent != cloudDirectory?.standardizedFileURL.path else { return }
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return }
        var entries = defaults.array(forKey: "externalProjects") as? [Data] ?? []
        if !entries.contains(bookmark) { entries.append(bookmark) }
        defaults.set(entries, forKey: "externalProjects")
    }

    func openReminderURL(_ url: URL) async {
        guard let route = ReminderRoute(url) else {
            error = ProjectError.invalidDocument("reminder")
            return
        }
        pendingReminder = route
        await openPendingReminder()
    }

    private func openPendingReminder() async {
        guard !isBusy, let route = pendingReminder else { return }
        pendingReminder = nil
        isBusy = true
        defer { isBusy = false }
        guard await finishEditor() else { return }
        do {
            if project?.manifest.projectID != route.projectID {
                await refreshCloudLibrary()
                let available = projects
                let match = await Task.detached {
                    available.first { (try? ProjectDisk.projectID(at: $0)) == route.projectID }
                }.value
                guard let match else { throw ProjectError.invalidDocument(route.projectID) }
                try await openPackage(match)
            }
            guard let project, project.manifest.projectID == route.projectID,
                  let cell = project.cells[route.cellID], await navigate(to: route.cellID) else {
                throw ProjectError.invalidDocument(route.cellID)
            }
            let actionID = cell.actions?.contains(where: { $0.id == route.actionID }) == true ? route.actionID : nil
            reminderDestination = ReminderDestination(cellID: route.cellID, actionID: actionID)
        } catch { self.error = error }
    }

    private func openPackage(_ url: URL) async throws {
        let value = try await Task.detached { try ProjectDisk.read(url) }.value
        setProject(value, at: url)
        remember(url)
        try await resumeRecovery()
    }
}
