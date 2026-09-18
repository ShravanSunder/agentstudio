# BridgeWeb annotation-backpressure E2E — failure diagnosis

Test: `1,699-item Review keeps root and five replies responsive and durable`
File: `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-backpressure.e2e.test.ts`
Repo root: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.issues-perf-again`
Local HEAD under test: `ec659af36` (branch `fix/panes-sidebar-recent-activity`)
Investigation: read-only. No repo edits, no test runs, no builds, no git state changes.

**Headline:** across 10 observed attempts (2 local + 8 CI) this test failed in **five different
phases**. Eight of the ten are fixed wall-clock budgets being exceeded. The CI logs identify a
concrete, fixable root cause for the largest CI cluster (a cold Vite dependency-optimizer pass
running inside a 120 s product-behaviour budget). The two local failures share **no** phase with
any CI failure and are best explained by machine starvation on the local box.

---

## 1. Exact failing test name, messages, log lines, and phase

### 1.1 Only one of the two local logs ever reached BridgeWeb

`tmp/debug-workflows/2026-09-15-sidebar-regressions/head-ec659-local-test.log` (exit 1, 24 s wall,
receipt `started_at=2026-09-15T12:03:27Z finished_at=2026-09-15T12:03:51Z`) never got past
`mise run lint`:

- `head-ec659-local-test.log:2652-2655`
  ```
  error: 'agentstudioarchitecturelint': Invalid manifest (compiled with: [...swiftc...])
  sandbox-exec: sandbox_apply: Operation not permitted
  error: 'agentstudioarchitecturelint': Invalid manifest (compiled with: [...swiftc...])
  sandbox-exec: sandbox_apply: Operation not permitted
  agentstudio architecture lint: FAIL
  ```
- The approved rerun compiled that same manifest without complaint
  (`head-ec659-local-test-approved.log:2650` `Building for debugging...`,
  `:2773-2775` `Build complete! (1.49s)`).

**Conclusion:** that run's exit 1 is a nested-sandbox denial in lint. It is unrelated to BridgeWeb
and is *not* a second data point on this test.

### 1.2 The approved local run

`head-ec659-local-test-approved.log` (exit 1, 694 s wall, receipt
`started_at=2026-09-15T12:05:07Z finished_at=2026-09-15T12:16:41Z`,
`head_before = head_after = ec659af36cdacc0bd2f83c5bdf155aa66eab957a`).

Summary lines:

- `:4209` `❯ tests/e2e/bridge-viewer-vite-annotation-backpressure.e2e.test.ts (1 test | 1 failed) 198957ms`
- `:4210` `× 1,699-item Review keeps root and five replies responsive and durable 198957ms (retry x1)`
- `:4239-4242` `Test Files 1 failed (1)` / `Tests 1 failed (1)` / `Start at 08:13:13` / `Duration 199.42s`
- `:4244-4249` `[ELIFECYCLE] Command failed with exit code 1` … `[test] ERROR task failed`

Both attempts throw from the same site, `bridge-viewer-vite-annotation-backpressure-journey.ts:380`,
because the journey collects a diagnostic and rethrows once at the end.

**Attempt 1 — `head-ec659-local-test-approved.log:4214-4215`, marker `[1/2]`**

```
cleanup:        {"fixture":"disposed","server":"stopped"}
cleanupFailure: null
currentMilestone:          "reply.5.flush.waiting"
currentElapsedMilliseconds: 48726
errorKind:                  "Error"
errorMessage:               "Bounded E2E operation timed out."
```

Milestone tape (same record) shows replies 1–4 were healthy and reply 5 was not:

| milestone | ms |
|---|---|
| `reply.3.body.waiting` | 7 |
| `reply.4.composer.opening` | 123 |
| `reply.4.create.waiting` | 25 |
| `reply.4.flush.waiting` | **1 022** |
| `reply.4.save.waiting` | 100 |
| `reply.4.save.committed` | 110 |
| `reply.5.composer.opening` | 88 |
| `reply.5.create.waiting` | 10 |
| `reply.5.flush.waiting` | **timed out** |

Catalog telemetry in the same blob: `windowCount: 3`, `maximumUnitByteCount: 131041`,
`presentationRevisionBefore: 11 → After: 12`, `longTaskCountDelta: 0`,
`longTaskObservation.entries: []`, phases `observer_started 7901.8 → settled_frames 9784.6`
(**1 883 ms** total), `root_flush_fill_complete 8026 → root_flush_committed 9068.9` (**1 042.9 ms**).

So a normal flush costs ~1 s here; reply 5 blew a 30 s bound — roughly 30×.

**Attempt 2 — `head-ec659-local-test-approved.log:4226-4227`, marker `[2/2]`**

```
cleanup:        {"fixture":"disposed","server":"not-started"}
cleanupFailure: null
currentMilestone:          "server.starting"
currentElapsedMilliseconds: 120350
errorKind:                  "Error"
errorMessage:               "Bounded E2E operation timed out."
recentMilestones:           test.start:0, fixture.starting:1732, fixture.ready:0
```

**The two local signatures are different.** Attempt 2 never started a server at all; attempt 1 got a
server, a browser, the 1 699-item Review, the root annotation and four replies before hanging.

---

## 2. What the test does, step by step, with budgets

`bridge-viewer-vite-annotation-backpressure.e2e.test.ts` is a 3-line registration shim
(`registerBridgeViewerViteAnnotationBackpressureJourneyTests()`); all behaviour lives in
`bridge-viewer-vite-annotation-backpressure-journey.ts`.

### 2.1 Budget constants

| Constant | Value | File:line | Governs |
|---|---|---|---|
| `stressReviewItemCount` | 1 699 | `journey.ts:59` | changed files in the Review fixture |
| `stressAnnotationCatalogCloneCount` | 2 000 | `journey.ts:60` | cloned annotation messages |
| `stressJourneyTimeoutMilliseconds` | 600 000 | `journey.ts:61` | vitest per-test timeout (arg at `journey.ts:392`) |
| `stressExecutionCeilingMilliseconds` | 540 000 | `journey.ts:62` | global clamp on every milestone bound (`:168-177`) |
| `stressOperationTimeoutMilliseconds` | **120 000** | `journey.ts:63` | default per-milestone bound (`:205`) |
| `stressDiagnosticTimeoutMilliseconds` | 119 000 | `journey.ts:64` | diagnostic waits |
| `annotationCommandTimeoutMilliseconds` | 30 000 | `journey.ts:65` | every create/flush/save wait |
| `cleanupOperationTimeoutMilliseconds` | 30 000 | `journey.ts:66` | cleanup bounds |
| `renderReceiptLeaseMilliseconds` | 5 000 | `journey.ts:67` | receipt-age assertions |
| `serverStartupTimeoutMilliseconds` | 30 000 | `bridge-viewer-vite-product-fixture.ts:20` | Vite readiness |
| `startupTimeoutMilliseconds` | **120 000** | `scripts/dev-server/bridge-development-server-process.ts:10` | Swift backend readiness |
| `readinessProbeIntervalMilliseconds` | 50 | `bridge-development-server-process.ts:12` | health poll cadence |
| `annotationSaveJourneyTimeoutMilliseconds` | **120 000** | `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts:48` | Playwright `waitForFunction` hard timeouts |
| `annotationProjectionResponseTimeoutMilliseconds` | 30 000 | `save-journey.ts:49` | projection-response waits |

Runner config, `BridgeWeb/vitest.e2e.config.ts`: `environment: 'node'`, `fileParallelism: false`,
`testTimeout: 180_000` (overridden per-test to 600 000), `hookTimeout: 60_000`, **`retry: 1`**.
The retry was added deliberately — commit `ee92e34cf ci: retry BridgeWeb E2E journeys once on CI
timing flakes (#324)`.

`withBoundedTimeout` (`journey.ts:212-227`) races a promise against a `setTimeout` that rejects with
the literal string `Bounded E2E operation timed out.` It **cannot cancel** the losing operation.
`runMilestone` (`journey.ts:194-210`) transitions the milestone label *before* running the
operation, and derives the bound from `operationTimeoutMilliseconds()`
(`journey.ts:168-177`) = `min(requested, 540 000 − elapsed)`.

### 2.2 Sequence

1. **`fixture.starting` → `fixture.ready`** — `journey.ts:241-250` calls
   `createBridgeViewerViteProductFixture({ reviewChangedFileCount: 1699 })`
   (`bridge-viewer-vite-product-fixture.ts:107`). It `mkdtemp`s a real git repo under `$TMPDIR`
   (`:119`), a separate data root (`:159`), writes 1 699 nested changed files plus 24 tree-only files
   and a 128-line "large" file, and commits base and head. Measured locally: **1 732 ms**; on CI
   2 071–3 382 ms.

2. **`server.starting` → `server.ready`** — `journey.ts:251-256` calls
   `startBridgeViewerOwnedViteProductServer` (`fixture.ts:426-517`), bounded by the milestone default
   of **120 000 ms**. Four things happen in sequence inside:
   - `reserveLoopbackPort()` (`fixture.ts:706-721`) — `listen(0, '127.0.0.1')` then close. A TOCTOU
     reservation.
   - `startBridgeViewerOwnedTelemetryReceiver()` (`fixture.ts:723`) — in-process HTTP OTLP sink.
   - `startOwnedBridgeDevelopmentServer` (`bridge-development-server-process.ts:58-138`) — spawns the
     **prebuilt** `.build-bridge-development-server/agentstudio-bridge-dev-server` with
     `cwd: repoRootPath` and `--worktree-root <tmp fixture>`, then polls
     `GET /__bridge-product/health` every 50 ms for a `204` **and** an `lsof -nP -a -p <pid>
     -iTCP:<port> -sTCP:LISTEN` proof that the child owns the port (`:182-228`, `:235-246`).
     Bounded at **120 000 ms** (`:10`).
   - spawns `node vite.js --host 127.0.0.1 --port <port> --strictPort` (`fixture.ts:444-458`) with
     `BRIDGE_WEB_DEV_BACKEND_ORIGIN`, the two OTLP URLs, and
     **`BRIDGE_WEB_VITE_CACHE_DIR: join(oracle.dataRootPath, 'vite-cache')`** — a *fresh temp
     directory per fixture*. Waits up to **30 000 ms** for the `http://127.0.0.1:<port>/` line
     (`fixture.ts:474-492`).

3. **File-surface seed journey** — `journey.ts:257-261` calls
   `runAnnotationSaveJourney({ surface: 'file' })`. **This is not wrapped in a milestone**, so the
   milestone label stays `server.ready` for its whole duration. Internally it launches a browser,
   loads the file viewer, selects a range, creates/flushes/saves an annotation, and waits on several
   Playwright `waitForFunction` calls with a **120 000 ms** hard timeout (`save-journey.ts:244-252`
   waits for the Save button to become enabled; `:803-832` `waitForSelectedFileReady`;
   `:586-610` `waitForSelectedReviewReady`). On failure it wraps the cause with
   `browser=<diagnostics>` and **`server=${props.server.diagnostics()}`** (`save-journey.ts:416-419`)
   — this is what carries the Vite/backend log tails into CI records.

4. **Catalog inflation** — `journey.ts:262-268`
   `cloneSavedAnnotationMessagesIntoCompletedSession({ cloneCount: 2000 })`.

5. **`browser.launching` → `browser.ready`** — `journey.ts:426-429`, Playwright chromium.

6. **Review journey** — `runAnnotationBackpressureJourney` (`journey.ts:419+`):
   `review.loading` → click the Review context (`:486-496`) →
   `review.item-count.waiting` → `waitForReviewItemCount({ expectedItemCount: 1699,
   failureContext: () => props.server.diagnostics() })` (`:497-508`) →
   `review.selecting` / `review.selected.waiting` → `selectReviewFile` then
   `waitForSelectedReviewReady` (`:512-524`, inner Playwright bound **120 000**) →
   `review.range.selecting` (`:525-532`) → root annotation
   (`create` / `flush` / `save` / `body.visible`, each bounded **30 000**, `journey.ts:831-867`) →
   five replies, each `composer.opening` → `create.waiting` → `flush.waiting` → `save.waiting` →
   `body.waiting` (`journey.ts:880-937`, each bounded **30 000**) → `review.telemetry`,
   `stopped-demand`, `review.reload`, `file.ready`, second `review.item-count`,
   `review.bodies.verifying`.

7. **`assertions.running` → `assertions.complete`** — `journey.ts:276-335`. Twenty-plus assertions:
   exact body count 6, 6 distinct message ids, `windowCount ≥ 2`,
   `maximumUnitByteCount ≤ 131072`, `presentationRevisionAfter == Before + 1`,
   **`longTaskCountDelta == 0`** (`:285-298`), undemanded-session fetch/acquire counts == 0,
   File outstanding publication count == 0 and high-water mark == 1, Review outstanding == 0,
   Review high-water mark in (0, 12], receipt high-water mark in (0, 6144],
   max receipt pending age / publication age / worker queue wait < 5 000 ms,
   `responseBeforeOwnerEffectObserved == true`, `failureCount == 0`.

8. **`finally`** — `journey.ts:350-378`. Stops the server with a 30 s bound and asserts
   `cleanup.forcedTerminationRequired === false` and `cleanup.ownedProcessAliveAfterStop === false`
   (`:358-359`). Those flags OR together the Vite child and the Swift backend
   (`fixture.ts:546-554`). Then disposes the fixture.

---

## 3. Same signature on both attempts? Environmental evidence

**Not the same.** Local attempt 1 died at `reply.5.flush.waiting` (30 s bound) with a fully started
server; attempt 2 died at `server.starting` (120 s bound) with no server at all. Across CI, five
further distinct phases appear (section 6).

### 3.1 A 5-minute stall sits immediately before the failing lane

The browser-integration lane prints its last console line at `8:08:05 AM` and reports
`Start at 08:07:52 / Duration 19.61s` (`head-ec659-local-test-approved.log:4199-4200`), so it
finished around **08:08:12**. The very next command's vitest reports `Start at 08:13:13`
(`:4241-4242`). That is **~301 s to spawn the next node process**, with `mise run test` doing nothing
but exiting one pnpm script and starting the next.

`.mise.toml [tasks.test]` (line 316) is strictly sequential:
`lint → test:architecture → test:atomlib-compile-negative → test:bridge-web → test:web →
verify-vendors → bridge-web-build → test:swift → git diff --check`. Nothing in the aggregate was
scheduled during that window.

### 3.2 Process churn across the stall

Node PIDs in the log:

```
:3163  (node:45043)   bridge-web unit lane      Start at 08:07:18
:4091  (node:52079)
:4093  (node:52085)
:4104  (node:52237)
:4122  (node:52383)
:4134  (node:52466)   browser lane              Start at 08:07:52
:4207  (node:64516)   stress lane               Start at 08:13:13
```

52466 → 64516 = **12 050 PIDs in ~321 s ≈ 37 process creations/second sustained**. For calibration,
the Swift dev-server build window (45043 → 52466, ~34 s) burned 7 423 PIDs. Something outside this
run was churning processes hard during the stall.

### 3.3 Ruled out by evidence, not assumption

- **Cold Swift build inside the test budget — NO.** `build:swift-dev-server` ran earlier in the same
  lane: `:3171-3172` invokes `mise --cd .. run build-bridge-development-server`,
  `:3174` `BUILD_PATH=.build-agent-1`, `:4083` `Building for debugging...`,
  `:4086` `executable=…/.build-bridge-development-server/agentstudio-bridge-dev-server`. The next
  lane starts at `08:07:46` (`:4127`). The stress lane at 08:13:13 spawned an already-built binary.
- **Orphan process or port holdover from attempt 1 — NO.** Attempt 1's cleanup reported
  `{"fixture":"disposed","server":"stopped"}` with `cleanupFailure: null`, and the journey asserts
  `forcedTerminationRequired === false` / `ownedProcessAliveAfterStop === false`
  (`journey.ts:358-359`) across *both* the Vite child and the Swift backend
  (`fixture.ts:546-554`). Ports are ephemeral (`listen(0)`), and Vite runs `--strictPort`, so a port
  squatter would have produced `Owned Vite exited before readiness` (`fixture.ts:485`), not a silent
  120 s.
- **Concurrent Swift build in this repo family — NO EVIDENCE.** `find` over all 19
  `~/Documents/dev/project-dev/agent-studio*` worktrees for any `.build*` artifact modified between
  08:08 and 08:14 on 2026-09-15 returned **0** files in every one, including this worktree's
  `.build-agent-1` and `.build-agent-2`.
- **Sandbox/permission denial — present but elsewhere.** `sandbox_apply: Operation not permitted`
  killed the *other* log in *lint* (`head-ec659-local-test.log:2653`); it never reached BridgeWeb.
  The approved run had no such denial.

### 3.4 Two diagnostic defects that destroyed the evidence we would want

1. **Equal budgets, outer timer wins.** The `server.starting` milestone bound is
   `stressOperationTimeoutMilliseconds` = 120 000 (`journey.ts:63`, applied at `:205` because
   `:251-256` passes no override). The Swift backend's own readiness budget is *also* 120 000
   (`bridge-development-server-process.ts:10`), and its clock starts **later** (after port
   reservation and the telemetry receiver). So the outer timer always fires first and its generic
   `Bounded E2E operation timed out.` (`journey.ts:219`) replaces the inner
   `Timed out waiting for owned Swift development backend: {stderrTail, stdoutTail}` (`:226-228`).
   That is why local attempt 2's record contains **nothing** about the backend. The 350 ms overshoot
   (120 350 vs 120 000) is event-loop lag on a 120 s timer.
   The same collision recurs at `review.selected.waiting`: outer 120 000 (`journey.ts:63`) vs inner
   Playwright 120 000 (`save-journey.ts:609`). And the same number again at
   `annotationSaveJourneyTimeoutMilliseconds` (`save-journey.ts:48`). **Three layers, all 120 000.**
2. **Unbounded diagnostic fetch on the failure path.** `journey.ts:339-341` does
   `await fetch(new URL('/__bridge-dev-telemetry/status', server.origin))` with no timeout, *before*
   snapshotting the diagnostic at `:349`. Local attempt 1's `currentElapsedMilliseconds: 48726` =
   the 30 s flush bound + **~18.7 s** in that fetch, which then threw or returned non-ok (the
   `telemetry` key is absent from the emitted JSON). An 18.7 s hang talking to its own loopback Vite
   is itself a starvation signal, and it makes the reported elapsed time misleading.
   Note `server.diagnostics()` (`fixture.ts:559-567`) *is* wired into some helpers
   (`journey.ts:505`, `:719` as `failureContext`; `save-journey.ts:417`) — it is missing only from
   the journey's own top-level catch, which is exactly why the two local records carry nothing and
   the CI records carry everything.

---

## 4. Ranked hypotheses

**H-CI (top, explains 5 of 8 CI attempts) — the per-fixture cold Vite dependency-optimizer pass runs
inside `runAnnotationSaveJourney`'s 120 s budget.**
*Verified from evidence:* in **5 of 5** `server.ready` CI failures the Swift backend is healthy
(`[HummingbirdCore] Server started and listening on 127.0.0.1:<port>`), Vite booted in 348–801 ms,
and Vite's **last log line ever** is `[vite] (client) [optimizer] bundling dependencies...` — it never
reaches `optimized dependencies changed. reloading`. `BRIDGE_WEB_VITE_CACHE_DIR` is a fresh
`mkdtemp` per fixture (`fixture.ts:454` + `:159`) consumed as Vite's `cacheDir`
(`vite.config.ts:36, 89-93`), so every attempt *and every retry* runs the optimizer stone cold.
`optimizeDeps.include` (`vite.config.ts:40-42`) prewarms a known list but does not prevent
discovery-triggered re-optimization, which triggers a full-page reload mid-journey.
*Unverified:* whether the optimizer merely runs long or triggers a reload that destroys the awaited
Save button; and whether a *passing* run's Vite tail differs (no successful-run tail exists in this
inventory, because `viteStdout` is only emitted on failure).

