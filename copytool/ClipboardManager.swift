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

        // 优化判断顺序：先检查是否是图片
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let imageData = image.tiffRepresentation
            if imageData != lastImageData {
                print("识别到图片类型")
                addToHistory(image: image)
                lastImageData = imageData
                lastText = nil
                lastFileURL = nil
                return
            }
        }

        // 再检查是否是文本
        if let string = pasteboard.string(forType: .string) {
            if string != lastText {
                print("识别到文本类型")
                addToHistory(text: string)
                lastText = string
                lastImageData = nil
                lastFileURL = nil
                return
            }
        }

        // 最后检查是否是文件
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            let fileURL = urls.first!
            if fileURL != lastFileURL {
                // 检查这个URL是否可能是图片文件
                let isImageFile = self.isImageFile(url: fileURL)
                if isImageFile {
                    // 如果是图片文件，尝试读取其内容作为图片
                    if let image = NSImage(contentsOf: fileURL) {
                        print("识别到图片文件类型")
                        addToHistory(image: image)
                        lastImageData = image.tiffRepresentation
                        lastText = nil
                        lastFileURL = nil
                        return
                    }
                }
                print("识别到文件类型")
                addToHistory(fileURL: fileURL)
                lastFileURL = fileURL
                lastText = nil
                lastImageData = nil
                return
            }
        }
    }

    private func isImageFile(url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"]
        let fileExtension = url.pathExtension.lowercased()
        return imageExtensions.contains(fileExtension)
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
