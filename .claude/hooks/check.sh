#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: lint Swift files after Edit/Write
# Reports errors via stderr so Claude sees them as hints.

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"

# Nothing to do if no file or file doesn't exist
[[ -n "$file_path" && -f "$file_path" ]] || exit 0

proj="${CLAUDE_PROJECT_DIR:-.}"
has_errors=0
err() { printf "%s\n" "$*" 1>&2; }

case "$file_path" in
  *.swift)
    # --- swift-format lint ---
    fmt_out="$(swift-format lint "$file_path" 2>&1 || true)"
    fmt_errors="$(printf "%s" "$fmt_out" | grep -c "warning:" 2>/dev/null || echo 0)"
    if (( fmt_errors > 0 )); then
      first_fmt="$(printf "%s" "$fmt_out" | grep "warning:" -m1 | sed -E 's/[[:space:]]+/ /g' | cut -c1-140)"
      err "Hint: swift-format found ${fmt_errors} issue(s). ${first_fmt}"
      has_errors=1
    else
      # Auto-format on success (no lint errors)
      swift-format format --in-place "$file_path" 2>/dev/null || true
    fi

    # --- swiftlint ---
    if command -v swiftlint >/dev/null 2>&1; then
      lint_out="$(cd "$proj" && swiftlint lint --path "$file_path" --force-exclude 2>&1 || true)"
      lint_clean="$(printf "%s" "$lint_out" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
      lint_errors="$(printf "%s" "$lint_clean" | grep -cE '(error|warning):' 2>/dev/null || echo 0)"
      if (( lint_errors > 0 )); then
        first_lint="$(printf "%s" "$lint_clean" | grep -E '(error|warning):' -m1 | sed -E 's/[[:space:]]+/ /g' | cut -c1-140)"
        err "Hint: swiftlint found ${lint_errors} issue(s). ${first_lint}"
        has_errors=1
      fi
    fi
    ;;
esac

if (( has_errors > 0 )); then
  exit 2
fi
exit 0