**H-Load (second, explains both CI and local) — the journey's fixed budgets sit too close to the
runtime it actually needs on a contended machine.**
*Verified from evidence:* five distinct failing phases across four machines and three days;
CI catalog-phase windows **3 858 ms / 5 277 ms** vs local **1 883 ms** (2–2.8× slower) with
**11 and 17** long tasks (50–444 ms) vs local **0**; local `server.starting` >120 000 ms against a CI
range of **574–1 236 ms** (a ~100× outlier); the 301 s inter-lane stall and 37 PIDs/s churn on the
local box (§3.1–3.2).
*Unverified:* no CPU/load sample, no per-process accounting, and no identification of what was
spawning processes locally.

**H-Product (third) — a genuine backpressure/ordering defect.**
*Unverified and currently unsupported.* Its only candidate evidence is CI attempts 7/8, where the
failing assertion (`longTaskCountDelta == 0`) is itself load-coupled, and local attempt 1's
`reply.5.flush.waiting`, which has no CI counterpart at all (CI completed that same milestone in
1 138 ms).

**H-Wedge (fourth) — the Swift dev backend wedged on a filesystem/consent boundary
(`cwd` is under `~/Documents`; worktree root is under `$TMPDIR` / `/var/folders`).**
*Unverified, and weakened:* the shape fits local attempt 2 (process alive, no output, health never
204), but the same binary from the same cwd came up fast on attempt 1 seventy-five seconds earlier,
and TCC grants are per-binary. Listed only because the destroyed inner diagnostic (§3.4) is exactly
what would confirm or kill it.

