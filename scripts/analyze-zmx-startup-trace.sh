#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/analyze-zmx-startup-trace.sh <trace-file.jsonl> [--pane-id <uuid>] [--zmx-log <file-or-dir>]

Summarizes Agent Studio app.startup and terminal.startup JSONL events and,
when provided, correlates the pane's zmx session with zmx log timestamps. The
analyzer is diagnostic-only: a failed terminal startup is reported as evidence,
not as a script failure.
USAGE
}

trace_file=""
pane_id=""
zmx_log_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane-id)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --pane-id" >&2
        usage
        exit 2
      fi
      pane_id="$2"
      shift 2
      ;;
    --zmx-log)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --zmx-log" >&2
        usage
        exit 2
      fi
      zmx_log_path="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 2
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$trace_file" ]]; then
        echo "too many trace files: $1" >&2
        usage
        exit 2
      fi
      trace_file="$1"
      shift
      ;;
  esac
done

if [[ -z "$trace_file" ]]; then
  echo "missing trace file" >&2
  usage
  exit 2
fi

if [[ ! -f "$trace_file" ]]; then
  echo "trace file not found: $trace_file" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to analyze startup traces" >&2
  exit 2
fi

run_jq() {
  local filter="$1"
  shift
  set +e
  jq -r "$@" "$filter" "$trace_file"
  local jq_status=$?
  set -e
  if [[ "$jq_status" == "4" ]]; then
    return 0
  fi
  if [[ "$jq_status" != "0" ]]; then
    echo "jq failed while reading startup trace" >&2
    exit 2
  fi
}

