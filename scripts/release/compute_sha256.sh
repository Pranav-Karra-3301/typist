#!/usr/bin/env bash
set -euo pipefail

file_path="${1:?usage: compute_sha256.sh <file-path>}"

shasum -a 256 "$file_path" | awk '{print $1}'
