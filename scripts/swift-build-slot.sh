#!/usr/bin/env bash
# Source, then acquire one named worktree-local slot. Callers own the EXIT trap
# and invoke swift_build_slot_release from that handler.

swift_build_slot_process_start_time() {
  local process_id="$1"
  LC_ALL=C ps -p "$process_id" -o lstart= 2>/dev/null | /usr/bin/sed 's/^[[:space:]]*//'
}

swift_build_slot_holder_is_same_process() {
  local process_id="$1"
  local expected_start_time="$2"
  local actual_start_time

  [[ "$process_id" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$process_id" 2>/dev/null || return 1
  actual_start_time="$(swift_build_slot_process_start_time "$process_id")"
  [ -n "$actual_start_time" ] && [ "$actual_start_time" = "$expected_start_time" ]
}

swift_build_slot_resolve_directory() {
  case "$1" in
    build) printf '%s\n' '.build-agent-1' ;;
    test) printf '%s\n' '.build-agent-2' ;;
    *)
      echo "swift-build-slot: expected slot 'build' or 'test', got '$1'" >&2
      return 2
      ;;
  esac
}

swift_build_slot_reap_stale_reaper_lock() {
  local reaper_directory="$1"
  local reaper_process_id reaper_start_time
  local confirmed_process_id confirmed_start_time
  local stale_reaper_directory

  if ! IFS=$'\t' read -r reaper_process_id reaper_start_time < "$reaper_directory/holder" 2>/dev/null ||
    swift_build_slot_holder_is_same_process "$reaper_process_id" "$reaper_start_time"
  then
    return 1
  fi

  if ! IFS=$'\t' read -r confirmed_process_id confirmed_start_time < "$reaper_directory/holder" 2>/dev/null ||
    [ "$confirmed_process_id" != "$reaper_process_id" ] ||
    [ "$confirmed_start_time" != "$reaper_start_time" ] ||
    swift_build_slot_holder_is_same_process "$confirmed_process_id" "$confirmed_start_time"
  then
    return 1
  fi

  stale_reaper_directory="${reaper_directory}.stale.${reaper_process_id}.$$.${RANDOM}"
  if ! mv "$reaper_directory" "$stale_reaper_directory" 2>/dev/null; then
    return 1
  fi

  /bin/rm -f "$stale_reaper_directory/holder"
  if ! rmdir "$stale_reaper_directory" 2>/dev/null; then
    return 1
  fi
  echo "[swift-build-slot] reaped stale reaper lock pid=$reaper_process_id start=$reaper_start_time"
}

swift_build_slot_release_reaper_lock() {
  local reaper_directory="$1"
  local expected_process_id="$2"
  local expected_start_time="$3"
  local current_process_id current_start_time

  if IFS=$'\t' read -r current_process_id current_start_time < "$reaper_directory/holder" 2>/dev/null &&
    [ "$current_process_id" = "$expected_process_id" ] &&
    [ "$current_start_time" = "$expected_start_time" ]
  then
    /bin/rm -f "$reaper_directory/holder"
    rmdir "$reaper_directory" 2>/dev/null || true
  fi
}

