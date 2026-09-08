#!/bin/bash
# Read-only renderer population and graphics-residency sampler for one AgentStudio PID.
# Reports renderer/IO thread counts, PTY children, IOSurface/IOAccelerator dirty footprint, heap
# class occupancy, and system memory pressure alongside WindowServer residency. Every source below
# is read-only; nothing here signals a process. Run with --help for full usage.
set -euo pipefail

PRODUCTION_APP_PATH="/Applications/AgentStudio.app/Contents/MacOS/AgentStudio"

usage() {
  cat <<'EOF'
Usage: verify-renderer-population.sh <pid> [label] [sample_seconds=1]
       verify-renderer-population.sh --parse-footprint <file>
       verify-renderer-population.sh --parse-vmmap <file>
       verify-renderer-population.sh --count-heap-class <file> <class>
       verify-renderer-population.sh --parse-system-memory <vm_stat file> <swap file>
       verify-renderer-population.sh --help

Samples renderer/IO thread population, PTY children, IOSurface/IOAccelerator dirty footprint,
heap class occupancy, and system memory pressure for one AgentStudio PID; prints one JSON object
on stdout. Raw captures land under
${AGENTSTUDIO_RENDERER_POPULATION_ROOT:-a fresh mktemp -d}/<label>/.

Sources (read-only, no sudo): /usr/bin/sample (thread population by name suffix),
/usr/bin/footprint -p (phys/IOSurface/IOAccelerator dirty MB), /usr/bin/vmmap -wide -noCoalesce
(IOSurface region counts), /usr/bin/heap (Ghostty.SurfaceView / TerminalPaneMountView /
PaneHostView instance counts -- heap briefly suspends the target while it walks the heap; never
run this against the production app), pgrep -P (PTY children), and ps/top/vm_stat/sysctl
vm.swapusage (WindowServer residency, compressor, free, swap).

Refusal: exits 2 and does nothing else when <pid> resolves to the production app
(/Applications/AgentStudio.app/Contents/MacOS/AgentStudio). The owner's running app is
passive-sample-only; heap pausing it is not acceptable outside a disposable debug/beta build.

Parser-only modes (--parse-footprint, --parse-vmmap) read a previously captured file and print the
parsed fields as JSON; they take no PID and touch no running process.
EOF
}

refuse_if_production_app() {
  local pid="$1"
  local comm
  comm="$(/bin/ps -o comm= -p "$pid" 2>/dev/null || true)"
  if [ "$comm" = "$PRODUCTION_APP_PATH" ]; then
    echo "refusing pid $pid: it is the production AgentStudio.app; heap would pause the owner's" \
      "running app. Use a disposable debug/beta build instead." >&2
    exit 2
  fi
}

parse_footprint_file() {
  local path="${1:?missing footprint capture path}"
  if capture_is_invalid "$path"; then
    print_null_capture_json "$path" \
      phys_footprint_mb iosurface_dirty_mb ioaccelerator_dirty_mb owned_graphics_dirty_mb
    return 0
  fi
  /usr/bin/python3 - "$path" <<'PY'
import json
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = text.splitlines()

def to_mb(value, unit):
    scale = {"B": 1 / (1024 * 1024), "KB": 1 / 1024, "MB": 1.0, "GB": 1024.0}[unit]
    return round(float(value) * scale, 3)

def dirty_mb_for_category(category_suffix):
    for line in lines:
        stripped = line.strip()
        if not stripped.endswith(category_suffix):
            continue
        match = re.match(r"([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)\s", stripped)
        if match:
            return to_mb(match.group(1), match.group(2))
    return 0.0

phys_match = re.search(r"phys_footprint:\s*([0-9,]+)\s*MB", text)
if phys_match is None:
    phys_match = re.search(r"Footprint:\s*([0-9,]+)\s*MB", text)
if phys_match is None:
    raise SystemExit("phys_footprint missing from footprint capture: " + sys.argv[1])

print(json.dumps({
    "phys_footprint_mb": int(phys_match.group(1).replace(",", "")),
    "iosurface_dirty_mb": dirty_mb_for_category("IOSurface"),
    "ioaccelerator_dirty_mb": dirty_mb_for_category("IOAccelerator (graphics)"),
    "owned_graphics_dirty_mb": dirty_mb_for_category("Owned physical footprint (unmapped) (graphics)"),
}))
PY
}

