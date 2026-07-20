#!/bin/bash
set -Eeuo pipefail

umask 077

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STANDARD_DEBUG_RUNNER="$PROJECT_ROOT/scripts/run-debug-observability.sh"
DEFAULT_OBSERVABILITY_STATE_FILE="$PROJECT_ROOT/tmp/debug-observability/latest-observability.env"
DEFAULT_JOURNEY_STATE_FILE="$PROJECT_ROOT/tmp/debug-observability/latest-bridge-packaged-product-journey.env"
OBSERVABILITY_STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$DEFAULT_OBSERVABILITY_STATE_FILE}"
JOURNEY_STATE_FILE="${AGENTSTUDIO_BRIDGE_PACKAGED_JOURNEY_STATE_FILE:-$DEFAULT_JOURNEY_STATE_FILE}"
GIT_BIN="${AGENTSTUDIO_BRIDGE_PACKAGED_PRODUCT_JOURNEY_GIT_BIN:-/usr/bin/git}"
SHASUM_BIN="${AGENTSTUDIO_BRIDGE_PACKAGED_PRODUCT_JOURNEY_SHASUM_BIN:-/usr/bin/shasum}"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: run-bridge-packaged-product-journey.sh [--dry-run]

Creates the disposable current-run fixture and delegates the packaged app launch
to the standard AgentStudio debug observability runner. The launched app and its
fixture remain available for the separate verifier and PID-targeted visual proof.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$dry_run" = true ]; then
  echo "dry-run contract: delegates to the standard debug observability runner"
  echo "dry-run contract: requires strict LaunchServices with direct fallback disabled"
  echo "dry-run contract: creates a private disposable hierarchical Git fixture outside the repo"
  echo "dry-run contract: starts with 257 initial Review diffs across the hierarchical fixture"
  echo "dry-run contract: starts the bridge-product-paint-correlation diagnostic with one-shot IPC escrow"
  echo "dry-run contract: preserves the fixture and app for verification"
  exit 0
fi

if [ ! -x "$STANDARD_DEBUG_RUNNER" ]; then
  echo "standard debug observability runner is not executable: $STANDARD_DEBUG_RUNNER" >&2
  exit 1
fi
if [ ! -x "$GIT_BIN" ]; then
  echo "fixture Git executable is not available: $GIT_BIN" >&2
  exit 1
fi
if [ ! -x "$SHASUM_BIN" ]; then
  echo "fixture SHA-256 executable is not available: $SHASUM_BIN" >&2
  exit 1
fi

decode_state_value() {
  local raw_value="${1:-}"
  /usr/bin/python3 - "$raw_value" <<'PY'
import shlex
import sys

try:
    parsed = shlex.split(sys.argv[1])
except ValueError:
    parsed = []
print(parsed[0] if parsed else "")
PY
}

identity_value() {
  local key="${1:?missing identity key}"
  local raw_value
  raw_value="$(sed -n "s/^${key}=//p" <<<"$identity_output" | tail -1)"
  decode_state_value "$raw_value"
}

write_state_value() {
  local key="${1:?missing state key}"
  local value="${2:-}"
  printf '%s=%q\n' "$key" "$value"
}

sha256_for_file() {
  local file_path="${1:?missing file path}"
  "$SHASUM_BIN" -a 256 "$file_path" | awk '{ print $1 }'
}

fixture_digest_for_current_worktree() {
  local fixture_path="${1:?missing fixture path}"
  local fixture_baseline="${2:?missing fixture baseline}"
  local content_oid
  {
    printf 'baseline\0%s\0' "$fixture_baseline"
    while IFS= read -r -d '' relative_path; do
      content_oid="$($GIT_BIN -C "$fixture_path" hash-object -- "$relative_path")"
      printf 'path\0%s\0blob\0%s\0' "$relative_path" "$content_oid"
    done < <("$GIT_BIN" -C "$fixture_path" ls-files -z)
  } | "$SHASUM_BIN" -a 256 | awk '{ print $1 }'
}

identity_output="$($STANDARD_DEBUG_RUNNER --print-identity)"
debug_code="$(identity_value AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE)"
debug_data_root="$(identity_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
if [ -z "$debug_code" ] || [ -z "$debug_data_root" ]; then
  echo "standard debug observability runner returned incomplete worktree identity" >&2
  exit 1
