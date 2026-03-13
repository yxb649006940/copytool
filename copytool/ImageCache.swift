import SwiftUI
import Cocoa

class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 10
    }

    func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func image(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}