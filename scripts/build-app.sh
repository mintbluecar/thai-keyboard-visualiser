#!/usr/bin/env bash
# Builds ThaiKeyboard.app, signs it, installs it to /Applications and
# launches it.
#
#   scripts/build-app.sh               build, sign, install, launch
#   scripts/build-app.sh --no-install  build and sign only (.build/ThaiKeyboard.app)
#
# Environment overrides (used by the release workflow):
#   SIGN_IDENTITY  codesign identity; "-" signs ad hoc (default "Apple Development")
#   ARCH_FLAGS     extra swift build flags, e.g. "--arch arm64 --arch x86_64"
#   VERSION        sets CFBundleShortVersionString and CFBundleVersion
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ThaiKeyboard"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development}"
read -r -a ARCH_ARGS <<< "${ARCH_FLAGS:-}"
INSTALL=1
if [[ "${1:-}" == "--no-install" ]]; then INSTALL=0; fi

echo "==> Building release binary"
swift build -c release "${ARCH_ARGS[@]}"

BIN_PATH="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)/${APP_NAME}"

echo "==> Assembling app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
fi

echo "==> Signing app bundle"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

if [[ "${INSTALL}" == 0 ]]; then
    echo "==> Built ${APP_BUNDLE}"
    exit 0
fi

echo "==> Installing to /Applications"
pkill -x "${APP_NAME}" || true
ditto "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"

echo "==> Launching"
open "/Applications/${APP_NAME}.app"