### Single discriminating observation

Set `BRIDGE_WEB_VITE_CACHE_DIR` to a warm shared directory and re-run the stress lane on CI several
times. If the `server.ready` class disappears, **H-CI** is confirmed and five of the eight CI
attempts are closed. If it persists, the failure is downstream of the optimizer and **H-Load**
carries it.

Secondary discriminator for the local-only phases: run
`pnpm --dir BridgeWeb run test:e2e:prepared:stress` three times on an otherwise idle machine while
sampling `uptime` / process count, and compare the `server.starting` and `reply.N.flush` milestone
durations. If `server.starting` returns to ~1 s and all flushes sit near 1 s → H-Load. If
`reply.5.flush` still blows the 30 s bound on an idle machine → H-Product, and it deserves a ticket.

---

## 5. Smallest candidate fix for the top hypothesis (NOT made)

### 5.1 Primary — `bridge-viewer-vite-product-fixture.ts:454`

Current:

```ts
BRIDGE_WEB_VITE_CACHE_DIR: join(oracle.dataRootPath, 'vite-cache'),
```

Change: point it at a directory that persists across fixtures and attempts — a fixed path derived
from `bridgeWebRootPath`, or omit the override entirely so Vite falls back to its default
`node_modules/.vite` (`vite.config.ts:36` only sets `cacheDir` when the env var is non-empty, per
`resolveBridgeWebViteCacheDirectory` at `:89-93`, so deleting the env entry is sufficient).

