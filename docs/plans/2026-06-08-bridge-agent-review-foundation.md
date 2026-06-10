# Bridge Agent Review Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Canonical spec: [`docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`](../superpowers/specs/2026-06-10-bridge-review-foundation.md)
> Historical plan: [`docs/plans/2026-02-23-bridge-diff-execution-plan.md`](2026-02-23-bridge-diff-execution-plan.md) is retired and must not be executed for LUNA-337.

**Goal:** Build the source-provider-neutral Bridge foundation for agent-first review: review queries, source endpoints, checkpoints, package snapshots, item deltas, content handles, hashes, review generations, and review-friendly filtering before the full Pierre/Shiki/Trees viewer milestone.

**Architecture:** Bridge is query-first and stream-refreshed. React asks for a `BridgeReviewQuery` such as "compare main to working tree", "compare last checkpoint to working tree", or "open this file"; off-main Swift services resolve `BridgeSourceEndpoint` values, build metadata-only `BridgeReviewPackage` snapshots, publish item-level `BridgeReviewDelta` updates, and serve bytes lazily through scoped `BridgeContentHandle` values. Agent edit streams are provenance and grouping metadata; they are not the source of truth.

**Tech Stack:** Swift 6.2, Swift Testing, WKWebView, typed JSON-RPC, `agentstudio://` URL scheme, React/TypeScript/Vite/pnpm after scaffold, Vitest with `*.unit.test.ts`, `*.integration.test.ts`, and `*.e2e.test.ts` naming.

---

## Research-Backed Concurrency Boundary

References:

- Swift Concurrency: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
- Apple responsiveness guidance: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- Apple filesystem guidance: https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system
- Apple `WKURLSchemeHandler`: https://developer.apple.com/documentation/webkit/wkurlschemehandler

Design conclusions:

1. `WKWebView`, `WKURLSchemeHandler`, navigation policy, and WebKit callback completion are main-actor boundaries.
2. Atom-backed observable state is main-actor state in this app. Bridge may publish compact metadata there, but must not run review computation there.
3. File I/O, hashing, endpoint comparison, collation, classification, review-package building, and large JSON/data preparation must run off the main actor.
4. Main-actor Bridge code should be an ingress/egress adapter: parse UI/WebKit/RPC requests, await off-main actors/services, then publish or complete WebKit responses.
5. Off-main services exchange `Sendable` request/result models. Do not pass `WKURLSchemeTask`, `WKWebView`, `@Observable` state, atoms, or non-sendable UI closures across that boundary.

## Pierre CodeView Research Conclusions

References:

- Pierre Diffs docs: https://diffs.com/docs
- Pierre architecture note: https://pierre.computer/writing/on-rendering-diffs
- `@pierre/diffs` npm package, current researched version: `1.2.7`
- `@pierre/diffs` package declarations:
  - `dist/components/CodeView.d.ts`
  - `dist/react/CodeView.d.ts`
  - `dist/types.d.ts`
  - `dist/worker/WorkerPoolManager.d.ts`

Design conclusions:

1. `CodeView` is the high-level review surface for one large mixed scroll region containing `file` and `diff` items. It owns virtualization, measured layout reconciliation, sticky headers, selection, annotations, gutter utilities, and `scrollTo`.
2. `CodeViewItem` identity is explicit. Each item has a stable `id`, `type`, payload, optional `version`, and optional `collapsed` state. Content changes must bump the item version.
3. `CodeView` supports controlled and imperative updates. For large or streaming surfaces, prefer the imperative handle: `addItems`, `updateItem`, `updateItemId`, `getItem`, and `scrollTo`.
4. Pierre's worker pool moves Shiki syntax highlighting off the main JavaScript thread. It does not own Bridge query streaming, source comparison, content fetching, or agent provenance.
5. Pierre wants complete renderable item payloads: `FileContents` for file view, or `FileDiffMetadata` for diff view. Bridge can stream descriptors first, but BridgeWeb must hydrate a complete item before calling `CodeView.addItems` or `CodeView.updateItem`.
6. `cacheKey` is the render/highlight reuse boundary. If contents, filename, diff metadata, theme-relevant render options, or line-diff options change, the cache key must change.
7. WebKit worker loading is a real delivery requirement. `LUNA-337` must keep worker asset delivery in the app-resource contract, and `LUNA-338` must validate `worker.js` / `worker-portable.js` under the `agentstudio://` origin.
8. Do not stream raw line or hunk mutations into Pierre. Stream package snapshots and item-level deltas into BridgeWeb; BridgeWeb hydrates or updates complete `CodeViewItem` records only when visible, near-visible, selected, or explicitly requested.

## Status And Scope

This plan executes the canonical design in `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`.

`docs/plans/2026-02-23-bridge-diff-execution-plan.md` is retired historical context. Useful future-work decisions from that file were ported into the canonical spec as downstream architecture-plan inputs. Its old `DiffManifest(epoch)`, `ContentHandle(fileId, epoch)`, `agentstudio://resource/file/{fileId}?epoch=...`, `BridgeDiff*`, and `LUNA-347 -> LUNA-337` foundation instructions are not current.

### In Scope

1. Fold the old contract/content/runtime foundation into one coherent `LUNA-337` milestone.
2. Clean stale approve/reject patch vocabulary that conflicts with the read-only review model.
3. Define Bridge-owned, source-provider-neutral contracts:
   - `BridgeReviewQuery`
   - `BridgeSourceEndpoint`
   - `BridgeReviewCheckpoint`
   - `BridgeViewFilter`
   - `BridgeChangeGrouping`
   - `BridgeProvenanceFilter`
   - `BridgeReviewPackage`
   - `BridgeReviewDelta`
   - `BridgeReviewItemDescriptor`
   - `BridgeContentHandle`
