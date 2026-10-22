# Single source of truth for bundle identity, shared by make-app.sh and release.sh.
# Sourced, not executed. Override with env vars when needed.
# Display name (PLO-107): the bundle, Finder, menu and DMG name. On-disk folders, the log, the executable and the
# bundle ID stay lowercase so saved drops, settings and granted permissions keep working.
APP_NAME="Plopcut"
# Decided (STA-85): reverse DNS of plopcut.com. The Notedrop-era ID was app.notedrop.dev. See docs/release.md.
BUNDLE_ID="${BUNDLE_ID:-com.plopcut.app}"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_BUILD="${APP_BUILD:-3}"
# Release channel label for the DMG name only (Plopcut-0.2.0-beta.1.dmg). Info.plist keeps the plain APP_VERSION, because
# CFBundleShortVersionString must be dotted integers. Set it empty (APP_CHANNEL=) for the official release (STA-88).
APP_CHANNEL="${APP_CHANNEL-rc.1}"
MIN_MACOS="14.0"
