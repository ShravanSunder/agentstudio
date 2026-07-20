# Bridge Recovery Stabilization And PR Wrap-Up Plan

Date: 2026-07-19
Status: reviewed and ready for implementation
Goal id: `2026-07-19-bridge-recovery-stabilization`
Branch: `luna-338-pierreshikitrees-review-viewer-2`
Committed baseline: `d0cede45b0cadf333c566e1ec59aef5f789fd2c0`
Terminal: PR ready, independently reviewed, not merged

## 1. Outcome

Finish the current Bridge recovery PR without expanding the Review demand-lane
design. The final candidate must work in the actual multi-file
`agent-studio.bridge-start` worktree with two Review panes for the same
worktree: one restored pane and one newly created pane. Both panes must accept
real clicks and heavy scrolling without a permanent metadata/content wedge.

The runtime model remains:

```text
one canonical worktree + one semantic Review query + one worktree epoch
                              |
                              v
              one Swift/agentstudio-git immutable construction
                              |
                 +------------+------------+
                 |                         |
                 v                         v
        restored Review pane       fresh Review pane
        pane-local publication     pane-local publication
        pane-local comm worker     pane-local comm worker
        pane-local presentation    pane-local presentation
        pane-local suspension      pane-local suspension
```

This plan stabilizes that model, removes the unproven React-owned selection
authority system that accumulated in the dirty tree, proves the existing
packaged WKWebView E2E, records representative metrics, completes the quality
and review loop, and prepares the PR for merge without merging it.

The separate next-PR demand-lane plan is:

`docs/specs/bridge-viewer-transport/plans/2026-07-19-review-demand-lane-completion.md`

## 2. Source Contract And Coverage

Required sources:

- `tmp/review-handoffs/2026-07-18-agent-studio-bridge-recovery-wrapup/implementation-handoff.md`
  (337 lines; fully read before this plan);
- `docs/specs/bridge-viewer-transport/plans/2026-07-13-bridge-viewer-product-recovery.md`
  (1,258 lines; fully read before this plan);
- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
  (2,000 lines; accepted architecture remains frozen);
- `docs/specs/bridge-viewer-transport/performance-demand-lanes.md`
  (1,159 lines; fully read before this plan);
- `tmp/debug-workflows/2026-07-18-agent-studio-bridge-start-packaged-review-publication/debug-investigation.md`;
- current `git status`, `git diff`, oq4s data, and marker-scoped Victoria evidence.

The accepted 2026-07-13 spec/plan and completed product work are not reopened.
This plan narrows the remaining implementation and proof sequence after the
dirty checkpoint grew beyond the handoff's seven files.

## 3. Live Baseline And Decisions

At plan creation:

- HEAD is `d0cede45b0cadf333c566e1ec59aef5f789fd2c0` and is already pushed;
- 32 tracked files are modified, four product experiment files are untracked,
  and the two plan documents are also untracked (six untracked total);
- the diff is approximately 2,498 insertions and 641 deletions;
- no production demand-policy, demand-reconciler, comm-session, or workspace
  persistence file is modified;
- the branch's deterministic debug identity is `oq4s`;
- the last oq4s PID received a Dock Quit event, approved termination, and
  exited cleanly; it did not crash;
- the user's later successful heavy scrolling likely occurred in debug app
  `yjy1`, built from `agent-studio.ghostty-performance`, so it is not proof for
  this worktree even though that app opened `bridge-start` as pane data;
- a separate surviving Ghostty `.flagsChanged`/`NSEvent.characters` exception
  is evidenced in an unmodified Terminal file and is outside this Bridge PR.

Decisions:

1. Keep the Swift shared-construction `.invalidated` reacquisition and its
   focused tests.
2. Keep real render-fulfillment/source-to-paint correlation and permanent
   Browser/packaged diagnostics, after removing only vocabulary that exists
   solely for the rejected authority system.
