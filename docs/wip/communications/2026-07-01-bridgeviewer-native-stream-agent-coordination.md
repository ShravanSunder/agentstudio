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
