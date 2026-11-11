import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Where captures go: PNG files in the save folder, and the clipboard.
enum Output {
    /// PNG with its pixel density, so a Retina capture opens at its on-screen size.
    static func png(_ image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * max(scale, 1)
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// "Longo Shot 2026-11-11 at 09.41.07.png", like macOS names its own screenshots.
    static func fileName(at date: Date, extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Longo Shot \(formatter.string(from: date)).\(ext)"
    }

    /// The name in `folder`, with " 2", " 3"… added when it's taken (two captures in the same second).
    static func freeURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }

    static func save(_ data: Data, in folder: URL, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = freeURL(in: folder, name: fileName(at: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The image, plus the file when there is one: apps that take images paste the picture, Finder pastes the file.
    static func copy(png: Data, file: URL?) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let file { item.setString(file.absoluteString, forType: .fileURL) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func copy(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
