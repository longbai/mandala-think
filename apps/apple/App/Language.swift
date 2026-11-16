import Foundation
import SwiftUI
import MandalaCore

enum AppLanguage: String, CaseIterable {
    case system, en, zh = "zh-Hans", ja, ko

    var name: String {
        switch self {
        case .system: return "language.system"
        case .en: return "English"
        case .zh: return "简体中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }
}

struct Words {
    let language: AppLanguage

    private var localization: String {
        language == .system ? (Bundle.main.preferredLocalizations.first ?? "en") : language.rawValue
    }

    var locale: Locale {
        if language == .system { return .current }
        return Locale(identifier: localization)
    }

    func callAsFunction(_ key: String) -> String {
        let selected = Bundle.main.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:))
        return (selected ?? .main).localizedString(forKey: key, value: nil, table: nil)
    }

    func count(_ key: String, _ number: Int) -> String {
        String(format: self(key), locale: locale, number)
    }

    func described(_ key: String, _ value: String) -> String {
        String(format: self(key), locale: locale, value)
    }

    func error(_ error: Error) -> String {
        guard let projectError = error as? ProjectError else { return self("error.generic") }
        switch projectError {
        case .invalidDocument(let path): return described("error.document", path)
        case .unsupportedVersion(let version): return count("error.version", version)
        case .invalidResource(let path): return described("error.resource", path)
        case .tooLarge: return self("error.size")
        case .conflict: return self("error.conflict")
        case .occupiedSlot: return self("error.occupied")
        case .randomUnavailable: return self("error.generic")
        }
    }

    func notice(_ notice: LegacyNotice, project: Project) -> String {
        func cellName(_ id: String) -> String {
            project.cells[id]?.previewText ?? id
        }
        switch notice {
        case .unknownEntry(let path): return described("notice.entry", path)
        case .actions(let id): return described("notice.actions", cellName(id))
        case .color(let id): return described("notice.color", cellName(id))
        case .resources(let id): return described("notice.resources", cellName(id))
        case .reminderRecords: return self("notice.reminders")
        }
    }
}

private struct WordsKey: EnvironmentKey {
    static let defaultValue = Words(language: .system)
}

extension EnvironmentValues {
    var words: Words {
        get { self[WordsKey.self] }
        set { self[WordsKey.self] = newValue }
    }
}
