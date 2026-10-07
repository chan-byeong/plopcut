#!/bin/sh
# Wraps the SwiftPM executable in a minimal Notedrop.app so macOS grants permissions to a stable bundle ID.
# Usage: scripts/make-app.sh [debug|release]   ->   NotedropApp/.build/Notedrop.app
set -eu
CONFIG="${1:-debug}"
cd "$(dirname "$0")/../NotedropApp"
swift build -c "$CONFIG"
APP=.build/Notedrop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/Notedrop" "$APP/Contents/MacOS/Notedrop"
# SwiftPM stamps the SDK as the deployment target (14.0), which keeps macOS on the pre-Liquid-Glass window style.
# Restamp with the real SDK so system chrome matches native apps.
SDK_VERSION="$(xcrun --show-sdk-version)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Notedrop" "$APP/Contents/MacOS/Notedrop"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.notedrop.dev</string>
  <key>CFBundleName</key><string>Notedrop</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
  <key>CFBundleExecutable</key><string>Notedrop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Notedrop reads the browser URL of the page you capture from.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
