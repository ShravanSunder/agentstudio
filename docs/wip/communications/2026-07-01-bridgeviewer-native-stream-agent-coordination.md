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
