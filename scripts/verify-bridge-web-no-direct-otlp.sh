#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_output="$(mktemp -t bridge-web-otlp-scan.XXXXXX)"
trap 'rm -f "$scan_output"' EXIT

default_scan_targets=(
  "$PROJECT_ROOT/BridgeWeb/package.json"
  "$PROJECT_ROOT/BridgeWeb/pnpm-lock.yaml"
  "$PROJECT_ROOT/BridgeWeb/src"
  "$PROJECT_ROOT/Sources/AgentStudio/Resources/BridgeWeb/app"
)
scan_targets=("${default_scan_targets[@]}")

if [ -n "${BRIDGE_WEB_OTLP_SCAN_TARGETS:-}" ]; then
  IFS=':' read -r -a extra_scan_targets <<<"$BRIDGE_WEB_OTLP_SCAN_TARGETS"
  scan_targets+=("${extra_scan_targets[@]}")
fi

forbidden_patterns=(
  "@opentelemetry"
  "otlp"
  "OTLP"
  "collector"
  "/v1/traces"
  "/v1/logs"
  "/v1/metrics"
  "OTEL_EXPORTER_OTLP"
  "OTLPHTTP"
  "127.0.0.1:4318"
  "localhost:4318"
)

for target in "${scan_targets[@]}"; do
  if [ ! -e "$target" ]; then
    echo "missing BridgeWeb OTLP scan target: $target" >&2
    exit 1
  fi
done

for pattern in "${forbidden_patterns[@]}"; do
  if /usr/bin/grep -R --line-number --fixed-strings -- "$pattern" "${scan_targets[@]}" >"$scan_output"; then
    echo "direct browser OTLP marker found in BridgeWeb scan target: $pattern" >&2
    cat "$scan_output" >&2
    exit 1
  fi
done

echo "BridgeWeb direct OTLP scan passed"
