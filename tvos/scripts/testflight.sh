#!/bin/bash
# testflight.sh — archive a Couch Suite app for tvOS and (optionally) upload to TestFlight.
#
#   scripts/testflight.sh <app-folder> [--upload]
#   scripts/testflight.sh rabbit-ears              # archive + export signed .ipa
#   scripts/testflight.sh rabbit-ears --upload     # archive + upload to App Store Connect
#   scripts/testflight.sh all --upload             # all five apps
#
# Signing configuration (either source):
#   - environment: COUCH_TEAM_ID=ABCDE12345
#   - tvos/signing.env (gitignored):  COUCH_TEAM_ID=ABCDE12345
#
# Upload auth: either be signed into Xcode with your Apple ID (Settings →
# Accounts), or provide an App Store Connect API key in signing.env:
#   ASC_KEY_ID=XXXXXXXXXX  ASC_ISSUER_ID=uuid  ASC_KEY_PATH=/path/AuthKey_XXXX.p8
#
# Build number is derived from git history (commit count), so every archive from
# a new commit gets a strictly increasing CFBundleVersion — no manual bumping.
set -euo pipefail

TVOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPS=(rabbit-ears darkroom nine blockhead cartridge)

[[ -f "$TVOS_DIR/signing.env" ]] && source "$TVOS_DIR/signing.env"

usage() { sed -n '2,17p' "$0"; exit 1; }
[[ $# -ge 1 ]] || usage

TARGET="$1"; shift
UPLOAD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload) UPLOAD=true ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

: "${COUCH_TEAM_ID:?Set COUCH_TEAM_ID (env or tvos/signing.env) to your Apple Developer Team ID}"

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }

BUILD_NUMBER=$(git -C "$TVOS_DIR" rev-list --count HEAD)

# API-key auth flags for xcodebuild, if an ASC key is configured.
AUTH_FLAGS=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH_FLAGS=(-authenticationKeyID "$ASC_KEY_ID"
              -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID required with ASC_KEY_ID}"
              -authenticationKeyPath "${ASC_KEY_PATH:?ASC_KEY_PATH required with ASC_KEY_ID}")
fi

archive_one() {
  local folder="$1"
  local dir="$TVOS_DIR/$folder"
  [[ -f "$dir/project.yml" ]] || { echo "No project.yml in $folder"; exit 1; }
  local scheme
  scheme=$(awk '/^name:/ {print $2; exit}' "$dir/project.yml")
  local dist="$dir/dist"
  local archive="$dist/$scheme.xcarchive"

  echo "──── $scheme ($folder) — build $BUILD_NUMBER ────"
  (cd "$dir" && xcodegen generate)

# The archive is built unsigned: signing it with an automatic *development*
  # profile would require a registered Apple TV on the team. Distribution
  # signing happens at export instead, where App Store profiles need no devices.
  xcodebuild archive \
    -project "$dir/$scheme.xcodeproj" \
    -scheme "$scheme" \
    -destination 'generic/platform=tvOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="$COUCH_TEAM_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  [[ -d "$archive" ]] || { echo "Archive failed for $scheme"; exit 1; }

  # An unsigned archive carries no entitlements, and export derives the final
  # entitlements from the archived binary — so apps that need iCloud KVS
  # (Darkroom/Nine/Blockhead) would silently lose it. Ad-hoc re-sign the
  # archived app with its entitlements file so export preserves them.
  local ents="$dir/$scheme.entitlements"
  if [[ -f "$ents" ]]; then
    local archived_app="$archive/Products/Applications/$scheme.app"
    local bundle_id
    bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$archived_app/Info.plist")
    # Resolve the build-setting placeholders XcodeGen leaves in the file;
    # xcodebuild would normally expand these during its own codesign step.
    sed -e "s/\$(TeamIdentifierPrefix)/$COUCH_TEAM_ID./g" \
        -e "s/\$(CFBundleIdentifier)/$bundle_id/g" \
        "$ents" > "$dist/resolved.entitlements"
    codesign --force -s - --entitlements "$dist/resolved.entitlements" "$archived_app"
    echo "· re-signed archive ad-hoc with resolved $(basename "$ents")"
  fi

  local dest="export"
  $UPLOAD && dest="upload"
  cat > "$dist/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$dest</string>
	<key>teamID</key>
	<string>$COUCH_TEAM_ID</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$dist/ExportOptions.plist" \
    -exportPath "$dist" \
    -allowProvisioningUpdates "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}"

  if $UPLOAD; then
    echo "✓ $scheme build $BUILD_NUMBER uploaded to App Store Connect (processing takes ~5-15 min)"
  else
    echo "✓ $scheme exported: $(ls "$dist"/*.ipa 2>/dev/null || echo "$dist")"
  fi
}

if [[ "$TARGET" == "all" ]]; then
  for app in "${APPS[@]}"; do archive_one "$app"; done
else
  archive_one "$TARGET"
fi
