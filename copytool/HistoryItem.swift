import SwiftUI
import Foundation

/// 剪贴板内容类型枚举
/// 定义了支持的三种剪贴板内容类型：文本、图片和文件
enum ContentType: String, Codable {
    case text    // 文本类型
    case image   // 图片类型
    case file    // 文件类型
}

/// 剪贴板历史项模型
/// 表示剪贴板历史中的单个条目，支持文本、图片和文件三种类型
struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID                // 唯一标识符
    let contentType: ContentType  // 内容类型
    let textContent: String?    // 文本内容
    let imageData: Data?        // 图片数据
    let fileName: String?       // 文件名（文件类型时）
    let fileURL: String?        // 文件URL（文件类型时）
    let timestamp: Date         // 时间戳
    var isFavorite: Bool        // 是否为收藏项

    /// 完整初始化方法
    /// - Parameters:
    ///   - id: 唯一标识符
    ///   - contentType: 内容类型
    ///   - textContent: 文本内容
    ///   - imageData: 图片数据
    ///   - timestamp: 时间戳
    init(id: UUID, contentType: ContentType, textContent: String?, imageData: Data?, timestamp: Date) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = timestamp
        self.isFavorite = false
    }

    /// 完整初始化方法（带文件名）
    /// - Parameters:
    ///   - id: 唯一标识符
    ///   - contentType: 内容类型
    ///   - textContent: 文本内容
    ///   - imageData: 图片数据
    ///   - fileName: 文件名
    ///   - fileURL: 文件URL
    ///   - timestamp: 时间戳
    init(id: UUID, contentType: ContentType, textContent: String?, imageData: Data?, fileName: String?, fileURL: String?, timestamp: Date) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.fileName = fileName
        self.fileURL = fileURL
        self.timestamp = timestamp
        self.isFavorite = false
    }

    /// 便捷初始化方法 - 用于文本内容
    /// - Parameter text: 文本内容
    init(text: String) {
        self.id = UUID()
        self.contentType = .text
        self.textContent = text
        self.imageData = nil
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = Date()
        self.isFavorite = false
    }

    /// 便捷初始化方法 - 用于图片内容
    /// - Parameter image: 图片对象
    init(image: NSImage) {
        self.id = UUID()
        self.contentType = .image
        self.textContent = nil
        self.imageData = image.tiffRepresentation // 直接保存原始图片数据，不压缩
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = Date()
        self.isFavorite = false
    }

    /// 便捷初始化方法 - 用于文件内容
    /// - Parameter fileURL: 文件URL
    init(fileURL: URL) {
        self.id = UUID()
        self.contentType = .file
        self.textContent = nil
        self.imageData = nil
        self.fileName = fileURL.lastPathComponent
        self.fileURL = fileURL.absoluteString
        self.timestamp = Date()
        self.isFavorite = false
    }

    /// 获取图片对象
    /// - Returns: 可选的图片对象
    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    /// 获取用于显示的文本
    /// - Returns: 文本内容的截断版本（最多50字符）
    var displayText: String {
        if let text = textContent {
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        } else if let fileName = fileName {
            return fileName
        }
        return "图片内容"
    }

    /// 获取相对时间字符串
    /// - Returns: 相对于当前时间的格式化字符串（如"2分钟前"）
    var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
