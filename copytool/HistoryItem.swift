import SwiftUI
import Foundation

enum ContentType: String, Codable {
    case text
    case image
    case file
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let contentType: ContentType
    let textContent: String?
    let imageData: Data?
    let fileName: String?
    let fileURL: String?
    let timestamp: Date

    // 完整初始化方法
    init(id: UUID, contentType: ContentType, textContent: String?, imageData: Data?, timestamp: Date) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = timestamp
    }

    // 完整初始化方法（带文件名）
    init(id: UUID, contentType: ContentType, textContent: String?, imageData: Data?, fileName: String?, fileURL: String?, timestamp: Date) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.fileName = fileName
        self.fileURL = fileURL
        self.timestamp = timestamp
    }

    // 便捷初始化方法 - 用于文本内容
    init(text: String) {
        self.id = UUID()
        self.contentType = .text
        self.textContent = text
        self.imageData = nil
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = Date()
    }

    // 便捷初始化方法 - 用于图片内容
    init(image: NSImage) {
        self.id = UUID()
        self.contentType = .image
        self.textContent = nil
        self.imageData = HistoryItem.compressImage(image) // 使用压缩后的图片数据
        self.fileName = nil
        self.fileURL = nil
        self.timestamp = Date()
    }

    // 便捷初始化方法 - 用于文件内容
    init(fileURL: URL) {
        self.id = UUID()
        self.contentType = .file
        self.textContent = nil
        self.imageData = nil
        self.fileName = fileURL.lastPathComponent
        self.fileURL = fileURL.absoluteString
        self.timestamp = Date()
    }

    // 压缩图片以减少存储大小
    private static func compressImage(_ image: NSImage) -> Data? {
        // 尝试转换为 JPEG 格式，压缩质量 0.8
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            if let jpegData = jpegData {
                // 如果压缩后的尺寸仍然太大，进一步压缩
                if jpegData.count > 100 * 1024 { // 超过 100KB 进一步压缩
                    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
                }
                return jpegData
            }
        }
        return nil
    }

    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    var displayText: String {
        if let text = textContent {
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        } else if let fileName = fileName {
            return fileName
        }
        return "图片内容"
    }

    var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}