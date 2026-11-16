import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

public enum LegacyNotice: Hashable, Sendable {
    case unknownEntry(String)
    case actions(String)
    case color(String)
    case resources(String)
    case reminderRecords
}

public enum LegacyMandala {
    private static let previewInfo = "Representing/RepresentingInfo.plist"
    private static let previewDefault = "Representing/Representing.png"
    private static let backgroundExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let audioExtensions: Set<String> = ["mp3", "wav", "aac", "m4a"]

    public static func read(_ data: Data, filename: String) throws -> (project: Project, notices: [LegacyNotice]) {
        let checked = try ProjectPackage.checkedArchive(data)
        var sourceCells: [String: [(name: String, entry: Entry)]] = [:]
        var notices = [LegacyNotice]()
        var previewEntries: [String: Entry] = [:]

        for item in checked.entries {
            if item.parts[0] == "Representing" && item.entry.type == .file {
                previewEntries[item.entry.path] = item.entry
                continue
            }
            guard let first = item.parts.first, rootNumber(first) != nil else {
                if item.entry.type == .file, item.parts.last != ".DS_Store" {
                    notices.append(.unknownEntry(item.entry.path))
                }
                continue
            }

            var index = 1
            while index + 1 < item.parts.count, item.parts[index] == "Children",
                  rootNumber(item.parts[index + 1]) != nil {
                index += 2
                guard index <= 257 else { throw ProjectError.tooLarge }
            }
            for count in stride(from: 1, through: index, by: 2) {
                let path = item.parts.prefix(count).joined(separator: "/")
                if sourceCells[path] == nil { sourceCells[path] = [] }
            }
            let path = item.parts.prefix(index).joined(separator: "/")
            let rest = Array(item.parts.dropFirst(index))
            if item.entry.type == .file, rest.count == 2, rest[0] == "Contents", rest[1].hasPrefix("Content.") {
                sourceCells[path, default: []].append((rest[1], item.entry))
            } else if item.entry.type == .file, rest != [".DS_Store"] {
                notices.append(.unknownEntry(item.entry.path))
            }
        }

        let roots = sourceCells.keys.filter { !$0.contains("/") }
        guard roots.count == 1, let rootPath = roots.first, let originalRoot = rootNumber(rootPath) else {
            throw ProjectError.invalidDocument("mandala")
        }
        let title = (filename as NSString).deletingPathExtension
        var project = try Project(title: title, center: "")
        project.manifest.legacyRootID = originalRoot
        let root = project.manifest.rootCellID
        var ids = [rootPath: root]
        var used: Set<String> = [root]
        for path in sourceCells.keys.sorted() where path != rootPath {
            let id = try ShortID.generate(excluding: used)
            ids[path] = id
            used.insert(id)
        }

        var assetIDs = Set<String>()
        func storeAsset(_ data: Data, ext: String) throws -> String {
            let id = try ShortID.generate(excluding: assetIDs)
            assetIDs.insert(id)
            let name = id + "." + ext
            project.assets[name] = data
            return "assets/" + name
        }

        for (path, files) in sourceCells.sorted(by: { $0.key < $1.key }) {
            var cell = Cell()
            var resources = [CellResource]()
            for (name, entry) in files.sorted(by: { $0.name < $1.name }) {
                let contents = try ProjectPackage.extract(entry, from: checked.archive)
                if name == "Content.txt" {
                    guard let body = String(data: contents, encoding: .utf8) else {
                        throw ProjectError.invalidDocument(entry.path)
                    }
                    cell.body = body
                } else {
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard ext.range(of: #"^[a-z0-9]{1,16}$"#, options: .regularExpression) != nil else {
                        notices.append(.unknownEntry(entry.path))
                        continue
                    }
                    let kind: CellResource.Kind
                    if backgroundExtensions.contains(ext) { kind = .image }
                    else if videoExtensions.contains(ext) { kind = .video }
                    else if audioExtensions.contains(ext) { kind = .audio }
                    else { kind = .file }
                    resources.append(.init(kind: kind, path: try storeAsset(contents, ext: ext), originalFilename: name))
                }
            }
            if !resources.isEmpty { cell.resources = resources }
            project.cells[ids[path]!] = cell
        }

        for (path, child) in ids where path != rootPath {
            let parts = path.split(separator: "/").map(String.init)
            let parentPath = parts.dropLast(2).joined(separator: "/")
            guard let parentID = ids[parentPath], var parent = project.cells[parentID],
                  let number = rootNumber(parts.last!) else { throw ProjectError.invalidDocument(path) }
            if let slot = Slot.allCases.first(where: { $0.legacyID == number }) {
                guard parent.child(at: slot) == nil else { throw ProjectError.invalidDocument(path) }
                parent.setChild(child, at: slot)
            } else {
                var extras = parent.legacyChildren ?? [:]
                guard extras[String(number)] == nil else { throw ProjectError.invalidDocument(path) }
                extras[String(number)] = child
                parent.legacyChildren = extras
            }
            project.cells[parentID] = parent
        }

        var previewPath = previewDefault
        if let entry = previewEntries[previewInfo] {
            let info = try ProjectPackage.extract(entry, from: checked.archive)
            if let values = (try? PropertyListSerialization.propertyList(from: info, format: nil)) as? [String: String],
               let declared = values["representingEntry"], previewEntries[declared] != nil {
                previewPath = declared
            } else { notices.append(.unknownEntry(previewInfo)) }
        }
        if let entry = previewEntries[previewPath] {
            let contents = try ProjectPackage.extract(entry, from: checked.archive)
            let ext = (previewPath as NSString).pathExtension.lowercased()
            if backgroundExtensions.contains(ext) {
                let asset = try storeAsset(contents, ext: ext)
                project.manifest.legacyPreviewPath = asset
                if !(project.cells[root]?.resources ?? []).contains(where: { $0.kind == .image }) {
                    project.cells[root]?.resources = [.init(kind: .image, path: asset, originalFilename: "Representing." + ext)]
                }
            } else { notices.append(.unknownEntry(previewPath)) }
        }
        for path in previewEntries.keys.sorted() where path != previewPath && path != previewInfo {
            notices.append(.unknownEntry(path))
        }
        try project.validate()
        return (project, notices)
    }

