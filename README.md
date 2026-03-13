# CopyTool - macOS 剪贴板历史记录管理器

一个简洁、高效的 macOS 剪贴板历史记录管理工具。

## 功能特点

- 📋 自动记录最后 10 条复制内容
- 📝 支持文本和图片内容
- 🔍 点击历史记录立即重新复制
- 🗑️ 删除单条记录或清空所有历史
- 💾 持久化存储，重启后记录保留
- ⌨️ Cmd + Opt + V 快捷键快速打开
- 🍎 菜单栏图标，随时访问

## 使用方法

### 1. 启动应用
- 在 Xcode 中运行，或打包后放入应用程序文件夹
- 应用会在菜单栏显示一个文档图标

### 2. 查看历史记录
- 点击菜单栏的文档图标
- 选择"显示历史记录"
- 或使用快捷键 Cmd + Opt + V

### 3. 使用历史记录
- **点击记录项**：立即复制到剪贴板并关闭窗口
- **点击 × 按钮**：删除单条记录
- **点击"清空所有"**：清除所有历史记录

### 4. 快捷键说明
- Cmd + Opt + V：打开/关闭历史记录（需要辅助功能权限）
- 也可以通过菜单栏图标随时访问

## 系统要求

- macOS 15.7 或更高版本
- Xcode 16.0 或更高版本（开发时）

## 授权辅助功能权限

为了让全局快捷键（失去焦点时也能工作）正常使用，需要授予辅助功能权限：

1. 打开"系统偏好设置"
2. 选择"安全性与隐私" → "隐私"
3. 在左侧选择"辅助功能"
4. 点击锁图标解锁
5. 添加 copytool 应用并勾选
6. 重启应用

## 项目结构

```
copytool/
├── AppDelegate.swift              # 应用委托和菜单栏
├── ClipboardManager.swift        # 剪贴板管理和历史记录
├── ContentView.swift              # 主界面
├── copytoolApp.swift              # 应用入口
├── HistoryItem.swift              # 历史记录数据模型
├── ImageCache.swift               # 图片缓存
├── Assets.xcassets/               # 资源文件
└── copytool.xcodeproj/            # Xcode 项目文件
```

## 技术栈

- **语言**：Swift
- **框架**：SwiftUI, AppKit
- **存储**：UserDefaults
- **平台**：macOS

## 核心功能实现

### 剪贴板监听
- 每 0.5 秒检查一次剪贴板变化
- 使用 NSPasteboard.changeCount 检测变化
- 自动记录文本和图片内容

### 历史记录管理
- 最多保存 10 条记录
- 使用 lastAddedText/lastAddedImageData 防止重复添加
- 持久化存储到 UserDefaults

### 用户界面
- 菜单栏状态项（NSStatusItem）
- 弹出式窗口（NSPopover）
- SwiftUI 列表显示历史记录

## 打包发布

### 1. 使用 Xcode Archive
1. Product → Archive
2. 在 Organizer 中选择归档
3. 点击"Distribute App"
4. 选择"Copy App"选项

### 2. 手动构建
1. 在 Xcode 中设置 Scheme 为 Release
2. Product → Build
3. 在 Build/Products/Release 文件夹中找到 .app 文件
4. 复制到应用程序文件夹

## 已知问题

- 全局快捷键需要辅助功能权限
- 首次使用时可能需要手动授权权限

## 开发者

使用 Xcode 16.0 或更高版本进行开发。

## 许可证

本项目仅供学习和个人使用。

---

享受高效的剪贴板管理！
