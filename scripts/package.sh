#!/bin/bash
# Builds dist/Aeri.app (ad-hoc signed) and dist/Aeri-<version>.zip.
# Usage: scripts/package.sh [version]   (default 0.2.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.2.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Aeri.app"

swift build -c release --build-system native
BIN="$(swift build -c release --build-system native --show-bin-path)/Aeri"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aeri"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Aeri</string>
    <key>CFBundleDisplayName</key><string>Aeri</string>
    <key>CFBundleIdentifier</key><string>com.fayezmuhammed.aeri</string>
    <key>CFBundleExecutable</key><string>Aeri</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Fayez Muhammed. MIT License.</string>
    <key>NSAppleEventsUsageDescription</key><string>Aeri shows what's playing in Music, Spotify and your browser, and lets you control playback from the notch.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no Apple Developer account). Users approve the first launch via
# System Settings > Privacy & Security > Open Anyway.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

ZIP="dist/Aeri-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Aeri"))"
echo "$ZIP"
shasum -a 256 "$ZIP"
