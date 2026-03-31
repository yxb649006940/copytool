#!/bin/bash

# 简单的 DMG 打包脚本
# 使用方法: ./make_dmg.sh

set -e

# 配置
APP_NAME="copytool"
VERSION="1.5.2"
BUILD_DIR="/Users/yuhoo/Library/Developer/Xcode/DerivedData/copytool-czqniqfdynuutaeknmdhjyeyfufj/Build/Products/Release"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="dmg_temp"

echo "========================================"
echo "copytool DMG 打包"
echo "========================================"

# 清理旧文件
echo "1. 清理旧文件..."
rm -f "${DMG_NAME}"
rm -rf "${DMG_DIR}"

# 创建临时目录
echo "2. 创建临时目录..."
mkdir -p "${DMG_DIR}"

# 复制应用程序
echo "3. 复制应用程序..."
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${DMG_DIR}/"

# 创建 Applications 快捷方式
echo "4. 创建 Applications 快捷方式..."
ln -s /Applications "${DMG_DIR}/Applications"

# 创建 DMG
echo "5. 创建 DMG 镜像..."
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_DIR}" -ov -format UDZO -imagekey zlib-level=9 -size 200m "${DMG_NAME}"

# 清理
echo "6. 清理临时文件..."
rm -rf "${DMG_DIR}"

echo "========================================"
echo "DMG 创建成功!"
echo "文件: ${DMG_NAME}"
echo "========================================"

# 显示文件大小
if [ -f "${DMG_NAME}" ]; then
    DMG_SIZE=$(du -h "${DMG_NAME}" | cut -f1)
    echo "DMG 大小: ${DMG_SIZE}"
fi
