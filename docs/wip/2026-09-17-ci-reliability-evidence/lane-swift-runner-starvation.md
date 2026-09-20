# Swift lane runner starvation / oversubscription — evidence lane

Date: 2026-09-17 · Read-only investigation · No edits, builds, or test runs performed.

Evidence base:

- `.github/workflows/ci.yml`, `.mise.toml`, `scripts/run-swift-test-task.sh`,
  `scripts/swift-test-helpers.sh`, `scripts/swift-build-slot.sh`, `scripts/xcb-helpers.sh`
- `scratchpad/pr350-attempt2-large.log` (Swift test suite / **Test large lane**, 2026-09-17 11:12–11:18)
- `scratchpad/pr350-attempt1-swift.log` (Swift test suite, full job, 2026-09-15 11:37–12:02)
- 33 failed-step logs under `scratchpad/flake-inventory/real/`

Every claim below is tagged **VERIFIED** (with the evidence that establishes it) or
**UNVERIFIED**.

---

## Verdict up front

**The hypothesis is SUPPORTED, with one correction to its mechanism.**

- **SUPPORTED:** the Swift test processes are massively oversubscribed. In the fast lane,
  4,936 tests are co-resident in a single process on a **3-vCPU / 7 GB** runner, and the
  sum of reported per-test durations exceeds the machine's entire CPU budget for the run
  by **488×**. Any wall-clock- or yield-budget-bounded wait executed inside such a test is
  competing with thousands of peers for three cores. Wait budgets calibrated on a
  developer Mac cannot mean the same thing there.
- **CORRECTION:** the *log timestamps* do **not** show a stall. The "all started at
  11:15:27, all finished at 11:15:42, but passed after 154 seconds" pattern in the large
  lane is an **output-buffering artifact**, not a process-wide freeze. The Swift test
  process ran 11:12:53 → 11:15:42 with its stdout fully buffered behind a pipe; GitHub
  timestamped the whole flush at exit. The real anomaly is not *when* the lines appeared —
  it is that 314 tests each report ~154 s of residency inside a 169 s run.
- **NOT SUPPORTED:** the lane watchdog is not the thing expiring. **Zero** of the 35
  inspected logs contain `no output progress` — the 600 s inactivity watchdog never fired.
  Everything that failed failed as an *in-test* assertion, several of them bounded waits.

---

## 1. How the Swift lanes are actually executed in CI

### 1.1 Runner

| Fact | Value | Source |
| --- | --- | --- |
| Label | `macos-26` | `.github/workflows/ci.yml:259` |
| Image | `macos-26-arm64`, version 20260907.0351.1 | `pr350-attempt1-swift.log`, *Set up job*, `Runner Image / Image: macos-26-arm64` |
| OS | macOS 26.6.2 (25G83) | same block |
| Host | Hosted Compute Agent, Azure `westus` | same block |
| **CPU** | **3 vCPU (M1)** | **UNVERIFIED from logs** — no log records `hw.ncpu`. GitHub docs, *GitHub-hosted runners reference*: `macos-latest / macos-14 / macos-15 / macos-26` arm64 = 3 (M1) CPU, 7 GB RAM, 14 GB SSD, identical for public and private repositories. |
| **RAM** | **7 GB** | same doc reference; **UNVERIFIED from logs** |

The arithmetic below is expressed against 3 cores. It does not depend on that number
being exactly right: the smallest GitHub macOS runner is 3 cores and the largest is 12,
and the ratios stay in the 80×–500× range either way.

### 1.2 Jobs — concurrency across runners

`ci.yml` declares five independent jobs, each `runs-on: macos-26`, with **no `needs:`
edges between them**: `code-quality` (:15), `marketing-site-validation` (:63),
`bridge-web-validation` (:98), `bridge-web-swift-backend` (:137), `swift-test-suite`
(:257). **VERIFIED**: each job gets its own fresh runner VM, so no cross-job CPU
contention exists. The comment at `ci.yml:128-130` ("They already run concurrently with
the code-quality and Swift test jobs") refers to concurrent *jobs on separate runners*,
not shared CPU.

### 1.3 `swift-test-suite` — steps are strictly sequential

**VERIFIED** from `pr350-attempt1-swift.log` step timeline (first/last timestamp per step):

```
11:37:34  Set up job
11:37:52  Checkout / Select Xcode 26.3
11:38:07  Get submodule SHAs · Install lint tools
11:38:08→11:38:35  [Parallel group] pnpm install + 3 cache restores
11:38:35→11:38:55  [Parallel group] BridgeWeb packaged build + ghostty/zmx (cache hit)
11:38:56→11:39:05  [Parallel group] Copy XCFramework + Setup dev resources
11:39:05→11:58:37  Prebuild Swift test bundles          (19m 32s)
11:58:41→12:02:42  Test fast lane                        (4m 01s, failed)
          (large / WebKit lanes never reached in this run)
```

The `- parallel:` blocks (`ci.yml:180`, `:212`, `:227`, `:309`, `:344`, `:361`) are real —
the runner emits a `Parallel group` pseudo-step that waits for the background steps and
reports each one's status (`Waiting for background step(s) to complete: …` /
`Finished waiting for background step(s).`). **VERIFIED**: every parallel group *closes*
before `Prebuild Swift test bundles` starts. **Answer to Q5: no overlap. The prebuild and
the test lanes are strictly sequential within the job, and no other job shares the runner.**

