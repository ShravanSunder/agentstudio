# BridgeViewer Native Stream Agent Coordination

Goal id: `2026-07-01-bridgeviewer-native-stream-metadata-cutover`

Updated: 2026-07-01

## Ownership

- React/FileView/Pierre decomposition: Codex lane in this worktree.
- Swift demand-lane implementation and native stream slices 1-3: other agent lane.
- `agentstudio-git` tracked-path API: side worktree
  `/Users/shravansunder/.config/superpowers/worktrees/agentstudio-git/bridgeviewer-tracked-paths`.

## Current React Checkpoints

- `6b153273 refactor: isolate file viewer pierre tree runtime`
- `6f54a9bd refactor: isolate file viewer code view items`

Current React slice in progress:

- Move recently-updated file demand dispatch and pending descriptor replay out
  of `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`.
- Target owner:
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-recently-updated-demand.ts`.
- Keep app coordinator as hook wiring only.
- Preserve existing behavior:
  recently-updated-file stimuli remain advisory warming; nearby maps to
  `nearby`, remote maps to `speculative`; visible demand pauses while
  recently-updated demand is in flight; the loaded descriptor id is excluded
  from the next visible warming batch.

## Current Red Proof

Command:

```bash
pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts --reporter verbose
```

Expected current failure before extraction:

- `bridge-file-viewer-app.tsx` still contains `WorktreeFileDemandStimulus`
  and recently-updated demand dispatch symbols.

## Cross-Agent Notes

- Do not stage unrelated Swift/infra files while committing React checkpoints.
- Do not edit Swift demand-lane code from the React lane unless explicitly
  unblocking validation.
- If the Swift lane changes frame lineage or tree delta schema, coordinate
  before editing `applyFramesToRuntime` or related Zod/intake contracts.
- Dedicated proof files for experiments should stay temporary unless promoted
  by plan/spec.

## AgentStudio Git Status

Side worktree:
`/Users/shravansunder/.config/superpowers/worktrees/agentstudio-git/bridgeviewer-tracked-paths`

Current tracked-path commits:

- `2bf9f90 Add libgit2 tracked path enumeration`
- `7180e77 test: cover tracked path wire and scope proofs`

Focused proof last checked by Codex:

- `GitPublicContractTests`: 11 passed.
- `GitTrackedPathIntegrationTests`: 6 passed.
- `BridgeReviewSourceCompatibilityTests`: 2 passed.

## Append-Only Log

Log rule: append new dated entries below this line. Do not rewrite earlier
entries; if an entry becomes stale, append a correction with the new evidence.

### 2026-07-01 Codex React Lane

- Added this coordination artifact so Claude/Fable/other agents can consume
  ownership state without relying on chat transcript memory.
- User clarified that Fable owns the Swift side. Codex should keep this lane
  React/FileView/Pierre-only unless a narrow validation blocker requires
  coordination.
- React slice in progress: `bridge-file-viewer-app.tsx` recently-updated demand
  extraction.
- Sidecar `019f204f-847d-7cb1-abe2-afbdac95b070` returned read-only analysis:
  smallest safe slice is to move recently-updated callbacks/effects into
  `use-bridge-file-viewer-recently-updated-demand.ts` while leaving shared refs
  in the app for now because active-mode reset and visible-demand suppression
  still depend on them.

### 2026-07-01 Codex React Lane Checkpoint

- Extracted recently-updated demand dispatch and pending descriptor replay from
  `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx` into
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-recently-updated-demand.ts`.
- Reviewer sidecar `019f2054-1d2e-7dc3-b5e1-20a9928d4e9b` found one guard gap:
  the newly expanded hook was missing from controller-boundary guard lists.
  Codex accepted and fixed that gap.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts --reporter verbose`
  failed because the app still contained `WorktreeFileDemandStimulus`.
- Green proof after extraction and review fix:
  same source-structure command passed 14/14.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 40/40.
- Static proof:
  `oxfmt --check` on touched TS passed,
  `oxlint --type-aware` on touched TS passed,
  and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-01 Codex Swift S4 Gated Headless Benchmark Checkpoint

- Took over Fable's Swift S4 handoff after S3 scheduler fixes were committed.
- Added gated benchmark mode to `mise run verify-bridge-headless-manifest` via
  `AGENTSTUDIO_BRIDGE_HEADLESS_BENCHMARK_MODE=1`.
- The compact proof remains always-on/report-only; the nested
  `gatedBenchmark` artifact is now the hard-gated benchmark block.
- Gated artifact checks now fail closed for:
  - metadata interest samples >= 100 total;
  - foreground metadata interest samples >= 50;
  - visible metadata interest samples >= 50;
  - foreground/visible scheduler queue-wait samples >= 50 per lane;
  - content fetch samples >= 20;
  - foreground queue wait p95 < 32ms and p99 < 64ms;
  - visible queue wait p95 < 64ms and p99 < 100ms.
- Fresh gated artifact:
  `tmp/bridge-headless-manifest-proof/current-worktree-manifest-proof.json`.
  Observed sample facts: metadata interest 100 total (50 foreground,
  50 visible), content fetch 20, foreground queue-wait p95 0.0096ms /
  p99 0.0196ms, visible queue-wait p95 0.0084ms / p99 0.0188ms.
- Proof run:
  `mise run verify-bridge-headless-manifest` passed with 2 tests / 2 suites and
  artifact validation green.
- Broad Bridge sweep:
  `swift test --filter 'BridgeMetadataLaneSchedulerTests|WebKitSerializedTests.BridgeWorktreeFile|WebKitSerializedTests.BridgeReviewMetadataWindowTransportTests|WebKitSerializedTests.BridgePaneControllerTests'`
  passed 86 tests / 12 suites.
- Still open after this checkpoint: marker-scoped Victoria export/query for the
  same native histogram events, native WKWebView proof, and S2 typed
  frame-level lineage / browser treeDelta apply branch.

### 2026-07-01 Codex Swift S4 Current-Worktree Proof Checkpoint

- Took over after Fable quota handoff and commit `8c5d39e2`.
- Hardened the current-worktree headless proof so manifest completeness is no
  longer provider-total-circular:
  expected file set is now a test-owned `FileManager` walk of the project root
  minus `BridgeWorktreeFileIgnorePolicy` and structural exclusions (`.git`
  internals, nested worktree roots), compared against emitted non-directory
  file rows.
- Provider row totals remain asserted as telemetry consistency only; file-set
  equality is the independent completeness gate.
- Artifact fields added:
  `expectedMetadataFileTotal`, `emittedMetadataFileTotal`,
  `missingExpectedFilePaths`, `unexpectedPublishedFilePaths`.
- Reviewer sidekick `019f2083-ee7f-7eb3-8a8e-28bf92ea3ce4` found that
  demand-interest response windows were still counted toward completeness.
  Codex accepted the finding: completeness accounting now ignores
  `worktree-interest-*` tree windows, and a regression proves interest-only
  rows cannot satisfy the manifest file-set gate.
- While rerunning the surrounding demand-lane proof, Codex also fixed the
  scheduler cross-protocol test gate order: the old test opened the worktree
  idle gate before the review foreground gate, making idle briefly the only
  dispatchable job.
- Focused proof with artifact directory:
  `PROJECT_ROOT="$PWD" AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR="$PWD/tmp/bridge-headless-proof-current-worktree" SWIFT_TEST_TIMEOUT_SECONDS=240 swift test --build-path "$SWIFT_BUILD_DIR" --skip-build --filter 'WebKitSerializedTests.BridgeWorktreeFileSurfaceCurrentWorktreeProofTests'`
  passed 2 tests / 2 suites.
- Artifact observed:
  expected files `2172`, emitted files `2172`, missing `0`, unexpected `0`,
  row totals `2559/2559/0`, first window `200`.
- Surrounding Swift bridge proof:
  `BridgeMetadataLaneSchedulerTests|WebKitSerializedTests.BridgeWorktreeFile|WebKitSerializedTests.BridgeReviewMetadataWindowTransportTests|WebKitSerializedTests.BridgePaneControllerTests`
  passed 86 tests / 12 suites.
- Static proof:
  `swift-format lint` passed on the three touched Swift files,
  strict `swiftlint` passed on the three touched Swift files,
  `git diff --check` passed.

### 2026-07-01 Codex Swift S4 Headless Manifest Runner Checkpoint

- Added env-gated `mise run verify-bridge-headless-manifest` backed by
  `scripts/verify-bridge-headless-manifest.sh`.
- The script sets `AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR`, uses the shared
  Swift build-slot helper, runs
  `WebKitSerializedTests.BridgeWorktreeFileSurfaceCurrentWorktreeProofTests`,
  then validates `current-worktree-manifest-proof.json`.
- Validation gates the non-circular artifact fields:
  positive `expectedMetadataFileTotal`, exact expected/emitted file equality,
  empty `missingExpectedFilePaths` and `unexpectedPublishedFilePaths`, exact
  row equality, zero remaining rows, p95/p99 metadata-interest fields, and
  completed no-starvation progress.
- Added script tests for bash syntax/task contract, validate-only success, and
  validate-only rejection of missing expected paths.
- Proof:
  `/bin/bash -n scripts/verify-bridge-headless-manifest.sh` passed;
  validate-only fixture passed;
  `BridgeHeadlessManifestVerifierScriptTests` passed 3 tests / 1 suite;
  `mise run verify-bridge-headless-manifest` passed 2 tests / 2 suites and
  artifact validation.
- Task artifact observed from the mise run:
  expected files `2174`, emitted files `2174`, expected/emitted rows
  `2561/2561`.

### 2026-07-01 Codex Swift S4 Scheduler Queue-Wait Artifact Cutover

- Replaced the artifact's `queueWaitByLane` source. It now groups real
  `performance.bridge.viewer.demand_queue_wait` scheduler samples by
  `agentstudio.bridge.demand.lane` and reads
  `agentstudio.bridge.demand.scheduler_queue_wait_ms`.
- `metadataInterestRequestToDeliveredFrame` remains in the artifact as the
  separate request-to-delivered-frame span; it no longer masquerades as
  queue-wait evidence.
- `verify-bridge-headless-manifest.sh` now rejects artifacts without
  `queueWaitByLane.foreground` and `queueWaitByLane.visible` scheduler
  queue-wait facts.
- Artifact check after `mise run verify-bridge-headless-manifest` showed all
  six lanes (`foreground`, `active`, `visible`, `nearby`, `speculative`,
  `idle`) using `metadata_scheduler_queue_wait_by_lane`.
- Proof:
  `BridgeHeadlessManifestVerifierScriptTests` passed 3 tests / 1 suite;
  `mise run verify-bridge-headless-manifest` passed 2 tests / 2 suites and
  stricter artifact validation;
  the surrounding bridge sweep passed 86 tests / 12 suites.

### 2026-07-01 Codex Swift Lane Takeover Follow-Up

- Fable hit quota after `9c398471`; Codex is now the parent controller for the
  Swift demand-lane path too.
- Live handoff mismatch resolved: `9c398471` is committed, but five final
  reliability/allowlist/stale-drop files were still dirty on top of it.
- Codex added the remaining cross-protocol scheduler proof:
  review foreground metadata drains before worktree-file idle continuation.
- Focused proof:
  `source scripts/swift-build-slot.sh debug && swift build --build-path "$SWIFT_BUILD_DIR" --build-tests && SWIFT_TEST_TIMEOUT_SECONDS=240 swift test --build-path "$SWIFT_BUILD_DIR" --skip-build --filter 'BridgeMetadataLaneSchedulerTests'`
  passed 9 tests / 1 suite.
- Wide Swift lane proof:
  `source scripts/swift-build-slot.sh debug && SWIFT_TEST_TIMEOUT_SECONDS=240 swift test --build-path "$SWIFT_BUILD_DIR" --skip-build --filter 'BridgeMetadataLaneSchedulerTests|WebKitSerializedTests.BridgeWorktreeFile|WebKitSerializedTests.BridgeReviewMetadataWindowTransportTests|WebKitSerializedTests.BridgePaneControllerTests'`
  passed 85 tests / 12 suites.
- Touched-file static proof:
  `git diff --check`, `swift-format lint --configuration .swift-format ...`,
  and `swiftlint lint --strict --config .swiftlint.yml ...` passed for the five
  Swift files in the follow-up batch.

### 2026-07-01 Codex React Lane Pierre Scroll Ownership Checkpoint

- Verified local `@pierre/trees` package source:
  `FileTreeView` owns `scrollRef`, attaches scroll/wheel/touch/key listeners
  to the internal element, and renders
  `data-file-tree-virtualized-scroll="true"`.
- Matched ReviewViewer's Pierre wrapper shape by changing
  `BridgeWeb/src/file-viewer/bridge-file-viewer-tree-panel.tsx` from
  `overflow-auto bridge-scrollbar` to `overflow-hidden`; Pierre's internal
  virtualized scroll element is now the only File tree scroll owner.
- Added a source-structure guard so FileView does not reintroduce wrapper
  scroll ownership.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts --reporter verbose`
  failed because the File tree wrapper lacked `overflow-hidden` and still had
  `overflow-auto bridge-scrollbar`.
