import SwiftUI
import Cocoa

/// 预览窗口管理器
/// 负责管理剪贴板内容的预览窗口显示和隐藏
class PreviewWindowManager {
    static let shared = PreviewWindowManager()  // 单例实例

    private var previewWindow: NSWindow?         // 预览窗口
    private var showTask: DispatchWorkItem?      // 显示任务
    private var currentItemId: UUID?             // 当前正在显示的项目ID

    private init() {}

    /// 显示预览窗口
    /// - Parameter item: 要预览的历史项目
    func showPreview(for item: HistoryItem) {
        // 检查主窗口是否可见，如果不可见则不显示预览
        guard let mainWindow = AppDelegate.shared?.mainWindow, mainWindow.isVisible else {
            hidePreview()
            return
        }

        // 立即取消所有正在进行的任务
        showTask?.cancel()
        showTask = nil

        // 文本、图片以及单张图片文件可显示预览。
        let shouldShowPreview = item.contentType == .text ||
                                 item.contentType == .image ||
                                 isImageFileItem(item)

        guard shouldShowPreview else {
            hidePreview()
            return
        }

        // 记录当前要显示的项目ID
        currentItemId = item.id

        // 创建新的显示任务
        let task = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.currentItemId == item.id,
                  let mainWindow = AppDelegate.shared?.mainWindow,
                  mainWindow.isVisible else {
                return
            }
            self.createOrUpdatePreviewWindow(with: item)
        }

        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    /// 检查是否是图片文件类型
    /// - Parameter item: 历史项目
    /// - Returns: 是否是图片文件类型
    private func isImageFileItem(_ item: HistoryItem) -> Bool {
        guard item.contentType == .file, let fileName = item.fileName else {
            return false
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        return imageExtensions.contains(fileExtension)
    }

    /// 隐藏预览窗口
    func hidePreview() {
        showTask?.cancel()
        showTask = nil
        currentItemId = nil
        // 保留窗口和 HostingController，后续悬停时直接复用。
        previewWindow?.orderOut(nil)
    }

    /// 创建或更新预览窗口
    /// - Parameter item: 要预览的历史项目
    private func createOrUpdatePreviewWindow(with item: HistoryItem) {
        // 确保只存在一个预览窗口
        if let existingWindow = previewWindow {
            // 无论是否可见，先更新内容
            if let hostingController = existingWindow.contentViewController as? NSHostingController<ContentPreviewView> {
                hostingController.rootView = ContentPreviewView(item: item)
            }
            positionWindow(existingWindow)
            existingWindow.orderFront(nil)
            return
        }

        // 创建新的预览窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = ContentPreviewView(item: item)
        let hostingController = NSHostingController(rootView: contentView)
        window.contentViewController = hostingController

        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true

        previewWindow = window
        positionWindow(window)
        window.orderFront(nil)
    }

    /// 定位预览窗口
    /// - Parameter window: 要定位的窗口
    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let previewSize = window.frame.size

        // 找到主窗口（通过 AppDelegate 获取）
        guard let mainWindow = AppDelegate.shared?.mainWindow, mainWindow.isVisible else {
            window.center()
            return
        }

        let mainFrame = mainWindow.frame
        guard let mainScreen = mainWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let safeRect = mainScreen.visibleFrame

        // X 坐标：主窗口左边缘左侧 10 像素，确保不遮挡主窗口
        var finalX = mainFrame.minX - previewSize.width - 10

        // 如果左侧空间不够，显示在右侧
        if finalX < safeRect.minX {
            finalX = mainFrame.maxX + 10
        }

        // Y 坐标：鼠标位置垂直居中于预览窗口
        var finalY = mouseLocation.y - previewSize.height / 2

        // 边界检查
        if finalX < safeRect.minX {
            finalX = safeRect.minX + 20
        }

        if finalY < safeRect.minY {
            finalY = safeRect.minY + 20
        }

        if finalX + previewSize.width > safeRect.maxX {
            finalX = safeRect.maxX - previewSize.width - 20
        }

        if finalY + previewSize.height > safeRect.maxY {
            finalY = safeRect.maxY - previewSize.height - 20
        }

        window.setFrameOrigin(NSPoint(x: finalX, y: finalY))
    }
}

/// 仅在主线程访问的预览图片缓存，限制数量和总内存，避免重复读盘与解密。
private final class PreviewImageCache {
    static let shared = PreviewImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 30
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// 内容预览视图
/// 用于显示剪贴板内容的预览，支持文本和图片类型
struct ContentPreviewView: View {
    let item: HistoryItem  // 要预览的项目
    @State private var loadedImage: NSImage?
    @State private var isLoadingImage = false

    var body: some View {
        if item.contentType == .image || isImageFileItem() {
            // 图片类型或图片格式文件：使用与文本预览相同的窗口样式
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "photo")
                        .foregroundColor(.green)
                    Text("图片预览")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                imagePreview
                    .padding(16)
            }
            .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)
            .frame(minHeight: 200, idealHeight: 300, maxHeight: 400)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .shadow(radius: 10, y: 5)
            .task(id: item.id) {
                await loadPreviewImage()
            }
        } else {
            // 文本类型：保留原来的样式
            textPreview
        }
    }

    /// 检查是否是图片文件类型
    /// - Returns: 是否是图片文件类型
    private func isImageFileItem() -> Bool {
        guard item.contentType == .file, let fileName = item.fileName else {
            return false
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        return imageExtensions.contains(fileExtension)
    }

    private var imageCacheKey: String {
        item.imageDigest ?? item.imageFileURL ?? item.fileURL ?? item.id.uuidString
    }

    private func loadPreviewImage() async {
        loadedImage = nil

        if let cachedImage = PreviewImageCache.shared.image(for: imageCacheKey) {
            loadedImage = cachedImage
            return
        }

        isLoadingImage = true
        let previewItem = item
        let data = await Task.detached(priority: .userInitiated) {
            previewItem.previewImageData()
        }.value

        guard !Task.isCancelled else { return }
        isLoadingImage = false
        guard let data, let image = NSImage(data: data) else { return }
        PreviewImageCache.shared.insert(image, for: imageCacheKey, cost: data.count)
        loadedImage = image
    }

    /// 图片预览视图
    @ViewBuilder
    private var imagePreview: some View {
        if let loadedImage {
            Image(nsImage: loadedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(8)
        } else if isLoadingImage {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: 250)
        } else {
            Text("图片无法加载")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
        }
    }

    /// 文本预览视图
    @ViewBuilder
    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                Text("文本预览")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                // 显示文本长度信息
                if let text = item.textContent {
                    Text("\(text.count) 字符")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if let text = item.textContent {
                ScrollView {
                    // 对于非常大的文本，只显示一部分并提示用户
                    let displayText = text.count > 5000 ? String(text.prefix(5000)) + "\n\n... (文本过长，仅显示前 5000 字符，点击条目可复制完整内容)" : text
                    Text(displayText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxHeight: 250)
            }
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
        .frame(minHeight: 200, idealHeight: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .shadow(radius: 10, y: 5)
    }
}
