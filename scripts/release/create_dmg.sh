#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: create_dmg.sh <version> [output-dir]}"
output_dir="${2:-dist}"
app_name="${APP_NAME:-Typist}"
volume_name="${DMG_VOLUME_NAME:-Typist}"
window_width="${DMG_WINDOW_WIDTH:-640}"
window_height="${DMG_WINDOW_HEIGHT:-420}"
app_icon_x="${DMG_APP_ICON_X:-180}"
app_icon_y="${DMG_APP_ICON_Y:-200}"
apps_icon_x="${DMG_APPLICATIONS_ICON_X:-460}"
apps_icon_y="${DMG_APPLICATIONS_ICON_Y:-200}"
render_background="${DMG_RENDER_BACKGROUND:-1}"

app_bundle="$output_dir/$app_name.app"
dmg_path="$output_dir/$app_name-$version.dmg"
tmp_dir="$(mktemp -d)"
rw_dmg="$tmp_dir/$app_name-$version-rw.dmg"
mount_dir=""
device_id=""
background_path="$tmp_dir/dmg-background.png"
stage_dir="$tmp_dir/stage"

cleanup() {
  if [[ -n "$device_id" ]]; then
    hdiutil detach "$device_id" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ ! -d "$app_bundle" ]]; then
  echo "App bundle not found at $app_bundle"
  exit 1
fi

mkdir -p "$stage_dir"
rm -f "$dmg_path"
cp -R "$app_bundle" "$stage_dir/$app_name.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create \
  -srcfolder "$stage_dir" \
  -volname "$volume_name" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -ov \
  "$rw_dmg"

attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg")"
device_id="$(echo "$attach_output" | awk '/Apple_HFS/ {print $1; exit}')"
mount_dir="$(echo "$attach_output" | awk '/Apple_HFS/ {print $3; exit}')"

if [[ -z "$device_id" || -z "$mount_dir" ]]; then
  echo "Failed to mount temporary DMG."
  exit 1
fi

if [[ "$render_background" == "1" ]]; then
  swift scripts/release/render_dmg_background.swift \
    "$background_path" \
    "$window_width" \
    "$window_height" \
    "$app_icon_x" \
    "$app_icon_y" \
    "$apps_icon_x" \
    "$apps_icon_y"
fi

has_background="false"
if [[ -f "$background_path" ]]; then
  mkdir -p "$mount_dir/.background"
  cp "$background_path" "$mount_dir/.background/background.png"
  has_background="true"
fi

if ! scripts/release/configure_dmg_layout.sh \
  "$volume_name" \
  "$app_name.app" \
  "$app_icon_x" \
  "$app_icon_y" \
  "$apps_icon_x" \
  "$apps_icon_y" \
  "$window_width" \
  "$window_height" \
  "$has_background"; then
  echo "Warning: Finder layout automation failed; continuing with default DMG layout."
fi

sync
hdiutil detach "$device_id" >/dev/null
device_id=""
hdiutil convert \
  "$rw_dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$dmg_path" >/dev/null

echo "Built DMG at $dmg_path"