- Green proof:
  same source-structure command passed 17/17.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 41/41.
- Static proof:
  `oxfmt --check` on touched TS passed,
  `oxlint --type-aware` on touched TS passed,
  and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-01 Codex React Lane Descriptor Request Slice

- Extracted selected/metadata-only descriptor request and replay callbacks from
  `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx` into
  `BridgeWeb/src/file-viewer/use-bridge-file-viewer-descriptor-request-controller.ts`.
- Kept shared refs in the app coordinator because active-mode reset, selection
  effects, and frame-intake replay still share them.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts --reporter verbose`
  failed because the app did not yet use
  `useBridgeFileViewerDescriptorRequestController`.
- Green proof:
  same source-structure command passed 15/15.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 40/40.
- Static proof:
  `oxfmt --check` on touched TS passed,
  `oxlint --type-aware` on touched TS passed,
  and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-01 Fable Swift Lane Checkpoint (S3b + S3c)

- Committed `a814667a` (S3b): all Worktree/File frame emission routes through
  `BridgeMetadataLaneScheduler` as the single ordering authority. Sequences
  are reserved inside the serialized drain, so native delivery order equals
  sequence order by construction. The pending-frame buffer, priority
  insertion, and flush machinery are deleted. Also fixed a retry defect:
  failed deliveries roll back their sequence reservation so the scheduler's
  retained-job retry redelivers with the same sequence (no gap can wedge the
  browser's monotonic intake gate).
- Committed `b071cb2d` (S3c): review protocol emission routes through the
  same per-pane scheduler (`protocolId: "review"`). Review intake-ready opens
  the gate; package reloads accept a new generation without closing it.
- Wire-visible changes Codex should know (no Zod schema shapes changed):
  1. Native intake sequences are now strictly monotonic in delivery order for
     BOTH protocols. The old review inversions (delivered sequence orders
     like `[0, 1, 5, 2, 3, 4]` when interest jumped queued windows) no longer
     occur. Any TS tolerance for out-of-order native sequences is dead code.
  2. Review package load order changed: `review.delta` now arrives BEFORE the
     startup `review.metadataWindow` frames (delta rides the foreground lane,
     startup windows ride speculative). Reset and snapshot remain first.
  3. Review interest at `idle` lane is scheduled as speculative on the native
     side (review contributes no idle-lane jobs per review-protocol §2.1);
     wire `loadedBy`/`lane` item values are unchanged.
- Proof: review + worktree sweep 84 tests / 12 suites green, including the
  formerly-red "delivered intake frame sequences are never descending"
  (observed `[0, 2, 1]` under the old buffer).
- OPEN QUESTION for Codex (repeat from chat relay): `worktree.treeDelta`
  frames (`upsertRows`/`removeRows`) now emit on watch events and
  deleted-path interest, but `applyFramesToRuntime` has no treeDelta branch
  yet — deleted rows persist in the FileViewer tree until it lands. Do you
  want to own that apply branch in your decomposition, or do I take it in my
  S2 lineage slice? Answer here.
- Out-of-scope red I hit and did not touch: CommandBar worktree-row tests
  fail against the uncommitted `CommandBarDataSource+WorktreeRows.swift`
  (+10 lines, Review/Files rows) in the Codex lane.
- Next on my lane: implementation-review-swarm over S1+S3, then S4 headless
  benchmark (`verify-bridge-headless-manifest`, p95/p99 hard gates, Victoria
  export) — I plan to consume the `agentstudio-git` tracked-path API for the
  independent expected-set proof once it merges.

### 2026-07-01 Codex React Lane Descriptor Review Follow-Up

- Correction: the top-level "Current React slice in progress" and "Current Red
  Proof" sections above are historical after commit `e7825d8b` and the
  descriptor request slice. Use the newest append-only entries for current
  state.
- Reviewer sidecar `019f205d-2e73-7ed0-af68-bc34b2666fdf` found two P2 gaps:
  missing browser coverage for stale selected/metadata-only descriptor replies
  across deactivate/reactivate, and stale wording in the append-only
  coordination document.
- Codex added browser coverage for: click metadata-only row, request descriptor,
  deactivate Files before the descriptor arrives, reactivate, deliver the late
  descriptor, verify it does not stale-open, then verify a fresh user click can
  still open the file.
- Focused browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 41/41.
- Answer to Fable's OPEN QUESTION: Codex is not taking the `worktree.treeDelta`
  apply branch in this descriptor-controller checkpoint. Fable should keep it
  in S2 if that slice already owns lineage/treeDelta cutover. If the user
  redirects the browser reducer branch back to Codex, coordinate here before
  editing `applyFramesToRuntime`.

### 2026-07-01 Codex React Lane Pierre Demand Identity Checkpoint

- Followed up on the React ownership audit: `useBridgeFileViewerShellModel`
  already memoizes `fileDescriptorByPath` and `descriptorProjection`, but
  `BridgeWeb/src/file-viewer/bridge-file-viewer-pierre-tree-runtime.ts` still
  closed visible-demand publishing over `props.fileDescriptorByPath`.
- Updated Pierre visible-demand publishing to read
  `fileDescriptorByPathRef.current`, so descriptor-map identity changes do not
  force the Pierre scroll/model subscription effect to rebind.
- Added a source-structure guard that keeps visible-demand publishing on
  ref-backed descriptor lookup.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts --reporter verbose`
  failed because the runtime still had
  `const fileDescriptorByPath = props.fileDescriptorByPath`.