**Does it weaken the test's proof? No.** The dependency-optimizer cache is build-tool plumbing.
Nothing the journey asserts — annotation durability, catalog windowing, receipt ages, backpressure
high-water marks, long-task freedom — depends on that cache being cold. The change removes a bundler
cost from inside a product-behaviour budget. It is not a sleep, not a raised retry count, not a
loosened assertion.

**Caveat to settle with the author before changing it:** the per-fixture cacheDir may be deliberate
isolation. `vitest.e2e.config.ts` sets `fileParallelism: false`, and `test:e2e:prepared` runs
`:stress` then `:ordinary` sequentially (`BridgeWeb/package.json`), so no overlap exists today — but
a shared cacheDir is concurrency-unsafe if fixtures are ever allowed to overlap. That is an
ownership decision, not a unilateral one.

### 5.2 Secondary — diagnostics only

- **Break the three-way 120 000 ms tie** so the inner layer always reports first. Either pass an
  explicit `timeoutMilliseconds` at `journey.ts:251-256` (and at the `review.selected` milestone,
  `:518-524`) that is strictly greater than the inner budget, or import/export the constants so the
  ordering is expressed rather than duplicated across `journey.ts:63`, `save-journey.ts:48`, and
  `bridge-development-server-process.ts:10`.
  *Proof strength unchanged:* the effective budget remains the inner one; only which error object
  survives changes. Had this been in place, local attempt 2 would have told us what the backend was
  doing instead of nothing.