3. Keep the search-control UX correction.
4. Park/remove the React-owned selection authority epoch/client-owner,
   attempt/ACK state, retry, navigation-reconciliation, and settlement-map
   system. A pane-local selected item remains presentation state; accepted
   worker authority remains owned by the existing comm-worker protocol.
5. Do not change demand-lane production logic in this PR.
6. Diagnose restored-pane failures before fixing them. Do not conflate:
   - an owned pane whose queued command never gets initial bootstrap recovery;
   - an active persisted pane with no tab/drawer ownership, which never creates
     a Bridge controller at all;
   - native package/publication completion followed by a pane-local
     worker/selection/content failure.
7. Synthetic fixtures remain deterministic automated proof. The actual current
   multi-file worktree is required for final UX/performance evidence.
8. The user-approved two-PR split supersedes the old S10a assumption that all
   demand-lane and byte-cache performance rows close in this PR. This PR closes
   selected/visible stabilization, shared construction, hidden suspension,
   click/paint/queue/jank metrics and descriptive RSS. Nearby/background,
   global-cap/cancellation, real Pierre rank, production byte-owning cache and
   full memory attribution close in the next PR.

## 4. Scope

In scope:

- preserve a recoverable snapshot of the entire dirty tree before cleanup;
- reduce the dirty checkpoint to the accepted model;
- add one durable red regression only after the first missing restored-pane
  boundary is evidenced;
- implement the smallest root-cause correction for that boundary;
- make the existing packaged WKWebView E2E green;
- prove restored plus fresh Review panes against the actual worktree;
- record startup, click, scroll, demand, construction, worker, suspension,
  memory, p95 and p99 evidence with fresh identities;
- complete S10/S11, one implementation review/remediation cycle, CI, and PR
  readiness;
- make scoped checkpoint commits and push them.

Out of scope:

- the six demand/retention gaps in the next-PR plan;
- Pierre source, package, fork, dependency, or lockfile changes;
- another harness, ad hoc probe, disposable verifier, or timeout inflation;
- a File cap, a compatibility owner, legacy projection/native-push owners,
  production TypeScript Git, or Worktrunk runtime use;
- arbitrary repair of persisted orphan panes by attaching them to a tab;
- deleting/resetting the oq4s data root;
- touching `yjy1`, stable, beta, or other shared app processes;
- merge.

## 5. Requirements / Proof Matrix

| Requirement or claim | Owning slice | Proof layer and modality | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| Dirty checkpoint reduced to accepted ownership model without losing useful work | S0-S1 | diff inventory, focused unit/Browser, static source audit | parent-run `git diff`, tests, recovery snapshot identity | baseline HEAD plus snapshot OID and final diff | existing failures plus green focused suites |
| Restored owned pane reaches controller, bootstrap, Review intake and content | S2 | SQLite/state inspection, unit/integration, real oq4s UI and Victoria | parent-run DB join, marker logs/metrics, Peekaboo | oq4s PID, executable, marker, pane id | permanent RED after boundary evidence |
| Fresh pane and restored pane remain independent pane authorities | S3-S4 | packaged and actual-worktree two-pane journey | parent-run IPC/UI/Victoria | same worktree digest, distinct pane/worker/publication ids | required |
| Swift constructs identical Review data once per worktree epoch | S4-S5 | counting-provider integration proves exact semantic-key/epoch equality; runtime proves one build plus two joins/leases in an invalidation-free window | parent-run Swift tests and Victoria reduction | integration query selectors, worktree epoch, marker window | existing and fresh green |
| Both panes click and heavy-scroll without permanent waiting/content unavailable | S4 | manual/native UI plus source-to-paint/demand terminal evidence | Peekaboo and Victoria, corroborated by user if present | oq4s window/PID/marker and two pane ids | runtime gate |
| Current-PR selected/visible interaction budgets hold | S4-S5 | restored/fresh action-window percentiles plus existing workload report | parent-run IPC/Peekaboo/Victoria and verifier | final SHA, runtime, machine, marker, sample count | stop-line gate |
| Hidden/inactive pane suspends and resumes without stale publication | S4-S5 | mode-idle smoke, pane flip, activity/queue evidence | existing verifier and focused lifecycle tests | final candidate and marker | required |
| Packaged WKWebView source-to-paint works | S3 | strict LaunchServices runner/verifier | parent-run checked-in commands | final HEAD, bundle, executable, PID, marker, fixture digest | runner/verifier exit 0 |
| No Pierre/legacy/new-owner drift | S1, S6 | dependency/asset/static audit | parent-run final audit | final diff and bundle | required |
| Full quality and PR readiness | S6-S8 | unit/integration/Browser/Vite/WebKit/build/lint/full tests/CI/review | parent and independent reviewer | exact final PR head SHA | required |

