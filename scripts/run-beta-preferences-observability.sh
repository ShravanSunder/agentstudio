#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_STACK_HELPER="$HOME/dev/ai-tools/observability/observability-stack"
STACK_HELPER="${AI_TOOLS_OBSERVABILITY_STACK_HELPER:-$DEFAULT_STACK_HELPER}"
COLLECTOR_HEALTH_URL="${AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
BETA_ARTIFACT_ROOT="${AGENTSTUDIO_BETA_ARTIFACT_ROOT:-$HOME/.agentstudio-db/beta-observability}"
proof_root="${AGENTSTUDIO_BETA_PREFERENCES_PROOF_ROOT:-$HOME/.agentstudio-db/beta-preferences-observability}"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/observability-control-guards.sh"

fail_on_legacy_observability_env
validate_observability_controls "$DEFAULT_STACK_HELPER" "$STACK_HELPER" "$COLLECTOR_HEALTH_URL"

trace_name="${AGENTSTUDIO_TRACE_NAME:-beta-preferences-observability-$(date +%s)-$$}"
validate_safe_trace_name "$trace_name" "AGENTSTUDIO_TRACE_NAME for preferences proof"

default_launch_data_root="$proof_root/$trace_name"
if [ -n "${AGENTSTUDIO_BETA_DATA_DIR:-}" ]; then
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_DATA_ROOT_ESCAPE:-0}" != "1" ]; then
    assert_child_path_under_parent "$proof_root" "$AGENTSTUDIO_BETA_DATA_DIR" AGENTSTUDIO_BETA_DATA_DIR
  fi
  launch_data_root="$AGENTSTUDIO_BETA_DATA_DIR"
else
  assert_child_path_under_parent "$proof_root" "$default_launch_data_root" AGENTSTUDIO_BETA_DATA_DIR
  launch_data_root="$default_launch_data_root"
fi
preferences_file="$launch_data_root/preferences.global.json"
otlp_endpoint="$(/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$STACK_HELPER" collector-url)"
validate_loopback_url OTEL_EXPORTER_OTLP_ENDPOINT "$otlp_endpoint"

mkdir -p "$launch_data_root" "$BETA_ARTIFACT_ROOT/traces"
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

export AGENTSTUDIO_BETA_DATA_DIR="$launch_data_root"
export AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE=honor_preferences
export AGENTSTUDIO_TRACE_NAME="$trace_name"

exec "$PROJECT_ROOT/scripts/run-beta-observability.sh" "$@"
