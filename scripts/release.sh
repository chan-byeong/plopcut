#!/bin/sh
# Release pipeline: build -> sign -> DMG -> notarize -> staple -> verify.
# Usage: scripts/release.sh [--check] [--adhoc]
#   --check  print the plan and report which prerequisites/env vars are missing; builds nothing.
#   --adhoc  local rehearsal: release build + ad-hoc signed DMG, no notarization (not distributable).
# Env (never commit values):
#   DEVELOPER_ID_IDENTITY  e.g. "Developer ID Application: Name (TEAMID)"  (required unless --adhoc)
#   NOTARY_PROFILE         keychain profile created with `xcrun notarytool store-credentials`  (required unless --adhoc)
#   APP_VERSION, APP_BUILD, BUNDLE_ID  optional overrides of scripts/app-config.sh
set -eu
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS/app-config.sh"
ROOT="$SCRIPTS/.."
MODE=release
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --adhoc) MODE=adhoc ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

APP="$ROOT/NotedropApp/.build/$APP_NAME.app"
OUT="$ROOT/dist"
DMG="$OUT/$APP_NAME-$APP_VERSION.dmg"
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
PROFILE="${NOTARY_PROFILE:-}"

if [ "$MODE" = check ]; then
  missing=0
  echo "bundle id : $BUNDLE_ID"; echo "version   : $APP_VERSION ($APP_BUILD)"; echo "min macOS : $MIN_MACOS"; echo "output    : $DMG"
  for t in swift codesign hdiutil xcrun spctl vtool; do
    command -v "$t" >/dev/null 2>&1 && echo "tool ok   : $t" || { echo "tool MISSING: $t"; missing=1; }
  done
  xcrun --find notarytool >/dev/null 2>&1 && echo "tool ok   : notarytool" || { echo "tool MISSING: notarytool"; missing=1; }
  xcrun --find stapler >/dev/null 2>&1 && echo "tool ok   : stapler" || { echo "tool MISSING: stapler"; missing=1; }
  if [ -n "$IDENTITY" ]; then
    security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null \
      && echo "identity ok: found in keychain" || { echo "identity MISSING: not in keychain"; missing=1; }
  else echo "env MISSING: DEVELOPER_ID_IDENTITY"; missing=1; fi
  [ -n "$PROFILE" ] && echo "env ok    : NOTARY_PROFILE set" || { echo "env MISSING: NOTARY_PROFILE"; missing=1; }
  [ "$missing" = 0 ] && echo "ready for a full release" || echo "not ready for a full release (use --adhoc to rehearse locally)"
  exit "$missing"
fi

if [ "$MODE" = release ]; then
  [ -n "$IDENTITY" ] || { echo "DEVELOPER_ID_IDENTITY is required (or use --adhoc)" >&2; exit 1; }
  [ -n "$PROFILE" ] || { echo "NOTARY_PROFILE is required (or use --adhoc)" >&2; exit 1; }
  SIGN_IDENTITY="$IDENTITY"
else
  SIGN_IDENTITY="-"
fi
export SIGN_IDENTITY

echo "==> build + sign $APP_NAME.app"
"$SCRIPTS/make-app.sh" release
codesign --verify --deep --strict "$APP"

echo "==> DMG"
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
if [ "$MODE" = release ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  echo "==> notarize (waits for Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  echo "==> staple"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "==> verify"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
  spctl --assess --type execute -vv "$APP"
else
  echo "ad-hoc rehearsal: skipped notarize/staple/spctl (would be rejected by Gatekeeper)"
  hdiutil verify "$DMG" >/dev/null && echo "dmg verifies"
fi
echo "$DMG"
