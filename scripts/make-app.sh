#!/bin/sh
# Wraps the SwiftPM executable in a minimal plopcut.app so macOS grants permissions to a stable bundle ID.
# Usage: scripts/make-app.sh [debug|release]   ->   PlopcutApp/.build/plopcut.app
# Env: SIGN_IDENTITY (default "-" = ad-hoc). When set to a real identity, signs with Hardened Runtime,
#      entitlements and a secure timestamp. Identity/version come from scripts/app-config.sh.
set -eu
CONFIG="${1:-debug}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS/app-config.sh"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
cd "$SCRIPTS/../PlopcutApp"
swift build -c "$CONFIG"
APP=.build/plopcut.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Plopcut" "$APP/Contents/MacOS/plopcut"
# App icon, reused for the Dock and the empty Library logo (Bundle.main "AppIcon").
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM stamps the SDK as the deployment target (14.0), which keeps macOS on the pre-Liquid-Glass window style.
# Restamp with the real SDK so system chrome matches native apps.
SDK_VERSION="$(xcrun --show-sdk-version)"
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/plopcut" "$APP/Contents/MacOS/plopcut"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>plopcut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>plopcut reads the browser URL of the page you capture from.</string>
</dict></plist>
PLIST
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
else
  codesign --force --options runtime --timestamp --entitlements "$SCRIPTS/plopcut.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
fi
echo "$APP"
