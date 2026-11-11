import LongoKitUI

/// Longo Mouse as a module: what a host needs to run it.
public enum MouseModule: LongoModule {
    public static let id = "mouse"
    public static let bundleIdentifier = "com.longngo.MouseMapper"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""
}
