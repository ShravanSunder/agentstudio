#!/usr/bin/env bash
set -euo pipefail

project_root="${PROJECT_ROOT:-$(pwd)}"
ghostty_root="$project_root/vendor/ghostty"
libtool_step="$ghostty_root/src/build/LibtoolStep.zig"
backup_file="$(mktemp)"

cleanup() {
  if [[ -f "$backup_file" ]]; then
    cp "$backup_file" "$libtool_step"
    rm -f "$backup_file"
  fi
}
trap cleanup EXIT

cp "$libtool_step" "$backup_file"

python - <<'PY' "$libtool_step"
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = '    run_step.addArgs(&.{ "libtool", "-static", "-o" });\n'
new = (
    '    run_step.addArgs(&.{\n'
    '        "/bin/bash",\n'
    '        b.pathFromRoot("../../scripts/ghostty-libtool-all-members.sh"),\n'
    '    });\n'
)
if old not in source:
    raise SystemExit("expected libtool invocation not found in Ghostty LibtoolStep.zig")
path.write_text(source.replace(old, new, 1))
PY

(
  cd "$ghostty_root"
  bash "$project_root/scripts/zig.sh" build -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=universal
)
