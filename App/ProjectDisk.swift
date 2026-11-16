import Foundation
import MandalaCore
import OSLog

enum ProjectDisk {
    private static let manager = FileManager.default
    private static let cloudContainer = "iCloud.org.mandalathink.app"
    private static let saveLogger = Logger(subsystem: "org.mandalathink.app", category: "Save")

    static func isOutOfSpace(_ error: Error) -> Bool {
        errorChain(error).contains { cause in
            (cause.domain == NSCocoaErrorDomain && cause.code == CocoaError.Code.fileWriteOutOfSpace.rawValue) ||
            (cause.domain == NSPOSIXErrorDomain && cause.code == Int(POSIXErrorCode.ENOSPC.rawValue))
        }
    }

    static func logSaveFailure(_ error: Error, stage: String) {
        let codes = errorChain(error).map { "\($0.domain)(\($0.code))" }.joined(separator: " → ")
        saveLogger.error("Save failed at \(stage, privacy: .public): \(codes, privacy: .public)")
    }

    private static func errorChain(_ error: Error) -> [NSError] {
        var pending = [error as NSError]
        var visited = Set<ObjectIdentifier>()
        var chain = [NSError]()
        while let cause = pending.popLast() {
            guard visited.insert(ObjectIdentifier(cause)).inserted else { continue }
            chain.append(cause)
            pending.append(contentsOf: cause.underlyingErrors.reversed().map { $0 as NSError })
        }
        return chain
    }