Hard interaction stop lines from the accepted performance contract:

```text
Review click_to_first_visible_content_window_ms: p95 < 100, p99 < 200
Review scroll_to_visible_rows_ms:              p95 < 100, p99 < 200
blank_tree_window_count = 0
wrong_visible_row_count = 0
foreground_queue_wait_ms:                      p95 < 16, p99 < 32
visible_queue_wait_ms:                         p95 < 32, p99 < 64
final percentile proof: click samples >= 100, scroll samples >= 100
```

The existing controlled worktree workload must be extended in place to sample
already-emitted Review selection and selected/visible worker queue waits. It is
the only current-PR owner of the following additional hard lines:

```text
local selection feedback p99 < 32 ms
selected worker queue wait p95 < 16 ms, p99 < 32 ms
web long tasks >= 50 ms = 0
telemetry required/optional loss = 0; sequence gaps = 0
logical demand failures/timeouts = 0
```

The accepted `>8 ms` synchronous-slice line has no executable producer in the
current suites and is deferred with the full demand workload rather than
claimed here. If the existing worktree workload cannot consume an
already-emitted per-sample Review queue wait without changing demand behavior,
stop and update the goal/matrix; do not invent telemetry or silently weaken the
line.

If the real-worktree action windows do not contain the minimum automated
sample count, report their p50/p95/p99 as exploratory restored/fresh cohorts;
the final hard percentile claim must come from the existing representative
workload. Do not synthesize samples.

Cold package build and startup duration are reported separately and are never
relabeled as interaction p99.

## 6. Vertical Slices

### S0 — Freeze The Recovery Boundary

Behavior/capability:

- capture exact HEAD/status/numstat and a recoverable full-dirty-tree snapshot
  without modifying the worktree;
- record every modified/untracked file under keep, park, rework, or unresolved;
- record oq4s identity and do not treat yjy1 interactions as branch proof.

Execution:

- after the reviewed plan checkpoint is committed, use a temporary Git index
  to read `HEAD`, add the remaining tracked and four untracked product paths,
  write one tree, and create one recovery commit with `git commit-tree`;
- anchor that commit under the named local-only ref
  `refs/agentstudio-recovery/2026-07-19-bridge-recovery-stabilization`; do not
  use mutable `refs/stash` or loose unreachable blob OIDs;
- record the ref, commit, tree, path, mode, Git blob OID and SHA-256 for every
  captured path in the ignored implementation ledger; never push the private
  recovery ref or its raw manifest;
- verify `git cat-file -e`, `git ls-tree -r`, path/mode/SHA-256 parity, and
  unchanged `git status --short` before cleanup.

Checkpoint: recovery snapshot receipt only; no commit yet.

Split trigger: any unrecognized user-owned change or mismatch from the
32-modified/four-product-untracked inventory stops cleanup for that file.

### S1 — Remove The Unproven React Authority Rewrite, Preserve Proven Work

Behavior/capability:

- restore the smallest existing selection flow consistent with one pane worker;
- remove authority epochs/owners, attempt counts, three-attempt retry,
  pending/acknowledged authority, navigation authority reconciliation, and
  selection settlement maps;
