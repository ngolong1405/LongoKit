import Foundation

/// Branding and links shown on the About tab.
enum AppInfo {
    static let name = "Longo Display"
    static let author = "Long Ngô"
    static let repo = URL(string: "https://github.com/ngolong1405/LongoKit")!
    static let license = URL(string: "https://github.com/ngolong1405/LongoKit/blob/main/LICENSE.md")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
