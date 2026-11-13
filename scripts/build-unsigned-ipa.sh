#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -d /Applications/Xcode_27.2.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer
fi

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
mkdir -p "$stage/Payload"
ditto --norsrc build/device-derived-data/Build/Products/Release-iphoneos/iMask.app "$app"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"
}

if [[ $(plist_value "$app" CADisableMinimumFrameDurationOnPhone) != true ]] ||
   [[ $(plist_value "$app" UIBackgroundModes:0) != audio ]] ||
   [[ ! -f "$app/NOTICE" || ! -f "$app/slience.mp3" || ! -f "$app/LICENSE" ]]; then
  printf 'Invalid high-refresh PiP configuration or missing attribution.\n' >&2
  exit 1
fi

widget="$app/PlugIns/iMaskWidget.appex"
if [[ $(plist_value "$app" NSSupportsLiveActivities) != true ]] ||
   [[ $(plist_value "$widget" NSExtension:NSExtensionPointIdentifier) != com.apple.widgetkit-extension ]] ||
   [[ $(plist_value "$widget" CFBundleIdentifier) != "$(plist_value "$app" CFBundleIdentifier).widget" ]]; then
  printf 'Invalid embedded Live Activity extension.\n' >&2
  exit 1
fi
xcrun lipo "$widget/$(plist_value "$widget" CFBundleExecutable)" -verify_arch arm64

executable="$app/$(plist_value "$app" CFBundleExecutable)"
if [[ ! -x "$executable" ]] ||
   [[ $(plist_value "$app" CFBundleSupportedPlatforms:0) != iPhoneOS ]] ||
   ! xcrun lipo "$executable" -verify_arch arm64; then
  printf 'Expected an arm64 iPhoneOS executable at %s\n' "$executable" >&2
  exit 1
fi

if [[ -e "$app/embedded.mobileprovision" || -d "$app/_CodeSignature" ||
      -e "$widget/embedded.mobileprovision" || -d "$widget/_CodeSignature" ]]; then
  printf 'Unexpected provisioning profile or bundle signature in %s\n' "$app" >&2
  exit 1
fi

(
  cd "$stage"
  zip -qry -X iMask-unsigned.ipa Payload
  unzip -tq iMask-unsigned.ipa
  shasum -a 256 iMask-unsigned.ipa > iMask-unsigned.ipa.sha256
)
mv "$stage/iMask-unsigned.ipa" "$stage/iMask-unsigned.ipa.sha256" build/artifacts/
printf 'Unsigned IPA, for re-signing: %s/build/artifacts/iMask-unsigned.ipa\n' "$PWD"