- retain render-source correlation, actual paint fulfillment, truthful scrubbed
  diagnostics, the search UX fix, and shared-construction retry;
- rewrite/remove tests and telemetry that only validate the parked model.

Before subtraction, write a symbol/hunk manifest for every dirty file with
`keep`, `park`, `rework`, or `unresolved`. Cleanup cannot start with an
`unresolved` hunk. Restore the committed two-rAF selection scheduling semantics;
diagnostics remain observational. A timer/rAF scheduling change requires
separate measured evidence and is not part of authority removal.

Likely write surface is limited to the already dirty files. Do not modify
comm-session, demand-policy/reconciler, persistence, or Pierre in this slice.

Proof:

- focused selection, render-fulfillment, telemetry-adapter and Browser tests;
- `pnpm -C BridgeWeb run check`;
- focused Swift shared-construction and diagnostic projection tests;
- `git diff --check`, an explicit static absence search for the parked
  authority vocabulary, and staged-path/hunk comparison against the manifest;
- `git diff --cached --check` plus post-commit status proving no parked or
  unrelated work entered the checkpoint.

Checkpoint commit: reduced checkpoint after all focused gates are green.

### S2 — Evidence-Gated Restored-Pane Root Cause

Start with a fresh oq4s marker, one restored candidate, and one untouched owned
sibling. Before editing, distinguish
the following at the same PID/binary/marker:

```text
pane row active + no tab/arrangement/drawer owner
  -> persistence ownership defect; no Bridge controller/worker exists

pane owned + foreground + no bootstrap/worker-ready/stream open
  -> initial-bootstrap recovery seam

pane owned + bootstrap/stream open + package/publication present
  -> inspect pane-local command receipt, demand and terminalization
```

The strategy-neutral SQLite discriminator joins `pane`, `tab_pane`,
`arrangement_layout_pane`, and `drawer_pane` by exact pane id. Raw identifiers
remain local and are not exported.

Candidate correction A, only if evidenced:

- red integration path spans app -> page handshake -> pane runtime -> comm
  session; it proves initial bootstrap is correlated once, worker failure asks
  for exactly one replacement, the same pane runtime accepts a fresh worker and
  capability, the old capability/port retires and rejects late messages, queued
  commands post once after replacement-ready, and existing worker
  reconciliation re-emits active surface/source/selection/viewport facts;
- open `bridge-app.tsx`, `bridge-page-handshake.ts`, `bridge-pane-runtime.ts`,
  and `bridge-pane-comm-worker-session.ts` only when same-PID evidence selects
  this boundary. The already-green session-only replacement test cannot prove
  the pane-runtime acceptance seam.

Candidate correction B, only if it blocks the tested restored pane and the
scope gate is explicitly accepted:

- red test proves close-tab panes retained only for undo cannot remain
  `.active` without tab/drawer ownership and undo restores residency;
- likely production owner is
  `WorkspaceSurfaceCoordinator+ActionExecution.swift`;
- do not attach arbitrary orphan panes during restore.

If the exact restored test pane is owned, candidate B is a separate follow-up
and does not expand this PR merely because other orphan rows exist.

If cleanup eliminates the wedge and neither restored candidate reproduces a
durable product defect, record a no-fix receipt and continue. Do not manufacture
a regression or correction.

Checkpoint commit: one evidenced root-cause fix with focused red/green proof,
or no product commit when the no-fix exit applies.

### S3 — Packaged WKWebView E2E Green

Use only:

