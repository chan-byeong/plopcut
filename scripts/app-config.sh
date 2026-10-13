# Single source of truth for bundle identity, shared by make-app.sh and release.sh.
# Sourced, not executed. Override with env vars when needed.
APP_NAME="plopcut"
# Decided (STA-85): reverse DNS of plopcut.com. The Notedrop-era ID was app.notedrop.dev. See docs/release.md.
BUNDLE_ID="${BUNDLE_ID:-com.plopcut.app}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
# Release channel label for the DMG name only (plopcut-0.1.0-beta.1.dmg). Info.plist keeps the plain APP_VERSION, because
# CFBundleShortVersionString must be dotted integers. Set it empty (APP_CHANNEL=) for the official release (STA-88).
APP_CHANNEL="${APP_CHANNEL-beta.1}"
MIN_MACOS="14.0"