swift_build_slot_release_dead_claim() {
  local slot_name="$1"
  local claim_directory="$2"
  local expected_process_id="${3:-}"
  local expected_start_time="${4:-}"
  local current_process_id current_start_time current_task reaper_start_time
  local reaper_directory="$claim_directory/.reaper-lock"
  local build_directory="${claim_directory%/.slot-claim}"
  local stale_directory holder_metadata_valid=0 lsof_status=0

  command -v lsof >/dev/null 2>&1 || return 1

  # Only one waiter may retire a claim. Re-read under this lock so a waiter
  # cannot remove a claim another process has already replaced.
  if ! mkdir "$reaper_directory" 2>/dev/null; then
    swift_build_slot_reap_stale_reaper_lock "$reaper_directory" || return 1
    mkdir "$reaper_directory" 2>/dev/null || return 1
  fi
  reaper_start_time="$(swift_build_slot_process_start_time "$$")"
  if [ -z "$reaper_start_time" ] ||
    ! printf '%s\t%s\n' "$$" "$reaper_start_time" > "$reaper_directory/holder"
  then
    /bin/rm -f "$reaper_directory/holder"
    rmdir "$reaper_directory" 2>/dev/null || true
    return 1
  fi
  if IFS=$'\t' read -r current_process_id current_start_time current_task \
    < "$claim_directory/holder" 2>/dev/null &&
    [[ "$current_process_id" =~ ^[0-9]+$ ]] &&
    [ -n "$current_start_time" ] &&
    [ -n "$current_task" ]
  then
    holder_metadata_valid=1
  fi

  if [ -n "$expected_process_id" ]; then
    if [ "$holder_metadata_valid" -ne 1 ] ||
      [ "$current_process_id" != "$expected_process_id" ] ||
      [ "$current_start_time" != "$expected_start_time" ] ||
      swift_build_slot_holder_is_same_process "$current_process_id" "$current_start_time"
    then
      swift_build_slot_release_reaper_lock "$reaper_directory" "$$" "$reaper_start_time"
      return 1
    fi
    lsof +D "$build_directory" >/dev/null 2>&1 || lsof_status=$?
    if [ "$lsof_status" -ne 1 ]; then
      swift_build_slot_release_reaper_lock "$reaper_directory" "$$" "$reaper_start_time"
      return 1
    fi
    stale_directory="$build_directory/.slot-claim.stale.$current_process_id.$$"
  else
    # An empty or malformed holder can be a legacy claim or an interrupted
    # foreign writer. Re-read it under the reaper lock and only retire it when
    # lsof confirms that nothing has the claim directory open.
    if [ "$holder_metadata_valid" -eq 1 ]; then
      swift_build_slot_release_reaper_lock "$reaper_directory" "$$" "$reaper_start_time"
      return 1
    fi
    lsof +D "$claim_directory" >/dev/null 2>&1 || lsof_status=$?
    if [ "$lsof_status" -ne 1 ]; then
      swift_build_slot_release_reaper_lock "$reaper_directory" "$$" "$reaper_start_time"
      return 1
    fi
    stale_directory="$build_directory/.slot-claim.stale.holderless.$$.$RANDOM"
  fi

  if mv "$claim_directory" "$stale_directory" 2>/dev/null; then
    swift_build_slot_release_reaper_lock \
      "$stale_directory/.reaper-lock" "$$" "$reaper_start_time"
    /bin/rm -f "$stale_directory/holder"
    if ! rmdir "$stale_directory" 2>/dev/null; then
      return 1
    fi
    if [ -n "$expected_process_id" ]; then
      echo "[swift-build-slot] reaped stale slot=$slot_name task=$current_task pid=$current_process_id start=$current_start_time"
    else
      echo "[swift-build-slot] reaped holder-less claim slot=$slot_name"
    fi
    return 0
  fi

  swift_build_slot_release_reaper_lock "$reaper_directory" "$$" "$reaper_start_time"
  return 1
}

swift_build_slot_discard_unpublished_claim() {
  local temporary_directory="$1"
  [ -d "$temporary_directory" ] || return 0
  /bin/rm -f "$temporary_directory/holder"
  rmdir "$temporary_directory" 2>/dev/null
}

