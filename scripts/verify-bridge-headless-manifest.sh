#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROOF_ROOT="${AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR:-$PROJECT_ROOT/tmp/bridge-headless-manifest-proof}"
TEST_FILTER="${AGENTSTUDIO_BRIDGE_HEADLESS_TEST_FILTER:-WebKitSerializedTests.BridgeWorktreeFileSurfaceCurrentWorktreeProofTests}"
SWIFT_TIMEOUT="${SWIFT_TEST_TIMEOUT_SECONDS:-240}"
VALIDATE_ONLY=0

if [ "${1:-}" = "--validate-only" ]; then
  VALIDATE_ONLY=1
  shift
fi

if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--validate-only]" >&2
  exit 2
fi

artifact_path() {
  if [ -f "$PROOF_ROOT/current-worktree-manifest-proof.json" ]; then
    printf '%s/current-worktree-manifest-proof.json\n' "$PROOF_ROOT"
    return 0
  fi
  find "$PROOF_ROOT" -type f -name current-worktree-manifest-proof.json -print -quit
}

validate_artifact() {
  local artifact="${1:?missing artifact path}"
  /usr/bin/python3 - "$artifact" <<'PY'
import json
import sys
from pathlib import Path

artifact = Path(sys.argv[1])
payload = json.loads(artifact.read_text())

def require_int(name: str) -> int:
    value = payload.get(name)
    if not isinstance(value, int):
        raise SystemExit(f"{name} missing or not an integer")
    return value

def require_empty_list(name: str) -> None:
    value = payload.get(name)
    if value != []:
        raise SystemExit(f"{name} must be an empty list")

expected_files = require_int("expectedMetadataFileTotal")
emitted_files = require_int("emittedMetadataFileTotal")
expected_rows = require_int("expectedMetadataRowTotal")
emitted_rows = require_int("emittedMetadataRowTotal")
remaining_rows = require_int("remainingMetadataRowTotal")
first_window_rows = require_int("firstWindowRowCount")
unique_paths = require_int("uniquePathCount")

if expected_files <= 0:
    raise SystemExit("expectedMetadataFileTotal must be positive")
if emitted_files != expected_files:
    raise SystemExit("emittedMetadataFileTotal must equal expectedMetadataFileTotal")
if emitted_rows != expected_rows:
    raise SystemExit("emittedMetadataRowTotal must equal expectedMetadataRowTotal")
if remaining_rows != 0:
    raise SystemExit("remainingMetadataRowTotal must be zero")
if unique_paths != emitted_rows:
    raise SystemExit("uniquePathCount must match emittedMetadataRowTotal")
if first_window_rows <= 0:
    raise SystemExit("firstWindowRowCount must be positive")

require_empty_list("missingExpectedFilePaths")
require_empty_list("unexpectedPublishedFilePaths")

metadata_interest = payload.get("metadataInterestRequestToDeliveredFrame")
if not isinstance(metadata_interest, dict):
    raise SystemExit("metadataInterestRequestToDeliveredFrame missing")
if metadata_interest.get("p95Milliseconds") is None:
    raise SystemExit("metadataInterestRequestToDeliveredFrame.p95Milliseconds missing")
if metadata_interest.get("p99Milliseconds") is None:
    raise SystemExit("metadataInterestRequestToDeliveredFrame.p99Milliseconds missing")

no_starvation = payload.get("noStarvationProgress")
if not isinstance(no_starvation, dict) or no_starvation.get("completed") is not True:
    raise SystemExit("noStarvationProgress.completed must be true")

print(f"artifact={artifact}")
print(f"expectedMetadataFileTotal={expected_files}")
print(f"emittedMetadataFileTotal={emitted_files}")
print(f"expectedMetadataRowTotal={expected_rows}")
print(f"emittedMetadataRowTotal={emitted_rows}")
PY
}

if [ "$VALIDATE_ONLY" != "1" ]; then
  rm -rf "$PROOF_ROOT"
  mkdir -p "$PROOF_ROOT"
  source "$PROJECT_ROOT/scripts/swift-build-slot.sh" debug
  swift build --build-path "$SWIFT_BUILD_DIR" --build-tests
  PROJECT_ROOT="$PROJECT_ROOT" \
    AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR="$PROOF_ROOT" \
    SWIFT_TEST_TIMEOUT_SECONDS="$SWIFT_TIMEOUT" \
    swift test --build-path "$SWIFT_BUILD_DIR" --skip-build --filter "$TEST_FILTER"
fi

ARTIFACT="$(artifact_path)"
if [ -z "$ARTIFACT" ]; then
  echo "missing current-worktree-manifest-proof.json under $PROOF_ROOT" >&2
  exit 1
fi

validate_artifact "$ARTIFACT"