parse_vmmap_file() {
  local path="${1:?missing vmmap capture path}"
  if capture_is_invalid "$path"; then
    print_null_capture_json "$path" iosurface_regions_total iosurface_regions_large
    return 0
  fi
  /usr/bin/python3 - "$path" <<'PY'
import json
import re
import sys

lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
size_pattern = re.compile(r"\[\s*([0-9]+(?:\.[0-9]+)?)\s*([BKMG])")
multipliers = {"B": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}
total = 0
large = 0
for line in lines:
    if not line.startswith("IOSurface"):
        continue
    total += 1
    match = size_pattern.search(line)
    if match is None:
        continue
    size_bytes = float(match.group(1)) * multipliers[match.group(2)]
    if size_bytes >= 1024 * 1024:
        large += 1
print(json.dumps({
    "iosurface_regions_total": total,
    "iosurface_regions_large": large,
}))
PY
}

count_thread_suffix() {
  local sample_path="$1" suffix="$2"
  grep -cE "Thread_[0-9]+: ${suffix}\$" "$sample_path" || true
}

# First line of a capture file, or empty string if the file is missing/empty.
capture_first_line() {
  local path="$1"
  if [ -s "$path" ]; then
    head -n 1 "$path"
  else
    printf ''
  fi
}

# A capture is invalid when the file is missing/empty, or its first line is one of the known
# failure shapes: heap/vmmap/footprint/sample's own `<tool>: ...` error prefix, a permission
# refusal, or a vanished process. An invalid capture must be reported as unavailable, not parsed
# as zero population.
capture_is_invalid() {
  local path="$1"
  if [ ! -s "$path" ]; then
    return 0
  fi
  local first_line
  first_line="$(head -n 1 "$path")"
  if printf '%s' "$first_line" | grep -qiE '^(heap|vmmap|footprint|sample):|cannot|not permitted|No such process'; then
    return 0
  fi
  return 1
}

# Prints `{"<field>": null, ..., "capture_error": "<first line>"}` for an invalid capture, so a
# failed/malformed capture reads as explicitly unavailable instead of masquerading as zero
# population. Used by both the standalone `--parse-footprint`/`--parse-vmmap` modes and the
# internal capture pipeline in `sample_pid`.
print_null_capture_json() {
  local path="$1"
  shift
  local first_line
  first_line="$(capture_first_line "$path")"
  /usr/bin/python3 - "$first_line" "$@" <<'PY'
import json
import sys

first_line = sys.argv[1]
fields = sys.argv[2:]
payload = {field: None for field in fields}
payload["capture_error"] = first_line
print(json.dumps(payload))
PY
}

# `heap` prints COUNT BYTES AVG CLASS_NAME ... . Match the class field exactly:
# keypath generic arguments and similarly named wrappers are not instances of the target.
count_heap_class() {
  local heap_path="$1" class_name="$2"
  awk -v class_name="$class_name" '$4 == class_name && $1 ~ /^[0-9]+$/ { total += $1 } END { print total + 0 }' "$heap_path"
}

# Read the whole ps stream (no early awk exit): under `pipefail` an early exit makes ps die of
# SIGPIPE and the script exits 141.
discover_windowserver_pid() {
  /bin/ps -axo pid=,comm= | awk '$2 ~ /\/WindowServer$/ && !found { print $1; found = 1 }'
}

parse_windowserver_mem_mb() {
  local top_path="${1:?missing top capture path}"
  if capture_is_invalid "$top_path"; then
    printf 'null\n'
    return 0
  fi
  /usr/bin/python3 - "$top_path" <<'PY'
import re
import sys

lines = [line.strip() for line in open(sys.argv[1], encoding="utf-8", errors="replace") if line.strip()]
for line in reversed(lines):
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)([KMG])[+-]?$", line)
    if match:
        scale = {"K": 1 / 1024, "M": 1.0, "G": 1024.0}[match.group(2)]
        print(round(float(match.group(1)) * scale, 3))
        break
else:
    # No memory column found: report unavailable, never zero.
    print("null")
PY
}

