import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, korean, english
    var id: String { rawValue }
}

/// Language setting. In system mode, anything other than Korean falls back to English.
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

    var isKorean: Bool {
        switch setting {
        case .korean: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }

    var locale: Locale { Locale(identifier: isKorean ? "ko_KR" : "en_US") }
}

func L(_ korean: String, _ english: String) -> String {
    Language.shared.isKorean ? korean : english
}
