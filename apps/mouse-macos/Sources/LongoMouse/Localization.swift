import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case vietnamese = "vi"

    /// Shown in its own language so it's recognizable either way.
    var title: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
    }
}

enum Localizer {
    static var language: AppLanguage = .english
}

/// Translates an English UI string into the chosen app language; unknown strings stay in English.
func L(_ english: String) -> String {
    guard Localizer.language == .vietnamese else { return english }
    return Vietnamese.strings[english] ?? english
}

/// Formats a translated template, e.g. `L("%d bindings", count)`.
func L(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: L(english), arguments: arguments)
}
