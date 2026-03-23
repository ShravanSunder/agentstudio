# xcbeautify Build Output Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pipe all `swift build` and `swift test` output through xcbeautify for readable, colored local output and GitHub Actions annotations in CI.

**Architecture:** xcbeautify acts as a pure output filter — stdin pipe, no code changes. We add it to three layers: the shared test helper script (affects all mise test tasks), the mise build tasks, and the CI/release workflows. GitHub Actions gets the `--renderer github-actions` flag for inline annotations plus JUnit XML upload.

**Tech Stack:** xcbeautify (Homebrew), GitHub Actions (pre-installed on macOS runners)

**Key facts:**
- xcbeautify is **pre-installed on all GitHub Actions macOS runners** — no `brew install` needed in CI
- Usage: `swift build 2>&1 | xcbeautify` / `swift test 2>&1 | xcbeautify`
- GitHub renderer: `--renderer github-actions` (creates inline warning/error annotations)
- JUnit: `--report junit --report-path <file>.xml`
- `set -o pipefail` preserves the exit code from swift, not xcbeautify

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/swift-test-helpers.sh` | Modify | Pipe swift build/test through xcbeautify in helper functions |
| `.mise.toml` | Modify | Pipe `swift build` in build/build-release tasks through xcbeautify |
| `.github/workflows/ci.yml` | Modify | Add `--renderer github-actions`, JUnit report, upload test results |
| `.github/workflows/release.yml` | Modify | Pipe release build through xcbeautify with github-actions renderer |
| `docs/guides/agent_resources.md` | Modify | Add xcbeautify to local dev prerequisites |

---

### Task 1: Add xcbeautify piping to swift-test-helpers.sh

The shared helper is sourced by all mise test tasks, so this single change covers `test`, `test-coverage`, `test-e2e`, `test-zmx-e2e`, and `test-benchmark`.

**Files:**
- Modify: `scripts/swift-test-helpers.sh`

- [ ] **Step 1: Add xcbeautify detection at the top of the helpers**

Add a function that checks if xcbeautify is available and sets a pipe command variable. When unavailable (e.g. fresh CI without brew), fall back to `cat` so nothing breaks.

```bash
# Add after the comment block at top of file, before prebuild_swift_tests()

