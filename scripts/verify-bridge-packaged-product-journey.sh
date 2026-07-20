#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOURNEY_STATE_FILE="${AGENTSTUDIO_BRIDGE_PACKAGED_JOURNEY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-bridge-packaged-product-journey.env}"
LSOF_BIN="${AGENTSTUDIO_LSOF_BIN:-/usr/sbin/lsof}"
GIT_BIN=/usr/bin/git
SHASUM_BIN=/usr/bin/shasum

if [ "${1:-}" = "--dry-run" ]; then
  cat <<'DRY_RUN'
dry-run ok: binds bundle/executable/assets to the current candidate
dry-run ok: uses one persistent authenticated semantic IPC session
dry-run ok: requires exactly 257 initial Review diffs and retains the 100-diff floor before IPC authentication
dry-run ok: proves Review early/middle/final traversal
dry-run ok: proves two independent panes and hidden-to-foreground refresh
dry-run ok: binds Victoria marker and proof token
dry-run ok: leaves the candidate available for PID-targeted Peekaboo
dry-run ok: requires visible document and live RAF; no frame_not_live skip
DRY_RUN
  exit 0
fi

if [ "$#" -ne 0 ]; then
  echo "usage: verify-bridge-packaged-product-journey.sh [--dry-run]" >&2
  exit 2
fi

decode_state_value() {
  /usr/bin/python3 - "$1" <<'PY'
import shlex
import sys

try:
    values = shlex.split(sys.argv[1])
except ValueError:
    values = []
print(values[0] if values else "")
PY
}

fixture_digest_for_current_worktree() {
  local fixture_path="${1:?missing fixture path}"
  local fixture_baseline="${2:?missing fixture baseline}"
  local content_oid
  {
    printf 'baseline\0%s\0' "$fixture_baseline"
    while IFS= read -r -d '' relative_path; do
      content_oid="$($GIT_BIN -C "$fixture_path" hash-object -- "$relative_path")"
      printf 'path\0%s\0blob\0%s\0' "$relative_path" "$content_oid"
    done < <("$GIT_BIN" -C "$fixture_path" ls-files -z)
  } | "$SHASUM_BIN" -a 256 | awk '{ print $1 }'
}

journey_status=""
observability_state_file=""
fixture_root=""
expected_file_count=""
expected_review_diff_count=""
expected_fixture_digest=""
baseline_commit=""
early_path=""
middle_path=""
final_path=""
tracked_path=""

if [ ! -f "$JOURNEY_STATE_FILE" ]; then
  echo "Bridge packaged journey state is missing: $JOURNEY_STATE_FILE" >&2
  exit 1
fi

while IFS='=' read -r key raw_value; do
  value="$(decode_state_value "$raw_value")"
  case "$key" in
    AGENTSTUDIO_BRIDGE_JOURNEY_STATUS) journey_status="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_OBSERVABILITY_STATE_FILE) observability_state_file="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_FIXTURE_ROOT) fixture_root="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_EXPECTED_FILE_COUNT) expected_file_count="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_EXPECTED_REVIEW_DIFF_COUNT) expected_review_diff_count="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_FIXTURE_DIGEST) expected_fixture_digest="$value" ;;
    BASELINE_COMMIT) baseline_commit="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_EARLY_PATH) early_path="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_MIDDLE_PATH) middle_path="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_FINAL_PATH) final_path="$value" ;;
    AGENTSTUDIO_BRIDGE_JOURNEY_TRACKED_PATH) tracked_path="$value" ;;
  esac
done <"$JOURNEY_STATE_FILE"

if [ "$journey_status" != "running" ]; then
  echo "Bridge packaged journey is not running: ${journey_status:-<missing>}" >&2
  exit 1
fi
if [ ! -f "$observability_state_file" ]; then
  echo "Bridge packaged journey observability state is missing: ${observability_state_file:-<missing>}" >&2
  exit 1
fi
if [ ! -d "$fixture_root/.git" ]; then
  echo "Bridge packaged journey fixture is not a Git worktree: ${fixture_root:-<missing>}" >&2
  exit 1
