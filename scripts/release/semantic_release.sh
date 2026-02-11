#!/usr/bin/env bash
set -euo pipefail

npx -y \
  -p semantic-release@24 \
  -p @semantic-release/commit-analyzer@13 \
  -p @semantic-release/release-notes-generator@14 \
  -p @semantic-release/github@11 \
  -p conventional-changelog-conventionalcommits@8 \
  semantic-release "$@"