### 1.4 Per-lane process topology

Derived from `scripts/run-swift-test-task.sh` and `scripts/swift-test-helpers.sh`.

| Lane | Phase | Processes | In-process test concurrency | Source |
| --- | --- | --- | --- | --- |
| **fast** | native-concurrent | **1** `swift test --skip-build` with a large `--skip` regex, **no `--parallel`** | Swift Testing default = unbounded | `swift-test-helpers.sh:336-345` |
| fast | isolated process-global | N `swiftpm-testing-helper` procs, **4 concurrent**, hard-coded | 1 suite each | `swift-test-helpers.sh:225-258` (`local process_global_concurrency=4`, `:226`) |
| fast | serial fast process | 1 `swift test --filter SQLiteDatabaseFactoryProcessTests` | — | `:204-215`, `:348` |
| **large** | parallel large | **1** `swift test --parallel --num-workers 4` | unbounded (see below) | `:352-364`; `--num-workers` from `ci.yml:399` |
| large | serial large process | 1 `swift test --filter <large_serial pattern>` | unbounded within that filter | `:366-371` |
| large | large process-global | 1 `swiftpm-testing-helper` per suite, **strictly serial** | 1 suite each | `:260-279`, `:382` |
| **WebKit** | — | **1 process per filter, strictly serial**, 34 filters, up to **3 attempts** each with 1s/2s backoff | per filter | `:385-435`, `:664-710` |

**`--num-workers 4` does nothing for Swift Testing here. VERIFIED** by the large-lane log:
the step env prints `SWIFT_TEST_NUM_WORKERS: 4`
(`pr350-attempt2-large.log`, 11:12:17.6042600Z) and the run still reports one
`✔ Test run with 314 tests in 57 suites passed after 169.547 seconds`
(11:15:42.7351050Z) — a single process, a single test run. This matches the repo's own
rule in `CLAUDE.md`: *"Do not use SwiftPM `--parallel` or `--num-workers` as a substitute
for process isolation: Xcode 26.3 still runs Swift Testing through one helper process."*
`swift test --help` documents `--num-workers` as "Number of tests to execute in parallel",
which is true for XCTest and misleading for Swift Testing.

### 1.5 Every timeout / watchdog value, with source

| Value | Meaning | Source |
| --- | --- | --- |
| `SWIFT_TEST_TIMEOUT_SECONDS: 600` | inactivity watchdog for each lane phase | `ci.yml:391` (fast), `:398` (large), `:408` (WebKit) |
| `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: 1200` | inactivity watchdog for prebuild | `ci.yml:385` |
| default `TIMEOUT_SECONDS=60` | local default when env unset | `run-swift-test-task.sh:20` |
| default `PREBUILD_TIMEOUT_SECONDS=90` | local default when env unset | `run-swift-test-task.sh:21` |
| watchdog poll = `sleep 1`, heartbeat = 20 s | watchdog loop | `swift-test-helpers.sh:488`, `:512` |
| **watchdog semantics: "no growth of the tee'd output file for N seconds"**, not total runtime | `swift_test_watchdog_state` / `swift_test_watchdog_timeout_status` | `swift-test-helpers.sh:437-460`, `:487-518` |
| WebKit retry: `max_attempts=3`, backoff 1s→2s, only on `unexpected signal code` | crash retry | `swift-test-helpers.sh:666-706` |
| TERM then 2 s then KILL on timeout | teardown | `swift-test-helpers.sh:520-531` |

**Important property of the watchdog: it measures output *bytes*, not test progress.**
Because the Swift Testing process writes an event line per test start, a process that is
starving but still emitting start events keeps the watchdog happy indefinitely. That is
why no lane ever hit 600 s even while tests were taking 154 s each.

---

## 2. Tests whose reported duration is wildly larger than their work

### 2.1 The timestamp discrepancy the brief asked about — resolved

Large lane (`pr350-attempt2-large.log`):

```
11:12:21.648  [test-large] >>> parallel large non-WebKit suites (inactivity-timeout=600s)
11:12:41      ... 20s elapsed, 20s without output
11:13:01      ... 40s elapsed,  8s without output     <-- last output growth ≈ 11:12:53
11:13:21 … 11:15:01   ... 28/48/68/88/108/128s without output
11:15:21      ... 180s elapsed, 0s without output     <-- output file grows again
11:15:26.968  [0/1] Planning build
11:15:26.978  ◇ Test run started.
11:15:27.011 … 11:15:27.42   ALL 291 "◇ Test … started" lines
11:15:42.683 … 11:15:42.735  ALL "✔ … passed after 152–169 seconds" lines
11:15:42.735  ✔ Test run with 314 tests in 57 suites passed after 169.547 seconds
```

Reconstruct the real clock from the in-process total: `11:15:42.735 − 169.547 s =
11:12:53.19`. That is exactly the moment the watchdog last saw the output file grow
before the 148-second silence. **VERIFIED: the test process started at ~11:12:53, ran for
169.5 s, and its stdout was fully buffered and flushed at exit.**