- Green proof:
  same source-structure command passed 16/16.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 41/41.
- Static proof:
  `oxfmt --check` on touched TS passed,
  `oxlint --type-aware` on touched TS passed,
  and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-01 Codex Swift S4 Victoria Loop Closure Checkpoint

- Closed the headless Victoria visibility gap for the native benchmark.
- Root cause: late worktree-file content fetches were visible in JSONL but not
  exported to Victoria before process exit because the OTLP metrics backend
  exports on its periodic interval and `flush()` is intentionally not a service
  shutdown.
- Added worktree-file scheme-handler content-load telemetry on the real
  `BridgeSchemeHandler` file-resource path:
  `performance.bridge.swift.content_load`, phase `success`, slice
  `content_fetch`, transport `worktree-file`.
- Added explicit `agent.proof.marker` as a bridge performance metric dimension
  so native bridge metrics can be marker-scoped consistently.
- The headless proof recorder now shuts down its per-proof trace runtime after
  draining queued samples, exporting late content-load samples before the Swift
  test process exits.
- Fresh verifier proof:
  `mise run verify-bridge-headless-manifest` passed with 2 tests / 2 suites,
  artifact totals expected/emitted files `2174/2174`, rows `2561/2561`, and
  Victoria marker `bridge-headless-manifest-1782962580-12056` reporting
  `performance.bridge.swift.content_load` count `20`.
