import Foundation
import ZIPFoundation

public enum ProjectPackage {
    public static let maximumBytes = 256 * 1024 * 1024
    static let maximumEntries = 30_000

    public static func makeWrapper(for project: Project, includeReminderLinks: Bool = true) throws -> FileWrapper {
        try project.validate()
        let manifest = try YAMLDocument.encode(project.manifest)
        let cells = try project.cells.reduce(into: [String: FileWrapper]()) { files, item in
            files[item.key + ".yaml"] = FileWrapper(regularFileWithContents: try YAMLDocument.encode(item.value))
        }
        var contents = [
            "project.yaml": FileWrapper(regularFileWithContents: manifest),
            "cells": FileWrapper(directoryWithFileWrappers: cells)
        ]
        if !project.assets.isEmpty {
            contents["assets"] = FileWrapper(directoryWithFileWrappers:
                project.assets.mapValues { FileWrapper(regularFileWithContents: $0) })
        }
        if includeReminderLinks, !project.reminderLinks.isEmpty {
            let records = try project.reminderLinks.reduce(into: [String: FileWrapper]()) { files, item in
                files[item.key + ".yaml"] = FileWrapper(regularFileWithContents: try YAMLDocument.encode(item.value))
            }
            contents["reminder-links"] = FileWrapper(directoryWithFileWrappers: records)
        }
        var total = 0
        try forEachFile(in: FileWrapper(directoryWithFileWrappers: contents)) { _, data in
            total += data.count
            guard total <= maximumBytes else { throw ProjectError.tooLarge }
        }
        return FileWrapper(directoryWithFileWrappers: contents)
    }