    public static func notices(for project: Project, includeLinks: Bool) -> [LegacyNotice] {
        var notices = [LegacyNotice]()
        if !project.reminderLinks.isEmpty { notices.append(.reminderRecords) }
        for (id, cell) in project.cells.sorted(by: { $0.key < $1.key }) {
            if !(cell.actions ?? []).isEmpty { notices.append(.actions(id)) }
            if cell.color != nil { notices.append(.color(id)) }
            let resources = cell.resources ?? []
            let printableLinks = includeLinks ? resources.filter { $0.url != nil }.count : 0
            let hasCover = images(in: cell, project: project).lazy.compactMap { jpeg($0) }.first != nil
            if resources.count > printableLinks + (hasCover ? 1 : 0) { notices.append(.resources(id)) }
        }
        return notices
    }

    public static func write(_ project: Project, includeLinks: Bool) throws -> Data {
        try project.validate()
        let archive = try Archive(accessMode: .create)
        let root = project.manifest.rootCellID
        // Root 9 is common in the provided samples. Official-app round trips are checked separately.
        var pending = [(root, "\(project.manifest.legacyRootID ?? 9).cell")]
        var firstImage: Data?
        while let (id, path) = pending.popLast(), let cell = project.cells[id] {
            try ProjectPackage.add(path + "/", data: nil, to: archive)
            let content = path + "/Contents/"
            var body = cell.body
            if includeLinks {
                let links = (cell.resources ?? []).compactMap { resource -> String? in
                    guard let url = resource.url else { return nil }
                    return resource.title.map { $0 + ": " + url } ?? url
                }
                if !links.isEmpty { body += (body.isEmpty ? "" : "\n\n") + links.joined(separator: "\n") }
            }
            let picture = images(in: cell, project: project).lazy.compactMap { jpeg($0) }.first
            if !body.isEmpty || picture != nil {
                try ProjectPackage.add(content, data: nil, to: archive)
            }
            if !body.isEmpty { try ProjectPackage.add(content + "Content.txt", data: Data(body.utf8), to: archive) }
            if let picture {
                try ProjectPackage.add(content + "Content.jpeg", data: picture, to: archive)
                if firstImage == nil { firstImage = picture }
            }
            let children = Slot.allCases.compactMap { slot in cell.child(at: slot).map { (slot.legacyID, $0) } } +
                (cell.legacyChildren ?? [:]).compactMap { item in Int(item.key).map { ($0, item.value) } }
            if !children.isEmpty { try ProjectPackage.add(path + "/Children/", data: nil, to: archive) }
            for (number, child) in children.sorted(by: { $0.0 > $1.0 }) {
                pending.append((child, path + "/Children/\(number).cell"))
            }
        }
        let retained = project.manifest.legacyPreviewPath.flatMap { project.assets[String($0.dropFirst(7))] }
        let preview = retained.flatMap { png($0) } ?? firstImage.flatMap { png($0) } ?? blankPNG()
        if let preview {
            let info = try PropertyListSerialization.data(fromPropertyList: ["representingEntry": previewDefault],
                                                          format: .xml, options: 0)
            try ProjectPackage.add("Representing/", data: nil, to: archive)
            try ProjectPackage.add(previewDefault, data: preview, to: archive)
            try ProjectPackage.add(previewInfo, data: info, to: archive)
        }
        guard let output = archive.data else { throw ProjectError.invalidDocument("mandala") }
        return output
    }

    private static func rootNumber(_ part: String) -> Int? {
        guard part.hasSuffix(".cell"), let id = Int(part.dropLast(5)), id >= 0,
              part == "\(id).cell" else { return nil }
        return id
    }

    private static func images(in cell: Cell, project: Project) -> [Data] {
        (cell.resources ?? []).compactMap { resource in
            guard resource.kind == .image, let path = resource.path else { return nil }
            return project.assets[String(path.dropFirst("assets/".count))]
        }
    }

    private static func jpeg(_ data: Data) -> Data? {
        if data.starts(with: [0xff, 0xd8, 0xff]),
           let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0 { return data }
        return convert(data, type: .jpeg, size: 2400)
    }

    private static func png(_ data: Data) -> Data? { convert(data, type: .png, size: 640) }

    private static func convert(_ data: Data, type: UTType, size: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
              ] as CFDictionary) else { return nil }
        return encode(image, type: type)
    }

    private static func blankPNG() -> Data? {
        guard let context = CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 0.09, green: 0.16, blue: 0.24, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        context.setStrokeColor(red: 0.95, green: 0.81, blue: 0.56, alpha: 1)
        context.setLineWidth(2)
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = CGRect(x: 31 + column * 34, y: 31 + row * 34, width: 30, height: 30)
                if row == 1 && column == 1 {
                    context.setFillColor(red: 0.95, green: 0.81, blue: 0.56, alpha: 1)
                    context.fill(rect)
                } else {
                    context.stroke(rect)
                }
            }
        }
        return context.makeImage().flatMap { encode($0, type: .png) }
    }

    private static func encode(_ image: CGImage, type: UTType) -> Data? {
        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, nil)
        return CGImageDestinationFinalize(target) ? output as Data : nil
    }
}