swift_build_slot_create_atomic_claim() {
  local requested_slot="$1"
  local task_label="$2"
  local build_directory="$3"
  local claim_directory="$4"
  local temporary_directory temporary_basename nested_temporary_directory
  local holder_file process_start_time move_status=0
  local published_process_id published_start_time published_task

  if [ -e "$claim_directory" ] || [ -L "$claim_directory" ]; then
    return 1
  fi

  temporary_directory="$(mktemp -d "$build_directory/.slot-claim.XXXXXXXXXX")" || {
    echo "swift-build-slot: cannot create temporary claim in $build_directory" >&2
    return 2
  }
  holder_file="$temporary_directory/holder"
  temporary_basename="${temporary_directory##*/}"
  nested_temporary_directory="$claim_directory/$temporary_basename"

  if ! exec 99>"$holder_file"; then
    swift_build_slot_discard_unpublished_claim "$temporary_directory" || true
    echo "swift-build-slot: cannot create holder metadata for slot $requested_slot" >&2
    return 2
  fi
  process_start_time="$(swift_build_slot_process_start_time "$$")"
  if [ -z "$process_start_time" ]; then
    exec 99>&-
    swift_build_slot_discard_unpublished_claim "$temporary_directory" || true
    echo "swift-build-slot: cannot read current process start time" >&2
    return 2
  fi
  if ! printf '%s\t%s\t%s\n' "$$" "$process_start_time" "$task_label" >&99; then
    exec 99>&-
    swift_build_slot_discard_unpublished_claim "$temporary_directory" || true
    echo "swift-build-slot: cannot write holder metadata for slot $requested_slot" >&2
    return 2
  fi

  # -n prevents replacement if another claimant publishes first. Verify the
  # holder at the destination because BSD mv treats an existing directory as a
  # container and may otherwise move the temporary claim inside it.
  if mv -n "$temporary_directory" "$claim_directory" 2>/dev/null; then
    move_status=0
  else
    move_status=$?
  fi
  if IFS=$'\t' read -r published_process_id published_start_time published_task \
    < "$claim_directory/holder" 2>/dev/null &&
    [ "$published_process_id" = "$$" ] &&
    [ "$published_start_time" = "$process_start_time" ] &&
    [ "$published_task" = "$task_label" ] &&
    [ ! -e "$temporary_directory" ] &&
    [ ! -e "$nested_temporary_directory" ]
  then
    SWIFT_BUILD_SLOT_NAME="$requested_slot"
    SWIFT_BUILD_SLOT_CLAIM_DIRECTORY="$claim_directory"
    SWIFT_BUILD_SLOT_OWNER_PROCESS_ID="$$"
    SWIFT_BUILD_SLOT_OWNER_START_TIME="$process_start_time"
    SWIFT_BUILD_SLOT_HOLDER_FD=99
    SWIFT_BUILD_SLOT_TASK="$task_label"
    SWIFT_BUILD_DIR="$build_directory"
    export SWIFT_BUILD_DIR
    echo "[swift-build-slot] using slot=$SWIFT_BUILD_SLOT_NAME path=$SWIFT_BUILD_DIR task=$SWIFT_BUILD_SLOT_TASK"
    return 0
  fi

  exec 99>&-
  swift_build_slot_discard_unpublished_claim "$temporary_directory" || true
  swift_build_slot_discard_unpublished_claim "$nested_temporary_directory" || true
  if [ -e "$claim_directory" ] || [ -L "$claim_directory" ]; then
    return 1
  fi
  if [ "$move_status" -ne 0 ]; then
    echo "swift-build-slot: cannot publish claim for slot $requested_slot" >&2
  else
    echo "swift-build-slot: claim publication did not preserve holder metadata for slot $requested_slot" >&2
  fi
  return 2
}

swift_build_slot_legacy_holder_description() {
  local build_directory="$1"
  local process_id process_start_time process_command

  for process_id in $(lsof -t +D "$build_directory" 2>/dev/null | sort -u); do
    process_start_time="$(swift_build_slot_process_start_time "$process_id")"
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null)"
    if [ -n "$process_start_time" ]; then
      printf 'holder_task=%s holder_pid=%s holder_start=%s\n' \
        "${process_command:-legacy command unavailable}" "$process_id" "$process_start_time"
      return 0
    fi
  done
  return 1
}

