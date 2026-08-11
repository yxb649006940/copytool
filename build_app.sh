#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${SCRIPT_DIR}/copytool.xcodeproj"
APP_ARCH="${1:-}"
DERIVED_DATA_DIRECTORY="build"
XCODE_ARCH_ARGS=()

case "${APP_ARCH}" in
    "")
        ;;
    arm64)
        XCODE_ARCH_ARGS=(
            -destination "platform=macOS,arch=arm64"
            ARCHS=arm64
            ONLY_ACTIVE_ARCH=YES
        )
        ;;
    x86_64)
        DERIVED_DATA_DIRECTORY="build-intel"
        XCODE_ARCH_ARGS=(
            -destination "platform=macOS,arch=x86_64"
            ARCHS=x86_64
            ONLY_ACTIVE_ARCH=YES
        )
        ;;
    *)
        echo "不支持的架构: ${APP_ARCH}（可选值：arm64、x86_64）" >&2
        exit 1
        ;;
esac

DERIVED_DATA_PATH="${SCRIPT_DIR}/${DERIVED_DATA_DIRECTORY}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/copytool.app"

command -v xcodebuild >/dev/null || {
    echo "未找到 xcodebuild，请先安装并选择 Xcode。" >&2
    exit 1
}

xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme copytool \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    "${XCODE_ARCH_ARGS[@]}" \
    clean build

test -d "${APP_PATH}" || {
    echo "构建完成但未找到 ${APP_PATH}" >&2
    exit 1
}

codesign --verify --deep --strict "${APP_PATH}"
echo "构建成功: ${APP_PATH}"
