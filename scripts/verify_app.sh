#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/Launchd\\ TOC.app" >&2
  exit 64
fi

app_path="$1"
binary_path="$app_path/Contents/MacOS/Launchd TOC"

/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$app_path"
architectures="$(/usr/bin/lipo -archs "$binary_path")"
[[ "$architectures" == *"arm64"* && "$architectures" == *"x86_64"* ]]

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
[[ "$bundle_id" == "com.litsquare.launchdtoc" ]]

signature_info="$(/usr/bin/codesign -dvvv "$app_path" 2>&1)"
[[ "$signature_info" == *"(runtime)"* ]]
[[ "$signature_info" == *"TeamIdentifier=N9U29A4T8J"* ]]

entitlements="$(/usr/bin/codesign -d --entitlements - "$app_path" 2>&1 || true)"
if [[ "$entitlements" == *"com.apple.security.app-sandbox"* ]]; then
  echo "Unexpected App Sandbox entitlement" >&2
  exit 1
fi

echo "Verified $architectures app without an App Sandbox entitlement."