parse_system_memory_values() {
  local vm_stat_path="${1:?missing vm_stat capture path}" swap_path="${2:?missing swap capture path}"
  if capture_is_invalid "$vm_stat_path"; then
    print_null_capture_json "$vm_stat_path" compressor_mb free_mb swap_used_mb
    return 0
  fi
  if capture_is_invalid "$swap_path"; then
    print_null_capture_json "$swap_path" compressor_mb free_mb swap_used_mb
    return 0
  fi
  /usr/bin/python3 - "$vm_stat_path" "$swap_path" <<'PY'
import json
import re
import sys

vm_text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
swap_text = open(sys.argv[2], encoding="utf-8", errors="replace").read()
page_match = re.search(r"page size of ([0-9]+) bytes", vm_text)
free_match = re.search(r"Pages free:\s*([0-9.]+)", vm_text)
compressor_match = re.search(r"Pages occupied by compressor:\s*([0-9.]+)", vm_text)
swap_match = re.search(r"used\s*=\s*([0-9.]+)([KMG])", swap_text)
if not all((page_match, free_match, compressor_match, swap_match)):
    # Malformed capture: report unavailable, never zero, and never abort the sample.
    print(json.dumps({"compressor_mb": None, "free_mb": None, "swap_used_mb": None,
                      "capture_error": "required vm_stat or swap series missing"}))
    raise SystemExit(0)
page_mb = int(page_match.group(1)) / (1024 * 1024)
units = {"K": 1 / 1024, "M": 1.0, "G": 1024.0}
print(json.dumps({
    "compressor_mb": round(float(compressor_match.group(1)) * page_mb, 3),
    "free_mb": round(float(free_match.group(1)) * page_mb, 3),
    "swap_used_mb": round(float(swap_match.group(1)) * units[swap_match.group(2)], 3),
}))
PY
}