fi

# Refuse before fixture creation when this worktree's debug app already exists.
# The standard owner performs process attribution and emits the authoritative error.
AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$OBSERVABILITY_STATE_FILE" \
  "$STANDARD_DEBUG_RUNNER" --preflight-idle

run_identifier="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(uuidgen | tr '[:upper:]' '[:lower:]')"
journey_root="$debug_data_root/bridge-packaged-product-journeys/$run_identifier"
fixture_root="$journey_root/fixture"
run_state_file="$journey_root/journey.env"
mkdir -p "$fixture_root" "$(dirname "$JOURNEY_STATE_FILE")"
chmod 700 "$journey_root" "$fixture_root"

journey_status=preparing
journey_reason=""
fixture_file_count=0
review_diff_count=0
fixture_digest=""
baseline_commit=""
tracked_relative_path=tracked.txt
tracked_sha256=""
tracked_byte_count=0
early_relative_path="tree/group-00/segment-00/file-000.swift"
middle_relative_path="tree/group-04/segment-00/file-128.swift"
final_relative_path="tree/group-07/segment-03/file-255.swift"
early_baseline_sha256=""
middle_baseline_sha256=""
final_baseline_sha256=""

write_receipt() {
  local status="${1:?missing journey status}"
  local reason="${2:-}"
  local temporary_run_state="$run_state_file.tmp"
  local temporary_latest_state="$JOURNEY_STATE_FILE.tmp"

  {
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_SCHEMA_VERSION 1
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_STATUS "$status"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_REASON "$reason"
    write_state_value DEBUG_CODE "$debug_code"
    write_state_value JOURNEY_ROOT "$journey_root"
    write_state_value RUN_STATE_FILE "$run_state_file"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_OBSERVABILITY_STATE_FILE "$OBSERVABILITY_STATE_FILE"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_FIXTURE_ROOT "$fixture_root"
    write_state_value STARTUP_ACTION bridge-product-paint-correlation
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_EXPECTED_FILE_COUNT "$fixture_file_count"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_EXPECTED_REVIEW_DIFF_COUNT "$review_diff_count"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_FIXTURE_DIGEST "$fixture_digest"
    write_state_value BASELINE_COMMIT "$baseline_commit"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_TRACKED_PATH "$tracked_relative_path"
    write_state_value TRACKED_CANARY bridge-product-paint-canary
    write_state_value TRACKED_SHA256 "$tracked_sha256"
    write_state_value TRACKED_BYTE_COUNT "$tracked_byte_count"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_EARLY_PATH "$early_relative_path"
    write_state_value EARLY_BASELINE_SHA256 "$early_baseline_sha256"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_MIDDLE_PATH "$middle_relative_path"
    write_state_value MIDDLE_BASELINE_SHA256 "$middle_baseline_sha256"
    write_state_value AGENTSTUDIO_BRIDGE_JOURNEY_FINAL_PATH "$final_relative_path"
    write_state_value FINAL_BASELINE_SHA256 "$final_baseline_sha256"
  } >"$temporary_run_state"
  chmod 600 "$temporary_run_state"
  mv "$temporary_run_state" "$run_state_file"
  /usr/bin/ditto "$run_state_file" "$temporary_latest_state"
  chmod 600 "$temporary_latest_state"
  mv "$temporary_latest_state" "$JOURNEY_STATE_FILE"
}

record_unexpected_failure() {
  local exit_code="$1"
  local line_number="$2"
  trap - ERR
  journey_status=failed
  journey_reason="unexpected_failure_line_${line_number}_exit_${exit_code}"
  write_receipt "$journey_status" "$journey_reason" || true
  echo "packaged product journey preparation failed; preserved fixture: $fixture_root" >&2
  exit "$exit_code"
}

trap 'record_unexpected_failure "$?" "$LINENO"' ERR
write_receipt "$journey_status" "$journey_reason"

"$GIT_BIN" -C "$fixture_root" init -q
"$GIT_BIN" -C "$fixture_root" config user.name "AgentStudio Packaged Journey"
"$GIT_BIN" -C "$fixture_root" config user.email "agentstudio-packaged-journey@invalid.local"
"$GIT_BIN" -C "$fixture_root" config commit.gpgsign false

