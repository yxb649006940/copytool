# CopyTool 打包说明

本文档介绍如何将 CopyTool 打包成可安装的 macOS 应用程序。

## 方法一：使用打包脚本（推荐）

我们提供了自动化的打包脚本，操作简单：

### 1. 运行打包脚本

```bash
# 进入项目目录
cd "/Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool"

# 运行打包脚本
./build_app.sh
```

### 2. 脚本功能说明

- **自动清理**：每次打包前自动清理旧的构建文件
- **验证环境**：检查 Xcode 是否已安装
- **构建应用**：使用 Release 配置构建
- **查找应用**：自动查找生成的应用程序
- **安装提示**：完成后提示如何安装到 Applications 文件夹

### 3. 脚本执行结果

脚本会在 `build/` 目录下生成应用程序，通常位于：
`build/Release/copytool.app`

## 方法二：使用 Xcode 手动打包

### 1. 打开项目

```bash
open "/Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool/copytool.xcodeproj"
```

### 2. 配置构建选项

1. 选择项目名称在左上角
2. 选择 `copytool` target
3. 选择 `Any Mac` 作为设备
4. 配置栏选择 `Edit Scheme...`
5. 将 `Run` 的 `Build Configuration` 设置为 `Release`

### 3. 构建应用

```bash
# 使用终端构建
xcodebuild -project "/Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool/copytool.xcodeproj" \
  -scheme "copytool" \
  -configuration "Release" \
  -derivedDataPath "/Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool/build" \
  clean build
```

## 方法三：使用 Xcode Archive

### 1. Archive 应用

- 在 Xcode 中，选择 `Product > Archive`
- 等待归档完成
- 点击 `Distribute App`

### 2. 选择分发方法

- 选择 `Copy App`（最简单的方法）
- 点击 `Next`
- 选择输出位置

## 安装和使用

### 1. 安装

将生成的 `copytool.app` 复制到 `/Applications` 文件夹：

```bash
cp -R "/Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool/build/Release/copytool.app" /Applications/
```

### 2. 打开应用

- 在 Finder 中打开 `/Applications` 文件夹
- 双击 `copytool.app`
- 菜单栏会出现剪贴板图标

### 3. 辅助功能权限

首次运行可能需要授予辅助功能权限：

1. 系统会弹出权限请求对话框
2. 点击"打开系统偏好设置"
3. 在"隐私" > "辅助功能"中添加 CopyTool 并勾选
4. 重启应用

## 打包常见问题

### 问题 1：Xcode 版本不匹配

**解决方法**：
- 确保使用 Xcode 16.0 或更高版本
- 检查项目设置中的部署目标版本

### 问题 2：签名问题

**解决方法**：
- 确保有有效的 Apple 开发者账户（可选，非必需）
- 或在项目设置中使用自动签名

### 问题 3：权限问题

**解决方法**：
- 确保脚本有执行权限：
  `chmod +x /Users/yuhoo/Documents/D/yxb10.com/ai/vibecoding/copy/copytool/build_app.sh`
- 确保用户有足够的权限

## 验证应用

### 检查应用是否可运行

```bash
# 直接运行
open "/Applications/copytool.app"

# 检查架构（现代 macOS 使用 arm64 或 x86_64）
file "/Applications/copytool.app/Contents/MacOS/copytool"
```

### 检查应用完整性

```bash
# 检查应用包内容
ls -la "/Applications/copytool.app/Contents/"
ls -la "/Applications/copytool.app/Contents/MacOS/"
ls -la "/Applications/copytool.app/Contents/Resources/"
```

## 卸载

要卸载应用，只需删除：

```bash
rm -rf "/Applications/copytool.app"
rm -rf "~/Library/Application Support/copytool"
rm -f "~/Library/Preferences/com.yourcompany.copytool.plist"
```

## 注意事项

1. **首次运行**：可能需要右键点击 `copytool.app` 然后选择"打开"来绕过安全警告
2. **运行状态**：应用会在后台运行，菜单栏会显示图标
3. **设置**：可以通过菜单栏图标的右键菜单打开设置窗口
4. **快捷键**：默认快捷键 `Cmd + Opt + V`

如果在打包过程中遇到其他问题，请检查 Xcode 的构建日志或终端输出。
