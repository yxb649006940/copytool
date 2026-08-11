#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-${SCRIPT_DIR}/build/Build/Products/Release/copytool.app}"
DMG_SUFFIX="${2:-}"

if [[ "${APP_PATH}" != /* ]]; then
    APP_PATH="${SCRIPT_DIR}/${APP_PATH}"
fi

test -d "${APP_PATH}" || {
    echo "未找到 Release 应用: ${APP_PATH}" >&2
    exit 1
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
if [[ -n "${DMG_SUFFIX}" ]]; then
    DMG_PATH="${SCRIPT_DIR}/copytool-${VERSION}-${DMG_SUFFIX}.dmg"
else
    DMG_PATH="${SCRIPT_DIR}/copytool-${VERSION}.dmg"
fi
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copytool-dmg.XXXXXX")"

cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/copytool.app"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"

hdiutil create \
    -volname "copytool" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
echo "DMG 创建成功: ${DMG_PATH}"