4. Define `BridgeReviewSourceProvider` as the stable Bridge-owned protocol for endpoint comparison and content loading.
5. Treat Git refs, working tree, index/staged state, prompt checkpoints, session checkpoints, manual checkpoints, and saved time-window checkpoints as diff endpoints.
6. Use prompt/session checkpoints as the primary automatic checkpoint source.
7. Treat time-window views such as "last 30 minutes" as collation/filter modes over the raw change stream. A time-window view only becomes a canonical checkpoint when the user or system explicitly saves it as one.
8. Establish filters for folders, globs, file roles, extensions, change kinds, review state, agent/session provenance, and checkpoint/time ranges.
9. Define `BridgeReviewGeneration` as a branded monotonic package freshness guard. Do not use the generic term `epoch` for review contracts.
10. Define package snapshots plus item-level deltas shaped for Pierre `CodeViewItem` identity: stable `itemId`, monotonic `itemVersion`, item kind, collapsed state, cache key, and per-role content handles.
11. Define the BridgeWeb source organization before scaffolding.
12. Keep Bridge processing off the main actor: query resolution, endpoint comparison, checkpoint collation, delta building, content hashing/loading, file classification, and package building must run in actors/services, with the main actor only coordinating UI state and WebKit calls.
13. Keep full Pierre/Shiki/Trees rendering as the next milestone (`LUNA-338`), but shape `LUNA-337` contracts around Pierre CodeView's confirmed item identity, versioning, cache-key, worker, and virtualization requirements.

### Out Of Scope

1. Choosing or implementing the Git backend. The separate Git-focused lane owns backend selection and helper discovery behind the `BridgeReviewSourceProvider` contract.
2. Applying patches, accepting agent changes, or editing source code from the Bridge pane.
3. Durable annotation/comment schema. `LUNA-340` owns annotation bodies, markdown editing, edit history, and persistence decisions.
4. Full Pierre CodeView, Shiki highlighting, and Trees navigation. `LUNA-338` owns complete viewer rendering once `LUNA-337` package, item, delta, and content-handle contracts are stable.
5. Durable Bridge persistence. This milestone may use runtime-local indexes/caches, but it does not add a new Bridge persistence store.

## Current Code Evidence

The current repo already has enough infrastructure to ground this milestone:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
  - `FileChangeset` carries `paths`, `timestamp`, `batchSeq`, and suppression counts.
  - `GitWorkingTreeSnapshot` carries worktree summary and branch.
  - The local branch already removed `DiffEvent.hunkApproved` / `allApproved`; keep Task 1 as verification, not greenfield work.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneFilesystemProjectionAtom.swift`
  - Derives pane-scoped CWD filesystem events from worktree-level batches.
  - Does not classify file roles, create checkpoints, compute content identity, or package diffs.
- `Sources/AgentStudio/Features/Bridge/State/BridgeDomainState.swift`
  - Push transport still has a runtime `epoch` for stale push rejection.
  - Review contracts use `BridgeReviewGeneration`; do not use `DiffState.epoch` as review-package identity.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
  - Classifies `agentstudio://app/*` and `agentstudio://resource/content/{handleId}?generation=...`.
  - Serves packaged BridgeWeb app assets and handle-scoped in-memory/test content.
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
  - Handles `loadDiff` as status/stats only.
  - The local branch already removed stale `approveHunk` / `rejectHunk` command handling; keep the vocabulary boundary test as the guardrail.
- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/`
  - Contains the query-first `BridgeReview*` / `BridgeSourceEndpoint` / `BridgeReviewGeneration` model.
  - The retired `BridgeDiff*` / raw review-contract `epoch` model must not be recreated.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
  - Keys content by handle ID, review generation, item ID, role, endpoint identity, and content hash.
  - This protects base/head/file/diff roles for the same path from colliding.
- `Tests/BridgeContractFixtures/`
  - Current review fixtures are `bridge-review-package`, `bridge-review-checkpoint`, `bridge-review-query-time-window`, `bridge-review-delta`, and `bridge-review-package-missing-generation`.
  - Do not add new `bridge-diff-*` or `*-epoch` review-contract fixtures.

## Cutover Decisions

1. `LUNA-337` is a refactor of the existing diff/epoch branch work, not a new parallel model.
2. Use the richer query-first review model: `BridgeReviewQuery`, `BridgeViewFilter`, `BridgeChangeGrouping`, `BridgeProvenanceFilter`, and `BridgeReviewDelta` replace the collapsed `BridgeChangeCollationPolicy` / `BridgeChangeGroup` model.
3. `BridgeReviewGeneration` is a branded monotonic freshness guard in Swift and TypeScript, encoded over the wire as a plain integer field named `reviewGeneration`.
4. Bridge owns the canonical review contracts in `Features/Bridge`. The Git/backend lane supplies data behind `BridgeReviewSourceProvider`; it must not own BridgeWeb TypeScript contracts, content-handle shape, endpoint shape, package shape, or review-generation vocabulary.
5. The sibling Git plan `docs/superpowers/plans/2026-06-08-agentstudio-git-bridge-foundation.md` is a separate data-plane plan. Execute it through its Git Tasks 1-8 only. Bridge contracts, BridgeWeb shape, resource URLs, content-handle shape, endpoint shape, package shape, and review-generation vocabulary remain owned by this Bridge plan.

## Efficient Review Pipeline

```text
┌────────────────────────────────────────────────────────────────────┐
│ 1. Review query                                                     │
│                                                                    │
│    User asks for a view:                                           │
│      compare main -> working tree                                  │
│      compare checkpoint -> working tree                            │
│      compare arbitrary endpoints                                   │
│      open one file from a tree                                     │
│      browse a folder                                               │
│      filter an existing package                                    │
└───────────────┬────────────────────────────────────────────────────┘
                │ Sendable BridgeReviewQuery
                ▼
┌────────────────────────────────────────────────────────────────────┐
│ 2. Off-main package builder                                         │
│                                                                    │
│    BridgeReviewPipeline actor                                      │
│      resolves BridgeSourceEndpoint values                          │
│      asks BridgeReviewSourceProvider for comparison/tree/file data │
│      classifies and groups descriptors                             │
│      builds BridgeReviewPackage metadata                           │
│      registers BridgeContentHandle values                          │
│      mints BridgeReviewGeneration                                  │
└───────────────┬────────────────────────────────────────────────────┘
                │ compact metadata snapshot
                ▼