fi
case "$expected_file_count" in
  ''|*[!0-9]*)
    echo "Bridge packaged journey expected file count is invalid: ${expected_file_count:-<missing>}" >&2
    exit 1
    ;;
esac
case "$expected_review_diff_count" in
  ''|*[!0-9]*)
    echo "Bridge packaged journey expected Review diff count is invalid: $expected_review_diff_count" >&2
    exit 1
    ;;
esac
if [ "$expected_file_count" -ne 257 ]; then
  echo "Bridge packaged journey expected file count must be exactly 257: $expected_file_count" >&2
  exit 1
fi
if [ "$expected_review_diff_count" -ne "$expected_file_count" ]; then
  echo "Bridge packaged journey expected Review diff count must equal expected file count: expected $expected_file_count, observed $expected_review_diff_count" >&2
  exit 1
fi
if [ "$expected_review_diff_count" -lt 100 ]; then
  echo "Bridge packaged journey rejects fewer than 100 initial Review diffs: $expected_review_diff_count" >&2
  exit 1
fi
case "$expected_fixture_digest" in
  ''|*[!0-9a-f]*)
    echo "Bridge packaged journey fixture digest is invalid" >&2
    exit 1
    ;;
esac
if [ "${#expected_fixture_digest}" -ne 64 ]; then
  echo "Bridge packaged journey fixture digest is invalid" >&2
  exit 1
fi
if [ -z "$baseline_commit" ] \
  || ! "$GIT_BIN" -C "$fixture_root" cat-file -e "$baseline_commit^{commit}" 2>/dev/null; then
  echo "Bridge packaged journey baseline commit is invalid" >&2
  exit 1
fi
actual_review_diff_count="$(
  "$GIT_BIN" -C "$fixture_root" diff --name-only "$baseline_commit" -- \
    | awk 'NF { count += 1 } END { print count + 0 }'
)"
if [ "$actual_review_diff_count" -ne "$expected_review_diff_count" ]; then
  echo "Bridge packaged journey initial Review diff count mismatch: expected $expected_review_diff_count, observed $actual_review_diff_count" >&2
  exit 1
fi
actual_fixture_digest="$(fixture_digest_for_current_worktree "$fixture_root" "$baseline_commit")"
if [ "$actual_fixture_digest" != "$expected_fixture_digest" ]; then
  echo "Bridge packaged journey fixture digest mismatch" >&2
  exit 1
fi
for required_path in "$early_path" "$middle_path" "$final_path" "$tracked_path"; do
  if [ -z "$required_path" ] || [ ! -f "$fixture_root/$required_path" ]; then
    echo "Bridge packaged journey sentinel is missing: ${required_path:-<missing>}" >&2
    exit 1
  fi
done

state_status=""
state_pid=""
state_app=""
state_executable=""
state_data_dir=""
state_launch_method=""
state_marker=""
state_proof_token=""
while IFS='=' read -r key raw_value; do
  value="$(decode_state_value "$raw_value")"
  case "$key" in
    AGENTSTUDIO_OBSERVABILITY_STATUS) state_status="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_PID) state_pid="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_APP) state_app="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_EXECUTABLE) state_executable="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_DATA_DIR) state_data_dir="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD) state_launch_method="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_MARKER) state_marker="$value" ;;
    AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN) state_proof_token="$value" ;;
  esac
done <"$observability_state_file"

if [ "$state_status" != "running" ] || [ "$state_launch_method" != "launchservices" ]; then
  echo "Bridge packaged journey requires a running strict LaunchServices candidate" >&2
  exit 1
fi
case "$state_pid" in
  ''|*[!0-9]*)
    echo "Bridge packaged journey state is missing a numeric PID" >&2
    exit 1
    ;;
esac
if ! kill -0 "$state_pid" >/dev/null 2>&1; then
  echo "Bridge packaged journey PID is not running: $state_pid" >&2
  exit 1
fi
if [ -z "$state_app" ] || [ -z "$state_executable" ] || [ ! -x "$state_executable" ]; then
  echo "Bridge packaged journey app/executable identity is incomplete" >&2
  exit 1
