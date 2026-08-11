import Foundation
import Cocoa
import ServiceManagement

/// 存储时间选项枚举
enum StorageDuration: String, Codable, CaseIterable {
    case oneDay = "1天"
    case sevenDays = "7天"
    case oneMonth = "1个月"
    case forever = "永久"

    /// 获取存储时间的天数
    var days: TimeInterval? {
        switch self {
        case .oneDay:
            return 1 * 24 * 60 * 60
        case .sevenDays:
            return 7 * 24 * 60 * 60
        case .oneMonth:
            return 30 * 24 * 60 * 60
        case .forever:
            return nil // 永久存储
        }
    }
}

/// 快捷键配置结构体
struct HotkeyConfiguration: Codable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt // 存储修饰符的原始值

    /// 获取显示字符串（如 "Cmd + Opt + V"）
    var displayString: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []

        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        if modifiers.contains(.option) {
            parts.append("Opt")
        }
        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }

        // 转换keyCode到字符
        let keyChar = keyCodeToCharacter(keyCode)
        parts.append(keyChar)

        return parts.joined(separator: " + ")
    }

    /// 获取修饰符标志
    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// 初始化方法
    /// - Parameters:
    ///   - keyCode: 键码
    ///   - modifiers: 修饰符
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }

    /// 键码到字符的转换
    /// - Parameter keyCode: 键码
    /// - Returns: 对应的字符
    private func keyCodeToCharacter(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "Return",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Esc", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
            75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =", 82: "Keypad 0",
            83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
            88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9", 96: "F5",
            97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
            106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
            115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End",
            120: "F2", 121: "Page Down", 122: "F1", 123: "Left", 124: "Right", 125: "Down",
            126: "Up"
        ]

        return keyMap[keyCode]?.uppercased() ?? "Unknown"
    }
}

/// 设置管理器
class SettingsManager {
    static let shared = SettingsManager() // 单例实例

    private let storageDurationKey = "storageDuration"
    private let hotkeyKey = "hotkeyConfiguration"
    private let launchAtLoginKey = "launchAtLogin"
    private let windowAlwaysOnTopKey = "windowAlwaysOnTop"
    private let monitoringEnabledKey = "monitoringEnabled"

    private init() {
        // 初始化时同步开机启动设置
        syncLoginItemSetting()
    }

    /// 存储持续时间设置
    var storageDuration: StorageDuration {
        get {
            if let savedDuration = UserDefaults.standard.string(forKey: storageDurationKey),
               let duration = StorageDuration(rawValue: savedDuration) {
                return duration
            }
            return .oneMonth // 默认存储1个月
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageDurationKey)
        }
    }

    /// 快捷键配置
    var hotkey: HotkeyConfiguration {
        get {
            if let data = UserDefaults.standard.data(forKey: hotkeyKey),
               let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) {
                return config
            }
            return HotkeyConfiguration(keyCode: 9, modifiers: NSEvent.ModifierFlags([.command, .option]))
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: hotkeyKey)
            }
        }
    }

    /// 窗口置顶设置
    var windowAlwaysOnTop: Bool {
        get {
            return UserDefaults.standard.bool(forKey: windowAlwaysOnTopKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: windowAlwaysOnTopKey)
            // 通知更新窗口层级
            NotificationCenter.default.post(name: NSNotification.Name("WindowAlwaysOnTopChanged"), object: nil)
        }
    }

    /// 是否记录新的剪贴板内容。默认开启。
    var monitoringEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: monitoringEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: monitoringEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: monitoringEnabledKey)
        }
    }

    /// 开机启动设置
    var launchAtLogin: Bool {
        get {
            let service = SMAppService.mainApp
            let isEnabled = service.status == .enabled
            let userDefaultValue = UserDefaults.standard.bool(forKey: launchAtLoginKey)

            if isEnabled != userDefaultValue {
                UserDefaults.standard.set(isEnabled, forKey: launchAtLoginKey)
            }

            return isEnabled
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
            applyLoginItemSetting(newValue)
        }
    }

    /// 同步开机启动设置（确保 UserDefaults 与系统状态一致）
    private func syncLoginItemSetting() {
        let service = SMAppService.mainApp
        let isEnabled = service.status == .enabled
        let userDefaultValue = UserDefaults.standard.bool(forKey: launchAtLoginKey)

        // 启动时以系统真实状态为准，不在用户未操作时注册或注销。
        if isEnabled != userDefaultValue {
            UserDefaults.standard.set(isEnabled, forKey: launchAtLoginKey)
        }
    }

    /// 应用开机启动设置
    private func applyLoginItemSetting(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                } else {
                    return
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            print("Failed to set login item with SMAppService: \(error)")
            UserDefaults.standard.set(service.status == .enabled, forKey: launchAtLoginKey)
        }
    }

    /// 检查历史项目是否过期
    func isItemExpired(timestamp: Date) -> Bool {
        guard let duration = storageDuration.days else {
            return false // 永久存储
        }

        let expirationDate = Date().addingTimeInterval(-duration)
        return timestamp < expirationDate
    }
}
