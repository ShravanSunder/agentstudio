#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${AGENTSTUDIO_ATOMLIB_BOUNDARY_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEFAULT_SCAN_PATH="$PROJECT_ROOT/Sources/AgentStudio/Infrastructure/AtomLib/DerivedValue.swift"
DEFAULT_SCAN_ROOT="$PROJECT_ROOT/Sources/AgentStudio"
DEFAULT_FIXTURE_PATH="$PROJECT_ROOT/Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures"
INVENTORY_FILE="$PROJECT_ROOT/tmp/atomlib-boundaries/repo-cache-dictionary-read-inventory.txt"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atomlib_boundary.XXXXXX")"

scan_paths=()
fixture_path="$DEFAULT_FIXTURE_PATH"
write_inventory=1
expect_fixture_failures=0
custom_scan_paths=0

cleanup_temp_dir() {
  find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup_temp_dir EXIT

usage() {
  cat <<'USAGE'
Usage: check-atomlib-boundaries.sh [--scan-path <path>] [--no-inventory] [--expect-fixture-failures]

Checks early AtomLib v2 boundaries:
  - no undeclared atom access from DerivedValue compute paths;
  - no named helper wrappers that hide undeclared atom/global reads;
  - no raw WorktreeEnrichment equality as a cache comparator;
  - no production raw repo-cache dictionary reads after row-1 migration.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scan-path)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      scan_paths=("$2")
      custom_scan_paths=1
      shift 2
      ;;
    --fixture-path)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      fixture_path="$2"
      shift 2
      ;;
    --no-inventory)
      write_inventory=0
      shift
      ;;
    --expect-fixture-failures)
      expect_fixture_failures=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

scan_path_for_violations() {
  local path="$1"
  local violations=0
  local undeclared_atom_output="$TEMP_DIR/undeclared-atom"
  local wrapper_output="$TEMP_DIR/wrapper"
  local worktree_eq_output="$TEMP_DIR/worktree-eq"
  local repo_cache_read_output="$TEMP_DIR/repo-cache-read"

  if [ ! -e "$path" ]; then
    echo "AtomLib boundary scan path not found: $path" >&2
    return 1
  fi

  if rg -n 'AtomScope|atom\(' "$path" >"$undeclared_atom_output" 2>/dev/null; then
    echo "AtomLib boundary violation: undeclared atom access in DerivedValue compute path" >&2
    cat "$undeclared_atom_output" >&2
    violations=1
  fi

  if rg -n 'AtomReader\(|withTestAtomRegistry|AtomScope\.\$override' "$path" >"$wrapper_output" 2>/dev/null; then
    echo "AtomLib boundary violation: denied wrapper can hide undeclared atom/global input access" >&2
    cat "$wrapper_output" >&2
    violations=1
  fi

  : >"$worktree_eq_output"
  while IFS= read -r candidate; do
    perl -0ne '
      if (/isContentEqual\s*:\s*==/s || /isContentEqual\s*:\s*\{[^}]*\b[A-Za-z_][A-Za-z0-9_]*\b\s*==\s*\b[A-Za-z_][A-Za-z0-9_]*\b[^}]*\}/s) {
        print "$ARGV\n"
      }
    ' "$candidate" >>"$worktree_eq_output"
  done < <(rg -l 'WorktreeEnrichment' "$path" 2>/dev/null || true)
  if [ -s "$worktree_eq_output" ]; then
    echo "AtomLib boundary violation: WorktreeEnrichment must not use raw equality as repo-cache comparator" >&2
    cat "$worktree_eq_output" >&2
    violations=1
  fi

  if rg -n '(atom\([^)]*repoCache[^)]*\)|self\.repoCache|[[:alpha:]_][[:alnum:]_]*|repoEnrichmentCacheAtom\??)\.(repoEnrichmentByRepoId|worktreeEnrichmentByWorktreeId|pullRequestCountByWorktreeId)' \
    "$path" >"$repo_cache_read_output" 2>/dev/null
  then
    echo "AtomLib boundary violation: production code must use repo-cache keyed reads or named snapshots" >&2
    cat "$repo_cache_read_output" >&2
    violations=1
  fi

  return "$violations"
}

