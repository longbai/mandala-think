import Foundation
import Security

public enum ProjectError: Error, Equatable {
    case invalidDocument(String)
    case unsupportedVersion(Int)
    case invalidResource(String)
    case tooLarge
    case conflict
    case occupiedSlot
    case randomUnavailable
}

public enum ShortID {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz-_~".utf8)

    public static func isValid(_ value: String) -> Bool {
        value.utf8.count == 13 && value.utf8.allSatisfy(alphabet.contains)
    }

    public static func generate(excluding existing: Set<String> = []) throws -> String {
        while true {
            var result = [UInt8]()
            while result.count < 13 {
                var bytes = [UInt8](repeating: 0, count: 32)
                let status = bytes.withUnsafeMutableBytes {
                    SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
                }
                guard status == errSecSuccess else { throw ProjectError.randomUnavailable }
                let limit = 256 / alphabet.count * alphabet.count
                for byte in bytes where Int(byte) < limit {
                    result.append(alphabet[Int(byte) % alphabet.count])
                    if result.count == 13 { break }
                }
            }
            let id = String(decoding: result, as: UTF8.self)
            if !existing.contains(id) { return id }
        }
    }
}

public enum Slot: String, CaseIterable, Codable, Hashable, Sendable {
    case topLeft = "top_left", top, topRight = "top_right", left, right
    case bottomLeft = "bottom_left", bottom, bottomRight = "bottom_right"

    public static let layout: [Slot?] = [.topLeft, .top, .topRight, .left, nil, .right, .bottomLeft, .bottom, .bottomRight]
    public var legacyID: Int { Self.layout.firstIndex(of: self)! }
}

public struct ProjectManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    public var schemaVersion: Int = ProjectManifest.currentSchemaVersion
    public var projectID: String
    public var title: String
    public var rootCellID: String
    public var revision: String
    public var legacyRootID: Int?
    public var legacyPreviewPath: String?
    public var template: ProjectTemplate?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version", projectID = "project_id", title
        case rootCellID = "root_cell_id", revision, legacyRootID = "legacy_root_id"
        case legacyPreviewPath = "legacy_preview_path", template
    }
}

public enum ProjectTemplate: String, Codable, Sendable { case fiveW = "five_w", time }

public enum CellColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, blue, purple, gray
}

public struct Cell: Codable, Equatable, Sendable {
    public var body: String
    public var color: CellColor?
    public var children: [String: String]?
    public var resources: [CellResource]?
    public var actions: [CellAction]?
    public var legacyChildren: [String: String]?

    public init(body: String = "") {
        self.body = body
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case body, color, children, resources, actions, legacyChildren = "legacy_children"
    }

    public var previewLine: String? {
        body.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    public var previewText: String? {
        previewLine ?? actions?.first?.title.trimmingCharacters(in: .whitespaces)
    }

    public var containsContent: Bool {
        previewLine != nil || color != nil || !(resources ?? []).isEmpty || !(actions ?? []).isEmpty
    }

    public func child(at slot: Slot) -> String? { children?[slot.rawValue] }

    public mutating func setChild(_ id: String?, at slot: Slot) {
        var positions = children ?? [:]
        positions[slot.rawValue] = id
        children = positions.isEmpty ? nil : positions
    }

    public static func == (lhs: Cell, rhs: Cell) -> Bool {
        lhs.body.utf8.elementsEqual(rhs.body.utf8) &&
        lhs.color == rhs.color && lhs.children == rhs.children && lhs.resources == rhs.resources &&
        lhs.actions == rhs.actions && lhs.legacyChildren == rhs.legacyChildren
    }
}

public struct CellResource: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case link, image, video, audio, file }
    public var kind: Kind
    public var url: String?
    public var path: String?
    public var title: String?
    public var caption: String?
    public var originalFilename: String?

    public init(kind: Kind, url: String? = nil, path: String? = nil, title: String? = nil,
                caption: String? = nil, originalFilename: String? = nil) {
        self.kind = kind
        self.url = url
        self.path = path
        self.title = title
        self.caption = caption
        self.originalFilename = originalFilename
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, url, path, title, caption, originalFilename = "original_filename"
    }

    public static func isWebURL(_ value: String) -> Bool {
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host, !host.isEmpty else { return false }
        return parts.url != nil && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public struct CellAction: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var due: ActionDue?

    public init(id: String, title: String, notes: String? = nil, due: ActionDue? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, title, notes, due }

    public static func == (lhs: CellAction, rhs: CellAction) -> Bool {
        lhs.id == rhs.id && lhs.title.utf8.elementsEqual(rhs.title.utf8) &&
        lhs.notes.map { Array($0.utf8) } == rhs.notes.map { Array($0.utf8) } && lhs.due == rhs.due
    }
}

