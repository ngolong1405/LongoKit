import AppKit

/// One LongoKit app as a part a host can run: its own small app, or one app holding several modules.
public protocol LongoModule {
    /// Short, stable id: "mouse", "display", "keys", "shot".
    static var id: String { get }
    /// The stand-alone app's bundle id: where its settings live, and the copy a host must not run beside.
    static var bundleIdentifier: String { get }
    /// The module's translations, read before the shared table.
    static var vietnamese: [String: String] { get }
    /// Folder under Contents/Resources holding the module's own images; empty in its stand-alone app, where they sit
    /// at the top.
    static var resourceFolder: String { get set }
}

public extension LongoModule {
    /// Once at launch, after `Resource.developmentSupport`: shares the module's translations with LongoKitUI's
    /// controls and registers the fonts.
    static func prepare() {
        Localizer.register(vietnamese)
        Fonts.register()
    }

    /// One of the module's own images, such as "Logo.png".
    static func image(_ name: String) -> NSImage? {
        Resource.image(resourceFolder + name)
    }
}
