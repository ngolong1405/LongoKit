import LongoKitUI

/// Longo Keys as a module: what a host needs to run it.
public enum KeysModule: LongoModule {
    public static let id = "keys"
    public static let bundleIdentifier = "com.longokit.keys"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""
}