┌────────────────────────────────────────────────────────────────────┐
│ 3. BridgeWeb item registry                                          │
│                                                                    │
│    Applies package snapshot and BridgeReviewDelta operations        │
│    Tracks itemId -> itemVersion -> content handles                  │
│    Decides visible / near-visible / selected / hidden priority      │
└───────────────┬────────────────────────────────────────────────────┘
                │ lazy content request for needed items
                ▼
┌────────────────────────────────────────────────────────────────────┐
│ 4. Content hydration and Pierre rendering                           │
│                                                                    │
│    Fetch bytes through agentstudio://resource/content/{handleId}    │
│    Build complete FileContents or FileDiffMetadata                  │
│    Call CodeView.addItems / updateItem with id + version            │
│    Let Pierre WorkerPool handle Shiki highlighting and render cache │
└────────────────────────────────────────────────────────────────────┘
```

The event bus stays a fact plane. It does not route commands, compute diffs, classify file risk, or choose collation. Bridge consumers do that work downstream of the existing pane filesystem projection.

The stream part is the live refresh layer:

```text
Agent/FS event
  -> EventBus fact
  -> BridgeChangeIndex actor
  -> BridgeReviewDelta
  -> BridgeWeb item registry
  -> hydrate only visible or requested items
  -> CodeView.updateItem(item with version + 1)
```

Bridge streams changes. Pierre renders complete items. Do not stream raw hunk or line mutations directly into Pierre CodeView.

## Actor And Atom Boundary

Bridge follows the existing Agent Studio state architecture:

- `PaneFilesystemProjectionAtom` remains a `@MainActor` fact projection over runtime events.
- `BridgePaneController`, `BridgeRuntime`, `BridgeDomainState`, `RPCRouter`, and WebKit integration remain `@MainActor` because they coordinate UI, observable state, and `WKWebView`.
- `BridgeReviewPipeline`, `BridgeChangeIndex`, `BridgeReviewDeltaBuilder`, and `BridgeContentStore` are runtime-local actors/services, not atoms.
- Review query resolution, endpoint comparison, checkpoint collation, file classification, content hashing, content loading, package building, and delta building run off the main actor behind `Sendable` request/response models.
- Main-actor code awaits the runtime actors, then publishes compact metadata through the existing push pipeline.
- This milestone does not add a new `AtomRegistry` field or persistence store. If a later ticket needs durable Bridge state, it must follow `Features/Bridge/State/MainActor/{Atoms,Persistence}/` conventions and earn a separate state-boundary discussion.

```text
┌──────────────────────────────────────────────────────────────────┐
│ MainActor                                                        │
│                                                                  │
│  PaneFilesystemProjectionAtom                                    │
│  BridgePaneController / BridgeRuntime                            │
│  BridgeDomainState + push metadata                               │
│  WKWebView / RPCRouter / scheme callbacks                        │
└───────────────┬──────────────────────────────────────────────────┘
                │ async Sendable requests/results
                ▼
┌──────────────────────────────────────────────────────────────────┐
│ Off-main Bridge runtime actors/services                          │
│                                                                  │
│  BridgeReviewPipeline                                            │
│  BridgeChangeIndex                                               │
│  BridgeReviewDeltaBuilder                                        │
│  BridgeChangeCollator                                            │
│  BridgeReviewFileClassifier                                      │
│  BridgeReviewPackageBuilder                                      │
│  BridgeContentStore                                              │
│  BridgeReviewSourceProvider adapter calls                        │
└──────────────────────────────────────────────────────────────────┘
```

## Provider Protocol Drawing

```text
┌──────────────────────────────────────────────────────────────────┐
│ Bridge Review Pane                                               │
│                                                                  │
│  BridgePaneController / BridgeRuntime                            │
│        │                                                         │
│        ▼                                                         │
│  BridgeReviewQuery                                               │
│        │                                                         │
│        ▼                                                         │
│  BridgeReviewSourceProvider  ◄──── stable Bridge-owned protocol  │
│        │                                                         │
│        ├─ resolve endpoint                                       │
│        ├─ compare endpoints                                      │
│        ├─ read tree/file metadata                                │
│        ├─ load content handle                                    │
│        └─ create/read checkpoint endpoints                       │
│        │                                                         │
└────────┼─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ Git/backend lane                                                 │
│                                                                  │
│  One implementation behind the protocol                          │
│        │                                                         │
│        ├─ direct AgentStudioGitClient call if DTOs match exactly │
│        └─ thin mapping adapter if Git DTOs differ from Bridge DTOs│
│                                                                  │
│  This lane can change internals without changing Bridge packages │
└──────────────────────────────────────────────────────────────────┘
```

Bridge owns the `BridgeReviewSourceProvider` protocol because Bridge owns review queries, source endpoints, checkpoints, filters, grouping, provenance, content handles, review generations, package identity, and item deltas. The implementation can call `AgentStudioGitClient` directly if the client returns the exact Bridge request/result DTOs. If Git data-plane DTOs differ from Bridge review DTOs, use one thin mapping implementation such as `AgentStudioGitReviewSourceProvider`. Do not build a generic provider framework.

## Source Provider Boundary

Bridge defines the request/response contract and the stable `BridgeReviewSourceProvider` protocol. The provider implementation is supplied by the Git/backend lane.

### Direct Client Vs Adapter Rule

- Direct `AgentStudioGitClient` calls from `BridgeReviewPipeline` are allowed when the client's public `Sendable` request/result DTOs exactly match Bridge review contracts.
- Use a thin `BridgeReviewSourceProvider` implementation when mapping is needed between Git concepts and Bridge source endpoints, checkpoints, content handles, review generations, or package identity.
- Keep only one production implementation and one fake/test implementation in `LUNA-337`.
- Apply the same rule to future Git command systems: define the Bridge-owned command protocol first; call the client directly only when contracts match; add a thin mapper only when it protects a real boundary.

### BridgeReviewSourceProvider Owns

- Resolve a `BridgeSourceEndpoint` request into a provider-backed endpoint identity.
- Compare two `BridgeSourceEndpoint` values and return ordered changed-file records.
- Read tree and single-file metadata for non-diff file browsing/open-file queries.
- Load a `BridgeContentHandle` into bytes/text plus MIME and hash confirmation.
- Create or read checkpoint endpoints when the checkpoint is Bridge-visible.
- Return typed failures for missing endpoints, stale review generations, unavailable content, oversized content, binary content, and provider errors.
- Preserve stable Bridge output even if the underlying adapter calls a CLI tool, a Swift library, a worktree helper, or a future backend.

### BridgeReviewSourceProvider Must Not Own

- UI file filtering decisions.
- Annotation/comment schema.
- Source mutation or patch application.
- Backend selection policy outside the adapter injected into Bridge.
- Persistent checkpoint storage decisions beyond the runtime-local identity needed for `LUNA-337`.

### Provider Must Supply

- Endpoint identity for git refs, working tree, index/staged state, and checkpoint snapshots.
- Ordered changed-path records for endpoint comparisons.
- Tree entries and single-file descriptors for file browsing/open-file queries.
- Additions/deletions and change kind when available.
- Content handles or content identity that Bridge can expose through `agentstudio://resource/content/{handleId}?generation=...`.
- Content hashes or stable content fingerprints.
- Optional tree/content-set hash for a checkpoint or endpoint.
- Clear failure reasons for unavailable endpoints, binary files, oversized files, and stale review generations.

