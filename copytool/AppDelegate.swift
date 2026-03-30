import SwiftUI
import Cocoa
import CoreGraphics

/// 应用程序代理类
/// 负责应用程序的生命周期管理、菜单栏设置、快捷键监听等
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusItem: NSStatusItem?          // 菜单栏状态项
    private(set) var mainWindow: NSWindow? // 主窗口（替代 popover）
    private var settingsWindow: NSWindow?  // 设置窗口
    var eventMonitors: [Any] = []         // 事件监听器数组
    private var eventTap: CFMachPort?     // CGEventTap 句柄
    private var eventTapRunLoopSource: CFRunLoopSource?  // EventTap 的 RunLoop 源
    private var eventTapCheckTimer: Timer?  // EventTap 状态检查定时器
    private var isProcessingHotkey = false  // 防止快捷键重复触发
    private var wasTemporarilyToggled = false  // 标记窗口是否被临时置顶

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
        // 监听窗口关闭事件，确保设置窗口也一起关闭
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowWillClose), name: NSWindow.willCloseNotification, object: nil)
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
        let minSize = NSSize(width: 400, height: 400)
        let savedWidth = UserDefaults.standard.double(forKey: "mainWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "mainWindowHeight")

        // 确保窗口尺寸不小于最小尺寸，并更新 UserDefaults 中的无效值
        let validWidth = max(savedWidth, minSize.width)
        let validHeight = max(savedHeight, minSize.height)

        // 如果保存的尺寸无效，更新 UserDefaults
        if savedWidth > 0 && savedWidth < minSize.width {
            UserDefaults.standard.set(minSize.width, forKey: "mainWindowWidth")
        }
        if savedHeight > 0 && savedHeight < minSize.height {
            UserDefaults.standard.set(minSize.height, forKey: "mainWindowHeight")
        }

        let windowSize = savedWidth > 0 && savedHeight > 0 ? NSSize(width: validWidth, height: validHeight) : defaultSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "剪贴板历史"
        window.isReleasedWhenClosed = false
        window.minSize = minSize
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
        saveWindowState(window: window)
    }

    /// 窗口位置变化时保存到 UserDefaults
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowState(window: window)
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

        // 首先尝试设置 CGEventTap（需要辅助功能权限）
        setupEventTap()

        // 本地事件监听（应用聚焦时）- 作为备用方案
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self = self else { return event }
            return self.handleLocalKeyDown(event: event)
        }) {
            eventMonitors.append(localMonitor)
        }

        // 添加 keyUp 事件监听
        if let keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            guard let self = self else { return event }
            return self.handleLocalKeyUp(event: event)
        }) {
            eventMonitors.append(keyUpMonitor)
        }
    }

    /// 处理全局 keyDown 事件（作为备用方案）
    private func handleGlobalKeyDown(event: NSEvent) {
        guard !isProcessingHotkey else {
            return
        }

        let settings = SettingsManager.shared
        let hotkey = settings.hotkey

        // 检查是否匹配自定义快捷键
        let isMatchingKeyCode = event.keyCode == hotkey.keyCode
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isMatchingModifiers = eventModifiers == hotkey.modifierFlags

        if isMatchingKeyCode && isMatchingModifiers {
            // 这个备用方案只在主窗口不可见时才触发（避免重复触发）
            if let mainWindow = mainWindow, !mainWindow.isVisible {
                DispatchQueue.main.async { [weak self] in
                    self?.togglePanel()
                }
            }
        }
    }

    /// 处理本地 keyDown 事件
    private func handleLocalKeyDown(event: NSEvent) -> NSEvent? {
        // 注意：如果有 EventTap 正在工作（辅助功能权限已授予），本地事件监听会被禁用
        // 这样可以防止重复触发 togglePanel()
        guard eventTap == nil else {
            return event // EventTap 已在处理，本地事件监听不处理
        }

        guard !isProcessingHotkey else {
            return event // 已有处理进行中，直接返回事件
        }

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
            return nil // 阻止事件继续传递
        }

        return event
    }

    /// 处理本地 keyUp 事件
    private func handleLocalKeyUp(event: NSEvent) -> NSEvent? {
        let settings = SettingsManager.shared
        let hotkey = settings.hotkey

        let isMatchingKeyCode = event.keyCode == hotkey.keyCode
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isMatchingModifiers = eventModifiers == hotkey.modifierFlags

        if isMatchingKeyCode && isMatchingModifiers {
            return nil // 阻止 keyUp 事件继续传递
        }

        return event
    }

    /// 设置 CGEventTap 来拦截键盘事件（更底层，可以真正阻止事件传递）
    private func setupEventTap() {
        // 先清理旧的 EventTap
        cleanupEventTap()

        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                // 回调函数，处理事件
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleEventTap(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("无法创建 EventTap，可能是没有辅助功能权限")
            return
        }

        eventTap = tap

        // 将 EventTap 添加到 RunLoop 中
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        eventTapRunLoopSource = runLoopSource

        // 启用 EventTap
        CGEvent.tapEnable(tap: tap, enable: true)
        print("EventTap 设置成功")

        // 启动 EventTap 状态检查定时器
        setupEventTapCheckTimer()
    }

    /// 设置 EventTap 状态检查定时器
    private func setupEventTapCheckTimer() {
        eventTapCheckTimer?.invalidate()
        eventTapCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.checkEventTapValidity()
        }
    }

    /// 检查 EventTap 是否仍然有效
    private func checkEventTapValidity() {
        // 检查 EventTap 是否存在且仍然有效
        guard let tap = eventTap else {
            print("EventTap 不存在，重新尝试设置")
            self.setupEventTap()
            return
        }

        // 尝试获取 EventTap 的属性来检查其有效性
        // 这里使用一种简单的方法：检查是否可以成功调用 CGEvent.tapEnable（它会返回布尔值）
        let isTapEnabled = CGEvent.tapIsEnabled(tap: tap)
        if !isTapEnabled {
            print("EventTap 已被禁用，重新设置")
            self.setupEventTap()
            return
        }

        // 额外的检查：尝试获取 EventTap 的事件类型
        // 如果 EventTap 无效，这些调用可能会失败，但为了安全，我们不在这里进行
        print("EventTap 状态检查 - 有效")
    }

    /// 清理 EventTap
    private func cleanupEventTap() {
        eventTapCheckTimer?.invalidate()
        eventTapCheckTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let runLoopSource = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            eventTapRunLoopSource = nil
        }
    }

    /// 处理 EventTap 回调
    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 如果不是 keyDown 事件，直接返回
        if type != .keyDown {
            return Unmanaged.passRetained(event)
        }

        // 检查是否正在处理快捷键
        guard !isProcessingHotkey else {
            return Unmanaged.passRetained(event)
        }

        let settings = SettingsManager.shared
        let hotkey = settings.hotkey

        // 获取按键信息
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var flags = event.flags

        // 提取我们关心的修饰键
        var modifierFlags: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifierFlags.insert(.command) }
        if flags.contains(.maskAlternate) { modifierFlags.insert(.option) }
        if flags.contains(.maskControl) { modifierFlags.insert(.control) }
        if flags.contains(.maskShift) { modifierFlags.insert(.shift) }

        // 检查是否匹配我们的快捷键
        let isMatchingKeyCode = UInt16(keyCode) == hotkey.keyCode
        let isMatchingModifiers = modifierFlags == hotkey.modifierFlags

        if isMatchingKeyCode && isMatchingModifiers {
            // 匹配成功，处理快捷键并返回 nil 来阻止事件传递
            DispatchQueue.main.async { [weak self] in
                self?.togglePanel()
            }
            return nil // 阻止事件继续传递！
        }

        // 不匹配，返回原始事件
        return Unmanaged.passRetained(event)
    }

    /// 显示设置窗口
    @objc private func showSettings() {
        DispatchQueue.main.async {
            // 检查是否已有设置窗口打开
            if let existingWindow = self.settingsWindow, existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
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
            settingsWindow.level = .normal // 设置为普通层级，不一直置顶

            let settingsView = SettingsView(onClose: {
                settingsWindow.close()
            })
            settingsWindow.contentViewController = NSHostingController(rootView: settingsView)
            settingsWindow.title = "设置"
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // 保存设置窗口的引用
            self.settingsWindow = settingsWindow
        }
    }

    /// 切换主窗口的显示/隐藏
    @objc func togglePanel() {
        // 防止重复触发
        guard !isProcessingHotkey else {
            print("Skipping - already processing hotkey")
            return
        }

        guard let mainWindow = mainWindow else {
            print("Error: mainWindow is nil")
            return
        }

        isProcessingHotkey = true

        print("=== togglePanel() called ===")
        print("Window visible: \(mainWindow.isVisible)")
        print("Window level: \(mainWindow.level.rawValue)")
        print("Floating level: \(NSWindow.Level.floating.rawValue)")
        print("Window always on top setting: \(SettingsManager.shared.windowAlwaysOnTop)")
        print("Window key: \(mainWindow.isKeyWindow)")
        print("---------------------------")

        if mainWindow.isVisible {
            // 如果窗口是当前的 key window，则关闭；否则只让它到前方但不改变置顶状态
            if mainWindow.isKeyWindow {
                // 窗口是当前的 key window - 关闭窗口
                print("Window is key window - closing window")
                saveWindowState(window: mainWindow)
                PreviewWindowManager.shared.hidePreview()
                mainWindow.orderOut(nil)

                // 同时关闭设置窗口（如果打开）
                if let settingsWindow = self.settingsWindow, settingsWindow.isVisible {
                    settingsWindow.orderOut(nil)
                    self.settingsWindow = nil
                }

                print("✅ Window closed")
            } else {
                // 窗口已显示但不是 key window - 让它到前方但保持原有的置顶设置
                print("Window is visible but not key window - bringing to front")
                // 恢复根据设置应该有的层级
                if SettingsManager.shared.windowAlwaysOnTop {
                    mainWindow.level = .floating
                } else {
                    mainWindow.level = .normal
                }
                mainWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                print("✅ Window has been brought to front")
            }
        } else {
            // 窗口未显示，显示窗口
            print("Window not visible - showing window")
            if mainWindow.contentViewController == nil {
                mainWindow.contentViewController = NSHostingController(rootView: ContentView())
            }

            restoreWindowState(window: mainWindow)

            let minSize = NSSize(width: 400, height: 400)
            let savedWidth = UserDefaults.standard.double(forKey: "mainWindowWidth")
            let savedHeight = UserDefaults.standard.double(forKey: "mainWindowHeight")
            if savedWidth > 0 && savedHeight > 0 {
                var frame = mainWindow.frame
                frame.size = NSSize(width: max(savedWidth, minSize.width), height: max(savedHeight, minSize.height))
                mainWindow.setFrame(frame, display: true, animate: false)
            }

            // 应用正确的层级
            if SettingsManager.shared.windowAlwaysOnTop {
                mainWindow.level = .floating
            } else {
                mainWindow.level = .normal
            }

            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("✅ Window has been shown")
        }

        // 重置状态（延迟时间缩短一点，让响应更迅速）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isProcessingHotkey = false
        }
    }

    /// 保存窗口状态（大小和位置）
    private func saveWindowState(window: NSWindow) {
        let minSize = NSSize(width: 400, height: 400)
        let size = window.frame.size
        let origin = window.frame.origin

        // 保存窗口大小（确保不小于最小尺寸）
        let validWidth = max(size.width, minSize.width)
        let validHeight = max(size.height, minSize.height)
        UserDefaults.standard.set(validWidth, forKey: "mainWindowWidth")
        UserDefaults.standard.set(validHeight, forKey: "mainWindowHeight")

        // 保存窗口位置
        UserDefaults.standard.set(origin.x, forKey: "mainWindowX")
        UserDefaults.standard.set(origin.y, forKey: "mainWindowY")

        // 立即同步
        UserDefaults.standard.synchronize()
    }

    /// 恢复窗口状态（大小和位置）
    private func restoreWindowState(window: NSWindow) {
        let minSize = NSSize(width: 400, height: 400)
        let defaultSize = NSSize(width: 400, height: 500)

        // 读取保存的窗口大小
        let savedWidth = UserDefaults.standard.double(forKey: "mainWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "mainWindowHeight")
        let windowSize = savedWidth > 0 && savedHeight > 0 ? NSSize(width: max(savedWidth, minSize.width), height: max(savedHeight, minSize.height)) : defaultSize

        // 读取保存的窗口位置
        let savedX = UserDefaults.standard.double(forKey: "mainWindowX")
        let savedY = UserDefaults.standard.double(forKey: "mainWindowY")
        let hasSavedPosition = savedX != 0 || savedY != 0

        // 直接创建完整的 frame
        var newFrame = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)

        if hasSavedPosition {
            newFrame.origin = NSPoint(x: savedX, y: savedY)
        } else {
            // 如果没有保存的位置，居中显示
            newFrame.origin = window.screen?.visibleFrame.origin ?? NSPoint(x: 0, y: 0)
        }

        // 使用 setFrame 方法直接设置完整的 frame
        window.setFrame(newFrame, display: true, animate: false)

        // 如果是第一次显示且没有保存位置，则居中显示
        if !hasSavedPosition {
            window.center()
        }
    }

    /// 处理设置更改事件
    @objc private func settingsChanged() {
        print("设置已更改，重新设置键盘监听")
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

    /// 主窗口即将关闭时的处理
    @objc private func mainWindowWillClose(notification: Notification) {
        // 如果是主窗口关闭，则同时关闭设置窗口（如果打开）
        if let window = notification.object as? NSWindow, window === mainWindow {
            if let settingsWindow = self.settingsWindow, settingsWindow.isVisible {
                settingsWindow.orderOut(nil)
                self.settingsWindow = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        cleanupEventTap()
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
