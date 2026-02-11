#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: build_app_bundle.sh <version> <build-number> [output-dir]}"
build_number="${2:?usage: build_app_bundle.sh <version> <build-number> [output-dir]}"
output_dir="${3:-dist}"

app_name="${APP_NAME:-Typist}"
binary_name="${APP_EXECUTABLE:-TypistMenuBar}"
bundle_id="${APP_BUNDLE_ID:-com.pranavkarra.typist}"
minimum_system_version="${MINIMUM_SYSTEM_VERSION:-14.0}"
icon_source="${APP_ICON_SOURCE:-scripts/release/assets/app-icon.png}"
icon_name="AppIcon"
round_icon="${APP_ICON_ROUND_CORNERS:-1}"
icon_corner_radius="${APP_ICON_CORNER_RADIUS:-0.22}"
update_repo="${SOURCE_REPO:-pranavkarra/typist}"
releases_url="${TYPIST_RELEASES_URL:-https://github.com/$update_repo/releases}"

swift build -c release --product "$binary_name"
bin_path="$(swift build -c release --show-bin-path | tail -n 1)"
binary_path="$bin_path/$binary_name"

if [[ ! -x "$binary_path" ]]; then
  echo "Binary not found at $binary_path"
  exit 1
fi

app_bundle="$output_dir/$app_name.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
plist_path="$contents_dir/Info.plist"

rm -rf "$app_bundle"
mkdir -p "$macos_dir" "$resources_dir"

cp "$binary_path" "$macos_dir/$app_name"

if [[ -f "$icon_source" ]]; then
  icon_tmp_dir="$(mktemp -d "$output_dir/${icon_name}.icon.XXXXXX")"
  iconset_dir="$icon_tmp_dir/${icon_name}.iconset"
  rounded_icon_source="$icon_tmp_dir/${icon_name}-rounded.png"
  icon_input="$icon_source"
  mkdir -p "$iconset_dir"
  trap 'rm -rf "$icon_tmp_dir"' EXIT

  if [[ "$round_icon" == "1" ]]; then
    swift scripts/release/round_icon.swift "$icon_source" "$rounded_icon_source" "$icon_corner_radius"
    icon_input="$rounded_icon_source"
  fi

  sips -z 16 16 "$icon_input" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$icon_input" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$icon_input" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$icon_input" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$icon_input" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$icon_input" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$icon_input" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$icon_input" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$icon_input" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$icon_input" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset_dir" -o "$resources_dir/${icon_name}.icns"
  rm -rf "$icon_tmp_dir"
  trap - EXIT
fi

cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleExecutable</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleIconFile</key>
    <string>${icon_name}.icns</string>
    <key>NSApplicationIconFile</key>
    <string>${icon_name}.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>$minimum_system_version</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>TypistUpdateRepo</key>
    <string>$update_repo</string>
    <key>TypistReleasesURL</key>
    <string>$releases_url</string>
</dict>
</plist>
EOF

echo "Built app bundle at $app_bundle"
