import SwiftUI
import Cocoa

/// 图片缓存管理器
/// 用于缓存图片对象，避免重复加载，提升性能
class ImageCache {
    static let shared = ImageCache()  // 单例实例

    private let cache = NSCache<NSString, NSImage>()  // 内部缓存对象

    private init() {
        cache.countLimit = 10  // 限制最多缓存10张图片
    }

    /// 设置图片到缓存
    /// - Parameters:
    ///   - image: 要缓存的图片
    ///   - key: 缓存键
    func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// 从缓存获取图片
    /// - Parameter key: 缓存键
    /// - Returns: 可选的图片对象
    func image(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }

    /// 从缓存移除指定图片
    /// - Parameter key: 缓存键
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// 清空所有缓存
    func clear() {
        cache.removeAllObjects()
    }
}