```text
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

Require strict LaunchServices; final HEAD/bundle/executable/PID/marker/fixture
digest; a 257-file hierarchical fixture with all 257 files changed before app
launch and a verifier floor of at least 100 initial Review diffs; selection,
early/middle/final traversal, content materialization and correlated painted
source; zero page errors; and runner/verifier exit 0. This deterministic fixture
proves File plus one fresh multi-file Review pane under repeatable load; it does
not substitute for the restored-plus-fresh two-Review-pane oq4s proof against
the actual current worktree.

Peekaboo may supplement visual evidence but never substitutes for the verifier.
Do not terminate a preserved failing candidate until its sibling-pane and
marker evidence are collected or a fully built replacement is ready.

Checkpoint commit and push only after this gate is green.

### S4 — Actual Worktree, Two Review Panes, Real Interaction And Metrics

Launch only the current worktree identity:

```text
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Bind the run to `oq4s`, the fresh PID, executable, marker, current HEAD/diff,
machine/runtime identity, and a digest of the actual multi-file worktree state.

Resolve `<data-root>/ipc/runtime.json` from the runner state and require
`agentstudio-ipc --metadata <metadata> auth-status` to report
`authenticated: true` and `accessMode: unsafeDebug` before control. This mode
is permitted only for the isolated DEBUG oq4s process. Packaged authentication
proof remains escrow/persistent-socket based.

Use semantic IPC for exact pane/activity state and supported control. The user
supplies heavy interaction when present; Peekaboo is screenshot-only unless the
user explicitly authorizes input automation. Then:

1. identify an owned restored Review pane for this worktree;
2. if no owned restored pane exists, create one normally, prove tab/drawer
   ownership, close it cleanly, relaunch the same data root, and use that pane
   as the restored candidate without modifying unrelated orphan rows;
3. create a second fresh Review pane for the same worktree through the normal
   product command path with the identical resolved base/head, query mode,
   filters, path target and package-affecting selectors;
4. capture distinct pane/worker/publication identities locally and prove exact
   semantic-key/epoch equality in the deterministic Swift integration test;
   runtime proof is one build plus two joins/leases in an invalidation-free
   marker window, not raw semantic-key export;
5. click early/middle/late files in each pane;
6. perform heavy forward/backward scrolling in each pane;
7. switch focus between panes and leave one inactive long enough to prove
   suspension, then return and prove resumption;
8. preserve a wedged pane and compare its sibling before stopping anything.

Collect marker-scoped counts and histograms for startup/metadata,
click-to-visible, scroll-to-visible, demand queue/inflight/deferred/stale/abort,
content fetch/materialization, selected source paint, package/build count,
worker tasks, leases/residue, telemetry loss, frame/main-thread behavior and
process/attributed retained memory.

The existing `performance.bridge.web.review_content_demand` adapter has no
production caller and therefore cannot be cited as live demand proof. Use
existing comm-worker/session snapshots and `performance.bridge.worker.task`
for current selected/visible queue evidence. Production nearby/background/
abort/cap telemetry is part of the next-PR plan, not an instrumentation detour
in this stabilization slice.

Do not run startup-action verifiers against this plain interactive launch.
Their contracts require mutually exclusive startup actions and receive
separate fresh launches in S5. If an existing verifier does not expose a
required already-emitted metric, extend that verifier and its permanent script
tests. Do not create another harness or scrape raw user data.

Exploratory manual clicks/scrolls may use fewer than 100 samples to diagnose a
wedge. They cannot satisfy the final p95/p99 row. Final percentile evidence
must use the accepted representative workload with the minimum sample counts.

Checkpoint: actual-worktree two-pane evidence artifact plus any narrowly
required verifier change; commit/push if files changed and gates are green.

### S5 — Current-PR Capacity, Lifecycle And Stabilization Performance

Reuse the existing controlled browser and packaged LaunchServices workload
surfaces rather than creating a Cartesian benchmark matrix. Fold the actual
oq4s two-pane run into the native/manual stabilization row; do not mislabel it
as the deterministic fixture workload.

The deterministic current-PR percentile owner is exactly:

```text
BRIDGE_VIEWER_WORKTREE_PERFORMANCE_ONLY=1 pnpm -C BridgeWeb run test:dev-server:worktree
```