public struct ActionDue: Codable, Equatable, Sendable {
    public var date: String
    public var time: String?
    public var timeZone: String?

    public init(date: String, time: String? = nil, timeZone: String? = nil) {
        self.date = date
        self.time = time
        self.timeZone = timeZone
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case date, time, timeZone = "time_zone" }

    public func components() throws -> DateComponents {
        let invalid = ProjectError.invalidDocument("actions.due")
        guard date.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
              (time == nil) == (timeZone == nil) else { throw invalid }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { throw invalid }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard day.isValidDate(in: calendar) else { throw invalid }
        guard let time, let timeZone else {
            var result = day
            result.calendar = Calendar(identifier: .gregorian)
            return result
        }
        guard time.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil,
              TimeZone.knownTimeZoneIdentifiers.contains(timeZone), let zone = TimeZone(identifier: timeZone) else {
            throw invalid
        }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2 else { throw invalid }
        var local = day
        local.hour = clock[0]
        local.minute = clock[1]
        calendar.timeZone = zone
        guard let midnight = calendar.date(from: day),
              let first = calendar.nextDate(after: midnight.addingTimeInterval(-1), matching: local,
                                            matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: midnight.addingTimeInterval(-1), matching: local,
                                           matchingPolicy: .strict, repeatedTimePolicy: .last),
              first == last else { throw invalid }
        local.calendar = calendar
        local.timeZone = zone
        return local
    }
}

public struct ReminderLink: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case pending, created, uncertain }
    public var projectID: String
    public var cellID: String
    public var state: State
    public var operationID: String
    public var systemItemID: String?
    public var systemExternalID: String?
    public var listHint: String?

    public init(projectID: String, cellID: String, state: State, operationID: String,
                systemItemID: String? = nil, systemExternalID: String? = nil, listHint: String? = nil) {
        self.projectID = projectID
        self.cellID = cellID
        self.state = state
        self.operationID = operationID
        self.systemItemID = systemItemID
        self.systemExternalID = systemExternalID
        self.listHint = listHint
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case projectID = "project_id", cellID = "cell_id", state, operationID = "operation_id"
        case systemItemID = "system_item_id", systemExternalID = "system_external_id", listHint = "list_hint"
    }
}

public struct Project: Equatable, Sendable {
    public var manifest: ProjectManifest
    public var cells: [String: Cell]
    public var assets: [String: Data]
    public var reminderLinks: [String: ReminderLink]

    public init(title: String, center: String, template: ProjectTemplate? = nil) throws {
        let root = try ShortID.generate()
        manifest = try ProjectManifest(projectID: ShortID.generate(), title: title, rootCellID: root,
                                       revision: ShortID.generate(), template: template)
        cells = [root: Cell(body: center)]
        assets = [:]
        reminderLinks = [:]
    }

    init(manifest: ProjectManifest, cells: [String: Cell], assets: [String: Data], reminderLinks: [String: ReminderLink]) {
        self.manifest = manifest
        self.cells = cells
        self.assets = assets
        self.reminderLinks = reminderLinks
    }

    public var actionIDs: Set<String> { Set(cells.values.flatMap { ($0.actions ?? []).map(\.id) }).union(reminderLinks.keys) }

    public mutating func advanceRevision() throws {
        manifest.revision = try ShortID.generate(excluding: [manifest.revision])
    }

    public mutating func makeIndependentCopy() throws {
        manifest.projectID = try ShortID.generate(excluding: [manifest.projectID])
        reminderLinks.removeAll()
        try advanceRevision()
    }

    public func path(to destination: String) -> [String]? {
        var parents: [String: String] = [:]
        for (id, cell) in cells {
            for child in (cell.children ?? [:]).values { parents[child] = id }
            for child in (cell.legacyChildren ?? [:]).values { parents[child] = id }
        }
        guard cells[destination] != nil else { return nil }
        var result = [destination]
        var seen: Set<String> = [destination]
        while let next = parents[result.last!], seen.insert(next).inserted { result.append(next) }
        return result.last == manifest.rootCellID ? result.reversed() : nil
    }

