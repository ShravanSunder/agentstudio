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
import shutil
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

    # Observe entry into the real release lock call, then inspect kernel-owned
    # slot protection while maintenance holds the pool lock. No timed sleeps.
    release_owner = subprocess.Popen(
        ["/bin/bash", "-c", '''set -eu
function /usr/bin/lockf() {
  if [ "${releasing:-0}" = 1 ] && [ "${!#}" = 8 ]; then
    echo RELEASE_WAITING
  fi
  command /usr/bin/lockf "$@"
}
source scripts/swift-build-slot.sh
echo READY
read -r release
releasing=1
'''], cwd=workspace, env=environment, text=True,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert release_owner.stdout is not None and release_owner.stdin is not None
    release_owner.stdout.readline()
    assert release_owner.stdout.readline().strip() == "READY"
    try:
        with (workspace / ".swift-build-pool.lock").open("w") as pool_file:
            fcntl.flock(pool_file, fcntl.LOCK_EX)
            release_owner.stdin.write("release\n")
            release_owner.stdin.flush()
            assert release_owner.stdout.readline().strip() == "RELEASE_WAITING"
            with (workspace / ".swift-build-slot-1.lock").open("w") as slot_file:
                try:
                    fcntl.flock(slot_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    raise AssertionError("normal release abandoned its lifetime token while maintenance held the pool")
    finally:
        release_owner.communicate(timeout=10)
    assert release_owner.returncode == 0
    assert not (workspace / ".build-agent-1/.slot-claim").exists()
    print("PASS normal release retains its token until maintenance permits claim removal")

    # A surviving child has no build file open while paused between commands.
    # The build lifetime must remain protected after its claiming shell dies.
    control_fifo = workspace / "orphan-control"
    os.mkfifo(control_fifo)
    orphan_owner = subprocess.Popen(
        ["/bin/bash", "-c", '''set -eu
source scripts/swift-build-slot.sh
(echo CHILD_READY; read -r release < orphan-control; echo CHILD_DONE) &
wait
'''], cwd=workspace, env=environment, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert orphan_owner.stdout is not None
    orphan_owner.stdout.readline()
    assert orphan_owner.stdout.readline().strip() == "CHILD_READY"
    orphan_owner.kill()
    orphan_owner.wait(timeout=10)
    try:
        cleanup = run_shell("bash scripts/clean-agent-builds.sh")
        assert cleanup.returncode == 0, cleanup.stderr
        assert (workspace / ".build-agent-1/.slot-claim").exists(), "orphan child lost its slot protection"
    finally:
        control_fifo.write_text("release\n")
        assert orphan_owner.stdout.readline().strip() == "CHILD_DONE"
        orphan_owner.stdout.close()
        assert orphan_owner.stderr is not None
        orphan_owner.stderr.close()
    # Synchronize with the child's descriptor close before testing recovery.
    released = run_shell('exec 6>.swift-build-slot-1.lock; /usr/bin/lockf -s -t 5 6')
    assert released.returncode == 0
    cleanup = run_shell("bash scripts/clean-agent-builds.sh")
    assert cleanup.returncode == 0
    assert not (workspace / ".build-agent-1/.slot-claim").exists()
    print("PASS orphan child retains slot until its inherited lifetime lock closes")

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

    published_server = workspace / ".build-bridge-development-server/server"
    published_server.parent.mkdir()
    published_server.write_text("prepared for next consumer")
    published_app = workspace / "AgentStudio.app/sentinel"
    published_app.parent.mkdir()
    published_app.write_text("published")
    cleaned = run_shell("bash scripts/clean-build-artifacts.sh")
    assert cleaned.returncode == 0, cleaned.stderr
    assert published_server.exists() and published_app.exists()
    print("PASS scratch cleanup preserves published artifacts between consumers")

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
    for name in ("swift-build-slot.sh", "swift-build-pool-lock.sh", "create-app-bundle.sh", "publish-app-bundle.sh", "create-local-beta-bundle.sh"):
        (workspace / "scripts" / name).write_text((root / "scripts" / name).read_text())
    (workspace / "scripts/vendor-worktree.sh").write_text('exit 0\n')
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

    swift.write_text('''#!/bin/bash
set -eu
mkdir -p "$SWIFT_BUILD_DIR/release"
printf current > "$SWIFT_BUILD_DIR/release/AgentStudio"
if [ "${TEST_RESOURCE:-0}" = 1 ]; then
  mkdir -p "$SWIFT_BUILD_DIR/release/AgentStudio_AgentStudio.bundle"
fi
''')
    (workspace / "scripts/inject-bundle-version.sh").write_text('exit 0\n')
    resources = workspace / "Sources/AgentStudio/Resources"
    resources.mkdir(parents=True)
    for name in ("Info.plist", "AppIcon.icns"):
        (resources / name).write_text("fixture")
    zmx = workspace / "vendor/zmx/zig-out/bin/zmx"
    zmx.parent.mkdir(parents=True)
    zmx.write_text("fixture")
    zmx.chmod(0o755)
    codesign = binaries / "codesign"
    codesign.write_text('#!/bin/bash\nexit "${TEST_SIGN_STATUS:-0}"\n')
    codesign.chmod(0o755)
    environment.update(APP_BUILD_VERSION="1", SIGNING_IDENTITY="-")

    def package_fixture() -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", "-c", tasks["create-app-bundle"]["run"]], cwd=workspace,
            env=environment, text=True, capture_output=True, timeout=10,
        )

    missing_resource = package_fixture()
    assert missing_resource.returncode != 0 and "exactly one SwiftPM resource" in missing_resource.stderr
    assert (bundle / "sentinel").exists()
    environment.update(TEST_RESOURCE="1", TEST_SIGN_STATUS="42")
    failed_signing = package_fixture()
    assert failed_signing.returncode == 42, failed_signing.stderr
    assert (bundle / "sentinel").exists()
    assert not list(workspace.glob(".agentstudio-package.*"))
    environment["TEST_SIGN_STATUS"] = "0"
    published = package_fixture()
    assert published.returncode == 0, published.stdout + published.stderr
    assert not (bundle / "sentinel").exists()
    assert (bundle / "Contents/MacOS/AgentStudio").read_text() == "current"
    beta_bundle = workspace / "beta/AgentStudio Beta.app"
    environment["APP_BUNDLE_PATH"] = str(beta_bundle)
    beta_published = package_fixture()
    assert beta_published.returncode == 0, beta_published.stdout + beta_published.stderr
    assert (beta_bundle / "Contents/MacOS/AgentStudio").read_text() == "current"
    assert not list((workspace / "beta").glob(".agentstudio-package.*"))
    print("PASS resource/signing failures preserve old bundle; successful publication atomically replaces it")

    second_worktree = workspace / "second-worktree"
    for relative_path in ("scripts", "Sources", "vendor"):
        shutil.copytree(workspace / relative_path, second_worktree / relative_path)
    build_fifo = workspace / "build-barrier"
    os.mkfifo(build_fifo)
    swift.write_text(swift.read_text().replace("set -eu\n", '''set -eu
if [ "${TEST_BUILD_BARRIER:-0}" = 1 ]; then
  echo BUILD_PAUSED
  read -r release < "$TEST_BUILD_FIFO"
fi
''', 1))
    first_environment = environment | {"TEST_BUILD_BARRIER": "1", "TEST_BUILD_FIFO": str(build_fifo)}
    first_publisher = subprocess.Popen(
        ["/bin/bash", "scripts/create-app-bundle.sh"], cwd=workspace,
        env=first_environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert first_publisher.stdout is not None
    while True:
        line = first_publisher.stdout.readline()
        assert line, "first publisher exited before reaching its build barrier"
        if line.strip() == "BUILD_PAUSED":
            break
    try:
        second_publisher = subprocess.run(
            ["/bin/bash", "scripts/create-app-bundle.sh"], cwd=second_worktree,
            env=environment | {"PROJECT_ROOT": str(second_worktree)},
            text=True, capture_output=True, timeout=10,
        )
        assert second_publisher.returncode != 0, "second worktree published into the first publisher's destination"
        assert "another bundle publication" in second_publisher.stderr
    finally:
        build_fifo.write_text("release\n")
        first_output, first_error = first_publisher.communicate(timeout=10)
    assert first_publisher.returncode == 0, first_output + first_error
    print("PASS two worktrees cannot publish concurrently into one destination")

    shared_beta_root = workspace / "shared-beta-root"
    shared_beta_root.mkdir()
    for name, body in (("git", "exit 0"), ("mise", "exit 73")):
        executable = binaries / name
        executable.write_text(f"#!/bin/bash\n{body}\n")
        executable.chmod(0o755)
    with (shared_beta_root / ".agentstudio-local-beta.lock").open("w") as beta_selection:
        fcntl.flock(beta_selection, fcntl.LOCK_EX)
        for checkout in (workspace, second_worktree):
            selection = subprocess.run(
                ["/bin/bash", "scripts/create-local-beta-bundle.sh"], cwd=checkout,
                env=environment | {"AGENTSTUDIO_BETA_ARTIFACT_ROOT": str(shared_beta_root)},
                text=True, capture_output=True, timeout=10,
            )
            assert selection.returncode == 1 and "local beta publication already in progress" in selection.stderr
    print("PASS beta destination selection shares a lock across worktrees")

aggregate = tasks["test"]["run"]
assert aggregate.count("mise run --skip-deps bridge-web-build") == 1
assert "mise run --skip-deps test:swift" in aggregate
assert "mise run verify-vendors" in aggregate
assert 'test -f Sources/AgentStudio/Resources/BridgeWeb/app/index.html' in aggregate
assert "mise run --skip-deps setup-dev-resources" in tasks["refresh-vendors"]["run"]
assert "build" not in tasks["test:swift:benchmark"]["depends"]
assert "build-release" not in tasks["create-app-bundle"]["depends"]
assert "swift-build-slot.sh" in (root / "scripts/create-app-bundle.sh").read_text()
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
print("15 mise task contract groups passed")
PY
