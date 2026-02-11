#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: create_dmg.sh <version> [output-dir]}"
output_dir="${2:-dist}"
app_name="${APP_NAME:-Typist}"
volume_name="${DMG_VOLUME_NAME:-Typist}"

app_bundle="$output_dir/$app_name.app"
dmg_path="$output_dir/$app_name-$version.dmg"

if [[ ! -d "$app_bundle" ]]; then
  echo "App bundle not found at $app_bundle"
  exit 1
fi

rm -f "$dmg_path"
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$app_bundle" \
  -ov \
  -format UDZO \
  "$dmg_path"

echo "Built DMG at $dmg_path"