- **Bound the diagnostic fetch and attach server diagnostics** at `journey.ts:336-349`: wrap the
  telemetry fetch in the existing `withBoundedTimeout` (a couple of seconds) and add
  `server.diagnostics()` (`fixture.ts:559-567`) to the captured failure.
  *Proof strength unchanged:* this runs strictly after the product failure has been recorded.

### 5.3 What I would NOT change

The `longTaskCountDelta == 0` assertion (`journey.ts:285-298`). It is the one thing this stress test
uniquely proves, and loosening it to make CI green would trade the gate's entire value for a
checkmark. If it keeps firing after H-CI is addressed, the honest options are a quieter runner or
scoping the assertion to `matchedEntries` — long tasks that genuinely overlap the main-staging window
— which HEAD's newer message shape already hints at. That is a design conversation, not a threshold
bump.

### 5.4 Honest answers to the two framings offered in the brief

- *"The test budget includes a cold Swift build"* — **no.** Ruled out at §3.3; the dev-server binary
  was built earlier in the lane (`:4086`) and the stress lane spawned it prebuilt. But the budget
  **does** include a cold **Vite dependency-optimizer** pass, which is the same category of mistake
  one layer up the toolchain (§4, H-CI).
- *"An orphan process holds the port"* — **no.** Ruled out at §3.3 by the test's own cleanup
  assertions and by ephemeral-port + `--strictPort` semantics.

