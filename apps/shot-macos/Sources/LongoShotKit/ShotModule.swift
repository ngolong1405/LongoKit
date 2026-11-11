import LongoKitUI

/// Longo Shot as a module: what a host needs to run it.
public enum ShotModule: LongoModule {
    public static let id = "shot"
    public static let bundleIdentifier = "com.longokit.shot"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""
}
