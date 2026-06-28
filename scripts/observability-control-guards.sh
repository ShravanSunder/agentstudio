#!/bin/bash

fail_on_legacy_observability_env() {
  local legacy_prefix="SHRAVAN_""OBSERVABILITY_"
  local env_name
  while IFS='=' read -r env_name _; do
    case "$env_name" in
      "$legacy_prefix"*)
        echo "Legacy observability env prefix is no longer supported; use AI_TOOLS_OBSERVABILITY_* instead of $env_name" >&2
        exit 2
        ;;
    esac
  done < <(env)
}

canonical_path() {
  /usr/bin/python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

validate_loopback_url() {
  local url_name="${1:?missing url name}"
  local url_value="${2:?missing url value}"
  /usr/bin/python3 - "$url_name" "$url_value" <<'PY'
import sys
from urllib.parse import urlparse

name, value = sys.argv[1], sys.argv[2]
parsed = urlparse(value)
if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
    print(f"{name} must be a loopback http URL: {value}", file=sys.stderr)
    sys.exit(2)
PY
}

validate_observability_controls() {
  local default_stack_helper="${1:?missing default stack helper}"
  local stack_helper="${2:?missing stack helper}"
  local collector_health_url="${3:?missing collector health url}"

  validate_loopback_url AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL "$collector_health_url"
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES:-0}" = "1" ]; then
    return
  fi
  if [ "$(canonical_path "$stack_helper")" != "$(canonical_path "$default_stack_helper")" ]; then
    echo "AI_TOOLS_OBSERVABILITY_STACK_HELPER must point to the trusted ai-tools helper: $default_stack_helper" >&2
    return 2
  fi
}

validate_safe_trace_name() {
  local trace_name="${1:?missing trace name}"
  local label="${2:-trace name}"
  case "$trace_name" in
    ""|"."|".."|*[!A-Za-z0-9._-]*)
      echo "unsafe $label: $trace_name" >&2
      return 2
      ;;
  esac
  if [ "${#trace_name}" -gt 128 ]; then
    echo "unsafe $label: value is longer than 128 characters" >&2
    return 2
  fi
}

assert_child_path_under_parent() {
  local parent_path="${1:?missing parent path}"
  local child_path="${2:?missing child path}"
  local label="${3:-child path}"
  /usr/bin/python3 - "$parent_path" "$child_path" "$label" <<'PY'
import os
import sys

parent, child, label = sys.argv[1], sys.argv[2], sys.argv[3]
real_parent = os.path.realpath(parent)
real_child = os.path.realpath(child)
try:
    common = os.path.commonpath([real_parent, real_child])
except ValueError:
    common = ""
if common != real_parent or real_child == real_parent:
    print(f"{label} must stay under {real_parent}: {real_child}", file=sys.stderr)
    sys.exit(2)
PY
}