pane_rows="$(
  run_jq '
    select(.body == "terminal.startup.pane_created")
    | [
        .time_unix_nano,
        (.attributes["agentstudio.pane.id"] // ""),
        (.attributes["agentstudio.terminal.startup.operation_id"] // "-")
      ]
    | @tsv
  ' | sort -n
)"

app_events="$(
  run_jq '
    select(
      (.body | startswith("app."))
      or .body == "workspace.boot.step"
      or (.attributes["agentstudio.trace.tag"] // "") == "app.startup"
    )
    | [
        .time_unix_nano,
        .body,
        (.attributes["agentstudio.app.startup.phase"] // "-"),
        (.attributes["agentstudio.app.startup.outcome"] // "-"),
        (.attributes["agentstudio.workspace.boot.step"] // "-")
      ]
    | @tsv
  ' | sort -n
)"

if [[ -z "$pane_rows" ]]; then
  echo "missing terminal.startup.pane_created records" >&2
  exit 1
fi

if [[ -z "$pane_id" ]]; then
  pane_id="$(printf '%s\n' "$pane_rows" | tail -n 1 | cut -f2)"
fi

operation_id="$(
  printf '%s\n' "$pane_rows" \
    | awk -F '\t' -v pane="$pane_id" '$2 == pane { value = $3 } END { print value }'
)"
if [[ "$operation_id" == "-" ]]; then
  operation_id=""
fi

if [[ -z "$operation_id" ]]; then
  operation_id="$(
    run_jq '
      select(.body | startswith("terminal.startup."))
      | select((.attributes["agentstudio.pane.id"] // "") == $pane)
      | .attributes["agentstudio.terminal.startup.operation_id"] // empty
    ' --arg pane "$pane_id" | tail -n 1
  )"
fi

if [[ -z "$pane_id" ]]; then
  echo "could not determine terminal startup pane id" >&2
  exit 1
fi

events="$(
  run_jq '
    select(.body | startswith("terminal.startup."))
    | . as $record
    | ($record.attributes["agentstudio.pane.id"] // "") as $recordPane
    | ($record.attributes["agentstudio.terminal.startup.operation_id"] // "") as $recordOperation
    | select(
        $recordPane == $pane
        or ($operation != "" and $recordOperation == $operation)
      )
    | [
        $record.time_unix_nano,
        $record.body,
        ($record.attributes["agentstudio.terminal.startup.phase"] // "-"),
        ($record.attributes["agentstudio.terminal.startup.outcome"] // "-"),
        ($record.attributes["agentstudio.surface.id"] // "-"),
        ($record.attributes["agentstudio.zmx.session_id"] // "-"),
        ($record.attributes["agentstudio.zmx.socket_path_headroom"] // "-"),
        (
          if ($record.attributes | has("agentstudio.app.is_active"))
          then ($record.attributes["agentstudio.app.is_active"] | tostring)
          else "-"
          end
        ),
        ($record.attributes["agentstudio.display.count"] // "-"),
        ($record.attributes["agentstudio.terminal.startup.error"] // "-")
      ]
    | @tsv
  ' --arg pane "$pane_id" --arg operation "$operation_id" | sort -n
)"

if [[ -z "$events" ]]; then
  echo "missing terminal.startup records for pane: $pane_id" >&2
  exit 1
fi

first_time="$(printf '%s\n' "$events" | head -n 1 | cut -f1)"
last_time="$(printf '%s\n' "$events" | tail -n 1 | cut -f1)"
zmx_session="$(
  printf '%s\n' "$events" \
    | awk -F '\t' '$6 != "-" { value = $6 } END { print value }'
)"
startup_outcome="$(
  printf '%s\n' "$events" \
    | awk -F '\t' '$4 != "-" { value = $4 } END { print value }'
)"

printf 'startup trace summary\n'
printf 'trace: %s\n' "$trace_file"
printf 'pane: %s\n' "$pane_id"
if [[ -n "$operation_id" ]]; then
  printf 'operation: %s\n' "$operation_id"
fi
if [[ -n "$zmx_session" ]]; then
  printf 'zmx_session: %s\n' "$zmx_session"
fi
printf 'duration_ms: '
awk -v start="$first_time" -v finish="$last_time" 'BEGIN { printf "%.3f\n", (finish - start) / 1000000 }'
if [[ -n "$startup_outcome" ]]; then
  printf 'outcome: %s\n' "$startup_outcome"
fi

if [[ -n "$app_events" ]]; then
  app_first_time="$(printf '%s\n' "$app_events" | head -n 1 | cut -f1)"
  printf '\napp startup timeline\n'
  printf '%12s  %-48s  %s\n' "delta_ms" "body" "details"
  printf '%12s  %-48s  %s\n' "────────" "────────────────────────────────────────────" "───────"
  printf '%s\n' "$app_events" | while IFS=$'\t' read -r time body phase outcome step; do
    delta_ms="$(awk -v time="$time" -v start="$app_first_time" 'BEGIN { printf "%.3f", (time - start) / 1000000 }')"
    details=()
    [[ "$phase" != "-" ]] && details+=("phase=$phase")
    [[ "$outcome" != "-" ]] && details+=("outcome=$outcome")
    [[ "$step" != "-" ]] && details+=("step=$step")
    printf '%12s  %-48s  %s\n' "$delta_ms" "$body" "${details[*]}"
  done
fi

printf '\nagentstudio timeline\n'
printf '%12s  %-48s  %s\n' "delta_ms" "body" "details"
printf '%12s  %-48s  %s\n' "────────" "────────────────────────────────────────────" "───────"

printf '%s\n' "$events" | while IFS=$'\t' read -r time body phase outcome surface session headroom active display error; do
  delta_ms="$(awk -v time="$time" -v start="$first_time" 'BEGIN { printf "%.3f", (time - start) / 1000000 }')"
  details=()
  [[ "$phase" != "-" ]] && details+=("phase=$phase")
  [[ "$outcome" != "-" ]] && details+=("outcome=$outcome")
  [[ "$surface" != "-" ]] && details+=("surface=$surface")
  [[ "$session" != "-" ]] && details+=("session=$session")
  [[ "$headroom" != "-" ]] && details+=("socket_headroom=$headroom")
  [[ "$active" != "-" ]] && details+=("app_active=$active")
  [[ "$display" != "-" ]] && details+=("display_count=$display")
  [[ "$error" != "-" ]] && details+=("error=$error")
  printf '%12s  %-48s  %s\n' "$delta_ms" "$body" "${details[*]}"
done

zmx_events=""
if [[ -n "$zmx_log_path" ]]; then
  if [[ -d "$zmx_log_path" ]]; then
    zmx_events="$(
      find "$zmx_log_path" -type f -name '*.log' -exec awk -v session="$zmx_session" '
          /^\[[0-9][0-9]*\] / {
            timestamp = $0
            sub(/^\[/, "", timestamp)
            sub(/\].*/, "", timestamp)
            message = $0
            sub(/^\[[0-9][0-9]*\] \[[^]]*\] \([^)]*\): /, "", message)
            include = (session == "" || index(message, session) > 0 || index(FILENAME, session) > 0)
            if (include && message ~ /(creating session|pty spawned|daemon started|attached session|client connected|session unresponsive|timeout waiting|execve failed|execvpe failed)/) {
              print timestamp "\t" message "\t" FILENAME
            }
          }
        ' {} + 2>/dev/null | sort -n || true
    )"
  elif [[ -f "$zmx_log_path" ]]; then
    zmx_events="$(
      awk -v session="$zmx_session" '
        /^\[[0-9][0-9]*\] / {
          timestamp = $0
          sub(/^\[/, "", timestamp)
          sub(/\].*/, "", timestamp)
          message = $0
          sub(/^\[[0-9][0-9]*\] \[[^]]*\] \([^)]*\): /, "", message)
          include = (session == "" || index(message, session) > 0 || index(FILENAME, session) > 0)
          if (include && message ~ /(creating session|pty spawned|daemon started|attached session|client connected|session unresponsive|timeout waiting|execve failed|execvpe failed)/) {
            print timestamp "\t" message "\t" FILENAME
          }
        }
      ' "$zmx_log_path" | sort -n || true
    )"
  else
    echo "zmx log path not found: $zmx_log_path" >&2
    exit 2
  fi
fi

if [[ -n "$zmx_log_path" ]]; then
  printf '\nzmx timeline\n'
  if [[ -z "$zmx_events" ]]; then
    printf 'no zmx events found for session'
    if [[ -n "$zmx_session" ]]; then
      printf ' %s' "$zmx_session"
    fi
    printf '\n'
  else
    zmx_first_time="$(printf '%s\n' "$zmx_events" | head -n 1 | cut -f1)"
    printf '%12s  %s\n' "delta_ms" "message"
    printf '%12s  %s\n' "────────" "───────"
    printf '%s\n' "$zmx_events" | while IFS=$'\t' read -r time message file; do
      delta_ms="$(awk -v time="$time" -v start="$zmx_first_time" 'BEGIN { printf "%.3f", time - start }')"
      printf '%12s  %s\n' "$delta_ms" "$message"
    done
  fi
fi

printf '\ninterpretation\n'
if printf '%s\n' "$events" | grep -q $'terminal.startup.child_exited'; then
  printf 'terminal child exited during startup; inspect socket headroom, zmx logs, and shell command output before treating first_output as readiness.\n'
elif printf '%s\n' "$events" | grep -q $'terminal.startup.surface_create_failed'; then
  if [[ -n "$zmx_log_path" && -z "$zmx_events" ]]; then
    printf 'surface creation failed before zmx emitted session events; this trace does not measure zmx daemon startup.\n'
  else
    printf 'surface creation failed; inspect surface/display attributes and zmx events before treating this as shell readiness latency.\n'
  fi
elif printf '%s\n' "$events" | grep -q $'terminal.startup.first_output'; then
  printf 'trace reached first output; compare surface_create_started/succeeded, zmx timeline, first_output, cwd_ready, and title_ready deltas.\n'
else
  printf 'trace has terminal startup events but did not reach first output; collect more runtime or inspect missing surface/action milestones.\n'
fi
