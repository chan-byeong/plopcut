#!/bin/sh
# Wraps the SwiftPM executable in a minimal Plopcut.app so macOS grants permissions to a stable bundle ID.
# Usage: scripts/make-app.sh [debug|release]   ->   PlopcutApp/.build/Plopcut.app
#        release builds a universal binary (Apple Silicon + Intel); debug builds the host architecture only.
# Env: SIGN_IDENTITY (default "-" = ad-hoc). When set to a real identity, signs with Hardened Runtime,
#      entitlements and a secure timestamp. Identity/version come from scripts/app-config.sh.
set -eu
CONFIG="${1:-debug}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS/app-config.sh"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
cd "$SCRIPTS/../PlopcutApp"
# Two --arch flags switch SwiftPM to the Xcode build system, which writes to a different folder; ask for it.
ARCH_FLAGS=""
if [ "$CONFIG" = release ]; then ARCH_FLAGS="--arch arm64 --arch x86_64"; fi
swift build -c "$CONFIG" $ARCH_FLAGS
BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)"
APP=.build/$APP_NAME.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Plopcut" "$APP/Contents/MacOS/plopcut"
# App icon, reused for the Dock and the empty Library logo (Bundle.main "AppIcon").
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles of dependencies (HighlighterSwift's highlight.js and themes, PLO-101). Their Bundle.module
# accessor looks in Bundle.main.resourceURL first; without the bundle it stops the app with a fatal error.
for bundle in "$BIN"/*.bundle; do
  if [ -d "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
# Licenses of the bundled open-source packages (PLO-106); their licenses require shipping these notices.
cp ../THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
# SwiftPM does not compile asset catalogs; actool builds Assets.car so NSAccentColorName finds AccentColor (spec 5).
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target "$MIN_MACOS" --accent-color AccentColor \
  --output-partial-info-plist .build/assets-info.plist >/dev/null
# SwiftPM stamps the SDK as the deployment target (14.0), which keeps macOS on the pre-Liquid-Glass window style.
# Restamp with the real SDK so system chrome matches native apps.
SDK_VERSION="$(xcrun --show-sdk-version)"
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/plopcut" "$APP/Contents/MacOS/plopcut"
if [ "$CONFIG" = release ]; then
  ARCHS="$(lipo -archs "$APP/Contents/MacOS/plopcut")"
  case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "expected a universal binary, got: $ARCHS" >&2; exit 1 ;;
  esac
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>CFBundleExecutable</key><string>plopcut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Plopcut reads the browser URL of the page you capture from.</string>
</dict></plist>
PLIST
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
else
  codesign --force --options runtime --timestamp --entitlements "$SCRIPTS/plopcut.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
fi
echo "$APP"