printf 'bridge-product-paint-baseline\n' >"$fixture_root/$tracked_relative_path"
fixture_file_count=1
for index in $(seq 0 255); do
  group_index=$((index / 32))
  segment_index=$(((index % 32) / 8))
  printf -v relative_path 'tree/group-%02d/segment-%02d/file-%03d.swift' \
    "$group_index" "$segment_index" "$index"
  mkdir -p "$(dirname "$fixture_root/$relative_path")"
  printf '// bridge packaged journey baseline %03d\nlet fixtureValue%03d = %d\n' \
    "$index" "$index" "$index" >"$fixture_root/$relative_path"
  fixture_file_count=$((fixture_file_count + 1))
done

if [ "$fixture_file_count" -ne 257 ]; then
  echo "fixture file count mismatch: expected 257, observed $fixture_file_count" >&2
  exit 1
fi

early_baseline_sha256="$(sha256_for_file "$fixture_root/$early_relative_path")"
middle_baseline_sha256="$(sha256_for_file "$fixture_root/$middle_relative_path")"
final_baseline_sha256="$(sha256_for_file "$fixture_root/$final_relative_path")"

"$GIT_BIN" -C "$fixture_root" add -- .
"$GIT_BIN" -C "$fixture_root" commit -q -m "fixture: establish packaged journey baseline"
baseline_commit="$($GIT_BIN -C "$fixture_root" rev-parse HEAD)"

printf 'bridge-product-paint-canary\npackaged-journey-selected-source\n' \
  >"$fixture_root/$tracked_relative_path"
for index in $(seq 0 255); do
  group_index=$((index / 32))
  segment_index=$(((index % 32) / 8))
  printf -v relative_path 'tree/group-%02d/segment-%02d/file-%03d.swift' \
    "$group_index" "$segment_index" "$index"
  printf '\nbridge-packaged-live::%s\n' "$relative_path" >>"$fixture_root/$relative_path"
done
tracked_sha256="$(sha256_for_file "$fixture_root/$tracked_relative_path")"
tracked_byte_count="$(wc -c <"$fixture_root/$tracked_relative_path" | tr -d '[:space:]')"

review_diff_count="$(
  "$GIT_BIN" -C "$fixture_root" diff --name-only "$baseline_commit" -- \
    | awk 'NF { count += 1 } END { print count + 0 }'
)"
if [ "$review_diff_count" -ne "$fixture_file_count" ]; then
  echo "fixture Review diff count mismatch: expected $fixture_file_count, observed $review_diff_count" >&2
  exit 1
fi
if [ "$review_diff_count" -lt 100 ]; then
  echo "fixture Review diff count is below the required minimum: $review_diff_count" >&2
  exit 1
fi
if ! "$GIT_BIN" -C "$fixture_root" diff --cached --quiet --; then
  echo "fixture contains unexpected staged changes after its baseline commit" >&2
  exit 1
fi
if [ -n "$("$GIT_BIN" -C "$fixture_root" ls-files --others --exclude-standard)" ]; then
  echo "fixture contains unexpected untracked files after its baseline commit" >&2
  exit 1
fi
fixture_digest="$(fixture_digest_for_current_worktree "$fixture_root" "$baseline_commit")"

journey_status=fixture_ready
write_receipt "$journey_status" ""

unset AGENTSTUDIO_IPC_UNSAFE_NO_AUTH
if ! AGENTSTUDIO_DEBUG_DIRECT_FALLBACK=0 \
  AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
  AGENTSTUDIO_STARTUP_WATCH_FOLDER="$fixture_root" \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation \
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$OBSERVABILITY_STATE_FILE" \
  "$STANDARD_DEBUG_RUNNER" --detach; then
  journey_status=launch_failed
  journey_reason=standard_debug_observability_runner_failed
  write_receipt "$journey_status" "$journey_reason"
  echo "packaged product journey launch failed; preserved fixture: $fixture_root" >&2
  exit 1
fi

journey_status=running
journey_reason=""
write_receipt "$journey_status" "$journey_reason"
trap - ERR

echo "Bridge packaged product journey launched through strict LaunchServices."
echo "fixture preserved at: $fixture_root"
echo "journey state: $JOURNEY_STATE_FILE"
echo "observability state: $OBSERVABILITY_STATE_FILE"
echo "Run the packaged product journey verifier before closing the app."
