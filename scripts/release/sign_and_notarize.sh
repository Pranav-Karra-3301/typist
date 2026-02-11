#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?usage: sign_and_notarize.sh <app-bundle-path> <dmg-path>}"
dmg_path="${2:?usage: sign_and_notarize.sh <app-bundle-path> <dmg-path>}"

: "${APPLE_DEVELOPER_ID_CERT_P12_BASE64:?APPLE_DEVELOPER_ID_CERT_P12_BASE64 is required}"
: "${APPLE_DEVELOPER_ID_CERT_PASSWORD:?APPLE_DEVELOPER_ID_CERT_PASSWORD is required}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required}"
: "${APPLE_API_PRIVATE_KEY_P8:?APPLE_API_PRIVATE_KEY_P8 is required}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
  if [[ -n "${keychain_path:-}" && -f "$keychain_path" ]]; then
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cert_path="$tmp_dir/dev_id.p12"
api_key_path="$tmp_dir/AuthKey_$APPLE_API_KEY_ID.p8"
keychain_path="$tmp_dir/typist-build.keychain-db"
keychain_password="$(uuidgen)"

echo "$APPLE_DEVELOPER_ID_CERT_P12_BASE64" | base64 -D > "$cert_path"
printf '%s' "$APPLE_API_PRIVATE_KEY_P8" > "$api_key_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$cert_path" -k "$keychain_path" -P "$APPLE_DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path"
security list-keychains -d user -s "$keychain_path" login.keychain-db

identity="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -p codesigning -v "$keychain_path" | sed -nE 's/.*"([^"]*Developer ID Application[^"]*)".*/\1/p' | head -n 1)"
fi

if [[ -z "$identity" ]]; then
  echo "Unable to determine Developer ID Application identity."
  exit 1
fi

codesign --force --deep --options runtime --timestamp --keychain "$keychain_path" --sign "$identity" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

codesign --force --options runtime --timestamp --keychain "$keychain_path" --sign "$identity" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"

xcrun notarytool submit "$dmg_path" \
  --key "$api_key_path" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"