### Provider Must Not Decide

- BridgeWeb folder organization.
- Viewer UI filters.
- Annotation schema.
- Whether a file is hidden by default in the review UI.
- Whether the read-only Bridge pane can mutate source files.

## Contract Semantics

### BridgeSourceEndpoint

One side of a comparison. Endpoints are source-neutral; Git is one provider, not the type system.

Required fields:

- `endpointId`: stable opaque ID.
- `kind`: `gitRef`, `workingTree`, `index`, `promptCheckpoint`, `sessionCheckpoint`, `manualCheckpoint`, `savedTimeWindowCheckpoint`.
- `repoId`
- `worktreeId`
- `label`
- `createdAtUnixMilliseconds`
- `contentSetHash`: optional when the provider cannot compute it cheaply.
- `providerIdentity`: opaque provider-local identity such as git SHA, ref name, checkpoint ID, or working-tree token.

Rules:

- `workingTree` and `index` endpoints may be volatile.
- Checkpoint endpoints are stable once created.
- Time-window views are not checkpoint endpoints unless saved.

### BridgeReviewQuery

The user intent that starts package or file production. Query mode is first-class because users can compare endpoints, browse a tree, open one file, or filter an existing package.

Required fields:

- `queryId`
- `queryKind`: `compare`, `openFile`, `browseTree`, `filterPackage`, `groupPackage`
- `repoId`
- `worktreeId`
- `baseEndpointId`: required for compare queries.
- `headEndpointId`: required for compare and open-file queries.
- `comparisonSemantics`: `twoDot`, `threeDot`, `checkpointDelta`, `indexDelta`, `workingTreeDelta`, `none`.
- `pathScope`
- `fileTarget`: optional path or file ID for open-file queries.
- `viewFilter`
- `grouping`
- `provenanceFilter`

Rules:

- "Compare against main", "compare against last checkpoint", "compare staged vs working tree", and "open this file" are query modes, not separate Bridge systems.
- Query mode decides whether Bridge produces a package snapshot, file result, tree result, or a metadata-only filter/grouping update.
- Agent edit streams are provenance filters and grouping inputs, not source truth.

### BridgeReviewCheckpoint

A stable review boundary.

Required fields:

- `checkpointId`
- `checkpointKind`: `prompt`, `session`, `manual`, `savedTimeWindow`
- `repoId`
- `worktreeId`
- `paneId`
- `createdAtUnixMilliseconds`
- `reviewGeneration`
- `baseEndpointId`
- `headEndpointId`
- `eventSequenceStart`
- `eventSequenceEnd`
- `batchSequenceStart`
- `batchSequenceEnd`
- `contentSetHash`
- `agentSessionId`
- `promptId`
- `summary`

Rules:

- Prompt/session checkpoints are the primary automatic checkpoints.
- Manual checkpoints are canonical user-created checkpoints.
- Saved time-window checkpoints are canonical only after save.
- Checkpoints must be durable enough for review identity, but `LUNA-337` does not require a new persistent store.

### BridgeViewFilter

The non-destructive visible subset applied to package/tree/file descriptors.

Required fields:

- `includedPathGlobs`
- `excludedPathGlobs`
- `includedFileClasses`
- `excludedFileClasses`
- `includedExtensions`
- `excludedExtensions`
- `changeKinds`
- `reviewStates`
- `showHiddenFiles`
- `showBinaryFiles`
- `showLargeFiles`

Rules:

- Filters should not mutate the package source of truth.
- If a filter only hides or reveals already-described items, BridgeWeb can apply it locally.
- If a filter changes the source comparison or requested endpoint scope, React sends a new `BridgeReviewQuery`.

### BridgeChangeGrouping

The organization applied to descriptors for navigation and review order.

Supported grouping kinds:

- `flat`
- `folder`
- `fileClass`
- `changeKind`
- `reviewState`
- `agentStream`
- `prompt`
- `session`
- `checkpoint`
- `custom`

Rules:

- Grouping changes presentation and order; it does not create checkpoints.
- A package can carry multiple group summaries if the UI needs toggles without recomputing the provider comparison.

### BridgeProvenanceFilter

The agent/workflow attribution filter applied over descriptors and change facts.

Required fields:

- `paneIds`
- `agentSessionIds`
- `promptIds`
- `operationIds`
- `createdAfterUnixMilliseconds`
- `createdBeforeUnixMilliseconds`
- `sourceKinds`: `runtimeEvent`, `filesystemWatch`, `gitStatus`, `manualScan`.

Rules:

- Provenance filters explain who/when/why, but endpoint comparison and content hashes remain source truth.
- Multiple panes can contribute to one review package. Keep stream identity as metadata so users can merge or split agent work.

### BridgeReviewItemDescriptor

A review-friendly item entry inside a package. This descriptor is metadata-first and maps to a future Pierre `CodeViewItem`.

