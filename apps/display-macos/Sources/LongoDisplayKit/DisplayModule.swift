import LongoKitUI

/// Longo Display as a module: what a host needs to run it.
public enum DisplayModule: LongoModule {
    public static let id = "display"
    public static let bundleIdentifier = "com.longokit.display"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""
}
