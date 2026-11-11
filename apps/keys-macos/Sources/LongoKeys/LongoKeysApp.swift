import LongoKeysKit
import LongoKitUI
import SwiftUI

@main
struct LongoKeysApp: App {
    @NSApplicationDelegateAdaptor(KeysAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        KeysModule.prepare()
    }

    var body: some Scene {
        KeysScenes()
    }
}