    static func library() throws -> URL {
        let url = try manager.url(for: .documentDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true).appendingPathComponent("Projects", isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func localProjects() throws -> [URL] {
        try projects(in: library())
    }

    static func cloudDirectory() -> URL? {
        manager.url(forUbiquityContainerIdentifier: cloudContainer)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    static func projects(in directory: URL) throws -> [URL] {
        try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                        options: .skipsHiddenFiles).filter { $0.pathExtension.lowercased() == "mprj" }
    }

    static func read(_ url: URL) throws -> Project {
        try coordinatedRead(url) { try ProjectPackage.readDirectory($0) }
    }

    static func projectID(at url: URL) throws -> String {
        try coordinatedRead(url) { location in
            let manifest = location.appendingPathComponent("project.yaml")
            let values = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= ProjectPackage.maximumBytes else {
                throw ProjectError.invalidDocument(manifest.lastPathComponent)
            }
            return try ProjectPackage.readManifest(Data(contentsOf: manifest)).projectID
        }
    }

    static func fileData(_ url: URL) throws -> Data {
        try coordinatedRead(url) {
            let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else {
                throw ProjectError.invalidResource($0.lastPathComponent)
            }
            guard size <= ProjectPackage.maximumBytes else { throw ProjectError.tooLarge }
            return try Data(contentsOf: $0)
        }
    }

    static func write(_ project: Project, at url: URL, replacing revision: String?) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { location in
            result = Result {
                if let revision {
                    if !NSFileVersion.unresolvedConflictVersionsOfItem(at: location).isNilOrEmpty {
                        throw ProjectError.conflict
                    }
                    let manifest = location.appendingPathComponent("project.yaml")
                    guard try ProjectPackage.readManifest(Data(contentsOf: manifest)).revision == revision else {
                        throw ProjectError.conflict
                    }
                } else if manager.fileExists(atPath: location.path) {
                    throw ProjectError.conflict
                }
                try ProjectPackage.makeWrapper(for: project).write(to: location, options: .atomic,
                                                                  originalContentsURL: revision == nil ? nil : location)
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            guard let result else { throw ProjectError.invalidDocument(url.lastPathComponent) }
            try result.get()
        } catch {
            logSaveFailure(error, stage: "project write")
            throw error
        }
    }

    static func create(_ project: Project, in directory: URL? = nil) throws -> URL {
        let folder = try directory ?? library()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = ProjectPackage.safeFilename(project.manifest.title)
        for counter in 1...10_000 {
            let basename = name + (counter == 1 ? "" : " " + String(counter)) + ".mprj"
            let url = folder.appendingPathComponent(basename, isDirectory: true)
            guard !manager.fileExists(atPath: url.path) else { continue }
            if directory == nil {
                try write(project, at: url, replacing: nil)
            } else {
                try publish(project, to: url)
            }
            return url
        }
        throw ProjectError.conflict
    }

    private static func publish(_ project: Project, to url: URL) throws {
        let staging = manager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let local = staging.appendingPathComponent(url.lastPathComponent, isDirectory: true)
        try write(project, at: local, replacing: nil)
        try manager.setUbiquitous(true, itemAt: local, destinationURL: url)
    }

    static func coordinatedRead<T>(_ url: URL, _ read: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "mprj",
           (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus == .notDownloaded {
            try manager.startDownloadingUbiquitousItem(at: url)
        }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try read(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectError.invalidDocument(url.lastPathComponent) }
        return try result.get()
    }

    static func trash(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "mprj" else {
            throw ProjectError.invalidDocument(url.lastPathComponent)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let projects = try library().resolvingSymlinksInPath()
        let local = url.deletingLastPathComponent().resolvingSymlinksInPath().path == projects.path
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: local ? .forMoving : .forDeleting,
                               error: &coordinationError) { location in
            result = Result {
                guard location.pathExtension.lowercased() == "mprj" else {
                    throw ProjectError.invalidDocument(location.lastPathComponent)
                }
                if local {
                    let deleted = projects.deletingLastPathComponent()
                        .appendingPathComponent("Recently Deleted", isDirectory: true)
                    try manager.createDirectory(at: deleted, withIntermediateDirectories: true)
                    var destination = deleted.appendingPathComponent(location.lastPathComponent, isDirectory: true)
                    if manager.fileExists(atPath: destination.path) {
                        let name = location.deletingPathExtension().lastPathComponent
                        destination = deleted.appendingPathComponent(name + " " + (try ShortID.generate()) + ".mprj",
                                                                     isDirectory: true)
                    }
                    coordinator.item(at: location, willMoveTo: destination)
                    try manager.moveItem(at: location, to: destination)
                    coordinator.item(at: location, didMoveTo: destination)
                } else {
                    try manager.trashItem(at: location, resultingItemURL: nil)
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectError.invalidDocument(url.lastPathComponent) }
        try result.get()
    }

    static func writeRecovery(_ candidate: Project, baseRevision: String) throws {
        do {
            let path = try recoveryURL(candidate.manifest.projectID)
            let package = try ProjectPackage.makeWrapper(for: candidate)
            let wrapper = FileWrapper(directoryWithFileWrappers: [
                "base": FileWrapper(regularFileWithContents: Data(baseRevision.utf8)),
                "project.mprj": package
            ])
            try wrapper.write(to: path, options: .atomic,
                              originalContentsURL: manager.fileExists(atPath: path.path) ? path : nil)
        } catch {
            logSaveFailure(error, stage: "recovery write")
            throw error
        }
    }

    static func readRecovery(_ id: String) throws -> (base: String, candidate: Project)? {
        let path = try recoveryURL(id)
        guard manager.fileExists(atPath: path.path) else { return nil }
        let raw = try Data(contentsOf: path.appendingPathComponent("base"))
        guard let base = String(data: raw, encoding: .utf8), ShortID.isValid(base) else {
            throw ProjectError.invalidDocument("Recovery")
        }
        let project = try ProjectPackage.readDirectory(path.appendingPathComponent("project.mprj"))
        guard project.manifest.projectID == id else { throw ProjectError.invalidDocument("Recovery") }
        return (base, project)
    }

    static func clearRecovery(_ id: String) {
        if let url = try? recoveryURL(id) { try? manager.removeItem(at: url) }
    }

    private static func recoveryURL(_ id: String) throws -> URL {
        guard ShortID.isValid(id) else { throw ProjectError.invalidDocument(id) }
        let base = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true).appendingPathComponent("Recovery", isDirectory: true)
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(id, isDirectory: true)
    }
}

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
