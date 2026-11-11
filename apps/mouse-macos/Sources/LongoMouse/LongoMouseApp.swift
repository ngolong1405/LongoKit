import LongoMouseKit
import LongoKitUI
import SwiftUI

@main
struct LongoMouseApp: App {
    @NSApplicationDelegateAdaptor(MouseAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        MouseModule.prepare()
    }

    var body: some Scene {
        MouseScenes()
    }
}