swift_build_slot_acquire() {
  local requested_slot="${1:-}"
  local task_label="${2:-}"
  local build_directory claim_directory holder_file
  local process_start_time holder_process_id holder_start_time holder_task
  local holder_metadata_valid claim_attempt_status
  local wait_message_printed=0

  if [ -n "${SWIFT_BUILD_DIR:-}" ]; then
    if { [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; } &&
      [ "$SWIFT_BUILD_DIR" = '.build-ci' ]
    then
      echo "[swift-build-slot] using CI build path $SWIFT_BUILD_DIR"
      return 0
    fi
    echo "swift-build-slot: local SWIFT_BUILD_DIR overrides are not supported" >&2
    return 1
  fi

  if [ -z "$task_label" ]; then
    echo "swift-build-slot: task label is required" >&2
    return 2
  fi

  build_directory="$(swift_build_slot_resolve_directory "$requested_slot")" || return $?
  claim_directory="$build_directory/.slot-claim"
  holder_file="$claim_directory/holder"
  if ! mkdir -p "$build_directory"; then
    echo "swift-build-slot: cannot create build directory $build_directory" >&2
    return 1
  fi

  while true; do
    if swift_build_slot_create_atomic_claim \
      "$requested_slot" "$task_label" "$build_directory" "$claim_directory"
    then
      return 0
    else
      claim_attempt_status=$?
    fi
    if [ "$claim_attempt_status" -ne 1 ]; then
      return "$claim_attempt_status"
    fi

    holder_metadata_valid=0
    holder_process_id=""
    holder_start_time=""
    holder_task=""
    if [ -r "$holder_file" ] &&
      IFS=$'\t' read -r holder_process_id holder_start_time holder_task <"$holder_file"
    then
      if [[ "$holder_process_id" =~ ^[0-9]+$ ]] &&
        [ -n "$holder_start_time" ] &&
        [ -n "$holder_task" ]
      then
        holder_metadata_valid=1
      fi
    fi

    if [ "$holder_metadata_valid" -eq 1 ]; then
      if ! swift_build_slot_holder_is_same_process "$holder_process_id" "$holder_start_time"; then
        if swift_build_slot_release_dead_claim "$requested_slot" "$claim_directory" "$holder_process_id" "$holder_start_time"; then
          wait_message_printed=0
          continue
        elif [ "$wait_message_printed" -eq 0 ]; then
          echo "[swift-build-slot] waiting slot=$requested_slot holder_task=$holder_task holder_pid=$holder_process_id holder_start=$holder_start_time stale_pid_open_files=true"
          wait_message_printed=1
        fi
      elif [ "$wait_message_printed" -eq 0 ]; then
        echo "[swift-build-slot] waiting slot=$requested_slot holder_task=$holder_task holder_pid=$holder_process_id holder_start=$holder_start_time"
        wait_message_printed=1
      fi
    else
      if swift_build_slot_release_dead_claim "$requested_slot" "$claim_directory" "" ""; then
        wait_message_printed=0
        continue
      fi
      if [ "$wait_message_printed" -eq 0 ]; then
        # A holder-less legacy or interrupted claim remains busy only while
        # lsof can still see an open file under the claim directory.
        local legacy_holder
        legacy_holder="$(swift_build_slot_legacy_holder_description "$build_directory" || true)"
        if [ -n "$legacy_holder" ]; then
          echo "[swift-build-slot] waiting slot=$requested_slot legacy $legacy_holder"
        else
          echo "[swift-build-slot] waiting slot=$requested_slot holder_task=initializing holder_pid=unknown holder_start=unknown"
        fi
        wait_message_printed=1
      fi
    fi

    # This is a contention scheduling interval, never a correctness timeout.
    sleep 1
  done
}

swift_build_slot_release() {
  local exit_status=$?
  local current_process_id current_start_time current_task

  [ -n "${SWIFT_BUILD_SLOT_CLAIM_DIRECTORY:-}" ] || return "$exit_status"
  if IFS=$'\t' read -r current_process_id current_start_time current_task \
    < "$SWIFT_BUILD_SLOT_CLAIM_DIRECTORY/holder" 2>/dev/null &&
    [ "$current_process_id" = "${SWIFT_BUILD_SLOT_OWNER_PROCESS_ID:-}" ] &&
    [ "$current_start_time" = "${SWIFT_BUILD_SLOT_OWNER_START_TIME:-}" ]
  then
    exec 99>&-
    /bin/rm -f "$SWIFT_BUILD_SLOT_CLAIM_DIRECTORY/holder"
    rmdir "$SWIFT_BUILD_SLOT_CLAIM_DIRECTORY" || true
    echo "[swift-build-slot] released slot=${SWIFT_BUILD_SLOT_NAME:-unknown} task=${SWIFT_BUILD_SLOT_TASK:-unknown}"
  fi

  unset SWIFT_BUILD_SLOT_NAME SWIFT_BUILD_SLOT_CLAIM_DIRECTORY
  unset SWIFT_BUILD_SLOT_OWNER_PROCESS_ID SWIFT_BUILD_SLOT_OWNER_START_TIME
  unset SWIFT_BUILD_SLOT_HOLDER_FD SWIFT_BUILD_SLOT_TASK
  return "$exit_status"
}