    public static func readDirectory(_ url: URL) throws -> Project {
        var bytes = 0
        var entries = 0
        func wrapper(at location: URL, depth: Int) throws -> FileWrapper {
            entries += 1
            guard depth <= 2, entries <= maximumEntries else { throw ProjectError.tooLarge }
            let values = try location.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw ProjectError.invalidDocument(location.lastPathComponent) }
            if values.isDirectory == true {
                let children = try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: nil)
                return try FileWrapper(directoryWithFileWrappers: children.reduce(into: [:]) { result, child in
                    if child.lastPathComponent != ".DS_Store" {
                        result[child.lastPathComponent] = try wrapper(at: child, depth: depth + 1)
                    }
                })
            }
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= maximumBytes - bytes else { throw ProjectError.tooLarge }
            let data = try Data(contentsOf: location)
            bytes += data.count
            guard bytes <= maximumBytes else { throw ProjectError.tooLarge }
            return FileWrapper(regularFileWithContents: data)
        }
        return try read(wrapper(at: url, depth: 0))
    }

    public static func readManifest(_ data: Data) throws -> ProjectManifest {
        try YAMLDocument.decode(ProjectManifest.self, from: data, filename: "project.yaml")
    }

    public static func read(_ wrapper: FileWrapper) throws -> Project {
        guard let entries = wrapper.fileWrappers,
              Set(entries.keys).isSubset(of: ["project.yaml", "cells", "assets", "reminder-links"]),
              let manifestFile = entries["project.yaml"]?.regularFileContents,
              let cellFiles = entries["cells"]?.fileWrappers, !cellFiles.isEmpty else {
            throw ProjectError.invalidDocument("project.yaml")
        }
        var manifest = try readManifest(manifestFile)
        guard [1, ProjectManifest.currentSchemaVersion].contains(manifest.schemaVersion) else {
            throw ProjectError.unsupportedVersion(manifest.schemaVersion)
        }
        let migrateEarlyBuild = manifest.schemaVersion == 1
        manifest.schemaVersion = ProjectManifest.currentSchemaVersion

        var total = manifestFile.count
        var fileCount = 1
        func contents(_ file: FileWrapper, named name: String) throws -> Data {
            guard let data = file.regularFileContents else { throw ProjectError.invalidDocument(name) }
            total += data.count
            fileCount += 1
            guard total <= maximumBytes, fileCount <= maximumEntries else { throw ProjectError.tooLarge }
            return data
        }
        func readRecords<T: Decodable>(_ files: [String: FileWrapper], as type: T.Type,
                                         in folder: String, migrateEarlyBuildCell: Bool = false) throws -> [String: T] {
            try files.reduce(into: [:]) { result, item in
                let name = item.key
                let id = String(name.dropLast(".yaml".count))
                guard name.hasSuffix(".yaml"), ShortID.isValid(id) else { throw ProjectError.invalidDocument(name) }
                result[id] = try YAMLDocument.decode(type, from: contents(item.value, named: name),
                                                      filename: folder + "/" + name,
                                                      migrateEarlyBuildCell: migrateEarlyBuildCell)
            }
        }
        func optionalDirectory(_ name: String) throws -> [String: FileWrapper] {
            guard let directory = entries[name] else { return [:] }
            guard let files = directory.fileWrappers else { throw ProjectError.invalidDocument(name) }
            return files
        }

        let cells = try readRecords(cellFiles, as: Cell.self, in: "cells", migrateEarlyBuildCell: migrateEarlyBuild)
        let assets = try optionalDirectory("assets").reduce(into: [String: Data]()) { result, item in
            guard Project.assetName(item.key) else { throw ProjectError.invalidResource(item.key) }
            result[item.key] = try contents(item.value, named: item.key)
        }
        let links = try readRecords(optionalDirectory("reminder-links"), as: ReminderLink.self, in: "reminder-links")
        let project = Project(manifest: manifest, cells: cells, assets: assets, reminderLinks: links)
        try project.validate()
        return project
    }

    public static func sharingData(for project: Project, backup: Bool = false) throws -> Data {
        let wrapper = try makeWrapper(for: project, includeReminderLinks: backup)
        let archive = try Archive(accessMode: .create)
        let name = safeFilename(project.manifest.title) + ".mprj"
        var directories = Set([name, name + "/cells"])
        var files: [String: Data] = [:]
        try forEachFile(in: wrapper) { path, data in
            let parts = path.split(separator: "/").dropLast()
            if !parts.isEmpty { directories.insert(name + "/" + parts.joined(separator: "/")) }
            files[name + "/" + path] = data
        }
        for directory in directories.sorted() { try add(directory + "/", data: nil, to: archive) }
        for (path, data) in files.sorted(by: { $0.key < $1.key }) { try add(path, data: data, to: archive) }
        guard let data = archive.data else { throw ProjectError.invalidDocument(name) }
        return data
    }

    public static func readSharingData(_ data: Data) throws -> Project {
        let archive = try checkedArchive(data)
        guard let root = archive.entries.first?.parts.first, root.hasSuffix(".mprj"),
              archive.entries.allSatisfy({ $0.parts.first == root }) else {
            throw ProjectError.invalidDocument("mandalaprj")
        }
        var top: [String: FileWrapper] = [:]
        var folders: [String: [String: FileWrapper]] = [:]
        for item in archive.entries {
            let parts = Array(item.parts.dropFirst())
            if item.entry.type == .directory {
                if parts.isEmpty { continue }
                guard parts.count == 1, ["cells", "assets", "reminder-links"].contains(parts[0]) else {
                    throw ProjectError.invalidDocument(item.entry.path)
                }
                if folders[parts[0]] == nil { folders[parts[0]] = [:] }
            } else if parts == ["project.yaml"] {
                top["project.yaml"] = FileWrapper(regularFileWithContents: try extract(item.entry, from: archive.archive))
            } else if parts.count == 2, ["cells", "assets", "reminder-links"].contains(parts[0]) {
                folders[parts[0], default: [:]][parts[1]] = FileWrapper(
                    regularFileWithContents: try extract(item.entry, from: archive.archive))
            } else {
                throw ProjectError.invalidDocument(item.entry.path)
            }
        }
        for (name, files) in folders { top[name] = FileWrapper(directoryWithFileWrappers: files) }
        return try read(FileWrapper(directoryWithFileWrappers: top))
    }

    public static func safeFilename(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters))
            .joined(separator: "-").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "mandala" : String(cleaned.prefix(64))
    }

    private static func forEachFile(in wrapper: FileWrapper, prefix: String = "",
                                    _ action: (String, Data) throws -> Void) throws {
        guard let files = wrapper.fileWrappers else { throw ProjectError.invalidDocument(prefix) }
        for (name, file) in files {
            let path = prefix + name
            if file.isDirectory { try forEachFile(in: file, prefix: path + "/", action) }
            else if let data = file.regularFileContents { try action(path, data) }
            else { throw ProjectError.invalidDocument(path) }
        }
    }

    struct CheckedArchive {
        struct Item { let entry: Entry; let parts: [String] }
        let archive: Archive
        let entries: [Item]
    }

    static func checkedArchive(_ data: Data) throws -> CheckedArchive {
        guard data.count <= maximumBytes else { throw ProjectError.tooLarge }
        let archive = try Archive(data: data, accessMode: .read)
        var total: UInt64 = 0
        var paths = Set<String>()
        var entries = [CheckedArchive.Item]()
        for entry in archive {
            let path = entry.path
            let parts = (path.hasSuffix("/") ? String(path.dropLast()) : path)
                .split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard entry.type != .symlink, !path.contains("\\"), !path.contains("\0"), !path.contains(":"),
                  !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  paths.insert(parts.joined(separator: "/").lowercased()).inserted else {
                throw ProjectError.invalidDocument(path)
            }
            guard entry.uncompressedSize <= UInt64(maximumBytes) - total,
                  entries.count < maximumEntries else { throw ProjectError.tooLarge }
            total += entry.uncompressedSize
            entries.append(.init(entry: entry, parts: parts))
        }
        guard UInt64(entries.count) == archive.totalNumberOfEntriesInCentralDirectory else { throw ProjectError.invalidDocument("ZIP") }
        return CheckedArchive(archive: archive, entries: entries)
    }

    static func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var contents = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard chunk.count <= Int(entry.uncompressedSize) - contents.count else { throw ProjectError.tooLarge }
            contents.append(chunk)
        }
        guard contents.count == entry.uncompressedSize, checksum == entry.checksum else {
            throw ProjectError.invalidDocument(entry.path)
        }
        return contents
    }

    static func add(_ path: String, data: Data?, to archive: Archive) throws {
        let contents = data ?? Data()
        try archive.addEntry(with: path, type: data == nil ? .directory : .file,
                             uncompressedSize: Int64(contents.count), compressionMethod: .deflate) {
            offset, length in
            contents.subdata(in: Int(offset)..<(Int(offset) + length))
        }
    }
}