    public mutating func createChild(in parent: String, at slot: Slot, content: Cell) throws -> String {
        guard var parentCell = cells[parent] else { throw ProjectError.invalidDocument(parent) }
        guard parentCell.child(at: slot) == nil else { throw ProjectError.occupiedSlot }
        let id = try ShortID.generate(excluding: Set(cells.keys))
        parentCell.setChild(id, at: slot)
        cells[parent] = parentCell
        cells[id] = content
        return id
    }

    public mutating func move(_ id: String, to targetParent: String, at slot: Slot) throws {
        guard id != manifest.rootCellID, let originalPath = path(to: id),
              let originalParent = originalPath.dropLast().last, let targetPath = path(to: targetParent),
              !targetPath.contains(id), var from = cells[originalParent], var to = cells[targetParent],
              let oldSlotName = from.children?.first(where: { $0.value == id })?.key,
              let oldSlot = Slot(rawValue: oldSlotName) else { throw ProjectError.invalidDocument(id) }
        if originalParent == targetParent {
            if oldSlot == slot { return }
            let replaced = from.child(at: slot)
            from.setChild(replaced, at: oldSlot)
            from.setChild(id, at: slot)
            cells[originalParent] = from
        } else {
            guard to.child(at: slot) == nil else { throw ProjectError.occupiedSlot }
            from.setChild(nil, at: oldSlot)
            to.setChild(id, at: slot)
            cells[originalParent] = from
            cells[targetParent] = to
        }
    }

    public static func assetName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && ShortID.isValid(String(parts[0])) &&
            parts[1].range(of: #"^[a-z0-9]{1,16}$"#, options: .regularExpression) != nil
    }

    public func validate() throws {
        guard manifest.schemaVersion == ProjectManifest.currentSchemaVersion else { throw ProjectError.unsupportedVersion(manifest.schemaVersion) }
        guard ShortID.isValid(manifest.projectID), ShortID.isValid(manifest.rootCellID),
              ShortID.isValid(manifest.revision), cells[manifest.rootCellID] != nil,
              (manifest.legacyRootID ?? 0) >= 0 else { throw ProjectError.invalidDocument("project.yaml") }
        guard cells.count <= 20_000 else { throw ProjectError.tooLarge }
        for name in assets.keys where !Self.assetName(name) { throw ProjectError.invalidResource(name) }
        if let preview = manifest.legacyPreviewPath { try validateAssetPath(preview) }

        var visited = Set<String>()
        var pending = [(manifest.rootCellID, 0)]
        var actions = Set<String>()
        while let (id, depth) = pending.popLast() {
            guard depth <= 128 else { throw ProjectError.tooLarge }
            guard ShortID.isValid(id), let cell = cells[id], visited.insert(id).inserted else {
                throw ProjectError.invalidDocument(id)
            }
            for (slot, child) in cell.children ?? [:] {
                guard Slot(rawValue: slot) != nil else { throw ProjectError.invalidDocument(id + "/" + slot) }
                pending.append((child, depth + 1))
            }
            for (slot, child) in cell.legacyChildren ?? [:] {
                guard let value = Int(slot), value >= 0, String(value) == slot,
                      !Slot.allCases.contains(where: { $0.legacyID == value }) else {
                    throw ProjectError.invalidDocument(id + "/" + slot)
                }
                pending.append((child, depth + 1))
            }
            for resource in cell.resources ?? [] {
                switch (resource.path, resource.url) {
                case (let path?, nil) where resource.kind != .link: try validateAssetPath(path)
                case (nil, let url?) where CellResource.isWebURL(url): break
                default: throw ProjectError.invalidResource(id)
                }
            }
            for action in cell.actions ?? [] {
                guard ShortID.isValid(action.id), actions.insert(action.id).inserted,
                      !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      action.title.rangeOfCharacter(from: .newlines) == nil else {
                    throw ProjectError.invalidDocument(id + "/actions")
                }
                _ = try action.due?.components()
            }
        }
        guard visited.count == cells.count else { throw ProjectError.invalidDocument("cells") }
        var operations = Set<String>()
        for (id, link) in reminderLinks {
            guard ShortID.isValid(id), link.projectID == manifest.projectID, ShortID.isValid(link.cellID),
                  ShortID.isValid(link.operationID), operations.insert(link.operationID).inserted else {
                throw ProjectError.invalidDocument("reminder-links/" + id)
            }
        }
    }

    private func validateAssetPath(_ path: String) throws {
        let file = String(path.dropFirst("assets/".count))
        guard path.hasPrefix("assets/"), Self.assetName(file), assets[file] != nil else {
            throw ProjectError.invalidResource(path)
        }
    }
}
