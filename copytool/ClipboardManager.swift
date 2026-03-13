import SwiftUI
import Combine
import Cocoa

class ClipboardManager: ObservableObject {
    @Published var history: [HistoryItem] = []
    private var clipboardObserver: Int?
    private let pasteboard = NSPasteboard.general

    // 保存最后添加的内容，避免重复添加
    private var lastText: String?
    private var lastImageData: Data?
    private var lastFileURL: URL?

    static let shared = ClipboardManager()

    private init() {
        loadHistory()
        setupClipboardObserver()
        cleanExpiredItems() // 加载时清理过期记录
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "clipboardHistory"),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            // 过滤掉过期的记录
            let settings = SettingsManager.shared
            self.history = items.filter { !settings.isItemExpired(timestamp: $0.timestamp) }
        }
    }

    // 清理过期的历史记录
    func cleanExpiredItems() {
        let settings = SettingsManager.shared
        history.removeAll { item in
            return settings.isItemExpired(timestamp: item.timestamp)
        }
        saveHistory()
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "clipboardHistory")
        }
    }

    private func setupClipboardObserver() {
        clipboardObserver = pasteboard.changeCount
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func checkClipboard() {
        guard let currentCount = clipboardObserver, pasteboard.changeCount != currentCount else {
            return
        }

        clipboardObserver = pasteboard.changeCount

        // 检查是否有文件路径（复制文件）
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            // 检查是否与上次添加的文件相同
            let fileURL = urls.first!
            if fileURL == lastFileURL {
                return
            }
            addToHistory(fileURL: fileURL)
            lastFileURL = fileURL
            lastText = nil
            lastImageData = nil
            return
        }

        if let string = pasteboard.string(forType: .string) {
            // 检查是否与上次添加的文本相同
            if string == lastText {
                return
            }
            addToHistory(text: string)
            lastText = string
            lastImageData = nil
            lastFileURL = nil
        } else if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let imageData = image.tiffRepresentation
            // 检查是否与上次添加的图片相同
            if imageData == lastImageData {
                return
            }
            addToHistory(image: image)
            lastImageData = imageData
            lastText = nil
            lastFileURL = nil
        }
    }

    private func addToHistory(text: String) {
        if history.first?.textContent == text {
            return
        }

        let item = HistoryItem(text: text)
        history.insert(item, at: 0)
        saveHistory()
    }

    private func addToHistory(image: NSImage) {
        if let firstItem = history.first, firstItem.contentType == .image,
           let firstData = firstItem.imageData, let currentData = image.tiffRepresentation,
           firstData == currentData {
            return
        }

        let item = HistoryItem(image: image)
        history.insert(item, at: 0)
        saveHistory()
    }

    private func addToHistory(fileURL: URL) {
        if let firstItem = history.first, firstItem.contentType == .file,
           let firstFileURL = firstItem.fileURL, firstFileURL == fileURL.absoluteString {
            return
        }

        let item = HistoryItem(fileURL: fileURL)
        history.insert(item, at: 0)
        saveHistory()
    }

    func copyToClipboard(item: HistoryItem) {
        // 先关闭 popover
        NSApp.sendAction(#selector(AppDelegate.togglePanel), to: nil, from: nil)

        // 延迟一小段时间后复制内容
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let strongSelf = self else { return }

            strongSelf.pasteboard.clearContents()

            if item.contentType == .text, let text = item.textContent {
                strongSelf.pasteboard.setString(text, forType: .string)
                strongSelf.lastText = text
                strongSelf.lastImageData = nil
                strongSelf.lastFileURL = nil
            } else if item.contentType == .image, let image = item.image {
                strongSelf.pasteboard.writeObjects([image])
                strongSelf.lastImageData = image.tiffRepresentation
                strongSelf.lastText = nil
                strongSelf.lastFileURL = nil
            } else if item.contentType == .file, let fileURLString = item.fileURL, let fileURL = URL(string: fileURLString) {
                strongSelf.pasteboard.writeObjects([fileURL as NSURL])
                strongSelf.lastFileURL = fileURL
                strongSelf.lastText = nil
                strongSelf.lastImageData = nil
            }
        }
    }

    func removeItem(at index: Int) {
        history.remove(at: index)
        saveHistory()
    }

    func clearAll() {
        history.removeAll()
        saveHistory()
    }
}
