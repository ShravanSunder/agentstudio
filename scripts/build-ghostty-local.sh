#!/usr/bin/env bash
set -euo pipefail

project_root="${PROJECT_ROOT:-$(pwd)}"
bash "$project_root/scripts/vendor-worktree.sh" require-producer

(
  cd "$project_root/vendor/ghostty"
  # Keep terminal rendering optimized even when the Swift host is a Debug build.
  # Ghostty's Debug integrity checks hold its terminal lock during redraws.
  bash "$project_root/scripts/zig.sh" build -Doptimize=ReleaseFast -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=universal
)