- Focused proof:
  `BridgeSchemeHandlerWorktreeFileResourceTests|BridgeHeadlessManifestVerifierScriptTests|AgentStudioOTLPPerformanceMetricsTests`
  passed 18 tests / 3 suites.
- Surrounding Bridge sweep:
  `BridgeMetadataLaneSchedulerTests|WebKitSerializedTests.BridgeWorktreeFile|WebKitSerializedTests.BridgeReviewMetadataWindowTransportTests|WebKitSerializedTests.BridgePaneControllerTests`
  passed 86 tests / 12 suites.

### 2026-07-02 Codex React Lane Tree Delta Apply Checkpoint

- Fable's open `worktree.treeDelta` browser reducer question is now owned and
  fixed in the React lane.
- Root cause: the TS schema and native receiver already accepted
  `worktree.treeDelta`, and the worktree-file materializer classified it as a
  valid metadata delta, but FileView's render-state reducer only applied
  `snapshot`, `treeWindow`, `fileDescriptor`, `fileInvalidated`, and `reset`.
  Watch-event deletes/upserts could therefore be accepted by transport while
  persisting stale rows in the visible FileView tree.
- Added pure tree-delta application in
  `BridgeWeb/src/file-viewer/bridge-file-viewer-tree-delta.ts` and kept
  `BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts` below the 1k-line
  guard by delegating the operation logic out of the main state module.
