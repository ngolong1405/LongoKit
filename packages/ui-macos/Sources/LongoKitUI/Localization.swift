import Foundation

public enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case vietnamese = "vi"

    /// Shown in its own language so it's recognizable either way.
    public var title: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    public static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
    }
}

public enum Localizer {
    public static var language: AppLanguage = .english
    /// English → Vietnamese for every string the app (and this package) shows; each app provides its own.
    public static var vietnamese: [String: String] = [:]
}

/// Translates an English UI string into the chosen app language; unknown strings stay in English.
public func L(_ english: String) -> String {
    guard Localizer.language == .vietnamese else { return english }
    return Localizer.vietnamese[english] ?? english
}

/// Formats a translated template, e.g. `L("%d bindings", count)`.
public func L(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: L(english), arguments: arguments)
}
