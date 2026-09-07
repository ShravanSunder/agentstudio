#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$PROJECT_ROOT" <<'PY'
import os
import fcntl
import json
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import tomllib

root = Path(sys.argv[1])
tasks = tomllib.loads((root / ".mise.toml").read_text())["tasks"]

# Real shell allocation and cleanup; no Swift compiler or live build directories.
with tempfile.TemporaryDirectory(prefix="agentstudio-slot-contract-") as directory:
    workspace = Path(directory)
    (workspace / "scripts").mkdir()
    for name in ("swift-build-slot.sh", "swift-build-pool-lock.sh", "clean-agent-builds.sh", "clean-build-artifacts.sh"):
        source = root / "scripts" / name
        if source.exists():
            (workspace / "scripts" / name).write_text(source.read_text())
    environment = dict(os.environ)
    for name in ("SWIFT_BUILD_DIR", "CI", "GITHUB_ACTIONS"):
        environment.pop(name, None)
    environment["PROJECT_ROOT"] = str(workspace)

    def run_shell(source: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", "-c", "set -euo pipefail\n" + source],
            cwd=workspace, env=environment, text=True, capture_output=True, timeout=10,
        )

    claimed = run_shell('source scripts/swift-build-slot.sh; test -f "$SWIFT_BUILD_DIR/.slot-claim/owner-pid"')
    assert claimed.returncode == 0, claimed.stdout + claimed.stderr
    assert not (workspace / ".build-agent-1/.slot-claim").exists(), "normal exit must release claim"
    print("PASS claim records owner and releases on exit")

    # Hold ownership with an input event, not a timing assumption or open build fd.
    owners = []
    try:
        for _ in (1, 2):
            owner = subprocess.Popen(
                ["/bin/bash", "-c", 'set -eu; source scripts/swift-build-slot.sh; echo READY; read -r release'],
                cwd=workspace, env=environment, text=True,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            owners.append(owner)
        claimed_slots = set()
        for owner in owners:
            assert owner.stdout is not None
            claimed_slots.add(owner.stdout.readline().strip())
            assert owner.stdout.readline().strip() == "READY"
        assert claimed_slots == {"[swift-build-slot] using .build-agent-1", "[swift-build-slot] using .build-agent-2"}
        rejected = run_shell("source scripts/swift-build-slot.sh")
        assert rejected.returncode != 0 and "all 2 slots are busy" in rejected.stderr
        assert not (workspace / ".build-agent-3").exists()
        cleanup = run_shell("bash scripts/clean-agent-builds.sh")
        assert cleanup.returncode == 0, cleanup.stderr
        assert all((workspace / f".build-agent-{slot}/.slot-claim").exists() for slot in (1, 2))
        clean = run_shell("bash scripts/clean-build-artifacts.sh")
        assert clean.returncode != 0 and "refusing" in clean.stderr
        print("PASS two owners exclude a third and survive cleanup between commands")
    finally:
        for owner in owners:
            owner.communicate("release\n", timeout=10)
    assert all(not (workspace / f".build-agent-{slot}/.slot-claim").exists() for slot in (1, 2))

    maintenance = subprocess.Popen(
        ["/bin/bash", "-c", 'set -eu; source scripts/swift-build-pool-lock.sh; acquire_swift_build_pool_lock; echo READY; read -r release'],
        cwd=workspace, env=environment, text=True,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    try:
        assert maintenance.stdout is not None
        assert maintenance.stdout.readline().strip() == "READY"
        with (workspace / ".swift-build-pool.lock").open("w") as lock_file:
            try:
                fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise AssertionError("maintenance must retain a kernel lock after lockf exits")
    finally:
        maintenance.communicate("release\n", timeout=10)

    failed = run_shell("source scripts/swift-build-slot.sh; exit 7")
    assert failed.returncode == 7
    assert not (workspace / ".build-agent-1/.slot-claim").exists()
    print("PASS failure releases claim without changing exit status")

    interrupted = subprocess.Popen(
        ["/bin/bash", "-c", 'set -eu; source scripts/swift-build-slot.sh; echo READY; read -r release'],
        cwd=workspace, env=environment, text=True,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert interrupted.stdout is not None
    interrupted.stdout.readline()
    assert interrupted.stdout.readline().strip() == "READY"
    interrupted.send_signal(signal.SIGKILL)
    interrupted.communicate(timeout=10)
    recovered = run_shell("bash scripts/clean-agent-builds.sh")
    assert recovered.returncode == 0, recovered.stderr
    assert not (workspace / ".build-agent-1/.slot-claim").exists()

    claim = workspace / ".build-agent-1/.slot-claim"
    claim.mkdir()
    unknown = run_shell("bash scripts/clean-agent-builds.sh")
    assert unknown.returncode == 0 and claim.exists(), "unknown owner must be preserved"
    claim.rmdir()
    print("PASS legacy or partially published claims are not guessed stale")

    ci = run_shell('export CI=true SWIFT_BUILD_DIR=.build-ci; source scripts/swift-build-slot.sh')
    assert ci.returncode == 0
    invalid = run_shell('export SWIFT_BUILD_DIR=.build; source scripts/swift-build-slot.sh')
    assert invalid.returncode != 0
    print("PASS explicit CI exception and rejected local override")

# Execute the actual packaging shell with a failed external compiler. This is
# failure-path integration proof, not proof of a signed release artifact.
with tempfile.TemporaryDirectory(prefix="agentstudio-bundle-contract-") as directory:
    workspace = Path(directory)
    (workspace / "scripts").mkdir()
    for name in ("swift-build-slot.sh", "swift-build-pool-lock.sh"):
        (workspace / "scripts" / name).write_text((root / "scripts" / name).read_text())
    (workspace / "scripts/xcb-helpers.sh").write_text('_xcb_pipe_cmd() { echo cat; }\n')
    binaries = workspace / "bin"
    binaries.mkdir()
    swift = binaries / "swift"
    swift.write_text("#!/bin/bash\nexit 23\n")
    swift.chmod(0o755)
    environment = dict(os.environ)
    for name in ("SWIFT_BUILD_DIR", "CI", "GITHUB_ACTIONS"):
        environment.pop(name, None)
    environment.update(PROJECT_ROOT=str(workspace), PATH=f"{binaries}:{os.environ['PATH']}")
    bundle = workspace / "AgentStudio.app"
    bundle.mkdir()
    (bundle / "sentinel").write_text("previous bundle")
    failed = subprocess.run(
        ["/bin/bash", "-c", tasks["create-app-bundle"]["run"]], cwd=workspace,
        env=environment, text=True, capture_output=True, timeout=10,
    )
    assert failed.returncode == 23, failed.stdout + failed.stderr
    assert (bundle / "sentinel").exists()
    assert not (workspace / ".build-agent-1/.slot-claim").exists()
    print("PASS packaging preserves prior bundle and releases its slot on compiler failure")

aggregate = tasks["test"]["run"]
assert aggregate.count("mise run bridge-web-build") == 1
assert "mise run --skip-deps test:swift" in aggregate
assert "mise run verify-vendors" in aggregate
assert 'test -f Sources/AgentStudio/Resources/BridgeWeb/app/index.html' in aggregate
assert "mise run --skip-deps setup-dev-resources" in tasks["refresh-vendors"]["run"]
assert "build" not in tasks["test:swift:benchmark"]["depends"]
assert "build-release" not in tasks["create-app-bundle"]["depends"]
assert "swift-build-slot.sh" in tasks["create-app-bundle"]["run"]
assert "newest_mtime" not in tasks["create-app-bundle"]["run"]
print("PASS task graph preserves preparation once and packages its own claimed build")
package_scripts = json.loads((root / "BridgeWeb/package.json").read_text())["scripts"]
bridge_test = package_scripts["test"]
assert bridge_test.count("pnpm run build:swift-dev-server") == 1
assert "test:integration:node:prepared" in bridge_test and "test:e2e:prepared" in bridge_test
assert "test:browser:integration" in bridge_test and "test:unit" in bridge_test
release = (root / ".github/workflows/release.yml").read_text()
assert "mise run --skip-deps build-release" in release
assert "SWIFT_BUILD_DIR: .build-ci" in release
assert ".build/release" not in release and "path: .build\n" not in release
print("PASS BridgeWeb single preparation and CI release slot routing")

for name, task in tasks.items():
    for dependency in task.get("depends", []):
        assert dependency in tasks, f"{name}: missing dependency {dependency}"
    script = task.get("run", "")
    syntax = subprocess.run(["/bin/bash", "-n"], input=script, text=True, capture_output=True)
    assert syntax.returncode == 0, f"{name}: {syntax.stderr}"

def visit(name: str, ancestors: set[str]) -> None:
    assert name not in ancestors, f"dependency cycle at {name}"
    for dependency in tasks[name].get("depends", []):
        visit(dependency, ancestors | {name})

for name in tasks:
    visit(name, set())
print(f"PASS {len(tasks)} task bodies parse and all dependency edges resolve without cycles")
print("9 mise task contract groups passed")
PY