populate_default_scan_paths() {
  while IFS= read -r scan_path; do
    scan_paths+=("$scan_path")
  done < <(
    rg -l --glob '*.swift' 'DerivedValue[<(]' "$DEFAULT_SCAN_ROOT" 2>/dev/null || true
  )

  if [ "${#scan_paths[@]}" -eq 0 ] && [ -e "$DEFAULT_SCAN_PATH" ]; then
    scan_paths=("$DEFAULT_SCAN_PATH")
  fi
}

check_production_repo_cache_dictionary_reads() {
  local production_output="$TEMP_DIR/production-repo-cache-read"
  if rg -n --glob '*.swift' \
    '(atom\([^)]*repoCache[^)]*\)|self\.repoCache|[[:alpha:]_][[:alnum:]_]*|repoEnrichmentCacheAtom\??)\.(repoEnrichmentByRepoId|worktreeEnrichmentByWorktreeId|pullRequestCountByWorktreeId)' \
    "$PROJECT_ROOT/Sources/AgentStudio" 2>/dev/null |
    grep -Ev 'Sources/AgentStudio/(Core/State/MainActor/Atoms/RepoCacheAtom.swift|Core/State/MainActor/Persistence/RepoCacheStore.swift|Core/State/MainActor/Persistence/WorkspacePersistor\+Payloads.swift|Core/State/MainActor/Persistence/WorkspaceLocalRepository(\+Storage)?\.swift|Features/RepoExplorer/Models/RepoExplorerProjection.swift|Features/InboxNotification/Views/InboxNotificationSidebarView.swift):' \
      >"$production_output"
  then
    echo "AtomLib boundary violation: production code must use repo-cache keyed reads or named snapshots" >&2
    cat "$production_output" >&2
    return 1
  fi
}

write_repo_cache_dictionary_inventory() {
  mkdir -p "$(dirname "$INVENTORY_FILE")"
  {
    echo "report-only repo-cache dictionary inventory"
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    rg -n --glob '*.swift' \
      'repoEnrichmentByRepoId|worktreeEnrichmentByWorktreeId|pullRequestCountByWorktreeId' \
      "$PROJECT_ROOT/Sources/AgentStudio" || true
  } >"$INVENTORY_FILE"
  echo "report-only repo-cache dictionary inventory: $INVENTORY_FILE"
}

expect_compile_negative_fixtures_to_fail() {
  local found=0
  local failed=0

  while IFS= read -r fixture; do
    found=1
    if scan_path_for_violations "$fixture" >/dev/null 2>&1; then
      echo "AtomLib compile-negative fixture unexpectedly passed: $fixture" >&2
      failed=1
    fi
  done < <(find "$fixture_path" -type f -name '*.swift.fixture' -print | sort)

  if [ "$found" -eq 0 ]; then
    echo "No AtomLib compile-negative fixtures found under $fixture_path" >&2
    return 1
  fi
  if [ "$failed" -ne 0 ]; then
    return 1
  fi

  echo "expected fixture failures: OK"
}

if [ "$expect_fixture_failures" -eq 1 ]; then
  expect_compile_negative_fixtures_to_fail
  exit 0
fi

if [ "$custom_scan_paths" -eq 0 ]; then
  populate_default_scan_paths
fi

scan_failed=0
if [ "${#scan_paths[@]}" -gt 0 ]; then
  for scan_path in "${scan_paths[@]}"; do
    if ! scan_path_for_violations "$scan_path"; then
      scan_failed=1
    fi
  done
fi

if ! check_production_repo_cache_dictionary_reads; then
  scan_failed=1
fi

if [ "$write_inventory" -eq 1 ]; then
  write_repo_cache_dictionary_inventory
fi

if [ "$scan_failed" -ne 0 ]; then
  exit 1
fi

echo "AtomLib boundary check passed."
