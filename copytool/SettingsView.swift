import SwiftUI
import Cocoa

struct SettingsView: View {
    var onClose: (() -> Void)?
    @State private var selectedStorageDuration: StorageDuration
    @State private var selectedHotkey: HotkeyConfiguration
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var launchAtLogin: Bool

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        let settings = SettingsManager.shared
        self._selectedStorageDuration = State(initialValue: settings.storageDuration)
        self._selectedHotkey = State(initialValue: settings.hotkey)
        self._launchAtLogin = State(initialValue: settings.launchAtLogin)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    storageDurationSection
                    launchAtLoginSection
                    hotkeySection
                }
                .padding(24)
            }

            Divider()

            footerView
                .padding(.vertical, 16)
        }
        .frame(width: 440, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            setupHotkeyMonitor()
        }
        .onDisappear {
            removeHotkeyMonitor()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("偏好设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("自定义应用程序行为和外观")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                onClose?()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
    }

    private var storageDurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "存储管理", icon: "clock.arrow.circlepath")

            VStack(spacing: 10) {
                ForEach(StorageDuration.allCases, id: \.self) { duration in
                    Button(action: {
                        selectedStorageDuration = duration
                    }) {
                        HStack {
                            Text(duration.rawValue)
                                .font(.system(size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedStorageDuration == duration {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(NSColor.separatorColor))
                            }
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedStorageDuration == duration ? Color.blue : Color(NSColor.separatorColor), lineWidth: selectedStorageDuration == duration ? 1.5 : 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
            .padding(.all, 1)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
        }
        .padding(.all, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "应用程序", icon: "power")

            VStack(spacing: 12) {
                Toggle(isOn: $launchAtLogin) {
                    HStack(spacing: 14) {
                        Image(systemName: "poweron")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开机启动")
                                .font(.system(size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("系统启动时自动运行应用程序")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(SwitchToggleStyle())
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .onChange(of: launchAtLogin) {
                    SettingsManager.shared.launchAtLogin = launchAtLogin
                }
            }
        }
        .padding(.all, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "快捷键", icon: "keyboard")

            VStack(spacing: 20) {
                HStack {
                    Text("当前快捷键:")
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    if isRecordingHotkey {
                        Text("请按新快捷键...")
                            .font(.system(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(NSColor.systemOrange.withAlphaComponent(0.1)))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange, lineWidth: 1.5)
                            )
                    } else {
                        Text(selectedHotkey.displayString)
                            .font(.system(size: 14))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("预设快捷键:")
                        .font(.system(size: 13))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        presetHotkeyButton(name: "Cmd+Opt+V", keyCode: 9, modifiers: [.command, .option])
                        presetHotkeyButton(name: "Cmd+Opt+C", keyCode: 8, modifiers: [.command, .option])
                        presetHotkeyButton(name: "Cmd+Shift+V", keyCode: 9, modifiers: [.command, .shift])
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("自定义快捷键:")
                            .font(.system(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            isRecordingHotkey.toggle()
                        }) {
                            Text(isRecordingHotkey ? "取消录制" : "开始录制")
                                .font(.system(size: 13))
                                .fontWeight(.medium)
                                .foregroundColor(isRecordingHotkey ? .red : .green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isRecordingHotkey ? Color(NSColor.systemRed.withAlphaComponent(0.1)) : Color(NSColor.systemGreen.withAlphaComponent(0.1)))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isRecordingHotkey ? Color.red : Color.green, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }

                    if isRecordingHotkey {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("请按任意快捷键组合，例如 Cmd + Opt + K")
                                .font(.system(size: 12))
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("说明：至少需要一个修饰键（Cmd/Opt/Ctrl/Shift）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(NSColor.systemOrange.withAlphaComponent(0.15)))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(.all, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private func SectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
            Text(title)
                .font(.system(size: 15))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }

    private func presetHotkeyButton(name: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> some View {
        let config = HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)

        return Button(action: {
            selectedHotkey = HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)
        }) {
            Text(name)
                .font(.system(size: 12))
                .fontWeight(.medium)
                .foregroundColor(isSelected(config) ? .white : .blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected(config) ? Color.blue : Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected(config) ? Color.blue : Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func isSelected(_ config: HotkeyConfiguration) -> Bool {
        selectedHotkey.keyCode == config.keyCode && selectedHotkey.modifierFlags == config.modifierFlags
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            Button(action: {
                selectedStorageDuration = .oneMonth
                selectedHotkey = HotkeyConfiguration(keyCode: 9, modifiers: [.command, .option])
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("恢复默认")
                }
                .font(.system(size: 13))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Spacer()

            Button(action: {
                let settings = SettingsManager.shared
                settings.storageDuration = selectedStorageDuration
                settings.hotkey = selectedHotkey

                // 保存设置后立即清理过期记录
                ClipboardManager.shared.cleanExpiredItems()

                NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
                onClose?()
            }) {
                Text("保存并关闭")
                    .font(.system(size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }

    private func setupHotkeyMonitor() {
        if let existingMonitor = hotkeyMonitor {
            NSEvent.removeMonitor(existingMonitor)
        }

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard isRecordingHotkey else { return event }

            if event.type == .keyDown {
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

                // 确保至少有一个修饰键，且不是单独的修饰键
                if !modifiers.isEmpty && event.keyCode != 0 && event.keyCode != 55 && event.keyCode != 56 && event.keyCode != 58 && event.keyCode != 59 {
                    let newHotkey = HotkeyConfiguration(keyCode: event.keyCode, modifiers: modifiers)
                    selectedHotkey = newHotkey
                    isRecordingHotkey = false
                    return nil
                }
            }

            return event
        }
    }

    private func removeHotkeyMonitor() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
