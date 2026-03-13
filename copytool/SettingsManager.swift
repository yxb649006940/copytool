import Foundation
import Cocoa
import ServiceManagement

// 存储时间选项
enum StorageDuration: String, Codable, CaseIterable {
    case oneDay = "1天"
    case sevenDays = "7天"
    case oneMonth = "1个月"
    case forever = "永久"

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

// 快捷键配置
struct HotkeyConfiguration: Codable {
    let keyCode: UInt16
    let modifiers: UInt // 存储修饰符的原始值

    var displayString: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []

        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Opt")
        }
        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }

        // 转换keyCode到字符
        let keyChar = keyCodeToCharacter(keyCode)
        parts.append(keyChar)

        return parts.joined(separator: " + ")
    }

    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "1", 32: "2",
            33: "3", 34: "4", 35: "6", 36: "5", 37: "=", 38: "9", 39: "7", 40: "-", 41: "8",
            42: "0", 43: "]", 44: "o", 45: "u", 46: "[", 47: "i", 48: "p"
        ]

        return keyMap[keyCode]?.uppercased() ?? "Unknown"
    }
}

class SettingsManager {
    static let shared = SettingsManager()

    private let storageDurationKey = "storageDuration"
    private let hotkeyKey = "hotkeyConfiguration"
    private let launchAtLoginKey = "launchAtLogin"

    private init() {}

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

    var launchAtLogin: Bool {
        get {
            return UserDefaults.standard.bool(forKey: launchAtLoginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
            applyLoginItemSetting(newValue)
        }
    }

    // 应用开机启动设置
    private func applyLoginItemSetting(_ enabled: Bool) {
        let mainBundle = Bundle.main
        guard let bundleIdentifier = mainBundle.bundleIdentifier else {
            return
        }

        if #available(macOS 13.0, *) {
            // 使用现代的 SMAppService API
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Failed to set login item: \(error)")
            }
        } else {
            // 使用旧的 API 保持向后兼容
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            if !success {
                print("Failed to set login item")
            }
        }
    }

    // 检查历史项目是否过期
    func isItemExpired(timestamp: Date) -> Bool {
        guard let duration = storageDuration.days else {
            return false // 永久存储
        }

        let expirationDate = Date().addingTimeInterval(-duration)
        return timestamp < expirationDate
    }
}
