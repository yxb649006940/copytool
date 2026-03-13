import SwiftUI
import Combine
import Cocoa

class ClipboardManager: ObservableObject {
    @Published var history: [HistoryItem] = []
    private let maxHistoryCount = 10
    private var clipboardObserver: Int?
    private let pasteboard = NSPasteboard.general

    // 保存最后添加的内容，避免重复添加
    private var lastText: String?
    private var lastImageData: Data?

    static let shared = ClipboardManager()

    private init() {
        loadHistory()
        setupClipboardObserver()
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "clipboardHistory"),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = items
        }
    }

    private func saveHistory() {
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

        if let string = pasteboard.string(forType: .string) {
            // 检查是否与上次添加的文本相同
            if string == lastText {
                return
            }
            addToHistory(text: string)
            lastText = string
            lastImageData = nil
        } else if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let imageData = image.tiffRepresentation
            // 检查是否与上次添加的图片相同
            if imageData == lastImageData {
                return
            }
            addToHistory(image: image)
            lastImageData = imageData
            lastText = nil
        }
    }

    private func addToHistory(text: String) {
        if history.first?.textContent == text {
            return
        }

        let item = HistoryItem(text: text)
        history.insert(item, at: 0)

        if history.count > maxHistoryCount {
            history.removeLast()
        }

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

        if history.count > maxHistoryCount {
            history.removeLast()
        }

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
            } else if item.contentType == .image, let image = item.image {
                strongSelf.pasteboard.writeObjects([image])
                strongSelf.lastImageData = image.tiffRepresentation
                strongSelf.lastText = nil
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