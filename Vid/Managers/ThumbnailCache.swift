import UIKit
import AVFoundation

class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?

    private init() {
        // Configure cache
        cache.countLimit = 100 // Keep up to 100 thumbnails in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        // Setup disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachesDir.appendingPathComponent("Thumbnails")
            if let cacheDir = cacheDirectory, !fileManager.fileExists(atPath: cacheDir.path) {
                try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
        }
    }

    func thumbnail(for videoURL: URL) -> UIImage? {
        let key = cacheKey(for: videoURL)

        // Check memory cache first
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            cache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        return nil
    }

    func setThumbnail(_ image: UIImage, for videoURL: URL) {
        let key = cacheKey(for: videoURL)

        // Save to memory cache
        cache.setObject(image, forKey: key as NSString)

        // Save to disk cache
        saveToDisk(image: image, key: key)
    }

    private func cacheKey(for url: URL) -> String {
        return url.lastPathComponent
    }

    private func loadFromDisk(key: String) -> UIImage? {
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(key).appendingPathExtension("jpg")

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func saveToDisk(image: UIImage, key: String) {
        guard let cacheDir = cacheDirectory,
              let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        let fileURL = cacheDir.appendingPathComponent(key).appendingPathExtension("jpg")
        try? data.write(to: fileURL)
    }

    func clearCache() {
        cache.removeAllObjects()
        if let cacheDir = cacheDirectory {
            try? fileManager.removeItem(at: cacheDir)
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
}