fi
actual_executable="$($LSOF_BIN -a -p "$state_pid" -d txt -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }')"
expected_executable="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$state_executable")"
actual_executable="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$actual_executable")"
if [ "$actual_executable" != "$expected_executable" ]; then
  echo "Bridge packaged journey executable does not match the live PID" >&2
  exit 1
fi
case "$expected_executable" in
  "$state_app"/Contents/MacOS/AgentStudio) ;;
  *)
    echo "Bridge packaged journey executable is not inside the recorded app bundle" >&2
    exit 1
    ;;
esac

/usr/bin/codesign --verify --deep --strict "$state_app"
packaged_bridge_web="$state_app/Contents/Resources/AgentStudio_AgentStudio.bundle/BridgeWeb/app"
source_bridge_web="$PROJECT_ROOT/Sources/AgentStudio/Resources/BridgeWeb/app"
for required_asset in \
  index.html \
  agentstudio-app-assets.json \
  assets/bridge-app.js \
  assets/bridge-comm-worker.js \
  assets/bridge-telemetry-worker.js \
  assets/bridge-markdown-render-worker.js \
  workers/pierre-diffs-worker-portable.js; do
  if [ ! -f "$packaged_bridge_web/$required_asset" ]; then
    echo "Bridge packaged journey bundle is missing asset: $required_asset" >&2
    exit 1
  fi
done
if ! cmp -s "$source_bridge_web/agentstudio-app-assets.json" "$packaged_bridge_web/agentstudio-app-assets.json"; then
  echo "Bridge packaged journey asset manifest does not match the current source build" >&2
  exit 1
fi
audit_file="$PROJECT_ROOT/tmp/bridge-web-assets/latest-app-asset-audit.json"
if [ ! -f "$audit_file" ]; then
  echo "Bridge packaged journey asset audit is missing" >&2
  exit 1
fi
audit_commit="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["git"]["commit"])' "$audit_file")"
candidate_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
if [ "$audit_commit" != "$candidate_commit" ]; then
  echo "Bridge packaged journey asset audit commit is stale" >&2
  exit 1
fi

AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$observability_state_file" \
  AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1 \
  /bin/bash "$PROJECT_ROOT/scripts/verify-debug-observability.sh"
AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$observability_state_file" \
  /bin/bash "$PROJECT_ROOT/scripts/verify-bridge-product-paint-correlation.sh"

ipc_metadata="$state_data_dir/ipc/runtime.json"
ipc_token="$state_data_dir/ipc/debug-token"
if [ ! -f "$ipc_metadata" ] || [ ! -f "$ipc_token" ]; then
  echo "Bridge packaged journey requires fresh one-shot authenticated IPC escrow" >&2
  exit 1
fi

AGENTSTUDIO_BRIDGE_JOURNEY_MARKER="$state_marker" \
AGENTSTUDIO_BRIDGE_JOURNEY_PROOF_TOKEN="$state_proof_token" \
/usr/bin/python3 - \
  "$ipc_metadata" \
  "$ipc_token" \
  "$fixture_root" \
  "$expected_file_count" \
  "$expected_review_diff_count" \
  "$early_path" \
  "$middle_path" \
  "$final_path" \
  "$tracked_path" <<'PY'
import hashlib
import json
import os
import socket
import sys
import time

metadata_path, token_path, fixture_root = sys.argv[1:4]
expected_file_count = int(sys.argv[4])
expected_review_diff_count = int(sys.argv[5])
sentinel_paths = sys.argv[6:9]
tracked_path = sys.argv[9]
response_timeout = float(os.environ.get("AGENTSTUDIO_BRIDGE_JOURNEY_IPC_TIMEOUT_SECONDS", "20"))


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


with open(metadata_path, "r", encoding="utf-8") as file:
    metadata = json.load(file)
socket_path = metadata.get("socketPath")
if not isinstance(socket_path, str) or not socket_path:
    fail("Bridge packaged journey IPC metadata has no socketPath")
with open(token_path, "r", encoding="utf-8") as file:
    token = file.read().strip()
if not token:
    fail("Bridge packaged journey IPC token is empty")


