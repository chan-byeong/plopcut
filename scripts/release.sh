#!/bin/sh
# Release pipeline: build -> sign -> DMG -> notarize -> staple -> verify -> appcast.
# Usage: scripts/release.sh [--check] [--adhoc]
#   --check  print the plan and report which prerequisites/env vars are missing; builds nothing.
#   --adhoc  beta build: release build + ad-hoc signed DMG, no notarization. Gatekeeper rejects it, so it is only for
#            testers who accept the unsigned install steps in the README (docs/release.md, "Beta channel").
# Env (never commit values):
#   DEVELOPER_ID_IDENTITY  e.g. "Developer ID Application: Name (TEAMID)"  (required unless --adhoc)
#   NOTARY_PROFILE         keychain profile created with `xcrun notarytool store-credentials`  (required unless --adhoc)
#   SPARKLE_PUBLIC_KEY     EdDSA public key for in-app updates (required unless --adhoc; normally set in app-config.sh).
#                          The private key is read from the login keychain by generate_appcast.
#   RELEASE_NOTES          optional Markdown file shown in the update window
#   APP_VERSION, APP_BUILD, APP_CHANNEL, BUNDLE_ID  optional overrides of scripts/app-config.sh
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

APP="$ROOT/PlopcutApp/.build/$APP_NAME.app"
OUT="$ROOT/dist"
DMG="$OUT/$APP_NAME-$APP_VERSION${APP_CHANNEL:+-$APP_CHANNEL}.dmg"
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
PROFILE="${NOTARY_PROFILE:-}"

if [ "$MODE" = check ]; then
  missing=0
  echo "bundle id : $BUNDLE_ID"; echo "version   : $APP_VERSION ($APP_BUILD) channel: ${APP_CHANNEL:-official}"; echo "min macOS : $MIN_MACOS"; echo "output    : $DMG"
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
  [ -n "$SPARKLE_PUBLIC_KEY" ] && echo "env ok    : SPARKLE_PUBLIC_KEY set" || { echo "env MISSING: SPARKLE_PUBLIC_KEY"; missing=1; }
  [ "$missing" = 0 ] && echo "ready for a full release" || echo "not ready for a full release (use --adhoc to rehearse locally)"
  exit "$missing"
fi

if [ "$MODE" = release ]; then
  [ -n "$IDENTITY" ] || { echo "DEVELOPER_ID_IDENTITY is required (or use --adhoc)" >&2; exit 1; }
  [ -n "$PROFILE" ] || { echo "NOTARY_PROFILE is required (or use --adhoc)" >&2; exit 1; }
  # A release without the key would ship with no updater, and its users would have to update by hand again.
  [ -n "$SPARKLE_PUBLIC_KEY" ] || { echo "SPARKLE_PUBLIC_KEY is required (or use --adhoc)" >&2; exit 1; }
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
  # Fixed-name copy for the GitHub Release: the site links to releases/latest/download/Plopcut.dmg.
  cp "$DMG" "$OUT/$APP_NAME.dmg"
  echo "release asset: $OUT/$APP_NAME.dmg"
  # The appcast item points at the versioned DMG of this release's tag; earlier items keep their own URLs (PLO-118).
  # generate_appcast signs the DMG with the EdDSA private key from the login keychain.
  echo "==> appcast"
  TAG="v$APP_VERSION${APP_CHANNEL:+-$APP_CHANNEL}"
  FEED="$STAGE/feed"
  mkdir -p "$FEED"
  if [ -f "$ROOT/site/appcast.xml" ]; then cp "$ROOT/site/appcast.xml" "$FEED/"; fi
  cp "$DMG" "$FEED/"
  if [ -n "${RELEASE_NOTES:-}" ]; then cp "$RELEASE_NOTES" "$FEED/$(basename "$DMG" .dmg).md"; fi
  "$ROOT/PlopcutApp/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --embed-release-notes \
    --download-url-prefix "https://github.com/chan-byeong/plopcut/releases/download/$TAG/" "$FEED"
  cp "$FEED/appcast.xml" "$ROOT/site/appcast.xml"
  echo "appcast: site/appcast.xml (commit it after the GitHub Release $TAG is published)"
else
  echo "ad-hoc beta build: skipped notarize/staple/spctl (Gatekeeper rejects it; testers use Open Anyway)"
  hdiutil verify "$DMG" >/dev/null && echo "dmg verifies"
fi
echo "$DMG"
