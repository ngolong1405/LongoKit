import LongoFlowKit
import LongoKitUI
import SwiftUI

@main
struct LongoFlowApp: App {
    @NSApplicationDelegateAdaptor(FlowAppDelegate.self) private var appDelegate

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        FlowModule.prepare()
    }

    var body: some Scene {
        FlowScenes()
    }
}