class Session:
    def __init__(self, path):
        self._next_id = 1
        self._socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._socket.settimeout(response_timeout)
        self._socket.connect(path)
        self._reader = self._socket.makefile("rb")

    def close(self):
        self._reader.close()
        self._socket.close()

    def request(self, method, params):
        request_id = self._next_id
        self._next_id += 1
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        self._socket.sendall((json.dumps(payload, separators=(",", ":")) + "\n").encode())
        while True:
            line = self._reader.readline()
            if not line:
                fail(f"IPC closed before response for {method}")
            response = json.loads(line)
            if response.get("id") != request_id:
                continue
            if response.get("error") is not None:
                fail(f"{method} failed: {response['error']}")
            return response.get("result", {})


def wait_for(label, read, accept, attempts=120):
    last = None
    for _ in range(attempts):
        last = read()
        if accept(last):
            return last
        time.sleep(0.1)
    fail(f"{label} did not become ready: {last}")


def require_control(result, method, item_id=None, path=None):
    if result.get("method") != method or result.get("status") != "accepted":
        fail(f"{method} was not accepted: {result}")
    if item_id is not None and result.get("itemId") != item_id:
        fail(f"{method} selected the wrong item: {result}")
    if path is not None and result.get("path") != path:
        fail(f"{method} revealed the wrong path: {result}")


def canonical(value):
    return os.path.realpath(value)


