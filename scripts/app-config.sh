# Single source of truth for bundle identity, shared by make-app.sh and release.sh.
# Sourced, not executed. Override with env vars when needed.
APP_NAME="plopcut"
# Decided (STA-85): reverse DNS of plopcut.com. The Notedrop-era ID was app.notedrop.dev. See docs/release.md.
BUNDLE_ID="${BUNDLE_ID:-com.plopcut.app}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
MIN_MACOS="14.0"
