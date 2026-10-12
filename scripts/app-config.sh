# Single source of truth for bundle identity, shared by make-app.sh and release.sh.
# Sourced, not executed. Override with env vars when needed.
APP_NAME="Notedrop"
# Open decision (STA-76): kept as the legacy ID so existing Accessibility/Automation grants survive. See docs/release.md.
BUNDLE_ID="${BUNDLE_ID:-app.notedrop.dev}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
MIN_MACOS="14.0"