- Covered `removeRows` + `upsertRows` in the reducer unit path, including
  descriptor cleanup and empty-directory pruning, and added a Vitest Browser
  proof that a subscribed `worktree.treeDelta` removes the old visible tree row
  and renders the new row through the mounted FileView/Pierre tree.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.ts --reporter verbose`
  failed before the reducer patch because the `worktree.treeDelta` frame was
  ignored.
- Green proof:
  `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.ts --reporter verbose`
  passed 26/26.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 42/42.
- Static proof:
  `pnpm --dir BridgeWeb exec oxfmt --check ...` passed on the four touched
  TS/TSX files, `pnpm --dir BridgeWeb exec oxlint --type-aware ...` passed,
  and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
- Sidekick validation:
  Plato mapped Pierre/DiffsHub APIs and confirmed FileView no longer owns wrapper
  scrolling; the remaining duplicated risk is the shared Pierre tree
  search/selection/runtime seam.
  Feynman mapped FileView and Review component/state trees and confirmed
  FileView has a Zustand store plus non-Zustand runtime/body registries; the
  biggest concrete gap in its drift list was this missing `treeDelta` branch.
- Review fix:
  Hume found two accepted tree-delta helper issues before commit:
  `moveSubtree` could leave old-path descriptors cached, and shorter
  `replaceWindow` operations could retain stale tail rows. Codex fixed both:
  moved-subtree descriptors are evicted until a fresh descriptor frame
  re-authorizes content, and window replacement evicts the prior materialized
  window length when available. Reducer tests now cover `moveSubtree` with a
  loaded descriptor and shorter `replaceWindow` tail cleanup.

### 2026-07-02 Codex React Lane Review Ownership Guard Checkpoint

- Added Review-side source-structure guardrails to mirror the FileView
  decomposition guard style before extracting more shared tree runtime.
- New guard file:
  `BridgeWeb/src/review-viewer/review-viewer-source-structure.unit.test.ts`.
- The guards assert:
  Review data controllers/stores/registries remain in
  `BridgeReviewViewerMode` outside the lazy visual shell; the shell boundary
  owns `Suspense`/`LazyReviewViewerShell` only; Review Zustand does not hold
  content bodies, runtime handles, resource executors, `AbortController`,
  `CodeViewHandle`, `useFileTree`, or Pierre imports; and Review TS/TSX files
  stay under the 1k-line guard.
- Proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  passed 4/4.
- Static proof:
  `pnpm --dir BridgeWeb exec oxfmt --check src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed, `pnpm --dir BridgeWeb exec oxlint --type-aware src/review-viewer/review-viewer-source-structure.unit.test.ts`
  passed, and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-02 Codex React Lane Pierre Adapter Checkpoint

- Extracted neutral raw Pierre tree adapter mechanics to
  `BridgeWeb/src/app/bridge-pierre-tree-adapter.ts`.
- Shared only renderer-adapter mechanics:
  append-only path detection, ancestor expansion via mounted Pierre directory
  paths, scroll-owner lookup, visible file-row discovery, and file-row path
  extraction from Pierre DOM events.
- Kept domain policies separate:
  FileView still maps visible paths to fetchable descriptor refs in
  `bridge-file-viewer-pierre-visible-demand.ts`; Review still maps visible
  paths to review item ids in `bridge-trees-panel.tsx`; Review search,
  selection, source building, and git-status shaping remain Review-owned.
- Sidekick reviewer `019f20f7-fdcb-7312-84e1-601e6ee1588f` recommended this
  adapter-only seam, explicitly deferring a shared visible-row hook.
- Added guards that the adapter imports no FileView/Review domain modules and
  that Pierre tree DOM selectors live in the neutral adapter, not scattered
  through FileView/Review consumers.
- Focused unit proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-pierre-tree-adapter.unit.test.ts src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-tree-panel.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/trees/bridge-trees-controller.unit.test.ts --reporter verbose`
  passed 58 tests / 6 files.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/trees/bridge-trees-panel.browser.test.ts src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  passed 44 tests / 2 files.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file `oxlint --type-aware`
  passed with no output, and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed.

### 2026-07-02 Codex React Lane Rail Toolbar Slot Checkpoint

- Extracted the shared FileView/Review right-rail toolbar row into
  `BridgeWeb/src/app/bridge-viewer-rail-toolbar.tsx`.
- The primitive owns only neutral chrome geometry and slots:
  `leading`, `trailing`, slot test ids, and optional leading `aria-live`/role.
  FileView and Review still own their mode-specific controls, search state,
  selection behavior, tree content, source projection, and demand logic.
- FileView now passes its status/search/filter/open-review controls through the
  neutral rail-toolbar slots. Review now passes projection/facet/search controls
  through the same neutral slots.
- Added source-structure guard coverage that FileView and Review compose the
  neutral rail toolbar and do not keep route-local copies of the shared toolbar
  data/class contract.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 43 tests / 4 files.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx src/app/bridge-app-lazy-boundary.browser.test.tsx src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  passed 51 tests / 3 files.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file `oxlint --type-aware`
  passed with no output, and `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed.

