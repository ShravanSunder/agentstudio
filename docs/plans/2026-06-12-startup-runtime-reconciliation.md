# Startup Runtime Reconciliation Implementation Plan

Date: 2026-06-12
Source spec: `docs/superpowers/specs/2026-06-12-startup-runtime-reconciliation.md`
Status: reviewed by `plan-review-swarm`; accepted findings folded into this
plan; execution target is T0-T6 only.

## Goal

Remove destructive zmx cleanup from Agent Studio boot before this branch opens a
PR, while preserving startup anchor hydration/adoption and updating architecture
docs to match the new safety model.

The first slice is intentionally narrow:

- boot may discover, classify, hydrate, adopt, persist, and log,
- boot must not call any API that can reach `zmx kill`; the startup helper
  accepts a discovery-only capability, not `SessionBackend`,
- debug zmx sessions must survive PR-blocking local proof, and beta zmx
  sessions must survive release-promotion proof against the signed/notarized
  GitHub beta artifact,
- stable production sessions are inventoried but not launched against unless the
  user explicitly approves a stable smoke,
- this PR surface includes the already-implemented SQLite anchor/source-removal
  migrations from the branch; promotion proof must therefore validate migration
  backup, integrity checks, and zmx session preservation together with the
  startup reconciliation change.
- PR closeout uses a normal merge commit, not squash, unless the user
  explicitly overrides that merge policy.
- PR readiness includes resolving or explicitly answering all review comments
  after validating them against current code.

The background janitor is a follow-up. Any new janitor persistence or tombstone
work beyond the existing 008/009 anchor/source-removal migrations must use
append-only SQLite migrations in later, stepwise slices with dedicated
red/green migration tests.

## Source Coverage

Spec read in full:

- `docs/superpowers/specs/2026-06-12-startup-runtime-reconciliation.md`
- `wc -l` result: 416 lines
- chunks read: lines 1-160, 161-320, 321-416

Pre-change live repo evidence checked while creating the plan:

- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
  - former startup cleanup and kill path: lines 207-338
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
  - boot awaits cleanup before coordinator setup: lines 251-277
- `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift`
  - pure planner, anchor hydration plan, same-kind pane-tail protection
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift`
  - session id format, `discoverOrphanSessions`, `destroySessionById`
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`
  - stored-first restore identity
- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift`
  - data roots: debug default `~/.agentstudio-db`, stable `~/.agentstudio`,
    beta `~/.agent-studio-b`; observability debug runner overrides debug to
    `~/.agentstudio-db/<worktree-code>`
- `Tests/AgentStudioTests/App/ZmxOrphanCleanupPlannerTests.swift`
  - former tests asserted boot destroys unrelated sessions
- `Tests/AgentStudioTests/Integration/ZmxE2ETests.swift`
  - former real-zmx smoke expected startup cleanup to kill unrelated session
- `.mise.toml`
  - default tests skip `ZmxE2ETests` unless `SWIFT_TEST_INCLUDE_ZMX_E2E=1`
- architecture docs requiring alignment:
  - `docs/architecture/session_lifecycle.md`
  - `docs/architecture/zmx_restore_and_sizing.md`
  - `docs/architecture/pane_runtime_architecture.md`
  - `docs/debugging/zmx-environment-isolation.md`

## New System Sketch

```text
BOOT, NON-DESTRUCTIVE

  restore core/local SQLite
          |
          v
  build active workspace pane candidates
          |
          v
  all persistent zmx panes have valid stored anchors?
          |
          +-- yes --> skip inventory; continue boot
          |
          +-- no ---> zmx inventory snapshot
                         |
                         v
  ZmxOrphanCleanupPlanner.plan(...)
          |
          +-- anchorsToHydrate ---------> store.paneAtom.setTerminalZmxSessionId
          |                                store.flushAsync()
          |
          +-- protectedRuntimeIds ------> log / trace protection counts
          |
          +-- candidateOrphans ---------> log / trace only
          |
          v
  continue boot

  There is no transition to zmx kill in boot.
