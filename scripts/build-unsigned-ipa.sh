#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $(uname -s) != Darwin ]] || ! xcodebuild -version; then
  printf 'Building the IPA requires macOS with full Xcode selected.\n' >&2
  exit 1
fi

mkdir -p build/artifacts
xcodebuild build -project iMask.xcodeproj -scheme iMask -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device-derived-data \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''

stage=$(mktemp -d "${TMPDIR:-/tmp}/imask-ipa.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT

app="$stage/Payload/iMask.app"
widget="$app/PlugIns/iMaskWidget.appex"
mkdir -p "$stage/Payload"
ditto --norsrc build/device-derived-data/Build/Products/Release-iphoneos/iMask.app "$app"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"
}

if [[ $(plist_value "$app" NSSupportsLiveActivities) != true ]] ||
   [[ $(plist_value "$widget" NSExtension:NSExtensionPointIdentifier) != com.apple.widgetkit-extension ]] ||
   [[ $(plist_value "$widget" CFBundleIdentifier) != "$(plist_value "$app" CFBundleIdentifier).widget" ]]; then
  printf 'Invalid Live Activity app or embedded Widget Extension configuration.\n' >&2
  exit 1
fi

for bundle in "$app" "$widget"; do
  executable="$bundle/$(plist_value "$bundle" CFBundleExecutable)"
  if [[ ! -x "$executable" ]] ||
     [[ $(plist_value "$bundle" CFBundleSupportedPlatforms:0) != iPhoneOS ]] ||
     ! xcrun lipo -verify_arch arm64 "$executable"; then
    printf 'Expected an arm64 iPhoneOS executable at %s\n' "$executable" >&2
    exit 1
  fi

  if [[ -e "$bundle/embedded.mobileprovision" || -d "$bundle/_CodeSignature" ]]; then
    printf 'Unexpected provisioning profile or bundle signature in %s\n' "$bundle" >&2
    exit 1
  fi
done

(
  cd "$stage"
  zip -qry -X iMask-unsigned.ipa Payload
  unzip -tq iMask-unsigned.ipa
  shasum -a 256 iMask-unsigned.ipa > iMask-unsigned.ipa.sha256
)
mv "$stage/iMask-unsigned.ipa" "$stage/iMask-unsigned.ipa.sha256" build/artifacts/
printf 'Unsigned IPA, for re-signing: %s/build/artifacts/iMask-unsigned.ipa\n' "$PWD"
