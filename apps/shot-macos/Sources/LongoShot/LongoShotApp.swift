import LongoShotKit
import LongoKitUI
import SwiftUI

@main
struct LongoShotApp: App {
    @NSApplicationDelegateAdaptor(ShotAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        ShotModule.prepare()
    }

    var body: some Scene {
        ShotScenes()
    }
}