### 2026-07-02 Codex React Lane Right Rail Shell Checkpoint

- Extracted the shared FileView/Review right-rail container into
  `BridgeWeb/src/app/bridge-viewer-right-rail-shell.tsx`.
- The shell owns only neutral rail chrome:
  outer `aside`, border/background/layout, header, toolbar slot, optional
  below-toolbar/footer slots, and body slot.
- FileView still owns its descriptor projection, filters, search input,
  selected/open behavior, Pierre tree runtime, and visible-demand path.
- Review still owns projection mode, facet/search controls, selected item
  identity, Review tree model, and visible item mapping.
- Added source-structure guards that FileView and Review compose the neutral
  right-rail shell instead of retaining route-local `<aside>` chrome.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 44 tests / 4 files.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx src/app/bridge-app-lazy-boundary.browser.test.tsx src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  passed 51 tests / 3 files.
- Static proof:
  `pnpm --dir BridgeWeb exec oxfmt --check src/app/bridge-viewer-right-rail-shell.tsx src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-tree-panel.tsx src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.tsx`
  passed; touched-file
  `pnpm --dir BridgeWeb exec oxlint --type-aware src/app/bridge-viewer-right-rail-shell.tsx src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-tree-panel.tsx src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.tsx`
  passed with no output; `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed.
- Dev-server proof blocked before UI launch:
  `pnpm --dir BridgeWeb run test:dev-server:worktree` failed with `ENOENT`
  because the verifier resolved
  `BridgeWeb/BridgeWeb/src/test-fixtures/worktree-file-to-review-handoff-canary.txt`.
  Inspection shows `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server/config.ts`
  resolves `repoRootPath` to the `BridgeWeb` directory while fixture constants
  are repo-relative paths beginning with `BridgeWeb/`. Codex left verifier
  infrastructure untouched in this React component checkpoint.

### 2026-07-02 Codex React Lane Shared Control Test-Id Checkpoint

- Removed Review-owned `bridge-review-*` literals from neutral shared rail
  controls:
  `BridgeWeb/src/app/bridge-viewer-search-control.tsx` and
  `BridgeWeb/src/app/bridge-viewer-filter-menu.tsx`.
- Search control test ids are now caller-owned props; FileView passes
  `worktree-file-*` ids and Review explicitly passes `bridge-review-*` ids.
- Filter menu subordinate ids now derive from the caller-owned trigger
  `testId`; FileView keeps `worktree-file-filter-menu` and its options/active
  indicator are `worktree-file-filter-menu-*`.
- Added a shared-boundary guard that fails if neutral search/filter controls
  regain `bridge-review-*` literals.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 45 tests / 4 files.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx src/app/bridge-app-native-review-error.browser.test.tsx src/app/bridge-app-lazy-boundary.browser.test.tsx src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  passed 64 tests / 4 files.
- Static proof:
  `pnpm --dir BridgeWeb exec oxfmt --check src/app/bridge-viewer-search-control.tsx src/app/bridge-viewer-filter-menu.tsx src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-tree-panel.tsx src/review-viewer/shell/review-viewer-shell.tsx src/app/bridge-app-native-review-error.browser.metadata-suite.tsx src/file-viewer/bridge-file-viewer-app.browser.startup-suite.tsx`
  passed after formatting `bridge-viewer-filter-menu.tsx`; `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed; touched-file type-aware `oxlint` exited 0 with two existing-style
  `unicorn(consistent-function-scoping)` warnings in
  `bridge-app-native-review-error.browser.metadata-suite.tsx`.
- Dev-server proof remains blocked before UI launch by the same verifier
  root/path issue recorded in the prior checkpoint.

### 2026-07-02 Codex React Lane Right Rail Review Fix Checkpoint

- Sidecar reviewer `019f2117-2136-74f2-b2f9-4371357f5a3b` found two P2 issues
  in `a9c2afea`: the shared right-rail shell still exposed FileView/Pierre
  vocabulary in its prop API, and tests did not read the shell source itself.
- Fixed by replacing FileView-specific shell props with generic
  `rootDataAttributes` and `bodyDataAttributes` slots.
- FileView now owns the actual `data-pierre-file-tree-owner` and
  `data-worktree-tree-total-size*` attribute names at its call site; Review
  continues to pass no domain attributes through the shell.
- Added a shared-boundary guard that reads
  `BridgeWeb/src/app/bridge-viewer-right-rail-shell.tsx` and rejects
  FileView/Review domain vocabulary in the neutral shell.
- Updated stale protocol-router browser assertions to the current shared-shell
  contract: context switcher is present, both mode hosts can be mounted, and
  Worktree/File initially renders the lazy-loading frame until readiness/loading.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 46 tests / 4 files.
