# Bridge comm-worker cutover goal details

Goal id: `2026-07-05-bridge-comm-worker-cutover`

## Objective

Finish the BridgeViewer local-first comm-worker hard cutover in this branch:
the FE owns only local render slices and frame-budgeted apply, the comm worker
owns Bridge protocol/cache/demand/retry/telemetry truth, and Swift remains the
metadata/content server. The final terminal is PR-ready proof, not merge.

## Required Reading

- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
- `docs/plans/2026-07-04-local-first-comm-worker.md`
- `docs/specs/bridge-viewer-transport/performance-demand-lanes.md`
- `tmp/review-handoffs/2026-07-04-bridge-start-luna338-demand-queue-redesign/implementation-handoff.md`

## Current Workflow

Current workflow: `shravan-dev-workflow:implementation-execute-plan`

Next workflow after implementation proof: `shravan-dev-workflow:implementation-review-swarm`

Terminal condition: implementation complete, required proof gates pass or are
explicitly blocked by out-of-scope infrastructure, implementation review
findings addressed or explicitly rejected, PR created or updated and proven
ready, and merge not performed without explicit user authorization.

## Current Re-Anchor

- HEAD at setup: `5016e59c docs(plan): reanchor worker prep budget spec`.
- Worktree at setup: clean.
- Spec line count: 1192.
- Plan line count: 1724 before this setup edit.
- F0 diagnostic scaffolding exists.
- F1 live worker-fetch scheme proof is fresh on current HEAD after
  `2c03639d`: marker `debug-observability-oq4s-1783418131-7443`, PID `11885`,
  `mise run verify-debug-observability` passed, and
  `mise run verify-bridge-worker-fetch-scheme-smoke` passed with worker fetch
  and held-open streamed read both observing 82 bytes.
- G1-G4 have landed through the File View content protocol cutover checkpoint.
  Remaining implementation gates are Review browser-proof closure, G5 shared
  demand membership cutover, G6 ordinary script-message RPC deletion, and final
  browser/native perf and review proof.

## Requirements / Proof Matrix

Requirement / claim: F1 worker-originated `agentstudio://` scheme fetch and
stream proof passes before G content-byte cutovers.
Proof source: `mise run observability:up`, diagnostic debug launch, `mise run
verify-debug-observability`, `mise run verify-bridge-worker-fetch-scheme-smoke`.
evidence source: parent-run command output and Victoria marker.
freshness guard: latest `tmp/debug-observability/latest-observability.env`
marker for this worktree; kill only exact reported PID if a debug app is alive.

Requirement / claim: G1 typed shell is complete without production ownership.
Proof source: targeted Vitest command for `BridgeWeb/src/core/comm-worker/*`
G1 unit tests plus `pnpm --dir BridgeWeb exec tsc --noEmit`.
evidence source: parent-run command output; red-first for missing tests.
freshness guard: current diff and line-count/source-scan output.

Requirement / claim: no React/main Bridge data Zustand remains in converted
Review/File View surfaces after G3/G4/G6.
Proof source: source scans in the plan, Review/File View render-snapshot tests,
and TypeScript compile.
evidence source: parent-run scans/tests.
freshness guard: run scans after each cutover unit, not only at final wrap.

Requirement / claim: no TanStack/SWR/Apollo/equivalent async cache becomes the
Bridge worker RPC or visible-data authority.
Proof source: source scan plus `BridgeWorkerRpcLifecycleStore` tests proving it
stores only lifecycle/ack/rollback metadata.
evidence source: parent-run scans/tests.
freshness guard: run scan at G1 and after every G3/G4/G6 cutover.

Requirement / claim: comm-worker hot paths are O(delta) and selected-preemptible.
Proof source: worker-store tests, content-prep pump tests, selected queue-wait
telemetry, and large-prep selected-preemption test.
evidence source: parent-run tests and live metrics after wiring.
freshness guard: source scans for full snapshots/clones and Victoria metrics
from a fresh marker after native launch.

Requirement / claim: main remains a courier to Pierre and never parses/windows/
diffs/highlights content for converted surfaces.
Proof source: Pierre render-job/courier tests, source scans for parse/window/
diff/decode/highlight on main surfaces, clone/submit telemetry.
evidence source: parent-run tests/scans/metrics.
freshness guard: run after G3 and G4 cutovers.

Requirement / claim: final browser/native RPC cutover leaves only minimal
one-shot page-load bootstrap; ordinary Swift communication uses scheme POST and
streamed fetch.
Proof source: Swift recorded-traffic tests, source scans for script-message RPC
plane, native debug smokes.
evidence source: parent-run tests/scans/Victoria.
freshness guard: run after G6 on current HEAD.

## Stop And Block Rules

Stop only when the terminal condition is met, or when a proof gate fails outside
the approved scope and needs split/replan, or when F1 fails as a true WebKit
worker-fetch/streamed-response failure.

Blocked condition: same blocking condition repeats across three goal turns and
cannot make meaningful progress without user input or external state change.

Checkpoint rhythm: commit verified doc/setup and each verified implementation
slice; never stage unrelated files; record command, exit code, and pass/fail
counts before claiming a gate.

## Checkpoints

### 2026-07-05 G1 transfer DTO hardening

- Parent commit before checkpoint: `9958fb57 feat(bridge): harden comm worker boundary DTOs`.
- Sidekick review: `Goodall` reported one accepted P2 finding: transfer-list
  preparation accepted any `{ kind, transferDescriptors }` shape and tests used
  synthetic DTOs.
- Fix: `BridgeWorkerPierreRenderJob` now has Zod-derived schemas/types;
  `BridgeWorkerContracts` exports `BridgeWorkerPierreRenderJobEvent` as a real
  `serverWorkerToMain` DTO; `prepareBridgeWorkerStructuredMessage` accepts only
  `BridgeWorkerMainToServerMessage | BridgeWorkerServerToMainMessage`; unit and
  browser tests use the real DTO.
- Red evidence: `pnpm --dir BridgeWeb exec tsc --noEmit` failed with missing
  `BridgeWorkerPierreRenderJobEvent` and unused `@ts-expect-error`, proving the
  helper still accepted synthetic messages.
- Green evidence:
  `pnpm --dir BridgeWeb test src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-client.unit.test.ts src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts src/core/comm-worker/bridge-worker-rpc-lifecycle-store.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts`
  passed 9 files / 17 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 browser test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Source scans: async-cache scan had only absence-test matches; retry/refetch
  scan had absence-test matches and browser polling helpers; Zustand and
  rootSnapshot matches remain the known pre-G3/G4 legacy deletion targets.

### 2026-07-05 G2 telemetry route cutover

- Parent commit before checkpoint: `ff5054ce test(bridge): anchor transfer
  helpers to worker DTOs`.
- Sidekick review: `Sagan` classified remaining telemetry old-path matches.
  Accepted scope: remove production `system.bridgeTelemetry` / `rpcMethodName`
  telemetry transport, preserve generic script-message command plane for G6,
  and keep `system.bridgeTelemetry` only in negative/test assertions.
- Fix: telemetry bootstrap config now carries `endpointUrl`; browser/native
  Worktree/File and Review telemetry post to `agentstudio://telemetry/batch`;
  production `system.bridgeTelemetry` is removed from Swift bootstrap allowlist,
  `SystemMethods`, and `RPCRouter`; `BridgeApp` uses the comm-worker telemetry
  client facade and recorder client wrapper.
- Honest scope note: this is the G2 telemetry transport deletion slice. The
  current production wiring still constructs the telemetry client from the main
  app shell until later G slices wire the real comm-worker runtime underneath
  it. It is not a G3/G4/G5 content/demand cutover claim.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts src/foundation/telemetry/bridge-telemetry-bootstrap-config.unit.test.ts src/app/bridge-app-dev-telemetry.unit.test.ts src/bridge/bridge-page-handshake.unit.test.ts src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts`
  passed 6 files / 47 tests;
  `CI=true mise run test -- --filter "RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests|RPCRouterTests|BridgeBootstrapTests"`
  passed 88 tests / 6 suites;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  `pnpm --dir BridgeWeb exec oxlint --type-aware` exited 0 with existing
  warnings;
  `pnpm --dir BridgeWeb exec oxfmt --check .` passed;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/app/bridge-app-native-review-error.browser.test.tsx -t "emits accepted review intake telemetry when web telemetry is enabled"`
  passed 1 browser test.
- Browser blocker: the full
  `src/app/bridge-app-native-review-error.browser.test.tsx` file remains red
  with 3/14 failures: missing `bridge.activeViewerMode.update`, two content
  resource URL assertions, and act-guard noise. This matches the known
  native-review-error/browser-suite debt and is not treated as G2 green proof.
- Source scans: `rg -n "rpcMethodName" BridgeWeb/src Sources/AgentStudio
  Tests/AgentStudioTests` returned no matches. `system.bridgeTelemetry` remains
  only in negative/test helpers and rejection tests.

### 2026-07-05 F1 native worker-fetch proof

- Marker: `debug-observability-oq4s-1783258135-24055`.
- PID during proof: `24866`.
- Startup diagnostic action:
  `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke`.
- Green evidence:
  `mise run observability:up` passed with VictoriaMetrics, VictoriaLogs,
  VictoriaTraces, and OTel collector healthy;
  `mise run verify-debug-observability` passed for the marker;
  `mise run verify-bridge-worker-fetch-scheme-smoke` passed.
- Proof facts: worker-originated request used the content scheme and content
  resource kind; worker fetch completed successfully; held-open streamed
  response read completed successfully; worker observed returned byte count 82;
  stream first chunk byte count 82; stream reader was held open.
- Consequence: F1 unblocks G content-byte and streamed-response cutover work.
  This does not by itself prove Review/File View content/demand ownership has
  moved to the comm worker.

### 2026-07-05 G3 selected-click FE demand removal

- Parent commit before checkpoint: `c39a6dee feat(bridge): cut telemetry off
  script-message rpc`.
- Checkpoint commit: `3d6c5ffc feat(bridge): defer review selection content
  demand off click path` (unsigned; signed commit attempt failed before object
  write with `1Password: failed to fill whole buffer`).
- Sidekick: `Helmholtz` reviewed the browser-test wait shape read-only and
  confirmed the post-cutover sequence should be selected-path commit first,
  selected-content demand from the later layout effect second.
- Scope: first narrow G3 production cutover only. This removes selected-content
  FE demand/retry/parking from `beginForegroundReviewSelection`, so clicking a
  Review tree row only commits local selection/render-mode state and schedules
  mark-viewed. The old selected-content effect remains as a temporary legacy
  post-render demand owner until later G3 units move content truth fully to the
  comm worker.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-selection-controller.unit.test.ts`
  failed before production edits on the new source guard because the selection
  callback still referenced `startSelectedReviewContentDemand`,
  `setSelectedContentResourcesState`, foreground keys, abort refs, demand
  cancellation, and `resourceExecutor`.
- Green deterministic evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-selection-controller.unit.test.ts`
  passed 1 file / 5 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  `pnpm --dir BridgeWeb exec oxlint --type-aware src/app/bridge-app-review-selection-controller.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/app/bridge-app-review-viewer-mode.tsx src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
  passed;
  `pnpm --dir BridgeWeb exec oxfmt --check src/app/bridge-app-review-selection-controller.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/app/bridge-app-review-viewer-mode.tsx src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
  passed;
  `git diff --check` passed.
- Browser proof status: blocked, not green. The focused new browser proof
  `starts clicked Review foreground content demand after selected path commit`
  was updated to assert selected path before deferred content demand, but the
  Vitest Browser runner hung with repeated React act warnings and was
  interrupted (exit 130). A pre-existing focused browser test in the same file,
  `clicking a tree row fetches and renders the newly selected file`, also hung
  under a hard 45s shell alarm and exited 142 with the same act-warning storm.
  This is recorded as browser-harness debt for the Review browser file, not as
  passed G3 proof.
- Source/contract note: the unit guard proves the click callback no longer
  imports or receives selected-content demand owners. This is not a full G3
  content protocol cutover: Review main-thread selected/visible content
  controllers, root snapshot data, and package-first content paths remain known
  later G3 deletion targets.

### 2026-07-05 G3 worker select command handler seam

- Parent commit before checkpoint: `3d6c5ffc feat(bridge): defer review
  selection content demand off click path`.
- Checkpoint commit: `88835060 feat(bridge): handle selected facts in comm
  worker` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: narrow comm-worker core seam only. This introduces a typed
  `BridgeCommWorkerCommandHandler` that handles the converted `select` command
  by mutating the worker-local normalized store, publishing a typed
  `slicePatch` event, and returning a ready health ack. Non-selected commands
  still return health only and are not claimed as converted.
- Sidekick note: `Mill` recommended the next larger G3 unit should be the
  Review selected-content lane cutover, because selected/visible Review content
  controllers remain FE-owned. This checkpoint intentionally does not claim
  that deletion.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  failed before production edits because
  `./bridge-comm-worker-command-handler.js` did not exist.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts`
  passed 3 files / 6 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  `pnpm --dir BridgeWeb exec oxlint --type-aware src/core/comm-worker/bridge-comm-worker-command-handler.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed;
  `pnpm --dir BridgeWeb exec oxfmt --check src/core/comm-worker/bridge-comm-worker-command-handler.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed;
  `git diff --check` passed.
- Source/contract note: the handler boundary returns only
  `BridgeWorkerServerToMainMessage` DTOs. The select test asserts the emitted
  messages do not contain `rowById`, `orderedIds`, `rootSnapshot`, or `allRows`.

### 2026-07-05 G3 command handler P1 review fixes

- Parent commit before checkpoint: `88835060 feat(bridge): handle selected
  facts in comm worker`.
- Checkpoint commit: `7db5da64 fix(bridge): reject incomplete comm worker
  commands` (unsigned; previous signed commit attempts in this session failed
  before object write with `1Password: failed to fill whole buffer`).
- Sidekick: `Copernicus` reported accepted P1 findings: the command handler
  silently returned ready for unimplemented non-select commands, and the handler
  had no stale/replayed request rejection before mutation. It also classified
  the prior handler-only checkpoint as prep, not a G3 deletion-backed hard
  cutover. This state file now preserves that label.
- Fix: `viewport` now mutates worker-local viewport state and emits a typed
  viewport `slicePatch`; `hover`, `markFileViewed`, and `mode` return degraded
  health instead of ready; stale epochs and replayed request ids are rejected
  before store mutation or slice publication.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  failed with 3/4 red tests before production edits: viewport returned only one
  ready health event, unsupported commands returned ready instead of degraded,
  and a stale select emitted a `slicePatch`.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed 1 file / 4 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts`
  passed 3 files / 9 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  `pnpm --dir BridgeWeb exec oxlint --type-aware src/core/comm-worker/bridge-comm-worker-command-handler.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed;
  `pnpm --dir BridgeWeb exec oxfmt --check src/core/comm-worker/bridge-comm-worker-command-handler.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed;
  `git diff --check` passed.
- Remaining scope note: worker entry still uses the inert port protocol and the
  Review selected-content lane remains FE-owned. The next real G3 unit is the
  Review selected/viewport/render-snapshot cutover with deletion-backed proof.

### 2026-07-05 G3 Review selection/viewport render-snapshot cutover

- Parent commit before checkpoint: `7db5da64 fix(bridge): reject incomplete
  comm worker commands`.
- Scope: first deletion-backed G3 Review display-fact cutover. Review mode now
  derives selection and viewport render slices from
  `BridgeMainRenderSnapshotStore` via
  `useBridgeReviewRenderSnapshotController`, publishes typed `select` and
  `viewport` command DTOs through `BridgeCommWorkerCommandHandler`, and no
  longer reads Review selection/viewport display facts from the legacy
  main-thread Review Zustand store selectors. Selection and viewport both write
  the main render snapshot locally before worker publication, preserving the
  R41 local-first paint contract when the handler later becomes a real worker
  boundary.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts`
  failed 1/12 before the production viewport-local-first fix because the new
  guard expected `renderSnapshotStore.setLocalViewport` before
  `publishWorkerMessages`.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 1 file / 12 tests after the viewport-local-first fix;
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-selection-controller.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed 4 files / 24 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scan:
  `rg -n "selectBridgeReviewSelectionSlice|selectBridgeReviewViewportSlice|viewerActions\\.setMountedItemIds|viewerActions\\.setSelectedItemId\\(|viewerActions\\.setRenderMode\\(" BridgeWeb/src/app BridgeWeb/src/review-viewer`
  shows no converted Review selection/viewport store selector use in
  `BridgeReviewViewerMode`; remaining matches are source guards, legacy store
  definitions/tests, and panel render-mode chrome actions.
- Remaining scope note: this does not complete G3 content protocol ownership.
  Review selected/visible content controllers, package-first content paths, and
  the worker-entry cutover remain later G3/G6 work.

### 2026-07-05 G3 Pierre courier seam

- Parent commit before checkpoint: `d8b571e9 feat(bridge): route review
  selection through render snapshot`.
- Scope: narrow G3 courier seam only. Adds `BridgeWorkerPierreCourier` as the
  typed main-thread route for worker-prepared `BridgeWorkerPierreRenderJob`
  values and wires Review render-snapshot message application so
  `pierreRenderJob` events are no longer dropped. The controller still applies
  only `slicePatch` messages to `BridgeMainRenderSnapshotStore`; health and
  subscription messages remain no-op display events.
- Sidekick: `Averroes` reviewed the seam read-only. Accepted concerns folded in:
  keep the courier at the render-snapshot dispatcher boundary, do not teach
  `BridgeMainRenderSnapshotStore` about Pierre, source-scan the current
  main-thread content/materialization helper names, and avoid claiming selected
  content protocol cutover while legacy selected/visible content controllers
  remain live.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts`
  failed before production edits because
  `./bridge-worker-pierre-courier.js` did not exist.
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed before controller edits because
  `applyBridgeWorkerMessagesToMainRenderSnapshotStore` was not exported and
  still dropped `pierreRenderJob`.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 5 files / 20 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed;
  source scan over the courier/controller for main-thread content processors
  returned no matches.
- Remaining scope note: this is not the full G3 Review content protocol
  cutover. The default courier adapter is a typed pending edge until a later
  content-protocol unit supplies the actual Pierre enqueue integration and
  deletes old FE selected/visible content demand owners.

### 2026-07-05 G3 unsupported Pierre courier P1 fix

- Parent commit before checkpoint: `868e4694 feat(bridge): route worker pierre
  jobs through courier`.
- Checkpoint commit: `02ae5a6c fix(bridge): fail unsupported pierre courier
  loudly` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: accepted Planck P1 review finding. The default Review Pierre courier
  fallback no longer returns fake enqueue success; it throws if a worker
  `BridgeWorkerPierreRenderJob` arrives before an actual Pierre adapter has
  been installed.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-render-snapshot-controller.unit.test.ts -t "default unsupported courier fails loudly"`
  failed before the production fix because the default fallback did not throw.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts`
  passed 2 files / 5 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Remaining scope note: this keeps the seam honest; it does not provide the
  actual Pierre adapter or selected-content protocol cutover.

### 2026-07-05 G3 selected availability handoff

- Parent commit before checkpoint: `02ae5a6c fix(bridge): fail unsupported
  pierre courier loudly`.
- Checkpoint commit: `1673b645 feat(bridge): drive selected availability from
  worker snapshot` (unsigned; signed commit attempt failed before object write
  with `1Password: failed to fill whole buffer`).
- Scope: deletion-backed selected display/pause handoff only. Review mode now
  derives `selectedContentAvailability` from
  `BridgeMainRenderSnapshotStore.contentAvailabilityById`; selected canvas
  content loading, selected unavailable path, and visible hydration pause
  decisions read that worker-owned availability display copy instead of
  `SelectedContentResourcesState.status`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  failed 2 files / 9 tests before production edits because selected loading and
  unavailable paths still read `selectedContentResourcesState`;
  `pnpm --dir BridgeWeb exec tsc --noEmit` failed because the
  `selectedContentAvailability` prop/export did not exist.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts`
  passed 4 files / 46 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scan: `rg -n "selectedContentResourcesState" BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts`
  returned no matches after the handoff.
- Remaining scope note: actual selected content resources, selected content
  demand effects, content bytes, and Pierre render job generation remain
  legacy-owned until the later G3 content-byte/Pierre adapter cutover.

### 2026-07-05 G3 worker review content metadata index

- Parent commit before checkpoint: `1673b645 feat(bridge): drive selected
  availability from worker snapshot`.
- Checkpoint commit: `92a1e020 feat(bridge): index review content metadata in
  worker store` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: narrow G3 metadata-prep slice only. The Review render-snapshot
  controller maps `BridgeReviewPackage` item descriptors into strict
  `BridgeWorkerReviewContentMetadata` DTOs, the comm-worker command handler
  initializes the worker-local store with that normalized metadata, and selecting
  an item without worker metadata publishes `contentAvailability: unavailable`
  without adding selected demand. This does not fetch bytes, prepare Pierre
  render jobs, or move selected content bodies yet.
- Red evidence captured before production edits:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed because the metadata schema/type, `contentItems` props,
  `contentMetadataByItemId`, missing-metadata unavailable behavior, and
  `bridgeCommWorkerContentItemsFromReviewPackage` mapper did not exist;
  `pnpm --dir BridgeWeb exec tsc --noEmit` failed with the corresponding missing
  exports/properties.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts`
  passed 7 files / 59 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scan:
  `rg -n "itemsById|orderedItemIds|summary|groups|reviewPackage" BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches, proving the worker store/handler/contracts do not accept
  package-shaped snapshots in this slice.
- Remaining scope note: this is metadata indexing only. The worker still does
  not fetch content bytes, build `BridgeWorkerPierreRenderJob` values, or own
  the actual selected/visible content materialization path.

### 2026-07-05 G3 worker metadata eligibility sidekick fix

- Parent commit before checkpoint: `92a1e020 feat(bridge): index review content
  metadata in worker store`.
- Checkpoint commit: `a475ed28 fix(bridge): keep worker metadata demand
  eligible` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Sidekick: `Sartre` reported two accepted findings after the metadata
  checkpoint:
  - P1: selecting an item with missing metadata suppressed demand initially, but
    a later viewport rebuild restored a selected demand entry from `selectedId`.
  - P2: `BridgeWorkerReviewContentMetadata` still carried full `contentRoles`
    handles, including `resourceUrl`/`endpointId`, which made this prep slice
    look like content-handle transport rather than metadata eligibility.
- Fix: demand rebuilding is now metadata-eligibility aware for both selected and
  visible demand; worker review content metadata now carries only indexing facts
  (`itemId`, `path`, `language`, `cacheKey`, `sizeBytes`,
  `contentLineCountsByRole`) and excludes content handle/resource URL fields.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed 3 files / 3 tests before production edits: viewport restored
  `item-without-content-metadata: selected`, the metadata schema still required
  `contentRoles`, and the mapper output still contained `contentRoles`,
  `resourceUrl`, and `endpointId`.
- Green evidence:
  the same focused red tests passed 3 files / 11 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts`
  passed 7 files / 59 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scans:
  `rg -n "itemsById|orderedItemIds|summary|groups|reviewPackage|contentRoles|resourceUrl|endpointId" BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches;
  `rg -n "contentRoles|resourceUrl|endpointId" BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches.
- Remaining scope note: this makes the metadata-prep seam honest. A later G3
  content-byte/Pierre job unit must introduce a separate typed content request
  descriptor and transfer-list proof rather than reusing the metadata DTO for
  full content handles.

### 2026-07-05 G3 worker metadata content-role eligibility

- Parent commit before checkpoint: `a475ed28 fix(bridge): keep worker metadata
  demand eligible`.
- Checkpoint commit: `a00c6166 fix(bridge): gate worker demand by content
  roles` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: follow-up metadata eligibility hardening. `BridgeWorkerReviewContentMetadata`
  now includes `availableContentRoles` as a role-name summary only, still no
  full content handles/resource URLs. Demand rebuilding treats metadata with no
  available content roles as unavailable and ineligible for both selected and
  visible demand.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed before production edits because the schema rejected
  `availableContentRoles`, the mapper did not emit it, and a metadata-only item
  still received `selected:6` demand.
