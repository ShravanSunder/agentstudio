#!/usr/bin/env bash
set -euo pipefail

source_root="Tests/BridgeContractFixtures"
destination_root="BridgeWeb/src/test-fixtures/bridge-contract-fixtures"
mode="${1:---check}"

if [ "$mode" != "--check" ] && [ "$mode" != "--fix" ]; then
  echo "Usage: $0 [--check|--fix]" >&2
  exit 2
fi

fixture_count=0
drift_count=0

while IFS= read -r -d '' source_path; do
  fixture="${source_path#${source_root}/}"
  destination_path="${destination_root}/${fixture}"
  fixture_count=$((fixture_count + 1))

  if [ ! -f "$destination_path" ] || ! cmp -s "$source_path" "$destination_path"; then
    drift_count=$((drift_count + 1))
    if [ "$mode" = "--fix" ]; then
      mkdir -p "$(dirname "$destination_path")"
      cp "$source_path" "$destination_path"
      echo "Synced drifted BridgeWeb fixture: $fixture" >&2
    else
      echo "BridgeWeb fixture drift: $fixture" >&2
    fi
  fi
done < <(find "$source_root" -type f -name '*.json' -print0 | sort -z)

while IFS= read -r -d '' destination_path; do
  fixture="${destination_path#${destination_root}/}"
  source_path="${source_root}/${fixture}"
  if [ ! -f "$source_path" ]; then
    drift_count=$((drift_count + 1))
    echo "BridgeWeb fixture has no Swift source fixture: $fixture" >&2
  fi
done < <(find "$destination_root" -type f -name '*.json' -print0 | sort -z)

if [ "$drift_count" -ne 0 ]; then
  if [ "$mode" = "--fix" ]; then
    echo "BridgeWeb fixtures were updated. Review the copied files and rerun --check." >&2
  else
    echo "BridgeWeb fixtures are out of sync. Run scripts/bridge-web-sync-fixtures.sh --fix." >&2
  fi
  exit 1
fi

echo "BridgeWeb fixtures are in sync (${fixture_count} files)."
