#!/bin/bash
set -u

if [ "$#" -lt 4 ]; then
  echo "usage: cleanup-owned-zmx-sessions.sh <zmx> <zmx-dir> <artifact> <session-id>..." >&2
  exit 2
fi

ZMX_EXECUTABLE="$1"
OWNED_ZMX_DIR="$2"
CLEANUP_ARTIFACT="$3"
shift 3
OWNED_SESSION_IDS=("$@")

case "$OWNED_ZMX_DIR" in
  /tmp/asw.*|/private/tmp/asw.*)
    ;;
  *)
    echo "refusing zmx cleanup outside a disposable workload root: $OWNED_ZMX_DIR" >&2
    exit 2
    ;;
esac

if [ ! -d "$OWNED_ZMX_DIR" ]; then
  echo "refusing zmx cleanup for a missing workload root: $OWNED_ZMX_DIR" >&2
  exit 2
fi

PHYSICAL_OWNED_ZMX_DIR="$(cd "$OWNED_ZMX_DIR" 2>/dev/null && pwd -P)" || {
  echo "refusing zmx cleanup for an unresolved workload root: $OWNED_ZMX_DIR" >&2
  exit 2
}

case "$PHYSICAL_OWNED_ZMX_DIR" in
  /tmp/asw.*|/private/tmp/asw.*)
    ;;
  *)
    echo "refusing zmx cleanup outside a disposable workload root: $OWNED_ZMX_DIR" >&2
    exit 2
    ;;
esac
OWNED_ZMX_DIR="$PHYSICAL_OWNED_ZMX_DIR"

INVENTORY_FILE="$CLEANUP_ARTIFACT.inventory"
CLEANUP_DEADLINE=$((SECONDS + 5))
CLEANUP_FAILED=0
UNRESOLVED_SESSION_IDS=()
remaining_session_ids=()

mkdir -p "$(dirname "$CLEANUP_ARTIFACT")"
: >"$CLEANUP_ARTIFACT"

record_value() {
  printf '%s=%q\n' "$1" "$2" >>"$CLEANUP_ARTIFACT"
}

list_sessions_with_deadline() {
  local list_pid=""
  ZMX_DIR="$OWNED_ZMX_DIR" "$ZMX_EXECUTABLE" list >"$INVENTORY_FILE" 2>>"$CLEANUP_ARTIFACT" &
  list_pid=$!
  while kill -0 "$list_pid" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$CLEANUP_DEADLINE" ]; then
      kill "$list_pid" >/dev/null 2>&1 || true
      wait "$list_pid" >/dev/null 2>&1 || true
      record_value list_error timeout
      return 1
    fi
    sleep 0.05
  done
  if ! wait "$list_pid"; then
    record_value list_error command_failed
    return 1
  fi
}

inventory_session_names() {
  sed -n -E 's/^(session_name|name)=([^[:space:]]+).*/\2/p' "$INVENTORY_FILE"
}

session_is_listed_exactly() {
  local expected_session_id="$1"
  inventory_session_names | grep -Fxq "$expected_session_id"
}

if ! list_sessions_with_deadline; then
  CLEANUP_FAILED=1
  UNRESOLVED_SESSION_IDS=("${OWNED_SESSION_IDS[@]}")
else
  for owned_session_id in "${OWNED_SESSION_IDS[@]}"; do
    collision_name="$(inventory_session_names | awk -v owned="$owned_session_id" 'index($0, owned) == 1 && $0 != owned { print; exit }')"
    if [ -n "$collision_name" ]; then
      record_value collision_owned_id "$owned_session_id"
      record_value collision_session_name "$collision_name"
      UNRESOLVED_SESSION_IDS+=("$owned_session_id")
      CLEANUP_FAILED=1
      continue
    fi
    if session_is_listed_exactly "$owned_session_id"; then
      record_value attempted_session_id "$owned_session_id"
      if ! ZMX_DIR="$OWNED_ZMX_DIR" "$ZMX_EXECUTABLE" kill "$owned_session_id" >>"$CLEANUP_ARTIFACT" 2>&1; then
        record_value kill_error_session_id "$owned_session_id"
        CLEANUP_FAILED=1
      fi
    else
      record_value already_absent_session_id "$owned_session_id"
    fi
  done
fi

while [ "$SECONDS" -lt "$CLEANUP_DEADLINE" ]; do
  if ! list_sessions_with_deadline; then
    CLEANUP_FAILED=1
    break
  fi
  remaining_session_ids=()
  for owned_session_id in "${OWNED_SESSION_IDS[@]}"; do
    if session_is_listed_exactly "$owned_session_id"; then
      remaining_session_ids+=("$owned_session_id")
    fi
  done
  if [ "${#remaining_session_ids[@]}" -eq 0 ]; then
    break
  fi
  sleep 0.05
done

for owned_session_id in "${remaining_session_ids[@]:-}"; do
  [ -n "$owned_session_id" ] || continue
  UNRESOLVED_SESSION_IDS+=("$owned_session_id")
  CLEANUP_FAILED=1
done
for owned_session_id in "${UNRESOLVED_SESSION_IDS[@]:-}"; do
  [ -n "$owned_session_id" ] || continue
  record_value unresolved_session_id "$owned_session_id"
done

record_value zmx_dir "$OWNED_ZMX_DIR"
if [ "$CLEANUP_FAILED" -ne 0 ]; then
  record_value cleanup_status failed
  exit 1
fi
record_value cleanup_status verified_clean