- Green evidence:
  the same focused set passed 4 files / 17 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts`
  passed 7 files / 60 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scans:
  `rg -n "itemsById|orderedItemIds|summary|groups|reviewPackage|\"contentRoles\"|resourceUrl|endpointId" BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches;
  `rg -n "\"contentRoles\"|resourceUrl|endpointId" BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches.
- Remaining scope note: content fetch descriptors remain a separate next slice.
  This checkpoint only makes worker demand eligibility precise without moving
  content handles into the metadata DTO.

### 2026-07-05 G3 worker content request descriptor seam

- Parent commit before checkpoint: `a00c6166 fix(bridge): gate worker demand by
  content roles`.
- Checkpoint commit: `ef23c859 feat(bridge): define worker content request
  descriptors` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: typed descriptor seam only. Added strict
  `BridgeWorkerReviewContentRequestDescriptor` for worker fetch identity and a
  Review package mapper that produces role-scoped descriptors separate from
  handle-free metadata. This slice does not wire live worker fetch, does not
  fabricate bytes, and does not build `BridgeWorkerPierreRenderJob` values.
- Sidekick: `Aristotle` reviewed the descriptor boundary read-only before
  commit. Accepted adjustment: trim unevidenced `mimeType` and handle `cacheKey`
  from the descriptor; keep fetch-required/safe-forward fields only:
  `itemId`, `role`, `handleId`, `reviewGeneration`, `resourceUrl`,
  `contentHash`, `contentHashAlgorithm`, `language`, `sizeBytes`, and
  `isBinary`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed before production edits because the descriptor schema/export and
  package-to-descriptor mapper did not exist.
- Green evidence:
  the same focused set passed 2 files / 10 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts`
  passed 9 files / 65 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scan:
  `rg -n "itemsById|orderedItemIds|summary|groups|reviewPackage|\"contentRoles\"" BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
  returned no matches.
- Remaining scope note: a real worker prep/job slice still needs item semantics
  (`itemKind`, `changeKind`, presentation), path/name, role line counts,
  language fallback, fetched bytes, rank/window/budget, and hash-based Pierre
  cache identity. This checkpoint intentionally only creates the typed fetch
  descriptor seam.

### 2026-07-05 G3 worker content fetch prep seam

- Parent commit before checkpoint: `ef23c859 feat(bridge): define worker content
  request descriptors`.
- Checkpoint commit: `be0ed71d feat(bridge): fetch review content in worker
  prep seam` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: worker-side fetch helper only. Added
  `fetchBridgeWorkerReviewContentResource`, which validates a typed content
  request descriptor, rejects binary descriptors before fetch, validates
  `agentstudio://resource/review/content/...` handle id and review generation
  before fetch, reads the response stream with the existing byte cap helper, and
  returns worker-owned text bytes. This still does not wire live demand, build
  Pierre render jobs, or call the main courier.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts`
  failed before production edits because `bridge-worker-review-content-fetch.js`
  did not exist.
- Green evidence:
  the same focused test passed 1 file / 3 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 8 files / 28 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scan:
  `rg -n "itemsById|orderedItemIds|summary|groups|reviewPackage|\"contentRoles\"|SelectedContentResourcesState|materializeBridgeCodeViewItem" BridgeWeb/src/core/comm-worker/bridge-worker-review-content-fetch.ts BridgeWeb/src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts`
  returned no matches.
- Remaining scope note: the next G3 unit must add semantic prep/job planning
  around these fetched bytes. Per Aristotle's sidekick analysis, job prep still
  needs item semantics, role selection, path/name, line counts, language
  fallback, demand rank, window, and budget before a real
  `BridgeWorkerPierreRenderJob` can be emitted.

### 2026-07-05 G3 worker render semantics descriptor seam

- Parent commit before checkpoint: `be0ed71d feat(bridge): fetch review content
  in worker prep seam`.
- Checkpoint commit: `54b0d4b3 feat(bridge): define worker render semantics
  descriptors` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: typed semantic descriptor seam only. Added strict
  `BridgeWorkerReviewRenderSemantics` and a Review package mapper that carries
  item-level render facts needed by later worker job planning: item kind, change
  kind, display/base/head paths, language fallback, and role line counts. It
  explicitly excludes content handles, resource URLs, handle ids, endpoint ids,
  and content hashes.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  failed before production edits because the render semantics schema/export and
  package mapper did not exist.
- Green evidence:
  the same focused set passed 2 files / 12 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 10 files / 70 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Source scans:
  broad worker-contract scan showed `handleId`/`resourceUrl` only in the request
  descriptor schema; targeted render-semantics block scan found no
  `contentRoles`, `resourceUrl`, `handleId`, `endpointId`, or `contentHash`.
- Remaining scope note: this is still prep-only. The next G3 unit can now require
  both content request descriptors and render semantics before planning any
  `BridgeWorkerPierreRenderJob`.

### 2026-07-05 G3 worker Pierre render job diff payload seam

- Parent commit before checkpoint: `54b0d4b3 feat(bridge): define worker render
  semantics descriptors`.
- Checkpoint commit: `98d88adf feat(bridge): model worker review diff render
  payloads` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: `BridgeWorkerPierreRenderJob` payload semantics only. Extended the
  Zod-derived render job payload union from single `textWindow` to
  `textWindow | diffTextWindow`, where Review diffs carry fixed
  `baseTextBytes` / `headTextBytes` `ArrayBuffer | null` fields. The builder
  now rejects `reviewDiff + textWindow`, rejects `fileText + diffTextWindow`,
  requires at least one diff side, and computes byte budget across all present
  sides. Transfer-list tests now declare both diff-side field paths and one-sided
  present-side-only paths. This does not wire live demand, content fetch
  aggregation, or Pierre adapter generation.
- Sidekick evidence:
  Pascal read the spec/plan/render-job/transfer/materialization files and
  confirmed that Review diff jobs must not fake a single text payload because
  current materialization is base/head-shaped and main is forbidden from
  reconstructing diffs.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts`
  failed before production edits because `diffTextWindow` was not accepted and
  `reviewDiff + textWindow` did not throw.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 4 files / 17 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Remaining scope note: the next G3 unit must build the actual worker prep
  planner from fetched role resources plus render semantics, including role
  selection, language fallback, composite diff identity, line/window budget, and
  `BridgeWorkerPierreRenderJob` emission. Do not emit fake Review diff jobs from
  a single resource.

### 2026-07-05 G3 worker Review Pierre job planner

- Parent commit before checkpoint: `98d88adf feat(bridge): model worker review
  diff render payloads`.
- Checkpoint commit: `5fb6081b feat(bridge): plan worker review pierre jobs`
  (unsigned; signed commit attempt failed before object write with `1Password:
  failed to fill whole buffer`).
- Scope: pure worker-local job planning only. Added
  `planBridgeWorkerReviewPierreRenderJob`, which consumes typed render semantics
  plus already-fetched role resources and emits bounded `BridgeWorkerPierreRenderJob`
  values. It plans modified/renamed/copied Review diffs only when both base and
  head resources are present, plans added/deleted as one-sided diffs, plans file
  render jobs from a single preferred resource, derives composite diff cache/hash
  identity, derives language fallback, and derives line windows from semantic
  role line counts and the job budget. This still does not fetch content, mutate
  the worker store, publish worker messages, or enqueue Pierre jobs.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts`
  failed before production edits because the planner module did not exist.
- Green evidence:
  the planner test passed 1 file / 4 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 12 files / 82 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Remaining scope note: the next G3 unit must wire this planner into the worker
  demand/content-ready path and emit typed `pierreRenderJob` messages with
  declared transfer fields. Keep Review/File View live cutovers separate and
  preserve the no-main-parse/window/diff/highlight rule.

### 2026-07-05 G3 worker Review Pierre job event prep

- Parent commit before checkpoint: `5fb6081b feat(bridge): plan worker review
  pierre jobs`.
- Checkpoint commit: `a91ca1b3 feat(bridge): prepare worker review pierre job
  events` (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: pure event-prep seam only. Added
  `prepareBridgeWorkerReviewPierreRenderJobEvent`, which calls the pure planner,
  returns `null` when no complete job can be planned, wraps a planned job as a
  schema-derived `BridgeWorkerPierreRenderJobEvent`, and prepares it through
  `prepareBridgeWorkerStructuredMessage` with transfer declarations derived from
  the actual payload. File-text jobs declare `job.payload.textBytes`;
  two-sided Review diffs declare both `job.payload.baseTextBytes` and
  `job.payload.headTextBytes`; one-sided diffs declare only the present side.
  This still does not fetch content, mutate worker store state, enqueue Pierre,
  or wire live demand.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts`
  failed before production edits with 4 failures because
  `prepareBridgeWorkerReviewPierreRenderJobEvent` was not a function.
- Green evidence:
  the focused planner test passed 1 file / 8 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 12 files / 86 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed.
- Sidekick review: `Kierkegaard` reviewed the working-tree diff read-only and
  returned `Verdict: ready`, with no accepted P0-P3 findings. It confirmed the
  helper stays pure, uses schema-derived DTOs, and derives transfer descriptors
  from `job.payload` only.
- Remaining scope note: the next G3 unit is the first real worker
  demand/content-ready integration point. It must consume fetched resources and
  semantics, call the event-prep seam, publish typed `pierreRenderJob` events,
  and keep old Review/File View live cutovers separate until their deletion sets
  are ready.

### 2026-07-05 G3 worker Review content-ready seam

- Parent commit before checkpoint: `a91ca1b3 feat(bridge): prepare worker
  review pierre job events`.
- Scope: worker-core content-ready composition only. Added
  `prepareBridgeWorkerReviewContentRenderJobEvent`, which consumes fetched
  resources plus render semantics and returns a prepared typed
  `pierreRenderJob` message with transfer list, without mutating the worker
  store or publishing ready. Added
  `commitBridgeWorkerReviewContentReadySlicePatch`, which takes an already
  prepared Pierre render job event and commits the ready row-paint and
  availability slice patch. This explicitly models the future caller contract:
  enqueue/accept the render job first, then commit ready. No live FE, Swift,
  worker-entry, or Pierre wiring was added.
