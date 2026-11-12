import AppKit
import AVFoundation
import ImageIO

/// One of the last captures, for the menu's Recent list. Saved captures are only pointed to; ones kept on the
/// clipboard alone have a copy in the app's cache (`cached`), so they can be had again later.
struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let file: URL
    let isMovie: Bool
    /// The file is the app's own copy (or a recording kept off the save folder): it goes when the item goes.
    let cached: Bool
    /// A recording's length in seconds.
    var duration: Int?

    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }
}

/// The Recent list's rules: the newest first, at most `limit`, and the cache kept to what the list still shows.
enum History {
    static let limit = 10

    /// Where copies of clipboard-only captures are kept.
    static var defaultFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("com.longokit.shot/History", isDirectory: true)
    }

    /// `item` added at the front; what falls off the end (or went missing) is returned to be deleted if cached.
    static func adding(_ item: HistoryItem, to items: [HistoryItem]) -> (kept: [HistoryItem], dropped: [HistoryItem]) {
        let all = [item] + items.filter { $0.file != item.file }
        return (Array(all.prefix(limit)), Array(all.dropFirst(limit)))
    }

    /// The app's own copies of `items`, removed from disk (off the main thread; never the user's own files).
    /// Cached copies are written and deleted here, one after another in order: a copy dropped right after it's
    /// added is deleted after it's written, not before (and left behind).
    static let files = DispatchQueue(label: "com.longokit.shot.history", qos: .utility)

    static func deleteCached(_ items: [HistoryItem]) {
        let files = items.filter(\.cached).map(\.file)
        guard !files.isEmpty else { return }
        Self.files.async {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }
}

/// Small pictures for the Recent list, made on demand from the files and kept while memory allows.
@MainActor
final class HistoryThumbnails {
    static let shared = HistoryThumbnails()
    private let cache = NSCache<NSString, NSImage>()
    /// Pixels on the longest side: plenty for a 52-point cell on a Retina screen.
    nonisolated static let size = 200
    /// For the menu's larger preview.
    nonisolated static let previewSize = 600

    private func key(_ item: HistoryItem, _ size: Int) -> NSString { "\(item.file.path)#\(size)" as NSString }

    func cached(_ item: HistoryItem, size: Int = HistoryThumbnails.size) -> NSImage? { cache.object(forKey: key(item, size)) }

    func load(_ item: HistoryItem, size: Int = HistoryThumbnails.size) async -> NSImage? {
        if let image = cached(item, size: size) { return image }
        let file = item.file, isMovie = item.isMovie
        // Read straight at thumbnail size: the full capture is never decoded.
        let image: CGImage? = await Task.detached(priority: .utility) {
            if isMovie {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: size, height: size)
                return try? await generator.image(at: .zero).image
            }
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let image else { return nil }
        let thumbnail = NSImage(cgImage: image, size: CGSize(width: image.width / 2, height: image.height / 2))
        cache.setObject(thumbnail, forKey: key(item, size))
        return thumbnail
    }

    func forget(_ item: HistoryItem) {
        for size in [Self.size, Self.previewSize] { cache.removeObject(forKey: key(item, size)) }
    }
}