Required fields:

- `itemId`
- `itemKind`: `file`, `diff`
- `itemVersion`
- `basePath`
- `headPath`
- `changeKind`
- `fileClass`: `source`, `test`, `docs`, `config`, `generated`, `vendor`, `binary`, `large`, `fixture`, `unknown`
- `language`
- `extension`
- `sizeBytes`
- `baseContentHash`
- `headContentHash`
- `contentHashAlgorithm`
- `additions`
- `deletions`
- `isHiddenByDefault`
- `hiddenReason`
- `reviewPriority`
- `contentRoles`
  - `base`: optional `BridgeContentHandle`
  - `head`: optional `BridgeContentHandle`
  - `diff`: optional `BridgeContentHandle`
  - `file`: optional `BridgeContentHandle`
- `cacheKey`
- `provenance`
- `annotationSummary`
- `reviewState`
- `collapsed`

Rules:

- File identity must not be path-only. Use endpoint, path, and content identity.
- Added files have a head handle only.
- Deleted files have a base handle only.
- Modified files can have base and head handles, or a diff handle when the provider supplies patch/diff metadata directly.
- Plain file browsing/open-file queries use a file handle for the selected endpoint.
- If render-significant content changes while `itemId` remains stable, increment `itemVersion` and change `cacheKey`.
- Hidden by default is a UI default, not data loss.
- Generated/vendor/binary/large files should collapse by default with counts.
- Tests and docs should be filterable, not globally hidden.

### BridgeContentHandle

The lazy content pointer React uses for fetch. Handles are scoped to a package generation and content role.

Required fields:

- `handleId`
- `itemId`
- `role`: `base`, `head`, `diff`, `file`
- `endpointId`
- `reviewGeneration`
- `resourceUrl`
- `contentHash`
- `contentHashAlgorithm`
- `cacheKey`
- `mimeType`
- `language`
- `sizeBytes`
- `isBinary`

Rules:

- React must include the review generation when fetching content.
- Swift must reject stale review-generation requests.
- Cache keys must include endpoint identity and content hash, not just path.
- Handles do not grant arbitrary path access.
- `BridgeContentStore` must be keyed by handle ID, package ID or generation, item ID, role, and content hash. It must not be keyed by file ID alone.

### BridgeReviewPackage

The metadata payload pushed to BridgeWeb.

Required fields:

- `packageId`
- `schemaVersion`
- `reviewGeneration`
- `query`
- `baseEndpoint`
- `headEndpoint`
- `orderedItemIds`
- `itemsById`
- `groups`
- `summary`
- `filterState`
- `generatedAtUnixMilliseconds`

Rules:

- The package is metadata-heavy and content-light.
- File content is pulled by handle through the scheme handler.
- Packages must be small enough to push safely through the existing Bridge push path.
- The package must be valid without Pierre, Shiki, or Trees, but item identity/version/cache fields must map cleanly to Pierre `CodeViewItem`.

### BridgeReviewDelta

An incremental metadata update for an existing package.

Required fields:

- `packageId`
- `reviewGeneration`
- `revision`
- `operations`
  - `addItems`
  - `updateItems`
  - `removeItems`
  - `moveItems`
  - `updateGroups`
  - `updateSummary`
  - `invalidateContent`

Rules:

- Deltas update BridgeWeb's item registry. They do not stream raw line/hunk mutations into Pierre.
- If a visible item's renderable content changes, BridgeWeb hydrates the new complete item and calls `CodeView.updateItem` with `itemVersion + 1`.
- If a hidden or offscreen item changes, BridgeWeb updates tree/count metadata and postpones content fetch until the item becomes visible, near-visible, selected, or explicitly expanded.
- Deltas must be ordered by package-local `revision`; React drops stale or duplicate revisions.

## Review Filter Defaults

Default initial view:

- Show source, config, and human-authored test files.
- Collapse generated, vendor, binary, large, and fixture files.
- Show docs as collapsed when the package is large, visible when the package is small.
- Surface counts for every hidden class.
- Preserve quick toggles for tests, docs, generated, binary, and large files.

Required filter controls for `LUNA-337` package semantics:

- Folder/path filter.
- Extension/language filter.
- File class filter.
- Change kind filter.
- Review state filter.
- Checkpoint/session/prompt filter.
- Time-window filter.
- Endpoint comparison selector.

`LUNA-338` can decide exact UI controls, but `LUNA-337` must deliver enough metadata for them.

## BridgeWeb Scaffold Shape

`LUNA-337` creates the minimal BridgeWeb scaffold after the Swift contracts are stable. Use this organization:

```text
BridgeWeb/
  src/
    app/
      bridge-app.tsx
      bridge-app-bootstrap.ts

    bridge/
      bridge-push-envelope.ts
      bridge-push-receiver.ts
      bridge-resource-url.ts
      bridge-rpc-client.ts

    foundation/
      review-query/
        bridge-review-query.ts
        bridge-source-endpoint.ts
        bridge-view-filter.ts
        bridge-change-grouping.ts
        bridge-provenance-filter.ts
        review-query.unit.test.ts

      review-package/
        bridge-review-generation.ts
        bridge-review-checkpoint.ts
        bridge-content-handle.ts
        bridge-review-package.ts
        bridge-review-item-descriptor.ts
        bridge-review-delta.ts
        bridge-file-classifier.ts
        bridge-review-package-adapter.unit.test.ts
        bridge-review-delta.unit.test.ts
        bridge-file-classifier.unit.test.ts

      content/
        content-resource-loader.ts
        review-content-cache.ts
        content-resource-loader.integration.test.ts
        review-content-cache.unit.test.ts

    review-viewer/
      shell/
        review-viewer-shell.tsx
        review-viewer-shell.integration.test.tsx
```

Naming rules:

- No generic `types.ts`, `utils.ts`, `store.ts`, `protocol.ts`, or `helpers.ts`.
- Tests use exact naming classes:
  - `*.unit.test.ts`
  - `*.unit.test.tsx`
  - `*.integration.test.ts`
  - `*.integration.test.tsx`
  - `*.e2e.test.ts`
