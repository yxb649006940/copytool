import SwiftUI
import Cocoa

/// 预览窗口管理器
/// 负责管理剪贴板内容的预览窗口显示和隐藏
class PreviewWindowManager {
    static let shared = PreviewWindowManager()  // 单例实例

    private var previewWindow: NSWindow?         // 预览窗口
    private var hideTimer: Timer?                // 隐藏定时器
    private var showTask: DispatchWorkItem?      // 显示任务
    private var currentItemId: UUID?             // 当前正在显示的项目ID

    private init() {}

    /// 显示预览窗口
    /// - Parameter item: 要预览的历史项目
    func showPreview(for item: HistoryItem) {
        // 取消正在进行的显示任务
        showTask?.cancel()

        // 检查是否是图片或文本类型，或者是图片格式的文件
        let shouldShowPreview = item.contentType == .text ||
                                 item.contentType == .image ||
                                 isImageFileItem(item)

        guard shouldShowPreview else {
            hidePreview()
            return
        }

        // 记录当前要显示的项目ID
        currentItemId = item.id

        hideTimer?.invalidate()
        hideTimer = nil

        // 创建新的显示任务
        let task = DispatchWorkItem { [weak self] in
            // 检查任务是否已取消或当前要显示的项目已更改
            guard let self = self, self.currentItemId == item.id else {
                return
            }
            self.createOrUpdatePreviewWindow(with: item)
        }

        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
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
        // 取消正在进行的显示任务
        showTask?.cancel()
        showTask = nil

        hideTimer?.invalidate()
        hideTimer = nil
        currentItemId = nil

        DispatchQueue.main.async { [weak self] in
            self?.previewWindow?.orderOut(nil)
        }
    }

    /// 创建或更新预览窗口
    /// - Parameter item: 要预览的历史项目
    private func createOrUpdatePreviewWindow(with item: HistoryItem) {
        if let existingWindow = previewWindow, existingWindow.isVisible {
            if let hostingController = existingWindow.contentViewController as? NSHostingController<ContentPreviewView> {
                hostingController.rootView = ContentPreviewView(item: item)
            }
            positionWindow(existingWindow)
            existingWindow.orderFront(nil)
            return
        }

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.positionWindow(window)
            window.orderFront(nil)
        }
    }

    /// 定位预览窗口
    /// - Parameter window: 要定位的窗口
    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let previewSize = window.frame.size

        // 找到主窗口（第一个可见窗口）
        guard let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 != window }) else {
            window.center()
            return
        }

        let mainFrame = mainWindow.frame
        let mainScreen = mainWindow.screen ?? NSScreen.main!
        let safeRect = mainScreen.visibleFrame

        // X 坐标：主窗口左边缘左侧 190 像素，确保完全不遮挡主窗口
        var finalX = mainFrame.minX - previewSize.width - 190

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

/// 内容预览视图
/// 用于显示剪贴板内容的预览，支持文本和图片类型
struct ContentPreviewView: View {
    let item: HistoryItem  // 要预览的项目

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

    /// 获取图片对象
    /// - Returns: 可选的图片对象
    private var image: NSImage? {
        if item.contentType == .image {
            return item.image
        } else if isImageFileItem(), let fileURLString = item.fileURL, let fileURL = URL(string: fileURLString) {
            return NSImage(contentsOf: fileURL)
        }
        return nil
    }

    /// 图片预览视图
    @ViewBuilder
    private var imagePreview: some View {
        if let image = self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(8)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if let text = item.textContent {
                ScrollView {
                    Text(text)
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
