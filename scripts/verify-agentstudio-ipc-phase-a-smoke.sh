#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"

state_status=""
state_pid=""
state_data_dir=""
state_activation_mode=""
state_ipc_auth_mode=""

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
      AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE)
        state_activation_mode="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE)
        state_ipc_auth_mode="$decoded_value"
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

if [ "$state_ipc_auth_mode" != "authenticated" ]; then
  echo "AgentStudio IPC phase-a smoke requires authenticated IPC auth mode: ${state_ipc_auth_mode:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

if [ "$state_activation_mode" != "background" ]; then
  echo "AgentStudio IPC phase-a smoke requires background activation mode: ${state_activation_mode:-<missing>}" >&2
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


def require_error(response, label, expected_code, expected_message):
    error = response.get("error")
    if error is None:
        print(f"{label} unexpectedly succeeded: {response.get('result', {})}", file=sys.stderr)
        sys.exit(1)
    if error.get("code") != expected_code or error.get("message") != expected_message:
        print(
            f"{label} returned unexpected error: {error}; "
            f"expected code={expected_code} message={expected_message!r}",
            file=sys.stderr,
        )
        sys.exit(1)


session = JSONRPCSession(socket_path)
try:
    login_result = require_success(
        session.request(1, "auth.login", {"token": debug_token}),
        "auth.login",
    )
    if login_result.get("authenticated") is not True:
        print(f"auth.login did not authenticate: {login_result}", file=sys.stderr)
        sys.exit(1)
    if os.path.exists(debug_token_path):
        print(f"AgentStudio IPC debug token was not consumed: {debug_token_path}", file=sys.stderr)
        sys.exit(1)

    replay_session = JSONRPCSession(socket_path)
    try:
        require_error(
            replay_session.request(900, "auth.login", {"token": debug_token}),
            "auth.login replay",
            -32001,
            "unauthenticated",
        )
    finally:
        replay_session.close()

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

    command_list = require_success(
        session.request(6, "command.list", {}),
        "command.list",
    )
    commands = command_list.get("commands", [])
    if not commands:
        print("command.list returned no commands", file=sys.stderr)
        sys.exit(1)
    command_bar_entry = next(
        (
            command
            for command in commands
            if command.get("id") == "showCommandBarCommands"
        ),
        None,
    )
    if command_bar_entry is None:
        print("command.list did not include showCommandBarCommands", file=sys.stderr)
        sys.exit(1)
    if command_bar_entry.get("title") != "Command Palette":
        print(f"showCommandBarCommands title mismatch: {command_bar_entry}", file=sys.stderr)
        sys.exit(1)
    repo_visibility_entry = next(
        (
            command
            for command in commands
            if command.get("id") == "setRepoSidebarVisibilityMode"
        ),
        None,
    )
    if repo_visibility_entry is None:
        print("command.list did not include setRepoSidebarVisibilityMode", file=sys.stderr)
        sys.exit(1)
    repo_visibility_arguments = repo_visibility_entry.get("argumentSchema", [])
    if repo_visibility_arguments != [
        {
            "name": "mode",
            "kind": {"type": "stringEnum", "values": ["all", "favoritesOnly"]},
            "isRequired": True,
        }
    ]:
        print(
            f"setRepoSidebarVisibilityMode argument schema mismatch: {repo_visibility_entry}",
            file=sys.stderr,
        )
        sys.exit(1)
    repo_sort_entry = next(
        (
            command
            for command in commands
            if command.get("id") == "setRepoSidebarSortOrder"
        ),
        None,
    )
    if repo_sort_entry is None:
        print("command.list did not include setRepoSidebarSortOrder", file=sys.stderr)
        sys.exit(1)
    repo_sort_arguments = repo_sort_entry.get("argumentSchema", [])
    if repo_sort_arguments != [
        {
            "name": "order",
            "kind": {"type": "stringEnum", "values": ["ascending", "descending"]},
            "isRequired": True,
        }
    ]:
        print(
            f"setRepoSidebarSortOrder argument schema mismatch: {repo_sort_entry}",
            file=sys.stderr,
        )
        sys.exit(1)
    allowed_command_keys = {
        "id",
        "title",
        "executionModes",
        "targetKinds",
        "requiredPrivileges",
        "argumentSchema",
    }
    for command in commands:
        unexpected_keys = set(command.keys()) - allowed_command_keys
        if unexpected_keys:
            print(
                f"command.list leaked non-IPC command metadata keys {sorted(unexpected_keys)}: {command}",
                file=sys.stderr,
            )
            sys.exit(1)

    require_error(
        session.request(
            7,
            "command.execute",
            {"commandId": "showCommandBarCommands", "targetHandle": None},
        ),
        "command.execute showCommandBarCommands",
        -32003,
        "requires presentation",
    )

    repo_visibility_favorites = require_success(
        session.request(
            8,
            "command.execute",
            {
                "commandId": "setRepoSidebarVisibilityMode",
                "targetHandle": None,
                "arguments": {"mode": "favoritesOnly"},
            },
        ),
        "command.execute setRepoSidebarVisibilityMode favoritesOnly",
    )
    if repo_visibility_favorites.get("applied") is not True:
        print(f"repo visibility favoritesOnly command did not apply: {repo_visibility_favorites}", file=sys.stderr)
        sys.exit(1)

    repo_visibility_all = require_success(
        session.request(
            9,
            "command.execute",
            {
                "commandId": "setRepoSidebarVisibilityMode",
                "targetHandle": None,
                "arguments": {"mode": "all"},
            },
        ),
        "command.execute setRepoSidebarVisibilityMode all",
    )
    if repo_visibility_all.get("applied") is not True:
        print(f"repo visibility all command did not apply: {repo_visibility_all}", file=sys.stderr)
        sys.exit(1)

    require_error(
        session.request(
            10,
            "command.execute",
            {
                "commandId": "setRepoSidebarVisibilityMode",
                "targetHandle": None,
                "arguments": {"mode": "recent"},
            },
        ),
        "command.execute setRepoSidebarVisibilityMode invalid mode",
        -32007,
        "validation rejected",
    )

    repo_sort_descending = require_success(
        session.request(
            101,
            "command.execute",
            {
                "commandId": "setRepoSidebarSortOrder",
                "targetHandle": None,
                "arguments": {"order": "descending"},
            },
        ),
        "command.execute setRepoSidebarSortOrder descending",
    )
    if repo_sort_descending.get("applied") is not True:
        print(f"repo sort descending command did not apply: {repo_sort_descending}", file=sys.stderr)
        sys.exit(1)

    repo_sort_ascending = require_success(
        session.request(
            102,
            "command.execute",
            {
                "commandId": "setRepoSidebarSortOrder",
                "targetHandle": None,
                "arguments": {"order": "ascending"},
            },
        ),
        "command.execute setRepoSidebarSortOrder ascending",
    )
    if repo_sort_ascending.get("applied") is not True:
        print(f"repo sort ascending command did not apply: {repo_sort_ascending}", file=sys.stderr)
        sys.exit(1)

    require_error(
        session.request(
            103,
            "command.execute",
            {
                "commandId": "setRepoSidebarSortOrder",
                "targetHandle": None,
                "arguments": {"order": "currentRepoOrder"},
            },
        ),
        "command.execute setRepoSidebarSortOrder invalid order",
        -32007,
        "validation rejected",
    )

    command_bar_open = require_success(
        session.request(
            11,
            "ui.commandBar.open",
            {"scope": "commands"},
        ),
        "ui.commandBar.open commands",
    )
    if command_bar_open.get("scope") != "commands":
        print(f"ui.commandBar.open did not report commands scope: {command_bar_open}", file=sys.stderr)
        sys.exit(1)
    if not command_bar_open.get("workspaceWindowId"):
        print(f"ui.commandBar.open result missing workspaceWindowId: {command_bar_open}", file=sys.stderr)
        sys.exit(1)

    def execute_sidebar_command(request_id, command_id):
        result = require_success(
            session.request(
                request_id,
                "command.execute",
                {"commandId": command_id, "targetHandle": None, "arguments": {}},
            ),
            f"command.execute {command_id}",
        )
        if result.get("applied") is not True:
            print(f"{command_id} did not apply: {result}", file=sys.stderr)
            sys.exit(1)

    sidebar_command_expectations = [
        (12, "showWorktreeSidebar"),
        (13, "setRepoSidebarGroupingRepo"),
        (14, "setRepoSidebarGroupingPane"),
        (15, "setRepoSidebarGroupingTab"),
        (16, "showInboxNotifications"),
        (17, "setInboxGroupingTab"),
        (18, "setInboxGroupingRepo"),
        (19, "setInboxGroupingPane"),
        (20, "setInboxGroupingNone"),
    ]
    for request_id, command_id in sidebar_command_expectations:
        execute_sidebar_command(request_id, command_id)

    repo_grouping = require_success(
        session.request(21, "sidebar.grouping.get", {"surface": "repo"}),
        "sidebar.grouping.get repo",
    )
    if repo_grouping.get("mode") != "tab":
        print(f"repo grouping did not persist tab mode: {repo_grouping}", file=sys.stderr)
        sys.exit(1)

    inbox_grouping = require_success(
        session.request(22, "sidebar.grouping.get", {"surface": "inbox"}),
        "sidebar.grouping.get inbox",
    )
    if inbox_grouping.get("mode") != "none":
        print(f"inbox grouping did not persist none mode: {inbox_grouping}", file=sys.stderr)
        sys.exit(1)

    sidebar_surface = require_success(
        session.request(23, "sidebar.surface.get", {}),
        "sidebar.surface.get",
    )
    if sidebar_surface.get("surface") != "inbox":
        print(f"sidebar surface did not persist inbox: {sidebar_surface}", file=sys.stderr)
        sys.exit(1)

    require_error(
        session.request(
            24,
            "sidebar.grouping.set",
            {"surface": "repo", "mode": "none"},
        ),
        "sidebar.grouping.set removed route",
        -32601,
        "method not found",
    )

    print(f"AgentStudio IPC Phase A smoke passed for {canonical_pane_handle}")
finally:
    session.close()
PY