session = Session(socket_path)
try:
    login = session.request("auth.login", {"token": token})
    if login.get("authenticated") is not True or os.path.exists(token_path):
        fail("Bridge packaged journey IPC escrow was not authenticated and consumed exactly once")

    session.request("system.identify", {})
    capabilities = session.request("system.capabilities", {})
    methods = capabilities.get("methods", [])
    method_names = {
        entry if isinstance(entry, str) else entry.get("name")
        for entry in methods
        if isinstance(entry, (str, dict))
    }
    required_methods = {
        "workspace.list",
        "pane.list",
        "pane.focus",
        "pane.close",
        "bridge.diff.load",
        "bridge.diff.refresh",
        "bridge.diff.getPackage",
        "bridge.diff.renderState",
        "bridge.diff.selectFile",
        "bridge.diff.scrollToFile",
        "bridge.diff.collapseFile",
        "bridge.diff.expandFile",
        "bridge.fileTree.search",
        "bridge.fileTree.setFilter",
        "bridge.fileTree.revealPath",
        "bridge.telemetry.snapshot",
        "bridge.telemetry.flush",
    }
    missing = sorted(required_methods - method_names)
    if missing:
        fail(f"Bridge packaged journey IPC capabilities are missing: {missing}")

    def fixture_worktree():
        workspaces = session.request("workspace.list", {}).get("workspaces", [])
        for workspace in workspaces:
            for repository in workspace.get("repositories", []):
                for worktree in repository.get("worktrees", []):
                    if canonical(worktree.get("path", "")) == canonical(fixture_root):
                        return worktree
        return None

    worktree = wait_for("fixture workspace registration", fixture_worktree, lambda value: value is not None)
    worktree_id = worktree.get("id")
    if not worktree_id:
        fail("Bridge packaged journey fixture worktree has no canonical id")

    panes = session.request("pane.list", {}).get("panes", [])
    file_pane = next(
        (
            pane
            for pane in panes
            if pane.get("contentKind") == "bridgePanel" and pane.get("worktreeId") == worktree_id
        ),
        None,
    )
    if file_pane is None:
        fail("Bridge packaged journey startup File pane is missing")
    file_handle = f"pane:{file_pane['id']}"

    review_open = session.request("bridge.diff.load", {"worktreeId": worktree_id})
    review_handle = review_open.get("handle")
    if not isinstance(review_handle, str) or review_handle == file_handle:
        fail("Bridge packaged journey did not create two independent panes")
    session.request("pane.focus", {"handle": review_handle})

    source_hash_by_path = {}
    corpus_paths = []
    for directory, _, filenames in os.walk(os.path.join(fixture_root, "tree")):
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                corpus_paths.append(os.path.relpath(os.path.join(directory, filename), fixture_root))
    corpus_paths.sort()
    if len(corpus_paths) != expected_file_count - 1:
        fail(
            f"Bridge packaged journey corpus count mismatch: "
            f"expected {expected_file_count - 1}, observed {len(corpus_paths)}"
        )
    for relative_path in corpus_paths:
        absolute_path = os.path.join(fixture_root, relative_path)
        if relative_path in sentinel_paths:
            with open(absolute_path, "rb") as file:
                source_hash_by_path[relative_path] = hashlib.sha256(file.read()).hexdigest()
    if set(source_hash_by_path) != set(sentinel_paths):
        fail("Bridge packaged journey failed to hash every traversal sentinel")

    def read_package():
        return session.request("bridge.diff.getPackage", {"handle": review_handle})

    initial_package = wait_for(
        "initial Review package",
        read_package,
        lambda value: value.get("status") == "ready"
        and value.get("summary", {}).get("filesChanged") == expected_review_diff_count
        and len(value.get("items", [])) == expected_review_diff_count,
    )
    generation_before = initial_package.get("reviewGeneration")
    if not isinstance(generation_before, int):
        fail("Initial Review package has no generation")

    session.request("bridge.diff.refresh", {"handle": review_handle})

    package = wait_for(
        "refreshed Review package",
        read_package,
        lambda value: value.get("status") == "ready"
        and value.get("summary", {}).get("filesChanged") == expected_review_diff_count
        and len(value.get("items", [])) == expected_review_diff_count
        and value.get("reviewGeneration") is not None
        and value.get("reviewGeneration") > generation_before,
    )
    items_by_path = {item.get("displayPath"): item for item in package.get("items", [])}
    missing_paths = [path for path in sentinel_paths if path not in items_by_path]
    if missing_paths:
        fail(f"Review package omitted traversal sentinels: {missing_paths}")

    def read_review_page():
        return session.request("bridge.diff.renderState", {"handle": review_handle})

    review_page = wait_for(
        "refreshed Review page metadata",
        read_review_page,
        lambda value: value.get("diagnostics", {}).get("evaluateSucceeded") is True
        and value.get("diagnostics", {}).get("pageErrorCount") == 0
        and value.get("summary", {}).get("activeViewerMode") == "review"
        and value.get("summary", {}).get("reviewMetadataGeneration")
        == package.get("reviewGeneration")
        and value.get("summary", {}).get("reviewMetadataItemCount")
        == expected_review_diff_count
        and (value.get("summary", {}).get("reviewMetadataTreeRowCount") or 0)
        >= expected_review_diff_count,
    )

    for position, relative_path in zip(("early", "middle", "final"), sentinel_paths):
        item = items_by_path[relative_path]
        item_id = item.get("itemId")
        query = os.path.basename(relative_path)
        search = session.request(
            "bridge.fileTree.search",
            {"handle": review_handle, "searchText": query, "searchMode": {"kind": "text"}},
        )
        require_control(search, "bridge.fileTree.search")
        if search.get("treeSearchText") != query:
            fail(f"Review {position} search receipt is stale: {search}")
        filter_result = session.request(
            "bridge.fileTree.setFilter",
            {"handle": review_handle, "gitStatusFilter": "all", "fileClassFilter": "all"},
        )
        require_control(filter_result, "bridge.fileTree.setFilter")
        reveal = session.request(
            "bridge.fileTree.revealPath", {"handle": review_handle, "path": relative_path}
        )
        require_control(reveal, "bridge.fileTree.revealPath", item_id=item_id, path=relative_path)
        selected = session.request(
            "bridge.diff.selectFile", {"handle": review_handle, "itemId": item_id}
        )
        if selected.get("selected") is not True or selected.get("itemId") != item_id:
            fail(f"Review {position} select failed: {selected}")
        scroll = session.request(
            "bridge.diff.scrollToFile", {"handle": review_handle, "itemId": item_id}
        )
        require_control(scroll, "bridge.diff.scrollToFile", item_id=item_id)
        collapsed = session.request(
            "bridge.diff.collapseFile", {"handle": review_handle, "itemId": item_id}
        )
        require_control(collapsed, "bridge.diff.collapseFile", item_id=item_id)
        expanded = session.request(
            "bridge.diff.expandFile", {"handle": review_handle, "itemId": item_id}
        )
        require_control(expanded, "bridge.diff.expandFile", item_id=item_id)

        def selected_render_state():
            return session.request("bridge.diff.renderState", {"handle": review_handle})

        wait_for(
            f"Review {position} painted selection",
            selected_render_state,
            lambda value: value.get("diagnostics", {}).get("evaluateSucceeded") is True
            and value.get("diagnostics", {}).get("pageErrorCount") == 0
            and value.get("summary", {}).get("activeViewerMode") == "review"
            and value.get("summary", {}).get("documentVisibilityState") == "visible"
            and value.get("summary", {}).get("frameLivenessRafAlive") == "true"
            and value.get("summary", {}).get("reviewSelectedItemId") == item_id
            and (value.get("summary", {}).get("reviewCodeTextLength") or 0) > 0,
        )
        selected_package = read_package()
        if selected_package.get("selectedItemId") != item_id:
            fail(f"Review {position} native selection diverged from DOM selection")

    session.request("pane.focus", {"handle": file_handle})

    def reveal_final_file():
        return session.request(
            "bridge.fileTree.revealPath", {"handle": file_handle, "path": sentinel_paths[-1]}
        )

    final_reveal = wait_for(
        "File final-path reveal",
        reveal_final_file,
        lambda value: value.get("status") == "accepted" and value.get("path") == sentinel_paths[-1],
    )
    require_control(final_reveal, "bridge.fileTree.revealPath", path=sentinel_paths[-1])
    final_search = session.request(
        "bridge.fileTree.search",
        {
            "handle": file_handle,
            "searchText": os.path.basename(sentinel_paths[-1]),
            "searchMode": {"kind": "text"},
        },
    )
    require_control(final_search, "bridge.fileTree.search")

    def final_file_render_state():
        return session.request("bridge.diff.renderState", {"handle": file_handle})

    wait_for(
        "File final-path painted content",
        final_file_render_state,
        lambda value: value.get("diagnostics", {}).get("evaluateSucceeded") is True
        and value.get("diagnostics", {}).get("pageErrorCount") == 0
        and value.get("summary", {}).get("activeViewerMode") == "file"
        and value.get("summary", {}).get("documentVisibilityState") == "visible"
        and value.get("summary", {}).get("frameLivenessRafAlive") == "true"
        and value.get("summary", {}).get("worktreeRenderedFilePath") == sentinel_paths[-1]
        and value.get("summary", {}).get("worktreeOpenFilePath") == sentinel_paths[-1]
        and (value.get("summary", {}).get("worktreeCodeTextLength") or 0) > 0,
    )

    session.request("pane.focus", {"handle": review_handle})
    session.request("pane.focus", {"handle": file_handle})
    for handle in (review_handle, file_handle):
        snapshot = session.request("bridge.telemetry.snapshot", {"handle": handle})
        if snapshot.get("kind") != "report":
            fail(f"Bridge telemetry snapshot unavailable for {handle}: {snapshot}")
        flushed = session.request("bridge.telemetry.flush", {"handle": handle})
        if flushed.get("kind") != "report" or flushed.get("drained") is not True:
            fail(f"Bridge telemetry did not drain/reopen for {handle}: {flushed}")

    session.request("pane.close", {"handle": review_handle})
    marker = os.environ.get("AGENTSTUDIO_BRIDGE_JOURNEY_MARKER", "")
    proof_token = os.environ.get("AGENTSTUDIO_BRIDGE_JOURNEY_PROOF_TOKEN", "")
    if not marker or not proof_token:
        fail("Bridge packaged journey is missing Victoria marker/proof-token binding")
    print(
        json.dumps(
            {
                "filePane": file_handle,
                "reviewPane": review_handle,
                "reviewGeneration": package.get("reviewGeneration"),
                "filesChanged": package.get("summary", {}).get("filesChanged"),
                "sentinelSha256": source_hash_by_path,
            },
            sort_keys=True,
        )
    )
finally:
    session.close()
PY

echo "Bridge packaged LaunchServices product journey PASS"
echo "pid=$state_pid"
echo "app=$state_app"
echo "fixture=$fixture_root"
echo "candidate remains available for PID-targeted Peekaboo"
