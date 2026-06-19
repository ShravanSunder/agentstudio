#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"

state_status=""
state_pid=""
state_data_dir=""

if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    decoded_value="$(
      /usr/bin/python3 - "$value" <<'PY'
import shlex
import sys

try:
    parsed = shlex.split(sys.argv[1])
except ValueError:
    parsed = []
print(parsed[0] if parsed else "")
PY
    )"
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_STATUS)
        state_status="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_PID)
        state_pid="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_DATA_DIR)
        state_data_dir="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

if [ "$state_status" != "running" ]; then
  echo "AgentStudio debug observability state is not running: ${state_status:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

case "$state_pid" in
  ''|*[!0-9]*)
    echo "AgentStudio debug observability state missing numeric PID" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
    ;;
esac

if ! kill -0 "$state_pid" >/dev/null 2>&1; then
  echo "AgentStudio debug observability PID is not running: $state_pid" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

if [ -z "$state_data_dir" ]; then
  echo "AgentStudio debug observability state missing data directory" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

AGENTSTUDIO_OBSERVABILITY_IPC_METADATA="${AGENTSTUDIO_OBSERVABILITY_IPC_METADATA:-$state_data_dir/ipc/runtime.json}"
AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN="${AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN:-$state_data_dir/ipc/debug-token}"

if [ ! -f "$AGENTSTUDIO_OBSERVABILITY_IPC_METADATA" ]; then
  echo "AgentStudio IPC runtime metadata is missing: $AGENTSTUDIO_OBSERVABILITY_IPC_METADATA" >&2
  exit 1
fi

if [ ! -f "$AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN" ]; then
  echo "AgentStudio IPC debug token is missing: $AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN" >&2
  echo "Launch with AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 before running this verifier." >&2
  exit 1
fi

/usr/bin/python3 - "$AGENTSTUDIO_OBSERVABILITY_IPC_METADATA" "$AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN" <<'PY'
import json
import os
import socket
import sys

metadata_path = sys.argv[1]
debug_token_path = sys.argv[2]
response_timeout_seconds = float(os.environ.get("AGENTSTUDIO_IPC_PHASE_A_SMOKE_RESPONSE_TIMEOUT_SECONDS", "15"))

with open(metadata_path, "r", encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)
socket_path = metadata.get("socketPath")
if not socket_path:
    print(f"IPC metadata missing socketPath: {metadata_path}", file=sys.stderr)
    sys.exit(1)

with open(debug_token_path, "r", encoding="utf-8") as token_file:
    debug_token = token_file.read().strip()
if not debug_token:
    print(f"AgentStudio IPC debug token file is empty: {debug_token_path}", file=sys.stderr)
    sys.exit(1)


class JSONRPCSession:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(response_timeout_seconds)
        self.socket.connect(path)
        self.reader = self.socket.makefile("rb")

    def close(self):
        self.reader.close()
        self.socket.close()

    def request(self, request_id, method, params):
        payload = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
        self.socket.sendall((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
        while True:
            try:
                line = self.reader.readline()
            except socket.timeout:
                print(
                    f"IPC response timed out after {response_timeout_seconds:g}s for {method}",
                    file=sys.stderr,
                )
                sys.exit(1)
            if not line:
                print(f"IPC socket closed before response for {method}", file=sys.stderr)
                sys.exit(1)
            response = json.loads(line.decode("utf-8"))
            if response.get("id") == request_id:
                return response


def require_success(response, label):
    if response.get("error") is not None:
        print(f"{label} failed: {response['error']}", file=sys.stderr)
        sys.exit(1)
    return response.get("result", {})


session = JSONRPCSession(socket_path)
try:
    login_result = require_success(
        session.request(1, "auth.login", {"token": debug_token}),
        "auth.login",
    )
    if login_result.get("authenticated") is not True:
        print(f"auth.login did not authenticate: {login_result}", file=sys.stderr)
        sys.exit(1)

    capabilities = require_success(
        session.request(2, "system.capabilities", {}),
        "system.capabilities",
    )
    methods = capabilities.get("methods", [])
    if not any(method.get("name") == "pane.snapshot" for method in methods):
        print("pane.snapshot missing from system.capabilities", file=sys.stderr)
        sys.exit(1)

    panes_result = require_success(
        session.request(3, "pane.list", {}),
        "pane.list",
    )
    panes = panes_result.get("panes", [])
    ordinal_one = next((pane for pane in panes if pane.get("ordinal") == 1), None)
    if ordinal_one is None:
        print("pane:1 is not available in pane.list result", file=sys.stderr)
        sys.exit(1)
    pane_id = ordinal_one.get("id")
    if not pane_id:
        print("pane:1 result is missing a canonical id", file=sys.stderr)
        sys.exit(1)
    canonical_pane_handle = f"pane:{pane_id}"

    friendly_snapshot = require_success(
        session.request(4, "pane.snapshot", {"handle": "pane:1"}),
        "pane.snapshot pane:1",
    )
    friendly_pane_id = friendly_snapshot.get("pane", {}).get("id")
    if f"pane:{friendly_pane_id}" != canonical_pane_handle:
        print("pane.snapshot pane:1 did not resolve to the expected canonical pane", file=sys.stderr)
        sys.exit(1)

    canonical_snapshot = require_success(
        session.request(5, "pane.snapshot", {"handle": canonical_pane_handle}),
        "pane.snapshot canonical handle",
    )
    canonical_result_pane_id = canonical_snapshot.get("pane", {}).get("id")
    if f"pane:{canonical_result_pane_id}" != canonical_pane_handle:
        print("pane.snapshot canonical result does not match requested pane", file=sys.stderr)
        sys.exit(1)

    print(f"AgentStudio IPC Phase A smoke passed for {canonical_pane_handle}")
finally:
    session.close()
PY