sample_pid() {
  local pid="$1" label="$2" sample_seconds="$3" capture_root="$4"
  local sample_file="$capture_root/sample.txt" footprint_file="$capture_root/footprint.txt"
  local vmmap_file="$capture_root/vmmap.txt" heap_file="$capture_root/heap.txt"
  local windowserver_top_file="$capture_root/windowserver-top.txt"
  local vm_stat_file="$capture_root/vm_stat.txt" swap_file="$capture_root/swap.txt"

  /usr/bin/sample "$pid" "$sample_seconds" -mayDie -file "$sample_file" >/dev/null 2>&1 || true
  /usr/bin/footprint -p "$pid" >"$footprint_file" 2>&1 || true
  /usr/bin/vmmap -wide -noCoalesce "$pid" >"$vmmap_file" 2>&1 || true
  /usr/bin/heap "$pid" >"$heap_file" 2>&1 || true
  local windowserver_pid
  windowserver_pid="$(discover_windowserver_pid)"
  /usr/bin/top -l 1 -pid "$windowserver_pid" -stats mem >"$windowserver_top_file" 2>&1 || true
  /usr/bin/vm_stat >"$vm_stat_file" 2>&1 || true
  /usr/sbin/sysctl vm.swapusage >"$swap_file" 2>&1 || true

  local capture_error_names=()

  local renderer_threads io_threads
  if capture_is_invalid "$sample_file"; then
    capture_error_names+=("$(basename "$sample_file")")
    renderer_threads="null"
    io_threads="null"
  else
    renderer_threads="$(count_thread_suffix "$sample_file" "renderer")"
    io_threads="$(count_thread_suffix "$sample_file" "io")"
  fi

  # `pgrep -P` exits 1 (not an error) when the pid has no children; under `pipefail` an
  # unguarded exit 1 would abort the whole script on the valid zero-child case.
  local pty_children
  pty_children="$( { pgrep -P "$pid" || true; } | wc -l | tr -d ' ')"

  local heap_surface_view heap_terminal_mount_view heap_pane_host_view
  if capture_is_invalid "$heap_file"; then
    capture_error_names+=("$(basename "$heap_file")")
    heap_surface_view="null"
    heap_terminal_mount_view="null"
    heap_pane_host_view="null"
  else
    heap_surface_view="$(count_heap_class "$heap_file" "Ghostty.SurfaceView")"
    heap_terminal_mount_view="$(count_heap_class "$heap_file" "TerminalPaneMountView")"
    heap_pane_host_view="$(count_heap_class "$heap_file" "PaneHostView")"
  fi

  if capture_is_invalid "$footprint_file"; then
    capture_error_names+=("$(basename "$footprint_file")")
  fi
  if capture_is_invalid "$vmmap_file"; then
    capture_error_names+=("$(basename "$vmmap_file")")
  fi
  for system_capture in "$windowserver_top_file" "$vm_stat_file" "$swap_file"; do
    if capture_is_invalid "$system_capture"; then
      capture_error_names+=("$(basename "$system_capture")")
    fi
  done

  local footprint_json vmmap_json windowserver_mem_mb system_memory_json
  footprint_json="$(parse_footprint_file "$footprint_file")"
  vmmap_json="$(parse_vmmap_file "$vmmap_file")"
  windowserver_mem_mb="$(parse_windowserver_mem_mb "$windowserver_top_file")"
  system_memory_json="$(parse_system_memory_values "$vm_stat_file" "$swap_file")"

  local capture_errors_json="[]"
  if [ ${#capture_error_names[@]} -gt 0 ]; then
    capture_errors_json="["
    local first=1
    for name in "${capture_error_names[@]}"; do
      if [ "$first" -eq 1 ]; then
        first=0
      else
        capture_errors_json+=","
      fi
      capture_errors_json+="\"${name}\""
    done
    capture_errors_json+="]"
  fi

  /usr/bin/python3 - "$pid" "$label" "$renderer_threads" "$io_threads" "$pty_children" \
    "$footprint_json" "$vmmap_json" "$windowserver_pid" "$windowserver_mem_mb" "$system_memory_json" \
    "$heap_surface_view" "$heap_terminal_mount_view" "$heap_pane_host_view" "$capture_errors_json" <<'PY'
import datetime
import json
import sys

(_, pid, label, renderer_threads, io_threads, pty_children, footprint_json, vmmap_json,
 windowserver_pid, windowserver_mem_mb, system_memory_json, heap_surface_view,
 heap_terminal_mount_view, heap_pane_host_view, capture_errors_json) = sys.argv
footprint = json.loads(footprint_json)
vmmap = json.loads(vmmap_json)
system_memory = json.loads(system_memory_json)
capture_errors = json.loads(capture_errors_json)


def optional_int(value):
    return None if value == "null" else int(value)


print(json.dumps({
    "pid": int(pid),
    "label": label,
    "observed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    "renderer_threads": optional_int(renderer_threads),
    "io_threads": optional_int(io_threads),
    "pty_children": int(pty_children),
    "iosurface_regions_total": vmmap["iosurface_regions_total"],
    "iosurface_regions_large": vmmap["iosurface_regions_large"],
    "iosurface_dirty_mb": footprint["iosurface_dirty_mb"],
    "ioaccelerator_dirty_mb": footprint["ioaccelerator_dirty_mb"],
    "owned_graphics_dirty_mb": footprint["owned_graphics_dirty_mb"],
    "phys_footprint_mb": footprint["phys_footprint_mb"],
    "heap_surface_view": optional_int(heap_surface_view),
    "heap_terminal_mount_view": optional_int(heap_terminal_mount_view),
    "heap_pane_host_view": optional_int(heap_pane_host_view),
    "windowserver_pid": int(windowserver_pid) if windowserver_pid else 0,
    "windowserver_mem_mb": None if windowserver_mem_mb == "null" else float(windowserver_mem_mb),
    "compressor_mb": system_memory["compressor_mb"],
    "free_mb": system_memory["free_mb"],
    "swap_used_mb": system_memory["swap_used_mb"],
    "capture_errors": capture_errors,
}))
PY
}

main() {
  case "${1:-}" in
    --help | -h)
      usage
      exit 0
      ;;
    --parse-footprint)
      parse_footprint_file "${2:?missing footprint file argument}"
      exit 0
      ;;
    --parse-vmmap)
      parse_vmmap_file "${2:?missing vmmap file argument}"
      exit 0
      ;;
    --parse-system-memory)
      parse_system_memory_values "${2:?missing vm_stat file argument}" "${3:?missing swap file argument}"
      exit 0
      ;;
    --count-heap-class)
      count_heap_class "${2:?missing heap file argument}" "${3:?missing class argument}"
      exit 0
      ;;
  esac

  local pid="${1:?missing pid argument; run with --help for usage}"
  local label="${2:-sample}"
  local sample_seconds="${3:-1}"

  refuse_if_production_app "$pid"

  local capture_root
  capture_root="${AGENTSTUDIO_RENDERER_POPULATION_ROOT:-$(mktemp -d /tmp/agentstudio-renderer-population.XXXXXX)}/$label"
  mkdir -p "$capture_root"

  sample_pid "$pid" "$label" "$sample_seconds" "$capture_root"
}

main "$@"
