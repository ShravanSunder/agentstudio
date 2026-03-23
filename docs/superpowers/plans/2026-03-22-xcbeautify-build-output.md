# xcbeautify Build Output Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pipe all `swift build` and `swift test` output through xcbeautify for readable, colored local output and GitHub Actions annotations in CI.

**Architecture:** xcbeautify acts as a pure output filter — stdin pipe, no code changes. We add it to three layers: the shared test helper script (covers `test` and `test-coverage`), the mise build/standalone-test tasks, and the CI/release workflows. GitHub Actions gets the `--renderer github-actions` flag for inline annotations. JUnit reports use per-invocation file paths to avoid clobbering across sequential test runs.

**Tech Stack:** xcbeautify (Homebrew), GitHub Actions (pre-installed on macOS runners)

**Key facts:**
- xcbeautify is **pre-installed on all GitHub Actions macOS runners** — no `brew install` needed in CI
- Usage: `swift build 2>&1 | xcbeautify` / `swift test 2>&1 | xcbeautify`
- GitHub renderer: `--renderer github-actions` (creates inline warning/error annotations)
- JUnit: `--report junit --report-path <file>.xml`
- `set -o pipefail` preserves the exit code from swift, not xcbeautify
- **Caveat:** xcbeautify was built for xcodebuild/XCTest output. Swift 6 `Testing` framework output may pass through partially unparsed. Verify during local testing (Task 1 Step 5). Worst case: output passes through unformatted, which is the same as today.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/swift-test-helpers.sh` | Modify | Pipe swift build/test through xcbeautify in helper functions; add `pipefail` guard |
| `.mise.toml` | Modify | Pipe `swift build` in build/build-release/test-e2e/test-zmx-e2e/test-benchmark through xcbeautify |
| `.github/workflows/ci.yml` | Modify | Add `--renderer github-actions`, JUnit reports (per-invocation paths), upload test results |
| `.github/workflows/release.yml` | Modify | Pipe release build through xcbeautify with github-actions renderer |
| `docs/guides/agent_resources.md` | Modify | Add xcbeautify to local dev prerequisites |

---

### Task 1: Add xcbeautify piping to swift-test-helpers.sh

The shared helper is sourced by the `test` and `test-coverage` mise tasks. Other standalone test tasks (`test-e2e`, `test-zmx-e2e`, `test-benchmark`) call swift directly and are handled in Task 2.

**Files:**
- Modify: `scripts/swift-test-helpers.sh`

- [ ] **Step 1: Add pipefail guard and xcbeautify detection**

The helper currently relies on callers having set `pipefail`. Make it self-contained by adding `pipefail` at the top, plus the xcbeautify detection function.

```bash
#!/usr/bin/env bash
# Shared test helper functions for mise tasks.
#
# Required variables (set by caller before sourcing):
#   LOG_PREFIX         - Log prefix, e.g. "test" or "test-coverage"
#   TIMEOUT_SECONDS    - Timeout in seconds for swift commands
#   BUILD_PATH         - Swift build path
#
# Optional variables:
#   EXTRA_SWIFT_TEST_ARGS - Additional swift test flags (e.g. "--enable-code-coverage")
#   XCB_EXTRA_ARGS        - Extra xcbeautify flags (e.g. "--renderer github-actions")

set -o pipefail

_xcb_pipe_cmd() {
  if command -v xcbeautify >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    echo "xcbeautify"${XCB_EXTRA_ARGS:+ $XCB_EXTRA_ARGS}
  else
    echo "cat"
  fi
}
```

- [ ] **Step 2: Pipe prebuild output through xcbeautify**

```bash
prebuild_swift_tests() {
  echo "[$LOG_PREFIX] >>> prebuild test bundles"
  local xcb_pipe
  xcb_pipe=$(_xcb_pipe_cmd)
  # shellcheck disable=SC2086
  swift build --build-tests ${EXTRA_SWIFT_TEST_ARGS:-} --build-path "$BUILD_PATH" 2>&1 | $xcb_pipe
}
```

- [ ] **Step 3: Pipe the command output in run_swift_with_timeout**

The tricky part: `run_swift_with_timeout` backgrounds the swift command and monitors it. We pipe through xcbeautify inside a subshell so we track one PID. The subshell inherits `pipefail` from the parent (bash forks the process), so if swift fails, the subshell exit code reflects the swift failure.

Replace the full function:

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

  # Run command piped through xcbeautify in a subshell so we track one PID.
  # Subshell inherits pipefail from parent — swift exit code propagates.
  # shellcheck disable=SC2086
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

- [ ] **Step 4: No change needed for run_webkit_suite_with_retry**

`run_webkit_suite_with_retry` calls `run_swift_with_timeout` internally, which now pipes through xcbeautify. No change needed here.

- [ ] **Step 5: Verify locally**

```bash
# Install xcbeautify if not present
brew install xcbeautify

