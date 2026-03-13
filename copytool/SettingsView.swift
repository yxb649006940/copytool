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
                VStack(spacing: 24) {
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
        .frame(width: 400, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            setupHotkeyMonitor()
        }
        .onDisappear {
            removeHotkeyMonitor()
        }
    }

    private var headerView: some View {
        HStack {
            Text("设置")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                onClose?()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
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
        .padding(.horizontal, 16)
    }

    private var storageDurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("存储时间")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(StorageDuration.allCases, id: \.self) { duration in
                    Button(action: {
                        selectedStorageDuration = duration
                    }) {
                        HStack {
                            Text(duration.rawValue)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedStorageDuration == duration {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
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
                }
            }
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用程序")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Toggle(isOn: $launchAtLogin) {
                    HStack {
                        Image(systemName: "poweron")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("开机启动")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                }
                .toggleStyle(SwitchToggleStyle())
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .onChange(of: launchAtLogin) {
                    SettingsManager.shared.launchAtLogin = launchAtLogin
                }

                Text("启用后，应用程序将在系统启动时自动运行")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                HStack {
                    Text("当前快捷键:")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Spacer()

                    if isRecordingHotkey {
                        Text("请按新快捷键...")
                            .font(.system(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.orange, lineWidth: 1)
                            )
                    } else {
                        Text(selectedHotkey.displayString)
                            .font(.system(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("预设快捷键:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        presetHotkeyButton(name: "Cmd+Opt+V", keyCode: 9, modifiers: [.command, .option])
                        presetHotkeyButton(name: "Cmd+Opt+C", keyCode: 8, modifiers: [.command, .option])
                        presetHotkeyButton(name: "Cmd+Shift+V", keyCode: 9, modifiers: [.command, .shift])
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("自定义快捷键:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            isRecordingHotkey.toggle()
                        }) {
                            Text(isRecordingHotkey ? "取消" : "录制")
                                .font(.system(size: 12))
                                .foregroundColor(isRecordingHotkey ? .red : .green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isRecordingHotkey ? Color.red : Color.green, lineWidth: 1)
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
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("说明：至少需要一个修饰键（Cmd/Opt/Ctrl/Shift）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.top, 4)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.systemOrange.withAlphaComponent(0.1)))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.orange, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    private func presetHotkeyButton(name: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> some View {
        let config = HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)

        return Button(action: {
            selectedHotkey = HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)
        }) {
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(isSelected(config) ? .white : .blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected(config) ? Color.blue : Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
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
    }

    private func isSelected(_ config: HotkeyConfiguration) -> Bool {
        selectedHotkey.keyCode == config.keyCode && selectedHotkey.modifierFlags == config.modifierFlags
    }

    private var footerView: some View {
        HStack(spacing: 8) {
            Button(action: {
                selectedStorageDuration = .oneMonth
                selectedHotkey = HotkeyConfiguration(keyCode: 9, modifiers: [.command, .option])
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("恢复默认")
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
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
                // 保存设置到 SettingsManager
                let settings = SettingsManager.shared
                settings.storageDuration = selectedStorageDuration
                settings.hotkey = selectedHotkey

                // 发送通知重新设置键盘监听
                NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)

                // 关闭窗口
                onClose?()
            }) {
                Text("确定")
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(6)
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
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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
