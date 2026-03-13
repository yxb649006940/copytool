import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusItem: NSStatusItem?
    private(set) var popover: NSPopover?
    var eventMonitors: [Any] = []

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

    // 检查并清理过大的历史记录
    private func checkAndCleanupLargeHistory() {
        if let data = UserDefaults.standard.data(forKey: "clipboardHistory") {
            if data.count >= 4 * 1024 * 1024 { // >=4MB
                print("Warning: Clipboard history data too large (\(data.count) bytes), clearing all history")
                UserDefaults.standard.removeObject(forKey: "clipboardHistory")
            }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "剪贴板历史")
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
                showMenu()
            } else {
                togglePanel()
            }
        }
    }

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

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .applicationDefined
        popover?.contentViewController = NSHostingController(rootView: ContentView())
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        print("辅助功能权限: \(accessibilityEnabled ? "已授予" : "未授予")")
    }

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

    @objc func togglePanel() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
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

    @objc private func settingsChanged() {
        setupGlobalKeyboardMonitor()
    }

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
}
