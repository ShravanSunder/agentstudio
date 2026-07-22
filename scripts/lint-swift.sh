#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

run_architecture_lint() {
  echo "--- AgentStudio architecture lint ---"
  swift run --package-path Tools/AgentStudioArchitectureLint \
    agentstudio-architecture-lint Sources Tests 2>&1 \
    && echo "agentstudio architecture lint: OK" \
    || { echo "agentstudio architecture lint: FAIL"; exit 1; }
}

run_release_script_checks() {
  echo "--- release script checks ---"
  /bin/bash scripts/verify-release-scripts.sh
}

if [[ $# -eq 0 ]]; then
  echo "--- swift-format lint ---"
  swift-format lint --recursive \
    Sources/ Tests/ \
    Tools/AgentStudioArchitectureLint/Sources \
    Tools/AgentStudioArchitectureLint/Tests 2>&1 \
    && echo "swift-format: OK" \
    || { echo "swift-format: FAIL"; exit 1; }

  echo "--- SwiftLint ---"
  swiftlint lint --strict 2>&1 \
    && echo "swiftlint: OK" \
    || { echo "swiftlint: FAIL"; exit 1; }

  run_architecture_lint
  run_release_script_checks
  exit 0
fi

scoped_paths=("$@")
for scoped_path in "${scoped_paths[@]}"; do
  if [[ "$scoped_path" = /* || "$scoped_path" == *".."* || ! -f "$scoped_path" ]]; then
    echo "lint-swift: scoped path must be an existing repository-relative file: $scoped_path" >&2
    exit 2
  fi
done

scoped_swift_paths=()
run_release_contract=0
for scoped_path in "${scoped_paths[@]}"; do
  case "$scoped_path" in
    *.swift)
      scoped_swift_paths+=("$scoped_path")
      ;;
    .github/workflows/release.yml|scripts/release-*|scripts/verify-release-scripts.sh)
      run_release_contract=1
      echo "lint-swift: routing release path to release checks: $scoped_path"
      ;;
    docs/*)
      echo "lint-swift: ignoring documentation path: $scoped_path"
      ;;
    *)
      echo "lint-swift: ignoring non-Swift path: $scoped_path"
      ;;
  esac
done

if [[ ${#scoped_swift_paths[@]} -gt 0 ]]; then
  echo "--- swift-format lint (scoped) ---"
  swift-format lint "${scoped_swift_paths[@]}" 2>&1 \
    && echo "swift-format: OK" \
    || { echo "swift-format: FAIL"; exit 1; }

  echo "--- SwiftLint (scoped) ---"
  swiftlint lint --strict "${scoped_swift_paths[@]}" 2>&1 \
    && echo "swiftlint: OK" \
    || { echo "swiftlint: FAIL"; exit 1; }

  run_architecture_lint
else
  echo "lint-swift: no Swift-lintable paths remain"
fi

if [[ $run_release_contract -eq 1 ]]; then
  run_release_script_checks
else
  echo "--- release script checks: not affected by scoped paths ---"
fi