- Pierre/Shiki/Trees adapter files are not part of `LUNA-337`; add `foundation/pierre-adapter/` in `LUNA-338`.

## Implementation Tasks

### Task 0: Reconcile Existing Diff/Epoch Foundation

**Files:**

- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeDiffEndpoint.swift` -> `BridgeSourceEndpoint.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeDiffPackage.swift` -> `BridgeReviewPackage.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeFileDescriptor.swift` -> `BridgeReviewItemDescriptor.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeCheckpoint.swift` -> `BridgeReviewCheckpoint.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeContentHandle.swift`
- Delete/replace: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeCollationPolicy.swift`
- Delete/replace: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeGroup.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewQuery.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeViewFilter.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeGrouping.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeProvenanceFilter.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewDelta.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewGeneration.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeDiffPackageBuilder.swift` -> `BridgeReviewPackageBuilder.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeCollator.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewSourceProvider.swift`
- Rename/update tests:
  - `BridgeDiffPackageBuilderTests.swift` -> `BridgeReviewPackageBuilderTests.swift`
  - `BridgeChangeCollatorTests.swift` -> review-query/grouping tests if the collator no longer owns the contract shape.
- Rename/update fixtures:
  - `bridge-diff-package.json` -> `bridge-review-package.json`
  - `bridge-change-checkpoint.json` -> `bridge-review-checkpoint.json`
  - `bridge-collation-time-window.json` -> `bridge-review-query-time-window.json`
  - `bridge-diff-package-missing-epoch.json` -> `bridge-review-package-missing-generation.json`
  - Add `bridge-review-delta.json`.
- Update docs:
  - `docs/architecture/swift_react_bridge_design.md`
  - Verify `docs/superpowers/plans/2026-06-08-agentstudio-git-bridge-foundation.md` remains scoped to Git Tasks 1-8 and does not own Bridge contracts.

- [x] Replace raw review-contract `epoch` fields with `BridgeReviewGeneration` / `reviewGeneration`; leave existing push-envelope `__epoch` terminology alone unless a separate push-transport task changes it.
- [x] Replace `BridgeDiffEndpoint` with `BridgeSourceEndpoint` in review foundation contracts, builders, provider protocols, tests, and fixtures.
- [x] Replace `BridgeDiffPackage` with `BridgeReviewPackage`.
- [x] Replace `BridgeFileDescriptor.contentHandle` with `BridgeReviewItemDescriptor.contentRoles`.
- [x] Replace `BridgeChangeCollationPolicy` and `BridgeChangeGroup` with `BridgeViewFilter`, `BridgeChangeGrouping`, `BridgeProvenanceFilter`, and package `groups`.
- [x] Replace `staleEpoch` provider/content failures with `staleReviewGeneration`.
- [x] Replace `agentstudio://resource/file/{fileId}?epoch=...` review-content URLs with `agentstudio://resource/content/{handleId}?generation=...`.
- [x] Verify no review foundation model names still use the old `BridgeDiff*` contract family.
- [ ] Run `mise run test -- --filter BridgeReview`.

Expected result:

- The branch has one review foundation model family. No old diff/epoch contracts remain beside the new query-first review contracts.

### Task 1: Plan And Vocabulary Boundary

**Files:**

- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Diagnostics/RuntimeEnvelopeTraceSummary.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- Test: existing affected Swift tests under `Tests/AgentStudioTests/Features/Bridge/` and runtime event tests.

- [x] Remove `DiffCommand.approveHunk` and `DiffCommand.rejectHunk`.
- [x] Remove or rename `DiffEvent.hunkApproved` / `allApproved` so the diff plane speaks review/navigation state, not patch acceptance.
- [x] Keep review artifact actions in `ReviewMethods`, not source mutation commands in `DiffCommand`.
- [x] Re-run `mise run test -- --filter Bridge`.
- [x] Re-run `mise run lint`.

Expected result:

- Runtime vocabulary no longer suggests that the Bridge diff surface can approve, reject, or apply source changes.

### Task 2: Swift Contract Models

**Files:**

