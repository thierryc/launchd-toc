#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/to/Launchd\\ TOC.app version output-directory" >&2
  exit 64
fi

app_path="$1"
version="$2"
output_directory="$3"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 66
fi

mkdir -p "$output_directory"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/launchd-toc-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

/usr/bin/ditto "$app_path" "$staging_directory/Launchd TOC.app"
/bin/ln -s /Applications "$staging_directory/Applications"

dmg_path="$output_directory/Launchd-TOC-${version}-universal.dmg"
/usr/bin/hdiutil create \
  -volname "Launchd TOC" \
  -srcfolder "$staging_directory" \
  -ov \
  -format UDZO \
  "$dmg_path"

echo "$dmg_path"
