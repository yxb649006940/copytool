//
//  copytoolApp.swift
//  copytool
//
//  Created by yuhoo on 2026/3/12.
//

import SwiftUI

@main
struct copytoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
