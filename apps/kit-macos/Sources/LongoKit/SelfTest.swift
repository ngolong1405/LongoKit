import Carbon.HIToolbox
import AppKit
import LongoKitUI
import SwiftUI

/// `LongoKit --selftest` checks turning modules on and off, the settings they share, bringing a module's settings
/// over from its own app, and that every page and menu draws. Modules run without touching the Mac.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    @MainActor
    static func runAndExit() {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "PASS  \(name)" : "FAIL  \(name)")
            if !ok { failures += 1 }
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

        let ids = ModuleInfo.all.map(\.id)
        check("four modules, each once", ids == ["mouse", "display", "keys", "shot"])
        check("each module knows its own app", ModuleInfo.all.map { $0.type.bundleIdentifier }
            == ["com.longngo.MouseMapper", "com.longokit.display", "com.longokit.keys", "com.longokit.shot"])
        check("each module has its logo", ModuleInfo.all.allSatisfy { $0.logo(dark: true) != nil && $0.logo(dark: false) != nil })

        let suiteName = "LongoKit.selftest"
        let storePrefix = "LongoKit.selftest."
        func clean() {
            UserDefaults().removePersistentDomain(forName: suiteName)
            for id in ids + ["probe"] { UserDefaults().removePersistentDomain(forName: storePrefix + id) }
            UserDefaults().removePersistentDomain(forName: "com.longokit.selftest.own")
        }
        clean()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(["mouse", "shot"], forKey: "modules")
        defaults.set(AppLanguage.english.rawValue, forKey: "language")
        var ownAppsOpen: Set<String> = []
        let suite = Suite(live: false, defaults: defaults, storeName: { storePrefix + $0 },
                          runsElsewhere: { ownAppsOpen.contains($0.id) })
        suite.start()
        settle()

        // Which modules run
        check("the modules that are on run", Set(suite.hosts.keys) == ["mouse", "shot"])
        check("the others are off", suite.status("display") == .off && suite.status("keys") == .off)
        check("the window opens on the first module that's on", suite.page == .module("mouse"))
        check("the menu shows the first module that runs", suite.menuInfo.id == "mouse")
        suite.setEnabled(ModuleInfo.named("display")!, true)
        settle()
        check("turning a module on runs it at once", suite.hosts["display"] != nil && suite.status("display") == .running)
        check("…and remembers it", Set(defaults.stringArray(forKey: "modules") ?? []) == ["mouse", "display", "shot"])
        ownAppsOpen.insert("keys")
        suite.setEnabled(ModuleInfo.named("keys")!, true)
        check("a module whose own app is open waits", suite.hosts["keys"] == nil && suite.status("keys") == .elsewhere)
        suite.setEnabled(ModuleInfo.named("mouse")!, false)
        settle()
        check("turning a module off drops it", suite.hosts["mouse"] == nil && suite.status("mouse") == .off)
        check("…and the menu moves to another", suite.menuInfo.id == "display")

        // A module's own app quitting starts the module here, unless it was turned off meanwhile.
        ownAppsOpen.remove("keys")
        suite.ownAppChanged("com.longokit.keys", launched: false)
        suite.setEnabled(ModuleInfo.named("keys")!, false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check("a module turned off while its own app quits stays off", suite.hosts["keys"] == nil && suite.status("keys") == .off)
        suite.setEnabled(ModuleInfo.named("keys")!, true)
        ownAppsOpen.insert("keys")
        suite.ownAppChanged("com.longokit.keys", launched: false)
        ownAppsOpen.remove("keys")
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check("…and one still on takes over", suite.hosts["keys"] != nil)
        suite.setEnabled(ModuleInfo.named("keys")!, false)

        // The Dock icon follows LongoKit's menu bar setting, whatever a module sets.
        suite.showMenuBarIcon = false
        MainWindowRef.keepsDockIconWhenHidden = false // as a module restoring its own defaults would
        suite.hosts["display"]!.appearance = suite.appearance == .dark ? .light : .dark
        settle()
        check("a module can't hide the Dock icon LongoKit keeps", MainWindowRef.keepsDockIconWhenHidden)
        suite.showMenuBarIcon = true

        // Settings every module shares
        suite.language = .vietnamese
        check("the language reaches every module", suite.hosts.values.allSatisfy { $0.language == .vietnamese })
        check("…and the shared translations", Localizer.language == .vietnamese)
        suite.appearance = .light
        check("the appearance reaches every module", suite.hosts.values.allSatisfy { $0.appearance == .light })
        suite.hosts["shot"]!.appearance = .dark
        settle()
        check("a module's own theme switcher changes the app's", suite.appearance == .dark
              && suite.hosts.values.allSatisfy { $0.appearance == .dark })
        check("the shared settings are saved", defaults.string(forKey: "language") == "vi" && defaults.string(forKey: "appearance") == "dark")
        suite.language = .english

        // Opening a module's page
        MainWindowRef.showModule?("shot")
        check("a module asking for the window opens its page", suite.page == .module("shot") && suite.menuModule == "shot")

        // Bringing settings over from a module's own app
        UserDefaults().setPersistentDomain(["probe": 42, "kept": "own"], forName: "com.longokit.selftest.own")
        let store = UserDefaults(suiteName: storePrefix + "probe")!
        store.set("here", forKey: "kept")
        Suite.importSettings(from: "com.longokit.selftest.own", into: store)
        check("a module's settings come over from its own app", store.integer(forKey: "probe") == 42)
        check("…without overwriting what's already here", store.string(forKey: "kept") == "here")
        Suite.importSettings(from: "com.longokit.selftest.missing", into: store)
        check("an app that never ran brings nothing", store.integer(forKey: "probe") == 42)

        // Shortcuts: the modules share one process. The fixed ones never clash (Display ⌃⌥⌘B, Mouse ⌃⌥⌘M, Keys ⌃⌥⌘K;
        // Shot's are ⌥⇧ by default), and a combination one module holds is refused to another, which Shot shows as taken.
        let hyper = controlKey | optionKey | shiftKey | cmdKey
        let held = GlobalHotKey(keyCode: kVK_F17, modifiers: hyper) {}
        let again = GlobalHotKey(keyCode: kVK_F17, modifiers: hyper) {}
        check("a shortcut one module holds can't be taken by another", held.isRegistered && !again.isRegistered)
        check("…and each has an id of its own", held.id != again.id)

        // Every page and menu draws
        for (id, host) in suite.hosts.sorted(by: { $0.key < $1.key }) {
            let panel = render(host.panel.frame(width: Theme.windowWidth))
            check("\(id)'s page draws", panel.map { $0.height > 200 } ?? false)
            let menu = render(host.menu)
            check("\(id)'s menu draws", menu.map { $0.width > 250 && $0.height > 150 } ?? false)
        }
        for page in [Suite.Page.general, .about, .module("keys"), .module("mouse")] {
            suite.page = page
            let window = render(KitWindow(forSnapshot: true).environmentObject(suite))
            check("the window draws \(page)", window.map { abs($0.width - (Sidebar.width + 1 + Theme.windowWidth)) < 1 } ?? false)
        }
        check("the menu draws", render(KitMenu().environmentObject(suite)) != nil)

        clean()
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func render<V: View>(_ view: V) -> CGSize? {
        let renderer = ImageRenderer(content: view.environment(\.rendersFlat, true))
        return renderer.nsImage?.size
    }
}