- Browser proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx src/app/bridge-app-protocol-router.browser.test.tsx src/app/bridge-app-lazy-boundary.browser.test.tsx --reporter verbose`
  passed 53 tests / 3 files.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, and
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-02 Codex React Lane Navigation Controller Checkpoint

- Extracted Review navigation/projection reconciliation into
  `BridgeWeb/src/app/bridge-app-review-navigation-controller.ts` as
  `useBridgeReviewNavigationController`.
- The hook owns explicit Review file-target application, refinement clearing
  when filters hide an explicit target, and fallback/default selection when the
  current selected item disappears from the projection.
- `BridgeReviewViewerMode` now composes the navigation controller after the
  projection coordinator and keeps only runtime/controller composition plus
  shell prop assembly for this slice.
- Added source-structure guards that the mode composes the navigation
  controller and no longer owns `appliedNavigationCommandRef`,
  `projection.orderedItemIds.includes(`, or
  `clearReviewRefinementsHidingExplicitTarget(`.
- File size checkpoint:
  `bridge-app-review-viewer-mode.tsx` is now 570 lines;
  `bridge-app-review-navigation-controller.ts` is 150 lines;
  `bridge-app-review-selection-controller.ts` remains 265 lines;
  `review-viewer-source-structure.unit.test.ts` is 188 lines.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  first failed because `useBridgeReviewNavigationController` was absent and
  `bridge-app-review-navigation-controller.ts` did not exist.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-control.unit.test.ts --reporter verbose`
  passed 11 tests / 2 files.
- Boundary proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 50 tests / 4 files.
- Browser selected/navigation proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "clicking a tree row fetches and renders the newly selected file|starts clicked Review foreground content demand before selected path commit|large fixture deep tree selection scrolls the selected file body into the CodeView viewport" --reporter verbose`
  passed 3 selected tests.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx -t "programmatic file reveal|preview command explicit|markdown preview restores CodeView|custom filter controls route through projection requests" --reporter verbose`
  passed 4 selected tests. The large browser run emitted existing React
  `flushSync` lifecycle warnings in markdown-preview tests, but all selected
  browser tests passed.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, and
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-02 Codex React Lane Selection Controller Checkpoint

- Extracted Review selected-item orchestration into
  `BridgeWeb/src/app/bridge-app-review-selection-controller.ts` as
  `useBridgeReviewSelectionController`.
- The hook owns foreground selection setup, selected-demand cancellation,
  selected content loading state, selection-commit telemetry, explicit
  `review.markFileViewed`, and file-viewed dedupe telemetry/RPC behavior.
- `BridgeReviewViewerMode` now composes the selection controller and keeps
  runtime construction, refs, store creation, worker clients, scheduler,
  resource executor, and shell wiring outside the lazy visual shell.
- Added source-structure guards that the mode composes the selection controller
  and no longer owns `pendingSelectionCommitTelemetryRef`,
  `lastTelemetryMarkedItemRef`, `review.markFileViewed`, or
  `recordReviewStartupTelemetry`.
- File size checkpoint:
  `bridge-app-review-viewer-mode.tsx` is now 646 lines;
  `bridge-app-review-selection-controller.ts` is 265 lines;
  `review-viewer-source-structure.unit.test.ts` is 165 lines.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  first failed because `useBridgeReviewSelectionController` was absent and
  `bridge-app-review-selection-controller.ts` did not exist.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-control.unit.test.ts --reporter verbose`
  passed 10 tests / 2 files.
- Boundary proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 49 tests / 4 files.
- Browser selected-content proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "clicking a tree row fetches and renders the newly selected file|starts clicked Review foreground content demand before selected path commit|large fixture deep tree selection scrolls the selected file body into the CodeView viewport" --reporter verbose`
  passed 3 selected tests.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx -t "programmatic file reveal|preview command explicit|markdown preview restores CodeView" --reporter verbose`
  passed 3 selected tests. The large browser run emitted existing React
  `flushSync` lifecycle warnings in markdown-preview tests, but all selected
  browser tests passed.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, and
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.

### 2026-07-02 Codex React Lane Visible Content Controller Checkpoint

- Extracted Review visible-content hydration out of
  `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx` into
  `BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts` as
  `useBridgeReviewVisibleContentController`.
- The hook owns visible-hydration pause calculation, visible demand load
  dispatch, `useVisibleReviewContentHydration`, paused fallback shaping, and
  the `setVisibleContentItemIds` callback consumed by metadata-interest
  runtime.
- `BridgeReviewViewerMode` still owns runtime construction and passes in the
  existing content registry, descriptor refs, demand scheduler, resource
  executor, telemetry refs, selected state, and package state. No runtime
  handles moved into Zustand or the lazy shell.
- Reviewer sidecar `019f2147-8bd4-7391-8ea4-e9735d6097fa` found two accepted
  P2s before commit: the controller imported fallback empties from
  `bridge-app-review-runtime`, and the source guard did not explicitly protect
  store creation / app-controller line count. Codex fixed both: fallback
  empties are local stable constants, and the guard rejects runtime/store
  creation imports plus checks the new app controller under 1k lines.
- File size checkpoint:
  `bridge-app-review-viewer-mode.tsx` is now 526 lines;
  `bridge-app-review-visible-content-controller.ts` is 139 lines;
  `review-viewer-source-structure.unit.test.ts` is 223 lines.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  failed first because `useBridgeReviewVisibleContentController` and
  `bridge-app-review-visible-content-controller.ts` were absent. Review-fix red
  then failed because the controller still imported `bridge-app-review-runtime`.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-control.unit.test.ts --reporter verbose`
  passed 12 tests / 2 files.
- Boundary proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 51 tests / 4 files.
- Browser visible/selection proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "visible added files hydrate without requiring file selection|clicking a tree row fetches and renders the newly selected file|starts clicked Review foreground content demand before selected path commit|large fixture deep tree selection scrolls the selected file body into the CodeView viewport" --reporter verbose`
  passed 4 selected tests.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx -t "programmatic file reveal|preview command explicit|markdown preview restores CodeView|custom filter controls route through projection requests" --reporter verbose`
  passed 4 selected tests. The large run emitted the existing React
  `flushSync` lifecycle warnings in markdown-preview tests.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false`
  passed, and `git diff --check` passed for the checkpoint files.

### 2026-07-02 Codex React Lane Review Control Event Hook Checkpoint

- Extracted Review app-mode DOM control-event wiring into
  `BridgeWeb/src/app/use-bridge-review-control-event-listeners.ts`.
- The hook owns only the two app-level custom-event bridges:
  `__bridge_select_review_item` and `__bridge_review_control`.
- `BridgeReviewViewerMode` still owns selection, content demand, registries,
  runtime refs, worker clients, and Zustand store creation outside the lazy
  visual shell; nothing moved into Zustand.
- Added source-structure guards that the mode composes the hook, the mode no
  longer contains the event strings/control-command parsing, and the hook does
  not import Pierre, the shell boundary, Zustand store creation, schedulers,
  resource executors, or AbortController.
- File size checkpoint:
  `bridge-app-review-viewer-mode.tsx` dropped from 899 to 814 lines;
  new hook is 172 lines.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  first failed because `useBridgeReviewControlEventListeners` was absent and
  the hook file did not exist.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-control.unit.test.ts --reporter verbose`
  passed 8 tests / 2 files.
- Boundary proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 47 tests / 4 files.
- Browser control-event proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture deep tree selection scrolls the selected file body into the CodeView viewport" --reporter verbose`
  passed 1 selected test.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx -t "programmatic file reveal|preview command explicit|stale markdown worker responses|markdown preview restores CodeView" --reporter verbose`
  passed 4 selected tests.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, and
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
- Broader browser note:
  the full `bridge-viewer-browser.integration.browser.test.tsx` file still has
  one out-of-scope CodeView geometry failure in
  `CodeView file header collapse preserves mid-viewport header position`
  (`aria-expanded=true` candidate offset 348 vs expected near 144). The
  programmatic control-event tests passed, so Codex left geometry/test
  infrastructure untouched in this React decomposition checkpoint.

### 2026-07-02 Codex React Lane Selected Content Effect Checkpoint

- Extracted the Review selected-content lifecycle effect into
  `BridgeWeb/src/app/bridge-app-review-selected-content-controller.ts` as
  `useBridgeReviewSelectedContentEffect`.
- The effect now lives beside the selected-content demand controller that owns
  foreground content load/abort/retry state; `BridgeReviewViewerMode` composes
  it and no longer owns that layout-effect block directly.
- Kept user-initiated selection semantics in the mode: `selectReviewItem` and
  `beginForegroundReviewSelection` still own selection identity, telemetry,
  cancellation of prior selected demand, and `review.markFileViewed`.
- Added source-structure guards that the selected-content effect stays in the
  demand controller module and not the lazy shell; the controller still imports
  no Pierre modules or shell boundary code.
- File size checkpoint:
  `bridge-app-review-viewer-mode.tsx` is now 783 lines;
  `bridge-app-review-selected-content-controller.ts` is 405 lines;
  `use-bridge-review-control-event-listeners.ts` is 172 lines.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts --reporter verbose`
  first failed because `useBridgeReviewSelectedContentEffect` was absent.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/review-viewer-source-structure.unit.test.ts src/app/bridge-app-control.unit.test.ts --reporter verbose`
  passed 9 tests / 2 files.
- Boundary proof:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-viewer-shared-boundaries.unit.test.ts src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/review-viewer/review-viewer-source-structure.unit.test.ts src/review-viewer/shell/review-viewer-shell.integration.test.tsx --reporter verbose`
  passed 48 tests / 4 files.
- Browser selected-content proof:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "clicking a tree row fetches and renders the newly selected file|starts clicked Review foreground content demand before selected path commit|large fixture deep tree selection scrolls the selected file body into the CodeView viewport" --reporter verbose`
  passed 3 selected tests.
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx -t "programmatic file reveal|preview command explicit|stale markdown worker responses|markdown preview restores CodeView" --reporter verbose`
  passed 4 selected tests.
- Static proof:
  touched-file `oxfmt --check` passed, touched-file type-aware `oxlint`
  passed with no output, and
  `pnpm --dir BridgeWeb exec tsc --noEmit --pretty false` passed.
