import SwiftUI
import Cocoa

/// 应用程序代理类
/// 负责应用程序的生命周期管理、菜单栏设置、快捷键监听等
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusItem: NSStatusItem?          // 菜单栏状态项
    private(set) var mainWindow: NSWindow? // 主窗口（替代 popover）
    var eventMonitors: [Any] = []         // 事件监听器数组

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusBar()
        setupMainWindow()
        requestAccessibilityPermission()
        setupGlobalKeyboardMonitor()
        checkAndCleanupLargeHistory()

        // 监听设置更改通知
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: NSNotification.Name("SettingsChanged"), object: nil)
        // 监听打开设置窗口的通知
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromPopover), name: NSNotification.Name("OpenSettings"), object: nil)
        // 监听窗口置顶设置变化
        NotificationCenter.default.addObserver(self, selector: #selector(windowAlwaysOnTopChanged), name: NSNotification.Name("WindowAlwaysOnTopChanged"), object: nil)
    }

    /// 检查并清理过大的历史记录
    private func checkAndCleanupLargeHistory() {
        if let data = UserDefaults.standard.data(forKey: "clipboardHistory") {
            if data.count >= 4 * 1024 * 1024 { // >=4MB
                print("Warning: Clipboard history data too large (\(data.count) bytes), clearing all history")
                UserDefaults.standard.removeObject(forKey: "clipboardHistory")
            }
        }
    }

    /// 设置菜单栏
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // 尝试使用自定义图标，如果失败则回退到系统图标
            if let customImage = NSImage(named: "MenuBarIcon") {
                customImage.isTemplate = true  // 模板模式，自动适配深色/浅色模式
                customImage.size = NSSize(width: 18, height: 18)
                button.image = customImage
            } else {
                button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板历史")
            }
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// 处理菜单栏点击事件
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
                showMenu()
            } else {
                togglePanel()
            }
        }
    }

    /// 显示右键菜单
    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "显示历史记录", action: #selector(togglePanel), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "设置", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate), keyEquivalent: "q")

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    /// 设置主窗口（独立窗口）
    private func setupMainWindow() {
        // 从 UserDefaults 恢复窗口大小，如果没有保存则使用默认大小
        let defaultSize = NSSize(width: 400, height: 500)
        let savedWidth = UserDefaults.standard.double(forKey: "mainWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "mainWindowHeight")
        let windowSize = savedWidth > 0 && savedHeight > 0 ? NSSize(width: savedWidth, height: savedHeight) : defaultSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "剪贴板历史"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 400)
        window.contentViewController = NSHostingController(rootView: ContentView())

        // 监听窗口大小变化以保存到 UserDefaults
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove), name: NSWindow.didMoveNotification, object: window)

        // 默认窗口层级
        updateWindowLevel()

        mainWindow = window
    }

    /// 窗口大小变化时保存到 UserDefaults
    @objc private func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let size = window.frame.size
        UserDefaults.standard.set(size.width, forKey: "mainWindowWidth")
        UserDefaults.standard.set(size.height, forKey: "mainWindowHeight")
    }

    /// 窗口位置变化时保存到 UserDefaults
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let origin = window.frame.origin
        UserDefaults.standard.set(origin.x, forKey: "mainWindowX")
        UserDefaults.standard.set(origin.y, forKey: "mainWindowY")
    }

    /// 更新窗口层级（置顶/普通）
    func updateWindowLevel() {
        if SettingsManager.shared.windowAlwaysOnTop {
            mainWindow?.level = .floating
        } else {
            mainWindow?.level = .normal
        }
    }

    /// 请求辅助功能权限
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        print("辅助功能权限: \(accessibilityEnabled ? "已授予" : "未授予")")

        // 如果权限未授予，设置定时检查
        if !accessibilityEnabled {
            setupPermissionCheckTimer()
        }
    }

    /// 设置权限检查定时器
    private func setupPermissionCheckTimer() {
        // 每2秒检查一次权限
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let strongSelf = self else {
                timer.invalidate()
                return
            }

            let accessibilityEnabled = AXIsProcessTrusted()
            print("检查辅助功能权限: \(accessibilityEnabled ? "已授予" : "未授予")")

            if accessibilityEnabled {
                // 权限已授予，停止定时器并重新设置键盘监控器
                timer.invalidate()
                print("权限已授予，重新设置键盘监控器")
                strongSelf.setupGlobalKeyboardMonitor()
            }
        }
    }

    /// 设置全局键盘监听器
    func setupGlobalKeyboardMonitor() {
        // 移除旧的监听
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()

        // 全局事件监听（应用未聚焦时）
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event)
        }) {
            eventMonitors.append(globalMonitor)
        }

        // 本地事件监听（应用聚焦时）
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }) {
            eventMonitors.append(localMonitor)
        }
    }

    /// 处理键盘按下事件
    private func handleKeyDown(_ event: NSEvent) {
        let settings = SettingsManager.shared
        let hotkey = settings.hotkey

        // 检查是否匹配自定义快捷键
        let isMatchingKeyCode = event.keyCode == hotkey.keyCode
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isMatchingModifiers = eventModifiers == hotkey.modifierFlags

        if isMatchingKeyCode && isMatchingModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.togglePanel()
            }
        }
    }

    /// 显示设置窗口
    @objc private func showSettings() {
        DispatchQueue.main.async {
            // 先关闭主窗口
            self.mainWindow?.orderOut(nil)

            // 检查是否已有设置窗口打开
            for window in NSApp.windows where window.title == "设置" && window.isVisible {
                window.level = .modalPanel
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            // 初始化窗口时添加 resizable 样式，让内容更好地适应
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            settingsWindow.minSize = NSSize(width: 400, height: 550)
            settingsWindow.maxSize = NSSize(width: 500, height: 620)
            settingsWindow.center()
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.level = .modalPanel

            let settingsView = SettingsView(onClose: {
                settingsWindow.close()
            })
            settingsWindow.contentViewController = NSHostingController(rootView: settingsView)
            settingsWindow.title = "设置"
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 切换主窗口的显示/隐藏
    @objc func togglePanel() {
        guard let mainWindow = mainWindow else { return }

        if mainWindow.isVisible {
            // 确保预览窗口也被隐藏
            PreviewWindowManager.shared.hidePreview()
            mainWindow.orderOut(nil)
        } else {
            // 恢复窗口位置（如果有保存的话）
            let savedX = UserDefaults.standard.double(forKey: "mainWindowX")
            let savedY = UserDefaults.standard.double(forKey: "mainWindowY")
            if savedX != 0 || savedY != 0 {
                mainWindow.setFrameOrigin(NSPoint(x: savedX, y: savedY))
            }

            // 确保窗口内容是最新的
            mainWindow.contentViewController = NSHostingController(rootView: ContentView())
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 处理设置更改事件
    @objc private func settingsChanged() {
        setupGlobalKeyboardMonitor()
    }

    /// 从弹出窗口中打开设置
    @objc private func openSettingsFromPopover() {
        DispatchQueue.main.async {
            self.showSettings()
        }
    }

    /// 处理窗口置顶设置变化
    @objc private func windowAlwaysOnTopChanged() {
        DispatchQueue.main.async {
            self.updateWindowLevel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidResignActive(_ notification: Notification) {
        // 应用程序失去焦点时，确保隐藏预览窗口
        PreviewWindowManager.shared.hidePreview()
    }

    func applicationWillHide(_ notification: Notification) {
        // 应用程序隐藏时，确保隐藏预览窗口
        PreviewWindowManager.shared.hidePreview()
    }
}