---

## 6. CI failure records (four runs, eight attempts)

Source logs (ANSI-stripped with `sed -E 's/\x1b\[[0-9;]*m//g'`), job **"BridgeWeb Swift backend"**,
under `…/scratchpad/flake-inventory/real/`. CI runs
`pnpm --dir BridgeWeb run test:e2e:prepared` on a dedicated `macos-26` runner
(`.github/workflows/ci.yml:255`) — the same script as local.

### 6.1 Per-attempt records

| # | Run · log line | Date / branch | Att. | Milestone | Elapsed (ms) | Kind | Message |
|---|---|---|---|---|---|---|---|
| 1 | `34588581240-103228380630.log:5280` | 2026-09-11 feat/zmx-update | 1 | `server.ready` | **142 475** | Error | `Annotation Save journey failed: cause={"kind":"TimeoutError","message":"page.waitForFunction: Timeout 120000ms exceeded."}` |
| 2 | `34588581240-103228380630.log:5292` | " | 2 | `server.ready` | **138 366** | Error | same |
| 3 | `34657945125-103454281946.log:5246` | 2026-09-11 rendered-markdown-annotations | 1 | `server.ready` | **142 265** | Error | same |
| 4 | `34657945125-103454281946.log:5258` | " | 2 | `server.ready` | **132 548** | Error | same |
| 5 | `34734857735-103664331818.log:5229` | 2026-09-13 repo-bugs | 1 | `server.ready` | **135 105** | Error | same |
| 6 | `34734857735-103664331818.log:5241` | " | 2 | `review.selected.waiting` | **120 449** | Error | `Bounded E2E operation timed out.` |
| 7 | `34764766262-103743666630.log:5195` | 2026-09-13 repo-bugs | 1 | `assertions.running` | **123** | **AssertionError** | `catalog-scoped long-task count: {…}: expected 1 to be +0 // Object.is equality` |
| 8 | `34764766262-103743666630.log:5208` | " | 2 | `assertions.running` | **69** | **AssertionError** | same |

