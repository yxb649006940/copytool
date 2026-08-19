import Foundation
import Cocoa
import CryptoKit

/// 剪贴板内容类型枚举
/// 定义了支持的三种剪贴板内容类型：文本、图片和文件
enum ContentType: String, Codable, Sendable {
    case text    // 文本类型
    case image   // 图片类型
    case file    // 文件类型
}

/// 用户创建的收藏分类；未设置分类 ID 的收藏归入“默认”。
struct FavoriteCategory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
}

/// 剪贴板历史项模型
/// 表示剪贴板历史中的单个条目，支持文本、图片和文件三种类型
struct HistoryItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID                // 唯一标识符
    let contentType: ContentType  // 内容类型
    let textContent: String?    // 文本内容
    let imageData: Data?        // 新图片在落盘前的临时数据
    let imageFileURL: String?   // 已落盘图片的本地文件 URL
    let imageDigest: String?    // 图片内容哈希，用于跨启动去重
    let fileName: String?       // 文件名（文件类型时）
    let fileURL: String?        // 文件URL（文件类型时）
    let fileURLs: [String]?     // 文件URL列表（支持一次复制多个文件）
    let timestamp: Date         // 时间戳
    var isFavorite: Bool        // 是否为收藏项
    var favoriteCategoryID: UUID? // nil 表示默认分类

    /// 自定义编码/解码键
    enum CodingKeys: String, CodingKey {
        case id
        case contentType
        case textContent
        case imageData
        case imageFileURL
        case imageDigest
        case fileName
        case fileURL
        case fileURLs
        case timestamp
        case isFavorite
        case favoriteCategoryID
    }

    /// 自定义解码器，为缺少的字段提供默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        contentType = try container.decode(ContentType.self, forKey: .contentType)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        let decodedImageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageData = decodedImageData
        imageFileURL = try container.decodeIfPresent(String.self, forKey: .imageFileURL)
        imageDigest = try container.decodeIfPresent(String.self, forKey: .imageDigest)
            ?? decodedImageData.map { Self.imageDigest(for: $0) }
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileURL = try container.decodeIfPresent(String.self, forKey: .fileURL)
        fileURLs = try container.decodeIfPresent([String].self, forKey: .fileURLs)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoriteCategoryID = try container.decodeIfPresent(UUID.self, forKey: .favoriteCategoryID)
    }

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
        self.imageFileURL = nil
        self.imageDigest = imageData.map { Self.imageDigest(for: $0) }
        self.fileName = nil
        self.fileURL = nil
        self.fileURLs = nil
        self.timestamp = timestamp
        self.isFavorite = false
        self.favoriteCategoryID = nil
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
        self.imageFileURL = nil
        self.imageDigest = imageData.map { Self.imageDigest(for: $0) }
        self.fileName = fileName
        self.fileURL = fileURL
        self.fileURLs = fileURL.map { [$0] }
        self.timestamp = timestamp
        self.isFavorite = false
        self.favoriteCategoryID = nil
    }

    /// 便捷初始化方法 - 用于文本内容
    /// - Parameter text: 文本内容
    init(text: String) {
        self.id = UUID()
        self.contentType = .text
        self.textContent = text
        self.imageData = nil
        self.imageFileURL = nil
        self.imageDigest = nil
        self.fileName = nil
        self.fileURL = nil
        self.fileURLs = nil
        self.timestamp = Date()
        self.isFavorite = false
        self.favoriteCategoryID = nil
    }

    /// 便捷初始化方法 - 用于图片内容
    /// - Parameter image: 图片对象
    init(image: NSImage) {
        self.id = UUID()
        self.contentType = .image
        self.textContent = nil
        // 使用 JPEG 压缩图片，质量设置为 0.6 以平衡质量和内存占用
        let encodedData: Data?
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
            encodedData = jpegData
        } else {
            encodedData = image.tiffRepresentation
        }
        self.imageData = encodedData
        self.imageFileURL = nil
        self.imageDigest = encodedData.map { Self.imageDigest(for: $0) }
        self.fileName = nil
        self.fileURL = nil
        self.fileURLs = nil
        self.timestamp = Date()
        self.isFavorite = false
        self.favoriteCategoryID = nil
    }

    /// 便捷初始化方法 - 用于文件内容
    /// - Parameter fileURL: 文件URL
    init(fileURL: URL) {
        self.id = UUID()
        self.contentType = .file
        self.textContent = nil
        self.imageData = nil
        self.imageFileURL = nil
        self.imageDigest = nil
        self.fileName = fileURL.lastPathComponent
        self.fileURL = fileURL.absoluteString
        self.fileURLs = [fileURL.absoluteString]
        self.timestamp = Date()
        self.isFavorite = false
        self.favoriteCategoryID = nil
    }

    /// 便捷初始化方法 - 用于多文件内容
    init?(fileURLs: [URL]) {
        guard let firstFileURL = fileURLs.first else { return nil }
        self.id = UUID()
        self.contentType = .file
        self.textContent = nil
        self.imageData = nil
        self.imageFileURL = nil
        self.imageDigest = nil
        self.fileName = fileURLs.count == 1 ? firstFileURL.lastPathComponent : "\(fileURLs.count) 个文件"
        self.fileURL = firstFileURL.absoluteString
        self.fileURLs = fileURLs.map(\.absoluteString)
        self.timestamp = Date()
        self.isFavorite = false
        self.favoriteCategoryID = nil
    }

    /// 持久化层恢复历史项时使用的完整初始化方法
    nonisolated init(
        id: UUID,
        contentType: ContentType,
        textContent: String?,
        imageData: Data?,
        imageFileURL: String?,
        imageDigest: String?,
        fileName: String?,
        fileURL: String?,
        fileURLs: [String]?,
        timestamp: Date,
        isFavorite: Bool,
        favoriteCategoryID: UUID? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.imageFileURL = imageFileURL
        self.imageDigest = imageDigest ?? imageData.map { Self.imageDigest(for: $0) }
        self.fileName = fileName
        self.fileURL = fileURL
        self.fileURLs = fileURLs ?? fileURL.map { [$0] }
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.favoriteCategoryID = isFavorite ? favoriteCategoryID : nil
    }

    /// 获取图片对象
    /// - Returns: 可选的图片对象
    var image: NSImage? {
        if let data = imageData {
            return NSImage(data: data)
        }
        guard let imageFileURL,
              let fileURL = URL(string: imageFileURL) else { return nil }
        guard let storedData = try? Data(contentsOf: fileURL) else { return nil }
        let imageData = (try? HistoryCrypto.shared.decrypt(storedData)) ?? storedData
        return NSImage(data: imageData)
    }

    /// 读取预览所需的原始图片数据。调用方可在后台任务中执行，避免阻塞列表滚动。
    nonisolated func previewImageData() -> Data? {
        if contentType == .image {
            if let imageData {
                return imageData
            }
            guard let imageFileURL,
                  let storedURL = URL(string: imageFileURL),
                  let storedData = try? Data(contentsOf: storedURL) else {
                return nil
            }
            return (try? HistoryCrypto.shared.decrypt(storedData)) ?? storedData
        }

        guard contentType == .file,
              let fileURL = resolvedFileURLs.first else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    nonisolated static func imageDigest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 返回当前历史项中所有有效的文件 URL。
    nonisolated var resolvedFileURLs: [URL] {
        let values = fileURLs ?? fileURL.map { [$0] } ?? []
        return values.compactMap(URL.init(string:))
    }

    /// 搜索使用完整内容，不受列表摘要的 50 字符限制。
    nonisolated var searchableText: String {
        [textContent, fileName, resolvedFileURLs.map(\.path).joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " ")
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

}
