import Foundation

/// Where an app keeps what it saves: its own folder in Downloads ("Longo Shot", "Longo Share"), made at launch, as
/// Telegram does. The person can pick another one; that one is kept.
public enum AppFolder {
    public static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// The app's own folder: Downloads/`name`.
    public static func standard(_ name: String) -> URL {
        downloads.appendingPathComponent(name, isDirectory: true)
    }

    /// The folder to use: the one the person picked, or the app's own. Downloads itself (the old default) moves to the
    /// app's own folder. The folder is made if it isn't there.
    public static func resolve(saved path: String?, name: String) -> URL {
        var folder = standard(name)
        if let path, !path.isEmpty {
            let picked = URL(fileURLWithPath: path, isDirectory: true)
            if picked.standardizedFileURL.path != downloads.standardizedFileURL.path { folder = picked }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
