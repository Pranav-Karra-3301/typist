#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: update_tap_repo.sh <version> <sha256>}"
sha256="${2:?usage: update_tap_repo.sh <version> <sha256>}"

: "${TAP_REPO:?TAP_REPO is required (owner/homebrew-typist)}"
: "${TAP_REPO_TOKEN:?TAP_REPO_TOKEN is required}"

source_repo="${SOURCE_REPO:-}"
if [[ -z "$source_repo" ]]; then
  echo "SOURCE_REPO is required (owner/repo)."
  exit 1
fi
asset_url="https://github.com/$source_repo/releases/download/v${version}/Typist-${version}.dmg"

if [[ ! "$sha256" =~ ^[A-Fa-f0-9]{64}$ ]]; then
  echo "Invalid SHA256 checksum format: $sha256"
  exit 1
fi

if ! curl -fsIL "$asset_url" >/dev/null; then
  echo "Release asset URL is not reachable: $asset_url"
  exit 1
fi

tap_branch="${TAP_DEFAULT_BRANCH:-main}"
tap_clone_url="https://x-access-token:${TAP_REPO_TOKEN}@github.com/${TAP_REPO}.git"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

git clone --depth 1 --branch "$tap_branch" "$tap_clone_url" "$tmp_dir/tap"
mkdir -p "$tmp_dir/tap/Casks"

cat > "$tmp_dir/tap/Casks/typist.rb" <<EOF
cask "typist" do
  version "$version"
  sha256 "$sha256"

  url "$asset_url"
  name "Typist"
  desc "Privacy-first macOS typing metrics menu bar app"
  homepage "https://github.com/$source_repo"

  depends_on macos: ">= :sonoma"
  app "Typist.app"

  caveats <<~EOS
    Typist beta builds are currently unsigned and not notarized.
    If macOS blocks launch, right-click Typist.app and choose Open, or run:
      xattr -dr com.apple.quarantine /Applications/Typist.app
  EOS
end
EOF

cd "$tmp_dir/tap"
git config user.name "typist-release-bot"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/typist.rb

if git diff --cached --quiet; then
  echo "No tap changes to commit."
  exit 0
fi

git commit -m "chore(cask): release typist $version"
git push origin "HEAD:$tap_branch"

echo "Updated tap repo $TAP_REPO for version $version"
