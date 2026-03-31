import SwiftUI
import Combine
import Cocoa

/// 剪贴板管理器
/// 负责监听剪贴板变化、管理剪贴板历史记录
class ClipboardManager: ObservableObject {
    @Published var history: [HistoryItem] = []  // 剪贴板历史记录
    @Published var favorites: [HistoryItem] = []  // 收藏列表
    private var clipboardObserver: Int?          // 剪贴板变化计数器
    private let pasteboard = NSPasteboard.general  // 系统剪贴板

    // 保存最后添加的内容，避免重复添加
    private var lastText: String?
    private var lastImageData: Data?
    private var lastFileURL: URL?

    static let shared = ClipboardManager()  // 单例实例

    private init() {
        loadHistory()
        setupClipboardObserver()
        setupExpirationTimer() // 设置定期清理定时器
        cleanExpiredItems() // 加载时清理过期记录
    }

    /// 设置定期清理过期记录的定时器
    private func setupExpirationTimer() {
        // 每小时清理一次过期记录
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanExpiredItems()
        }
    }

    /// 加载历史记录
    private func loadHistory() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var loadedItems: [HistoryItem]?

            // 先尝试从文件加载（更好的性能）
            do {
                let fileManager = FileManager.default
                let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDirectory = appSupportDirectory.appendingPathComponent("com.yxb10.copytool")
                let historyFileURL = appDirectory.appendingPathComponent("clipboardHistory.json")

                if fileManager.fileExists(atPath: historyFileURL.path) {
                    let data = try Data(contentsOf: historyFileURL)
                    loadedItems = try JSONDecoder().decode([HistoryItem].self, from: data)
                }
            } catch {
                print("从文件加载历史记录失败: \(error)")
            }

            // 如果文件加载失败，使用UserDefaults
            if loadedItems == nil {
                if let data = UserDefaults.standard.data(forKey: "clipboardHistory"),
                   let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
                    loadedItems = items
                }
            }

            // 加载收藏列表
            var favoriteItems: [HistoryItem] = []
            if let favoriteData = UserDefaults.standard.data(forKey: "favoriteHistory"),
               let favorites = try? JSONDecoder().decode([HistoryItem].self, from: favoriteData) {
                favoriteItems = favorites
            }

            // 在主线程更新UI
            DispatchQueue.main.async {
                if let items = loadedItems {
                    // 过滤掉过期的记录
                    let settings = SettingsManager.shared
                    var filteredItems = items.filter { !settings.isItemExpired(timestamp: $0.timestamp) }

                    // 确保历史记录中的 isFavorite 属性与收藏列表同步
                    filteredItems = filteredItems.map { item in
                        var mutableItem = item
                        // 检查该项目是否在收藏列表中
                        mutableItem.isFavorite = favoriteItems.contains { $0.id == item.id }
                        return mutableItem
                    }

                    self.history = filteredItems
                }

                self.favorites = favoriteItems
            }
        }
    }

    /// 清理过期的历史记录
    func cleanExpiredItems() {
        let settings = SettingsManager.shared
        history.removeAll { item in
            // 如果是收藏项，保留；否则检查是否过期
            if item.isFavorite {
                return false
            }
            return settings.isItemExpired(timestamp: item.timestamp)
        }
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    /// 保存历史记录到本地存储（异步）
    func saveHistory() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            if let data = try? JSONEncoder().encode(self.history) {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(data, forKey: "clipboardHistory")
                }
            }

            // 保存收藏列表
            if let favoriteData = try? JSONEncoder().encode(self.favorites) {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(favoriteData, forKey: "favoriteHistory")
                }
            }
        }
    }

    /// 收藏/取消收藏方法
    func toggleFavorite(item: HistoryItem) {
        // 如果是收藏项，取消收藏
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            // 否则，添加到收藏
            var itemToAdd = item
            itemToAdd.isFavorite = true
            favorites.insert(itemToAdd, at: 0)
        }

        // 在历史记录中也更新状态
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isFavorite = !item.isFavorite
        }

        saveHistory()
    }

    /// 设置剪贴板监听器
    private func setupClipboardObserver() {
        clipboardObserver = pasteboard.changeCount
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    /// 检查剪贴板内容变化
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

        var item = HistoryItem(text: text)

        // 检查是否已在收藏中，保持同步
        if favorites.first(where: { $0.textContent == text && $0.contentType == .text }) != nil {
            item.isFavorite = true
        }

        history.insert(item, at: 0)
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    private func addToHistory(image: NSImage) {
        if let firstItem = history.first, firstItem.contentType == .image,
           let firstData = firstItem.imageData, let currentData = image.tiffRepresentation,
           firstData == currentData {
            return
        }

        var item = HistoryItem(image: image)

        // 检查是否已在收藏中，保持同步
        if let currentImageData = image.tiffRepresentation,
           favorites.first(where: { $0.contentType == .image && $0.imageData == currentImageData }) != nil {
            item.isFavorite = true
        }

        history.insert(item, at: 0)
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    private func addToHistory(fileURL: URL) {
        if let firstItem = history.first, firstItem.contentType == .file,
           let firstFileURL = firstItem.fileURL, firstFileURL == fileURL.absoluteString {
            return
        }

        var item = HistoryItem(fileURL: fileURL)

        // 检查是否已在收藏中，保持同步
        if favorites.first(where: { $0.fileURL == fileURL.absoluteString && $0.contentType == .file }) != nil {
            item.isFavorite = true
        }

        history.insert(item, at: 0)
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    func copyToClipboard(item: HistoryItem) {
        // 立即隐藏预览窗口
        PreviewWindowManager.shared.hidePreview()

        // 直接复制内容，不关闭窗口
        DispatchQueue.main.async { [weak self] in
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
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    func clearAll() {
        history.removeAll()
        // 使用异步保存避免阻塞主线程
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }
}