Extend only this existing workload, its result types, and
`interaction-performance.ts`/review performance verifier to capture >=100
Review click and >=100 Review scroll samples plus already-emitted per-sample
selection and selected/visible queue waits. The artifact must bind final SHA,
fixture/worktree digest, runtime, machine and sample counts. The packaged
journey remains correctness plus descriptive timing in this PR; it is not a
second percentile workload.

Run each startup diagnostic as its own fresh launch/marker after the
interactive oq4s evidence is safely frozen:

```text
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke mise run run-debug-observability -- --detach
mise run verify-bridge-review-journey-smoke
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-to-file-view-observability-smoke mise run run-debug-observability -- --detach
mise run verify-bridge-mode-idle-smoke
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation mise run run-debug-observability -- --detach
mise run verify-bridge-product-paint-correlation
```

Each launch gets a fresh state file, PID, marker and successful
`verify-debug-observability`. Close one verified diagnostic candidate before
starting the next; never stop a preserved failing candidate before its sibling
evidence is frozen.

Prove:

- exact shared Review construction count for duplicate panes;
- distinct pane publications/workers and independent cancellation;
- current-epoch invalidation/reacquisition;
- hidden suspension through IPC-observed
  `foreground -> loadedHidden -> foreground`, foreground-work epoch advance,
  producer/task/lease/queue/receipt/ACK drainage, and repaint after refocus;
  mode-idle proves Review/File idleness but cannot substitute for this pane
  lifecycle proof;
- restored/fresh selected-content and worker-queue p50/p95/p99, with final hard
  claims only where sample policy is met;
- zero >=50 ms web long tasks;
- descriptive process RSS sampled with `/bin/ps -o rss= -p <oq4s-pid>` at
  settled baseline, duplicate-pane peak, post-close drainage and final idle;
  record that macOS reports KiB and do not invent worker/Pierre/CoW precision;
- zero failed-session, lease, waiter, queue, receipt, or tombstone residue;
- telemetry loss within accepted stop lines.

The following remain explicitly open for the next demand-lane PR and cannot be
claimed by this checkpoint: nearby/background cohorts, global visible-start
cap, obsolete viewport abort, real Review Pierre/Shiki rank, production
byte-owning cache, three-launch/50-attempt demand workload, and full
worker/Pierre/CoW/process memory attribution.

Checkpoint commit/push after S10 evidence is closed.

### S6 — Final Local Hard Cut And Quality

Run in order:

```text
pnpm -C BridgeWeb run test
pnpm -C BridgeWeb run check
pnpm -C BridgeWeb run test:browser
pnpm -C BridgeWeb run test:e2e
pnpm -C BridgeWeb run build
pnpm -C BridgeWeb run audit:assets
mise run test-webkit -- --filter WebKitSerializedTests/BridgeProductRealGitFileAndReviewWebKitTests
mise run lint
mise run build
mise run test
```

Also run the existing static/dependency/asset audits for one worker, no legacy
owners, no Pierre change, Swift/agentstudio-git production data, and no
production TS Git/Worktrunk path. Every focused Swift filter must execute a
nonzero test count. Unrelated red gates invoke the repository scope guard; do
not edit unrelated infrastructure.

At the final implementation head, rerun both freshness-sensitive owners:

```text
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
BRIDGE_VIEWER_WORKTREE_PERFORMANCE_ONLY=1 pnpm -C BridgeWeb run test:dev-server:worktree
```

Checkpoint commit/push after final local proof.

### S7 — Provisional PR/CI Candidate, Handoff And Independent Review

Push the locally green candidate, create/update the PR, and obtain a green CI
candidate. Prepare the exact-head `implementation-handoff` before review, then
send it to one fresh independent agent. Use
`shravan-dev-workflow:implementation-review-swarm` on that exact pushed head.
Review lanes cover native/shared construction, pane worker/web authority,
concurrency/reliability, security/static cut, and proof honesty.

The parent validates every finding. Apply at most one bounded remediation pass,
commit/push, and do not start a second external review loop.

