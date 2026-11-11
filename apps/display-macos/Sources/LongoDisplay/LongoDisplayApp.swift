import LongoDisplayKit
import LongoKitUI
import SwiftUI

@main
struct LongoDisplayApp: App {
    @NSApplicationDelegateAdaptor(DisplayAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        DisplayModule.prepare()
    }

    var body: some Scene {
        DisplayScenes()
    }
}
