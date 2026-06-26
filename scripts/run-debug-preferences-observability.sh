#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_STACK_HELPER="$HOME/dev/ai-tools/observability/observability-stack"
STACK_HELPER="${AI_TOOLS_OBSERVABILITY_STACK_HELPER:-$DEFAULT_STACK_HELPER}"
COLLECTOR_HEALTH_URL="${AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/observability-control-guards.sh"

fail_on_legacy_observability_env
validate_observability_controls "$DEFAULT_STACK_HELPER" "$STACK_HELPER" "$COLLECTOR_HEALTH_URL"

worktree_debug_code() {
  /usr/bin/python3 - "$PROJECT_ROOT" <<'PY'
import hashlib
import os
import sys

alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
space = 36 ** 4
root = os.path.realpath(sys.argv[1])
value = int.from_bytes(hashlib.sha256(root.encode("utf-8")).digest()[:4], "big") % space
chars = []
for _ in range(4):
    value, digit = divmod(value, 36)
    chars.append(alphabet[digit])
print("".join(reversed(chars)))
PY
}

debug_code="$(worktree_debug_code)"
debug_root="$HOME/.agentstudio-db/$debug_code"
trace_name="${AGENTSTUDIO_TRACE_NAME:-debug-preferences-observability-$debug_code-$(date +%s)-$$}"
validate_safe_trace_name "$trace_name" AGENTSTUDIO_TRACE_NAME

default_launch_parent="$debug_root/preferences-runs"
default_launch_data_root="$default_launch_parent/$trace_name"
if [ -n "${AGENTSTUDIO_DEBUG_DATA_DIR:-}" ]; then
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_DATA_ROOT_ESCAPE:-0}" != "1" ]; then
    assert_child_path_under_parent "$default_launch_parent" "$AGENTSTUDIO_DEBUG_DATA_DIR" AGENTSTUDIO_DEBUG_DATA_DIR
  fi
  launch_data_root="$AGENTSTUDIO_DEBUG_DATA_DIR"
else
  assert_child_path_under_parent "$default_launch_parent" "$default_launch_data_root" AGENTSTUDIO_DEBUG_DATA_DIR
  launch_data_root="$default_launch_data_root"
fi
otlp_endpoint="$(/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$STACK_HELPER" collector-url)"
validate_loopback_url OTEL_EXPORTER_OTLP_ENDPOINT "$otlp_endpoint"
preferences_file="$launch_data_root/preferences.global.json"

mkdir -p "$launch_data_root"
chmod 700 "$launch_data_root"
cat >"$preferences_file" <<JSON
{
  "schemaVersion": 1,
  "observability": {
    "enabled": true,
    "traceTags": "*",
    "traceBackend": "otlp",
    "traceFlush": "buffered",
    "otlpEndpoint": "$otlp_endpoint"
  }
}
JSON
chmod 600 "$preferences_file"

export AGENTSTUDIO_DEBUG_DATA_DIR="$launch_data_root"
export AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE=honor_preferences
export AGENTSTUDIO_TRACE_NAME="$trace_name"

exec "$PROJECT_ROOT/scripts/run-debug-observability.sh" "$@"
