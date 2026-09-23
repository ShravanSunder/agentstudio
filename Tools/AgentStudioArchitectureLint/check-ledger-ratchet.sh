#!/usr/bin/env bash
# Fails when the architecture debt ledger raises a count or adds a row compared
# with the ledger at the merge base of HEAD and the given base ref (default
# origin/main). The lint run itself cannot see history, so this check owns the
# only-decrease rule.
#
# A merge base that has no ledger passes: the change that introduces the
# ledger records its initial baseline. A merge base that cannot be computed
# fails; the fix is enough fetched history, never skipping the check.
#
# Usage: Tools/AgentStudioArchitectureLint/check-ledger-ratchet.sh [base-ref]
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

base_ref="${1:-origin/main}"
ledger_path="Tools/AgentStudioArchitectureLint/architecture-debt-ledger.tsv"

if ! merge_base="$(git merge-base HEAD "$base_ref")"; then
  echo "check-ledger-ratchet: cannot compute the merge base of HEAD and ${base_ref}; fetch full history" >&2
  exit 1
fi
echo "check-ledger-ratchet: comparing ${ledger_path} with merge base ${merge_base} (${base_ref})"

source "${repository_root}/scripts/swift-build-slot.sh"
build_path="${repository_root}/${SWIFT_BUILD_DIR}/architecture-lint"
swift build -c release --package-path Tools/AgentStudioArchitectureLint \
  --build-path "$build_path" \
  --product agentstudio-architecture-lint

# The merge-base copy lives in this checkout's build slot, beside the tool.
# It is absent when the merge base has no ledger.
base_ledger_copy="${build_path}/merge-base-architecture-debt-ledger.tsv"
rm -f "$base_ledger_copy"
if git cat-file -e "${merge_base}:${ledger_path}" 2>/dev/null; then
  git show "${merge_base}:${ledger_path}" > "$base_ledger_copy"
fi

"${build_path}/release/agentstudio-architecture-lint" \
  --ledger "$ledger_path" \
  --check-ledger-ratchet "$base_ledger_copy"
