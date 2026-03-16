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
struct HotkeyConfiguration: Codable {
    let keyCode: UInt16
    let modifiers: UInt // 存储修饰符的原始值

    /// 获取显示字符串（如 "Cmd + Opt + V"）
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
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "1", 32: "2",
            33: "3", 34: "4", 35: "6", 36: "5", 37: "=", 38: "9", 39: "7", 40: "-", 41: "8",
            42: "0", 43: "]", 44: "o", 45: "u", 46: "[", 47: "i", 48: "p"
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

    /// 开机启动设置
    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                let service = SMAppService.mainApp
                let isEnabled = service.status == .enabled
                let userDefaultValue = UserDefaults.standard.bool(forKey: launchAtLoginKey)

                // 如果系统状态与 UserDefaults 不一致，同步到系统状态
                if isEnabled != userDefaultValue {
                    print("Login item status mismatch - system: \(isEnabled), userDefault: \(userDefaultValue), syncing to system state")
                    UserDefaults.standard.set(isEnabled, forKey: launchAtLoginKey)
                }

                return isEnabled
            } else {
                return UserDefaults.standard.bool(forKey: launchAtLoginKey)
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
            applyLoginItemSetting(newValue)
        }
    }

    /// 检查应用是否在 Applications 文件夹中（macOS 13+ 的 SMAppService 要求）
    private func isAppInApplicationsFolder() -> Bool {
        let appPath = Bundle.main.bundlePath
        let applicationsPaths = [
            "/Applications",
            NSString(string: "~/Applications").expandingTildeInPath
        ]
        for applicationsPath in applicationsPaths {
            if appPath.hasPrefix(applicationsPath) {
                return true
            }
        }
        return false
    }

    /// 同步开机启动设置（确保 UserDefaults 与系统状态一致）
    private func syncLoginItemSetting() {
        let mainBundle = Bundle.main
        guard let bundleIdentifier = mainBundle.bundleIdentifier else {
            print("Failed to get bundle identifier for login item sync")
            return
        }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            let isEnabled = service.status == .enabled
            let userDefaultValue = UserDefaults.standard.bool(forKey: launchAtLoginKey)

            print("Login item status - system: \(isEnabled), userDefault: \(userDefaultValue), inApplicationsFolder: \(isAppInApplicationsFolder())")

            // 如果系统状态与 UserDefaults 不一致，强制同步
            if isEnabled != userDefaultValue {
                print("Syncing login item setting...")
                applyLoginItemSetting(userDefaultValue)
            }
        } else {
            // 旧版本 API 的同步逻辑
            let currentState = SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
            let shouldBeEnabled = UserDefaults.standard.bool(forKey: launchAtLoginKey)

            print("Login item status (old API) - current: \(currentState), shouldBe: \(shouldBeEnabled)")

            SMLoginItemSetEnabled(bundleIdentifier as CFString, shouldBeEnabled)
        }
    }

    /// 应用开机启动设置
    private func applyLoginItemSetting(_ enabled: Bool) {
        let mainBundle = Bundle.main
        guard let bundleIdentifier = mainBundle.bundleIdentifier else {
            print("Failed to get bundle identifier")
            return
        }

        if #available(macOS 13.0, *) {
            // 使用现代的 SMAppService API
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status != .enabled {
                        try service.register()
                        print("Successfully registered login item")
                    } else {
                        print("Login item already registered")
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                        print("Successfully unregistered login item")
                    } else {
                        print("Login item already unregistered")
                    }
                }
            } catch {
                print("Failed to set login item with SMAppService: \(error)")
                // 如果现代 API 失败，尝试使用旧 API（如果可用）
                if #unavailable(macOS 13.0) {
                    let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
                    print("Fallback to SMLoginItemSetEnabled: \(success ? "Success" : "Failed")")
                }
            }
        } else {
            // 使用旧的 API 保持向后兼容
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            print("SMLoginItemSetEnabled: \(success ? "Success" : "Failed") - \(enabled ? "Enabled" : "Disabled")")
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