- Red evidence:
  First red test failed because `bridge-worker-review-content-ready.js` did not
  exist. After sidekick review found a ready-before-courier contract issue, the
  revised focused test failed with 3 failures because
  `prepareBridgeWorkerReviewContentRenderJobEvent` did not exist.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts`
  passed 1 file / 3 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 5 files / 26 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 13 files / 89 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Sidekick review: `Zeno` first returned `needs fixes` for a P1/P2
  ready-before-courier ordering issue. The fix split prepare from ready commit.
  Zeno re-reviewed and returned `Verdict: ready`, with no accepted findings and
  both prior findings closed.
- Source scans:
  `rg -n "prepareBridgeWorkerReviewContentRenderJobEvent|commitBridgeWorkerReviewContentReadySlicePatch|bridge-worker-review-content-ready" BridgeWeb/src`
  showed only the new module and its unit test. A targeted scan for `any`,
  `unknown`, `postMessage(`, `fetch(`, `enqueue(`, live Review demand loaders,
  and legacy selected/visible content resource names in the new files returned
  no matches.
- Remaining scope note: the next G3 unit can add the worker-entry/runtime post
  seam that preserves prepared-message transfer lists. It must still avoid live
  FE selected/visible cutover until the Review deletion set is ready.

### 2026-07-05 G3 worker-entry prepared transfer-list post seam

- Parent commit before checkpoint: `5bf72aeb feat(bridge): stage worker review
  content ready events`.
- Scope: worker-entry/runtime post seam only. Added
  `postPreparedBridgeCommWorkerMessage`, which posts a
  `PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>` as
  `postMessage(message, [...transferList])`. Added
  `createBridgeCommWorkerScopePortAdapter`, and `bootstrapInertBridgeCommWorkerEntry`
  now uses it, so the scope adapter preserves transfer lists while one-argument
  inert health replies still use the one-argument post path. The port/scope
  `postMessage` contracts use DOM-style overloads rather than a loose optional
  protocol shape. No live Review/File View cutover, Swift transport change, or
  FE demand wiring was added.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts`
  first failed because `postPreparedBridgeCommWorkerMessage` was not a
  function. After sidekick review, the DOM-assignability guard failed under
  `pnpm --dir BridgeWeb exec tsc --noEmit` because the optional transfer-list
  signature did not match real `MessagePort` overloads. The scope-adapter
  regression then failed because `createBridgeCommWorkerScopePortAdapter` was
  not a function.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts`
  passed 1 file / 4 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/app/bridge-app.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed 14 files / 93 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Sidekick evidence: `Pauli` mapped the worker-entry transfer-list drop point
  to `bridge-comm-worker-entry.ts` and recommended a typed prepared-message
  post seam. `Faraday` confirmed no downstream imports/usages of
  `BridgeCommWorkerPort` or `BridgeCommWorkerGlobalScope` outside the entry
  file and new test. `Franklin` checked the DOM `postMessage` type surface; the
  implementation was tightened to overloads after this. `Boole` and `Tesla`
  returned `needs fixes` for the optional-transfer signature and missing
  scope-adapter proof; both findings were accepted and fixed with new red/green
  guards.
- Remaining scope note: the next narrow G3 unit can add selected-review
  runtime dispatch that posts a prepared Pierre job before committing the
  content-ready slice patch. It must still avoid app/review-viewer/native live
  cutover and avoid any Review/File View deletion-set claim until that unit is
  ready.

### 2026-07-05 G3 worker-selected review content-ready runtime dispatch

- Parent commit before checkpoint:
  `49338327 feat(bridge): preserve worker entry transfer lists`.
- Scope: worker-core selected-review runtime dispatch only. Added
  `dispatchSelectedBridgeWorkerReviewContentReady`, which looks up selected
  review render semantics, fetches only the descriptors needed for that render,
  posts the prepared `pierreRenderJob` with its transfer list, commits the
  worker-local content-ready slice, and posts the prepared slice patch with its
  transfer list. Added worker-store terminal availability publication so
  missing semantics, incomplete render inputs, and fetch failures do not strand
  the selected item in `loading`. The immediate select command handler remains
  synchronous local slice publication only (`slicePatch`, `health`); it does
  not emit a `pierreRenderJob` or ready availability. No live
  app/review-viewer/native wiring, Swift transport change, Review deletion-set
  claim, File View claim, or demand-membership cutover was added.
- Descriptor-selection rule:
  modified/renamed/copied diff items fetch `base` plus `head` only when both
  descriptors are present; otherwise they fetch nothing and publish
  `unavailable`. Added items fetch the first present of `head`, `file`; deleted
  items fetch the first present of `base`, `diff`; non-diff file renders fetch
  the first present of `head`, `file`, `diff`, `base`. Fallback roles are
  alternatives, not a batch.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts`
  first failed because `bridge-comm-worker-review-runtime.js` did not exist.
  The immediate-select guard initially failed for a bad health-regex assertion
  and was tightened to ban only `pierreRenderJob` plus ready availability.
  After the first green implementation, a new over-fetch regression assertion
  failed because a modified diff fetched the unnecessary `file` descriptor in
  addition to `base` and `head`. Sidekick review then drove three additional
  red checks: missing semantics left selected content at `loading`; incomplete
  two-sided diff descriptors left selected content at `loading`; fetch
  rejection escaped instead of publishing `failed`. A follow-up Poincare red
  assertion proved partial two-sided diffs still performed a wasteful
  single-side fetch before publishing `unavailable`.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts`
  passed 1 file / 5 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts`
  passed 2 files / 10 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 9 files / 45 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Sidekick evidence: `Confucius` returned `needs fixes` for the selected-item
  failure path leaving runtime state stuck at `loading`; this was accepted and
  fixed with terminal `unavailable` / `failed` availability publication.
  `Poincare` returned `needs fixes` for partial two-sided diffs fetching a
  single side before silently stopping; this was accepted and fixed by making
  modified/renamed/copied diff descriptor selection all-or-nothing for
  `base`/`head`.
- Remaining scope note: this still does not satisfy the full G3 Review content
  protocol cutover. The next unit must either wire this runtime through the
  worker command/entry path with a selected-first prep pump or continue building
  worker-only runtime seams, while preserving the hard-cutover rule for any live
  converted surface.

### 2026-07-05 G3 worker-selected review preparation pump seam

- Parent commit before checkpoint:
  `a6980bcf feat(bridge): dispatch selected review runtime content`.
- Scope: worker-core selected-review preparation scheduling only. Added
  `enqueueSelectedBridgeWorkerReviewContentReadyPreparation`, which admits the
  selected review content-ready runtime dispatch into `WorkerContentPreparationPump`
  as selected-ranked work. Added an injected command-handler scheduling hook so
  `select` can request deferred selected prep after local slice publication,
  while the immediate response remains `slicePatch` + `health` and never emits
  `pierreRenderJob` or ready availability. Added stale guards so deferred
  selected prep drops if `selectedId` and `demandByKey` no longer match
  `selected:<epoch>` before side effects or after async fetch. No live
  Review/app/native wiring, Swift transport change, Review deletion-set claim,
  File View claim, or full R60 ownership claim was added.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts`
  first failed because `bridge-comm-worker-review-preparation.js` did not exist.
  After the first helper, focused tests failed because the command handler did
  not call a scheduler hook, stale selected work still posted old `pierreRenderJob`
  and ready patches after selection changed during fetch, and skipped
  non-demand-eligible prep never resolved.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
  passed 2 files / 10 tests;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-worker-content-preparation-pump.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 11 files / 51 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Sidekick evidence: `Godel` recommended the smallest safe G3b boundary:
  selected prep behind the pump, immediate select still synchronous, no live
  wiring, stale guard against current `selectedId` plus
  `demandByKey == selected:<epoch>`, and skip non-demand-eligible scheduling.
  Those recommendations were accepted in the implementation. A final reviewer
  sidekick (`Erdos`) was dispatched before commit.
- Remaining scope note: this is still not the full G3 Review content protocol
  cutover and not full R60. The pump currently owns admission/ranking for the
  selected prep start decision; full async chunking/in-flight worker compute
  ownership, live worker entry drain, Review old-path deletion scans, and browser
  Review proof remain later G3 work.

### 2026-07-05 G3 worker runtime protocol selected-prep drain seam

- Parent commit before checkpoint:
  `873d6ac8 feat(bridge): enqueue selected review prep through worker pump`.
- Checkpoint commit:
  `a3190625 feat(bridge): drain selected review prep through worker protocol`
  (unsigned local commit after signing failed with
  `1Password: failed to fill whole buffer`).
- Scope: worker-core runtime protocol composition only. Added
  `registerBridgeCommWorkerRuntimePortProtocol`, which composes the typed
  command handler, worker-local store, selected Review content-ready
  preparation enqueue helper, and `WorkerContentPreparationPump` behind a
  `BridgeCommWorkerPort`. A `select` command now posts only immediate local
  `slicePatch` + `health` responses on the one-argument post path, schedules a
  selected prep drain, and the drain posts the prepared `pierreRenderJob` plus
  ready `slicePatch` through the same worker port with transfer lists preserved.
  No live Review app wiring, native Swift transport change, File View claim,
  Review old-path deletion, browser Review proof, or full R60 async/chunked
  compute ownership claim was added.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts`
  first failed because `bridge-comm-worker-runtime-protocol.js` did not exist.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-worker-content-preparation-pump.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-worker-review-content-ready.unit.test.ts src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  passed 12 files / 52 tests;
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts`
  passed 1 file / 1 test;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and `git diff --check`
  passed.
- Sidekick evidence: metrics sidekick `Lorentz` reported live marker
  `debug-observability-oq4s-1783262841-48835`, PID `53012`, with Victoria
  services healthy but only startup/package-apply Bridge telemetry under the
  marker. It found no click-to-paint, scroll, event-loop, or jank rows, so the
  current live telemetry neither supports nor refutes the user-reported Review
  click/scroll stalls. This is a telemetry coverage gap to address before any
  performance claim.
- Remaining scope note: this closes a worker-boundary proof seam between
  selected command handling and prepared transfer-list content-ready posts. It
  still does not convert live Review content protocol ownership, delete legacy
  Review package-first/demand/retry paths, or prove browser/native Review UX.

## 2026-07-05 16:41 ET - G3 FE selected retry loop deletion

- Checkpoint commit:
  `9ca120c0 feat(bridge): delete selected review FE retry loop`
  (unsigned local commit after signing failed with
  `1Password: failed to fill whole buffer`).
- Scope: deleted the app-side selected Review descriptor-registration retry
  owner and its callback seam through Review intake/controller code. Added a
  source-structure guard so these FE retry owner symbols do not return:
  `selectedContentRetryVersion`, `selectedContentRetryScheduledRef`,
  `scheduleSelectedContentRetry`,
  `shouldRetrySelectedReviewContentAfterDescriptorRegistration`, and
  `retrySelectedContentAfterDescriptorRegistration`.
- Sidekick finding accepted: removing the FE retry owner exposed a partial
  cutover hazard where non-runtime command handling could publish selected
  `contentAvailability: loading` without any selected-prep scheduler able to
  complete it. Fixed by making selected demand/loading conditional on an
  installed selected-prep scheduler; non-runtime select now publishes selection
  only for demand-eligible content. Old package-first selected demand
  `deferred` results now map to terminal failed state instead of parking
  `SelectedContentResourcesState` in loading.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app.unit.test.ts`
  failed 3 tests for the intended reasons: false contentAvailability loading,
  unwanted selected demand, and deferred-to-loading mapping.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app.unit.test.ts src/app/bridge-app-review-content-validity-key.unit.test.ts src/app/bridge-app-review-metadata-package.preservation.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts`
  passed 10 files / 125 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `pnpm --dir BridgeWeb exec oxfmt --check ...` passed;
  scoped `pnpm --dir BridgeWeb exec oxlint --type-aware ...` exited 0 with the
  pre-existing `bridge-app-review-controller.ts:575 consistent-return` warning;
  `git diff --check` passed; the retry-owner `rg` deletion scan returned no
  matches outside the source-structure guard.
- Browser proof note: the Review Vitest Browser integration proof was attempted
  before this fix and interrupted with exit 130 during the known React act
  warning/harness storm. Do not treat this commit as browser/native Review UX
  proof.
- Remaining scope note: live Review still uses the immediate command handler in
  this path; this slice prevents false non-runtime loading and removes the old
  FE retry owner. It does not claim full live Review content protocol cutover,
  browser smoothness, or native Swift proof.

## 2026-07-05 20:55 ET - G3 Review runtime-port selected/viewport checkpoint

- Scope: live Review selected and viewport facts now dispatch through
  `registerBridgeCommWorkerRuntimePortProtocol` via a runtime-port dispatcher
  instead of constructing and calling the comm-worker command handler directly in
  the app controller. The selected no-courier path keeps worker preparation and
  selected demand disabled while still publishing a selected
  `contentAvailability: loading` display patch. Legacy selected-content settle
  is mirrored back into the render snapshot as selected availability
  `loading|ready|failed` only for the current selected item/content key, so the
  no-courier path does not stay pinned in loading while the old selected loader
  remains live.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  first failed because no-courier selected availability was null and the store
  could not publish loading availability without selected demand;
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts`
  then failed because
  `selectedContentAvailabilityFromLegacySelectedContentState` was missing;
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
  then failed because
  `applyLegacySelectedContentAvailabilityToMainRenderSnapshotStore` was missing.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-runtime.unit.test.ts`
  passed 9 files / 81 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware`, scoped `oxfmt --check`, and
  `git diff --check` passed; source scans found no direct
  `createBridgeCommWorkerCommandHandler` or `.handleMessage(` usage and no
  inline R57 512 KiB / 400-line budget literals in
  `bridge-app-review-render-snapshot-controller.ts`; production async-cache scan
  over app/review/core comm-worker paths returned no matches.
- Full-suite / browser proof note:
  `pnpm --dir BridgeWeb exec vitest run` was attempted and reached 148/149
  files, 994/995 tests passing; the sole failure was the unrelated existing
  line-cap guard for `src/core/demand/bridge-resource-executor.unit.test.ts:
  1060`. Review browser Vitest integration was attempted and interrupted after
  several minutes with exit 130 during the known React act-warning/harness storm,
  so this checkpoint must not be treated as browser/native Review UX proof.
- Sidekick evidence: Peirce found the first loading-only patch incomplete
  because no-courier mode could stay stuck in loading. Noether reviewed the
  corrected diff and returned ready/no findings, with the explicit caveat that
  this is a checkpoint-safe legacy selected-availability display mirror, not the
  final R56-only-worker-patch end state.
- Remaining scope note: this does not claim full Slice G3 / R44 worker-content
  cutover, full R56, browser/native proof, F1/G final RPC cutover, or R57/R60
  telemetry/performance proof. Review main-thread Zustand and legacy selected
  content demand remain live deletion targets for later G3/G4 work.

## 2026-07-05 21:19 ET - G3 no-courier selected loading shim deletion

- Commit: `02ffeb15 feat(bridge): delete review no-courier loading shim`
  (unsigned local fallback because 1Password signing failed with
  `failed to fill whole buffer` before the commit object was written).
- Scope: deleted the temporary no-courier selected loading compatibility path
  from live Review runtime wiring. Selected Review facts now always create
  selected demand/loading for eligible worker content and schedule selected
  preparation through the worker runtime path. The runtime/command/store no
  longer expose `selectedContentLoadingAvailabilityEnabled`,
  `selectedContentPreparationEnabled`, `selectedLoadingAvailabilityEnabled`, or
  `selectedPreparationAvailable`. `BridgeReviewViewerMode` no longer mirrors
  legacy selected-content demand state into worker availability via
  `selectedContentAvailabilityFromLegacySelectedContentState` or
  `setSelectedContentAvailability`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts`
  failed because the new durable source-structure guard found 14 forbidden shim
  owners across Review mode, selection state, render snapshot controller,
  runtime protocol, command handler, and comm-worker store.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/app/bridge-app.unit.test.ts`
  passed 6 files / 63 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed; production-only source scan for the deleted shim
  tokens returned no matches.
- Sidekick evidence: Arendt reviewed the checkpoint and returned `needs fixes`
  for one P2: the durable shim-deletion source scan did not include the public
  `bridge-app.tsx` re-export surface. The test was fixed to include
  `bridge-app.tsx`; direct source-structure proof and the full focused slice
  proof then passed.
- Remaining scope note: `createBridgeReviewWorkerPierreCourier` is an explicit
  courier seam that returns typed receipts for `BridgeWorkerPierreRenderJob`;
  it does not yet perform full Pierre DOM submit/apply work. Do not claim full
  G3, full R44/R54/R56/R57/R60, browser/native Review UX proof, or complete
  worker-owned content paint from this checkpoint. Legacy selected body/resource
  loading and the real Pierre execution adapter remain later deletion targets.

## 2026-07-05 22:21 ET - G3 real packaged worker boundary checkpoint

- Scope: moved Review runtime protocol registration out of the page/app
  controller and into the real packaged comm-worker entry. The Review app
  controller now builds a strict Zod-derived `bridgeCommWorker.bootstrap`
  request and delegates commands to
  `createBridgeReviewCommWorkerTransportDispatcher`. The new transport loads
  `agentstudio://app/assets/bridge-comm-worker.js`, constructs a module
  `Worker`, sends bootstrap once, buffers commands until bootstrap-ready health,
  validates worker-to-main messages, and reports typed degraded health for
  startup/bootstrap/postMessage failures instead of silently stranding queued
  commands. The app asset manifest and tsdown config now package
  `bridge-comm-worker` as a module worker asset.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts`
  first failed 1 file / 2 tests for the reviewer-found silent worker-startup
  and degraded-bootstrap holes, including an unhandled `asset fetch failed`
  rejection. After initial handling, an expanded branch test failed on duplicate
  degraded bootstrap `postMessage` failure publication, proving the exact
  double-publish path before the idempotence guard landed.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts src/app/bridge-app-review-render-snapshot-controller.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts scripts/app-asset-contract.unit.test.ts src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts src/core/comm-worker/bridge-comm-worker-store.unit.test.ts src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts scripts/check-bridgeweb-architecture.unit.test.ts scripts/build-app-assets-collector.unit.test.ts`
  passed 13 files / 97 tests;
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed;
  scoped `oxlint --type-aware` passed;
  scoped `oxfmt --check` passed;
  `git diff --check` passed. Source scans found no
  `registerBridgeCommWorkerRuntimePortProtocol` or
  `createBridgeReviewRuntimeProtocolPort` in
  `bridge-app-review-render-snapshot-controller.ts`; `new Worker` for this
  slice appears only in the shared-rpc transport; async-cache scan hits remain
  absence-test regexes only.
- Full-suite / browser proof note:
  `pnpm --dir BridgeWeb exec vitest run` was attempted from this checkpoint and
  reached 148/150 files and 997/999 tests passing. The remaining failures were
  outside this slice: the existing line-cap guard for
  `src/core/demand/bridge-resource-executor.unit.test.ts: 1060` and a
  suite-load timing spike in
  `bridge-app-review-metadata-package.scaling.unit.test.ts` that passed alone
  on immediate rerun. No browser Vitest, native debug, packaged-app worker-load,
  or Victoria UX proof is claimed for this checkpoint.
- Sidekick evidence: Feynman first returned `needs fixes` for the transport
  bootstrap failure hole and missing replay coverage. The fixes added direct
  branch tests for workerFactory rejection, degraded bootstrap health,
  bootstrap `postMessage` throw, invalid worker messages, worker error events,
  post-ready command `postMessage` throw, and pre-bootstrap command replay.
  Final re-review returned `ready` with no remaining P0-P3 findings and noted
  that remaining missing proof is packaged-app/browser/native runtime proof
  outside this narrow checkpoint.
- Remaining scope note: this checkpoint proves the Review runtime protocol is
  behind a real packaged worker boundary and guarded by typed bootstrap/worker
  transport tests. It does not claim full G3 Review content cutover, packaged
  worker runtime load in WKWebView, browser/native paint-ready behavior, full
  R49 final topology, R53 transfer-mode proof, R54/R56 store cutover,
  R57 Pierre courier performance proof, or R60 worker-prep performance proof.

## 2026-07-05 22:33 ET - packaged comm-worker app asset route proof

- Scope: added a focused Swift route proof for the generated packaged
  comm-worker asset. The generated app resource tree remains ignored
  (`.gitignore` line 39) and `git ls-files
  Sources/AgentStudio/Resources/BridgeWeb/app` returned 0, so the durable
  tracked artifact is the scheme-handler test, not force-added generated JS.
- Fix shape: the first inline placement in `BridgeSchemeHandlerTests.swift`
  made scoped `swiftlint --strict` fail on file length and type body length.
  The final checkpoint keeps the existing large suite unchanged and adds
  `BridgeSchemeHandlerAppAssetTests.swift` as a small sibling suite.
- Green evidence:
  `mise run test -- --filter "BridgeSchemeHandlerTests|BridgeSchemeHandlerAppAssetTests"`
  passed 53 tests / 2 suites. The build step emitted
  `assets/bridge-comm-worker.js` at 105.66 kB before Swift copied BridgeWeb
  resources, and the new test verified
  `agentstudio://app/assets/bridge-comm-worker.js` serves
  `application/javascript` containing `bridgeCommWorker.bootstrap` and
  `mainToServerWorker`.
  `swift-format lint
  Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift
  Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerAppAssetTests.swift`
  passed.
  `swiftlint lint --strict
  Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift
  Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerAppAssetTests.swift`
  passed with 0 violations.
  `git diff --check` passed.
- Remaining scope note: this proves packaged app route serving after a normal
  BridgeWeb build. It does not prove WKWebView module-worker startup,
  browser/native Review UX, full G3 Review content ownership, or final G6
  script-message RPC deletion.

## 2026-07-05 23:45 ET - G3 worker-prepared Review CodeView/Pierre job checkpoint

- Commit: `9b6b38b8 feat(bridge): prepare review codeview jobs in comm worker`
  (unsigned local fallback because 1Password signing failed with
  `failed to fill whole buffer` before the commit object was written).
- Scope: moved the Review worker render-job payload from raw
  `textWindow`/`diffTextWindow` byte windows to worker-prepared
  `codeViewFileItem`/`codeViewDiffItem` DTOs. The worker now decodes fetched
  Review content into text, windows content before Pierre DTO construction,
  prepares `parseDiffFromFile` results in the comm-worker planner, and sends an
  explicit clone descriptor with byte length for the worker-to-main
  `pierreRenderJob` payload. Main/app remains a courier/render-snapshot seam for
  this checkpoint.
- Sidekick findings accepted and fixed:
  - Gibbs/Boyle established that Pierre does not consume the old raw
    `ArrayBuffer` job payloads directly; the comm worker should emit
    Pierre/CodeView-ready DTOs for this sub-slice.
  - Dalton found three blockers before commit: post-fetch CodeView prep escaped
    `WorkerContentPreparationPump`, byte caps were enforced after expensive DTO
    construction, and clone descriptors could name unresolved fields. Fixes:
    post-fetch publish re-enters the pump as a continuation; windowed byte
    preflight rejects oversized windows before CodeView/Pierre payload
    construction; clone descriptors must resolve to an actual field even when
    `byteLength` is supplied.
  - Bohr re-reviewed those fixes and found one P2: publish-phase synchronous
    errors could strand the preparation completion. Fix: publish is wrapped and
    rejects completion on synchronous failure; fetch-continuation callback errors
    are captured with `.catch(completion.reject)`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts` failed on
  `rejects clone descriptors whose field path does not resolve`;
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts`
  failed on the two oversized-window tests because byte budget was enforced only
  after payload construction; `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts` failed
  on the pump-continuation and publish-error completion tests before production
  fixes.
- Green scoped evidence:
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts` passed 21
  files / 88 tests.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts` passed 1
  file / 2 tests.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware`, scoped
  `pnpm --dir BridgeWeb exec oxfmt --check`, and `git diff --check` passed.
  Production source scans found no raw `textWindow`/`diffTextWindow` payload
  constructors in `BridgeWeb/src/core/comm-worker` and no main/courier
  parse/window/diff/decode/content-loader imports in the converted courier
  seam.
- Broad-suite note:
  `pnpm --dir BridgeWeb exec vitest run` was attempted after the final fixes and
  passed 149/150 files and 1011/1012 tests. The only failure was the known
  out-of-scope line-cap guard:
  `src/core/demand/bridge-resource-executor.unit.test.ts: 1060`. That file is
  outside this checkpoint's write scope and was not edited.
- Remaining scope note: this checkpoint proves the worker-core Review render-job
  DTO prep seam and explicit clone accounting. It does not claim zero-copy or
  transfer-aware large CodeView payloads, full G3 Review content ownership, full
  R57/Pierre DOM submit telemetry, full R60 performance budgets, browser/native
  Review UX, or the final G6 script-message RPC deletion.

## 2026-07-06 00:23 ET - G3 selected Review CodeView display cutover checkpoint

- Commit: `c8d9a584 feat(bridge): consume worker prepared selected codeview`
  (unsigned local fallback because 1Password signing failed with
  `failed to fill whole buffer` before the commit object was written).
- Scope: selected Review CodeView now consumes worker-prepared CodeView items
  from `BridgeMainRenderSnapshotStore`. The selected CodeView shell/panel prop
  corridor no longer accepts `selectedContentResources` or selected demand start
  timing, and the CodeView panel merges the worker-prepared selected item into
  its initial Pierre item set instead of materializing selected content from FE
  resources. The selected FE content loader remains only as an explicit
  markdown-preview legacy path gated by `rootSnapshot.renderMode.kind ===
  'markdownPreview'`.
- Keepalive closure: the foreground-expanded visible controller now rejects
  the current selected item and sends expanded non-selected loads as
  `interest: 'visible'`, not `selected`. The CodeView loading-id helper also
  filters selected ids from visible-loading state, while preserving the worker
  availability path's selected loading placeholder.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts` failed before
  production changes on missing `selectedCodeViewItem`, missing
  `codeViewItemsById`, and missing
  `bridgeCodeViewInitialItemsWithSelectedCodeViewItem`.
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts` then failed on
  the foreground-expanded `interest: 'selected'` guard.
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts` then failed
  on selected visible-loading placeholder materialization.
- Green scoped evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/app/bridge-app.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/shell/review-viewer-shell.integration.test.tsx
  src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts
  src/core/comm-worker/bridge-worker-review-pierre-job-planner.unit.test.ts
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts` passed 11
  files / 122 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware`, scoped
  `pnpm --dir BridgeWeb exec oxfmt --check`, and `git diff --check` passed.
  Source scans found no selected `selectedContentResources` shell/panel prop
  corridor and no `interest: 'selected'` in the foreground-expanded visible
  controller path.
- Sidekick verification:
  Background sidekick `task-mr8pmut0-gw3nsm` wedged before writing a job log
  and was killed by exact PID. A foreground read-only verifier then returned
  PASS: worker-prepared CodeView items land in `BridgeMainRenderSnapshotStore`;
  selected CodeView flows through `selectedCodeViewItem`; shell/panel do not
  receive `selectedContentResources`; markdown selected content is gated to
  markdown preview; visible expanded content no longer uses selected interest.
- Remaining scope note: this checkpoint proves selected Review CodeView display
  cutover and the selected keepalive closures above. It does not claim full G3
  visible hydration cutover, File View cutover, G5 demand-membership deletion,
  G6 script-message RPC deletion, browser/native Review UX, zero-copy Pierre
  delivery, or full R57/R60 performance proof.

## 2026-07-06 01:16 ET - G3 selected markdown/control selected-resource deletion

- Parent commit before checkpoint: `c8d9a584 feat(bridge): consume worker
  prepared selected codeview`.
- Scope: the live selected Review markdown/control/telemetry corridor is cut
  away from FE package-first `selectedContentResources` and the deleted selected
  content demand controller. `BridgeReviewViewerMode`, markdown preview,
  control-command listeners, navigation, and Review-ready telemetry now consume
  `selectedCodeViewItem` from `BridgeMainRenderSnapshotStore` instead of
  selected FE resources.
- Freshness closure: `selectedBridgeCodeViewItemForReviewPackage()` rejects
  stale same-item package rollover content by matching worker-prepared CodeView
  cache keys to the current Review package content handles. Raw selected
  `{ state: 'ready' }` availability is downgraded to `{ state: 'loading' }`
  when no fresh selected CodeView item exists, while terminal `failed` and
  `unavailable` availability still pass through.
- Scope boundary: visible hydration remains explicitly out of scope for this
  checkpoint because worker-visible preparation is not yet live; that is the
  larger remaining G3 content-ownership slice.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts` failed before
  production changes on two assertions: the new selected-resource deletion
  guard found the still-live selected controller, selected resource state, and
  markdown/control/telemetry selected-resource props; the selected CodeView
  guard also found `shouldLoadSelectedContent`.
  Raman then found a P2 stale metadata leak: file-backed worker markdown preview
  used stale `codeViewItem.file.name` when the same item rolled over with the
  same content hash but a changed path. The added regression
  `uses current package path for same-hash file markdown rollover previews`
  failed before the fix with received `sourcePath:
  "docs/plans/bridge-plan.md"` instead of expected current package path
  `"docs/plans/renamed-bridge-plan.md"`.
- Green scoped evidence:
  The P2 regression then passed after `displayPathForMarkdownCodeViewRole()`
  moved file-backed worker markdown preview metadata to current Review item
  metadata.
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/state/review-viewer-store.unit.test.ts
  src/review-viewer/state/review-viewer-render-snapshot.unit.test.ts
  src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/review-viewer/content/review-content-demand-loader.unit.test.ts
  src/review-viewer/content/visible-review-content-hydration.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/review-viewer/markdown/bridge-markdown-render-mode.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts` passed 10
  files / 106 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the scoped changed
  TypeScript corridor. The first oxlint invocation failed before linting
  because root-relative paths were passed with `pnpm --dir BridgeWeb`; the
  rerun used BridgeWeb-relative paths and exited 0.
  `pnpm --dir BridgeWeb exec oxfmt --check` passed on 11 files.
  Deleted-file scan passed:
  `BridgeWeb/src/app/bridge-app-review-selected-content-controller.ts` is gone.
  Live selected-owner scan passed for selected markdown/control/telemetry
  corridor tokens. Added-line scan found no new TanStack/SWR/Apollo/equivalent
  async-cache authority and no new Zustand import/useStore outside the
  pre-existing Review viewer store reads. `git diff --check` passed.
- Browser proof blocker:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run
  --project integration-browser
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
  src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx
  src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx`
  was interrupted after the run hung with a large React `act(...)` warning
  stream and no terminal result. Retrying only
  `src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
  also hung the same way and was interrupted. This is recorded as a browser
  proof blocker, not a product pass.
- Sidekick verification:
  Harvey (`019f35cd-2f5b-78b1-beb0-1b8778790b6b`) verified the accepted P1
  closure: stale selected CodeView content is filtered before selected
  consumers see it, stale ready availability downgrades to loading, and no
  remaining code findings were reported. Harvey remained blocked only on the
  known browser proof lane and has been closed.
  Raman (`019f35da-ae2e-7b91-93d5-ec05aa7ba19d`) found the file-backed
  markdown-preview stale path P2, then verified the fix closed the finding with
  no new P0-P2 in the reviewed scope. Raman's closure proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/markdown/bridge-markdown-render-mode.unit.test.ts` passed
  11/11, and `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
- Remaining scope note: this checkpoint proves selected Review
  markdown/control/telemetry selected-resource deletion and stale selected
  CodeView freshness guards. It does not claim full G3 visible hydration
  cutover, File View cutover, G5 demand-membership deletion, G6 script-message
  RPC deletion, browser/native Review UX, zero-copy Pierre delivery, or full
  R57/R60 performance proof.

## 2026-07-06 02:25 ET - G3 visible Review CodeView display cutover (verified)

- Parent commit before checkpoint: `8a6128c3 feat(bridge): delete selected
  review content resources path`.
- Checkpoint commit: `3ada147e feat(bridge): render visible review codeview
  from worker snapshots`. Signing failed before commit object write with
  `1Password: failed to fill whole buffer`, so the commit used the repo-allowed
  unsigned local fallback.
- Scope: continue the G3 Review content cutover by deleting the app-side
  visible content controller and replacing its CodeView display path with
  worker-prepared display copies from `BridgeMainRenderSnapshotStore`.
  `visibleBridgeCodeViewItemsForReviewPackage()` selects current visible item
  ids from `codeViewItemsById`, freshness-filters them against current Review
  package content handles, and passes them through
  `BridgeReviewViewerMode -> BridgeReviewViewerShellBoundary ->
  ReviewViewerShell -> BridgeCodeViewPanel` as `visibleCodeViewItems`.
  `BridgeCodeViewPanel` merges selected and visible worker-prepared CodeView
  items into initial Pierre items, with selected replacement taking precedence.
  Expanded non-selected loading items are promoted by the same
  reconcile/apply/controller path when worker-prepared content arrives.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts` failed
  before production edits with three expected failures:
  missing `visibleBridgeCodeViewItemsForReviewPackage` and missing
  `bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems`.
- Green scoped evidence:
  The same two-file command passed 2 files / 33 tests after implementation.
  After accepted sidekick findings, the final focused G3 battery passed 13
  files / 138 tests:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts
  src/review-viewer/shell/review-viewer-shell.integration.test.tsx
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/review-viewer/state/review-viewer-store.unit.test.ts
  src/review-viewer/state/review-viewer-render-snapshot.unit.test.ts
  src/core/comm-worker/bridge-worker-pierre-courier.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/review-viewer/content/review-content-demand-loader.unit.test.ts
  src/review-viewer/content/visible-review-content-hydration.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware`, scoped
  `pnpm --dir BridgeWeb exec oxfmt --check`, and `git diff --check` passed.
  Live app/shell/CodeView deletion scan for old visible-resource tokens
  returned no matches, and
  `test ! -e BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts`
  passed.
  Line-cap check: `bridge-code-view-panel-support.tsx` is 976 lines,
  `bridge-code-view-panel.unit.test.ts` is 948 lines, and
  `bridge-code-view-panel-reconcile.unit.test.ts` is 132 lines.
- Browser proof blocker:
  Review Vitest Browser integration remains blocked by the known
  integration-browser `act(...)` hang from the prior checkpoint. This slice is
  not claiming browser/native Review UX proof.
- Sidekick verification:
  Jason (`019f35e7-c32f-7702-bc9a-80c112211765`) and Nash
  (`019f35f4-f4de-7320-bcd5-8ba0fb1ec2b8`) found the visible/expanded
  non-selected CodeView gap after the old FE materialization path was deleted.
  Avicenna (`019f3605-6606-77d1-8a72-ad8f07ae52d6`) re-reviewed the fix and
  found two accepted seam issues: worker-prepared hydrated items initially
  stopped at reconcile and did not prove live controller paint, and
  worker-prepared replacement could overwrite local collapse intent. Both were
  fixed. Final Avicenna verdict: ready, original stuck-loading P1 closed,
  collapse-intent P2 closed, no new P0-P2 in the visible worker-prepared
  reconcile/apply path. All three sidekicks were closed after completion.
- Remaining scope note: this checkpoint targets the visible/non-selected
  CodeView display gap only. It does not claim File View cutover, G5 demand
  membership deletion, G6 script-message RPC deletion, browser/native Review UX,
  zero-copy Pierre delivery, full R57/R60 proof, or the final G3 content-demand
  membership cutover.

## 2026-07-06 02:33 ET - G3 initial selected foreground demand deletion (verified)

- Parent commit before checkpoint: `3ada147e feat(bridge): render visible
  review codeview from worker snapshots`.
- Checkpoint commit: `7387ed6d feat(bridge): stop initial review foreground
  demand`. Signing failed before commit object write with `1Password: failed
  to fill whole buffer`, so the commit used the repo-allowed unsigned local
  fallback.
- Scope: remove the remaining Review app production promotion call into
  `loadReviewItemContentResourcesThroughDemandResult` during metadata snapshot
  apply. Snapshot apply now selects the initial Review item through
  `selectInitialReviewItem(nextSelectedItemId)` without starting FE foreground
  descriptor demand or filling the FE content registry.
- Red evidence:
  Added `../app/bridge-app-review-controller.ts` to the selected Review
  source-structure forbidden owner list, then ran
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts`. It failed as
  expected with
  `../app/bridge-app-review-controller.ts: loadReviewItemContentResourcesThroughDemandResult`.
- Green scoped evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app.unit.test.ts
  src/app/bridge-app-review-metadata-package.preservation.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/review-viewer/content/review-content-demand-loader.unit.test.ts` passed
  8 files / 133 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed.
  Production scan for `loadReviewItemContentResourcesThroughDemandResult` and
  `promoteInitialReviewItemContentToForeground` in
  `bridge-app-review-controller.ts` returned no matches.
- Sidekick verification:
  Parfit (`019f361e-cbef-7a51-be5d-e66e5a91c9c8`) reviewed the current
  working-tree diff read-only and returned `ready`, no P0-P2 findings. Parfit
  independently ran `tsc --noEmit`, the source-structure plus selection
  controller units, and the focused app unit for the new zero-descriptor-load
  behavior. Sidekick closed after completion.
- Remaining scope note: this checkpoint only deletes the metadata-snapshot
  initial selected FE foreground demand. It does not claim browser/native UX,
  File View/G4, demand membership/G5, final RPC/G6, zero-copy Pierre delivery,
  or full R57/R60 proof.

## 2026-07-06 04:07 ET - G3 Review app content invalidation worker-source cutover (verified)

- Parent commit before checkpoint: `7387ed6d feat(bridge): stop initial review
  foreground demand`.
- Checkpoint commit: `36c14eaf feat(bridge): route review invalidation
  through worker source state`. Signing failed before commit object write with
  `1Password: failed to fill whole buffer`, so the commit used the repo-allowed
  unsigned local fallback.
- Scope: continue G3 by deleting the remaining Review app-side content identity
  controller and package-first descriptor invalidation test path. Review
  metadata snapshot/window/delta/reset/invalidation now synchronizes the
  current Review package/tree rows into the comm worker through typed
  `reviewSourceUpdate`; accepted Review invalidation dispatches typed
  `reviewInvalidate` to the worker cache owner. The Review runtime dispatcher
  is stable across metadata updates and receives source updates instead of
  being rebuilt from a whole app-side package identity controller.
- Worker ownership: `BridgeCommWorkerStore.applyReviewSourceUpdateFact()`
  updates source indexes in place while preserving selected, visible,
  paint-ready, availability, demand, and byte-cache state.
  `applyReviewInvalidationFact()` resolves invalidated items from item ids,
  path hints, selected/visible ids, and paint-ready entries; it deletes stale
  row paint and byte cache entries, marks availability `stale`, and schedules
  selected refresh demand when the invalidated item is selected.
  `BridgeMainRenderSnapshotStore` deletes cached CodeView display copies on
  rowPaint delete/reset so stale selected/visible content cannot keep painting
  from the main display cache.
- Sidekick finding fixed: Euler found a P1 after rowPaint deletion: worker
  `stale` availability with no cached CodeView item could fall through to a
  blank selected panel. Red regression
  `selected canvas content loading follows worker-owned stale availability`
  failed in `BridgeWeb/src/app/bridge-app.unit.test.ts` with expected
  `null` versus `content`. The fix maps selected worker `stale` availability
  to the existing `content` loading reason, so the shell renders the loading
  placeholder instead of stale content or a blank panel. Euler re-reviewed the
  narrow seam and returned `ready`, no P0-P2.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts`
  failed before the stale-display fix on
  `selected canvas content loading follows worker-owned stale availability`,
  received `null` instead of `content`.
- Green scoped evidence:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.unit.test.ts`
  passed 1 file / 29 tests after the P1 fix.
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app.unit.test.ts` passed 4 files / 62 tests.
  The adjacent G3 unit battery passed 16 files / 147 tests:
  `src/core/comm-worker/bridge-worker-contracts.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-client.unit.test.ts`,
  `src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts`,
  `src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts`,
  `src/core/comm-worker/bridge-worker-rpc-lifecycle-store.unit.test.ts`,
  `src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-store.unit.test.ts`,
  `src/core/comm-worker/bridge-worker-content-preparation-pump.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts`,
  `src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`,
  `src/app/bridge-app.unit.test.ts`,
  `src/app/bridge-app-review-metadata-package.preservation.unit.test.ts`,
  and `src/review-viewer/review-viewer-source-structure.unit.test.ts`.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts` passed
  1 browser file / 2 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the
  touched non-deleted TS/TSX files.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed on 22 files.
  `git diff --check` passed.
- Source/deletion scans:
  `test ! -e BridgeWeb/src/app/bridge-app-review-content-identity-controller.ts`
  and
  `test ! -e BridgeWeb/src/app/bridge-app-review-descriptors.unit.test.ts`
  passed.
  Touched production Review/worker surface scan for the old content identity,
  registry, selected resource map, and
  `loadReviewItemContentResourcesThroughDemandResult` tokens returned no
  matches. Touched production Review/worker surface scan for TanStack Query,
  SWR, Apollo, `webkit.messageHandlers`, and `__bridge_command` returned no
  matches. Broader script-message and legacy-demand matches remain expected
  pre-G4/G5/G6 test/support or unconverted-surface debt, not a G3 pass claim.
- Sidekicks:
  Ptolemy found the earlier source-update ordering P1 and that was fixed before
  this proof by synchronizing latest Review source before select/viewport/
  invalidation dispatch.
  Euler found the stale selected-panel P1 above, verified the closure, and was
  closed. Gauss completed the parallel Victoria read and found the latest
  marker contained startup/control traffic only, not a review-lag interaction
  capture; it was closed as no-signal for UX proof.
- Line-cap note: all touched TS/TSX files remain under 1000 lines. The largest
  touched files are `BridgeWeb/src/app/bridge-app.unit.test.ts` at 926 lines
  and
  `BridgeWeb/src/app/bridge-app-review-metadata-package.preservation.unit.test.ts`
  at 849 lines.
- Remaining scope note: this checkpoint proves Review app-side legacy content
  registry/resource executor invalidation ownership is deleted; worker source
  updates preserve selected/visible/paint-ready/cache state; invalidation
  stales/deletes worker paint and main display copies; and typed
  source/invalidation commands are Zod-derived. It does not claim browser/native
  Review UX, File View/G4, G5 demand membership, G6 script-message RPC deletion,
  zero-copy Pierre delivery, or full R57/R60 performance budgets.

## 2026-07-06 04:37 ET - G3 dead Review FE content-authority deletion (verified)

- Parent commit before checkpoint: `36c14eaf feat(bridge): route review
  invalidation through worker source state`.
- Checkpoint commit: `4489fcfa feat(bridge): delete dead review fe content
  authority`. Signing failed before commit object write with `1Password: failed
  to fill whole buffer`, so the commit used the repo-allowed unsigned local
  fallback.
- Scope: continue G3 by compile-deleting the dead Review FE content-authority
  modules left after the worker snapshot/source cutovers. The deleted cluster
  includes old visible hydration, demand loader, content loader, and content
  registry modules plus their obsolete tests/support. Surviving Review content
  files are limited to demand policy/telemetry/type vocabulary and the
  content-addressed identity helper.
- Store ownership: `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
  no longer exposes `contentHydrationByItemId`, `setContentHydrationStatus`, or
  `BridgeContentHydrationStatus`. It remains a shell/projection/display slice
  store for this checkpoint; it does not become a protocol/cache/demand truth
  owner.
- Selection/content cleanup: `BridgeWeb/src/app/bridge-app-review-selection-state.ts`
  no longer exports selected FE content-resource state, demand-start decisions,
  content validity drop classification, resource counters, or visible hydration
  pause/start helpers. The selected content identity import now comes from
  `visible-review-content-hydration-identity.ts`.
- Source-structure guard: `BridgeWeb/src/review-viewer/review-viewer-source-structure.unit.test.ts`
  now asserts the eight old Review FE content-authority modules are absent,
  legacy imports do not survive, and the Review FE store does not regain the old
  hydration truth fields.
- Sidekick context: Ohm's earlier read-only sidekick review found two checkpoint
  risks: obsolete tests could survive after their modules were deleted, and
  `review-viewer-store.ts` must not become the new content truth owner. Both
  findings are closed in this checkpoint by deleting the obsolete test cluster
  and removing the old hydration truth from the store. Newton is running an
  extra read-only sidekick review for this final diff before commit.
- Green scoped evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-client.unit.test.ts
  src/core/comm-worker/bridge-worker-transfer-list.unit.test.ts
  src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts
  src/core/comm-worker/bridge-worker-rpc-lifecycle-store.unit.test.ts
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/core/comm-worker/bridge-worker-content-preparation-pump.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/app/bridge-app.unit.test.ts
  src/app/bridge-app-review-metadata-package.preservation.unit.test.ts
  src/app/bridge-app-review-content-validity-key.unit.test.ts
  src/app/bridge-app-review-render-slices.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/review-viewer/state/review-viewer-store.unit.test.ts
  src/review-viewer/shell/review-viewer-shell.integration.test.tsx
  src/review-viewer/telemetry/bridge-review-viewer-telemetry.unit.test.ts`
  passed 21 files / 170 tests.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/core/comm-worker/bridge-worker-transfer-list.browser.test.ts` passed
  1 browser file / 2 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the 15
  touched non-deleted TS/TSX files after rerunning with `src/...` paths.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed on the same 15 files.
  `git diff --check` passed.
- Deletion/source scans:
  `test ! -e` passed for the eight deleted Review FE content-authority modules:
  `visible-review-content-hydration.ts`,
  `visible-review-content-hydration-demand.ts`,
  `visible-review-content-hydration-load-state.ts`,
  `visible-review-content-hydration-result.ts`,
  `visible-review-content-hydration-support.ts`,
  `review-content-demand-loader.ts`, `review-content-loader.ts`, and
  `review-content-registry.ts`.
  Production import scan for old demand/registry/loader/hydration modules
  returned no matches outside source-structure guards.
  Production scan for old FE content-resource and hydration truth helpers
  returned no matches outside assertion tests.
- Line-cap note: all touched TS/TSX files remain under 1000 lines. Largest
  touched files checked: `review-viewer-shell.integration.test.tsx` 876 lines,
  `bridge-app.unit.test.ts` 704 lines, `review-viewer-source-structure.unit.test.ts`
  524 lines, and `review-viewer-store.ts` 468 lines.
- Remaining scope note: this checkpoint proves deletion of dead Review FE
  content-authority modules/tests and the old Review FE store hydration truth
  only. It does not prove browser/native Review UX, File View/G4, G5 demand
  membership, G6 script-message RPC deletion, zero-copy Pierre delivery, full
  R54 across all converted surfaces, or full R57/R60 performance budgets.

## 2026-07-06T09:16:16Z - G3 Review main-thread Zustand remnant removal

- Checkpoint scope: remove the remaining direct main-thread Review Zustand
  dependency from the Review mode/store seam and replace it with a typed
  non-Zustand render store surface. This is a narrow G3/R54/R56 cleanup slice;
  it is not full G3, File View/G4, G5, G6, browser/native UX, zero-copy Pierre,
  or full R57/R60 proof.
- Production changes:
  `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx` no longer imports
  `useStore` from Zustand. Its projection, panel chrome, and action reads now
  go through `useBridgeReviewViewerStoreSelector`.
  `BridgeWeb/src/review-viewer/state/review-viewer-store.ts` no longer imports
  `zustand/vanilla` or `subscribeWithSelector`; it now exposes a small typed
  render store with `getState`, root `subscribe`, explicit
  `subscribeSelector`, and a `useSyncExternalStore` React hook.
- Accepted sidekick findings and closure:
  Lagrange found P1 selector-snapshot instability risk and P2 too-narrow
  source-structure coverage. P1 was closed by caching selected snapshots by
  store, selector, and raw store state before returning values to
  `useSyncExternalStore`. P2 was closed by broadening the permanent
  source-structure guard over Review main-thread production sources and by
  forbidding Zustand root/subpath imports plus `useStore`,
  `useStoreWithEqualityFn`, `createStore`, `createWithEqualityFn`, and
  `subscribeWithSelector`.
- Test coverage added/updated:
  `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts` now
  proves stable selector subscriptions ignore unrelated worker/viewport
  updates, actions identity remains stable, and an allocating selector returns
  the same selected object while store state and selector are unchanged.
  `BridgeWeb/src/review-viewer/review-viewer-source-structure.unit.test.ts`
  now scans Review app production files and Review viewer main-thread
  production files, excluding tests, test-support, and worker surfaces.
- Fresh controller evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/state/review-viewer-store.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts` passed 2
  files / 29 tests.
  Focused 5-file Review battery passed 5 files / 67 tests.
  Adjacent 11-file battery passed 11 files / 109 tests.
  G3-adjacent 21-file battery passed 21 files / 173 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the four
  touched files with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed on the four touched
  files.
  `git diff --check` passed.
  Broad production source scan for direct Zustand imports/helpers over
  `BridgeWeb/src/app` and `BridgeWeb/src/review-viewer` excluding tests,
  test-support, and workers returned no matches.
- Sidekick proof:
  Lagrange final re-review returned `ready`: P1 and P2 are closed on the
  current diff, focused Vitest pair passed, and broad production scan returned
  no Review main-thread Zustand matches.

## 2026-07-06T09:37:30Z - G4 File View direct Zustand seam removal

- Checkpoint scope: remove the direct main-thread File View Zustand dependency
  from the File View store/bindings seam and replace it with a typed
  non-Zustand render store surface. This is a narrow G4/R54/R56 cleanup slice;
  it is not full G4 content protocol cutover, worker-local canonical File View
  ownership, browser/native UX proof, G5 demand membership, G6 RPC deletion,
  zero-copy Pierre delivery, or full R57/R60 performance proof.
- Production changes:
  `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.ts` no longer
  imports `zustand/vanilla` or `subscribeWithSelector`; it now exposes a small
  typed render store with `getState`, root `subscribe`, explicit
  `subscribeSelector`, and a `useSyncExternalStore` selector hook with cached
  selected snapshots.
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-store-bindings.ts` no
  longer imports `useStore` from Zustand. File View root snapshot, actions,
  render state, open-file state, load state, refresh debug state, and telemetry
  reads now go through `useBridgeFileViewerStoreSelector`.
- Accepted sidekick finding and closure:
  Leibniz found a P2 proof gap because the initial source-structure guard
  scanned only `src/file-viewer/**` and missed app-level File View wrappers.
  The guard now scans `BridgeWeb/src/file-viewer/**` plus app production files
  whose relative path includes `file-viewer`, and the test name was narrowed to
  avoid claiming a completed render-snapshot cutover. Leibniz re-reviewed the
  correction and returned `ready`.
- Test coverage added/updated:
  `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.unit.test.ts` now
  proves stable selector subscriptions ignore unrelated updates, actions
  identity remains stable, allocating selector snapshots are cached while store
  state and selector are unchanged, and functional open-state transitions still
  work.
  `BridgeWeb/src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts`
  permanently guards File View production files and File View app wrappers
  against Zustand root/subpath imports plus `useStore`,
  `useStoreWithEqualityFn`, `createStore`, `createWithEqualityFn`, and
  `subscribeWithSelector`.
- Fresh controller evidence:
  Red-first proof: the new source-structure guard initially failed on old
  File View Zustand imports/helpers and the store tests failed because
  `subscribeSelector` and selector snapshot caching did not exist.
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/state/bridge-file-viewer-store.unit.test.ts
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-app.unit.test.ts` passed 3 files / 18
  tests after the sidekick finding was fixed.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the four
  touched files with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed on the four touched
  files.
  `git diff --check` passed.
  Broad production source scan for direct Zustand imports/helpers over
  `BridgeWeb/src/file-viewer` and `BridgeWeb/src/app`, excluding tests and
  browser suites, returned no matches.
  Line counts are under cap: `bridge-file-viewer-store.ts` 253 lines,
  `use-bridge-file-viewer-store-bindings.ts` 76 lines,
  `bridge-file-viewer-store.unit.test.ts` 293 lines, and
  `bridge-file-viewer-store-source-structure.unit.test.ts` 77 lines.
- Known proof boundary:
  The full File View browser suite remains outside this checkpoint and was
  previously observed failing on known integration-browser noise/flakes. This
  checkpoint does not claim browser/native UX, full G4 content loading, File
  View runtime/protocol migration, G5/G6, zero-copy Pierre delivery, or full
  R57/R60.

## 2026-07-06T10:03:38Z - G4 File View UI-store correction after route-local snapshot review

- Checkpoint scope: correct the post-`1371e55a` File View store split so it
  does not introduce a permanent File View route-local render snapshot store.
  This is a narrow R54/R56 alignment correction on the File View store/bindings
  seam. It is not full G4 content protocol cutover, worker-owned File View
  content/runtime transport, browser/native UX proof, G5 demand membership, G6
  RPC deletion, zero-copy Pierre delivery, or full R57/R60 performance proof.
- Production changes:
  `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.ts` remains a tiny
  UI store for `searchText`, `searchMode`, and `filterMode` only.
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-store-bindings.ts` keeps
  the current legacy render/open/load/debug display fields in React local state
  as a binding-layer adapter so no second route-local external render store is
  committed. This is a deferral boundary: full G4 must replace these legacy
  fields with worker slice patches/shared render snapshot semantics instead of
  treating the adapter as protocol truth.
- Test coverage added/updated:
  `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.unit.test.ts` now
  proves the File View store owns only file-tree search/filter UI facts and that
  render/protocol authority fields are absent from the store snapshot.
  `BridgeWeb/src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts`
  now guards the UI store against render/open/load/debug ownership and guards
  all File View production sources, including
  `use-bridge-file-viewer-store-bindings.ts`, against
  `BridgeFileViewerRenderSnapshotStore` /
  `createBridgeFileViewerRenderSnapshotStore` route-local render-store tokens.
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-store-bindings.browser.test.tsx`
  now proves the binding hook keeps functional open-file state transitions
  alive, preserves legacy display state across search/filter UI updates, and
  keeps `viewerStore.getState()` limited to `actions` plus `rootSnapshot`.
- Fresh controller evidence:
  Red proof before the correction: focused File View store tests failed 6/10
  because the previous tests still expected removed `setRenderState`,
  `setOpenFileState`, `setInitialSurfaceLoadState`, `setRefreshDebugState`,
  `setLastOpenLoadTelemetry`, and `setLastDemandDispatchDebugState` actions on
  `BridgeFileViewerStore`.
  Green proof after the correction:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-app.unit.test.ts
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  src/file-viewer/state/bridge-file-viewer-store.unit.test.ts` passed 3 files /
  18 tests.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run
  --project integration-browser
  src/file-viewer/use-bridge-file-viewer-store-bindings.browser.test.tsx`
  passed 1 file / 1 test.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` passed on the four
  touched production/unit files plus the new browser test with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` passed on the four touched
  production/unit files plus the new browser test.
  `git diff --check` passed.
  Source scans for route-local render snapshot, direct Zustand, and async-cache
  tokens over File View/app surfaces returned only absence-assertion tests or
  existing comm-worker absence tests; no File View production match remains.
  Line counts are under cap: `use-bridge-file-viewer-store-bindings.ts` 113
  lines, `use-bridge-file-viewer-store-bindings.browser.test.tsx` 90 lines,
  `bridge-file-viewer-store.ts` 179 lines,
  `bridge-file-viewer-store.unit.test.ts` 109 lines, and
  `bridge-file-viewer-store-source-structure.unit.test.ts` 113 lines.
- Sidekick evidence:
  Russell reported a P1 spec mismatch for a permanent
  `BridgeFileViewerRenderSnapshotStore`, citing R54/R56 and G4's
  `BridgeMainRenderSnapshotStore` proof wording. The current diff adopts the
  recommended fallback shape: land only the UI-store extraction/correction and
  defer File View render ownership to the shared primitive/full G4 cutover.
  Ptolemy reported two P2 proof gaps: the render-store guard skipped
  `use-bridge-file-viewer-store-bindings.ts`, and hook behavior coverage for
  the legacy adapter was missing. Both were fixed by removing the guard
  exclusion and adding the browser hook proof described above.
  Fermat mapped the remaining G4 old authorities and confirmed this checkpoint
  is store/snapshot-boundary-only; direct runtime/content/frame/demand/native
  authorities remain future G4 work.
- Known proof boundary:
  The binding-layer local state is a legacy adapter, not the final converted
  File View render architecture. Direct `runtime.openFile`,
  `runtime.refreshOpenFile`, `readText()`, `applyFramesToRuntime`, FE
  staleness/refresh/demand scheduling, and native worktree-file transport remain
  old authorities for later G4 slices and are not claimed fixed here.

## 2026-07-06T11:16:49Z - G4 File View worktree surface transport boundary checkpoint

- Checkpoint scope: collapse File View native/dev worktree-file backend
  plumbing behind one typed `worktreeFileSurfaceTransport` prop and adapter.
  This is a narrow preparatory G4 checkpoint. It does not perform File View
  content protocol cutover, worker-owned selected-file content, worker-owned
  frame/projection intake, G5 demand membership deletion, G6 RPC deletion,
  browser/native UX proof, zero-copy Pierre delivery, or full R57/R60 proof.
- Production changes:
  `BridgeFileViewerAppProps` no longer exposes exploded top-level
  `fetchResource`, `loadInitialSurface`,
  `registerSurfaceStreamResetRequiredCallback`, `requestFileDescriptor`, or
  `subscribeFrames` transport hooks. `bridge-app-bootstrap.tsx` and
  `bridge-app-dev-bootstrap.tsx` adapt the native/dev backend through
  `createBridgeFileViewerWorktreeFileSurfaceTransport(...)`.
  `BridgeFileViewerMode`, `bridge-file-viewer-frame-controller.ts`,
  `BridgeFileViewerApp`, `bridge-file-viewer-runtime.ts`, and the descriptor
  request controller read the nested transport boundary instead of the old
  top-level File View props.
- Test coverage added/updated:
  `BridgeWeb/src/app/bridge-file-viewer-worktree-file-surface-transport-adapter.unit.test.ts`
  proves the adapter forwards every native/dev backend method through the typed
  transport boundary. `bridge-file-viewer-store-source-structure.unit.test.ts`
  now guards against reintroducing the old exploded transport props at the
  bootstrap/component boundary. Browser suites were mechanically updated to use
  the nested prop, and the two app-level browser suites that were tripping
  React's act guard were converted to the existing act-safe helpers without
  weakening assertions.
- Fresh controller evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  src/file-viewer/state/bridge-file-viewer-store.unit.test.ts
  src/file-viewer/bridge-file-viewer-app.unit.test.ts
  src/app/bridge-file-viewer-worktree-file-surface-transport-adapter.unit.test.ts`
  passed 4 files / 20 tests.
  `CI=true pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts
  run --project integration-browser
  src/file-viewer/use-bridge-file-viewer-store-bindings.browser.test.tsx
  src/app/bridge-app-protocol-router.browser.test.tsx
  src/app/bridge-app-protocol-router.contract.browser.test.tsx
  src/app/bridge-app-file-viewer-mode-reopen.browser.test.tsx
  src/app/bridge-app-lazy-boundary.browser.test.tsx`
  passed 5 files / 26 tests. The two individually repaired browser suites also
  passed standalone: file-viewer-mode-reopen 4/4 and lazy-boundary 9/9.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` over the touched files
  exited 0 with style warnings only in existing browser-test helpers.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` over the touched files
  passed. `git diff --check` passed.
  Source scans for old component-level File View transport methods returned
  clean. Source scans for forbidden File View route-local render snapshot
  store, Zustand/useStore/createStore, and TanStack/SWR/Apollo async-cache
  tokens returned clean over the scoped production surface.
- Line-count proof:
  touched cap-adjacent files remain under 1000 lines:
  `bridge-app-lazy-boundary.browser.test.tsx` HEAD 761 -> worktree 831;
  `bridge-app-native-review-error.browser.metadata-suite.tsx` 992 -> 994;
  `bridge-file-viewer-app.browser.reactivation-demand-suite.tsx` 821 -> 839;
  `bridge-file-viewer-app.browser.selection-suite.tsx` 820 -> 839;
  `bridge-file-viewer-app.browser.startup-suite.tsx` 925 -> 960.
- Sidekick evidence:
  Mencius mapped the next smallest honest post-checkpoint G4 slice as selected
  File View content ownership and warned not to overclaim this transport
  checkpoint. Herschel independently confirmed the old backend method names
  remain only in backend/adapter/test-owned locations, component surfaces use
  `worktreeFileSurfaceTransport`, and no File View route-local render
  snapshot/Zustand/async-cache drift is present in scoped production surfaces.
  Bohr independently verified that no touched TS/TSX file exceeds 1000 lines
  and every touched >800 file has line-count proof.
- Known proof boundary:
  The old native/dev backend implementations, `WorktreeFileSurfaceRuntime`,
  main-thread raw content body reads (`readText()`), synchronous frame intake,
  FE refresh/staleness/debug display state, and demand/runtime authorities
  remain old-path G4 work. This checkpoint only narrows the prop/adapter seam so
  later G4 content/protocol slices have one typed File View transport boundary.

## 2026-07-07T02:26:20Z - G4 File View selected CodeView snapshot-store checkpoint

- Checkpoint scope: move File View selected CodeView display ownership out of
  `useBridgeFileViewerShellModel` and behind the shared
  `BridgeMainRenderSnapshotStore` primitive via
  `useBridgeFileViewerRenderSnapshotController`. This is a narrow G4 selected
  display checkpoint. It does not claim full File View worker content
  production, worker-owned raw content fetch/read, worker-owned frame intake,
  full G4 content protocol cutover, G5/G6 deletion, zero-copy Pierre delivery,
  browser/native UX, or full R44/R54/R57/R60 proof.
- Production changes:
  Added `BridgeWeb/src/file-viewer/bridge-file-viewer-render-snapshot-controller.ts`.
  `BridgeFileViewerApp` now creates the render-snapshot controller, passes its
  stable publisher functions into the content controller, and passes
  `renderSnapshotController.selectedCodeViewItem` to the shell. The shell model
  no longer imports or derives selected CodeView display content. The File View
  body-state hook now only owns temporary runtime-adapter refs/procedures, not
  duplicate selected display React state. The old
  `renderedOpenFileContentForState` helper and rendered-content type were
  deleted. `BridgeMainRenderSnapshotStore` now has a batched
  `applySnapshotUpdate(...)` path so local selection, CodeView item, and worker
  availability patches can publish one snapshot notification.
- Regressions fixed during sidekick review:
  Feynman found that a same-path stale refresh could blank the File canvas when
  the replacement descriptor kept the same `fileId`/path but changed
  `contentHandle`, because the selector rejected the previous displayed item on
  cache-key mismatch. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts -t
  "file view retains same-file content while a replacement descriptor
  refreshes"` failed with `expected null to be { id: 'file:file-same', ... }`.
  Green fix: strict cache matching remains for fresh `loading`; same `fileId` +
  same path fallback is allowed only for `refreshing`/`stale`, so last good
  content survives until replacement content lands.
  McClintock found two more issues before commit: same-file fresh `openFile()`
  loading could keep rendering a stale cached body, and each selected display
  publish notified app subscribers three times. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts -t
  "file view clears same-descriptor cached body while a fresh open request is
  loading|file view publishes selected display state in one snapshot
  notification"` failed with missing loading helper and `expected 3 to be 1`.
  Green fix: fresh loading deletes the cached item for that file, refresh
  loading preserves the last good item, and content publish uses the batched
  shared-store update.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts
  src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-code-view-items.unit.test.ts
  src/file-viewer/bridge-file-viewer-app.unit.test.ts
  src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts -t
  "Bridge File Viewer render snapshot controller|keeps selected File CodeView
  display behind|Bridge file viewer CodeView item
  adapter|BridgeFileViewerApp|Bridge main render snapshot store"` passed 5
  files / 28 tests, with 19 skipped by the filter.
  `CI=true pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts
  run --project integration-browser
  src/file-viewer/bridge-file-viewer-app.browser.test.tsx -t "renders file body
  without Pierre file header chrome inside the File canvas|keeps the File
  CodeView viewport mounted while selected file content loads|reserves selected
  file scroll extent without rendering retained previous content|does not render
  retained file body while the next selected file content loads|ignores stale
  refresh completion after Files becomes inactive|restores File CodeView scroll
  position after a same-path stale auto refresh|does not repeat silent auto
  refresh for the same stale descriptor after failure"` passed 1 file / 7
  tests, with 43 skipped by the filter.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` over the touched core
  and File View files passed with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` over the touched core and
  File View files passed.
  `git diff --check` passed.
  Source scans over File View/app production surfaces found only absence-test
  strings for forbidden route-local File View store/Zustand/TanStack/SWR/Apollo
  and old shell selected-display tokens.
  Touched file line counts remain under cap; largest touched file is
  `bridge-file-viewer-state.ts` at 802 lines.
- Sidekick evidence:
  Noether verified the source-structure claims: the shell model no longer owns
  selected render-content symbols; the app passes selected CodeView display
  from the new controller; no route-local File View Zustand/TanStack/SWR/Apollo
  cache was introduced; and the controller uses shared
  `createBridgeMainRenderSnapshotStore` + `useSyncExternalStore`. Noether's
  wording caveat is recorded: the snapshot store holds derived display
  `codeViewItem.file.contents`; do not claim it stores no file text at all.
  Feynman's P1 same-file stale-refresh finding and McClintock's P1/P2
  same-file fresh-loading and publish-fanout findings were accepted and fixed
  red-to-green. Kierkegaard performed the closure review and reported ready:
  fresh loading clears, refresh loading retains, wrong-file stale items are
  still rejected, batched publish emits one combined snapshot update, and no
  route-local cache/Zustand/TanStack/SWR/Apollo path was introduced.
- Known proof boundary:
  `runtime.openFile`, `runtime.refreshOpenFile`, `readText()`,
  `WorktreeFileSurfaceRuntime`, synchronous frame intake, descriptor refresh,
  FE demand/runtime authorities, and native/dev content serving remain old-path
  adapter work. This checkpoint proves selected File View CodeView display now
  reads from the shared main render snapshot store, the old shell-model
  selected-display path is deleted, and selected display publishes are batched.

## 2026-07-07 - G4 File View Worker Source Metadata Contract Checkpoint

- Scope:
  Added a typed File View source metadata/request-descriptor update command to
  `BridgeWorkerContracts`, a protocol encoder, command-handler ingestion, and
  worker-local store support for File View metadata demand truth. The File View
  source update path now validates request descriptors at the Zod boundary,
  rejects unsafe scheme URLs and mismatched metadata/descriptors, and repairs
  selected/visible availability plus stale paint when source metadata changes.
  File View-specific source repair lives in
  `bridge-comm-worker-file-view-source-update.ts` so the central worker store
  remains a coordinator rather than absorbing all G4 reconciliation behavior.
- Sidekick findings accepted and fixed:
  Parfit found that the first descriptor contract only typed fields
  individually and did not prove future worker-fetch safety. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts -t "rejects File
  View source updates"` failed because unsafe/mismatched descriptors parsed.
  Green fix: File View descriptor URLs are allowlisted to
  `agentstudio://resource/worktree-file/worktree.fileContent/`, and
  `fileViewSourceUpdate` cross-validates fetchable metadata against exactly one
  matching descriptor. Hooke's re-review found one remaining same-scheme
  hostile URL case where the URL path could name a different descriptor id than
  the descriptor payload. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts -t "rejects File
  View source updates"` failed on a same-scheme
  `descriptor-other` URL. Green fix: the URL parser now extracts the
  file-content descriptor segment and requires it to match `descriptorId`.
  Jason found that File View source updates could leave selected content stuck
  `unavailable` or keep ready paint after metadata became non-fetchable. Red
  proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts -t "file view
  source updates"` failed on unavailable->loading and ready-paint deletion, and
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts -t "file
  view source update command publishes availability repairs"` failed because
  only a health event was emitted. Green fix: File View source updates rebuild
  worker-local metadata indexes, restore selected demand/loading when fetchable
  metadata arrives, delete stale row paint/byte-cache entries when content
  becomes non-fetchable, enqueue typed slice patches, and emit those patches
  before the health ack.
  Jason also found a viewport hot-path churn risk. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts -t "does not churn
  availability state"` failed on `Map` identity. Green fix: viewport updates
  reuse `availabilityByItemId` unless at least one visible item transitions to
  `unavailable`.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts` passed
  4 files / 34 tests.
  Full comm-worker unit battery with 20 explicit files passed 20 files / 98
  tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` over the touched
  comm-worker files passed with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` over the touched files
  passed.
  `git diff --check` passed.
- Line/scope proof:
  Touched scope is confined to `BridgeWeb/src/core/comm-worker`. The largest
  production files remain below 900 lines: `bridge-worker-contracts.ts` 625,
  `bridge-comm-worker-store.ts` 612, and the new
  `bridge-comm-worker-file-view-source-update.ts` 235. Test files
  `bridge-comm-worker-command-handler.unit.test.ts` and
  `bridge-comm-worker-store.unit.test.ts` are over the 600-line smell threshold
  but under the hard refactor prompt; they are carried as follow-up test-support
  extraction candidates rather than blocking this contract checkpoint.
- Known proof boundary:
  This checkpoint does not claim full G4 File View content protocol cutover,
  worker-owned raw content bytes, worker fetch/readText deletion, native/dev
  serving cutover, File View frame/projection intake deletion, G5 demand
  membership cutover, G6 script-message RPC deletion, zero-copy Pierre delivery,
  browser/native UX, fresh F1 worker-fetch proof on current HEAD, or full
  R44/R54/R57/R60 proof.

## 2026-07-07 - G4 File View Selected Runtime Dispatch Checkpoint

- Commit:
  `182a4e1e feat(bridge): add file view selected runtime dispatch`.
- Scope:
  Added `bridge-comm-worker-file-view-runtime.ts` and its unit suite. The worker
  runtime now has a File View selected-content dispatch mirror for Review:
  it checks the selected demand epoch, reads File View metadata from the
  worker-local store, fetches the matching typed File View descriptor, posts a
  prepared `pierreRenderJob` before the content-ready `slicePatch`, commits
  ready only after job preparation, publishes terminal `unavailable` for
  missing metadata/descriptor or non-renderable fetched content, publishes
  terminal `failed` for fetch failure, and drops stale selected work before
  publishing.
- Red/green evidence:
  Initial red proof for the slice failed on the missing runtime helper module.
  After implementation, a reviewer-requested non-renderable-content case first
  exposed a test setup gap because the fake fetcher was not wired and the real
  `agentstudio://` fetch path produced `failed`; the test was corrected to
  exercise the render-job-null branch. Lovelace then found two P2 proof gaps:
  missing File View metadata and stale terminal publish. Both were closed with
  permanent unit coverage. The added proof-gap tests covered already-correct
  branches, so they passed when added rather than requiring a production
  behavior change.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts`
  passed 1 file / 7 tests.
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker` passed 23 files
  / 117 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.ts
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts`
  passed with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.ts
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts`
  passed.
  `git diff --check --` for the two files passed.
- Sidekick review:
  Arendt mapped the File View runtime/protocol gap read-only and confirmed that
  the next required G4 slice must schedule selected File View preparation from
  both `select` and `fileViewSourceUpdate` repair. Lovelace reviewed the
  two-file runtime slice, reported two P2 missing-proof findings, then
  re-reviewed after fixes and returned ready with no new P0-P2 findings.
- Line/scope proof:
  The new runtime file is 187 lines and the unit suite is 479 lines. The commit
  touched only `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-view-runtime.ts`
  and
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts`.
  The signed commit attempt failed before object write with `1Password: failed
  to fill whole buffer`; the checkpoint used the accepted unsigned local
  fallback.
- Known proof boundary:
  This checkpoint is worker-core runtime dispatch proof only. It does not claim
  File View selected preparation scheduler wiring, runtime-protocol File View
  descriptor retention, worker-owned app content loading/readText deletion,
  browser/native UX, G5 demand membership cutover, G6 script-message RPC
  deletion, zero-copy Pierre delivery, or full R44/R54/R57/R60 proof.

## 2026-07-07 - G4 File View Selected Preparation Scheduler Checkpoint

- Commit:
  `8ecb6b5a feat(bridge): schedule file view selected prep in comm worker`.
- Scope:
  File View worker-core now schedules selected content-ready preparation from
  the comm-worker command path for both `select` and `fileViewSourceUpdate`.
  The handler retains previous File View runtime descriptors, store source
  update returns whether selected File View metadata changed, and the ready
  no-op is allowed only when selected demand is current, availability is
  `ready`, selected metadata is unchanged, and the selected request descriptor
  is unchanged. Runtime protocol now retains File View descriptors and drains
  File View selected prep through the shared worker content preparation pump.
- Red/green evidence:
  New command-handler proof covered ready same-cache metadata refresh and ready
  same-cache descriptor refresh. The new tests initially failed because the
  existing ready no-op skipped scheduling for both cases, then passed after the
  scheduler compared metadata and descriptor identity. A reviewer P2 found that
  terminal failure after a ready refresh could leave stale ready paint and byte
  cache. Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-file-view-preparation.unit.test.ts`
  failed on missing `rowPaint` delete in
  `clears stale ready paint when selected File View refresh fetch fails`.
  Green fix: terminal availability now deletes prior `rowPaint`, clears
  `paintReadyByItemId` and `byteCache`, and then publishes terminal
  availability. Reviewer proof gaps were closed by isolating metadata-only
  refresh to `lineCount` and adding a runtime-protocol test proving a ready
  same-cache descriptor refresh drains a second File View prep and posts
  refreshed `pierreRenderJob` plus ready slice.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run src/core/comm-worker` passed 25 files
  / 130 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
  Scoped `pnpm --dir BridgeWeb exec oxlint --type-aware` over the ten touched
  comm-worker files passed with no output.
  Scoped `pnpm --dir BridgeWeb exec oxfmt --check` over the ten touched files
  passed.
  `git diff --check --` over the ten touched files passed.
- Sidekick review:
  Linnaeus first returned `needs fixes` with one P2 stale-ready failure finding
  and two proof gaps. After the red-to-green fix and proof additions, Linnaeus
  re-reviewed read-only and returned `ready`, with the P2 and proof gaps closed
  and no new P1/P2 findings.
- Line/scope proof:
  Touched committed files are confined to `BridgeWeb/src/core/comm-worker`.
  Largest touched production files are under 900 lines:
  `bridge-comm-worker-store.ts` 635 and
  `bridge-comm-worker-command-handler.ts` 562. Largest touched test file is
  `bridge-comm-worker-command-handler.unit.test.ts` 931, under the 1000-line
  cap. Signed commit failed before object write with `1Password: failed to
  fill whole buffer`; the checkpoint used the accepted unsigned local fallback.
- Known proof boundary:
  This checkpoint is worker-core selected preparation scheduler/protocol proof
  only. It does not claim full G4 app-level File View content protocol cutover,
  FE raw body/frame package intake deletion, worker-owned app content loading
  or readText deletion, browser/native UX, G5 demand membership cutover, G6
  script-message RPC deletion, zero-copy Pierre delivery, or full
  R44/R54/R57/R60 proof.

## 2026-07-07 - G4 File View Content Protocol Cutover Checkpoint

- Commit:
  `2c03639d feat(bridge): cut file view content loading to comm worker`.
- Scope:
  Converted File Viewer content loading now routes through the comm-worker
  render snapshot path. The production File Viewer transport no longer exposes
  `fetchResource`; `bridge-file-viewer-runtime.ts` and
  `use-bridge-file-viewer-body-state.ts` are deleted; selected/visible File
  View demand publishes typed worker facts with real viewport indices; and
  File View frame/application state is applied from worker-originated
  snapshot patches. The legacy `worktree-file-surface` wrapper keeps manual
  stale refresh as the explicit old-surface exception.
- Fresh controller proof before commit:
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm --dir BridgeWeb exec oxfmt --check .` passed.
  `pnpm --dir BridgeWeb exec oxlint --type-aware` exited 0 with warnings only.
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-app.unit.test.ts
  src/file-viewer/bridge-file-viewer-tree-panel.unit.test.ts
  src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.file-view.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/core/comm-worker/bridge-worker-file-view-content-ready.unit.test.ts
  src/core/demand/bridge-resource-executor.unit.test.ts
  src/core/demand/bridge-resource-executor.failure-budget.unit.test.ts
  src/app/bridge-file-viewer-worktree-file-surface-transport-adapter.unit.test.ts
  --reporter dot` passed 12 files / 114 tests.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/file-viewer/bridge-file-viewer-app.browser.test.tsx` passed 56/56.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/worktree-file-surface/worktree-file-app.browser.test.tsx` passed 5/5.
  `git diff --cached --check` passed.
- Source scans:
  Deleted-file check passed for `bridge-file-viewer-runtime.ts` and
  `use-bridge-file-viewer-body-state.ts`. Stale auto-refresh and async-cache
  scans found no converted File Viewer production ownership. Zustand/async-cache
  scans matched absence tests only. Tightened production `fetchResource` scan
  matched only `BridgeWeb/src/worktree-file-surface/worktree-file-app.tsx`,
  the legacy wrapper exception. Touched TS/TSX files remained under the
  1000-line cap.
- Sidekick review:
  Socrates reported the missing source-structure proof guard for app-level
  `visibleItemIds` / `selectionSlice` / `viewportSlice`; the guard was added.
  Euclid reported synthetic `0..N` viewport indices and stale G4 proof
  commands; real indices and plan proof commands were added. Both lanes were
  closed before commit.
- Signing:
  Signed commit failed before object write with `1Password: failed to fill
  whole buffer`; unsigned local fallback commit `2c03639d` was used.
- Known proof boundary:
  This is the G4 converted File Viewer content-protocol checkpoint only. It
  does not claim full Review comm-worker cutover, G5 demand membership, G6
  ordinary script-message RPC deletion, native UX/perf closure, zero-copy Pierre
  delivery, or full R44/R54/R57/R60 proof.

## 2026-07-07 - Fresh F1 Worker-Fetch Proof On Current HEAD

- Commit under proof:
  `2c03639d feat(bridge): cut file view content loading to comm worker`.
- Marker:
  `debug-observability-oq4s-1783418131-7443`.
- PID during proof:
  `11885`.
- Startup diagnostic action:
  `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke`.
- Green evidence:
  `CI=true mise run test -- --filter "BridgeSchemeHandlerTests"` passed the
  `BridgeSchemeHandlerTests` Swift suite: 52 tests.
  `mise run observability:up` passed with VictoriaMetrics, VictoriaLogs,
  VictoriaTraces, and OTel collector healthy.
  `mise run verify-debug-observability` passed for the fresh marker.
  `mise run verify-bridge-worker-fetch-scheme-smoke` passed.
- Proof facts:
  Worker-originated request used the content scheme and content resource kind;
  worker fetch completed successfully; held-open streamed response read
  completed successfully; worker observed returned byte count 82; streamed first
  chunk byte count 82; and the stream reader was held open.
- Consequence:
  F1 is fresh for current HEAD and unblocks content-byte / streamed-response
  cutover proof claims for later G slices. It does not prove Review browser UX,
  G5 demand membership deletion, G6 ordinary script-message RPC deletion, or
  native scroll/click performance budgets.

## 2026-07-07 - G4 File View Selected Descriptor Refresh Follow-Up

- Commit under repair:
  `2c03639d feat(bridge): cut file view content loading to comm worker`.
- Root cause:
  The app-level G4 cutover left one old scheduler assumption in the comm-worker:
  when selected File View content was already `ready`, a changed selected
  content request descriptor returned early instead of scheduling selected
  content-ready preparation. React correctly does not request a stale refresh
  when the latest replacement descriptor is already present, so same-path source
  refreshes could leave the selected file stale/manual-refresh-only.
- Production changes:
  `bridge-comm-worker-command-handler.ts` now lets ready selected descriptor
  refreshes schedule selected File View preparation while preserving the true
  ready/no-metadata-change/no-descriptor-change no-op guard.
  `bridge-file-viewer-code-panel.tsx` tracks selected CodeView cache-key
  changes on the same ready path and retargets scroll restoration one additional
  frame so silent worker refreshes do not reset the user's viewport.
- Proof changes:
  `bridge-comm-worker-command-handler.file-view.unit.test.ts` now proves a ready
  descriptor refresh schedules preparation without an explicit follow-up select.
  `bridge-comm-worker-runtime-protocol.unit.test.ts` now proves the runtime
  drains the refreshed File View prep directly after source update.
  `bridge-file-viewer-app.browser.refresh-demand-suite.tsx` adds the missing
  no-navigation `autoOpenInitialFile` same-path source refresh browser proof.
  `bridge-file-viewer-store-source-structure.unit.test.ts` now excludes
  browser-test/test-support harness files from the production scan and forbids
  direct File View production content-fetch tokens from re-entering the app
  surface.
- Red/green evidence:
  Red focused unit failed before production change:
  `scheduledFileViewPreparations` was `[]` instead of length `1` in
  `bridge-comm-worker-command-handler.file-view.unit.test.ts`.
  After the scheduler fix, the focused comm-worker/source-structure proof passed
  4 files / 37 tests.
  The first full File Viewer browser run exposed an adjacent scroll regression
  in the existing same-path refresh scroll test; after the panel retarget fix,
  the focused scroll test passed and the full File Viewer browser file passed
  57/57.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-command-handler.file-view.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  --reporter dot` passed 4 files / 37 tests.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/file-viewer/bridge-file-viewer-app.browser.test.tsx` passed 57/57.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm --dir BridgeWeb exec oxfmt --check .` passed.
  `pnpm --dir BridgeWeb exec oxlint --type-aware` exited 0 with warnings only.
  `git diff --check` passed.
- Sidekick evidence:
  Feynman confirmed the P1 call chain and P2/browser proof gap: the existing
  browser refresh tests were navigation-command-driven, and the missing proof
  was no-navigation auto-open same-path source refresh. Ramanujan reviewed the
  scheduler/browser/static files. Plato found an accepted CodePanel scroll
  inheritance risk; the restore predicate now requires the same rendered file
  identity for load-finished restoration, and queued rAF scroll writes are
  version-guarded so stale writes cannot land after a newer render or file
  open. Parent verification owns final commit readiness.
- Known proof boundary:
  This closes the G4 File View selected descriptor-refresh follow-up only. It
  does not claim Review browser UX closure, G5 demand membership deletion, G6
  script-message RPC deletion, native scroll/click budgets, zero-copy Pierre
  delivery, or full R44/R54/R57/R60 proof.

## 2026-07-07 - G5 Demand Membership Authority Checkpoint

- Commit under repair:
  `d3d6f350 fix(bridge): refresh ready file view descriptors in worker`.
- Scope:
  Worker demand membership derivation is now centralized in
  `bridge-comm-worker-reconciler.ts`. The main comm-worker store and File View
  source-update path call the same pure reconciler and serializer instead of
  maintaining parallel private membership builders. The new worker executor
  seam keeps pacing, in-flight, and delivery-failure backoff below membership
  truth; it does not become a membership owner. Converted Review/File View
  surfaces now have a source-structure guard proving old main demand/resource
  membership owners remain compile-dead for those converted surfaces.
- Red/green evidence:
  Red executor-order proof was observed after Kuhn's sidekick review: the new
  test `preserves reconciler order for equal-rank visible members` failed
  because `planBridgeCommWorkerDemandExecution` returned
  `visible-a, visible-b, visible-c` instead of reconciler/viewport order
  `visible-c, visible-a, visible-b`. The fix removed lexical item-id
  tie-breaking and preserves stable equal-rank membership order.
- Fresh controller proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/demand/bridge-demand-membership-cutover.source-structure.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.file-view.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  --reporter dot` passed 7 files / 40 tests.
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts
  src/core/demand/bridge-demand-membership-cutover.source-structure.unit.test.ts
  src/core/demand/bridge-content-demand-reconciler.unit.test.ts
  src/core/demand/bridge-resource-executor.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-store.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.file-view.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  --reporter dot` passed 10 files / 74 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm --dir BridgeWeb exec oxfmt --check .` passed.
  `pnpm --dir BridgeWeb exec oxlint --type-aware` exited 0 with warnings only.
  `git diff --check` passed.
- Source scans:
  `retryAfterVersion`, `pendingEviction`, `membershipCap`,
  `visibleContentHydrationItemLimit`, and `parked` matches are absence-test,
  docs, or unrelated dev-server selector strings only, not converted-surface
  live demand state. `reviewContentPrefetch` and
  `useBridgeReviewContentPrefetchController` have no `BridgeWeb/src` code hits.
  `reconcileBridgeContentDemand` and `createBridgeResourceExecutor` remain live
  core helpers and tests, but the new source-structure guard proves they are
  compile-dead for converted surfaces. `WorktreeFileDemandStimulus` and
  `createBridgeResourceExecutor` remain in the intentionally unconverted
  `worktree-file-surface` legacy path.
- Architecture checker:
  `pnpm --dir BridgeWeb exec node --experimental-strip-types
  scripts/check-bridgeweb-architecture.ts` exited 1 on pre-existing branch-level
  violations in files outside this G5 diff, including existing worker
  `postMessage` boundary rules, comm-worker contract imports, the Pierre
  planner import, the File View browser harness, review tree telemetry, and
  Pierre/Shiki normalization. This is recorded as out-of-scope for this
  checkpoint; no infrastructure or architecture-lint edits were made.
- Sidekick evidence:
  Hypatia classified demand-membership scans and the architecture checker as
  clean for the converted-surface checkpoint, with remaining old terms limited
  to absence guards, core helper tests, or the unconverted worktree-file
  surface. Kuhn reviewed the seven-file G5 diff and found no checkpoint
  blockers. Kuhn's P2 executor-order finding was accepted and fixed red to
  green before this checkpoint was staged.
- Known proof boundary:
  This is a G5 demand membership authority/deletion-set checkpoint only. It
  does not claim production executor adoption, source-reset chunking/preemption,
  R35 same-queue preemption beyond rank/order seam proof, R58 worker queue-wait
  or handler-duration telemetry, Review browser UX closure, G6 ordinary
  script-message RPC deletion, native scroll/click budgets, zero-copy Pierre
  delivery, or full R44/R54/R57/R60 proof.

## 2026-07-07 - G6 Browser-Native RPC Hard Cutover Checkpoint

- Commit under repair:
  `d3d6f350 fix(bridge): refresh ready file view descriptors in worker`.
- Scope:
  Browser/native ordinary Bridge RPC command dispatch has been cut from the old
  content-world script-message path to scheme RPC. The old
  `bridge-content-world-rpc` TypeScript helper, native `RPCMessageHandler`, and
  privileged-ingress tests are removed. The one remaining production direct
  `webkit.messageHandlers.rpc.postMessage` use is the one-shot page-load
  `bridge.ready` bootstrap path in `BridgeBootstrap.swift`; scheme RPC rejects
  `bridge.ready` as bootstrap-only. Review app tests now inject an in-process
  comm-worker runtime transport instead of reusing the old native script-message
  path, and the Review intake controller retains selection from the live
  selection slice rather than stale root snapshot state.
- Red/green evidence:
  The focused BridgeWeb node pair was red after adding hardening tests:
  malformed ready ACK `{ id }` was accepted, and
  `sendBridgeRPCRequest` threw `ReferenceError: window is not defined` in a
  worker-like runtime. After the production fixes, the focused node pair passed.
  The native cutover source scan was red before the dedicated direct privileged
  relay scan allowlist; after the allowlist was narrowed to bootstrap/test/spike
  files, the source-scan Swift test passed. During final proof, the native
  review browser aggregate also caught one stale expectation that asserted the
  schema-parsed command still contained wire-only `jsonrpc`; the recorder keeps
  the Zod-parsed `BridgeRPCCommand`, while RPC client unit tests own the wire
  envelope proof. The browser aggregate passed after aligning that assertion.
  The final hardening red proof also failed as intended for non-empty/extra
  `bridge.ready` params and source-scan blind spots for alternate RPC spellings
  (`messageHandlers["rpc"]`, optional chaining, and local aliases). The green
  proof passes after strict bootstrap payload validation and broader source
  scanning. `BridgePaneController` push-plan factories were extracted into
  `BridgePaneController+PushPlans.swift` so the cutover stays under SwiftLint
  file/type limits.
- Fresh controller proof:
  `CI=true pnpm -C BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-protocol-router.browser.test.tsx
  src/app/bridge-app-review-intake-reannounce.browser.test.tsx
  src/review-viewer/test-support/bridge-viewer-mocked-backend.browser.test.ts
  src/app/bridge-app-lazy-boundary.browser.test.tsx --reporter dot` passed
  4 files / 33 tests.
  `CI=true pnpm -C BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-native-review-error.browser.test.tsx --reporter dot`
  initially failed on the stale typed-command `jsonrpc` assertion, then passed
  1 file / 14 tests after the assertion was aligned with the schema-parsed
  command recorder.
  `pnpm -C BridgeWeb exec vitest run
  src/bridge/bridge-page-handshake.unit.test.ts
  src/bridge/bridge-rpc-client.unit.test.ts
  src/app/bridge-app-dev-telemetry.unit.test.ts
  src/app/bridge-app-dev-worktree-review.unit.test.ts --reporter dot` passed
  4 files / 33 tests.
  `pnpm -C BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm -C BridgeWeb exec oxlint --type-aware` exited 0 with warnings only.
  `pnpm -C BridgeWeb exec oxfmt --check .` passed.
  `git diff --check` passed.
  `swift test --filter
  'BridgeReadyMessageHandlerTests|BridgeBrowserNativeRPCCutoverSourceScanTests'`
  was red for strict bootstrap params/alternate scan spellings, then passed 7
  Swift Testing tests / 2 suites after the hardening fix.
  `swift test --filter
  'BridgePaneControllerSchemeRPCTests|BridgeReadyMessageHandlerTests|BridgeSchemeHandlerRPCTests'`
  passed 10 Swift Testing tests / 3 suites.
  `SWIFT_TEST_TIMEOUT_SECONDS=300 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=300
  mise run test -- --filter "BridgeBrowserNativeRPCCutoverSourceScanTests"`
  passed 2 Swift Testing tests / 1 suite against packaged BridgeWeb assets.
  The earlier proof note that cited
  `BridgeTransportIntegrationTests.test_schemeRPCBridgeReadyIsRejectedAsBootstrapOnly`
  was stale: that filter matches no current tests. The live native proof for
  bootstrap-only scheme rejection is `BridgePaneControllerSchemeRPCTests`,
  covered by the focused Swift filters above.
  `mise run lint` passed after the push-plan extraction: swift-format OK,
  SwiftLint 0 violations in 1469 files, architecture lint OK, and release script
  verification passed.
- Source scans:
  `rg -n
  "__bridge_command|__bridge_response|data-bridge-nonce|bridge-content-world-rpc|RPCMessageHandler|PAGE_WORLD_ALLOWED_COMMAND_METHODS|sendCommandJSON|content world command|messageHandlers\\.rpc\\.postMessage|messageHandlers\\[[\\\"']rpc[\\\"']\\]|messageHandlers\\?\\.rpc|\\.rpc\\.postMessage"
  BridgeWeb/src Sources/AgentStudio Tests/AgentStudioTests` reports only
  expected bootstrap, negative/source-scan test, and WebKit spike hits. No
  unexpected product live ordinary command path remains.
- Sidekick evidence:
  Gibbs found three accepted G6 hardening issues before this final sweep:
  ready ACK schema validation, worker-safe timers, and a source-scan blind spot
  for direct privileged relays. All three were fixed and independently
  controller-verified with the proof above. Turing then found two additional P2
  hardening gaps: bootstrap payload shape accepted extra/non-empty params, and
  the source scan missed alternate script-message spellings. Both findings were
  accepted, fixed, and controller-verified with the red/green proof above.
- Known proof boundary:
  This is the G6 browser/native ordinary RPC hard-cutover checkpoint. It does
  not claim native/manual UX closure, Review scroll/click budget closure,
  Victoria/debug smoke closure, F1 worker-fetch live proof, slice-G worker data
  migration completion beyond this RPC cutover, PR readiness, or full goal
  completion.

## 2026-07-07 - G6 Post-Review RPC Hardening Checkpoint

- Commit under repair:
  `d807a41a fix(bridge): hard cut over browser native rpc`.
- Scope:
  Post-review hardening of the G6 browser/native ordinary RPC cutover. This
  checkpoint tightens browser-side scheme RPC envelopes, updates browser test
  harnesses to validate the real wire contract, keeps bridge-ready failure
  fail-closed, adds bounded retries for transient post-cutover control RPC
  failures, cleans File View pending-open replay state after failed
  `bridge.intakeReady` including late replay frames, and broadens the Swift
  source scan for direct privileged relay aliases, destructuring, and bracket
  spellings.
- Red/green evidence:
  The hardening tests first failed on missing strict request/response envelope
  exports, dropped awaited trace context, active-viewer updates not retrying
  after a transient failure, metadata interest declarations parking after a
  transient failure, stale File View pending-open replay state after
  `bridge.intakeReady` failure, and source-scan blind spots for aliased or
  bracketed `window.webkit.messageHandlers.rpc.postMessage`. Boole's follow-up
  review then exposed four accepted hardening gaps: metadata retry replayed the
  whole interest batch instead of only failed request keys, the Swift source
  scan missed `window.webkit` / `messageHandlers` alias spellings, one File View
  recovery test still hand-parsed the RPC body, and active-viewer retry lacked
  browser proof. Each gap now has production or harness coverage in this
  checkpoint. Jason's post-fix review then exposed three more accepted gaps:
  exhausted metadata retry budgets did not reset for later fresh request
  signatures, failed File View `bridge.intakeReady` opens could still leak a
  late replayed frame through the live listener, and the source scan missed
  destructured `postMessage` / `window` alias spellings. Red tests reproduced
  all three: metadata saw only 1 foreground retry after a fresh signature where
  2+ were required, File View delivered a late snapshot to a subscriber after
  failed intake-ready, and the Swift scan missed three new alternate spellings.
  The green proof below covers those fixes.
- Fresh controller proof:
  `CI=true pnpm -C BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-review-metadata-interest-runtime.browser.test.tsx
  --reporter verbose` was red on
  `resets exhausted metadata retry budget for a fresh request signature`
  (`expected 1 to be greater than or equal to 2`), then passed 1 file / 6 tests.
  `CI=true pnpm -C BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-native-worktree-file.browser.test.ts --reporter verbose`
  was red on the late-frame assertion (`expected [...] to deeply equal []`),
  then passed 1 file / 27 tests.
  `swift test --filter
  'BridgeBrowserNativeRPCCutoverSourceScanTests/forbiddenRPCSourceScanDetectsAlternateSpellings'`
  was red for the three destructured/alias samples, then passed 1 Swift Testing
  test / 1 suite.
  `pnpm -C BridgeWeb exec vitest run
  src/bridge/bridge-page-handshake.unit.test.ts
  src/bridge/bridge-rpc-client.unit.test.ts
  src/app/bridge-app-dev-telemetry.unit.test.ts
  src/app/bridge-app-dev-worktree-review.unit.test.ts --reporter dot` passed
  4 files / 36 tests.
  `swift test --filter
  'BridgePaneControllerSchemeRPCTests|BridgeReadyMessageHandlerTests|BridgeSchemeHandlerRPCTests|BridgeBrowserNativeRPCCutoverSourceScanTests'`
  passed 12 Swift Testing tests / 4 suites.
  `CI=true pnpm -C BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-protocol-router.browser.test.tsx
  src/app/bridge-app-review-metadata-interest-runtime.browser.test.tsx
  src/app/bridge-app-native-worktree-file.browser.test.ts
  src/app/bridge-app-native-review-error.browser.test.tsx
  src/app/bridge-app-review-intake-reannounce.browser.test.tsx
  src/app/bridge-app-lazy-boundary.browser.test.tsx
  src/review-viewer/test-support/bridge-viewer-mocked-backend.browser.test.ts
  --reporter dot` passed 7 files / 81 tests.
  `pnpm -C BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm -C BridgeWeb exec oxfmt --check .` passed after applying the repo
  formatter to touched BridgeWeb files.
  `pnpm -C BridgeWeb exec oxlint --type-aware` exited 0 with warning-only
  output.
  `git diff --check` passed.
  `SWIFT_TEST_TIMEOUT_SECONDS=300 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=300
  mise run test -- --filter "BridgeBrowserNativeRPCCutoverSourceScanTests"`
  passed 2 Swift Testing tests / 1 suite against rebuilt packaged BridgeWeb
  assets.
  `mise run lint` passed: swift-format OK, SwiftLint 0 violations in 1469
  files, architecture lint OK, and release script verification passed.
  The deletion scan
  `rg -n
  "__bridge_command|__bridge_response|data-bridge-nonce|bridge-content-world-rpc|RPCMessageHandler|PAGE_WORLD_ALLOWED_COMMAND_METHODS|sendCommandJSON|content world command|messageHandlers\\.rpc\\.postMessage|messageHandlers\\[[\\\"']rpc[\\\"']\\]|messageHandlers\\?\\.rpc|\\.rpc\\.postMessage"
  BridgeWeb/src Sources/AgentStudio Tests/AgentStudioTests
  Sources/AgentStudio/Resources/BridgeWeb/app` reports only expected bootstrap,
  negative/source-scan test, and WebKit spike hits.
- Sidekick evidence:
  Maxwell, Sartre, Kierkegaard, Cicero, Lovelace, Sagan, and Laplace were
  closed after their findings were either already addressed or superseded.
  Boole's final read-only review found the four accepted issues listed above;
  all four are addressed and covered by the fresh controller proof. Jason found
  the three accepted post-fix issues listed above; all three are addressed and
  covered by red-to-green proof. Carver then found one more accepted source-scan
  blind spot: destructured `window.webkit` relay forms could evade the direct
  privileged relay matcher. The red proof
  `swift test --filter
  'BridgeBrowserNativeRPCCutoverSourceScanTests/forbiddenRPCSourceScanDetectsAlternateSpellings'`
  failed on
  `const { webkit } = window; webkit.messageHandlers.rpc.postMessage(payload)`;
  after adding direct and aliased destructured-`webkit` samples plus matcher
  branches, the same focused test passed. Ptolemy then found three accepted
  matcher blind spots for nested destructuring and optional calls:
  `const { webkit: { messageHandlers: { rpc: { postMessage: sendRPC } } } } =
  window; sendRPC(payload)`,
  `const { postMessage: sendRPC } = window.webkit.messageHandlers.rpc;
  sendRPC?.(payload)`, and the earlier direct nested destructuring cases through
  `window.webkit.messageHandlers` / `window.webkit`. Each new sample was added
  red-first; the optional-call sample reproduced the normalizer bug where
  `sendRPC?.(payload)` became `sendRPC.(payload)`. After adding direct and
  aliased nested destructuring samples, matcher branches, and a `?.(` to `(`
  normalization before broader `?` stripping, the focused scan test passed.
  The broader focused Swift cutover filter passed 12 tests / 4 suites after a
  serial rerun. One earlier parallel run of that same direct Swift filter failed
  on a transient missing packaged asset (`vue-DRw8dVzS.js`) while the
  packaged-assets command was rebuilding BridgeWeb; it is treated as a harness
  race and was cleared by the serial rerun. The packaged-assets `mise run test
  -- --filter "BridgeBrowserNativeRPCCutoverSourceScanTests"` passed 2 tests /
  1 suite, the raw deletion scan reported only expected bootstrap/test/spike
  hits, and `mise run lint` passed. Peirce's contract sidekick confirmed this
  remains a G6 checkpoint only and must not be reported as full goal closure.
- Known proof boundary:
  This is a G6 browser/native ordinary RPC hardening checkpoint only. It does
  not claim full scheme-stream push/intake/ack cutover, native/manual UX
  closure, Review scroll/click budget closure, Victoria/debug smoke closure,
  PR readiness, or full goal completion.

### 2026-07-08 Pierre shared worker factory/prewarm hardening

- Scope:
  This is a narrow Pierre startup/prewarm support slice. It makes the default
  packaged Pierre worker source load shared between the runtime worker-pool
  provider and activation prewarm, rejects stale in-flight loads after reset,
  and removes the unshared `fetchWorkerSource` prewarm escape hatch. It is
  adjacent to R57/R60 worker bootstrap/prewarm pressure, but it is not a G5/G6
  protocol or final UX-budget closure.
- Changed files:
  `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx`,
  `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-prewarm.ts`,
  and
  `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-factory-loader.unit.test.ts`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/workers/pierre/bridge-pierre-worker-factory-loader.unit.test.ts
  --reporter dot` failed on the new
  `rejects an in-flight load that resolves after reset` test because the stale
  promise resolved with `blob:bridge-pierre-stale` instead of rejecting.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-viewer-activation-prewarm.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-factory-loader.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-initialization-probe.unit.test.ts
  --reporter dot` passed 4 files / 17 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
  `pnpm --dir BridgeWeb exec oxfmt --check
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx
  src/review-viewer/workers/pierre/bridge-pierre-worker-prewarm.ts
  src/review-viewer/workers/pierre/bridge-pierre-worker-factory-loader.unit.test.ts`
  passed. `pnpm --dir BridgeWeb exec oxlint --type-aware` on the same three
  files passed. `git diff --check` passed.
- Sidekick evidence:
  Volta mapped the dirty Pierre files to startup/prewarm support rather than
  G5/G6 closure. Hume found two accepted P2s: stale-reset awaiters could receive
  a revoked factory, and injected prewarm fetch bypassed the shared loader and
  revoke lifecycle. Both were fixed. Hume re-review returned ready with no
  P0-P2 findings. The reviewer still named the concurrent prewarm/provider proof
  as non-blocking missing evidence, but the current test file includes
  `shares one default packaged worker fetch across concurrent prewarm and pool
  load`, and the parent 17-test batch covered it.
- Known proof boundary:
  This checkpoint does not claim full scheme-stream push/intake/ack cutover,
  native/manual UX closure, Review scroll/click budget closure, Victoria/debug
  smoke closure, zero-copy Pierre delivery, PR readiness, or full goal
  completion.

### 2026-07-08 Review CodeView metadata delta apply pump

- Scope:
  This is a narrow Review CodeView main-thread apply-path slice. It keeps
  source reset / mount as the only full baseline `setItems` path, moves stable
  selected / visible / presentation worker-prepared updates into small metadata
  deltas, applies non-reset deltas through the frame apply pump, and cancels
  stale queued metadata apply turns on source reset. It is an R45/R46 hot-path
  repair, not full Review browser/native UX closure.
- Changed files:
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-metadata-apply.ts`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-worker-prepared-items.ts`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel-support.tsx`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts`,
  and
  `BridgeWeb/src/review-viewer/review-viewer-source-structure.unit.test.ts`.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter dot`
  failed 3 tests: visible selected worker item was downgraded to loading,
  one-sided file-targeted `diff` worker item was downgraded to loading, and
  source reset did not invalidate pending metadata apply turns.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-selected-diagnostics.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-selected-apply-pump.unit.test.ts
  src/core/rendering/bridge-frame-apply-pump.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter dot`
  passed 7 files / 63 tests. `pnpm --dir BridgeWeb exec tsc --noEmit --pretty
  false` passed. `pnpm --dir BridgeWeb exec oxfmt --check` on the 8 touched
  files passed after formatting. `pnpm --dir BridgeWeb run lint:types` exited
  0 with repo-wide warning-only output. `git diff --check` passed. Source scan
  for `applyBridgeCodeViewMetadataItems` in `BridgeWeb/src` was clean. Touched
  line counts stayed under 1000 lines.
- Sidekick evidence:
  Wegener found two accepted issues after the first implementation pass:
  selected metadata deltas could still blank valid hydrated selected content,
  and pending metadata apply turns were not invalidated early enough on source
  reset. Both were fixed red-to-green. Faraday found two later P1 hazards:
  non-reset same-id `diff` -> `file` updates could hit Pierre's forbidden
  type-mismatch update path, and source reset could still preserve an old-source
  selected item. Both were fixed: type flips now route through a replacement
  `setItems` path, and source reset passes no preserved item ids. Dalton
  re-reviewed those closures and returned ready with no P0/P1/P2 findings.
- Known proof boundary:
  This checkpoint does not claim full Review scroll/click UX closure, Victoria
  percentile movement, G6 scheme-stream push/intake/ack closure, zero-copy
  Pierre delivery, implementation-review-swarm, PR readiness, or full goal
  completion.

### 2026-07-08 Review worker paint telemetry checkpoint

- Checkpoint commit: `9169c24d fix(bridge): tag worker review paint telemetry`
  (unsigned; signed commit attempt failed before object write with
  `1Password: failed to fill whole buffer`).
- Scope: Review CodeView worker-prepared materialization now records
  `agentstudio.bridge.transport=worker`, selected worker materialization can
  schedule selected-content-painted telemetry with the original click token, and
  selected-content paint package identity is revision-aware so revision-only
  package updates cannot reuse stale click timing.
- Red evidence:
  `CI=true pnpm -C BridgeWeb exec vitest run
  src/app/bridge-app-review-telemetry.unit.test.ts -t "package telemetry keys
  include revision" --reporter dot` failed because both telemetry package keys
  were `package-1:1` before the fix.
- Green evidence:
  `CI=true pnpm -C BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-worker-telemetry.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/foundation/telemetry/bridge-viewer-telemetry-adapter.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/app/bridge-app-review-telemetry.unit.test.ts --reporter dot` passed 8
  files / 77 tests. `pnpm -C BridgeWeb exec tsc --noEmit --pretty false`
  passed. `pnpm -C BridgeWeb exec oxfmt --check .` passed. `pnpm -C BridgeWeb
  exec oxlint --type-aware` exited 0 with repo warning-only output. `git diff
  --check` passed.
- Sidekick evidence:
  Goodall the 2nd reviewed the dirty diff and reported one P2 telemetry
  correctness issue: selected-content paint tokens were keyed without
  `revision`. The fix made `makeTelemetryPackageKey()` revision-aware and added
  the regression above. No P0/P1 findings were reported.
- Known proof boundary:
  This checkpoint does not claim live Review scroll/click UX closure, Victoria
  percentile movement, render-proof success, G6 scheme-stream push/intake/ack
  closure, zero-copy Pierre delivery, implementation-review-swarm, PR
  readiness, or full goal completion.

### 2026-07-08 Review worker paint probe P2 closure

- Checkpoint commit: `f5a03faa fix(bridge): correct review worker paint probes`
  (unsigned; signed commit attempt failed before object write with
  `1Password: agent returned an error`).
- Scope: closed the two P2 findings from Goodall the 2nd's second review.
  Anchored-delivery debug probes now report `hasAnchor` only when the
  selected-content paint start token actually matches the selected worker item,
  and source-reset `setItems` records worker materialization telemetry for every
  materialized worker-prepared reset item instead of selected-only.
- Red evidence:
  `CI=true pnpm -C BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts -t "reports
  selected paint telemetry anchors|source reset records worker materialization
  telemetry" --reporter dot` failed 2/2 before the fix: the source still
  contained `hasAnchor: true` and the reset path did not loop over every item.
- Green evidence:
  The same filtered test passed 2/2 after the fix. `CI=true pnpm -C BridgeWeb
  exec vitest run` over the focused 8-file Review CodeView/telemetry battery
  passed 8 files / 79 tests. `pnpm -C BridgeWeb exec tsc --noEmit --pretty
  false` passed. `pnpm -C BridgeWeb exec oxfmt --check .` passed. `pnpm -C
  BridgeWeb exec oxlint --type-aware` exited 0 with repo warning-only output.
  `git diff --check` passed.
- Known proof boundary:
  This closes the deterministic P2s only. Browser-worker proof for actual
  Review click/apply telemetry and oq4s marker-scoped Victoria proof for
  `code_view_item_materialize` selected true/false with
  `agentstudio.bridge.transport=worker` remain open.

### 2026-07-08 Native admission for worker review paint telemetry

- Scope: native telemetry validator admission only. BridgeWeb already emits
  worker-prepared Review paint/materialization telemetry with
  `agentstudio.bridge.transport=worker`; native validation still accepted those
  two hot paint contracts only when transport was `swift`, so worker paint rows
  were rejected before they could reach VictoriaLogs.
- Fix: `BridgeTelemetryBatchValidator+ClickLatencyContracts.swift` now accepts
  both `swift` and `worker` transport for
  `code_view_item_materialize` and `selected_content_painted`, while preserving
  the exact phase, plane, priority, slice, and attribute-key contracts.
- Red evidence:
  `swift test --filter
  BridgeTelemetryBatchValidatorTests/validatorAcceptsWorkerPreparedReviewPaintEmitterShapes`
  failed before the fix with both worker samples rejected as unsafe attributes.
- Green evidence:
  `swift test --filter BridgeTelemetryBatchValidatorWorkerPaintTests` passed
  1 test / 1 suite. `swift test --filter BridgeTelemetryBatchValidatorTests`
  passed 29 tests / 3 suites. `swift test --filter BridgeTelemetryIngestorTests`
  passed 8 tests / 1 suite. `git diff --check` passed. `mise run lint` passed
  swift-format, SwiftLint with 0 violations, AgentStudio architecture lint, and
  release script verification.
- Known proof boundary:
  This repairs the native telemetry admission layer only. It does not prove the
  browser emitted selected paint in the current live app, does not prove
  Victoria percentile movement, does not prove render-proof success, and does
  not close the Review scroll/click UX issue.

### 2026-07-08 Telemetry flush sequence retry integrity

- Scope: narrow R43 telemetry integrity repair for browser/page and comm-worker
  telemetry batch sequencing. Live oq4s after worker paint admission still
  showed `missing_drop_counter` storms. Source inspection found both telemetry
  clients advanced their batch sequence before knowing whether `sink.flush(...)`
  accepted the drained snapshot. If the sink returned `false`, samples were
  restored but the next accepted retry used sequence 2, so native correctly
  rejected the stream as a sequence gap without a lossless drop counter.
- Fix: `createEnabledBridgeTelemetryRecorder` and
  `createBridgeCommWorkerTelemetryClient` now peek the next sequence, restore
  the drained snapshot on `flush === false`, and commit the sequence only after
  a successful flush.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts --reporter dot`
  failed before the fix: three retry-path assertions observed sequence `2`
  instead of sequence `1`.
- Green evidence:
  The same focused command passed 2 files / 12 tests after the fix. A wider
  focused telemetry battery passed 4 files / 16 tests:
  `src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts`,
  `src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts`,
  `src/foundation/telemetry/bridge-telemetry-buffer.unit.test.ts`, and
  `src/core/comm-worker/bridge-comm-worker-runtime-protocol.telemetry.unit.test.ts`.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed. Scoped
  `oxfmt --check`, scoped `oxlint --type-aware`, and `git diff --check`
  passed. Parent re-ran the focused 2-file command immediately before commit
  and it passed 2 files / 12 tests.
- Sidekick evidence:
  Hegel the 2nd reviewed the four-file diff and reported `ready` with no
  P0-P3 findings. The sidekick independently checked the focused Vitest, `tsc`,
  and scoped `oxlint` gates.
- Known proof boundary:
  This fixes retry sequencing only for a `false` sink return. The current oq4s
  marker still shows one `unsafe_attribute` rejection for
  `performance.bridge.web.first_render`, no
  `performance.bridge.web.selected_content_painted` rows, and remaining
  `missing_drop_counter` rows. Follow-up work must trace whether invalid
  first-render emission and the fire-and-forget fetch telemetry sink are still
  advancing streams past native rejection.

### 2026-07-08 Review first-render telemetry revision-key repair

- Scope: narrow BridgeWeb telemetry emitter correctness repair for the live
  oq4s `unsafe_attribute` drop where
  `performance.bridge.web.first_render` was the first rejected event.
- Root cause: the Review intake/apply path stores telemetry context and
  review-ready timing under the revision-aware `makeTelemetryPackageKey()`
  (`packageId:reviewGeneration:revision`), but
  `useBridgeReviewRenderTelemetryController` looked up both `first_render` and
  `review_ready` with only `packageId:reviewGeneration`. After the earlier
  revision-key hardening, that guaranteed a miss and made `first_render` emit
  `agentstudio.bridge.slice=unknown` and
  `agentstudio.bridge.transport=unknown`, which Swift correctly rejected.
- Fix: `bridge-app-review-telemetry-controller.ts` now imports and uses
  `makeTelemetryPackageKey(props.reviewPackage)` for both first-render and
  review-ready lookup/dedupe paths.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts -t "keeps
  Review render telemetry package keys aligned" --reporter dot` failed before
  the fix because the render telemetry controller did not use
  `makeTelemetryPackageKey(` and still contained the raw
  `` `${props.reviewPackage.packageId}:${props.reviewPackage.reviewGeneration}` ``
  lookup.
- Green evidence:
  The same filtered source-structure test passed after the fix. The focused
  BridgeWeb unit battery
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app-review-telemetry.unit.test.ts
  src/app/bridge-app.unit.test.ts --reporter dot` passed 3 files / 55 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed. Scoped
  `oxfmt --check`, scoped `oxlint --type-aware`, and `git diff --check`
  passed. `swift test --filter BridgeTelemetryBatchValidatorTests` passed
  29 tests / 3 suites, proving the native first-render contract stayed strict.
- Sidekick evidence:
  Tesla the 2nd independently traced the live drop to this BridgeWeb-side
  revision-key mismatch and recommended fixing the emitter rather than widening
  Swift. Laplace the 2nd reviewed the two-file implementation diff and reported
  `ready` with no P0-P3 findings and no material missing proof for the scoped
  diff.
- Known proof boundary:
  This should eliminate the first-render `unsafe_attribute` source on a fresh
  build, but it does not fix async telemetry POST false-success semantics, does
  not prove `selected_content_painted` live emission, does not close remaining
  `missing_drop_counter` rows, and does not claim Review scroll/click budget
  closure.

### 2026-07-08 Telemetry stream-id sequence hard cutover

- Scope: narrow R43 telemetry integrity repair for browser/page and comm-worker
  telemetry producer identity. The wire batch contract now requires
  `streamId: "page" | "comm-worker"`; the page recorder, comm-worker telemetry
  client, real worker entry, Vite/dev telemetry builder, and direct tests emit
  the stream id.
- Root cause: page and comm-worker telemetry are separate producers with
  independent sequence counters, but Swift validator state previously keyed
  monotonic sequence by one global scenario stream. That made live proof fragile:
  a valid worker batch could collide with page sequencing and produce
  `missing_drop_counter` drops. Sidekick correction remains important: this was
  not the only possible missing-drop source, because the current telemetry
  scheme sink is still fire-and-forget and can report success before native
  acceptance.
- Fix: `BridgeTelemetryBatch` carries `streamId`; JSON without `streamId` fails
  decode; `BridgeTelemetryBatchSequenceState` tracks last sequence per stream;
  TS batch construction is props-based and cannot omit the stream id without
  TypeScript failure.
- Red evidence:
  Focused BridgeWeb telemetry tests failed before production edits because page
  and worker batches lacked `streamId`. The Swift legacy JSON test failed before
  the native model change because a batch without `streamId` decoded as valid.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts
  src/bridge/bridge-telemetry-event-sink.unit.test.ts
  scripts/dev-server/bridge-dev-telemetry.unit.test.ts --reporter dot` passed
  4 files / 24 tests. `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed. `pnpm --dir BridgeWeb exec oxfmt --check` on touched TS files passed.
  `pnpm --dir BridgeWeb exec oxlint --type-aware` on touched TS files exited 0
  with one warning-only pre-existing `no-array-sort` note in dev telemetry.
  `swift test --filter BridgeTelemetryBatchValidatorTests` passed 28 tests /
  3 suites. `swift test --filter BridgeTelemetryBatchValidatorSequenceTests`
  passed 3 tests / 1 suite. `mise run lint -- <touched files>` passed
  swift-format, SwiftLint, AgentStudio architecture lint, and release script
  checks. `git diff --check` passed.
- File-size guard:
  `BridgeTelemetryBatchValidatorTests.swift` is 895 lines after moving sequence
  coverage into `BridgeTelemetryBatchValidatorSequenceTests.swift` at 224 lines.
- Known proof boundary:
  This closes producer stream identity and native sequence scoping only. It does
  not prove live Victoria non-lossy telemetry yet, does not fix the async
  fire-and-forget telemetry POST acceptance gap if that remains, does not prove
  selected paint/materialize rows on the current oq4s app, and does not close
  Review scroll/click budgets.

### 2026-07-08 G6 Review mark-viewed worker RPC hard cutover

- Scope: narrow G6 ordinary-RPC cutover for `review.markFileViewed`. Review
  selection no longer owns page-world `BridgeRPCClient` for mark-viewed. The
  render snapshot controller dispatches a typed `markFileViewed` comm-worker
  command carrying native `fileId`; the comm worker forwards it to Swift through
  scheme RPC POST and reports correlated ready/degraded health.
- Root cause: the pre-cutover page-owned RPC path could keep an ordinary Review
  command on the deprecated script-message/page-world boundary. The first fix
  also left a silent-loss gap where post-bootstrap in-flight mark-viewed
  requests had no request-correlated degraded event if the worker died before
  replying.
- Fix: `BridgeWorkerContracts` and protocol encoders now use `fileId` for
  `markFileViewed`; `BridgeAppReviewSelectionController` receives a worker
  callback instead of an RPC client; `BridgeAppReviewRenderSnapshotController`
  owns request ids and delivery-failure callbacks; the worker runtime withholds
  ready health until scheme RPC resolves and emits degraded health on scheme
  failure; transport tracks queued and in-flight mark-viewed request ids and
  emits correlated degraded health on startup, invalid-message, worker-error, or
  command-post failure before state reset.
- Red evidence:
  The focused G6 unit battery first failed six tests because old protocol fields
  and page-owned RPC were still present. A hostile stale-forwarding test failed
  because stale `markFileViewed` commands still forwarded. The scheme-RPC
  completion tests failed because ready health emitted before Swift scheme RPC
  resolved. The queued transport-failure test failed because only bootstrap
  degraded health emitted. After sidekick review, the new
  `in-flight mark-viewed` transport test failed because post-bootstrap worker
  error still omitted correlated degraded health for the command request id.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/app/bridge-app-review-selection-controller.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  --reporter dot` passed 7 files / 95 tests. `pnpm --dir BridgeWeb exec
  tsc --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed. Source scans found no
  `filePathHash` or `viewedAtSequence` in the converted BridgeWeb surfaces, and
  no `review.markFileViewed`, `BridgeRPCClient`, `sendCommandAndWait`, or
  `rpcClient` in the Review selection controller/test. The only remaining
  `review.markFileViewed` matches in the converted implementation are the
  worker-owned scheme RPC forwarder and tests.
- Sidekick evidence:
  Rawls mapped the smallest cutover route and recommended render-snapshot
  ownership plus native `fileId`. Euler mapped the next metadata-interest
  sibling cutover. Maxwell found the premature-ready P1, then the in-flight
  post-bootstrap transport P1; both were fixed red-to-green, and Maxwell's final
  re-review reported `ready` with no remaining concrete issue for this closure.
- Known proof boundary:
  This is one ordinary Review RPC cutover only. It does not remove the remaining
  Review metadata-interest page RPC, does not finish scheme-stream push/intake/
  ack cutover, does not prove native oq4s scroll/click budgets, does not close
  Review main-thread apply/materialization lag, does not claim implementation
  review swarm, PR readiness, or full goal completion.

### 2026-07-08 G6 Review metadata-interest worker RPC hard cutover

- Scope: narrow G6 ordinary-RPC cutover for
  `bridge.metadata_interest.update`. Review metadata-interest runtime no longer
  owns a page-world `BridgeRPCClient`; it receives a full
  `ReviewMetadataInterestRequest` sender callback. The render snapshot
  controller dispatches typed `metadataInterestUpdate` worker commands, and the
  comm worker forwards them to Swift through scheme RPC POST.
- Root cause: metadata-interest was the remaining Review ordinary-RPC sibling
  after `review.markFileViewed`. Keeping it on page-owned RPC preserved a dual
  carrier and could mask worker-path failures. The first WIP also needed the
  same correlated transport failure semantics as mark-viewed, otherwise
  metadata-interest retry could hang or stop without true native delivery.
- Fix: added Zod-derived `metadataInterestUpdate` worker contract, protocol
  encoder, inert client method, command-handler acceptance, worker runtime
  scheme-RPC forwarding, and request-correlated ready/degraded resolution in
  the render snapshot controller. Transport failure fan-out is generalized from
  mark-viewed-only tracking to awaited ordinary RPC command tracking for queued
  and in-flight requests. Runtime command routing and Review worker health
  resolution were extracted so touched large files did not keep growing.
- Red evidence:
  The focused metadata-interest battery first failed because
  `encodeBridgeWorkerMetadataInterestUpdateCommand` was missing and the source
  guard still found `createBridgeRPCClient`/`rpcClient` in
  `BridgeReviewViewerMode`. After sidekick review, added queued and in-flight
  metadata-interest transport failure tests; they failed because transport
  emitted only bootstrap degraded health and no request-correlated degraded
  event. Runtime metadata-interest tests also failed until the command had a
  worker telemetry lane.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/app/bridge-app-review-render-snapshot-controller.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  --reporter dot` passed 6 files / 94 tests. `CI=true pnpm --dir BridgeWeb
  exec vitest --config vitest.browser.config.ts run --project
  integration-browser
  src/app/bridge-app-review-metadata-interest-runtime.browser.test.tsx
  --reporter dot` passed 1 file / 6 tests. `pnpm --dir BridgeWeb exec
  tsc --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed. Source scans found no
  `createBridgeRPCClient`, `BridgeRPCClient`, `sendCommandAndWait`,
  `rpcClient`, or `bridge.metadata_interest.update` in the production Review
  metadata-interest runtime/mode files.
- File-size proof:
  `bridge-app-review-render-snapshot-controller.ts` was 753 lines at HEAD and
  is 769 after extraction. `bridge-comm-worker-runtime-protocol.ts` was 830
  lines at HEAD and is 806 after extracting runtime command routing.
- Sidekick evidence:
  Hilbert reviewed the metadata-interest cutover and identified the
  request-correlated delivery contract, the mark-viewed-only transport fan-out,
  full DTO preservation for stale clears, and mandatory deletion fence. The
  accepted P1/P2 items are represented in the tests and fixes above.
- Known proof boundary:
  This is one ordinary Review RPC cutover only. It does not finish
  scheme-stream push/intake/ack cutover, does not prove native oq4s
  scroll/click budgets, does not close Review main-thread apply/materialization
  lag, does not claim implementation review swarm, PR readiness, or full goal
  completion.

### 2026-07-08 G6 worker scheme RPC timeout follow-up

- Scope: narrow reliability follow-up for the G6 ordinary-RPC worker forwarder
  shared by `review.markFileViewed` and `bridge.metadata_interest.update`.
  Worker-owned scheme RPC forwarding now has a bounded timeout so a
  never-settling scheme sender cannot withhold request-correlated `ready` or
  `degraded` health forever.
- Root cause: the metadata-interest cutover correctly withheld `ready` until
  Swift scheme RPC resolved, but the worker wrapper trusted the scheme sender to
  always settle. The old page-world RPC client had a bounded timeout, so the
  cutover accidentally weakened the failure contract for hung native delivery.
- Fix: `registerBridgeCommWorkerRuntimePortProtocol` accepts an injectable
  `schemeRpcTimeoutMilliseconds`, defaults scheme RPC forwarding to 5000 ms,
  wraps both injected and default scheme senders with timeout handling, forwards
  the timeout through `sendBridgeRPCRequest`, and reports request-correlated
  degraded health instead of leaving the request parked.
- Red evidence:
  The new runtime-protocol test
  `reports degraded health when metadataInterestUpdate scheme RPC forwarding
  never settles` failed before the production change because no degraded health
  was emitted after advancing fake timers.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  --reporter dot` passed 1 file / 17 tests. The focused G6 worker/control
  battery passed 6 files / 95 tests:
  `src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`,
  `src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts`,
  `src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`,
  `src/review-viewer/review-viewer-source-structure.unit.test.ts`, and
  `src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts`.
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-review-metadata-interest-runtime.browser.test.tsx
  --reporter dot` passed 1 file / 6 tests. `pnpm --dir BridgeWeb exec tsc
  --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Sidekick evidence:
  Ohm the 2nd identified the accepted P1: worker-owned metadata-interest RPC
  could hang forever if scheme RPC never settled. The red fake-timer test and
  timeout wrapper represent that finding.
- Known proof boundary:
  This checkpoint only bounds the ordinary scheme-RPC forwarder. It does not
  finish active-viewer-mode cutover, scheme-stream push/intake/ack cutover,
  native oq4s scroll/click proof, Review apply/materialization lag closure,
  implementation-review-swarm, PR readiness, or full goal completion.

### 2026-07-08 G6 active-viewer-mode ordinary RPC cutover

- Scope:
  Active viewer mode updates are routed through the comm-worker ordinary command
  path and worker-owned scheme RPC forwarding. `BridgeApp` no longer owns a
  page-world `BridgeRPCClient` for `bridge.activeViewerMode.update`.
- Implementation:
  Added typed `activeViewerModeUpdate` worker command encoding, client surface,
  command handler acceptance, runtime command routing, scheme-RPC forwarding,
  and transport health semantics. `BridgeApp` now creates a narrow
  `createBridgeReviewRuntimeProtocolDispatcher` for active-mode notifications,
  resolves request promises from request-correlated worker health, retries
  definite pre-delivery failures, and treats `unknownAfterDispatch` as sent to
  avoid duplicate fresh-sequence notifications after ambiguous delivery.
- Accepted sidekick findings:
  Hooke the 2nd found a P1 queued-bootstrap-flush gap: a synchronous
  `postMessage` throw while flushing queued `activeViewerModeUpdate` commands
  could escape without request-scoped degraded health, leaving the app-side
  resolver pending. Red proof failed on the new queued-flush test with an
  unhandled `worker postMessage failed` and no terminate/reset. The fix shifts
  queued commands one at a time, catches flush-time post failures, publishes the
  failed queued command as a definite pre-delivery failure, and lets remaining
  queued awaited commands be failed by bootstrap reset.
  Volta the 2nd found a P1 degraded-bootstrap gap: queued
  `activeViewerModeUpdate` commands were reset after bootstrap degraded health
  without request-scoped failure. Red proof failed because only bootstrap
  degraded health was published. The fix publishes queued and in-flight awaited
  ordinary-RPC failures before degraded-bootstrap reset, and the browser proof
  verifies `BridgeApp` retries the first active-mode signal after receiving
  that request-scoped failure.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  -t "queued active-viewer-mode flush" --reporter dot` passed 1/1 after the
  red failure. `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  -t "bootstrap degrades" --reporter dot` passed 1/1 after the degraded-health
  red failure. `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  --reporter dot` passed 16/16. Browser proof
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-protocol-router.browser.test.tsx -t "queued bootstrap
  degradation" --reporter dot` passed 1/1. Focused G6 battery
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  src/app/bridge-app-source-structure.unit.test.ts --reporter dot` passed
  5 files / 59 tests. Browser protocol router
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-protocol-router.browser.test.tsx --reporter dot` passed
  1 file / 14 tests. `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed. Scoped `oxfmt --check`, scoped `oxlint --type-aware`, and
  `git diff --check` passed.
- Source scans:
  `rg -n "createBridgeRPCClient|sendCommandAndWait|method:
  'bridge.activeViewerMode.update'|activeViewerModeRPCClient"
  BridgeWeb/src/app/bridge-app.tsx || true` returned no production
  `BridgeApp` matches. Wider scan matches are limited to browser assertion,
  negative source guard, worker command routing, and worker runtime tests.
- Line proof:
  `bridge-app.tsx` 610 lines, `bridge-app-protocol-router.browser.test.tsx`
  900 lines, `bridge-worker-contracts.ts` 781 lines,
  `bridge-comm-worker-command-handler.ts` 940 lines,
  `bridge-comm-worker-runtime-protocol.ts` 856 lines, and
  `bridge-comm-worker-transport.unit.test.ts` 956 lines. The extracted
  `bridge-comm-worker-transport.test-support.ts` is 68 lines.
- Known proof boundary:
  This is one active-viewer-mode ordinary RPC hard-cutover checkpoint. It does
  not finish scheme-stream push/intake/ack cutover, native oq4s scroll/click
  proof, Review apply/materialization lag closure, implementation-review-swarm,
  PR readiness, or full goal completion.

### 2026-07-08 G6 Review intake-ready ordinary RPC cutover

- Scope:
  Review `bridge.intakeReady` is routed through the comm-worker ordinary
  command path and worker-owned scheme RPC forwarding. `BridgePageHandshakeSession`
  no longer owns `markIntakeReady`, and the Review intake controller no longer
  imports or calls the page-world handshake RPC sender for this command.
- Implementation:
  Added typed `reviewIntakeReady` worker command encoding, inert client method,
  command handler acceptance, runtime command routing to `bridge.intakeReady`,
  and transport failure wording. `useBridgeReviewRenderSnapshotController` now
  dispatches a request-correlated `reviewIntakeReady` worker command and
  resolves completion from worker health. `useBridgeReviewIntakeController`
  now receives stable `getPushNonce` and `sendReviewIntakeReady` callbacks,
  gates success until a push nonce exists, and preserves the existing retry /
  replay behavior. Browser reannounce proof now observes the worker runtime's
  injected scheme-RPC sender instead of spying page `fetch`.
- Accepted sidekick findings:
  Avicenna the 2nd found the browser proof was still booting the real
  comm-worker transport and failing Chromium's custom-scheme worker-script
  fetch before `bridge.intakeReady` could be observed. The fix uses the existing
  in-process review-worker transport and exposes its runtime `sendSchemeRpcCommand`
  seam for browser tests. Kierkegaard the 2nd found two P1 production regressions:
  intake-ready could be marked successful before the page had a push nonce, and
  the new inline `getPushNonce` closure reinstalled the intake controller effect
  on every render, causing repeated announces. The fix restores the nonce gate
  and memoizes `getPushNonce` in Review mode. Kierkegaard also found a P2
  missing negative-path proof; this checkpoint adds dedicated runtime tests for
  failed and never-settling `reviewIntakeReady` scheme RPC forwarding. Russell
  the 2nd supplied the source-scan and proof-pack commands used below.
- Red / green evidence:
  Browser red before the P1 fixes:
  `CI=true pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts
  run --project integration-browser
  src/app/bridge-app-review-intake-reannounce.browser.test.tsx --reporter dot`
  failed with `reviewIntakeReadyCount` inflating to 3-4 and
  `TypeError: Failed to fetch`. After the test seam isolation, nonce gate, and
  stable `getPushNonce`, the same command passed 1 file / 4 tests.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.review-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.review-intake-ready.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts
  src/bridge/bridge-page-handshake.unit.test.ts --reporter dot` passed
  7 files / 87 tests. Browser proof `CI=true pnpm --dir BridgeWeb exec vitest
  --config vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-review-intake-reannounce.browser.test.tsx --reporter dot`
  passed 1 file / 4 tests. Adjacent proof:
  `CI=true pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts
  run --project integration-browser
  src/app/bridge-app-protocol-router.browser.test.tsx --reporter dot` passed
  1 file / 14 tests, and
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  --reporter dot` passed 1 file / 16 tests. `pnpm --dir BridgeWeb exec tsc
  --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Source scans:
  `rg -n "markIntakeReady|bridge\.intakeReady"
  BridgeWeb/src/app/bridge-app-review-intake-controller.ts
  BridgeWeb/src/bridge/bridge-page-handshake.ts` returned no matches.
  `rg -n "spyOn\(globalThis, 'fetch'\)|recordBridgeSchemeRPCFetch"
  BridgeWeb/src/app/bridge-app-review-intake-reannounce.browser.test.tsx`
  returned no matches. Wider scans show `bridge.intakeReady` only in allowed
  worktree-file paths, tests, source-structure guards, worker runtime routing,
  and comm-worker transport failure wording.
- Package check boundary:
  `pnpm -C BridgeWeb check` still exits 1 on pre-existing branch-level
  architecture lint / line-cap debt, including worker-boundary rules,
  `bridge-comm-worker-command-handler.unit.test.ts` (1161 lines at HEAD and
  after this split), `bridge-comm-worker-runtime-protocol.unit.test.ts`
  (1733 lines at HEAD, 1734 after this split), and generic core import
  boundary findings in `bridge-worker-contracts.ts`. This checkpoint moved new
  review-intake runtime and command-handler proof into dedicated small files
  instead of growing the oversized suites further.
- Known proof boundary:
  This is one Review intake-ready ordinary RPC hard-cutover checkpoint. It does
  not finish worktree-file intake-ready migration, scheme-stream push/intake/ack
  cutover, native oq4s scroll/click proof, Review apply/materialization lag
  closure, implementation-review-swarm, PR readiness, or full goal completion.

## 2026-07-08 - G6 Worktree/File Intake-Ready Ordinary RPC Cutover

- Commit target:
  pending local checkpoint `feat(bridge): route worktree file intake ready
  through comm worker`.
- Scope:
  Worktree/File `bridge.intakeReady` no longer uses the page/main direct
  `sendBridgeRPCRequest` sender from
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts`. The backend now calls
  `sendWorktreeFileIntakeReady` through a typed comm-worker ordinary RPC sender
  in `BridgeWeb/src/app/bridge-app-native-worktree-file-intake-ready.ts`.
- Implementation:
  Added `worktreeFileIntakeReady` to the zod-derived comm-worker command union,
  encoder, inert client, command handler, telemetry lane, runtime scheme-RPC
  routing, and shared transport awaited-RPC failure classification. Runtime
  routing maps to `bridge.intakeReady` with `protocolId`, `streamId`, and
  `generation`. The default Worktree/File intake-ready sender bootstraps the
  packaged comm worker, dispatches
  `encodeBridgeWorkerWorktreeFileIntakeReadyCommand`, resolves only from
  request-correlated worker health, and now has a bounded timeout wired to
  `responseTimeoutMilliseconds ?? defaultResponseTimeoutMilliseconds`.
- Browser harness honesty:
  Worktree/File browser test support now injects a fake worker sender for
  `bridge.intakeReady` and rejects any `bridge.intakeReady` call observed on
  the `fetchRPC` path, so direct page-RPC regressions cannot false-green the
  browser suites.
- Line-cap containment:
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts` is 956 lines after the
  helper extraction, down from 978 at HEAD and below the 1000-line cap. New
  proof lives in small dedicated files instead of growing the oversized shared
  transport suite.
- Accepted sidekick findings:
  Hubble the 2nd verified deletion scans and typed routing, then flagged proof
  holes around the default sender and shared transport coverage. Newton the
  2nd found two accepted findings: the default sender could park forever when
  worker health never arrived, and the browser harness still allowed deleted
  direct `bridge.intakeReady` fetches to pass. The fix adds default sender
  timeout proof, default transport proof, dedicated Worktree/File transport
  failure proof, and harness rejection for direct intake-ready fetches.
- Red / green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-native-worktree-file-intake-ready.unit.test.ts --reporter
  dot` failed before the timeout fix with the new timeout test receiving
  `"still-pending"` instead of `false`; the same file passed after the timeout
  implementation. A first version of the shared transport in-flight test also
  failed because the setup queued an awaited intake-ready command before
  bootstrap; the corrected setup uses a non-awaited select primer and passed,
  confirming queued awaited commands are degraded when appropriate.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-source-structure.unit.test.ts
  src/app/bridge-app-native-worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.worktree-file-intake-ready.unit.test.ts
  --reporter dot` passed 10 files / 79 tests.
  Browser proof `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-native-worktree-file.browser.test.ts
  src/app/bridge-app-native-review-error.browser.test.tsx --reporter dot`
  passed 2 files / 41 tests. `pnpm --dir BridgeWeb exec tsc --noEmit --pretty
  false` passed. Scoped `oxfmt --check`, scoped `oxlint --type-aware`, and
  `git diff --check` passed. `oxlint --type-aware` still prints pre-existing
  warning-only output for `__bridgeNativeWorktreeFileProbe`, missing
  `targetOrigin` in older recovery-suite test postMessage calls, and
  `handleReady` consistent-function-scoping in Review test support; exit code
  was 0.
- Source scans:
  Targeted scans in `BridgeWeb/src/app/bridge-app-native-worktree-file.ts` for
  `sendNativeBridgeIntakeReadyCommand`, `method: bridgeIntakeReadyMethod`,
  `protocolId: 'worktree-file'`, and `bridgeIntakeReadyMethod` returned no
  matches. Wider production scan for `bridge.intakeReady` found only allowed
  schema/routing/failure-text/mock-backend surfaces:
  `BridgeWeb/src/bridge/bridge-rpc-client.ts`,
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-command-routing.ts`,
  `BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.ts`,
  and `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts`.
- Known proof boundary:
  This is one Worktree/File intake-ready ordinary RPC hard-cutover checkpoint.
  It does not finish scheme-stream push/intake/ack cutover, native oq4s
  scroll/click proof, Review apply/materialization lag closure,
  implementation-review-swarm, PR readiness, or full goal completion.

## 2026-07-08 - G6 Worktree/File Surface RPC Cutover

- Commit target:
  pending local checkpoint `feat(bridge): route worktree file surface rpc
  through comm worker`.
- Scope:
  Worktree/File `worktreeFileSurface.openSourceStream` and
  `worktreeFileSurface.requestFileDescriptor` now route through the packaged
  comm-worker ordinary command path and worker-owned scheme RPC forwarding.
  The app-side Worktree/File backend no longer constructs those page/main RPC
  commands directly.
- Implementation:
  Added typed `worktreeFileOpenSourceStream` and
  `worktreeFileRequestDescriptor` worker commands, runtime routing to
  `worktreeFileSurface.openSourceStream` and
  `worktreeFileSurface.requestFileDescriptor`, and a typed
  `worktreeFileOpenSourceStreamResult` server-to-main event for the open
  outcome. The Worktree/File worker RPC transport now owns pending open,
  descriptor, and intake-ready requests in one discriminated pending map. Open
  commands reserve monotonic worker epochs, intake/descriptor commands record
  observed generations, and open-result success records the accepted generation
  before resolving.
- Accepted sidekick findings:
  Hypatia the 2nd initially found a stale-epoch P1: repeated open after
  intake-ready could reuse `epoch: 0` and be rejected by the worker command
  handler after generation-bearing commands advanced `currentEpoch`. The fix
  adds monotonic epoch tracking and a default-transport red-to-green regression.
  The same review also found degraded intake-ready health parked pending
  requests and descriptor stale/source-identity errors lost backend detail.
  Both were fixed red-to-green: degraded intake-ready resolves `false`
  immediately, and descriptor stale/source-identity errors preserve the backend
  suffix needed by the stream-reset detector. Hypatia re-reviewed the final
  dirty diff and returned `ready` with no accepted remaining findings.
- Red / green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-native-worktree-file-intake-ready.unit.test.ts -t
  "uses monotonic epochs" --reporter dot` failed before the epoch tracker with
  first open `epoch: 0` instead of `1`, then passed. The degraded intake-ready
  regression failed before the fix with `"still-pending"` and then passed. The
  descriptor failure-detail regression failed before the fix because degraded
  health emitted only
  `Bridge comm worker failed to forward worktreeFileSurface.requestFileDescriptor.`
  and then passed with the stale-generation suffix preserved.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-source-structure.unit.test.ts
  src/app/bridge-app-native-worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.worktree-file-intake-ready.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.worktree-file-surface-rpc.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts
  src/core/comm-worker/bridge-worker-contracts.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts
  src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.worktree-file-intake-ready.unit.test.ts
  src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts
  src/app/bridge-app-native-worktree-file-telemetry.unit.test.ts
  src/app/bridge-file-viewer-worktree-file-surface-transport-adapter.unit.test.ts
  --reporter dot` passed 14 files / 103 tests. Browser proof
  `CI=true pnpm --dir BridgeWeb exec vitest --config
  vitest.browser.config.ts run --project integration-browser
  src/app/bridge-app-native-worktree-file.browser.test.ts
  src/app/bridge-app-native-review-error.browser.test.tsx --reporter dot`
  passed 2 files / 41 tests. `pnpm --dir BridgeWeb exec tsc --noEmit
  --pretty false` passed. Scoped `oxfmt --check`, scoped `oxlint --type-aware`,
  and `git diff --check` passed. `oxlint --type-aware` still prints the
  pre-existing `__bridgeNativeWorktreeFileProbe` underscore warnings in
  `bridge-app-native-worktree-file.ts`; exit code was 0.
- Source scans:
  Targeted scans in `BridgeWeb/src/app/bridge-app-native-worktree-file.ts` and
  `BridgeWeb/src/app/bridge-app-native-worktree-file-intake-ready.ts` for
  `createBridgeRPCClient`, `sendCommandAndWait`, `fetchRPC`, direct
  `worktreeFileSurface.openSourceStream`, and direct
  `worktreeFileSurface.requestFileDescriptor` returned no production app-side
  matches. The two method names now appear in the worker runtime command
  routing/protocol and source-structure negative tests.
- Known proof boundary:
  This is one Worktree/File surface ordinary RPC hard-cutover checkpoint. It
  does not finish scheme-stream push/intake/ack cutover, native oq4s
  scroll/click proof, Review apply/materialization lag closure,
  implementation-review-swarm, PR readiness, or full goal completion.

## 2026-07-08 - File View O(N2) Directory Prune Deletion

- Commit target:
  pending local checkpoint `fix(bridge): prune file tree directories bottom-up`.
- Scope:
  Delete the File View O(N2) directory prune called out in the Slice G deletion
  checklist. This is a narrow File View frame-application cleanup; it does not
  claim full Review/File UX proof, telemetry proof, or PR readiness.
- Implementation:
  `pruneEmptyWorktreeFileTreeDirectories` now builds directory indexes once,
  marks direct file parents, and propagates `has file descendant` upward through
  row `parentPath` metadata with each known directory enqueued at most once.
  The old nested per-directory descendant scan and the intermediate per-file
  ancestor-string walk are gone.
- Red / review evidence:
  The first red test failed on the old production code with `valuesCallCount`
  equal to 80, proving one full row scan per directory. Popper the 2nd then
  found the first fix still had deep-tree O(N2) behavior. The stronger red test
  failed before the parentPath propagation fix because prune called
  `String.prototype.lastIndexOf` 3320 times on an 80-deep tree.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-app.unit.test.ts -t
  "prunes deep directory rows" --reporter dot` passed 1/1. `pnpm --dir
  BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.ts
  -t "BridgeFileViewerApp tree row pruning" --reporter dot` passed 2/2.
  Scoped File View battery `pnpm --dir BridgeWeb exec vitest run
  src/file-viewer/bridge-file-viewer-app.unit.test.ts
  src/file-viewer/bridge-file-viewer-store-source-structure.unit.test.ts
  src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts
  --reporter dot` passed 3 files / 31 tests. `pnpm --dir BridgeWeb exec tsc
  --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Source scans:
  Targeted scan for the old nested prune pattern
  `for (const candidate of treeRowsByPath.values())` and the intermediate
  `ancestorDirectoryPathsForWorktreeFile` helper returned no matches. Remaining
  File View `lastIndexOf('/')` matches are the unit-test row helper and
  `bridge-file-viewer-tree-delta.ts` path helper, not the prune.
- Known proof boundary:
  This removes one File View checklist hot-path residue. It does not finish
  telemetry non-lossiness, Review placeholder main-thread diff residue, native
  oq4s scroll/click proof, implementation-review-swarm, PR readiness, or full
  goal completion.

## 2026-07-08 - Telemetry Sequence And Proof-Signal Integrity

- Commit target:
  pending local checkpoint `fix(bridge): preserve telemetry proof signals`.
- Scope:
  Close the telemetry non-lossiness gap before using Victoria metrics as the
  next Review/File View UX proof source. This slice fixes producer-side async
  POST failure ordering in the BridgeWeb telemetry sink and native admission
  shedding for proof-required selected paint/materialize rows. It does not
  claim native oq4s UX improvement by itself.
- Implementation:
  `createBridgeTelemetryEventSink` now retries the active async-failed POST
  before queued batches. If that retry also rejects, it keeps the failed head at
  the front of the queue and waits for a later flush to wake the queue, so later
  sequences cannot leap ahead and manufacture Swift `missing_drop_counter`
  evidence. Native `BridgeTelemetryAdmissionController` now treats
  `selected_content_painted` as always proof-required and
  `code_view_item_materialize` as proof-required only when the sample carries
  `agentstudio.bridge.selected == true`; visible/unselected high-volume rows
  still spend the normal high-volume budget.
- Red / review evidence:
  The original JS retry test failed before the sink change because async
  rejection advanced to the queued sequence without retrying the active
  sequence. The retained-head recovery test failed during review with
  `expected "spy" to be called 2 times, but got 3 times` when a drop-head
  variant advanced the queue after a second rejection. Mill the 2nd supplied
  Swift red evidence for
  `ingestorDoesNotRateLimitSelectedProofRowsWhenHighVolumeBudgetIsSpent`:
  before the admission change the selected proof batch returned
  `.accepted(sampleCount: 0)` with a rate-limited drop. Confucius the 2nd
  reviewed the dirty slice twice; accepted findings forced retained-head JS
  recovery and a discriminating selected-vs-unselected Swift assertion. Final
  re-review verdict: ready, no P0-P2 blockers.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/bridge/bridge-telemetry-event-sink.unit.test.ts
  src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
  src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts --reporter dot`
  passed 3 files / 19 tests. `swift test --disable-sandbox --filter
  ingestorStillRateLimitsUnselectedMaterializeRowsWhenHighVolumeBudgetIsSpent`
  passed 1 test. `swift test --disable-sandbox --filter
  BridgeTelemetryIngestorTests` passed 10 tests. `pnpm --dir BridgeWeb exec tsc
  --noEmit --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, `git diff --check`, and scoped `mise run lint --`
  over the touched telemetry files passed; the repo lint wrapper reported
  swift-format OK, SwiftLint 0 violations, architecture lint OK, and release
  script verification passed.
- Known proof boundary:
  This makes the next Victoria/debug run more trustworthy by preserving
  telemetry sequence ordering and selected proof rows under high-volume pressure.
  It does not itself prove Review scroll/click smoothness, close Review
  placeholder main-thread diff residue, finish scheme-stream push/intake/ack
  cutover, run implementation-review-swarm, or prove PR readiness.

## 2026-07-08 - Review CodeView Source-Reset Seed Bounding

- Commit target:
  `d6eda41d fix(bridge): bound review codeview source reset seed`.
- Scope:
  Remove one remaining package-shaped main-thread Review CodeView reset path.
  Source-reset initial CodeView seeding now uses selected plus visible
  worker-prepared item ids instead of rebuilding placeholders for the full
  projection. This is an R45/R46/R57 cleanup slice only; it does not claim full
  Review UX proof, native oq4s scroll/click proof, or final comm-worker
  cutover completion.
- Implementation:
  `BridgeCodeViewPanel` derives a selected-first seed list from selected id and
  visible worker-prepared items. The seed helper dedupes selected and skips
  visible candidates whose `bridgeMetadata.itemId` does not match the item id.
  `createBridgeCodeViewInitialItemsForPanel` passes that seed list into
  materialization and reorders returned items by seed rank so selected stays
  first for the panel reset path. `buildBridgeReviewProjection` now records
  `orderedItemRankByItemId`; the seeded low-level materializer iterates only the
  seed ids, validates membership with the precomputed rank map, and sorts by
  projection rank without reading `projection.orderedItemIds`.
- Accepted sidekick findings:
  Socrates the 2nd and Noether the 2nd both found the first draft only bounded
  output size: it still filtered the full `projection.orderedItemIds` list, and
  the new panel dependencies would make that O(package) scan hotter. The fix
  moved the true seeded fast path into `createBridgeCodeViewInitialItems` and
  added projection rank data to preserve the existing low-level projection-order
  contract. Bernoulli the 2nd re-reviewed the final diff and returned `ready`
  with no findings.
- Red / green evidence:
  The original new test failed before the seed support because source reset
  returned full projection items instead of selected + visible. The
  selected-first guard failed before panel-level seed-rank ordering because the
  low-level helper preserved projection order. Review then supplied the stronger
  red condition: seeded initialization must not scan `projection.orderedItemIds`.
  The final test uses a throwing `orderedItemIds` getter and passed only after
  the O(seed) fast path.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-selected-apply-pump.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  src/review-viewer/navigation/review-projection.unit.test.ts --reporter dot`
  passed 7 files / 78 tests. `pnpm --dir BridgeWeb exec tsc --noEmit
  --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Line-cap evidence:
  Pre/post touched over-800 files:
  `bridge-code-view-materialization.ts` 865 -> 903,
  `bridge-code-view-panel-support.tsx` 874 -> 920,
  `bridge-code-view-panel.tsx` 969 -> 977. All remain below the 1000-line hard
  cap.
- Known proof boundary:
  This removes one Review CodeView package-shaped source-reset residue. It does
  not finish Review main-thread parse/window/diff residues, native oq4s
  scroll/click metrics, browser Vitest full-suite proof, Swift full-suite proof,
  implementation-review-swarm, PR readiness, or full goal completion.

## 2026-07-08 - Review CodeView Source-Reset Apply Pump

- Commit target:
  checkpoint label `fix(bridge): pump review codeview source reset apply`.
- Scope:
  Remove the remaining synchronous full-reset `setItems(props.items)` path in
  Review CodeView metadata apply. A source reset now seeds only the selected
  items synchronously, or at most one fallback item when there is no selected
  rank, then drains the remaining reset payload through the existing R46 frame
  apply pump. This is a narrow R46 main-thread apply-budget slice only.
- Implementation:
  `runBridgeCodeViewMetadataApplyInChunks` now routes source-reset payloads
  through `sourceResetSeedItemsForApply` and then `runBridgeCodeViewMetadataApplyPump`
  for the remaining items. `shouldSkipItem` filtering applies only to non-reset
  incremental metadata apply, because reset membership must preserve skipped but
  still-present items after the synchronous seed. The shared pump path continues
  to own stale checks, replacement-item handling, selected/visible ranking, and
  drain-coupled completion for the remaining reset work.
- Red / green evidence:
  The first new source-reset test failed before the initial fix because source
  reset called `setItems` with the full `[source-high, docs-plan]` payload
  synchronously. Copernicus the 2nd then found a P1 in the first fix:
  pre-filtering with `shouldSkipItem` could drop a skipped selected item from
  reset membership. The targeted regression test
  `keeps skipped selected item in source-reset seed membership` failed red with
  received seed `[docs-plan]` instead of expected `[source-high]`. After moving
  skip filtering below the reset branch, that test passed. A compact fallback
  test now covers the no-selected seed path.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  --reporter dot` passed 1 file / 15 tests. `pnpm --dir BridgeWeb exec vitest
  run src/review-viewer/code-view/bridge-code-view-panel.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-panel-reconcile.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-selected-apply-pump.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  src/review-viewer/navigation/review-projection.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter dot`
  passed 8 files / 111 tests. `pnpm --dir BridgeWeb exec tsc --noEmit
  --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Review evidence:
  Copernicus the 2nd initially returned `needs fixes` with the skipped-selected
  P1. After the red/green fix and fallback test, Copernicus re-reviewed and
  returned `ready` with no P0-P3 findings.
- Line-cap evidence:
  Touched files are `bridge-code-view-metadata-apply.ts` at 105 lines and
  `bridge-code-view-metadata-apply.unit.test.ts` at 590 lines.
- Known proof boundary:
  This removes the Review CodeView synchronous full-reset apply residue. It does
  not finish Review placeholder main-thread diff/parse/window residues, native
  oq4s scroll/click metrics, live Victoria percentile proof, implementation
  review swarm, PR readiness, or full goal completion.

## 2026-07-08 - Review CodeView Placeholder Diff Parser Removal

- Commit target:
  checkpoint label `fix(bridge): remove review placeholder diff parser`.
- Scope:
  Remove the placeholder/loading Review CodeView diff path's dependency on
  Pierre's `parseDiffFromFile` on the main thread. This is a narrow R52/R57
  cleanup slice for placeholder diff construction only. Hydrated legacy/test
  materialization still uses `parseDiffFromFile` and remains a separate deletion
  target for later Review content-protocol cutover work.
- Implementation:
  `createPlaceholderDiffItem` now delegates to
  `createBridgeCodeViewPlaceholderFileDiff`, which builds the bounded
  placeholder `fileDiff` directly from already-known line counts, paths, and
  placeholder cache keys. `createBridgeCodeViewPlaceholderDiffFiles` now carries
  explicit base/head line counts so placeholder diff construction does not need
  to synthesize placeholder text and then parse it back. The helper lives beside
  the placeholder content builders, keeping `bridge-code-view-materialization.ts`
  under the TS line cap.
- Red / review evidence:
  The source-structure test
  `keeps placeholder diff creation off the main-thread diff parser` failed red
  before the first implementation because `createPlaceholderDiffItem` contained
  `parseDiffFromFile`. Harvey the 2nd then found a P2 proof gap: the first guard
  scanned only the caller and did not directly prove the new helper's Pierre
  shape. The follow-up test
  `builds placeholder diffs with the same Pierre shape as parsed placeholder
  contents` compares the helper against `parseDiffFromFile` for modified,
  renamed, added, and deleted placeholder inputs, including normalized type,
  previous name, hunk fields, line counts, and cache key. The source-structure
  guard now scans both the materialization caller and the placeholder-content
  helper module for `parseDiffFromFile`.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts -t
  "same Pierre shape" --reporter verbose` passed 1 file / 1 selected test.
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts
  src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts
  src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter dot`
  passed 3 files / 64 tests. `pnpm --dir BridgeWeb exec tsc --noEmit
  --pretty false` passed. Scoped `oxfmt --check`, scoped
  `oxlint --type-aware`, and `git diff --check` passed.
- Review evidence:
  Harvey the 2nd initially returned `needs fixes` with the P2 helper-proof gap.
  After the parity test and expanded source scan, Harvey re-reviewed and
  returned `ready` with no findings for the P2 closure.
- Line-cap evidence:
  Touched line counts after formatting:
  `bridge-code-view-materialization.ts` 904,
  `bridge-code-view-placeholder-content.ts` 273,
  `bridge-code-view-materialization.unit.test.ts` 735,
  `review-viewer-source-structure.unit.test.ts` 749. All remain below the
  1000-line hard cap.
- Known proof boundary:
  This removes one Review placeholder main-thread diff-parse residue. It does
  not remove hydrated legacy `createDiffItem` parsing, worker-prepared diff
  deep-copy/rebuild work, visible-item re-materialization churn, native oq4s
  scroll/click metrics, live Victoria percentile proof, implementation-review
  swarm, PR readiness, or full goal completion.

## 2026-07-08 - Review Worker-Prepared Diff Identity Preservation

- Commit target:
  checkpoint label `fix(bridge): preserve review worker diff identity`.
- Scope:
  Narrow R45/R46/R57 main-thread apply-path cleanup for Review CodeView
  metadata deltas. `bridgeCodeViewItemFromWorkerPreparedItem` no longer
  deep-copies worker-prepared diff payloads on main for metadata delta apply.
  When worker language is already Pierre-normalized, the existing worker item
  is returned by reference. When language normalization is still required, the
  helper shallow-replaces only the top-level `file` / `fileDiff` wrapper and
  preserves existing hunks, hunk content, addition lines, and deletion lines.
- Root cause:
  The previous helper rebuilt worker-prepared items on main, including
  `hunks.map(...)`, `hunkContent.map(...)`, `[...deletionLines]`, and
  `[...additionLines]`, so each visible metadata delta paid a deep-copy cost
  before the R46 apply pump could bound DOM apply.
- Red evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  -t "preserves worker-prepared diff payload identity" --reporter verbose`
  failed before production changes because the delta item was structurally
  equal but not the same object reference. The normalization-focused variant
  also failed because normalized output rebuilt the `hunks` array.
- Green evidence:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/code-view/bridge-code-view-metadata-apply.unit.test.ts
  --reporter dot` passed 1 file / 17 tests. The wider Review CodeView battery
  passed 7 files / 106 tests:
  `bridge-code-view-panel.unit.test.ts`,
  `bridge-code-view-panel-reconcile.unit.test.ts`,
  `bridge-code-view-materialization.unit.test.ts`,
  `bridge-code-view-materialization.hydration.unit.test.ts`,
  `bridge-code-view-selected-apply-pump.unit.test.ts`,
  `bridge-code-view-metadata-apply.unit.test.ts`, and
  `review-viewer-source-structure.unit.test.ts`. The adjacent
  projection/materialization battery passed 4 files / 59 tests.
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed. Scoped
  `oxfmt --check`, scoped `oxlint --type-aware`, and `git diff --check`
  passed. Source scan for the old deep-copy patterns in the touched helper
  returned no matches.
- Review evidence:
  Poincare the 2nd found no repo-visible downstream mutation of incoming
  CodeView items, with language normalization as the only caveat. Averroes the
  2nd reviewed the two-file diff, reported one accepted P2 test gap proving the
  normalization path did not mutate the input worker item, then re-reviewed the
  added assertions and returned ready with no P0-P3 findings.
- Line-cap evidence:
  Touched line counts after formatting:
  `bridge-code-view-worker-prepared-items.ts` 261 and
  `bridge-code-view-metadata-apply.unit.test.ts` 660. Both remain below the
  1000-line hard cap.
- Known proof boundary:
  This removes the worker-prepared diff deep-copy/rebuild residue only. It does
  not prove live oq4s scroll/click percentile movement, visible-item
  re-materialization storm closure, native worker-fetch F1, zero-copy
  transfer-list delivery, implementation-review-swarm, PR readiness, or full
  goal completion.