All eight report `cleanup: {"fixture":"disposed","server":"stopped"}` with `cleanupFailure: null` —
cleanup was clean in every CI failure, exactly as locally.

(Lines ending `len=72` in the extraction are the `❯ …journey.ts:380:11` stack frames; the `len=4049`
ones are GitHub's 4096-character truncation of the repeated summary block. No failure records were
lost to truncation.)

### 6.2 The `server.ready` cluster (5 of 8) — what `server=` carried

`save-journey.ts:417` appends `server=${props.server.diagnostics()}` to the wrapped error, so these
five records contain the Vite and backend log tails. Every one of them:

```
backendStderr: "2026-09-11T10:48:05+0000 info agentstudio-bridge-dev-server:
                [HummingbirdCore] Server started and listening on 127.0.0.1:49432\n"
backendStdout: ""
viteStdout:    "VITE v8.1.5  ready in 632 ms
                ➜  Local:   http://127.0.0.1:49430/
                10:48:08 AM [vite] (client) [optimizer] bundling dependencies..."
```

Vite "ready in" across the five: **632, 653, 456, 801, 348 ms**. The backend listens every time.
And `[optimizer] bundling dependencies...` is the terminal Vite line in **5 of 5** — see §4 H-CI.

The 120 000 ms that expires is `annotationSaveJourneyTimeoutMilliseconds` (`save-journey.ts:48`), a
Playwright hard wall-clock on `waitForFunction` for the Save button becoming enabled
(`save-journey.ts:244-252`). The milestone reads `server.ready` only because the file-surface seed
journey (`journey.ts:257-261`) is not wrapped in a milestone — the label is misleading, the timing
is not.

Browser diagnostics in these records end with `transport-failures:{"annotationQueries":[…]}`, whose
`file.annotations.projection.query` result at `requestSequence: 12` returns
`expectedMessageCount: 0, expectedSessionCount: 0, expectedThreadCount: 0, projectionRevision: 1`.
At that point in the seed journey an empty projection may be correct, so I do not read this as a
defect on its own.

### 6.3 The assertion cluster (2 of 8) — the only non-clock failure

`longTaskCountDelta` was **1**, expected 0. Parsed observation payload:

| | Long tasks in window | Duration range | Observation window |
|---|---|---|---|
| CI att. 7 | **11** | 58–390 ms | `observer_started 33 556.3 → settled_frames 37 414.0` = **3 858 ms** |
| CI att. 8 | **17** | 50–444 ms | `observer_started 32 454.2 → settled_frames 37 731.1` = **5 277 ms** |
| Local (approved log `:4215`) | **0** | — | `7 901.8 → 9 784.6` = **1 883 ms** |

Phase costs, CI att. 7 vs local: `root_flush_fill_complete → root_flush_committed` = 1 023 ms vs
1 043 ms (comparable); `root_save_committed → root_body_visible` = 1 063 ms vs 21 ms; whole window
2.0× / 2.8× longer. The identical sequence runs through a main thread producing a long task roughly
every 300 ms on CI and none at all locally.

Also of note: the CI assertion message serializes as `{entries, phases}` while HEAD serializes
`{continuousBounds, mainStagingSamples, matchedEntries, observation}` (`journey.ts:287-297`). The
richer diagnostic — specifically `matchedEntries`, the tasks that actually overlap main staging —
was added **after** these runs. Someone was already narrowing this.

`review.item-count.ready` (waiting for 1 699 items to render) cost **19 397 / 21 798 / 21 468 ms** on
CI against a 120 000 ms bound — ~5.5× headroom, not currently at risk, but worth watching alongside
the `stressExecutionCeilingMilliseconds = 540 000` clamp (`journey.ts:168-177`), which progressively
collapses every later bound as a slow run accumulates elapsed time.

### 6.4 Do CI failures cluster on the local milestones?