- Create/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewGeneration.swift`
- Create/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewQuery.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeDiffEndpoint.swift` -> `BridgeSourceEndpoint.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeCheckpoint.swift` -> `BridgeReviewCheckpoint.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeViewFilter.swift`
- Create/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeChangeGrouping.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeProvenanceFilter.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeDiffPackage.swift` -> `BridgeReviewPackage.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewDelta.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeFileDescriptor.swift` -> `BridgeReviewItemDescriptor.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeContentHandle.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeFileClass.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewFoundationContractTests.swift`
- Fixture: `Tests/BridgeContractFixtures/valid/bridge-review-package.json`
- Fixture: `Tests/BridgeContractFixtures/valid/bridge-review-checkpoint.json`
- Fixture: `Tests/BridgeContractFixtures/edge/bridge-review-query-time-window.json`
- Fixture: `Tests/BridgeContractFixtures/valid/bridge-review-delta.json`
- Fixture: `Tests/BridgeContractFixtures/invalid/bridge-review-package-missing-generation.json`

- [x] Add `Codable`, `Equatable`, and `Sendable` contract models.
- [x] Use explicit field names from the Contract Semantics section.
- [x] Keep wire timestamps as Unix milliseconds for Swift/TS parity.
- [x] Keep content hashes opaque strings with an explicit algorithm field.
- [x] Include `BridgeReviewGeneration` as a branded value type encoded as a plain integer `reviewGeneration` field instead of a raw `epoch` integer in review contracts.
- [x] Include per-role content handles on `BridgeReviewItemDescriptor`, not a single head-only handle.
- [ ] Cover added, deleted, modified, and open-file descriptors in fixtures/tests so missing base/head roles are represented explicitly.
- [x] Write Swift fixture decode/encode tests.
- [ ] Run `mise run test -- --filter BridgeReviewFoundationContractTests`.

Expected result:

- Swift has stable source-provider-neutral contracts before any TypeScript scaffold exists.

### Task 3: Off-Main Bridge Review Pipeline Boundary

**Files:**

- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift`
- Rename/rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeDiffPackageBuilder.swift` -> `BridgeReviewPackageBuilder.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewDeltaBuilder.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewPipelineRequest.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewPipelineResult.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewPipelineTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewPackageBuilderTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewDeltaBuilderTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeContentStoreTests.swift`

- [x] Define `BridgeReviewPipeline` as the single off-main actor that orchestrates review package creation for a pane/source.
- [x] Define request/result value models that are `Codable`, `Equatable`, and `Sendable` where applicable.
- [x] Ensure the pipeline accepts only source/provider/checkpoint/filter inputs, never `WKWebView`, `WKURLSchemeTask`, atoms, or observable state.
- [x] Define `BridgeContentStore` as a runtime-local actor keyed by handle ID, package ID or review generation, item ID, role, endpoint identity, and content hash.
- [x] Add tests proving base/head handles for the same path do not collide.
- [x] Define `BridgeReviewPackageBuilder` as pure package assembly over review query, endpoint comparison/tree/file results, item descriptors, groups, hidden summary, and filter state.
- [ ] Define `BridgeReviewDeltaBuilder` as pure item-delta assembly over change-index facts and package-local revisions.
- [ ] Add cancellation and stale-review-generation behavior at the actor boundary.
- [x] Run `mise run test -- --filter BridgeReviewPipeline`.
- [x] Run `mise run test -- --filter BridgeReviewPackageBuilder`.
- [ ] Run `mise run test -- --filter BridgeReviewDeltaBuilder`.
- [x] Run `mise run test -- --filter BridgeContentStore`.

Expected result:

- The Bridge review foundation has one explicit off-main processing boundary before individual provider, index, collation, and content pieces are wired in.

### Task 4: Bridge Review Source Provider Facade

**Files:**

- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewSourceProvider.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeEndpointResolutionRequest.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeEndpointComparisonRequest.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeEndpointComparison.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeTreeReadRequest.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeTreeReadResult.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewItemDescriptorRequest.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeCheckpointEndpointRequest.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeContentLoadRequest.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeContentLoadResult.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeProviderFailure.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewSourceProviderContractTests.swift`
- Test support: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewSourceProviderFake.swift`

- [x] Define `BridgeReviewSourceProvider` as the narrow Bridge-owned protocol for endpoint resolution, endpoint comparison, checkpoint endpoint lookup, and content loading.
- [x] Include these provider methods:
  - `resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint`
  - `compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison`
  - `readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult`
  - `readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws -> BridgeReviewItemDescriptor`
  - `resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint`
  - `loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult`
- [x] Model `BridgeProviderFailure` as typed failure data with cases for unavailable endpoint, stale review generation, missing content, oversized content, binary content, provider unavailable, and provider failed.
- [x] Keep provider implementations off the main actor; `BridgePaneController` may call them only through async facade methods.
- [ ] Keep production backend implementation out of this task except for direct-client shape notes and a fake provider used by tests.
- [ ] Document in type comments that `BridgeReviewPipeline` may call `AgentStudioGitClient` directly if its public DTOs exactly match Bridge contracts.
- [ ] Document in type comments that a thin `AgentStudioGitReviewSourceProvider` mapping implementation is required when Git DTOs differ from Bridge endpoint/checkpoint/content-handle/package contracts.
- [ ] Run `mise run test -- --filter BridgeReviewSourceProviderContractTests`.

Expected result:

- Bridge has one stable provider protocol. Direct client calls are allowed only when contracts match exactly; otherwise a thin mapper protects `BridgeReviewPackage`, `BridgeReviewDelta`, `BridgeContentHandle`, checkpoint, query/filter/grouping, and BridgeWeb contract shapes.

### Task 5: Bridge Change Index

**Files:**

- Create: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeIndex.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeChangeIndexTests.swift`

- [x] Build a runtime-local `BridgeChangeIndex` actor that records checkpoints, endpoint identity, event/batch sequence ranges, provenance, package-local revision facts, and active review generation.
- [ ] Inject `any BridgeReviewSourceProvider` into the change index or the owning runtime/controller path.
- [ ] Feed it from existing pane filesystem context facts and explicit source loads.
- [x] Keep it runtime-local; do not add an `AtomRegistry` field or persistence store in this milestone.
- [ ] Keep main-actor entry points thin: collect UI/request context, await the actor, then publish resulting metadata.
- [ ] Use a fake provider in tests.
- [x] Run `mise run test -- --filter BridgeChangeIndex`.

Expected result:

- Bridge can create checkpoint/collation/package identity without owning Git implementation details.

### Task 6: Collation, Diff Package Loading, And Resource Handles

**Files:**

- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeCollator.swift`
- Rewrite: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewFileClassifier.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/BridgeDomainState.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/Methods/DiffMethods.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeChangeCollatorTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeReviewFileClassifierTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgePaneControllerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`

- [x] Implement pure file-class classification by path, extension, generated/vendor/build patterns, binary flag, and size threshold.
- [x] Implement pure filtering/grouping from descriptors/checkpoints/endpoints into package groups and summaries.
- [x] Wire classification/collation through `BridgeReviewPipeline`, not directly through `BridgePaneController`.
- [ ] Cover prompt, session, last-checkpoint, manual-range, time-window, git-comparison, folder, and file-class policies.
- [x] Verify time-window collation does not create a canonical checkpoint unless explicitly saved.
- [x] Replace placeholder resource serving with handle-based in-memory/test content resolution.
- [x] Reject stale review-generation content requests.
- [x] Reject unknown content handles and traversal attempts.
- [ ] Make `diff.loadDiff` or its replacement submit a `BridgeReviewQuery` and publish a `BridgeReviewPackage` instead of only stats.
- [x] Build packages and resolve content handles through `BridgeReviewPipeline` / `BridgeContentStore`; scheme callbacks may hop to main actor only for WebKit-facing response completion.
- [ ] Decide whether `diff.requestFileContents` remains necessary once scheme fetch is the single content path; remove duplicate RPC content fetch if it is redundant.
- [x] Run `mise run test -- --filter BridgeChangeCollator`.
- [x] Run `mise run test -- --filter BridgeReviewFileClassifier`.
- [x] Run `mise run test -- --filter BridgeSchemeHandler`.
- [ ] Run `mise run test -- --filter BridgePaneController`.
- [ ] Run the WebKit serialized Bridge tests through the project test command.