```

```text
FOLLOW-UP JANITOR, NOT THIS PR

  app healthy
       |
       v
  full datastore ownership inventory
       |
       v
  complete runtime inventory + instance ownership proof
       |
       v
  observe-only candidate recording
       |
       v
  append-only SQLite migration, if durable janitor state is needed
       |
       v
  two-snapshot TTL confirmation
       |
       v
  optional destructive cleanup after review + proof
```

## Non-Goals

- Do not implement the full background janitor in this PR-blocking slice.
- Do not add SQLite schema for janitor/tombstones in this slice.
- Do not change zmx session id format.
- Do not change `TerminalRestoreRuntime` stored-first restore semantics.
- Do not expose zmx IPC as app API.
- Do not solve high CPU/performance work here.
- Do not redesign build-slot/debug-observability DX here. Scoped launcher
  hardening is allowed when needed to make the required debug/beta proof
  executable without touching stable production state.

## Requirements / Proof Matrix

| Requirement / claim | Task | Proof gate | Layer | Red/green required? | Sized to pass? |
|---|---:|---|---|---|---|
| Boot cannot reach `zmx kill` by construction | T0, T1 | Startup reconciliation helper accepts a discovery-only inventory protocol with no destroy methods; AppDelegate boot wrapper test uses the discovery-only seam | unit/integration | yes | yes |
| Boot never reaches `zmx kill` at behavior level | T0, T1 | AppDelegate startup reconciliation test with recording inventory asserts no destroy-capable object is available; existing recording backend asserts `destroyedSessionIds.isEmpty` where retained for legacy helper proof | unit/integration | yes | yes |
| Legacy roamed pane anchor is still adopted and persisted | T0, T1 | Same test asserts stored `zmxSessionId == birthSessionId` after `flushAsync` | integration | yes | yes |
| Unrelated live zmx sessions survive boot | T0, T1, T4 | Unit recording backend + real-zmx E2E assert unrelated session remains alive | integration/e2e | yes | yes |
| Two boot contexts sharing one `ZMX_DIR` cannot reap each other | T4 | Real-zmx E2E seeds two independent stores/pane sets in one harness zmx dir, runs startup reconciliation for both, and asserts both pre-existing session sets remain alive | e2e | yes | yes |
| Stored-first restore identity is unchanged | T1 | Existing `TerminalRestoreRuntimeTests` remain green | unit | no new red needed | yes |
| Current planner protection/adoption rules remain intact | T1 | Existing `ZmxOrphanCleanupPlannerTests` plus renamed boot test | unit | yes for changed boot test | yes |
| Architecture docs match boot-no-kill model | T2 | Named-section checklist plus grep: restart-reconcile sections, TTL headings/anchors, LUNA-324 row, and zmx debugging guide all describe boot as non-destructive and janitor as future/follow-up | docs | no | yes |
| Debug sessions are not lost on PR-blocking local proof; beta sessions are preserved during release promotion proof | T3, T4 | Clean-shell preflight; non-empty preseeded debug inventory; debug pre/post zmx inventories match or only add expected sessions; beta proof is run against the accepted/notarized GitHub release artifact, not an ad-hoc local bundle | smoke/release | yes manual proof | yes |
| Stable production sessions are not touched without explicit approval | T3, T4 | Stable inventory captured before/after only when no stable launch occurs; final report labels stable smoke as release-only/user-approved | smoke/release | yes manual proof | yes |
| SQLite data is not corrupted by promotion proof | T3, T4 | `sqlite3 "$data_root/core.sqlite" 'PRAGMA integrity_check;'` and every `$data_root/workspaces/*.local.sqlite` returns `ok`; outputs archived with inventories | smoke/release | yes manual proof | yes |
| Default repo health remains green | T5 | `mise run test`, `SWIFT_TEST_INCLUDE_E2E=1 mise run test`, `SWIFT_TEST_INCLUDE_ZMX_E2E=1 SWIFT_TEST_TIMEOUT_SECONDS=420 mise run test`, `mise run lint` | unit/integration/e2e/lint | no | yes |
| Real zmx path remains safe | T4, T5 | `SWIFT_TEST_INCLUDE_ZMX_E2E=1 SWIFT_TEST_TIMEOUT_SECONDS=420 mise run test`; focused `mise run test-zmx-e2e` is diagnostic only | e2e | yes | yes |
| Victoria-stack debug proof is current locally; beta proof uses the signed/notarized release artifact | T4 | `mise run observability:up`, `mise run observability:smoke`, detached debug runner, and startup trace fields for inventory outcome/hydration/protection/unresolved/candidate counts; after beta tag workflow, run beta bundle runner + `mise run verify-beta-observability` against that artifact | smoke/observability/release | yes manual proof | yes |
| PR review comments are resolved from current evidence | T6 | Supported `gh pr view` fields plus GraphQL review-thread query; replies/resolutions; final unresolved count zero or explicitly non-blocking | PR/review | no | yes |
| PR merges by merge commit, not squash | T6 | `gh pr merge --merge`, final PR state `MERGED`, merge commit recorded | PR/release | no | yes |
| Future janitor schema is stepwise only | T7 | Follow-up plan uses append-only migration tests before code consumes new rows | planning | no code in this slice | yes |

## Task Sequence

### T0 — Red Tests for No-Boot-Kill

Purpose: flip the current destructive startup expectations before product code
changes.

Write surfaces:

- `Tests/AgentStudioTests/App/ZmxOrphanCleanupPlannerTests.swift`
- `Tests/AgentStudioTests/Integration/ZmxE2ETests.swift`
- possibly a small test-only fixture/fake for the new discovery-only startup
  inventory seam, colocated with existing zmx test helpers.

Changes:

1. Rename the boot-level test from its pre-change destructive-cleanup wording
   to `startup reconciliation hydrates legacy roamed pane anchor without
   destroying unrelated sessions`.
2. Keep the same arrangement: legacy roamed pane has no stored anchor, live birth
   session exists, unrelated live session exists.
3. Change assertions:
   - adopted anchor is persisted,
   - startup reconciliation receives only a discovery-only inventory capability,
   - `backend.destroyedSessionIds.isEmpty` for any retained legacy helper test,
   - unrelated session remains live/untouched.
4. Add a boot-wrapper/call-site proof, not only a direct helper proof:
   - introduce an injectable startup reconciliation path that can be exercised
     without `SessionConfiguration.detect()` reaching the real machine,
   - the test calls the same AppDelegate wrapper used by boot,
   - the injected object exposes discovery only and cannot destroy sessions.
5. In `ZmxE2ETests`, change the real-zmx smoke to assert the unrelated zmx
   session still exists after boot reconciliation.
6. Add a real-zmx shared-`ZMX_DIR` E2E:
   - one harness directory,
   - two independent workspace stores / pane sets,
   - at least one live zmx session per store,
   - run startup reconciliation for each store,
   - assert all pre-existing session ids from both stores still exist.

Pre-change expected red:

- tests failed because `runOrphanZmxCleanup` still called
  `destroySessionById` for unrelated live sessions.

Proof:

```bash
AGENT_STUDIO_BENCHMARK_MODE=off swift test --build-path .build-agent-startup-safety --filter ZmxOrphanCleanupPlannerTests
SWIFT_TEST_INCLUDE_ZMX_E2E=1 SWIFT_TEST_TIMEOUT_SECONDS=420 mise run test
```

If the full zmx E2E gate is too slow during red capture, capture focused red on
`ZmxE2ETests` with the same `SWIFT_TEST_INCLUDE_ZMX_E2E=1` environment. Do not
waive the final green E2E gate.

### T1 — Make Boot Reconciliation Non-Destructive

Purpose: preserve anchor hydration/adoption while removing destructive cleanup
from boot.

Write surfaces:

- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- optional rename call site in
  `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- small read-only startup inventory protocol/type near the App boot owner or zmx
  runtime owner, depending on the smallest dependency direction that keeps boot
  from accepting kill-capable APIs.
- possibly `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift`
  only for naming/read-model clarity; avoid changing core matching semantics.

Implementation direction:

1. Rename concepts away from "cleanup" where practical:
   - `cleanupOrphanZmxSessions` → `reconcileZmxSessionAnchorsAtStartup`
   - `runOrphanZmxCleanup` → `runZmxStartupSessionReconciliation`
   - keep old names only if rename churn becomes too wide, but comments/logs
     must stop promising kill-at-boot.
2. Introduce a startup read-only inventory seam. Boot reconciliation must not
   accept `any SessionBackend` because `SessionBackend` exposes
   `destroyPaneSession` and `destroySessionById`.
   Minimal acceptable shape:

   ```swift
   protocol ZmxStartupSessionInventory {
       func discoverLiveSessionInventory() async -> ZmxSessionInventorySnapshot
   }
   ```

   `ZmxBackend` may conform through a tiny adapter or extension that calls the
   existing list operation. The startup helper accepts this protocol. Destructive
   APIs remain reachable only from explicit janitor/backend tests and later
   janitor code, not boot reconciliation.
3. Keep:
   - `SessionConfiguration.detect()`,
   - the existing zmx list implementation behind the read-only inventory seam,
   - `ZmxOrphanCleanupPlanner.plan(...)`,
   - `persistHydratedZmxSessionAnchors(...)`.
4. Remove the boot loop that computes `orphans` and calls
   `backend.destroySessionById`.
5. Log/trace unmatched live-session count as non-destructive information only.
6. Keep cancellation/timeout only as a bounded discovery/hydration guard, not as
   a cleanup guard.
7. Avoid making every launch wait on live zmx inventory. Startup reconciliation
   may stay on the boot path only when legacy persistent zmx panes are missing
   stored anchors; already-anchored stores must skip live inventory before
   first-window readiness.
8. Rename or document the shared zmx list API coherently. Preferred small
   cutover: add neutral inventory wording at the new startup seam and leave
   deeper `discoverOrphanSessions(excluding:)` naming as backend/janitor legacy
   only; if the implementation touches shared backend tests anyway, rename the
   backend API and update `TerminalRestoreRuntime` and `ZmxBackendTests` in the
   same slice.

No new janitor schema changes. Existing branch migrations 008/009 remain in the
PR surface and are covered by the migration/integrity proof gates.

Proof:

```bash
AGENT_STUDIO_BENCHMARK_MODE=off swift test --build-path .build-agent-startup-safety --filter "ZmxOrphanCleanupPlannerTests|TerminalRestoreRuntimeTests|ZmxBackendTests"
```

### T2 — Align Architecture and Debugging Docs

Purpose: make architecture docs reflect the new invariant and prevent future
agents from reintroducing boot-time destruction.

Write surfaces:

- `docs/architecture/session_lifecycle.md`
- `docs/architecture/zmx_restore_and_sizing.md`
- `docs/architecture/pane_runtime_architecture.md`
- `docs/debugging/zmx-environment-isolation.md`
- possibly `docs/superpowers/specs/2026-06-12-startup-runtime-reconciliation.md`
  if implementation reveals a spec correction.

Required doc updates:

1. Replace launch-time "orphan cleanup" language with
   "startup runtime reconciliation" / "anchor hydration".
2. State clearly:
   - boot never kills zmx sessions,
   - pane UUID tail is adoption/protection evidence, not kill authority,
   - global `ZMX_DIR` requires full datastore and instance ownership before any
     janitor can destroy.
3. Mark TTL cleanup as future background janitor behavior, not current boot
   behavior.
4. Update test coverage descriptions so `ZmxE2ETests` no longer claims boot
   cleanup kills sessions.
5. Update the specific stale sections:
   - `session_lifecycle.md` identity/interplay and launch reconcile sections,
   - `zmx_restore_and_sizing.md` restart reconcile policy and TTL cleanup
     heading/anchor,
   - `pane_runtime_architecture.md` LUNA-324 relationship row and any Contract
     5b restart-reconcile text,
   - `zmx-environment-isolation.md` reaper and diagnostic signal language.

Proof:

```bash
rg -n "cleanupOrphanZmxSessions|runOrphanZmxCleanup|startup.*kill|launch.*kill|cleanup.*kill|Orphan Cleanup|orphan-cleanup-ttl-policy|LUNA-324" docs/architecture docs/debugging
```

The grep does not have to return zero results; every result must be either
historical/debugging context or clearly describe the new no-boot-kill invariant.
Do not treat grep alone as sufficient: manually re-read the four named doc
sections above and record the line ranges reviewed.

### T3 — Production Promotion Preservation Runbook / Guard

Purpose: ensure promotion testing explicitly preserves existing production
runtime sessions.

Write surfaces:

- Prefer documentation first:
  `docs/wip/debugging/2026-06-12-zmx-promotion-session-preservation.md`
- Optional helper script only if the manual command is too fragile:
  `scripts/snapshot-zmx-inventory.sh`

Required content:

1. Inventory before launch for each relevant data dir:
   - stable: `~/.agentstudio/z`
   - beta: `~/.agent-studio-b/z`
   - debug observability runner: the `AGENTSTUDIO_OBSERVABILITY_ZMX_DIR`
     reported in `tmp/debug-observability/latest-observability.env`
   - `AGENTSTUDIO_DATA_DIR` override, when used.
2. Launch target build with Victoria observability when practical.
3. Debug runner identity proof:
   - the launched app path contains `AgentStudio Debug <code>.app`,
   - bundle id is `com.agentstudio.app.debug.d<code>`,
   - data root is `~/.agentstudio-db/<code>`,
   - zmx dir is `~/.agentstudio-db/<code>/z`,
   - generated app/log/trace artifacts live under `~/.agentstudio-db/<code>` so
     autonomous runs do not need to read runnable artifacts from `~/Documents`,
   - state records `AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=launchservices` or
     `direct_executable`; only `launchservices` is full GUI proof,
   - launch removes inherited AgentStudio/zmx/Ghostty identity variables while
     preserving the normal GUI session environment.
4. Beta runner identity proof:
   - beta app remains `Agent Studio Beta`,
   - beta data root remains `~/.agent-studio-b`,
   - launch removes inherited AgentStudio/zmx/Ghostty identity variables while
     preserving the normal GUI session environment.
5. Inventory after launch/restart.
6. Compare:
   - no missing pre-existing session ids,
   - no unexpected kills,
   - no `zmx kill` trace/log during boot,
   - SQLite integrity still passes.
7. SQLite integrity commands for every touched data root:

   ```bash
   sqlite3 "$DATA_ROOT/core.sqlite" 'PRAGMA integrity_check;'
   find "$DATA_ROOT/workspaces" -name '*.local.sqlite' -print0 |
     xargs -0 -I{} sqlite3 "{}" 'PRAGMA integrity_check;'
   ```

   Expected output for every database: `ok`. If a database does not exist, the
   runbook must record that explicitly instead of treating it as a pass.
8. Include a release/promotion stop condition:
   - if any pre-existing stable/beta session disappears, stop promotion and
     preserve logs/inventory artifacts.

No new janitor schema changes. The runbook must validate the existing branch
migrations and resulting SQLite files because 008/009 are part of this PR
surface.

Proof:

- Runbook reviewed in plan-review.
- During implementation verification, execute against debug first, then beta.
  Local PR proof uses the isolated debug runner. Beta proof is release-promotion
  proof and must run against the accepted/notarized artifact produced by the
  GitHub beta-tag workflow. Do not touch stable production sessions beyond
  inventory capture unless the user explicitly asks for a stable promotion
  smoke.

### T4 — Real zmx E2E and Observability Proof

Purpose: prove the changed startup behavior against real zmx, not only fakes.

Write surfaces:

- Usually tests only:
  `Tests/AgentStudioTests/Integration/ZmxE2ETests.swift`
- No production code unless T1 revealed a gap.

Proof gates:

```bash
SWIFT_TEST_INCLUDE_ZMX_E2E=1 SWIFT_TEST_TIMEOUT_SECONDS=420 mise run test
mise run observability:up
mise run observability:smoke
mise run run-debug-observability -- --detach
```

Execution note: observability helpers run under `/bin/bash`; launchers try
LaunchServices `open` first. Debug may fall back to direct
`Contents/MacOS/AgentStudio` execution when the generated local debug bundle is
blocked by LaunchServices/Gatekeeper. That fallback is valid for Victoria/OTLP
debug proof because it keeps the per-worktree data/zmx root and records
`AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable`; it is not full GUI
proof. Beta remains strict: if LaunchServices refuses the beta bundle, the
helper must write `AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed` and exit
non-zero rather than direct-executing the app binary. Local ad-hoc beta bundles
may be AMFI/LaunchServices-rejected, and Developer ID signing alone can still be
rejected when the bundle is not notarized. Beta promotion proof requires the
accepted/notarized artifact produced by the GitHub release workflow, or another
explicitly notarized artifact. Local beta app/log/trace artifacts default to
`~/.agentstudio-db/beta-observability/`; only the verifier state file remains in
repo `tmp`. The verifier must bound Victoria query timeouts and avoid
`pipefail`/`head` SIGPIPE false failures.

Manual observability checks:

- Victoria logs show startup reconciliation/hydration facts.
- Startup trace/log fields include inventory outcome, hydration count, protected
  count, unresolved count, and unmatched live-session count.
- No boot-time `zmx kill` event/log.
- Debug app state file reports a per-worktree app/data/zmx identity plus launch
  method, and zmx sessions stay within that root; beta pre/post inventory
  preserves all pre-existing beta sessions.
- SQLite integrity output for touched debug and beta data roots is archived and
  every checked database reports `ok`.

### T5 — Repo Gates

Purpose: prove the branch is PR-ready after the safety change.

Commands:

```bash
mise run test
SWIFT_TEST_INCLUDE_E2E=1 mise run test
SWIFT_TEST_INCLUDE_ZMX_E2E=1 SWIFT_TEST_TIMEOUT_SECONDS=420 mise run test
mise run lint
```

Report:

- pass/fail counts,
- exit codes,
- whether default `mise run test` skipped E2E lanes,
- explicit serialized E2E result,
- explicit zmx E2E result,
- any unrelated failures separated from changed-surface proof.

### T6 — PR Open / Review / Merge-Commit Closeout

Purpose: carry the branch through PR readiness using the repo's expected merge
workflow.

Write surfaces:

- PR body and review replies only, unless review comments identify real code,
  test, or docs defects.

Required flow:

1. Open or update the PR only after T0-T5 are green.
2. In the PR body, state:
   - boot is now non-destructive,
   - SQLite anchor/source-removal migrations are included and covered by
     backup/integrity proof,
   - new janitor/tombstone schema is deferred to stepwise follow-up,
   - production promotion requires pre/post zmx + SQLite integrity proof.
3. For every review comment:
   - re-read the current code/docs around the comment,
   - fix valid issues,
   - answer stale/non-applicable comments with evidence,
   - resolve review threads only after validation.
4. Verify PR state:
   - checks green or explicitly understood,
   - required review threads resolved,
   - no uncommitted local changes intended for the PR remain out of branch.
5. Merge using a normal merge commit:

```bash
gh pr merge <number> --merge
```

Do not use squash unless the user explicitly changes the policy.

Proof:

```bash
gh pr view <number> --json state,mergeStateStatus,reviewDecision,statusCheckRollup
gh api graphql -f owner='ShravanSunder' -f name='agentstudio' -F number=<number> -f query='
query($owner:String!, $name:String!, $number:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          comments(first:1) { nodes { url body } }
        }
      }
    }
  }
}'
gh pr merge <number> --merge
gh pr view <number> --json state,mergedAt,mergeCommit
```

If local worktree conflicts block `gh pr merge`, verify remote PR state before
retrying or doing local cleanup. In multi-worktree cases, prefer GitHub-side
merge verification over fighting a local checkout that already owns `main`.

### T7 — Follow-Up Janitor and Stepwise SQLite Schema Plan

Purpose: prevent the background janitor from becoming an implicit part of the
PR-blocking no-boot-kill change.

This task is planning-only for this branch unless the user explicitly expands
scope after the no-boot-kill PR.

Follow-up plan requirements:

1. Observe-only janitor first, no destruction.
2. If durable janitor state is required, introduce it via one append-only
   migration at a time:
   - migration N: create candidate/tombstone table,
   - tests prove migrate from previous schema,
   - code writes observe-only rows,
   - tests prove rows do not trigger kill.
3. Later migration only if needed:
   - owner-token or instance-lock metadata,
   - red/green migration tests before runtime consumption.
4. Destructive janitor enablement is a separate reviewed slice:
   - requires complete runtime inventory,
   - full datastore ownership,
   - two-snapshot TTL confirmation,
   - instance ownership proof,
   - production-preservation runbook proof.

No janitor schema change is allowed in T0-T6.

## Write Surfaces Summary

PR-blocking slice:

- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Tests/AgentStudioTests/App/ZmxOrphanCleanupPlannerTests.swift`
- `Tests/AgentStudioTests/Integration/ZmxE2ETests.swift`
- `docs/architecture/session_lifecycle.md`
- `docs/architecture/zmx_restore_and_sizing.md`
- `docs/architecture/pane_runtime_architecture.md`
- `docs/debugging/zmx-environment-isolation.md`
- `docs/wip/debugging/2026-06-12-zmx-promotion-session-preservation.md`
- PR body/review replies for the no-boot-kill branch

Possible but avoid unless needed:

- `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift`
- `scripts/snapshot-zmx-inventory.sh`

No schema files in PR-blocking slice:

- do not touch `WorkspaceCoreMigrations.swift` for janitor state,
- do not add cleanup/tombstone tables,
- do not add migration identifiers for janitor work.

## Security / Data-Loss Context

Sensitive assets:

- live user shells,
- terminal scrollback/history,
- zmx sockets/processes,
- persisted `zmx_session_id` anchors,
- stable production runtime under `~/.agentstudio/z`.

Privileged action:

- `zmx kill <sessionId>`.

Security posture:

- no boot path may call that action,
- shared `ZMX_DIR` and `as-*` prefix are not ownership proof,
- malformed/unparseable ids are never killed,
- production promotion requires inventory preservation proof.

## Rollback / Recovery

If the no-boot-kill change causes zmx daemon accumulation:

- rollback is safe from data-loss perspective because sessions were preserved,
- collect zmx inventory and Victoria logs,
- implement observe-only janitor next.

If any session disappears during verification:

1. Stop promotion.
2. Save pre/post inventory, Victoria logs, app stderr log, and SQLite integrity
   output under `tmp/debug-observability/` or `docs/wip/debugging/`.
3. Do not launch further stable/beta builds against the affected data dir until
   the missing-session cause is understood.

## Open Questions

1. Should boot live discovery stay awaited in `bootEstablishRuntimeBus`, or move
   after first window readiness now that it is non-destructive?

   Recommended default: keep it where it is for this slice to preserve legacy
   anchor hydration behavior; consider moving it after app readiness in a
   performance-focused follow-up.

2. Should we rename `ZmxOrphanCleanupPlanner` now?

   Recommended default: do not rename the planner in the PR-blocking slice
   unless the final code reads badly. Rename public boot methods/comments/logs
   first. Planner rename can happen in the janitor follow-up.

3. Should promotion proof include stable production runtime immediately?

   Decision for this plan: PR-blocking local proof includes debug runtime smoke
   plus stable/beta inventory capture only. Beta runtime smoke is promotion proof
   against the GitHub workflow's signed/notarized beta artifact. A stable app
   launch against production data is release-only and requires explicit user
   approval before running.

## Recommended Next Skill

Run `plan-review-swarm` on this plan. After review findings are resolved, use
`implementation-execute-plan` for T0-T6 only. Keep T7 as follow-up planning
unless the user explicitly expands scope.
