import LongoShareKit
import LongoKitUI
import SwiftUI

@main
struct LongoShareApp: App {
    @NSApplicationDelegateAdaptor(ShareAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        ShareModule.prepare()
    }

    var body: some Scene {
        ShareScenes()
    }
}