Expected result:

- `agentstudio://resource/content/{handleId}?generation=...` serves real package-scoped content from handles, and the package metadata/deltas are created off the main actor with review-friendly query/filter/grouping semantics.

### Task 7: App Asset Delivery Foundation

**Files:**

- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- Modify: `Sources/AgentStudio/Infrastructure/Extensions/Bundle+AppResources.swift`
- Modify: `Package.swift`
- Modify: `.mise.toml`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`

- [x] Define the app-resource lookup for `agentstudio://app/index.html`.
- [x] Serve real packaged assets once BridgeWeb is built.
- [x] Keep worker chunk asset support in the delivery contract, but do not require Pierre worker code in `LUNA-337`.
- [x] Verify MIME types and missing-resource errors.
- [x] Run `mise run test -- --filter BridgeSchemeHandler`.
- [ ] Run `mise run test -- --filter WebKitSerializedTests`.

Expected result:

- Bridge can host a real web app shell from packaged resources before viewer-specific libraries land.

### Task 8: BridgeWeb Scaffold Plan Execution

**Files:**

- Create: `BridgeWeb/package.json`
- Create: `BridgeWeb/pnpm-lock.yaml`
- Create: `BridgeWeb/tsconfig.json`
- Create: `BridgeWeb/vite.config.ts`
- Create: `BridgeWeb/src/app/bridge-app.tsx`
- Create: `BridgeWeb/src/app/bridge-app-bootstrap.tsx`
- Create: folders and files listed in the BridgeWeb Scaffold Shape section.

- [x] Use `scaffold-project` semantics before creating files.
- [x] Use pnpm.
- [x] Enable strict TypeScript.
- [x] Add Vitest.
- [x] Add test filename patterns exactly as specified in this plan.
- [x] Do not add Pierre/Shiki/Trees dependencies in this task.
- [x] Add shared contract fixtures copied from `Tests/BridgeContractFixtures`.
- [x] Run BridgeWeb lint/type/test/build tasks.

Expected result:

- The TypeScript tree mirrors the Bridge domain instead of generic stores/protocols.

### Task 9: Minimal Review Shell Proof

**Files:**

- Modify: `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- Modify: `BridgeWeb/src/foundation/review-package/bridge-review-package.ts`
- Modify: `BridgeWeb/src/foundation/content/content-resource-loader.ts`
- Test: `BridgeWeb/src/review-viewer/shell/review-viewer-shell.integration.test.tsx`
- Test: `BridgeWeb/src/foundation/content/content-resource-loader.integration.test.ts`

- [ ] Render package summary, endpoint labels, checkpoint/collation label, and filtered file list.
- [ ] Fetch selected file content through the content handle.
- [ ] Support folder/file-class/change-kind filter state in the shell.
- [ ] Keep rendering simple; no Pierre CodeView in `LUNA-337`.
- [ ] Run BridgeWeb tests.
- [ ] Run packaged WebKit smoke once the bundle is copied into app resources.

Expected result:

- The user can inspect a package-shaped review surface before advanced viewer integration.

### Task 10: Full Validation

**Files:**

- No new files.

- [x] Run `git diff --check`.
- [x] Run `mise run lint`.
- [x] Run `mise run test`.
- [x] Run BridgeWeb lint/type/test/build tasks after BridgeWeb exists.
- [ ] Capture failing command, exit code, and scoped blocker if failures are outside Bridge scope.

Expected result:

- Current branch has a verified Bridge foundation baseline, with any unrelated validation failures called out separately.

## Current Linear Graph

Linear should track this repo plan instead of duplicating the design. The active graph is:

```text
LUNA-337  Bridge Agent Review Foundation
  -> LUNA-338  Pierre/Shiki/Trees Review Viewer
  -> LUNA-340  Annotation Anchors And Review Artifacts
  -> LUNA-377  Agent Review Workflow And Timeline
  -> LUNA-348  Bridge Security Hardening
  -> LUNA-341  Fan-In Performance And Lifecycle Hardening
```

`LUNA-347` is historical. Its scope is folded into `LUNA-337`; it should not remain a separate blocker for the foundation.

Downstream work after LUNA-337 should start from dedicated architecture specs
and execution plans, not from the retired February document:

- `LUNA-338`: Pierre/Shiki/Trees viewer integration.
- `LUNA-340`: annotation anchors and durable review artifacts.
- `LUNA-377`: agent review workflow and timeline.
- `LUNA-348`: Bridge security hardening.
- `LUNA-341`: fan-in performance and lifecycle hardening.

## Definition Of Done

`LUNA-337` is done when:

1. Runtime vocabulary no longer exposes approve/reject/patch-apply semantics for the Bridge diff surface.
2. `BridgeReviewSourceProvider` is the single stable protocol Bridge uses for endpoint resolution, endpoint comparison, checkpoint endpoint lookup, and content loading; direct `AgentStudioGitClient` calls are allowed only when DTOs match exactly.
3. Swift contract fixtures define review queries, source endpoints, checkpoints, filters, grouping, provenance filters, review packages, review deltas, item descriptors, and content handles.
4. Change indexing, checkpoint collation, file classification, content loading, hashing, and package building run off the main actor behind actors/services.
5. Prompt/session checkpoints and time-window collation semantics are documented and tested.
6. Review packages include endpoint identity, review generation, item versions, hashes, per-role content handles, file classes, hidden summaries, provenance, grouping, and review filter metadata.
7. `agentstudio://app/index.html` can serve a real Bridge app shell.
8. `agentstudio://resource/content/{handleId}?generation=...` serves package-scoped content and rejects stale/invalid requests.
9. BridgeWeb scaffold mirrors the domain structure and uses required test naming.
10. Pierre/Shiki/Trees remain downstream.
11. `git diff --check`, `mise run lint`, and `mise run test` pass or report a scoped non-Bridge blocker with evidence.
