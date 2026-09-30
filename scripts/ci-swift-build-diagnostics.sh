#!/usr/bin/env bash
set -euo pipefail

# Observe the restored build without changing its compiler command or timestamps.
exec python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

phase = sys.argv[1]
if phase not in ("before", "after"):
    raise ValueError("expected before or after")
build_path = Path(os.environ.get("SWIFT_BUILD_DIR", ".build-ci"))
output_path = Path("tmp/tq/diagnostics") / phase
output_path.mkdir(parents=True, exist_ok=True)
records = []
for current_root, directories, files in os.walk(build_path, followlinks=False):
    directories.sort()
    for name in sorted(files):
        input_path = Path(current_root) / name
        info = input_path.lstat()
        relative_path = input_path.relative_to(build_path)
        record = {"path": relative_path.as_posix(), "size": info.st_size,
                  "mtime_ns": info.st_mtime_ns, "mode": info.st_mode}
        if input_path.is_symlink():
            record["target"] = os.readlink(input_path)
        else:
            content_digest = hashlib.sha256()
            with input_path.open("rb") as input_file:
                for block in iter(lambda: input_file.read(1024 * 1024), b""):
                    content_digest.update(block)
            record["digest"] = content_digest.hexdigest()
        records.append(record)
        if name in ("build.db", "build.db-wal", "build.db-shm", "debug.yaml",
                    "description.json", "workspace-state.json", "ci-swift-build-seed.json") \
                or name.endswith((".swiftdeps", ".priors", ".swift-build-record")) \
                or "DerivedSources" in relative_path.parts:
            destination_path = output_path / relative_path
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(input_path, destination_path, follow_symlinks=False)
(output_path / "file-state.json").write_text(json.dumps(records, sort_keys=True, indent=2) + "\n")
if phase == "after":
    before = {item["path"]: item for item in json.loads(
        (output_path.parent / "before/file-state.json").read_text())}
    rebuilt_objects = [item["path"] for item in records if item["path"].endswith(".o")
                       and item != before.get(item["path"])]
    (output_path.parent / "rebuilt-objects.json").write_text(
        json.dumps(rebuilt_objects, indent=2) + "\n")
    print("lane-report swift_cache_rebuilt_objects=" + str(len(rebuilt_objects)))
PY
