//
//  copytoolApp.swift
//  copytool
//
//  Created by yuhoo on 2026/3/12.
//

import SwiftUI

/// 应用程序入口点
@main
struct copytoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // 适配 AppDelegate

    init() {
        // 初始化 SettingsManager，确保开机启动状态同步
        _ = SettingsManager.shared
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