_xcb_pipe_cmd() {
  if command -v xcbeautify >/dev/null 2>&1; then
    echo "xcbeautify ${XCB_EXTRA_ARGS:-}"
  else
    echo "cat"
  fi
}
```

- [ ] **Step 2: Pipe prebuild output through xcbeautify**

```bash
prebuild_swift_tests() {
  echo "[$LOG_PREFIX] >>> prebuild test bundles"
  # shellcheck disable=SC2086
  swift build --build-tests ${EXTRA_SWIFT_TEST_ARGS:-} --build-path "$BUILD_PATH" 2>&1 | $(_xcb_pipe_cmd)
}
```

- [ ] **Step 3: Pipe the command output in run_swift_with_timeout**

The tricky part: `run_swift_with_timeout` backgrounds the swift command and monitors it. We need to pipe through xcbeautify while preserving the background PID and exit code. The pipe needs to be part of the backgrounded command group.

Replace the `"$@" &` line and the `wait` logic:

```bash
run_swift_with_timeout() {
  local label="$1"
  shift
  local timeout_seconds="$1"
  shift

  echo "[$LOG_PREFIX] >>> $label (timeout=${timeout_seconds}s)"
  local start_epoch
  start_epoch=$(date +%s)
  local last_heartbeat="$start_epoch"
  local timed_out=0

  local xcb_pipe
  xcb_pipe=$(_xcb_pipe_cmd)

  # Run command piped through xcbeautify in a subshell so we track one PID
  ( "$@" 2>&1 | $xcb_pipe ) &
  local command_pid=$!

  while kill -0 "$command_pid" 2>/dev/null; do
    sleep 1
    local now_epoch
    now_epoch=$(date +%s)
    local elapsed_seconds=$((now_epoch - start_epoch))

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      timed_out=1
      break
    fi

    if [ $((now_epoch - last_heartbeat)) -ge 20 ]; then
      echo "[$LOG_PREFIX] ... $label still running (${elapsed_seconds}s)"
      last_heartbeat="$now_epoch"
    fi
  done

  if [ "$timed_out" -eq 1 ]; then
    echo "[$LOG_PREFIX] ERROR: timeout while running '$label' after ${timeout_seconds}s"
    kill -TERM "$command_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$command_pid" 2>/dev/null || true
    pkill -9 -f "swiftpm-testing-helper|swift test|swift-build|AgentStudioPackageTests" || true
    wait "$command_pid" 2>/dev/null || true
    return 124
  fi

  set +e
  wait "$command_pid"
  local command_status=$?
  set -e

  return "$command_status"
}
```

- [ ] **Step 4: Pipe webkit retry suite output**

In `run_webkit_suite_with_retry`, the output is already captured in a variable. Update the swift test invocation to pipe through xcbeautify:

```bash
    output=$(run_swift_with_timeout "$filter" "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} \
      --skip-build --filter "$filter" --build-path "$BUILD_PATH" 2>&1)
```

This already goes through `run_swift_with_timeout` which now pipes through xcbeautify internally. **No change needed here** — the pipe is handled by the timeout wrapper.

- [ ] **Step 5: Verify locally**

```bash
# Install xcbeautify if not present
brew install xcbeautify

# Run a quick filtered test to see beautified output
AGENT_RUN_ID=xcb mise run test
```

Expected: colored, clean output with test names and pass/fail status.

- [ ] **Step 6: Commit**

```bash
git add scripts/swift-test-helpers.sh
git commit -m "feat: pipe swift build/test output through xcbeautify in test helpers"
```

---

### Task 2: Add xcbeautify piping to mise build tasks

**Files:**
- Modify: `.mise.toml`

- [ ] **Step 1: Pipe build task output**

In `[tasks.build]`, change the swift build line:

```toml
[tasks.build]
description = "Debug build (run mise run setup first time)"
run = """
#!/usr/bin/env bash
set -euo pipefail
RUN_ID="${AGENT_RUN_ID:-}"
if [ -z "$RUN_ID" ]; then
  echo "[build] ERROR: AGENT_RUN_ID is required (example: AGENT_RUN_ID=abc123 mise run build)"
  exit 2
fi
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$RUN_ID}"
echo "[build] BUILD_PATH=$BUILD_PATH"
if command -v xcbeautify >/dev/null 2>&1; then
  swift build --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
else
  swift build --build-path "$BUILD_PATH"
fi
"""
```

- [ ] **Step 2: Pipe build-release task output**

Same pattern for `[tasks.build-release]`:

```toml
[tasks.build-release]
description = "Release build (run mise run setup first time)"
run = """
#!/usr/bin/env bash
set -euo pipefail
RUN_ID="${AGENT_RUN_ID:-}"
if [ -z "$RUN_ID" ]; then
  echo "[build-release] ERROR: AGENT_RUN_ID is required (example: AGENT_RUN_ID=abc123 mise run build-release)"
  exit 2
fi
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-release-agent-$RUN_ID}"
echo "[build-release] BUILD_PATH=$BUILD_PATH"
if command -v xcbeautify >/dev/null 2>&1; then
  swift build -c release --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
else
  swift build -c release --build-path "$BUILD_PATH"
fi
"""
```

- [ ] **Step 3: Verify build locally**

```bash
AGENT_RUN_ID=xcb mise run build
```

Expected: beautified compilation output.

- [ ] **Step 4: Commit**

```bash
git add .mise.toml
git commit -m "feat: pipe mise build tasks through xcbeautify"
```

---

### Task 3: Add xcbeautify to CI workflow with GitHub renderer + JUnit

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Set XCB_EXTRA_ARGS env var for the job**

Add `XCB_EXTRA_ARGS` at the job level so all mise tasks automatically pick it up via the `${XCB_EXTRA_ARGS:-}` expansion we added in Tasks 1-2:

```yaml
jobs:
  build:
    runs-on: macos-26
    env:
      AGENT_RUN_ID: ci
      XCB_EXTRA_ARGS: "--renderer github-actions"
```

xcbeautify is pre-installed on macOS runners — no install step needed.

- [ ] **Step 2: Add JUnit report generation to the Test step**

Update the Test step to also generate a JUnit XML report. We set `XCB_EXTRA_ARGS` to include the report flag for the test step specifically:

```yaml
      - name: Test
        env:
          SWIFT_TEST_WORKERS: "8"
          SWIFT_TEST_INCLUDE_E2E: "0"
          XCB_EXTRA_ARGS: "--renderer github-actions --report junit --report-path test-results.xml"
        run: mise run test
```

- [ ] **Step 3: Add test results upload step**

After the Test step, add a step to upload the JUnit XML as a check/artifact:

```yaml
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results.xml
          if-no-files-found: warn
```

- [ ] **Step 4: Verify the Build step also gets beautified**

The Build step (`mise run build-release`) will pick up the job-level `XCB_EXTRA_ARGS: "--renderer github-actions"` automatically. No change needed to that step.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add xcbeautify github-actions renderer and JUnit reports to CI"
```

---

### Task 4: Add xcbeautify to release workflow

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add XCB_EXTRA_ARGS env and pipe release build**

The release workflow has a standalone `swift build -c release` call that pipes through `filter-known-linker-warnings.sh`. Chain xcbeautify after the filter:

```yaml
jobs:
  build:
    runs-on: macos-26
    env:
      XCB_EXTRA_ARGS: "--renderer github-actions"

    steps:
      # ... existing steps unchanged ...

      - name: Build AgentStudio
        run: |
          set -o pipefail
          swift build -c release 2>&1 | scripts/filter-known-linker-warnings.sh | xcbeautify --renderer github-actions
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: pipe release build through xcbeautify with github-actions renderer"
```

---

### Task 5: Document xcbeautify as a local dev prerequisite

**Files:**
- Modify: `docs/guides/agent_resources.md` (add to prerequisites section)

- [ ] **Step 1: Add xcbeautify to the local tool list**

Find the prerequisites/setup section and add:

```markdown
- **xcbeautify** — beautifies swift build/test output: `brew install xcbeautify`
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/agent_resources.md
git commit -m "docs: add xcbeautify to local dev prerequisites"
```
