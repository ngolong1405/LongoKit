import Foundation

/// Branding and links shown on the About tab. Fill in the optional URLs to show the sponsor button and link tiles.
enum AppInfo {
    static let name = "Longo Mouse"
    static let tagline = "Custom mouse buttons, gestures, and scrolling for macOS."
    static let author = "Long Ngô"
    static let license = "Personal Use"
    static let communityTitle = "Project & Community"
    static let communityBlurb = "\(name) is part of LongoKit, a set of tools for mice, keyboards, and displays."

    static let sponsorTitle = "Sponsor"
    static let sponsorURL: URL? = nil
    static let releaseNotesURL: URL? = nil
    static let links: [AppLink] = [
        AppLink(title: "GitHub", detail: "ngolong1405/LongoKit", url: URL(string: "https://github.com/ngolong1405/LongoKit")!),
    ]

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

struct AppLink: Identifiable {
    var title: String
    var detail: String
    var url: URL
    var id: String { title }
}

enum SystemInfo {
    static var summary: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let chip = "Apple Silicon"
        #else
        let chip = "Intel"
        #endif
        return "macOS \(v.majorVersion).\(v.minorVersion) • \(chip)"
    }
}
