import AppKit

/// Installing from the disk image without hunting for the app afterwards. A disk image can't run anything when the app
/// is dragged out of it, so the app does it when it's opened:
/// - opened from the disk image, it offers to move itself to Applications, then opens from there;
/// - opened from Applications after an install, it offers to eject the disk image and put the installer in the Trash.
@MainActor
public enum SelfInstall {
    private static let installedFrom = "--installed-from"
    private static let offeredKey = "installerCleanupOffered"

    /// Once at launch, for the app itself (not self-tests or snapshots).
    public static func check() {
        let app = originalURL(of: Bundle.main.bundleURL)
        if isOnDiskImage(app) {
            offerToMove(app)
        } else if isInstalled(app) {
            offerToDeleteInstaller()
        }
    }

    // MARK: - Moving to Applications

    private static var name: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    }

    private static func offerToMove(_ app: URL) {
        let alert = NSAlert()
        alert.messageText = L("Move %@ to Applications?", name)
        alert.informativeText = L("It's running from the disk image. In Applications it stays installed, and opens from Launchpad and Spotlight.")
        alert.addButton(withTitle: L("Move to Applications"))
        alert.addButton(withTitle: L("Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        do {
            let installed = try install(app, into: applications)
            let image = volume(of: app).flatMap(diskImage(mountedAt:))
            // The installed copy opens once this one has quit (only one copy runs at a time), ejects the disk image and
            // offers to delete the installer.
            let pid = ProcessInfo.processInfo.processIdentifier
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$0\" --args \(installedFrom) \"$1\"",
                              installed.path, image ?? ""]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            let failed = NSAlert()
            failed.messageText = L("Couldn't move %@ to Applications", name)
            failed.informativeText = error.localizedDescription + "\n" + L("Drag it into Applications from the disk image instead.")
            failed.runModal()
        }
    }

    /// Copies `app` into `folder` (an older copy goes to the Trash; a running one is asked to quit first) and clears
    /// the download quarantine, which the person has already got past to open it. Returns the copy.
    public static func install(_ app: URL, into folder: URL) throws -> URL {
        let target = folder.appendingPathComponent(app.lastPathComponent)
        if let id = Bundle(url: app)?.bundleIdentifier {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: id)
            where running.bundleURL?.standardizedFileURL == target.standardizedFileURL {
                running.terminate()
                for _ in 0..<50 where !running.isTerminated { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            }
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        }
        try FileManager.default.copyItem(at: app, to: target)
        let clear = Process()
        clear.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        clear.arguments = ["-dr", "com.apple.quarantine", target.path]
        try? clear.run()
        clear.waitUntilExit()
        return target
    }

    // MARK: - Deleting the installer

    private static func offerToDeleteInstaller() {
        let arguments = CommandLine.arguments
        let given = arguments.firstIndex(of: installedFrom).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        // Asked once per version, unless the disk image itself just installed it.
        guard given != nil || UserDefaults.standard.string(forKey: offeredKey) != version else { return }
        UserDefaults.standard.set(version, forKey: offeredKey)
        let images = installers(given: given.flatMap { $0.isEmpty ? nil : $0 })
        guard !images.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("%@ is installed", name)
        alert.informativeText = L("Delete the installer? It isn't needed any more.") + "\n" + images.map(\.lastPathComponent).joined(separator: ", ")
        alert.addButton(withTitle: L("Move to Trash"))
        alert.addButton(withTitle: L("Keep"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for image in images {
            for mount in mountPoints(of: image.path) { detach(mount) }
            try? FileManager.default.trashItem(at: image, resultingItemURL: nil)
        }
    }

    /// The installers to offer: the disk image that installed it, any mounted one holding this app, and the app's
    /// disk images in Downloads (named like "LongoKit-0.1.2.dmg").
    private static func installers(given: String?) -> [URL] {
        var found: [String] = given.map { [$0] } ?? []
        let id = Bundle.main.bundleIdentifier
        for image in attachedImages() where image.mounts.contains(where: { holdsApp(id, at: $0) }) {
            found.append(image.path)
        }
        let executable = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? name
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            found += installerFiles(named: executable, in: downloads).map(\.path)
        }
        var seen = Set<String>()
        return found.filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }.map { URL(fileURLWithPath: $0) }
    }

    /// "LongoKit.dmg" and "LongoKit-<version>.dmg" (also "LongoKit-0.1.2 (1).dmg" from a second download) in `folder`.
    public static func installerFiles(named executable: String, in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { file in
            file.hasSuffix(".dmg") && (file == executable + ".dmg" || file.hasPrefix(executable + "-") || file.hasPrefix(executable + " ("))
        }
        .sorted()
        .map { folder.appendingPathComponent($0) }
    }

    private static func holdsApp(_ id: String?, at mount: String) -> Bool {
        guard let id, let names = try? FileManager.default.contentsOfDirectory(atPath: mount) else { return false }
        return names.contains { $0.hasSuffix(".app") && Bundle(path: mount + "/" + $0)?.bundleIdentifier == id }
    }

    // MARK: - Disk images

    /// Whether the app is in Applications (the system's or the person's own); a build run from elsewhere never
    /// offers to delete anything.
    public static func isInstalled(_ app: URL) -> Bool {
        let folder = app.standardizedFileURL.deletingLastPathComponent().path
        return folder == "/Applications" || folder == FileManager.default.homeDirectoryForCurrentUser.path + "/Applications"
    }

    /// Whether the app runs from a mounted disk image.
    public static func isOnDiskImage(_ app: URL) -> Bool {
        volume(of: app) != nil
    }

    /// "/Volumes/LongoKit" for "/Volumes/LongoKit/LongoKit.app".
    public static func volume(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return "/" + parts[1] + "/" + parts[2]
    }

    /// The disk image mounted at `mount`. hdiutil gives paths with symlinks resolved (/private/var for /var), so both
    /// sides are compared that way.
    public static func diskImage(mountedAt mount: String) -> String? {
        let wanted = resolved(mount)
        return attachedImages().first { $0.mounts.map(resolved).contains(wanted) }?.path
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func mountPoints(of image: String) -> [String] {
        attachedImages().first { $0.path == image }?.mounts ?? []
    }

    public static func attachedImages() -> [(path: String, mounts: [String])] {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        task.standardOutput = output
        guard (try? task.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return images(fromInfo: data)
    }

    /// The disk images in `hdiutil info -plist` output, with where each is mounted.
    public static func images(fromInfo data: Data) -> [(path: String, mounts: [String])] {
        guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = info["images"] as? [[String: Any]] else { return [] }
        return images.compactMap { image in
            guard let path = image["image-path"] as? String else { return nil }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            return (path, entities.compactMap { $0["mount-point"] as? String })
        }
    }

    private static func detach(_ mount: String) {
        for force in [false, true] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            task.arguments = ["detach", mount, "-quiet"] + (force ? ["-force"] : [])
            guard (try? task.run()) != nil else { return }
            task.waitUntilExit()
            if task.terminationStatus == 0 { return }
        }
    }

    // MARK: - Translocation

    /// Opened from a quarantined disk image, macOS runs the app from a hidden copy ("App Translocation"); this is
    /// where it really is.
    public static func originalURL(of url: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutableRawPointer?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        var translocated = DarwinBoolean(false)
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url as CFURL, &translocated, nil).boolValue,
              translocated.boolValue,
              let original = unsafeBitCast(originalSymbol, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue() else {
            return url
        }
        return original as URL
    }
}
