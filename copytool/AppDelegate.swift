import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        requestAccessibilityPermission()
        setupGlobalKeyboardMonitor()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "剪贴板历史")
            button.action = #selector(togglePanel)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示历史记录", action: #selector(togglePanel), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate), keyEquivalent: "q")

        statusItem?.menu = menu
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

    private func setupGlobalKeyboardMonitor() {
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
        // 检查 Cmd + Opt + V
        let isVKey = event.keyCode == 9
        let hasCmd = event.modifierFlags.contains(.command)
        let hasOpt = event.modifierFlags.contains(.option)
        let hasOtherModifiers = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.control)

        if isVKey && hasCmd && hasOpt && !hasOtherModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.togglePanel()
            }
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

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
    }
}