The pipeline is `( "$@" 2>&1 | tee "$output_file" | $xcb_pipe ) &`
(`swift-test-helpers.sh:484`). With `_XCB_BYPASS: 1` (`ci.yml:400`) the tail is
`bash scripts/filter-known-linker-warnings.sh` (`xcb-helpers.sh:15-18`). stdout is a pipe,
so libc block-buffers; the 169 s of events fit under the buffer high-water mark and land
in one flush.

Independent confirmation of buffering in the same file: the *second* process in the lane
(`WorkspaceCacheCoordinatorIntegrationTests`, isolated) prints every one of its
start/end lines between `11:18:11.0486` and `11:18:11.0510` — 2.4 ms of log timestamps —
while reporting `✘ Test run with 16 tests in 1 suite failed after 6.051 seconds` and one
inner test at `5.994 seconds`. Six seconds of work, 2 ms of timestamps. **VERIFIED.**

**So: GitHub log timestamps inside a burst are flush times and carry no timing
information. The in-process `passed after N seconds` values are the reliable signal.**

By contrast the fast-lane process *does* stream (4,936 tests overflow the buffer
repeatedly) — you can see it interleave with the watchdog heartbeat mid-line at
`pr350-attempt1-swift.log` 11:59:41.806 and 12:00:21.554. So streaming vs. burst is a
volume artifact, not a health signal.

### 2.2 The real anomaly: residency vastly exceeds the machine's CPU budget

| Lane / process | Tests | Run wall | Σ per-test durations | Mean | Tests > 20 s | CPU available (3 vCPU × wall) | Σ ÷ CPU-budget |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fast, native-concurrent | 4,936 | 125.398 s | **183,565 s** | 37.19 s | **3,908** | 376 core-s | **488×** |
| large, parallel | 314 | 169.547 s | **40,893 s** | 130.23 s | **265** | 509 core-s | **80×** |

**VERIFIED** — computed from every `✔/✘ Test … passed/failed after N seconds` line in each
process's section of the two logs; totals cross-check against the emitted
`Test run with 4937 tests in 732 suites passed after 125.398 seconds`
(`pr350-attempt1-swift.log` 12:01:32.393) and
`Test run with 314 tests in 57 suites passed after 169.547 seconds`
(`pr350-attempt2-large.log` 11:15:42.735).

Fast-lane duration histogram (**VERIFIED**): `≥60 s: 2` · `20–60 s: 3,907` ·
`5–20 s: 1` · `1–5 s: 3` · `<1 s: 1,301`. The distribution is bimodal — either a test
is sub-second, or it is pinned at roughly the length of the whole run. There is
essentially nothing in between. That is the signature of "everything is resident for the
whole run", not "some tests are slow".

A 488× ratio is not explicable by slow tests. It is only explicable by **co-residency**:
thousands of test tasks alive simultaneously, each accruing wall time while getting a
vanishing slice of three cores.

### 2.3 Concurrency in flight, measured directly

