#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: build_app_bundle.sh <version> <build-number> [output-dir]}"
build_number="${2:?usage: build_app_bundle.sh <version> <build-number> [output-dir]}"
output_dir="${3:-dist}"

app_name="${APP_NAME:-Typist}"
binary_name="${APP_EXECUTABLE:-TypistMenuBar}"
bundle_id="${APP_BUNDLE_ID:-com.pranavkarra.typist}"
minimum_system_version="${MINIMUM_SYSTEM_VERSION:-14.0}"

bin_path="$(swift build -c release --product "$binary_name" --show-bin-path | tail -n 1)"
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
    <key>LSMinimumSystemVersion</key>
    <string>$minimum_system_version</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Built app bundle at $app_bundle"
