#!/bin/bash

# CopyTool 打包脚本
# 用于构建 macOS 应用程序

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="copytool"
SCHEME_NAME="copytool"
CONFIGURATION="Release"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/$CONFIGURATION/$PROJECT_NAME.app"

echo "========================================="
echo "  CopyTool 应用打包脚本"
echo "========================================="
echo ""

# 清理旧的构建
echo "清理旧的构建文件..."
rm -rf "$BUILD_DIR"

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo "错误: 未找到 xcodebuild，请确保已安装 Xcode"
    exit 1
fi

# 构建应用
echo ""
echo "开始构建应用..."
xcodebuild \
    -project "$SCRIPT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    clean build

# 查找生成的应用
if [ ! -d "$APP_PATH" ]; then
    # 尝试查找其他位置
    APP_PATH=$(find "$BUILD_DIR" -name "$PROJECT_NAME.app" -type d | head -n 1)
    if [ -z "$APP_PATH" ]; then
        echo "错误: 无法找到生成的应用程序"
        exit 1
    fi
fi

echo ""
echo "========================================="
echo "  构建成功！"
echo "========================================="
echo ""
echo "应用程序位置:"
echo "  $APP_PATH"
echo ""
echo "你可以将应用复制到应用程序文件夹:"
echo "  cp -R \"$APP_PATH\" /Applications/"
echo ""
