#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ThaiKeyboard"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="Apple Development"

echo "==> Building release binary"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Assembling app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Signing app bundle"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "==> Installing to /Applications"
pkill -x "${APP_NAME}" || true
ditto "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"

echo "==> Launching"
open "/Applications/${APP_NAME}.app"
