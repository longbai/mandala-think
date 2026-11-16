import Foundation
import Yams

enum YAMLDocument {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
        return Data((try write(object, depth: 0) + "\n").utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, filename: String,
                                      migrateEarlyBuildCell: Bool = false) throws -> T {
        do {
            guard data.count <= 16 * 1024 * 1024, let source = String(data: data, encoding: .utf8),
                  let node = try Parser(yaml: source).singleRestrictedRoot(), node.mapping != nil else {
                throw ProjectError.invalidDocument(filename)
            }
            try checkKeys(node, for: type, migrateEarlyBuildCell: migrateEarlyBuildCell)
            guard var object = try read(node, depth: 0) as? [String: Any] else {
                throw ProjectError.invalidDocument(filename)
            }
            if migrateEarlyBuildCell, let earlyHeading = object.removeValue(forKey: "title") {
                guard let heading = earlyHeading as? String, let body = object["body"] as? String else {
                    throw ProjectError.invalidDocument(filename)
                }
                if !heading.isEmpty, Cell(body: body).previewLine?.utf8.elementsEqual(heading.utf8) != true {
                    object["body"] = body.isEmpty ? heading : heading + "\n\n" + body
                }
            }
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
        } catch {
            throw ProjectError.invalidDocument(filename)
        }
    }

    private static func checkKeys<T>(_ node: Node, for type: T.Type, migrateEarlyBuildCell: Bool) throws {
        if type == ProjectManifest.self { try only(node, ProjectManifest.CodingKeys.allCases) }
        if type == ReminderLink.self { try only(node, ReminderLink.CodingKeys.allCases) }
        if type == Cell.self {
            try only(node, Cell.CodingKeys.allCases, allowing: migrateEarlyBuildCell ? "title" : nil)
            for resource in node["resources"]?.sequence ?? [] { try only(resource, CellResource.CodingKeys.allCases) }
            for action in node["actions"]?.sequence ?? [] {
                try only(action, CellAction.CodingKeys.allCases)
                if let due = action["due"] { try only(due, ActionDue.CodingKeys.allCases) }
            }
        }
    }

    private static func only<Key: CodingKey>(_ node: Node, _ keys: [Key], allowing extra: String? = nil) throws {
        var allowed = Set(keys.map(\.stringValue))
        if let extra { allowed.insert(extra) }
        guard let mapping = node.mapping, mapping.allSatisfy({ $0.key.string.map(allowed.contains) == true }) else {
            throw ProjectError.invalidDocument("YAML keys")
        }
    }

    private static func read(_ node: Node, depth: Int) throws -> Any {
        let invalid = ProjectError.invalidDocument("YAML")
        guard depth <= 16, node.anchor == nil else { throw invalid }
        switch node {
        case .scalar(let scalar):
            if node.tag.rawValue == Tag.Name.str.rawValue { return scalar.string }
            if node.tag.rawValue == Tag.Name.int.rawValue,
               scalar.string.range(of: #"^-?(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil,
               let value = Int(scalar.string) { return value }
            throw invalid
        case .mapping(let mapping):
            var result: [String: Any] = [:]
            for (key, value) in mapping {
                guard case .scalar(let scalar) = key, key.anchor == nil,
                      key.tag.rawValue == Tag.Name.str.rawValue, scalar.string != "<<",
                      result[scalar.string] == nil else { throw invalid }
                result[scalar.string] = try read(value, depth: depth + 1)
            }
            return result
        case .sequence(let sequence):
            return try sequence.map { try read($0, depth: depth + 1) }
        case .alias:
            throw invalid
        }
    }

    private static func write(_ object: Any, depth: Int) throws -> String {
        let indent = String(repeating: "  ", count: depth)
        if let mapping = object as? [String: Any], !mapping.isEmpty {
            return try mapping.keys.sorted().map { key in
                try line(indent + scalar(key) + ":", mapping[key]!, depth: depth)
            }.joined(separator: "\n")
        }
        if let sequence = object as? [Any], !sequence.isEmpty {
            return try sequence.map { try line(indent + "-", $0, depth: depth) }.joined(separator: "\n")
        }
        return try indent + scalar(object)
    }

    private static func line(_ prefix: String, _ value: Any, depth: Int) throws -> String {
        if let mapping = value as? [String: Any], !mapping.isEmpty {
            return try prefix + "\n" + write(mapping, depth: depth + 1)
        }
        if let sequence = value as? [Any], !sequence.isEmpty {
            return try prefix + "\n" + write(sequence, depth: depth + 1)
        }
        return try prefix + " " + scalar(value)
    }

    private static func scalar(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{0085}", with: "\\u0085")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
