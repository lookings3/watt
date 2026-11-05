import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, korean, english, german, japanese
    var id: String { rawValue }
}

/// Language setting. In system mode, an unsupported language falls back to English.
final class Language: ObservableObject {
    static let shared = Language()

    @Published var setting: AppLanguage {
        didSet { try? setting.rawValue.write(to: file, atomically: true, encoding: .utf8) }
    }
    private let file = Storage.directory.appendingPathComponent("language")

    private init() {
        try? FileManager.default.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
        let saved = try? String(contentsOf: file, encoding: .utf8)
        setting = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The language actually shown, never `.system`.
    var resolved: AppLanguage {
        guard setting == .system else { return setting }
        let preferred = Locale.preferredLanguages.first ?? ""
        if preferred.hasPrefix("ko") { return .korean }
        if preferred.hasPrefix("de") { return .german }
        if preferred.hasPrefix("ja") { return .japanese }
        return .english
    }

    var locale: Locale {
        switch resolved {
        case .korean: return Locale(identifier: "ko_KR")
        case .german: return Locale(identifier: "de_DE")
        case .japanese: return Locale(identifier: "ja_JP")
        default: return Locale(identifier: "en_US")
        }
    }
}

func L(_ korean: String, _ english: String, _ german: String, _ japanese: String) -> String {
    switch Language.shared.resolved {
    case .korean: return korean
    case .german: return german
    case .japanese: return japanese
    default: return english
    }
}
