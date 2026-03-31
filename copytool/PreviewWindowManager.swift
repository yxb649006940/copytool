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
    private var isHiding: Bool = false           // 是否正在隐藏窗口的标志

    private init() {}

    /// 显示预览窗口
    /// - Parameter item: 要预览的历史项目
    func showPreview(for item: HistoryItem) {
        // 检查主窗口是否可见，如果不可见则不显示预览
        guard let mainWindow = AppDelegate.shared.mainWindow, mainWindow.isVisible else {
            hidePreview()
            return
        }

        // 立即取消所有正在进行的任务
        showTask?.cancel()
        showTask = nil
        hideTimer?.invalidate()
        hideTimer = nil

        // 重置隐藏状态标志
        isHiding = false

        // 检查是否是图片或文本类型，但文件类型（包括图片文件）不显示预览
        let shouldShowPreview = item.contentType == .text ||
                                 item.contentType == .image

        guard shouldShowPreview else {
            hidePreview()
            return
        }

        // 记录当前要显示的项目ID
        currentItemId = item.id

        // 创建新的显示任务
        let task = DispatchWorkItem { [weak self] in
            guard let self = self,
                  !self.isHiding,  // 确保不在隐藏过程中
                  self.currentItemId == item.id,
                  let mainWindow = AppDelegate.shared.mainWindow,
                  mainWindow.isVisible else {
                return
            }
            self.createOrUpdatePreviewWindow(with: item)
        }

        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
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
        // 设置正在隐藏的标志
        isHiding = true

        // 取消正在进行的显示任务
        showTask?.cancel()
        showTask = nil

        hideTimer?.invalidate()
        hideTimer = nil
        currentItemId = nil

        // 强制在主线程执行隐藏操作，确保同步性
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 先 orderOut，再 close，最后置为 nil，确保完全清理
            self.previewWindow?.orderOut(nil)
            self.previewWindow?.close()
            self.previewWindow?.contentViewController = nil
            self.previewWindow = nil

            // 延迟重置隐藏状态标志，防止竞态条件
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.isHiding = false
            }
        }
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

        // 找到主窗口（通过 AppDelegate 获取）
        guard let mainWindow = AppDelegate.shared.mainWindow, mainWindow.isVisible else {
            window.center()
            return
        }

        let mainFrame = mainWindow.frame
        let mainScreen = mainWindow.screen ?? NSScreen.main!
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
