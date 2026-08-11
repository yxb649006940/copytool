#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ARCH="${1:-}"

case "${APP_ARCH}" in
    "")
        APP_PATH="${SCRIPT_DIR}/build/Build/Products/Release/copytool.app"
        DMG_SUFFIX=""
        ;;
    arm64)
        APP_PATH="${SCRIPT_DIR}/build/Build/Products/Release/copytool.app"
        DMG_SUFFIX="arm64"
        ;;
    x86_64)
        APP_PATH="${SCRIPT_DIR}/build-intel/Build/Products/Release/copytool.app"
        DMG_SUFFIX="intel"
        ;;
    *)
        echo "不支持的架构: ${APP_ARCH}（可选值：arm64、x86_64）" >&2
        exit 1
        ;;
esac

"${SCRIPT_DIR}/build_app.sh" "${APP_ARCH}"
"${SCRIPT_DIR}/create_dmg.sh" "${APP_PATH}" "${DMG_SUFFIX}"
