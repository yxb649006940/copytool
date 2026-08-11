# CopyTool 构建与发布

## 环境要求

- macOS 15.7 或更高版本
- 能正常执行 `xcodebuild` 的 Xcode
- 命令行工具已通过 `xcode-select` 指向当前 Xcode

## 构建 Release 应用

```bash
./build_app.sh
```

脚本会执行干净构建、检查应用包是否存在，并验证代码签名。输出位于：

```text
build/Build/Products/Release/copytool.app
```

也可以显式构建指定架构：

```bash
./build_app.sh arm64
./build_app.sh x86_64
```

Intel 版本输出到 `build-intel/Build/Products/Release/copytool.app`。

## 创建 DMG

先构建应用，再创建 DMG：

```bash
./build_app.sh
./create_dmg.sh
```

也可以一次执行完整流程：

```bash
./build_dmg.sh
```

同时发布 ARM 与 Intel 安装包时分别执行：

```bash
./build_dmg.sh arm64
./build_dmg.sh x86_64
```

对应输出为 `copytool-<版本>-arm64.dmg` 和 `copytool-<版本>-intel.dmg`。

DMG 文件名从应用包的 `CFBundleShortVersionString` 自动生成，不再在脚本中重复维护版本号。`make_dmg.sh` 仅作为旧命令的兼容入口。

## 发布前检查

```bash
codesign --verify --deep --strict build/Build/Products/Release/copytool.app
spctl -a -vv --type execute build/Build/Products/Release/copytool.app
```

对外分发前还应使用 Developer ID Application 证书签名，通过 Apple notarization，然后使用 `stapler` 将凭据附加到最终 DMG。

## 常见问题

### Xcode 插件或 CoreSimulator 加载失败

如果 `xcodebuild` 报告系统内容不完整，先关闭 Xcode，然后执行：

```bash
xcodebuild -runFirstLaunch
```

如问题仍然存在，请在 Xcode Settings 中安装缺失的平台组件，或重新安装 Xcode。

### 开机启动无法注册

请先将 `copytool.app` 移到 `/Applications` 后再开启该选项。
