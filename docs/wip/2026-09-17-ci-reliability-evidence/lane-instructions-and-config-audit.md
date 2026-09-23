# Lane: Instructions & Config Audit (PR350 CI flakes)

Read-only audit of every agent-instruction file, mise task, CI workflow, lint
config, and BridgeWeb test config for places that teach, permit, or hard-code
the bad patterns behind two weeks of CI flakiness.

**Evidence discipline.** Every claim below is marked **VERIFIED** (I opened the
file and read the cited line in this session) or **UNVERIFIED** (I did not, or
could not, check it). A third marker, **VERIFIED-SIBLING**, means the fact was
established by the `lane-swift-runner-starvation` lane from real CI logs and I
read its recorded evidence but not the log itself.

## 0. Inventory of instruction surfaces (so nothing is missed)

**VERIFIED** — `find` over the repo excluding `.build*`, `node_modules`, `vendor`:

| Path | Kind | Note |
| --- | --- | --- |
| `AGENTS.md` | real file, 30 KB | the single root contract |
| `CLAUDE.md` | **symlink → `AGENTS.md`** | not a second file; do not report separately |
| `BridgeWeb/AGENTS.md` | real file | React UI rules |
| `web/AGENTS.md` | real file | marketing site (Astro); out of the Swift/CI blast radius |
| `web/.agents/skills/ai-copywriter/AGENTS.md` | real file | marketing copy skill only |
| `.codex/skills/agentstudio-bridgeweb-react-ui/SKILL.md` | real file | only skill in repo |
| `.claude/`, `.cursor/`, `.agents/` (root), `.gemini/`, `GEMINI.md`, root `*.mdc` | **ABSENT** | see F1 |

`.build*/checkouts/agentstudio-git/{AGENTS.md,CLAUDE.md,.cursor/rules/swift-rules.mdc}`
are vendored SwiftPM checkouts of a dependency, not this repo's instructions.

---

## A. Stale workarounds and lapsed time-based notes

### A1. The Xcode 26.3 pin — removal condition is **MET**, pin still in force (7 sites)

The condition stated in the note is *"Remove this note once ghostty bumps to zig
0.16 or Apple ships a fixed SDK."*

**Evidence the condition is met** — **VERIFIED**:
- `.mise.toml:4` — `zig = "0.16.0"` (top-level `[tools]`)
- `.mise.toml:33` — `tools.zig = "0.16.0"` (the `build-zmx` task)
- `Tests/AgentStudioTests/Scripts/VendorConsumerWiringScriptTests.swift:13-14` asserts
  both of those strings, so the 0.16 move is *gated*, not incidental.
- `docs/wip/zmx-pr2/progress.md:5` — `"Zig 0.16 builds both vendors."`

The repo is on zig 0.16. **The workaround is obsolete.** Sites still carrying it:

| # | File:line | Quoted text (truncated) | Correction |
| --- | --- | --- | --- |
| A1a | `README.md:124` | `> **Time-based note (as of 2026-04):** Xcode 26.4+ ships a MacOSX.sdk/… which breaks zig 0.15.2's bundled linker … Remove this note once ghostty bumps to zig 0.16` | Delete the note. |
| A1b | `docs/guides/agent_resources.md:139` | `> **Time-based note (2026-04): Xcode 26.4+ breaks vendored zig 0.15.2 builds.** … Delete this note once ghostty bumps to zig 0.16 or Apple fixes the SDK.` | Delete the note and the `### Xcode And Zig Vendor Builds` heading's stale body. |
| A1c | `docs/guides/agent_resources.md:30` | `# 1. Install pinned tool versions (zig 0.15.2)` | Now factually wrong — `.mise.toml` pins 0.16.0. Fix to 0.16.0. |
| A1d | `.github/workflows/ci.yml:27-30, 150-153, 271-274` | `- name: Select Xcode 26.3` / `xcode-version: "26.3"` (three jobs) | Remove the step so the runner image default (26.6) is used. |
| A1e | `.github/workflows/benchmarks.yml:32-35` | `- name: Select Xcode 26.3` | Same. |
| A1f | `.github/workflows/release.yml:29-32` | `- name: Select Xcode 26.3` | Same, but change release last and re-prove notarization. |
| A1g | `.github/workflows/ci.yml:46,48` | `key: architecture-lint-…-xcode-26.3-${{ hashFiles(…) }}` and the `restore-keys` prefix | The literal `26.3` is baked into a cache key; changing the toolchain without bumping this key serves a cache built by a different compiler. Replace with a version-derived value or a bumped literal. |
| A1h | `scripts/doctor-mac.sh:61-62` | `if [[ -n "$xcode_version" && "$xcode_version" != "26.3" ]]; then` / `report_warn "local Xcode ($xcode_version) differs from the GitHub Actions baseline (26.3 on macos-26-arm64)"` | Doctor will warn at *every* developer on a correct toolchain once CI moves. Update the baseline constant. |
| A1i | `AGENTS.md:73-74` | `Do not use SwiftPM --parallel or --num-workers as a substitute for process isolation: Xcode 26.3 still runs Swift Testing through one helper process.` | The *rule* survives the upgrade; the *justification clause* names the pin. See C1/C2. |
| A1j | `scripts/swift-test-helpers.sh:338-339` | `# harness wraps the entire Testing library in one helper process on Xcode` / `# 26.3 and can deadlock its event stream under the fast inventory's volume.` | Same: comment cites the pinned version as the reason. |

### A2. **The pin is load-bearing on a test — this blocks the fix** (highest-leverage finding)

**VERIFIED** — `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:37,42`:

```swift
let xcodeStep = try workflowStep(named: "Select Xcode 26.3", in: workflow)
#expect(xcodeStep.contains("xcode-version: \"26.3\""))
```

Line 29-33 loops this over `ci.yml`, `benchmarks.yml`, **and** `release.yml`.
Deleting the pin from any workflow makes this test **throw** (`workflowStep`
throws `missingBlock` when the marker is absent, line 855). Correction: this
test must be changed in the same commit as the pin removal — either drop the
Xcode assertions entirely, or assert the *absence* of a pin.

### A3. Other dated / conditional notes

