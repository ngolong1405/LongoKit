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
    /// English → Vietnamese for the strings this package shows, gathered from every module the app runs.
    public static private(set) var vietnamese: [String: String] = [:]

    /// Adds a module's translations to the shared table. The first module to translate a string keeps it, so modules
    /// that word something differently read their own tables first (see `L(_:in:)`).
    public static func register(_ strings: [String: String]) {
        vietnamese.merge(strings) { first, _ in first }
    }

    /// This package's own words, read last: an app's table can still word them its own way.
    static let package: [String: String] = [
        "Move %@ to Applications?": "Chuyển %@ vào Applications?",
        "It's running from the disk image. In Applications it stays installed, and opens from Launchpad and Spotlight.":
            "App đang chạy từ đĩa cài đặt. Ở trong Applications app sẽ được cài hẳn, mở được từ Launchpad và Spotlight.",
        "Move to Applications": "Chuyển vào Applications",
        "Not Now": "Để sau",
        "Couldn't move %@ to Applications": "Không chuyển được %@ vào Applications",
        "Drag it into Applications from the disk image instead.": "Hãy kéo app từ đĩa cài đặt vào Applications.",
        "%@ is installed": "Đã cài %@",
        "Delete the installer? It isn't needed any more.": "Xoá file cài đặt? Không cần dùng nữa.",
        "Move to Trash": "Chuyển vào Thùng rác",
        "Keep": "Giữ lại",
    ]
}

/// Translates an English UI string into the chosen app language; unknown strings stay in English.
public func L(_ english: String) -> String {
    guard Localizer.language == .vietnamese else { return english }
    return Localizer.vietnamese[english] ?? Localizer.package[english] ?? english
}

/// Translates with a module's own table first, then the shared one. Each module wraps this in its own `L`, which
/// shadows the shared one inside the module.
public func L(_ english: String, in table: [String: String]) -> String {
    guard Localizer.language == .vietnamese else { return english }
    return table[english] ?? Localizer.vietnamese[english] ?? Localizer.package[english] ?? english
}

/// Formats a translated template, e.g. `L("%d bindings", count)`.
public func L(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: L(english), arguments: arguments)
}