**No. They do not overlap at all.**

| Milestone | Local | CI |
|---|---|---|
| `reply.5.flush.waiting` | **failed**, 30 s bound exceeded (att. 1) | **passed** in 1 138 ms (record 6's tape) |
| `server.starting` | **failed**, >120 000 ms (att. 2) | **passed** in 574 / 725 / 964 / 998 / 1 236 ms (all records) |
| `server.ready` (seed journey) | passed both attempts | **failed 5 of 8** |
| `review.selected.waiting` | passed (att. 1 reached reply 5) | **failed 1 of 8** |
| `assertions.running` | never reached | **failed 2 of 8** |

Neither local phase appears as a CI failure, and no CI failure phase appears locally. The
`server.starting` contrast is the sharpest single fact in the whole inventory: CI completes it in
about **one second, every time**; the local machine failed to complete it in **120 seconds**. That is
a ~100× outlier on a path CI treats as trivial.

### 6.5 Does the CI data support the "two distinct local signatures → two distinct causes" split?

**Partly — but it reframes the split rather than confirming it.**

- The premise is right that the two local signatures are not one failure. They are not.
- But the CI data shows the correct decomposition is **not** "local cause A + local cause B". It is
  **"a CI-specific root cause" + "a local-machine-specific condition"**, with a shared amplifier.
- **Local attempt 2 (`server.starting`, >120 s)** is decisively local: CI does this in ~1 s in all
  five measured cases. Combined with the 301 s inter-lane stall and 37 PIDs/s churn (§3.1–3.2), this
  is machine starvation on the local box. It is not the CI flake.
- **Local attempt 1 (`reply.5.flush.waiting`, 30 s)** has no CI counterpart either, and the same
  milestone costs 1 138 ms on CI. It is most consistent with the same local starvation — note the
  18.7 s hang on a *loopback* fetch to its own Vite in the same record (§3.4) — but a product stall
  at the sixth annotation under a 2 000-message catalog cannot be excluded from one sample. This is
  the single local observation that could still turn out to be H-Product.
- **The CI cluster is a third, separate thing** with its own identified cause (cold Vite optimizer
  inside a 120 s Playwright budget) that never fires locally, because local attempt 1 sailed past the
  seed journey and local attempt 2 never got to it.
- **The common thread across all three** is H-Load: eight of ten attempts are fixed wall-clock
  budgets exceeded, in five different phases, on machines demonstrably 2–100× slower through the
  affected path than the reference. A single ordering or backpressure defect concentrates on one
  phase. This does not.

**Practical consequence:** fixing H-CI (§5.1) should close records 1–5 and is worth doing on its own
merits. It will do nothing for the local failures. The local box needs to not be running anything
else during `mise run test`, and the budget-collision fix (§5.2) is what will let the *next* local
occurrence say what actually happened instead of `Bounded E2E operation timed out.`

---

## Appendix — files and commands referenced

Repo (read-only):
- `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-backpressure.e2e.test.ts`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-backpressure-journey.ts`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-save-journey.ts`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts`
- `BridgeWeb/scripts/dev-server/bridge-development-server-process.ts`
- `BridgeWeb/vitest.e2e.config.ts`, `BridgeWeb/vite.config.ts`, `BridgeWeb/package.json`
- `.mise.toml` (`[tasks.test]` line 316; `[tasks."test:bridge-web"]` line 142)
- `.github/workflows/ci.yml:255`
- `BridgeWeb/AGENTS.md` — contains **no** stress/e2e/serialization conventions
  (grep for `stress|e2e|serial|flake|backpressure|concurren` returned nothing)

Evidence:
- `tmp/debug-workflows/2026-09-15-sidebar-regressions/head-ec659-local-test-approved.log` (+ `.receipt`)
- `tmp/debug-workflows/2026-09-15-sidebar-regressions/head-ec659-local-test.log` (+ `.receipt`)
- `…/scratchpad/flake-inventory/real/34588581240-103228380630.log`
- `…/scratchpad/flake-inventory/real/34657945125-103454281946.log`
- `…/scratchpad/flake-inventory/real/34734857735-103664331818.log`
- `…/scratchpad/flake-inventory/real/34764766262-103743666630.log`

Relevant history:
- `ee92e34cf ci: retry BridgeWeb E2E journeys once on CI timing flakes (#324)` — where `retry: 1` came from
- `aa4631935 Separate frame acknowledgement fixture support` — most recent touch of the journey file

Extraction scripts left in the scratchpad: `extract.py`, `extract2.py` … `extract6.py`. 30 logs sit
in the flake inventory; this report reads 4 of them plus the 2 local logs.