- **VERIFIED** `BridgeWeb/vitest.e2e.config.ts:15-17` —
  `// Browser repaint/scroll journeys are timing-sensitive on CI runners; one retry`
  `// keeps every assertion while tolerating the known intermittent.` / `retry: 1,`
  "The known intermittent" is never named or linked. Given finding B5 (the retry
  *cannot* help), this is a lapsed rationale. Correction: name the intermittent
  or delete the retry.
- **VERIFIED** `.swiftlint.yml:119` — `# Swift 6 concurrency anti-patterns (LUNA-325 migration scope)` and
  `:123` — `LUNA-325 migrates remaining instances to typed event streams.`
  Ticket-scoped `severity: warning` grandfathering with no stated expiry.
  **UNVERIFIED**: whether LUNA-325 is closed (no Linear access used).
- **VERIFIED** `.swiftlint.yml:178-182` and `:199-201` — thresholds explicitly
  documented as accommodating named legacy files ("Tighten limits as files are
  refactored"), with line counts (`WorkspaceStore.swift: 1646 lines`) that may
  have drifted. **UNVERIFIED**: current line counts.

---

## B. Instructions that teach or permit bad waits

### B1. **`No Wall-Clock Tests` is silent on turn-count / yield polling** — the core gap

**VERIFIED** — `AGENTS.md:371-389`, quoted in full-relevant part:

```
Do not:
- use `Task.sleep(...)` in test bodies to wait for async work
...
Instead:
- wait for the exact event or state you care about, with a bounded timeout
```

The prohibition list names **only `Task.sleep`**. It says nothing about
`Task.yield()` loops, turn counters, `while` polling, or `eventually`-style
helpers. Correction: extend the "Do not" list to name turn-count/yield loops and
repeated-read polling explicitly, and state that "wait for the exact event" means
an `AsyncStream`/continuation/quiescence barrier, not a re-read loop.

### B2. **The lint rule bans `Task.sleep` and nothing else — it *manufactured* the 678 polling sites**

**VERIFIED** — `Tools/…/Rules/TestTaskSleepRule.swift:4-7`:

```swift
let id = "agentstudio_no_task_sleep_in_tests"
let severity = ArchitectureSeverity.error
let message = "Tests must wait for explicit events, state, or injected fake clocks instead of direct Task.sleep"
```

The visitor (lines 46-59) matches **only** a member access whose base is `Task`
and whose name is `sleep`. `Task.yield()` is not matched. So the only mechanical
gate in the repo is an `error`-severity ban on the *honest* wait and a total
blind spot on the *dishonest* one. This is the direct causal path from the
instruction set to the 678 polling call sites. Correction: add a sibling rule
(`agentstudio_no_polling_waits_in_tests`) at `.error` that flags `Task.yield()`
inside loop/repeat constructs and repeated-read-until-true shapes in `/Tests/`,
and register it in `ExpectedRuleInventory` (see E4).

### B3. Existing rules that already forbid the bad patterns (the non-gaps, for contrast)

- **VERIFIED** `AGENTS.md:373-374` — `Wall-clock sleeps make tests flaky. CI machines run at different speeds, so "sleep 50ms and expect X" is not a contract.` Correct in spirit; too narrow in letter (B1).
- **VERIFIED** `AGENTS.md:382` — `rely on suite serialization to hide leaked async work` is in the Do-not list. Good.
- **VERIFIED** `AGENTS.md:387` — `fully shut down tasks, streams, actors, and observers before the test returns`. Good — this is the quiescence-barrier idea, but it is stated as teardown hygiene, not as the *wait* mechanism.
- **VERIFIED** `AGENTS.md:414` — `**@concurrent nonisolated** for blocking I/O … **This is a correctness requirement in 6.2, not a style choice.**` The rule for finding (3) already exists in prose. The gap is enforcement (B4).
- **VERIFIED** `docs/guides/agent_resources.md:105` — `Do not clear another running server's cache or compensate with product retries.` An explicit anti-retry rule, and it is the one the E2E `retry: 1` arguably violates in spirit.

### B4. The `@concurrent` rule exists but **cannot fail CI** — severity is `.report`

**VERIFIED** — `Tools/…/Rules/NonisolatedAsyncBlockingIORule.swift:4-6`:

```swift
let id = "agentstudio_nonisolated_async_blocking_io_requires_concurrent"
let severity = ArchitectureSeverity.report
```

**VERIFIED** — `Tools/…/Core/ArchitectureDiagnostic.swift`, `ArchitectureSeverity`:

```swift
var affectsExitCode: Bool { self != .report }
```

So all ~56 blocking calls are printed and ignored. Two further limits, both
**VERIFIED** by reading the visitor (lines 26-37): it inspects only
`FunctionDeclSyntax` that is *both* `nonisolated` *and* `async`; blocking I/O in
an actor method, a plain `async` method, a closure, or a `Task { }` body is
invisible to it.

Correction: raise to `.error` — but note this is **also test-locked**:
**VERIFIED** `Tools/…/Tests/…/RuleParityTests.swift:30` asserts
`allSatisfy { $0.severity == .report }` for the four performance rules, and
`RuleInventoryTests.swift` pins every `(id, severity)` pair. Both must change in
the same commit.

### B5. `retry: 1` on BridgeWeb E2E is structurally incapable of helping

**VERIFIED** — three files together:
- `BridgeWeb/vitest.e2e.config.ts:17` — `retry: 1,`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts:159` —
  `dataRootPath = await mkdtemp(join(tmpdir(), 'bridge-viewer-vite-product-data-'));`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts:454` —
  `BRIDGE_WEB_VITE_CACHE_DIR: join(oracle.dataRootPath, 'vite-cache'),`

The Vite cache dir is a subdirectory of a **freshly `mkdtemp`'d** data root, so
every fixture construction starts Vite's dependency optimizer **cold**. A retry
re-runs the test body, which constructs the fixture again, which makes a *new*
`mkdtemp` and another cold prebundle. The retry pays the full cold cost a second
time and changes nothing about the failure mode.

Compounding, **VERIFIED**: `vitest.e2e.config.ts:6` — `fileParallelism: false`,
and 12 e2e test files reference the fixture, so the cold prebundles serialize.

Correction: hoist the optimizer cache to one warm, repo-level directory shared
across fixtures (keeping the *data* root per-fixture for isolation), then delete
`retry: 1`. Note `docs/guides/agent_resources.md:97-105` already says each *live
server* needs its own cache — that rule is about concurrent dev servers, and does
not require a cold cache for serialized test fixtures; the distinction should be
written down.

### B6. Agent-facing guidance that teaches raising timeouts and is numerically wrong

**VERIFIED** — `docs/guides/agent_resources.md:181`:

```
**Timeouts are mandatory.** `60000` (60s) for test, `30000` (30s) for build. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention.
```

Three problems: (a) it hands agents a fixed wall-clock budget as doctrine;
(b) "Tests complete in ~15s" is contradicted by the repo's own CI evidence
(`docs/wip/2026-09-17-ci-reliability-evidence/lane-swift-runner-starvation.md:78`
records `Prebuild Swift test bundles (19m 32s)`, **VERIFIED-SIBLING**); (c) it
teaches the diagnosis "anything longer means lock contention", which will send an
agent hunting build slots when the real cause is test-suite load. Correction:
replace the fixed numbers with "let the mise watchdog own the budget; do not set
a tool-level timeout below it", and delete the ~15s claim.

### B7. Retry-on-crash in the WebKit lane

**VERIFIED** — `scripts/swift-test-helpers.sh:664-710`, `run_webkit_suite_with_retry`:

```bash
local max_attempts=3
...
if [ "$command_status" -ne 124 ] && grep -Eq "unexpected signal code [0-9]+" <<<"$output"; then
```

and **VERIFIED** `.github/workflows/ci.yml:405-406`:

```yaml
# WebKit teardown can crash swiftpm-testing-helper after assertions pass;
# this lane isolates real WebKit runtime suites and retries signal crashes.
```

This is the most *defensible* retry in the repo (it is narrowly scoped to a
signal crash after assertions passed, with exponential backoff, and it excludes
timeouts). It is still a green-from-red mechanism that hides a real teardown
bug. Correction for the standard: keep it, but require it to be the **only**
sanctioned retry, require the signal-code allowlist to be explicit rather than
`[0-9]+`, and require a tracked defect for the underlying teardown crash.

### B8. Retry/poll knobs in the proof scripts (not PR gates, but they set the norm)

**VERIFIED** (names harvested by `grep -ohE 'AGENTSTUDIO_[A-Z_]+'` over `scripts/`):
`AGENTSTUDIO_BRIDGE_COMPLETE_JOURNEY_ATTEMPTS`,
`AGENTSTUDIO_BRIDGE_COMPLETE_JOURNEY_RECEIPT_WAIT_ATTEMPTS`,
`AGENTSTUDIO_BRIDGE_HEADLESS_VICTORIA_ATTEMPTS`,
`AGENTSTUDIO_BRIDGE_HEADLESS_VICTORIA_RETRY_DELAY_SECONDS`,
`AGENTSTUDIO_BRIDGE_IDLE_POLL_SECONDS`.
These are attempt-count/poll-interval knobs in the observability verifiers.
**UNVERIFIED**: their default values and whether any is on a PR gate. Correction:
out of scope for the PR lane, but the standard should say polling is acceptable
*only* when observing an external system (a Victoria query endpoint) and never
for in-process async work.

---

## C. Contradictions

### C1. `--parallel` / `--num-workers`: instruction vs. tooling

**VERIFIED** — `AGENTS.md:72-74`:

```
Do not use SwiftPM
`--parallel` or `--num-workers` as a substitute for process isolation: Xcode
26.3 still runs Swift Testing through one helper process.
```

**VERIFIED** — the tooling does exactly that, in three places:

| Site | Line | Text |
| --- | --- | --- |
| `scripts/swift-test-helpers.sh` | 354-355 | `if [ -n "${SWIFT_TEST_NUM_WORKERS:-}" ]; then` / `parallel_args+=(--num-workers "$SWIFT_TEST_NUM_WORKERS")` |
| `.github/workflows/ci.yml` | 399 | `SWIFT_TEST_NUM_WORKERS: "4"` (the large lane) |
| `scripts/run-swift-test-task.sh` | 103 | `SWIFT_TEST_NUM_WORKERS=4 run_large_non_webkit_swift_tests` (the local `mise run test` aggregate) |

The rule's escape hatch is the phrase *"as a substitute for process isolation"*,
and AGENTS.md:63 narrows the `--parallel` ban to *"the fast inventory"* — so the
large lane is arguably compliant by letter. But the *stated justification* is
that the flags do nothing, which makes using them elsewhere incoherent.

**VERIFIED-SIBLING** (`lane-swift-runner-starvation.md:99,381-384`): the large
lane's `--parallel --num-workers 4` still produces **one** process, and there is
no parallelism-width knob for Swift Testing in this toolchain. So the flag is
inert (see F2). Correction: either delete `--num-workers` plumbing entirely, or
document precisely what it does and does not do.

### C2. The fast-lane concurrency rule was written for a toolchain with **no cap**

**VERIFIED** — `AGENTS.md:62-64`:

```
The Swift fast lane keeps ordinary suites
concurrent through Swift Testing itself; do not add SwiftPM `--parallel` to the
fast inventory.
```

This sentence is the instruction that produces ~4,900 tests in flight on a
3-vCPU runner: it delegates width to "Swift Testing itself", and on the pinned
26.3 that means unbounded. **UNVERIFIED** (from the task brief, not checked by
me): 26.6 adds `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` defaulting to
2×CPU. Correction: the rule must stop being silent about width — name the cap
mechanism and its value explicitly, so "concurrent through Swift Testing itself"
is a bounded claim rather than an unbounded one.

### C3. `mise run test` is a **strictly stronger** gate than CI — the PR gate lies

**VERIFIED** — `.mise.toml:329` sets `SWIFT_TEST_INCLUDE_E2E=1` for the local
aggregate, which reaches `scripts/run-swift-test-task.sh:107`
(`if [ "${SWIFT_TEST_INCLUDE_E2E:-0}" = "1" ]`) and runs `E2ESerializedTests`.

**VERIFIED** — `SWIFT_TEST_INCLUDE_E2E` appears **nowhere** in
`.github/workflows/ci.yml` (grep over the file), and CI never invokes the `test`
mode; it invokes `test:swift:prebuild`, `test:swift:fast`, `test:swift:large`,
`test:swift:webkit` as four separate steps (ci.yml:386, 393, 401, 410).

So `E2ESerializedTests` runs locally and **never runs in CI**. Meanwhile
`AGENTS.md:39-43` tells agents that `mise run test` is the PR gate and lists
"general E2E tests" as part of it. An agent who trusts CI green has less
coverage than one who ran the local gate. Correction: either add an E2E step to
`ci.yml` or state plainly in AGENTS.md that E2E is local-only.

### C4. Duplicated large lane, drifted between two workflows

**VERIFIED** — both exist and differ:

| | `ci.yml:395-401` ("Test large lane") | `benchmarks.yml:133-138` ("Test large non-WebKit lane") |
| --- | --- | --- |
| `SWIFT_TEST_SKIP_PREBUILD` | `"1"` | *absent* → rebuilds |
| `SWIFT_TEST_NUM_WORKERS` | `"4"` | *absent* → no `--num-workers` |
| `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS` | *absent* | `"900"` |
| invocation | `mise run --skip-deps --raw test:swift:large` | `mise run test:swift:large` (deps run) |

`benchmarks.yml:7-8` says the nightly exists to keep timing policies "exercised
without putting wall-clock gates in the pull-request lanes" — yet the large lane
is in **both**. Correction: decide which lane owns it; if both, converge the env.

### C5. AGENTS.md claims a hook that does not exist

**VERIFIED** — `AGENTS.md:76-78`:

```
A
PostToolUse hook (`.claude/hooks/check.sh`) runs swift-format and SwiftLint
automatically after every Edit/Write on `.swift` files.
```

**VERIFIED** — `.claude/` does not exist in this repo (`ls .claude` →
`No such file or directory`). The actual mechanism is `.githooks/pre-commit`
(**VERIFIED** present, and it does run `swift-format format --in-place` +
`swiftlint lint --fix` + `swiftlint lint --strict` on staged files). Correction:
the sentence promises automatic per-edit formatting that does not happen; agents
who believe it will skip `mise run format` and hit lint failures at commit time.
Point the sentence at `.githooks/pre-commit` instead.

---

## D. Every timeout, watchdog, retry, concurrency width, and cache key

**All rows VERIFIED** unless marked. "Fixed wall-clock?" answers: could a loaded
runner blow this budget without anything actually being wrong?

### D.1 Swift test watchdog and timeouts

| Name | Value | File:line | Governs | Fixed wall-clock a loaded runner could exceed? |
| --- | --- | --- | --- | --- |
| `TIMEOUT_SECONDS` default | `60` | `scripts/run-swift-test-task.sh:20` | per-command **inactivity** budget | **No** — inactivity, not elapsed. But 60 s is the default whenever CI/mise does not override. |
| `PREBUILD_TIMEOUT_SECONDS` default | `90` | `scripts/run-swift-test-task.sh:21` | prebuild inactivity | **No**, but 90 s default vs. a 19 m 32 s real prebuild means any caller that forgets the override is at risk during quiet link phases. |
| `SWIFT_TEST_TIMEOUT_SECONDS` (CI, all 4 steps) | `600` | `ci.yml:384,391,398,408` | inactivity | No |
| `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS` (CI) | `1200` | `ci.yml:385` | prebuild inactivity | No |
| `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS` (benchmarks) | `900` | `benchmarks.yml:135` | prebuild inactivity | No — but **inconsistent** with CI's 1200 (C4) |
| `SWIFT_TEST_TIMEOUT_SECONDS` (mise aggregate) | `600` | `.mise.toml:330` | inactivity | No |
| `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS` (mise aggregate) | `1200` | `.mise.toml:331` | prebuild inactivity | No |
| `TIMEOUT_SECONDS` (coverage task) | `60` | `.mise.toml:393` | inactivity for the whole coverage run | **Risky** — coverage-instrumented runs are slow; 60 s inactivity is the un-overridden default here. |
| watchdog poll interval | `sleep 1` | `swift-test-helpers.sh:488` | how often output size is sampled | n/a |
| heartbeat interval | `20` s | `swift-test-helpers.sh:512` | progress logging | n/a |
| timeout exit code | `124` | `swift-test-helpers.sh:457,530` | signals timeout upward | n/a |
| SIGTERM→SIGKILL grace | `sleep 2` | `swift-test-helpers.sh:527` | process-tree teardown | n/a |
| stuck-process sample cap | `3` processes, `3` s each | `swift-test-helpers.sh:625,644` | timeout diagnostics | n/a |

**Design note (VERIFIED, and a genuine strength):** the watchdog measures
*output inactivity*, not elapsed time — `swift_test_watchdog_state`
(`swift-test-helpers.sh:437-448`) only advances `last_progress_epoch` when
`output_size` grows, and `CIFastLaneWorkflowTests.swift:463` explicitly asserts
the elapsed-time form is **absent**. This is the right shape and should be
preserved by any change.

### D.2 Concurrency widths

| Name | Value | File:line | Governs | Notes |
| --- | --- | --- | --- | --- |
| `process_global_concurrency` | `4` | `swift-test-helpers.sh:226` | isolated process-global suites run 4-at-a-time | Hard-coded; not runner-CPU-aware. On a 3-vCPU runner, 4 concurrent test processes oversubscribe. |
| `SWIFT_TEST_NUM_WORKERS` | `4` (CI large), `4` (local aggregate) | `ci.yml:399`, `run-swift-test-task.sh:103` | `--num-workers` | **Inert** — see F2 |
| `SWIFT_TEST_PARALLEL` | default `1` | `swift-test-helpers.sh:317,352` | chooses `--parallel` branch | Only read by `run_non_serialized_swift_tests` and `run_large_non_webkit_swift_tests`; the **fast lane ignores it** (F3) |
| fast-lane in-process width | **unbounded** | `swift-test-helpers.sh:340-345` (no `--parallel`, no width flag) | ~4,900 tests in flight | **The root cause.** Nothing in repo config bounds it. |
| Vitest browser | `maxWorkers: '50%'` | `vitest.browser.config.ts:41` | browser lane workers | On a 3-vCPU runner this is 1-2; reasonable |
| Vitest integration | `fileParallelism: false` | `vitest.integration.config.ts:20` | serialized | |
| Vitest E2E | `fileParallelism: false` | `vitest.e2e.config.ts:6` | serialized | Combined with cold caches → additive (B5) |

### D.3 Retries

| Name | Value | File:line | Governs |
| --- | --- | --- | --- |
| WebKit signal retry | `max_attempts=3`, backoff `1→2→4` s | `swift-test-helpers.sh:667-669, 700-702` | retries only on `unexpected signal code N`; **not** on timeout 124 (line 689-691) |
| Vitest E2E retry | `retry: 1` | `vitest.e2e.config.ts:17` | every e2e test; see B5 |
| Vitest unit/browser/integration retry | **none set** | — | inherits Vitest default 0 |

### D.4 Vitest timeouts

| Name | Value | File:line | Fixed wall-clock a loaded runner could exceed? |
| --- | --- | --- | --- |
| `testTimeout` (E2E) | `180_000` | `vitest.e2e.config.ts:13` | **Yes** — 180 s elapsed per test, and a cold Vite prebundle is inside it |
| `hookTimeout` (E2E) | `60_000` | `vitest.e2e.config.ts:14` | **Yes** — fixture construction (incl. cold prebundle + git fixture writes) happens in hooks |
| `testTimeout` (browser integration) | `60_000` | `vitest.browser.config.ts:68` | **Yes** |
| unit lane | unset (Vitest default 5 s) | `vitest.config.ts` | **Yes** for any unit test that touches I/O |

`ci.yml:128-130` **VERIFIED** already acknowledges this class of problem:
`"sharing this runner causes Vitest's per-test timeout to become load-dependent."`
The mitigation chosen was job separation, not budget removal.

### D.5 Playwright

**VERIFIED** — `vitest.browser.config.ts:15-17` uses
`playwright({ launchOptions: { channel: 'chrome' } })`. No explicit Playwright
`timeout`/`expect.timeout` is set anywhere in the configs I read. **UNVERIFIED**:
Playwright's own defaults as they apply through `@vitest/browser-playwright`.
Two fixed values worth flagging: `api.port: 63325` (line 22) and `63326`
(line 100) are **hard-coded, non-`strictPort`-guarded ports** — two runs on one
machine collide. See G3.

### D.6 Workflow-level budgets

| Workflow | `timeout-minutes` | `concurrency` | File:line |
| --- | --- | --- | --- |
| `ci.yml` (all 5 jobs) | **NONE** | **NONE** | verified absent by grep over the file |
| `benchmarks.yml` | **NONE** | `group: benchmarks-${{ github.ref }}`, `cancel-in-progress: false` | `:15-17` |
| `release.yml` | `45` | `group: release-…`, `cancel-in-progress: true` | `:19`, `:13-14` |
| `daily-beta.yml` | `5` | `group: daily-beta-tag`, `cancel-in-progress: false` | `:20`, `:12-13` |

**This is the biggest structural gap in D.** With no `timeout-minutes`, a wedged
`ci.yml` job runs to GitHub's default job limit. With no `concurrency` group, a
force-push to a PR leaves the superseded run competing for the same macOS runner
pool — which directly worsens the load-dependent timeouts in D.4. Correction:
add `timeout-minutes` per job (sized above the observed 25-minute Swift job) and
`concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`.

### D.7 Cache keys

| Key | File:line | Rot risk |
| --- | --- | --- |
| `architecture-lint-…-xcode-26.3-${{ hashFiles('Tools/…/Package.swift','…/Package.resolved') }}` | `ci.yml:46` (+ restore-key `:48`) | Literal `26.3`; see A1g |
| `zig-compile-${{ runner.os }}-<ghostty_sha>-<zmx_sha>` with restore-key `zig-compile-${{ runner.os }}-` | `ci.yml:192-194`, `:322-324` | Broad restore-key means a stale zig cache from a *different* zig version can be restored; nothing in the key names the zig version |
| `ghostty-${{ runner.os }}-<ghostty_sha>` | `ci.yml:203`, `:333` | No `restore-keys` — correct (exact or cold) |
| `zmx-${{ runner.os }}-<zmx_sha>` | `ci.yml:210`, `:340` | Same — correct |
| `benchmark-swift-build-ci-${{ runner.os }}-${{ hashFiles('Package.swift','Package.resolved') }}` | asserted at `CIFastLaneWorkflowTests.swift:222` | Does not include toolchain version |
| pnpm cache via `cache-dependency-path` | `ci.yml:84`, `:118`, `:307` | Standard |

**Note (VERIFIED):** `CIFastLaneWorkflowTests.swift:153-170` asserts Swift build
outputs are **deliberately never cached** for the test jobs ("Swift jobs always
build cold"). That is why the prebuild costs 19 m 32 s. It is an intentional
choice, but it is the single largest fixed cost in the Swift job and is worth
revisiting alongside the toolchain change.

---

## E. Hand-maintained lists that can silently rot

### E1. `webkit_suite_filters` — **rot here silently disables tests**

**VERIFIED** — `swift-test-helpers.sh:385-423` is a literal 37-line heredoc of
suite paths. The three lanes interact like this (**VERIFIED**):
- fast lane: `--skip WebKitSerializedTests` (`:344`)
- large lane: `--skip WebKitSerializedTests` (`:364`, `:371`, `:379`)
- WebKit lane: runs **only** the enumerated filters (`:429-435`)

Therefore a new suite added under `WebKitSerializedTests` but not added to this
heredoc **runs in no lane at all** — it is skipped by fast and large and not
enumerated by WebKit. It will be silently, permanently unexecuted, and CI stays
green. Nothing verifies the heredoc against the source tree.
Correction: derive the list from the bundle (or add a test that enumerates
`WebKitSerializedTests` suites in `Tests/` and asserts set equality with the
heredoc).

Note the same heredoc is load-bearing elsewhere: `webkit_leaf_suite_filters`
(`:425-427`) feeds the exclusion patterns of both
`large_process_global_suite_filters` (`:56-57`) and
`aggregate_serial_non_webkit_suite_filters` (`:156-157`).

### E2. `aggregate_serial_non_webkit_suite_filters` — **half-discovered, half-hardcoded**

**VERIFIED** — `swift-test-helpers.sh:152-198`. Discovery is a perl regex over
`Tests/AgentStudioTests/**.swift` for `@MainActor` + `@Suite(… .serialized …)` in
either annotation order (`:159-161`, feeding `serialized_main_actor_suite_matches`
at `:129-139`). Appended to it are **10 hand-written `printf` entries**
(`:162-188`) for suites that do *not* carry both annotations.

Rot modes, both real:
1. A suite needing isolation that has neither both annotations nor a `printf`
   entry falls into the concurrent fast inventory and corrupts process-global
   state for its neighbours. This is a *flake generator*, not a skip.
2. The regex is brittle by construction — `CIFastLaneWorkflowTests.swift:695-742`
   exists precisely to pin its boundary behaviour, and line 722 shows a real
   near-miss it must reject (`.serializedIfSupported`).

**Partial verification exists** (a genuine strength, **VERIFIED**):
`CIFastLaneWorkflowTests.swift:559-583` asserts 21 named suites *are* discovered,
and `:594-597` asserts the discovered set is disjoint from the WebKit leaf set.
But this is a spot-check allowlist, not a completeness check — it proves the
named 21 did not fall out; it cannot notice a 22nd that was never added.

Note `AGENTS.md:66-68` **VERIFIED** already instructs agents on the annotation
convention (`Annotate MainActor global suites with both @MainActor and
@Suite(..., .serialized) so aggregate_serial_non_webkit_suite_filters discovers
them`) — the convention is documented; only completeness is unverified.

### E3. Other hand-maintained pattern lists

| List | File:line | Verified by anything? |
| --- | --- | --- |
| `large_non_webkit_filter_pattern` (19 substrings incl. bare `Script`, `Smoke`, `Integration`) | `swift-test-helpers.sh:17-38` | Only `#expect(testHelperScript.contains("SourceScan"))` at `CIFastLaneWorkflowTests.swift:335` — a single-token spot check |
| `large_serial_non_webkit_filter_pattern` (5 suites) | `:40-50` | Spot-checked at `CIFastLaneWorkflowTests.swift:394-397, 340` |
| `large_process_global_suite_filters` (9 hardcoded `printf` + discovery) | `:52-100` | 24 names spot-checked at `CIFastLaneWorkflowTests.swift:663-690` |
| `fast_serial_process_filter_pattern` (1 suite) | `:204-206` | `CIFastLaneWorkflowTests.swift:416` |
| `ArchitectureAllowlists.stateActorGrandfatheredPathFragments` (3 Feature paths) | `Paths/ArchitectureAllowlists.swift` | No expiry, no owner, no test that it shrinks |
| `ArchitectureAllowlists.repoCacheAllowedPathSuffixes` (7 paths) | same file | Same |

**Substring-matching hazard (VERIFIED):** because `large_non_webkit_filter_pattern`
contains the bare tokens `Script`, `Smoke`, and `Integration`, *any* newly named
suite containing those substrings is silently reclassified into the large lane —
a lane that, per C4, runs with different env in two workflows. Suite naming
therefore has invisible scheduling consequences.

### E4. The architecture-lint rule inventory **is** verified (the good example)

**VERIFIED** — `Tools/…/Tests/…/RuleInventoryTests.swift:8-15` compares
`ArchitectureRuleRegistry.rules` (id + severity) against an explicit
`ExpectedRuleInventory`, and `RuleParityTests.swift:33+` asserts the Bad fixture
corpus exercises **every** registered rule. This is the pattern the suite-filter
lists should copy. Current registered rules (**VERIFIED**, 30 ids across 22 files):

`agentstudio_import_direction`, `agentstudio_drawer_toolbar_owned_controls`,
`agentstudio_retired_worktrunk_cli`, `agentstudio_product_atom_boundary`,
`agentstudio_canonical_atom_mutation`, `agentstudio_shared_components_are_stateless`,
`agentstudio_atomlib_is_generic`, `agentstudio_derived_atom_declared_inputs`,
`agentstudio_repo_cache_keyed_reads`, `agentstudio_hot_pane_snapshot_reads`,
`agentstudio_worktree_enrichment_comparator`, `agentstudio_state_actor_path`,
`agentstudio_ipc_programmatic_control_boundary`, `agentstudio_appipc_port_boundary`,
`agentstudio_ipc_composition_location`, `agentstudio_features_do_not_import_appipc`,
`agentstudio_ipc_public_surface_sanitization`, `agentstudio_ipc_no_direct_atom_access`,
`agentstudio_no_forbidden_architecture_marker`, `agentstudio_toolbar_tooltip_source`,
`agentstudio_eventbus_subscriber_policy_required`,
`agentstudio_terminal_local_disposition_publication`,
`agentstudio_comparison_target_query_control_production`,
**`agentstudio_no_task_sleep_in_tests`** (error),
**`agentstudio_no_generic_clock_sleep`** (error),
`agentstudio_test_core_atom_fallback_ownership`,
`agentstudio_performance_constants_in_app_policies` (report),
**`agentstudio_nonisolated_async_blocking_io_requires_concurrent`** (report),
`agentstudio_observation_capture_keyed_reads` (report),
`agentstudio_mainactor_unbounded_collection_work` (report).

A new "no polling waits in Tests" rule sits naturally beside the two bolded sleep
rules, and must be added to `ExpectedRuleInventory` plus a Good/Bad fixture pair
(`Tools/…/Tests/…/Fixtures/{Good,Bad}/Tests/AgentStudioTests/*TaskSleepTest.swift`
is the existing template, **VERIFIED** present).

`docs/architecture/structure/architecture_lint_inventory.md` mentions
`agentstudio_` 49 times (**VERIFIED** count) against 30 registered rules —
**UNVERIFIED** whether the surplus is prose repetition or documented-but-absent
rules. Worth one targeted check.

---

## F. Dead or misleading tooling

### F1. `AGENTS.md:77` points at `.claude/hooks/check.sh`; `.claude/` does not exist
**VERIFIED** — see C5. Dead reference in the most-read instruction file.

### F2. `--num-workers` is inert for this repo
**VERIFIED** — `grep -rn "import XCTest" Tests/ Sources/` returns **nothing**;
`AGENTS.md:76` states `Swift 6 Testing only … No XCTest`. SwiftPM's
`--num-workers` governs XCTest parallel workers.
**VERIFIED-SIBLING** (`lane-swift-runner-starvation.md:99, 381-384`): the large
lane with `--parallel --num-workers 4` was observed to produce **one** process.
**UNVERIFIED by me**: SwiftPM's documented semantics for the flag.
Correction: delete the `SWIFT_TEST_NUM_WORKERS` plumbing
(`swift-test-helpers.sh:353-355`, `ci.yml:399`, `run-swift-test-task.sh:103`) and
the three assertions that pin it (`CIFastLaneWorkflowTests.swift:357, 431, 436`).

### F3. `SWIFT_TEST_PARALLEL` is documented as a global switch but the fast lane ignores it
**VERIFIED** — `docs/guides/agent_resources.md:169`:
`| SWIFT_TEST_PARALLEL | 1 (enabled) | Set to 0 to disable parallel workers |`
Read only at `swift-test-helpers.sh:317` (`run_non_serialized_swift_tests`, itself
near-dead — F4) and `:352` (`run_large_non_webkit_swift_tests`).
`run_fast_non_webkit_swift_tests` (`:336-349`) never consults it. So
`SWIFT_TEST_PARALLEL=0` does not change the fast lane at all — which is the lane
that actually needs a width control.

### F4. `run_non_serialized_swift_tests` is reachable only from the coverage task
**VERIFIED** — defined `swift-test-helpers.sh:314-334`; sole caller is
`.mise.toml:403` (`test:swift:coverage`). It is the **only** place that runs
`--parallel` over the *whole* non-serialized inventory (`:322`) — precisely the
shape the comment at `:337-339` says deadlocks. Coverage also runs it with the
un-overridden `TIMEOUT_SECONDS=60` (`.mise.toml:393`). `CIFastLaneWorkflowTests.swift:439`
asserts the aggregate lane does **not** call it, confirming it was deliberately
retired from the main path but left live in coverage.
Correction: either route coverage through `run_fast_non_webkit_swift_tests` +
`run_large_non_webkit_swift_tests`, or delete the coverage task.

### F5. Env vars that exist only as tombstone assertions
**VERIFIED** — these names appear **nowhere** in any script, task, or workflow;
only inside negative `#expect(!…contains…)` assertions:

| Name | Only occurrences |
| --- | --- |
| `SWIFT_TEST_WORKERS` | `CIFastLaneWorkflowTests.swift:312, 321, 369, 370`; `ObservabilityLaunchScriptsTests.swift:149` |
| `SWIFT_TEST_SHARD_BY_CLASS` | `CIFastLaneWorkflowTests.swift:366` |
| `SWIFT_TEST_SHARD_CLASS_COUNT` | `CIFastLaneWorkflowTests.swift:367` |
| `SWIFT_TEST_RUNNER_WARMUP_TIMEOUT_SECONDS` | `CIFastLaneWorkflowTests.swift:371` |
| `SWIFT_TEST_INCLUDE_ZMX_E2E` | `CIFastLaneWorkflowTests.swift:786, 788` |

Harmless individually; collectively they are ~10 assertions guarding against the
return of designs nobody is proposing, in a file that is already the repo's most
change-hostile (A2, G1).

### F6. `CIFastLaneWorkflowTests.swift:546` hard-codes a build path CI never uses
**VERIFIED** — `"LOG_PREFIX=test TIMEOUT_SECONDS=60 PREBUILD_TIMEOUT_SECONDS=60 BUILD_PATH=.build-agent-1 "`.
CI uses `SWIFT_BUILD_DIR: .build-ci` (`ci.yml:19,141,261`). The value is inert
here because `aggregate_serial_non_webkit_suite_filters` does not read
`BUILD_PATH` — but it is a misleading literal that will mislead the next reader.

### F7. Docs list an env-var table that omits most of the real knobs
**VERIFIED** — `docs/guides/agent_resources.md:166-169` documents exactly two
variables (`SWIFT_BUILD_DIR`, `SWIFT_TEST_PARALLEL`). Actually-consumed and
undocumented: `SWIFT_TEST_TIMEOUT_SECONDS`, `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS`,
`SWIFT_TEST_SKIP_PREBUILD`, `SWIFT_TEST_INCLUDE_E2E`, `SWIFT_TEST_NUM_WORKERS`,
`SWIFT_TEST_TRACE_BACKEND`, `_XCB_BYPASS`, `XCB_EXTRA_ARGS`,
`AGENT_STUDIO_BENCHMARK_MODE`.

---

## G. Other risks to CI reliability

### G1. `CIFastLaneWorkflowTests` is a ~200-assertion string mirror of the CI topology
**VERIFIED** — `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift`, 903
lines, asserting exact whitespace-sensitive substrings of `.mise.toml`,
`ci.yml`, `benchmarks.yml`, `release.yml`, `run-swift-test-task.sh`,
`swift-test-helpers.sh`, `xcb-helpers.sh`, `filter-known-linker-warnings.sh`.
Examples of the coupling tightness:
- `:99` `"      - parallel:\n          - name: Copy XCFramework"` — exact indentation
- `:618` a single `#expect` containing the **entire** fast-lane `--skip` regex verbatim
- `:51` `"  code-quality:\n    name: Code quality"` — job ordering in YAML text

Any correction in this report that touches those files breaks this suite. That is
not a reason to avoid the corrections; it is a reason to **plan the test change
into the same commit**, and a reason to replace the most brittle assertions with
behavioural ones. This file is the single largest tax on fixing CI.

### G2. This same suite shells out to bash inside the concurrent fast lane
**VERIFIED** — `runBash` (`:866-887`) spawns `/bin/bash` and blocks on
`process.waitUntilExit()` (`:882`). It is invoked from test bodies at `:468, 471,
478, 483, 491, 502, 516, 545, 549, 634, 844`. Two of those
(`aggregate_serial_non_webkit_suite_filters`, `large_process_global_suite_filters`)
run `find Tests/AgentStudioTests -type f -name '*.swift' -exec /usr/bin/perl …`
over the whole test tree (`swift-test-helpers.sh:134-138`).

The suite name `CIFastLaneWorkflowTests` matches none of the
`large_non_webkit_filter_pattern` tokens (**VERIFIED** by inspection of the
19-token list), so it runs in the **fast** lane — i.e. these full-tree perl scans
and blocking `waitUntilExit` calls execute while ~4,900 other tests are in
flight. This is both a load contributor and an instance of finding (3).

### G3. Hard-coded Vitest browser ports
**VERIFIED** — `vitest.browser.config.ts:22` (`port: 63325`) and `:100`
(`port: 63326`). No `strictPort`-style guard, no per-run allocation. Two CI runs
or two local agents on one machine collide. Contrast `vitest.e2e.config.ts`'s
fixture, which allocates a port dynamically (`--strictPort` with a computed
`port`, `bridge-viewer-vite-product-fixture.ts:446`).

### G4. Playwright `channel: 'chrome'` depends on a runner-provided browser
**VERIFIED** — `vitest.browser.config.ts:16`: `launchOptions: { channel: 'chrome' }`.
This uses the machine's installed Google Chrome rather than Playwright's pinned
chromium, so a runner-image Chrome auto-update changes browser behaviour under
CI with no repo-side change. **UNVERIFIED**: whether any observed flake traces to
a Chrome version bump.

### G5. `benchmarks.yml` cancels nothing and runs the large lane on every push to main
**VERIFIED** — `:15-17` `cancel-in-progress: false`, `:5-6` `push: branches: [main]`,
`:9-10` nightly cron. Every main push queues a full benchmark job (including the
duplicated large lane, C4) that cannot be superseded, on the same macOS runner
pool the PR jobs need. During a merge-heavy day this is a self-inflicted
runner-contention source that directly feeds the load-dependent timeouts in D.4.

### G6. `set -e` + backgrounded suites: partial-failure surface in the aggregate runner
**VERIFIED** — `swift-test-helpers.sh:235-257`. Suites launch with `&` into
batches of 4; `wait_for_process_global_suite_batch` (`:303-312`) collects
statuses and returns 1 if any failed. The final partial batch (`:255-257`) is
waited **without** `|| return $?`, so its status becomes the function's return
value by fallthrough — correct under `set -e`, but only by accident of being the
last statement. A future line appended after it would silently swallow the
failure of the final batch. Worth hardening while the file is open.

### G7. The `- parallel:` step syntax is real, and I confirm it is not the bug
**VERIFIED-SIBLING** — `lane-swift-runner-starvation.md:83-86` records that the
runner emits a `Parallel group` pseudo-step and that *every* parallel group
closes (`Finished waiting for background step(s).`), with timestamps at `:75-77`.
I flag it only so a future reader does not chase it: the unusual syntax at
`ci.yml:180, 212, 227, 309, 344, 361` is functioning.

### G8. Instruction files are silent on the one thing that would have caught this
No file in the repo tells an agent how to *measure* whether a test lane is
healthy — there is no "if a lane's wall time changes by more than X, investigate"
rule, and no recorded baseline for lane durations. **VERIFIED**: `AGENTS.md`'s
Proof section (`:341-353`) and Definition of Done (`:391-398`) require pass/fail
counts and exit codes, never durations. Correction: the standard should require
lane duration to be reported alongside pass/fail, so regressions like a 19 m 32 s
prebuild are visible at review time rather than after two weeks of flakes.

---

## Top 15 corrections, ordered by expected impact on CI reliability

1. **Drop the Xcode 26.3 pin from all three workflows** so Swift Testing's
   parallelism cap applies — `ci.yml:27-30, 150-153, 271-274`;
   `benchmarks.yml:32-35`; `release.yml:29-32`.
2. **Change `CIFastLaneWorkflowTests` in the same commit**, since it hard-asserts
   the pin and will otherwise fail the very run that fixes CI —
   `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:37, 42`.
3. **Add an explicit in-process parallelism width for the fast lane** instead of
   delegating unbounded concurrency to the toolchain —
   `scripts/swift-test-helpers.sh:340-345`, rule text at `AGENTS.md:62-64`.
4. **Add `timeout-minutes` and a `concurrency` group with `cancel-in-progress` to
   `ci.yml`**, which today has neither, so wedged and superseded runs stop
   consuming the runner pool — `.github/workflows/ci.yml:14-17`.
5. **Add a `.error`-severity architecture-lint rule banning `Task.yield()` loops
   and repeated-read polling in `/Tests/`**, beside the existing sleep ban that
   created them — `Tools/…/Rules/TestTaskSleepRule.swift:4-7`.
6. **Extend `No Wall-Clock Tests` to name turn-count/yield waits and dual
   turn+time budgets as prohibited**, since it currently forbids only
   `Task.sleep` — `AGENTS.md:376-382`.
7. **Hoist the Vite dependency-optimizer cache out of the per-fixture `mkdtemp`
   data root** so E2E stops paying a cold prebundle 12+ times serially —
   `BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts:159, 454`.
8. **Delete `retry: 1` once (7) lands**, because the retry recreates the cold
   fixture and cannot help — `BridgeWeb/vitest.e2e.config.ts:17`.
9. **Raise `agentstudio_nonisolated_async_blocking_io_requires_concurrent` from
   `.report` to `.error`** (updating `RuleParityTests:30` and
   `RuleInventoryTests` with it) so the ~56 blocking calls fail the build —
   `Tools/…/Rules/NonisolatedAsyncBlockingIORule.swift:6`.
10. **Generate or test-verify `webkit_suite_filters` against the source tree**,
    because a WebKit suite missing from it runs in *no* lane and CI stays green —
    `scripts/swift-test-helpers.sh:385-423`.
11. **Add a completeness check for `aggregate_serial_non_webkit_suite_filters`**,
    whose 10 hand-written entries plus regex discovery can silently drop a
    process-global suite into the concurrent inventory —
    `scripts/swift-test-helpers.sh:152-198`.
12. **Delete the inert `SWIFT_TEST_NUM_WORKERS` / `--num-workers` plumbing** that
    contradicts `AGENTS.md:72-74` and provably yields one process —
    `scripts/swift-test-helpers.sh:353-355`, `.github/workflows/ci.yml:399`.
13. **Reconcile the PR gate with CI**: `E2ESerializedTests` runs locally via
    `SWIFT_TEST_INCLUDE_E2E=1` and never runs in CI, while AGENTS.md advertises it
    as gated — `.mise.toml:329` vs `.github/workflows/ci.yml:382-410`.
14. **Fix the two dead/wrong agent instructions that misdirect every session**:
    the nonexistent `.claude/hooks/check.sh` and the "tests complete in ~15s, use
    a 60s timeout" guidance — `AGENTS.md:77`,
    `docs/guides/agent_resources.md:181`.
15. **Delete the obsolete zig-0.15.2/Xcode-26.3 workaround notes and update the
    doctor baseline**, whose own stated removal condition (zig 0.16) is met —
    `README.md:124`, `docs/guides/agent_resources.md:30, 139`,
    `scripts/doctor-mac.sh:61-62`, `.github/workflows/ci.yml:46`.
