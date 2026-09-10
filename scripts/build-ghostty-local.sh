#!/usr/bin/env bash
set -euo pipefail

project_root="${PROJECT_ROOT:-$(pwd)}"
bash "$project_root/scripts/vendor-worktree.sh" require-producer

(
  cd "$project_root/vendor/ghostty"
  bash "$project_root/scripts/zig.sh" build -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=universal
)