### S8 — Final Freshness Join And PR Readiness

Use `shravan-dev-workflow:implementation-pr-wrapup` to update/create the PR,
watch checks at the repository-approved interval, inspect comments and thread
resolution, confirm mergeability and artifact identity at the exact head, and
stop at ready/not merged.

After any S7 remediation, rerun every affected lower/runtime/packaged/
performance/CI gate, then rebind the handoff to the final SHA with commands,
counts, marker identities, accepted/rejected review findings, open non-blocking
follow-ups, and the next-PR demand-lane plan. Even with no remediation, verify
the final PR head equals the reviewed, packaged and performance-proven head.

## 7. Execution DAG

```text
gate 0: verify HEAD/status/source paths + preserve full recovery snapshot
  |
  v
S1 reduce dirty checkpoint to accepted ownership model
  |
  +--> focused BridgeWeb proof
  +--> focused Swift/shared-construction/diagnostic proof
  |
  v
S2 fresh oq4s same-PID restored/fresh boundary capture
  |
  +--> evidenced comm-session fix OR
  +--> evidenced pane-local terminalization fix OR
  +--> scope-gated persistence fix
  |
  v
S3 packaged WKWebView E2E green -> checkpoint/push
  |
  v
S4 actual-worktree two-pane clicks/heavy-scroll/metrics
  |
  v
S5 stabilization workload + shared capacity/lifecycle/descriptive memory
  |
  v
S6 full local hard cut
  |
  v
S7 provisional PR/CI + exact-head handoff + independent review + at most one remediation
  |
  v
S8 affected gate reruns + final freshness join + PR readiness; do not merge
```

Parallel implementation is deliberately limited while the dirty files overlap.
After S1, read-only metric reduction, Swift tests, and BridgeWeb tests may run in
parallel; production edits remain serial until the first missing boundary is
proven.

## 8. Reliability, Security And Recovery

Threat context:

- entry points: debug IPC metadata/socket, one-shot packaged escrow, Git-backed
  worktree fixtures, worker messages, OTLP exporters, verifier inputs and the
  private recovery ref;
- untrusted inputs: file paths/names/content, Git object data, persisted pane
  topology, worker/browser messages and fixture-generated source;
- privileged assets: same-user pane control, IPC capability/token, local Git
  recovery objects, oq4s data root and scrubbed observability evidence;
- invariants: DEBUG unsafe IPC is same-UID and allowlisted; packaged control is
  authenticated; replacement bootstrap rotates capability and rejects replay;
  raw ids/paths/source never enter OTLP, commits, PR text or handoffs; the
  private recovery ref is local-only;
- non-goal: no new trust boundary, IPC method, token lifetime or export field.

- Preserve the full dirty snapshot until the PR-ready head is pushed and
  independently reviewed.
- Do not export raw paths, pane ids, worktree ids, source, hashes, payloads,
  errors, tokens, or capabilities through OTLP. Use counts, booleans, enums,
  durations and deterministic safe hashes only.
- Authenticated semantic IPC and one-shot escrow remain the only packaged
  control path.
- Do not hold locks across awaits; stale generations cannot cache or publish;
  cancellation must terminalize and release capacity exactly once.
- Hidden/inactive panes keep local presentation state but start no background
  work until foreground.
- If three scoped fixes fail, stop implementation and reconverge on the model.

## 9. Blocked And Stop Conditions

Block/reconverge when:

- live code contradicts the accepted architecture;
- a required correction belongs outside the approved code path;
- Pierre, a File cap, a new compatibility owner, or timeout inflation appears
  necessary;
- the exact restored pane cannot be distinguished from an unowned orphan;
- continuing risks user data or requires deleting the oq4s data root;
- an unrelated required gate fails and would require infrastructure edits.

Complete only when every material matrix row is green at the exact PR head,
the independent review/remediation cycle is closed, CI and threads are clean,
mergeability is proven, the handoff is prepared, and the PR is ready but not
merged.
