import SwiftUI
import Cocoa

/// 应用程序代理类
/// 负责应用程序的生命周期管理、菜单栏设置、快捷键监听等
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusItem: NSStatusItem?          // 菜单栏状态项
    private(set) var popover: NSPopover? // 弹出窗口
    var eventMonitors: [Any] = []         // 事件监听器数组

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusBar()
        setupPopover()
        requestAccessibilityPermission()
        setupGlobalKeyboardMonitor()
        checkAndCleanupLargeHistory()

        // 监听设置更改通知
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: NSNotification.Name("SettingsChanged"), object: nil)
        // 监听打开设置窗口的通知
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromPopover), name: NSNotification.Name("OpenSettings"), object: nil)
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

    /// 设置弹出窗口
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .applicationDefined
        popover?.contentViewController = NSHostingController(rootView: ContentView())
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
            // 先关闭 popover
            self.popover?.performClose(nil)

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

    /// 切换弹出窗口的显示/隐藏
    @objc func togglePanel() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            // 确保预览窗口也被隐藏
            PreviewWindowManager.shared.hidePreview()
            popover.performClose(nil)
        } else {
            popover.contentViewController = NSHostingController(rootView: ContentView())
            popover.show(relativeTo: .zero, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            if let window = popover.contentViewController?.view.window {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 处理设置更改事件
    @objc private func settingsChanged() {
        setupGlobalKeyboardMonitor()
    }

    /// 从弹出窗口中打开设置
    @objc private func openSettingsFromPopover() {
        DispatchQueue.main.async {
            self.popover?.performClose(nil)
            self.showSettings()
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
