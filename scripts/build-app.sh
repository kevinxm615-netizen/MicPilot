#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/../MicPilot.app"
BUILD_DIR="$ROOT_DIR/.build/release"

cd "$ROOT_DIR"
swift build -c release --build-system native

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/AudioInputSwitcher" "$APP_DIR/Contents/MacOS/AudioInputSwitcher"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/AudioInputSwitcher"

codesign --force --sign - "$APP_DIR"
echo "Built $APP_DIR"
