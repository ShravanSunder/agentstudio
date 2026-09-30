#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

bash "$PROJECT_ROOT/scripts/vendor-worktree.sh" verify
source "$PROJECT_ROOT/scripts/swift-build-slot.sh"
swift_build_slot_acquire build "mise run build-bridge-development-server"
trap swift_build_slot_release EXIT

echo "[build-bridge-development-server] BUILD_PATH=$SWIFT_BUILD_DIR"
compiler_statistics_arguments=()
if [ -n "${SWIFT_BUILD_STATS_DIR:-}" ]; then
  case "$SWIFT_BUILD_STATS_DIR" in
    /*)
      if mkdir -p "$SWIFT_BUILD_STATS_DIR" 2>/dev/null; then
        compiler_statistics_arguments=(-Xswiftc -stats-output-dir -Xswiftc "$SWIFT_BUILD_STATS_DIR")
      fi
      ;;
  esac
  if [ "${#compiler_statistics_arguments[@]}" -eq 0 ]; then
    echo "[build-bridge-development-server] warning: compiler statistics disabled (directory must be writable and absolute)" >&2
  fi
fi
# Match the publisher's effective compiler flags even when the Vite supervisor
# invokes this narrower product build again later in the same CI job.
# shellcheck disable=SC2086
swift build \
  ${EXTRA_SWIFT_TEST_ARGS:-} \
  --build-path "$SWIFT_BUILD_DIR" \
  --product agentstudio-bridge-dev-server \
  "${compiler_statistics_arguments[@]}"

swift_bin_path="$(swift build --build-path "$SWIFT_BUILD_DIR" --show-bin-path)"
source_executable="$swift_bin_path/agentstudio-bridge-dev-server"
artifact_directory="$PROJECT_ROOT/.build-bridge-development-server"
artifact_executable="$artifact_directory/agentstudio-bridge-dev-server"

mkdir -p "$artifact_directory"
temporary_executable="$(mktemp "$artifact_directory/.agentstudio-bridge-dev-server.XXXXXX")"
if ! install -m 755 "$source_executable" "$temporary_executable"; then
  rm -f "$temporary_executable"
  exit 1
fi
mv -f "$temporary_executable" "$artifact_executable"

echo "[build-bridge-development-server] executable=$artifact_executable"