# Run a quick filtered test to see beautified output
AGENT_RUN_ID=xcb mise run test
```

Expected: colored, clean output with test names and pass/fail status. Check specifically that Swift `Testing` framework output (`@Test`, `@Suite`) renders reasonably — if not, it passes through unformatted which is acceptable.

- [ ] **Step 6: Commit**

```bash
git add scripts/swift-test-helpers.sh
git commit -m "feat: pipe swift build/test output through xcbeautify in test helpers"
```

---

### Task 2: Add xcbeautify piping to mise build and standalone test tasks

The `test-e2e`, `test-zmx-e2e`, and `test-benchmark` tasks call swift directly (they don't source `swift-test-helpers.sh`), so they need explicit xcbeautify piping.

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

- [ ] **Step 3: Pipe test-e2e task output**

```toml
[tasks.test-e2e]
description = "Run E2E serialized tests only (opt-in; zmx E2E currently unstable)"
run = """
#!/usr/bin/env bash
set -euo pipefail
BUILD_PATH="${SWIFT_BUILD_DIR:-.build}"
if command -v xcbeautify >/dev/null 2>&1; then
  swift build --build-tests --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
  AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter E2ESerializedTests --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
else
  swift build --build-tests --build-path "$BUILD_PATH"
  AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter E2ESerializedTests --build-path "$BUILD_PATH"
fi
"""
```

- [ ] **Step 4: Pipe test-zmx-e2e task output**

```toml
[tasks.test-zmx-e2e]
description = "Run zmx E2E tests only (opt-in; may stall)"
run = """
#!/usr/bin/env bash
set -euo pipefail
BUILD_PATH="${SWIFT_BUILD_DIR:-.build}"
if command -v xcbeautify >/dev/null 2>&1; then
  swift build --build-tests --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
  AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter ZmxE2ETests --build-path "$BUILD_PATH" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
else
  swift build --build-tests --build-path "$BUILD_PATH"
  AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter ZmxE2ETests --build-path "$BUILD_PATH"
fi
"""
```

- [ ] **Step 5: Pipe test-benchmark task output**

```toml
[tasks.test-benchmark]
description = "Run benchmark-only bridge push tests"
depends = ["build"]
run = """
#!/usr/bin/env bash
set -euo pipefail
RUN_ID="${AGENT_RUN_ID:-}"
if [ -z "$RUN_ID" ]; then
  echo "[test-benchmark] ERROR: AGENT_RUN_ID is required (example: AGENT_RUN_ID=abc123 mise run test-benchmark)"
  exit 2
fi
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$RUN_ID}"
export AGENT_STUDIO_BENCHMARK_MODE=benchmark

if command -v xcbeautify >/dev/null 2>&1; then
  swift test --build-path "$BUILD_PATH" --filter "PushBenchmarkSupportTests" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
  swift test --build-path "$BUILD_PATH" --filter "PushPerformanceBenchmarkTests" 2>&1 | xcbeautify ${XCB_EXTRA_ARGS:-}
else
  swift test --build-path "$BUILD_PATH" --filter "PushBenchmarkSupportTests"
  swift test --build-path "$BUILD_PATH" --filter "PushPerformanceBenchmarkTests"
fi
"""
```

- [ ] **Step 6: Verify build locally**

```bash
AGENT_RUN_ID=xcb mise run build
```

Expected: beautified compilation output.

- [ ] **Step 7: Commit**

```bash
git add .mise.toml
git commit -m "feat: pipe all mise build/test tasks through xcbeautify"
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

- [ ] **Step 2: Override XCB_EXTRA_ARGS for the Test step with JUnit report**

Each `run_swift_with_timeout` invocation spawns a separate xcbeautify process. If all write to the same `--report-path`, later invocations clobber earlier results. Use a unique report path per step by setting the env only for the main test invocation (which runs the bulk of tests):

```yaml
      - name: Test
        env:
          SWIFT_TEST_WORKERS: "8"
          SWIFT_TEST_INCLUDE_E2E: "0"
          XCB_EXTRA_ARGS: "--renderer github-actions --report junit --report-path test-results-main.xml"
        run: mise run test
```

Note: The JUnit file will contain results from whichever xcbeautify invocation ran last within `mise run test` (the webkit suites or the main parallel suite, depending on ordering). This is a known limitation — xcbeautify creates a fresh report per process. For most CI purposes, the main parallel suite results (which run the bulk of tests) are sufficient. If complete aggregation is needed later, we can merge XML files in a post-step.

- [ ] **Step 3: Add test results upload step**

After the Test step, upload all JUnit XML files:

```yaml
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results-*.xml
          if-no-files-found: warn
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add xcbeautify github-actions renderer and JUnit reports to CI"
```

---

### Task 4: Add xcbeautify to release workflow

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Pipe release build through xcbeautify**

The release workflow has a standalone `swift build -c release` call that pipes through `filter-known-linker-warnings.sh`. Chain xcbeautify after the filter:

```yaml
      - name: Build AgentStudio
        run: |
          set -o pipefail
          swift build -c release 2>&1 | scripts/filter-known-linker-warnings.sh | xcbeautify --renderer github-actions
```

No job-level env var needed here — the renderer flag is hardcoded since this is the only swift command in the release workflow.

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
