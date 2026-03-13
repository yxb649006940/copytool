import SwiftUI
import Foundation

enum ContentType: String, Codable {
    case text
    case image
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let contentType: ContentType
    let textContent: String?
    let imageData: Data?
    let timestamp: Date

    init(text: String) {
        self.id = UUID()
        self.contentType = .text
        self.textContent = text
        self.imageData = nil
        self.timestamp = Date()
    }

    init(image: NSImage) {
        self.id = UUID()
        self.contentType = .image
        self.textContent = nil
        self.imageData = image.tiffRepresentation
        self.timestamp = Date()
    }

    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    var displayText: String {
        if let text = textContent {
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        }
        return "图片内容"
    }

    var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}