In the large lane, **291 `◇ Test … started` events are emitted before the first
`✔ Test … passed`** (event #292 of the test-event stream). **VERIFIED** by ordinal
position in `pr350-attempt2-large.log`. So at least 291 of 314 tests were simultaneously
in flight, on 3 cores, before a single one completed.

### 2.4 Top 30 by reported duration (both lanes, this pair of runs)

| # | Duration | Lane | Test |
| --- | --- | --- | --- |
| 1 | 169.5 s | large | `scriptMessageRPCPlane_isCompileDeadExceptOneShotPageLoadBootstrap()` |
| 2 | 158.2 s | large | "strict fixture parser accepts exact VictoriaLogs boolean strings" |
| 3 | 157.3 s | large | "project-dev shape converges remote grouping and PR enrichment across sibling checkouts" |
| 4 | 157.2 s | large | "filesystem → git → forge → cache converges for two repos sharing one remote identity" |
| 5 | 157.2 s | large | "real discovery-only client services compatibility scan loop" |
| 6 | 157.2 s | large | "real metadata queue reset reopens File delivery and replays retained work once" |
| 7 | 157.2 s | large | "message-driven repo discovery seeds unresolved enrichment before origin resolves" |
| 8 | 157.1 s | large | "stale repository removal cannot disable a newer remote-reference lifetime" |
| 9 | 157.1 s | large | "message-driven origin and branch events trigger one admitted repository refresh" |
| 10 | 157.0 s | large | "continuity delta contract rejects missing recovery outcomes" |
| 11 | 157.0 s | large | "OPTIONS remains bodyless and claim-free across pane routing states" |
| 12 | 156.5 s | large | "capability rejection precedes body access and closed admission is conflict" |
| 13 | 156.4 s | large | "close before the first control response suppresses every response and settles residue" |
| 14 | 156.4 s | large | "continuity control helper commits a clean baseline and injects one ignored file" |
| 15 | 156.2 s | large | "multi-worktree admission and shared Review construction drain exactly" |
| 16 | 156.0 s | large | "system memory parser reports failed or malformed captures as null and never aborts" |
| 17 | 156.0 s | large | "phase-a verifier rejects unsafe auth and foreground activation state" |
| 18 | 156.0 s | large | "session completion cannot commit after pane admission closes" |
| 19 | 154.4 s | large | `test_makeUserScript_blockedTrue_embedsInitialBlockedTrue()` |
| 20 | 154.4 s | large | `test_makeUserScript_blockedFalse_embedsInitialBlockedFalse()` |
| 21 | 154.4 s | large | `test_makeRuntimeToggleSource_containsStateSetter()` |
| 22 | 154.4 s | large | "origin change updates resolved identity grouping" |
| 23 | 154.4 s | large | **"parsers report failed captures as null, not zero population"** |
| 24 | 154.4 s | large | "parsers read footprint and vmmap fixtures" |
| 25 | 154.4 s | large | "uses the system Python-compatible Victoria timestamp parser" |
| 26 | 154.4 s | large | "rejects title publication beyond one second" |
| 27 | 154.4 s | large | "rejects suppression and drain ratios against admitted equal offers" |
| 28 | 154.4 s | large | "rejects sensitive terminal content in OTLP projection" |
| 29 | 154.4 s | large | "rejects Repo command work during the title-only phase" |
| 30 | 152.8 s | large | "report script summarizes marker scoped TCC identity and access rows" |

Fast-lane top entries (same phenomenon, smaller magnitude): "local architecture tool
exposes expected rule inventory" 78.7 s; then a plateau at 53–57 s covering ~3,900 tests,
e.g. "time budget exhausted still honors the turn floor (MainActor)" 54.9 s and
"issued descriptors are metadata-only and bounded" 54.0 s.

Entries 19–21 are decisive: `test_makeUserScript_blockedTrue_embedsInitialBlockedTrue()`
builds a JavaScript string and asserts a substring. It cannot take 154 s of work. It was
*alive* for 154 s.

**Answer to the "reporting-artifact vs. process-stall" question in the brief: neither.**
Swift Testing timestamps each test case from when its task starts to when its body
returns; those are honest wall-clock intervals. There is no process-wide stall (the
output file was growing at the start and the run completed normally). The tests really
were resident for ~154 s each, because Swift Testing put **all of them in flight at once**
on a 3-core box.

### 2.5 Process-spawn cost is a second, separate tax

Fast-lane isolated phase: 28 suites, run in batches of 4, `12:01:36.7 → 12:02:42.1` =
**65.4 s wall** for **13.45 s** of summed in-process test time. Each batch of four
`swiftpm-testing-helper` launches costs ~7–8 s wall for ≪1 s of tests (e.g. batch started
12:01:36.71–12:01:36.73, results 12:01:44.94–12:01:45.35, reporting 0.042/0.073/0.058/0.491 s).
**VERIFIED.** That is four simultaneous dyld loads of the full `AgentStudioPackageTests`
bundle against 3 cores and a 7 GB memory budget. `process_global_concurrency=4`
(`swift-test-helpers.sh:226`) exceeds the core count.

---

## 3. What can block Swift concurrency cooperative threads

Counts over `Tests/` and `Sources/` (`*.swift`), **VERIFIED** by grep:

| Pattern | Tests | Sources |
| --- | --- | --- |
| `waitUntilExit` | 33 | 2 |
| `DispatchSemaphore` | 23 | 1 |
| `readDataToEndOfFile` | 28 | 3 |
| `RunLoop` | 19 | 10 |
| `NSLock` | 116 | 42 |
| `DispatchGroup` | 0 | 1 |
| `Thread.sleep` | **0** | **0** |
| `usleep` / `sleep(` | **0** | **0** |
| `os_unfair_lock` | **0** | **0** |
| `.sync {` on a queue | **0** | **0** |

Classified `waitUntilExit()` + `DispatchSemaphore(` sites by enclosing function
(56 sites total). **Not one of them is marked `@concurrent`.** Breakdown:

**Sources (2 sites, both synchronous, neither `@concurrent`):**

- `Sources/AgentStudio/Core/Models/SessionConfiguration.swift:189` — `private static func findZmx(…)`, `Process` + `waitUntilExit()` + `readDataToEndOfFile()` to shell out to `/usr/bin/which`. Guarded by an `allowBlockingProbe` flag at the call sites.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTCCDiagnosticRecorder.swift:315,332` — `static func shellChildDirectoryProbe(_:)`, `DispatchSemaphore(value: 0)` + `completion.wait(timeout: .now() + 2)`, then `process.terminate(); process.waitUntilExit()` on timeout. Bounded at 2 s, but blocking for up to 2 s on whatever thread calls it.

**Tests (54 sites; 49 synchronous, 5 inside `async` functions), all `@concurrent`-free.**
The dominant shape is a synchronous `run(_ process:)` helper:

```
try process.run()
process.waitUntilExit()
let out = stdout.fileHandleForReading.readDataToEndOfFile()
```

Representative sites (file:line, enclosing declaration):

| File:line | Enclosing decl | Ctx |
| --- | --- | --- |
| `Tests/AgentStudioTests/TestSupport/FilesystemTestGitRepo.swift:49` | `package static func runGit(at:args:) throws` | SYNC |
| `Tests/AgentStudioTests/Scripts/BridgeHeadlessManifestVerifierScriptTests.swift:238` | `private func run(_ process: Process) throws -> ScriptResult` | SYNC |
| `Tests/AgentStudioTests/Scripts/ObservabilityLaunchScriptTestSupport.swift:153, 229` | `worktreeDebugCode(for:)`, `run(_:)` | SYNC |
| `Tests/AgentStudioTests/Scripts/VendorWorktreeTestSupport.swift:527` | `private static func run(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:882, 896` | `runBash(_:standardInput:)`, `runBashStatus(_:)` | SYNC |
| `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceComparatorScriptTests.swift:604` | `runScript(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift:682` | `runScript(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/StartupPerformanceWorkloadScriptTests.swift:75` | `runScript(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/HomebrewBetaReleaseScriptsTests.swift:192` | `runScript(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/PerformanceReportScriptTests.swift:136` | `runReport(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/ZmxStartupTraceAnalyzerTests.swift:343` | `runAnalyzer(_:)` | SYNC |
| `Tests/AgentStudioTests/Scripts/NotificationOSCSmokeVerifierTests.swift:162` | `runVerifier(_:)` | SYNC |
| `Tests/AgentStudioTests/Scripts/VendorConsumerWiringScriptTests.swift:511` | `runShellScript(…)` | SYNC |
| `Tests/AgentStudioTests/Scripts/ArchitectureSwiftLintRulesTests.swift:132` | `runProcess(arguments:)` | SYNC |
| `Tests/AgentStudioTests/Scripts/BridgeObservabilityVerifierScriptTests.swift:345, 390, 417` | `runTtfiGateSelfTest(…)` and two `@Test func … throws` bodies | SYNC |
| `Tests/AgentStudioTests/App/WorkspaceStrictStartupSubprocessTests.swift:86, 97` | `private static func runAgentStudio(…)` | SYNC |
| `Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:605` | `initializeGitRepository(at:)` | SYNC |
| `Tests/AgentStudioTests/Integration/FilesystemToPrimarySidebarIntegrationTests.swift:346` | `initializeGitRepository(at:)` | SYNC |
| `Tests/AgentStudioTests/Infrastructure/RepoScannerTests.swift:407` | `runGit(at:args:)` | SYNC |
| `Tests/AgentStudioTests/Infrastructure/RepoScannerGitDiscoveryReadOnlyIntegrationTests.swift:203` | `runGit(at:arguments:)` | SYNC |
| `Tests/AgentStudioTests/Infrastructure/SQLite/SQLiteDatabaseFactoryTests.swift:174,179,182` | `createCrashLeftWALDatabase()` | SYNC |
| `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedExactItemRealStreamTestSupport.swift:550` | `run(_ arguments:)` | SYNC |
| `Tests/AgentStudioTests/Core/Stores/ZmxBackendTests.swift:227, 603` | one `@Test func … throws`, one helper | SYNC |
| `Tests/AgentStudioTests/Helpers/ZmxTestHarness.swift:66, 466` | closure / `childProcessIDs(of:)` | SYNC |
| `Tests/AgentStudioTests/App/PaneAgents/PaneAgentLaunchOwnerTests.swift:144` | `waitForProcessExit(…)` | SYNC |
| `Tests/AgentStudioIPCTransportTests/UnixSocketTransportTests.swift:14, 46` | two `@Test func … throws` bodies | SYNC |
| `Tests/AgentStudioTests/Infrastructure/ProcessExecutorTests.swift:396` | `waitForProcessIdentifier(at:) async throws` | **ASYNC** |
| `Tests/AgentStudioTests/Features/Bridge/BridgeProductAdmissionGateTests.swift:110` | `racingCloseLinearizesAfterAdmittedMutation() async throws` | **ASYNC** |
| `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerNativeTablePilotTests.swift:189` | `injectedDeadlineDrainsBeforeReturningFailure() async` | **ASYNC** |
| `Tests/AgentStudioTests/App/Panes/TabBarAdapterMaterializationTestSupport.swift:74` | `func wait() async -> Bool` | **ASYNC** |
| `Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTestSupport.swift:60` | `func wait() async -> Bool` | **ASYNC** |

**The SYNC/ASYNC distinction does not rescue the synchronous ones.** Swift Testing runs
*every* `@Test`, synchronous or not, as a child task in a task group. A `@Test func … throws`
that calls `waitUntilExit()` still executes inside a Task, on a cooperative-pool thread,
and blocks it for the subprocess's whole lifetime. Verified example of the shape: the
entire `BridgeHeadlessManifestVerifierScriptTests` suite (`@Suite("Bridge headless
manifest verifier script") struct`, `:4-5`) declares four `@Test func … throws` bodies,
each routed through `run(_:)` at `:238`.

Per CLAUDE.md's Swift 6.2 rule ("`@concurrent nonisolated` for blocking I/O … **This is a
correctness requirement in 6.2, not a style choice**"), **all 56 sites violate the rule**.
The rule exists precisely because, under SE-0461, a plain `nonisolated async` inherits the
caller's executor — so blocking there blocks that executor.

**No `Thread.sleep`, `usleep`, `sleep(`, `os_unfair_lock`, or queue `.sync {` exists in
either tree.** The repo's "No Wall-Clock Tests" rule is being honoured on that axis.
**VERIFIED.**

### 3.1 Which lane pays for this

`large_non_webkit_filter_pattern()` (`swift-test-helpers.sh:17-38`) selects `Script`,
`SourceScan`, `Smoke`, `Integration`, `ProcessExecutorTests`, the Darwin FSEvent suites,
and `WorkspaceStrictStartupSubprocessTests` — i.e. the large lane is **exactly the
subprocess-spawning inventory**, and it runs all 314 of them in one process with unbounded
concurrency. The `FilesystemTestGitRepo.runGit` helper alone has **159 call sites** across
`Tests/` (**VERIFIED** by grep count).

---

## 4. In-process parallelism and what the core count implies

**VERIFIED:**

- The fast lane passes **no `--parallel` and no `--no-parallel`** (`swift-test-helpers.sh:340-345`),
  so SwiftPM defaults to `--no-parallel` (per `swift test --help`: *"Run the tests in
  parallel. (default: --no-parallel)"*) — meaning **one process**, and Swift Testing's own
  in-process concurrency does all the fan-out. The comment at `:337-339` says this is
  deliberate: "SwiftPM's `--parallel` harness wraps the entire Testing library in one
  helper process on Xcode 26.3 and can deadlock its event stream under the fast
  inventory's volume."
- The large lane passes `--parallel --num-workers 4` and still gets **one** process and
  one test run of 314 tests (§1.4).
- **There is no parallelism-width knob for Swift Testing in this toolchain.** `swift test
  --help` exposes only `-j/--jobs` (build jobs), `--parallel/--no-parallel`, and
  `--num-workers` (XCTest process fan-out). **UNVERIFIED**: whether a newer swift-testing
  release adds a per-run concurrency limit — not checked against upstream.
- The only per-suite brake available is the `.serialized` trait, which
  `aggregate_serial_non_webkit_suite_filters()` (`:152-198`) discovers by regex over
  `@MainActor` + `@Suite(… .serialized …)` and then **removes from the concurrent process**
  entirely, running each in its own helper process, 4 at a time.

**What that implies on a 3-core runner.** The Swift cooperative pool's target width is the
active processor count. Every `.serialized`-free, non-MainActor test is a child task in
one unbounded task group:

```
  3 cores
  ───────────────────────────────────────────────────────────
  cooperative pool  ~3 wide (target)
       ▲
       │  4,936 ready tasks (fast lane)  /  314 (large lane)
       │  ~49 of them will call waitUntilExit() and block a thread
       ▼
  Darwin workqueue brings up replacement threads when a pool
  thread blocks in a syscall  →  thread count climbs far above 3
  →  context-switch and memory pressure on a 7 GB box
```

The measured consequence is already established: 291 tests in flight before the first
completion (§2.3); 488× CPU over-subscription (§2.2). Whether the excess presents as
"thread explosion" or "fair-shared time slicing" is **UNVERIFIED** (no `sample` output
exists — the watchdog's `sample_stuck_swift_test_processes` at `:607-635` only fires on a
timeout, and no timeout ever occurred). Either way the effect on a bounded wait is the
same: **a test asking "did X happen within B?" is asking it while ~3,900 peers share three
cores.**

Concrete example of a budget whose meaning collapses:
`Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift:402`

```swift
private func waitUntil(iterations: Int = 20_000, _ condition: () -> Bool) async -> Bool {
    for _ in 0..<iterations {
        if condition() { return true }
        await Task.yield()
    }
    return false
}
```

`Task.yield()` re-enqueues at the tail of a run queue that holds thousands of ready tasks.
The budget is denominated in *scheduling turns*, and the number of turns needed for a
dependency to make progress scales with the queue depth. This suite is one of the observed
CI failures (`flake-inventory/real/34715932576-103613049989.log`, *Test fast lane*,
`PaneTabViewControllerLaunchRestoreTests.swift:528` `Expectation failed: await wa…`).
Detailed wait-shape analysis belongs to the polling-wait survey lane; flagged here only as
the mechanism link.

---

## 5. Prebuild vs. test-lane overlap

**Answer: no overlap. VERIFIED** — see §1.3. `Prebuild Swift test bundles` occupies
11:39:05 → 11:58:37 and `Test fast lane` starts 11:58:41. All `- parallel:` groups close
at 11:39:05. Jobs are on separate runners (§1.2). The only intra-job concurrency during a
test lane is the lane's own process fan-out.

Worth noting for the cost model even though it is not contention: **the prebuild alone
takes 19m32s** on this runner, which is itself a 3-core symptom.

---

## 6. Conclusion and the single most discriminating measurement

**SUPPORTED** — with the mechanism restated precisely:

1. `macos-26` arm64 = 3 vCPU / 7 GB (docs; not verified in-log).
2. Swift Testing runs the whole non-serialized inventory concurrently in one process, with
   no width control: 4,936 tests (fast) / 314 (large). **VERIFIED.**
3. Summed test residency exceeds the machine's entire CPU budget for the run by 488×
   (fast) and 80× (large). **VERIFIED.**
4. 291 of 314 large-lane tests were in flight before the first completion. **VERIFIED.**
5. 56 blocking `waitUntilExit`/`DispatchSemaphore.wait` sites, none `@concurrent`, sitting
   in the very inventory the large lane runs concurrently. **VERIFIED.**
6. Therefore any bounded wait executed inside a test is being evaluated under ~3 orders of
   magnitude of contention relative to a developer machine. **Supported inference.**

**REFUTED sub-claims:**

- "Ordinary async work is delayed by tens of seconds" — *the symptom is real* (tests
  resident 150 s), but attributing it to a **stall** is wrong. The process is making
  progress the whole time; nothing is frozen. **VERIFIED via the reconstructed clock in §2.1.**
- "Many failures are bounded waits expiring [against the lane watchdog]" — the 600 s
  inactivity watchdog **never fired**: `no output progress` appears in **0 of 35** logs.
  **VERIFIED.** The expiring budgets are all *inside* tests.

**UNDETERMINED:** whether the contention is CPU saturation, thread explosion, or memory
pressure (7 GB with 4 concurrent full-bundle helper processes). No log carries CPU, load,
or memory evidence.

### The one cheap measurement that settles it

Add to each lane a **CPU-utilisation ratio** for the test process, plus the machine shape:

```bash
sysctl -n hw.ncpu hw.memsize hw.perflevel0.logicalcpu hw.perflevel1.logicalcpu
uptime                      # load average immediately before the lane
/usr/bin/time -l <the swift test invocation>   # user + sys CPU seconds, max RSS, page-ins
vm_stat                     # compressor / swap pressure after the lane
```

Then compute `R = (user + sys) / (wall × ncpu)`:

- `R ≈ 0.9–1.0` → the box is **CPU-saturated**. The fix is fewer concurrent tests /
  more cores. Oversubscription confirmed as the mechanism.
- `R ≪ 0.5` with high `wall` → the process is **blocked**, not computing: semaphores,
  subprocess waits, or paging. Look at `max RSS` and `vm_stat` page-ins next.
- High `sys` fraction (`sys/user > 0.5`) → **thread explosion / context-switch churn**,
  the workqueue-overcommit hypothesis.

One `/usr/bin/time -l` wrapper per lane and one `sysctl`/`uptime` line is a few seconds of
CI time and produces the exact number that discriminates all three. It is strictly better
than adding per-test event timestamps, because the per-test durations are *already*
published and already tell us residency — what is missing is whether that residency is
CPU-bound.

Second-cheapest addition, if more is wanted: `print_timeout_process_diagnostics`
(`swift-test-helpers.sh:558-566`) already knows how to `/usr/bin/sample` the test process.
Firing that on a **heartbeat** (every 60 s) instead of only on timeout would capture the
thread count and stack distribution during the plateau, at the cost of ~1 s of CPU per
sample.

---

## 7. Candidate structural remedies

No wall-clock budget increases, no retries. Each is stated with the evidence it addresses,
the cost, and what it does not fix. **Nothing below has been implemented.**

### R1 — Move blocking subprocess work off the cooperative pool

Wrap every `waitUntilExit()` / `readDataToEndOfFile()` helper so the blocking section runs
on `@concurrent nonisolated` (or an explicit `spawn_blocking`-equivalent), per CLAUDE.md's
Swift 6.2 rule.

- **Addresses:** §3 — 56 blocking sites, 0 `@concurrent`; §1.4/§2.2 — the large lane runs
  exactly the subprocess inventory concurrently.
- **Gain:** cooperative threads stop being consumed by `waitpid`; the pool stops being
  forced to overcommit.
- **Cost:** ~20 shared helpers to change (most sites funnel through `run(_:)` /
  `runScript(…)` / `runGit(…)`); every synchronous caller becomes `async`, which cascades
  into the `@Test func … throws` signatures that call them. Medium, mechanical, wide diff.
- **Does not fix:** the fan-out itself. 4,936 concurrent tests on 3 cores remains 4,936
  concurrent tests. Blocking would move off the pool, but the CPU budget does not grow.
  **This is necessary, not sufficient.**

### R2 — Bound the number of tests in flight per process

Since Swift Testing exposes no width knob (§4), the available mechanism is the one the
repo already built: shard the inventory across processes, as
`run_aggregate_serial_non_webkit_swift_tests` does, and size the shard count to cores.

- **Addresses:** §2.2/§2.3 — 488× over-subscription, 291 in flight before any completion.
- **Gain:** directly bounds residency; makes every in-test wait budget mean roughly what it
  means locally; the bimodal duration distribution collapses toward real work.
- **Cost:** high. 4,936 tests in ~1,000 helper-process launches at ~2 s of dyld each
  (§2.5) would be catastrophic — so this only works as **coarse sharding** (e.g. N shards
  by suite, N ≈ cores), not per-suite isolation. Needs a shard-assignment scheme and a
  merged result summary.
- **Risk:** the fast lane's existing comment (`:337-339`) records that SwiftPM's own
  `--parallel` deadlocks the Testing event stream on Xcode 26.3; any sharding must use the
  `swiftpm-testing-helper` path the repo already drives directly (`:243-245`), not
  `--parallel`.

### R3 — Split the process-spawning suites into their own lane, run with low width

The large lane's filter (`:17-38`) is already a near-perfect selector for "tests that
`fork`/`exec`". Give that subset its own lane with a small, explicit in-flight bound (via
R2's sharding), and leave the pure-logic inventory in a wide lane.

- **Addresses:** §3.1 — the large lane *is* the subprocess inventory; §2.2 — large lane
  mean is 130 s/test vs. 37 s/test in fast.
- **Gain:** the highest-leverage, smallest-blast-radius version of R2. 314 tests is a
  tractable number to shard; 4,936 is not.
- **Cost:** low-to-medium. Mostly `swift-test-helpers.sh` and one `ci.yml` step. The filter
  patterns already exist.
- **Does not fix:** the fast lane's 488× ratio, which is the larger number.

### R4 — Reduce `process_global_concurrency` to match cores

`swift-test-helpers.sh:226` hard-codes `4` concurrent helper processes on a 3-core,
7 GB runner.

- **Addresses:** §2.5 — 65.4 s wall for 13.45 s of tests; ~7.5 s per batch of 4.
- **Gain:** small but free; reduces peak RSS during the isolated phase, which matters at
  7 GB.
- **Cost:** trivial (one constant, ideally derived from `hw.ncpu`).
- **Caveat:** reducing to 3 could *increase* wall time if the cost is dyld I/O rather than
  CPU. **UNVERIFIED which** — R6's measurement settles it. Do not change this blind.

### R5 — A larger runner

`macos-26-large` (Intel, 12 vCPU / 30 GB) or `macos-26-xlarge` (arm64 M2, 5 vCPU / 14 GB).

- **Addresses:** §1.1 — 3 vCPU / 7 GB is the floor of GitHub's macOS fleet; §5 — a 19m32s
  prebuild.
- **Gain:** 12 cores turns the fast lane's 488× into ~122× and the prebuild into minutes.
  Requires no code change at all.
- **Cost:** billed (larger runners are not free even on public repos); `macos-26-large` is
  Intel, which changes the architecture the tests run on — a real risk for a repo with an
  arm64 Ghostty XCFramework and `arm64e-apple-macos14.0` test targets
  (`pr350-attempt2-large.log` 11:15:26.999). `macos-26-xlarge` stays arm64 but only gets
  to 5 cores.
- **Honest framing:** this *reduces* the ratio; it does not make wait budgets principled.
  A 122× oversubscription is still oversubscription. **Treat as mitigation, not a fix.**

### R6 — Instrument the lanes (prerequisite, not a remedy)

Add §6's `sysctl` / `uptime` / `/usr/bin/time -l` / `vm_stat` around each lane, and
optionally the heartbeat `sample`.

- **Addresses:** the UNDETERMINED in §6 — no log carries CPU, load, or memory evidence.
- **Gain:** decides between R1 (blocked threads), R2/R3 (CPU saturation), and R4/R5
  (memory pressure) *before* spending effort on the wrong one.
- **Cost:** seconds of CI time; a few lines in `run_swift_with_timeout`.
- **Recommendation:** do this first. R2 and R3 are expensive, and the measurement is cheap.

### Explicitly rejected

- Raising `SWIFT_TEST_TIMEOUT_SECONDS` — the watchdog never fired (§6); raising it changes
  nothing.
- Raising in-test wait budgets — treats the symptom and re-calibrates a number that has no
  stable meaning under variable contention. The fast-lane run totals across the inventory
  logs vary 100.9 s → 174.7 s for the same test set
  (`flake-inventory/real/34753109765-103712860598.log`: 4,921 tests / 100.935 s;
  `34619261023-103328839051.log`: 4,882 tests / 174.726 s), a 1.73× spread. Any fixed
  budget is being asked to straddle that.
- Retries — hides the signal. The WebKit lane's existing retry
  (`swift-test-helpers.sh:664-710`) is scoped narrowly to `unexpected signal code` and
  should stay that way.

---

## Appendix — failure taxonomy across the 33 inventory logs

**VERIFIED** by grepping each log for `no output progress`, `✘ … recorded an issue`, and
`##[error]`.

| Class | Count | Examples |
| --- | --- | --- |
| Lane watchdog (`no output progress`) | **0** | — |
| Swift in-test assertion, bounded-wait-shaped | ~17 | `BridgeProductRealGitFileAndReviewWebKitTests.swift:158` (×5), `WorkspaceCacheCoordinatorTests.swift:458/459` `didApplyNewestSnapshot` (×3), `GitWorkingDirectoryProjectorVisibleTierTests.swift:273/435` `visibleTierWaitUntil` (×2), `RepoExplorerProjectionObservationDemandTests.swift:199/209/210` (×2), `PaneTabViewControllerLaunchRestoreTests.swift:528` (×1), `BridgePaneControllerRefreshAdmissionIntegrationTests.swift:554` (×1), `DarwinSharedExactItemRealStreamIntegrationTests.swift:106` (×1), `BridgeDevelopmentHostReviewReplayTests.swift:16` `sessionAlreadyOpen` (×2) |
| Swift, environment/deterministic | 3 | `GhosttyEventRoutingCoverageTests.swift:10` — `NSCocoaErrorDomain Code=260 "ghostty.h"` missing (×2); one job exiting `133` (SIGTRAP) |
| BridgeWeb / Playwright timeouts (other lane) | ~10 | `Test timed out in 60000ms`, `page.waitForResponse: Timeout 120000ms`, `Annotation backpressure journey failed … currentElapsedMilliseconds: 142475, currentMilestone: "server.ready"` |
| Indeterminate (cancelled job, no error line) | 2 | `34651876564-103435665063.log`, `34796189300-103829643194.log` |

The BridgeWeb `server.ready` milestone taking 142.5 s, 138.4 s, 135.1 s, 132.5 s and
120.4 s across separate runs is the same shape on the Node side and belongs to the
BridgeWeb lane's own investigation.
