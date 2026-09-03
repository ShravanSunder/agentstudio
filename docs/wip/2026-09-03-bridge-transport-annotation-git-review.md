# Bridge transport, annotation system, and agentstudio-git review

Date: 2026-09-03. Branch `bridge-review-design-2026-08-14` at c688dd60f.
agentstudio-git pinned at b18aff893. libgit2 vendored 1.9.4.
Read-only review. No code changes were made by this review. Note on anchors: a concurrent session has uncommitted edits in this worktree (the comm-worker epoch change reviewed in section 6 plus three Swift files). Line numbers for `BridgePaneController+DiffCommands.swift` were read from that working tree, which deletes 8 lines near the top, so HEAD line numbers are 8 higher. All G rows were checked by an independent Sonnet read-only verifier
(four parallel forks, claims C1 to C10) and by my own reads; the Status
column records which. Verifier corrections to my original claims are
kept in the rows rather than hidden.

Purpose: input for the next specification and program design. Older
specs cited below are temporary artifacts; where code and doc disagree,
the disagreement is recorded here rather than treated as a defect in
either.

## 1. Verdicts

| Area | Verdict |
| --- | --- |
| Transport genericity | Generic. Three product routes, pane-scoped session, producer registry, typed metadata-application registry, generic `MetadataCatalogTransfer<Entry>`. File and Review are applications on it. |
| Annotation system genericity | Generic at the transport and catalog layer. Surface-specific only in source-material capture (File vs Review material providers), which is the right place for the split. |
| Annotation correctness | Two correctness defects (placement depends on viewport demand; all-or-nothing `unavailable`). |
| Annotation performance | One hot-path chain makes every draft flush a full projection rebuild including file re-reads and re-hashes. |
| agentstudio-git performance | The largest single cost is a one-line libgit2 API choice (`git_diff_tree_to_workdir` vs `_with_index`). Second is per-delta patch generation for line stats. |
| Refresh proposal (caller-owned Review session) | Premise about full rebuild is correct. Premise that a path-scoped libgit2 diff exists is false. Recommended order differs from the proposal. |

## 2. Refresh proposal validation

The proposal claimed: Review refresh drops the changeset, so every
one-file change rebuilds all 927 items; recommended a caller-owned
agentstudio-git Review session that retains the full snapshot and does
a conservative one-file path-scoped update with a long fallback list.

### 2.1 What is true

| Claim | Status | Anchor |
| --- | --- | --- |
| Review dirty fact is built with `fileChangeset: nil` | Confirmed | `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift:312-327` |
| Every invalidation forces a Review refresh | Confirmed | `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+RefreshAdmission.swift:110-113` sets `requiresReviewRefresh: true` |
| Refresh runs a full comparison | Confirmed | `BridgePaneController+DiffCommands.swift:842-871` `loadReviewPackageForRefresh` -> `makeReviewRefreshPipelineRequest` (no `preparedComparison`, lines ~890-920) -> `resolveContributionRequestIfNeeded` -> `acquireReviewPackage` |
| The reservation type can carry a changeset | Confirmed | `BridgePaneRefreshCatchUpReservation` has `fileChangeset`; the Review lane never fills it |
| Shared Review backing is discarded on every files-changed event | Confirmed | `App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift:272` calls `worktreeProductConstructionCoordinator.invalidate(worktree:)`, which advances the freshness epoch (`Construction/BridgeWorktreeProductConstructionCoordinator.swift:102-108`) before any pane decides whether the change mattered |

### 2.2 What is false

| Claim | Status | Anchor |
| --- | --- | --- |
| "Path-scoped libgit2 diff: yes" | False | `GitDiffRequest` and `GitContributionDiffRequest` in agentstudio-git have no pathspec; only `GitStatusOptions.pathspecs` exists. The app's `BridgeReviewQuery.pathScope` is a post-hoc visibility filter in `ReviewFoundation/BridgeChangeCollator.swift:69-77`, and is only per-path on the tree-read fallback (`AgentStudioGitBridgeReviewDataClient.swift:203-235`). The primary comparison at `AgentStudioGitBridgeReviewDataClient.swift:69-73` is a whole-repository `loadGitDiff`. |
| An incremental one-file update is the first lever | Disagree | The comparison cost profile (tmp/profiles/2026-09-03-review-git-live-profile/reduction.md) is 54% tree-to-workdir including 28.8% attribute/filter work and 41.5% per-file patch/stat. Most of that is spent on the ~2,959 unchanged files, which an incremental session does not touch either unless it also stops hashing them. See finding G1. |

### 2.3 Recommended order for the new program design

1. WITHDRAWN. `_with_index` changes staged-deletion plus same-path recreation from `modified` to `deleted` and fails the pinned agentstudio-git test. Direct tree-to-worktree semantics stay. The per-file hash cost of a complete comparison is therefore inherent, and the incremental seed design is the lever.
2. Stop the second hash of every modified file (G13), then skip `git_patch_from_diff` for untracked and binary deltas or compute line stats lazily per demanded item (G2). The binary test must move ahead of patch generation.
3. Carry the changeset into the Review lane (`recordInvalidation` already receives it) and add a pathspec to the SDK diff request so a one-file refresh can diff only that path and merge into the retained comparison. Fallbacks the proposal lists (renames, git-internal changes, index changes, >N files, unknown paths) remain necessary. Rename detection is whole-diff by construction, so a pathspec diff must disable rename detection or accept that renames land only on the fallback path.
4. Stop advancing the construction epoch for changesets that the pane's own admission later classifies as no-impact. The epoch advance at FilesystemSource.swift:272 is unconditional.

A caller-owned "Review session" object in agentstudio-git is not needed for steps 1 to 4. The retained comparison already lives in the pane's committed publication; the missing pieces are the pathspec and the changeset plumbing.

## 3. Transport genericity

Routes `agentstudio://rpc/command|stream|content`, `BridgeProductSession` per pane, `BridgeProductProducerRegistry`, `BridgeProductMetadataApplicationRegistry` with typed applications (fileAnnotations, fileMetadata, reviewAnnotations, reviewMetadata), and `MetadataCatalogTransfer<Entry>` begin/window/commit. Nothing in the routes or the session knows about File or Review. Frame limits live in `BridgeProductSessionContract.swift` (128 KiB metadata frame, 256 KiB content frame, 64 queued frames / 4 MiB).

Genericity gaps worth naming in the new spec:

- The per-frame worker acknowledgement (`requiresWorkerObservation`) is a transport-level contract that every application pays. See G9.
- Annotation adapters are wired in `BridgePaneProductMetadataCoordinator+SubscriptionProducers.swift` per application rather than discovered from the registry. Adding a third application means editing the coordinator.

## 4. Findings

Severity: H = user-visible correctness or the dominant cost, M = measurable waste, L = hygiene.

| # | Sev | Finding | Anchor | Status |
| --- | --- | --- | --- | --- |
| G1 | H | `git_diff_tree_to_workdir` hashes every tracked file because tree iterator entries carry no stat data; `maybe_modified` sets `modified_uncertain` and `git_diff__oid_for_entry` loads filters, opens, hashes. `_with_index` uses the index stat cache. All three Review readers (`LibGit2DiffReader`, `LibGit2ContributionDiffReader:25`, `LibGit2DirectReviewComparisonReader:32`) go through this one call. No agentstudio-git test pins the no-index choice; the staged same-path recreation test (`GitReviewDataIntegrationTests.swift:387-402`) is a correctness assertion that `git_diff_merge` is designed to satisfy. | agentstudio-git `LibGit2DiffReader.swift:114-122`; libgit2 `diff_generate.c:894-926`, `iterator.c:1541` | Cost confirmed; the `_with_index` fix is WITHDRAWN. `git_diff__merge_like_cgit` (`diff_tform.c:76-77`) returns the tree-to-index delta whenever it is DELETED, so a staged deletion followed by same-path recreation reports `deleted`, while the pinned agentstudio-git test (`Tests/AgentStudioGitTests/Integration/GitReviewDataIntegrationTests.swift:387-402`) requires `.modified` with the recreated content hash. My earlier statement that no test pins direct semantics was wrong. The per-file hashing is inherent to direct tree-to-worktree semantics; the incremental design is the correct cure, which makes fallback frequency (V2) the cost that matters. |
| G2 | M | `files()` calls `git_patch_from_diff` + `git_patch_line_stats` for every delta including binary and untracked. Caveat for the fix: `isBinary(delta:)` at `LibGit2DiffReader.swift:239` reads `delta.flags` after `lineStats` ran, and libgit2 sets `GIT_DIFF_FLAG_BINARY` only inside patch generation (`patch_generate.c:57-63`). Skipping the patch call therefore also requires a different binary test (attribute or content sniff), otherwise `isBinary` silently breaks. | `LibGit2DiffReader.swift:184-213`, `:239` | Confirmed with caveat (verifier C2) |
| G3 | H | Annotation source refresh reads every `.available` descriptor path plus annotated paths through an inline `LibGit2AgentStudioGitLocalClient()`, bypassing `BridgeGitReadScheduler`, re-opening the repository per candidate. Over 256 candidates the whole session becomes `.unavailable`. | `Transport/WorktreeAnnotations/WorktreeAnnotationSourceCapture.swift:~520-560`; `AgentStudioGitWorktreeAnnotationSourceMaterialProvider.swift` | Confirmed (verifier C3). Repository is re-opened per candidate through `LibGit2ReviewSupport.withRepository`, up to 256 times, strictly sequentially. |
| G4 | H | Draft flush hot path: flush -> `.content` -> `applyCommittedChange` -> publish to all observers incl. the typing pane -> `sessionChanged` -> worker `#admitProjectionInvalidation` -> full projection query -> `captureProjection` (`loadSessionDetail` N+1 SQL, policy regex per message) -> `sourceResolver.refresh` (G3) -> `evaluatePlacements` -> record analysis JSON-encodes every message, entry init encodes again, batch delivery encodes again. | `WorktreeAnnotationServiceActor+MetadataPublication.swift`; `bridge-comm-worker-annotation-projection-query-controller.ts`; `BridgePaneProductWorktreeAnnotationProjectionSource.swift`; `WorktreeAnnotationSQLiteRepository+Loading.swift`; `BridgeProductWorktreeAnnotationProjectionRecordCursor.swift` | Confirmed and worse (verifier C4). Only panes that demand the session re-query, but each re-query costs up to 256 file reads with zero on-disk change, `4 + threads + messages` SQL statements per demanded session, and 4 full JSON encodes per message per cycle (`ProjectionContracts.swift:678-706` size-check encode, `RecordCursor.swift:375-398` built once for analysis at :226 and again for delivery at :322, each with its own `encodeAnnotationProjectionRecord`). |
| G5 | M | `projectionRevision` bumps on every store publish (`markRefreshing`, `apply`, `recordCommandOutcome`, `replaceOutputHistory`), and the effects hook re-annotates every CodeView item and bumps every item version, so unchanged items are pushed through `applyItemUpdate`. | `use-bridge-code-view-worktree-annotations.tsx`; `use-bridge-code-view-worktree-annotation-effects.ts`; `worktree-annotation-projection-store.ts` `#publish` | Confirmed (verifier C5). Pierre `syncItemRecord` re-syncs any item whose version changed, so the skip never fires; renders coalesce through one rAF so the waste is dirty-marking and resync, not N synchronous renders. Correctness gap: while composing, the guard hides every remote projection change until the composer closes, then one large re-annotate pass fires. |
| G6 | H | Placement correctness. `contextMatches` scans every role-compatible file in the material; on File the material is the pane's demanded descriptor set, so relocated vs outdated can flip as the user scrolls with no repository change. One oversized, binary, or unreadable candidate makes every thread `.unavailable`. | `Models/WorktreeAnnotations/WorktreeAnnotationSourceEvaluation.swift` `locatedPlacement`; `WorktreeAnnotationSourceCapture.swift` `reviewMaterial` | Confirmed (verifier C6). `locatedPlacement` at `:148-187`; `.unavailable` guards at `:128-130`, `:153-155`. |
| G7 | M | `executeOutputPreparation` runs `WorktreeAnnotationSourceEvaluator.evaluate` on up to 256 files x 1 MiB inside a `@MainActor` adapter method. | `WorktreeAnnotationTransportAdapter+Output.swift` | Confirmed (verifier C7). `evaluate` runs on MainActor at `+Output.swift:38-47`; `contextMatches` (`WorktreeAnnotationSourceEvaluation.swift:209-231`) is O(lines x excerptLines) per file. File reads in `createRoot` run on the `BridgePaneProductFileMetadataSource` actor, off-main. |
| G8 | M | Shared-locator Review content is hashed three times: `LibGit2ContentReader` SHA256, `+SharedContent.validate` git-blob-sha1, `BridgeReviewContentLoaderCache.validateResult` git-blob-sha1 again. Live locators twice. Annotation material re-SHA256s payload data instead of reading the `sha256:` prefix (`AgentStudioGitWorktreeAnnotationSourceMaterialProvider.swift:84-86`, working-tree candidates only). | `AgentStudioGitBridgeReviewDataClient+SharedContent.swift`; `BridgeReviewContentLoaderCache.swift` | Confirmed pass counts (verifier C8). Correction to my claim: this path is SHA-256 on every pass, since `LibGit2ContentReader` stamps `contentHashAlgorithm: "sha256"` (`:85`, `:107`) and the cache support branches on that field; git-blob-sha1 is used only on the fallback path. |
| G9 | M | Every frame whose receipt requires worker observation blocks the pump until the worker acknowledges. Catalog writer waits per begin/window/commit; projection page streaming waits per 128 KiB batch. Round trips scale with catalog size and page bytes. Worse than I stated: `requiresWorkerObservation` is not per frame kind, it is hardcoded `true` for every producer key (`Transport/BridgeProductProducerRegistryState.swift:17-19`), so every metadata and content frame is serialized behind a worker acknowledgement. Catalog round trips are `2 + windows` (the writer binary-searches the largest run fitting 128 KiB), projection pages are `ceil(bytes / 131072)`. | `BridgeProductSchemeAdapter.swift:431-467`; `BridgeProductMetadataCatalogWriter.swift:22-57`; `BridgePaneProductSchemeProvider+AnnotationProjection.swift:187-244` | Confirmed (verifier C9 + my read of the property) |
| G10 | L | PR1 program design says notifications are `snapshotRequired/sessionChanged/discoveryChanged/recoveryChanged` with no thread/message DTOs. Code publishes a full catalog on bootstrap and on every `.catalog` change. The 08-27 design describes the catalog. Docs disagree; the new spec should state the catalog contract once. | `BridgeProductWorktreeAnnotationMetadataEvent.swift`; `BridgePaneProductWorktreeAnnotationNotificationSource.swift` | Confirmed with one correction (verifier C10). PR1 `pr1-program-design.md:378-411` is stale for `.catalog`; the 08-27 design `:379-538` is the authority. The catalog is not discarded after membership checks: the worker catalog applicator uses `createdOrdinal`/`ordinal` for ordering and duplicate detection (`bridge-comm-worker-annotation-catalog-applicator.ts:167-222`). |
| G11 | H | Review refresh drops the changeset and rebuilds the full comparison; construction epoch is advanced unconditionally. See section 2. | Section 2 anchors | Confirmed by me |
| G13 | M | Every modified file is hashed twice during one comparison. libgit2 hashes it inside `maybe_modified` and stores the result in `delta.new_file.id`, but `diff_delta__from_two` (`diff_generate.c:270-282`) sets `GIT_DIFF_FLAG_VALID_ID` only when the workdir iterator entry itself carries a non-zero id, which it never does. `LibGit2DiffReader.contentHash` (`:244-264`) then sees no `VALID_ID` and calls `git_repository_hashfile`, which opens, filters, and hashes the same bytes again. Patch generation then reads the file a third time. Fix inside agentstudio-git: trust `delta.new_file.id` when non-zero even without `VALID_ID`, or read the blob once and derive both. | `diff_generate.c:270-282`, `:951-953`; `LibGit2DiffReader.swift:244-264` | Confirmed, with a limit: patch generation hashes the file a third time when `VALID_ID` is unset (`diff_file.c:433-436`). Trusting the nonzero OID in Swift removes only the second hash; the third can only be removed inside libgit2 (`maybe_modified` never sets `VALID_ID`), which is out of scope. |
| G14 | L | Annotation material candidates are read strictly sequentially (`for candidate in request.candidates { await client.content(...) }`), each opening the repository, and the binary and UTF-8 rejection happens after the full read and hash. Correction: oversize is rejected before reading, from file attributes or blob size (`LibGit2ContentReader.swift:77-79`, `:91-92`). | `AgentStudioGitWorktreeAnnotationSourceMaterialProvider.swift:52-100`, `:71-76` | Confirmed (verifier C2 additional) |
| G15 | M | `loadSessionDetail` is N+1: one SELECT per thread for messages and one SELECT per message for its draft (`WorktreeAnnotationSQLiteRepository+Loading.swift:439-471`, `:524-528`), and `WorktreeAnnotationMessagePolicy.validate` compiles three `NSRegularExpression` patterns per call (`WorktreeAnnotationMessagePolicy.swift:91-117`) for every saved and draft body on every reload. | as cited | Confirmed (verifier additional 9, 12) |
| G16 | L | `containsDuplicateCandidate` is O(n^2) over candidates (`AgentStudioGitWorktreeAnnotationSourceMaterialProvider.swift:104-121`) and provably a no-op on the File path where role, identity, and target are constant. Refresh candidates are the full demanded set, never narrowed to the session or thread being refreshed (`WorktreeAnnotationSourceCapture.swift:524-530`). `descriptor(for:)` re-resolves files even when the trigger was a draft-only edit. | as cited | Confirmed (verifier additional 6, 8, 13) |
| G12 | L | `LibGit2StatusReader.status` computes `shortstat` through `git_diff_tree_to_workdir_with_index` + `git_diff_get_stats` on every status call, even when the caller only wants entries. | agentstudio-git `LibGit2StatusReader.swift` | Read by me |

## 5. Inputs for the new spec and program design

- Name the Git comparison semantics once: working-tree delta including staged changes (PR0 R4). Then the libgit2 call follows (`_with_index`).
- Add pathspec to `GitDiffRequest`/`GitContributionDiffRequest` in agentstudio-git, with rename detection disabled on scoped calls.
- Define the Review refresh contract as: retained comparison + scoped delta merge, with the fallback list from the proposal. Carry the changeset through the Review lane.
- Define annotation source material as a demand-independent set: annotated paths plus their placement candidates, never "every descriptor the pane happens to have demanded". Placement must not depend on viewport.
- Make `unavailable` per-file, not per-session.
- Route annotation Git reads through `BridgeGitReadScheduler` like every other Bridge read.
- Make projection invalidation carry the changed session and thread so the worker can query a page, not the whole projection, and so the typing pane can ignore its own command-confirmed echo.
- Move `evaluate` off MainActor; the adapter should publish results only.
- Decide the acknowledgement granularity per application (catalog transfer can ack per commit, not per window). Today the flag is a constant `true`, so this is a transport contract decision, not a per-producer tweak.
- Load a session's messages and drafts in one query per session, cache the policy regexes, and encode each projection record once.
- Reading composing-pane semantics: decide whether remote changes must reach a pane while it composes (the current guard hides them).

Verifier items left unsettled from source: whether the producer-side page wait and the consumer-side pump wait are one observation event or two round trips; whether the `sessionChanged` notification frame itself blocks on observation; the exact vendored libgit2 revision versus the open-source checkout used for line numbers (treated as 1.9.4-equivalent).

## 6. Code review of the uncommitted working-tree diff

The `/code-review high` fork produced eight finder candidate lists and was stopped before its verification phase. I verified the recurring candidates against current source myself. Scope: the uncommitted comm-worker epoch change plus the Swift creation-time build removal.

| # | Sev | Verdict | Finding | Anchor |
| --- | --- | --- | --- | --- |
| R1 | M | Confirmed | Review "updating chrome" is skipped on metadata-stream failure. The consume catch and ended paths fire the null epoch callback before `#onReviewMetadataFailure`, and the chrome publisher returns null when the active Review epoch is null. The application-failure recovery path uses the opposite order, so the two failure paths disagree. | `bridge-comm-worker-product-controller.ts:552-557`, `:573-578`, `:589-590`; `bridge-comm-worker-runtime-protocol.ts:813-815`; `bridge-comm-worker-updating-chrome.ts:41-42` |
| R2 | M | Confirmed | `ensureReviewMetadata` bumps the transport epoch to N+1, and on subscribe failure reports the failure under N+1 without ever announcing N+1 through the epoch callback. Controller and scheduling authority disagree until the next successful subscribe. | `bridge-comm-worker-product-controller.ts:335-352` |
| R3 | M | Partial | `updateWorkerDerivationEpoch` wipes the latest demand request, scheduling store, and reset request on both the retire and admit edges, so `resume()` has nothing to replay after a reopen. Re-derivation then depends on the reopened subscription's first admitted snapshot scheduling a reset or demand execution through the post-commit effects. The finder claim that nothing re-subscribes until a fresh viewer-mode update is overstated: `ensureReviewMetadata` has eight call sites including demand updates. Whether the applicator always schedules post-commit work on a reopened snapshot is not settled here. | `bridge-comm-worker-review-demand-scheduling.ts:640-660`, `:611-625`; `bridge-comm-worker-command-handler.ts:209-235` |
| R4 | M | Confirmed | Five hand-copied retire blocks for the Review subscription (teardown, interest-update failure, consume catch, ended, application failure) with three variants of which fields they reset. One owned retire transition would remove the ordering defect in R1. | `bridge-comm-worker-product-controller.ts:306-311`, `:501-505`, `:552-556`, `:573-577`, `:590-603` |
| R5 | M | Confirmed | `updateGeneration(null)` publishes current active demand into scheduling, which rejects with a constructed Error because the epoch is null; the rejection is swallowed. Dead publication on every retire edge. | `bridge-comm-worker-review-demand-ledger.ts:292-308`; `bridge-comm-worker-review-demand-scheduling.ts:209-217` |
| R6 | M | Confirmed | The coordinator no longer schedules the initial Review build at pane creation. Initial construction now starts only from a committed viewer-mode update or a `background-warmup` intake-ready message, both web-originated, and the viewer-mode signal gives up after three attempts. A Review-first pane also loses the overlap between web load and the libgit2 comparison. | `WorkspaceSurfaceCoordinator+BridgeViewLifecycle.swift:51` (removed line); `BridgePaneController+Bootstrap.swift:90`, `:162-168`; `bridge-viewer-active-mode-signal.ts:22-30` |
| R7 | L | Confirmed | The doc comment on `loadInitialReviewPackageIfPossible` still promises the creation-time bootstrap that the diff removed. | `BridgePaneController+DiffCommands.swift:90-96` (working tree) |
| R8 | L | Confirmed | The `_error` parameter is used on the next line; the underscore is wrong. | `bridge-comm-worker-runtime-protocol.ts:813-814` |
| R9 | L | Noted | The controller file is past 900 lines and the scheduling unit test past 800 with a fourth copy of the same setup block. | `bridge-comm-worker-product-controller.ts`; `bridge-comm-worker-review-demand-scheduling.unit.test.ts:487` |

Not verified from the finder lists: the claim that a second application failure on the same publication leaves a retained Review with permanent placeholders (`shouldReopen` false at `:592`). The code path exists; whether a later demand update re-subscribes in practice depends on the demand-update call sites and was not traced.

## 7. Validation of the three-artifact design (2026-09-03 incremental review git refresh)

Artifacts read in full: requirements (171 lines), specification (274), program design (459). Overall: the observable model and the ownership split are right. Git combination stays in agentstudio-git, the seed is opaque, no path-level candidate is visible, and the fallback list is complete for change kinds. Four items need a change before planning, and two are decisions the design leaves implicit.

### 7.1 Facts the design states that I confirmed in code

| Design statement | Status |
| --- | --- |
| Review lane replaces the changeset with nil | Confirmed, `BridgePaneRefreshAdmissionCoordinator.swift:312-327` |
| Whole-worktree construction invalidation on every event | Confirmed, `WorkspaceSurfaceCoordinator+FilesystemSource.swift:272` |
| Pathless agentstudio-git request | Confirmed, `GitDiffRequest` has no pathspec |
| `GIT_DIFF_DISABLE_PATHSPEC_MATCH` makes the pathspec a literal pathlist on both iterators | Confirmed, libgit2 `diff_generate.c:1349-1353`; the pathlist walk descends parents so nested literal paths are reachable |
| Existing untracked, recurse-untracked, type-change, rename options unchanged | Confirmed in `LibGit2DiffReader.swift:154-178`; rename detection is `FIND_RENAMES` plus `FIND_FOR_UNTRACKED`, so a same-path modified row can never become a rename target and the same-path-only admission rule is sound |
| Coverage facts exist on the changeset | Confirmed, `PaneRuntimeEvent.swift:137-146` |

### 7.2 Must change before planning

**V1. "No scoped row removes the predecessor row" is unsafe as written (R-IRR-004 / Proportional calculation).** The design treats an empty scoped result for an affected path as a reversion to base and deletes the predecessor row. An empty result also occurs when the literal pathspec does not match Git's spelling of the path. Two macOS-specific ways that happens: case (APFS is case-insensitive, the diff is not; `GIT_DIFF_IGNORE_CASE` is not set, `diff_generate.c:1392`) and Unicode form (the workdir iterator precomposes names when `core.precomposeunicode` is set, `iterator.c:147-155`, while the filesystem actor's relative paths carry whatever FSEvents delivered, with no normalization in `FilesystemRootOwnership.route`). Outcome: a real modified row is silently deleted from the successor and the parity proof would not catch it unless the fixture has such a path. Fix: an affected path with a predecessor row and no scoped row must either be positively confirmed (path resolves in the index or base tree with a stat-clean or hash-equal match) or select complete fallback. Reversion to base is rare, so fallback is the cheaper rule.

**V2. Admission will rarely fire during builds (Review change scope).** The `.exactPaths` rule requires `suppressedIgnoredPathCount == 0`. That rule is necessary today because `FilesystemPathFilter.classify` marks a path `ignoredByPolicy` from the root `.gitignore` alone (`FilesystemPathFilter.swift:59-75`), without checking whether the path is tracked, so a suppressed path could be a tracked file. But any batch that contains `.build`, `node_modules`, or editor scratch churn then demotes to complete, which is the common case while a developer or agent is building. Either make suppression exact (suppress only paths that are both ignore-matched and absent from the index, and count tracked-but-ignore-matched paths separately) or accept and document that proportional refresh is effectively disabled during builds. This decision belongs in the requirements, not the plan.

**V3. WITHDRAWN.** The design's choice to keep the direct tree-to-worktree call is correct; `_with_index` breaks the pinned staged-deletion recreation semantics (see G1). What survives of V3: because the complete comparison cost is inherent, the admission rate (V2) decides whether this design pays off, and the design should carry an admission metric from day one.

**V4. Seed ownership is stated twice.** The calculation holder "owns the lifetime of one active seed" and shared construction "carries the opaque successor seed with the immutable template". The template is discarded on every construction-epoch advance (`BridgeWorktreeProductConstructionCoordinator.swift:102-108`), which happens on every filesystem event, so it cannot be the retention owner. Name the holder as the sole owner and make the template a pass-through.

### 7.3 Should be made explicit

**V5. Unchanged-load path.** `performReviewPackageRefresh` short-circuits when the load is unchanged on the same lineage (`isUnchangedSameLineageLoad`). State that the successor seed still replaces the active seed on that path, since the resolved OIDs are what the next attempt validates against.

**V6. Nested `.gitignore` files.** The filter loads only the root `.gitignore`, so a file ignored by a nested rule arrives as a projected path. The scoped diff returns no row for it and there is no predecessor row, so nothing happens. Harmless, but the design should say the admission rule does not depend on ignore-rule completeness.

**V7. Scoped line stats and binary test.** The scoped diff still runs `git_patch_from_diff` for the affected path, which is fine, but G2's caveat applies if the plan also tries to skip patch generation: the binary flag is only set during patch generation.

### 7.4 Requirements and spec, smaller notes

- R-IRR-003 lists "status-only notification" as non-exact. The code merges `latestFileStatus` into the same dirty fact; the classifier should read that field, not a separate flag.
- R-IRR-010 asks for "identical complete encoded metadata". Ordering is Swift `String <` after splice (`LibGit2DiffReader.swift:192`), which is deterministic but not byte order; the parity fixture should include paths that sort differently under the two orders so the proof exercises the comparator.
- U-IRR-007 bound: one active plus one candidate projection per calculation owner, roughly 927 rows each on the fixture. Fine. Multiple panes on one worktree multiply it per pane, which the design's "revisit" clause already covers.


## 8. Disposition validation and telemetry magnitudes (2026-09-03, later pass)

### 8.1 Dispositions from the design owner's review of this report

| Item | Their disposition | My check | Result |
| --- | --- | --- | --- |
| G1/V3 `_with_index` | Reject | `git_diff__merge_like_cgit` returns the tree-to-index delta whenever it is DELETED (`diff_tform.c:76-77`), so staged delete plus same-path recreate reports `deleted`; the pinned test at `GitReviewDataIntegrationTests.swift:387-402` requires `.modified`. | They are right. Withdrawn above. My "no test pins it" statement was wrong. |
| G13 double hash | Partial | Patch load hashes again when `VALID_ID` is unset (`diff_file.c:433-436`). Trusting the nonzero delta OID in Swift removes the second hash only; the third is libgit2-internal. | Agreed. |
| V1 empty scoped result | Accept, fallback | | Agreed. |
| V2 suppressed ignored | Owner decision, recommend conservative fallback plus admission metric | Telemetry below shows refresh cost equals initial cost today, so the admission rate is the whole win. | Agreed, and the metric is not optional. |
| V4, V5, V6 | Accept | | Agreed. |
| V7 | Already met | | Agreed. |
| G5 | Split: waste accepted, composing suppression is product behavior | | Agreed. |
| G9 commit-only ack | Reject as direct fix; needs replacement ordering/backpressure contract | | Agreed. It was a spec input, not a fix. |
| G12 status shortstat | Observation, not defect | | Agreed. |
| G14 oversize pre-check | Partial: size is rejected before read | `LibGit2ContentReader.swift:77-79`, `:91-92` check size from attributes or blob size before reading. | They are right; corrected above. Binary and UTF-8 checks still follow the read. |
| R6 creation-time build removal | Reject: implements active-first design | Design rationale accepted. Residual: the three-attempt cap in `bridge-viewer-active-mode-signal.ts:22-30` is a liveness edge with no failing journey yet. | Agreed, with the residual noted. |
| R3 | Unverified | | Agreed. |
| R9 | Reject for this diff | | Agreed. |

### 8.2 Magnitudes from the shared OTel stack (VictoriaLogs, last 30 days)

Caveat: every record carries a proof marker or Vite scenario. This is debug-config and test-fixture data, not production usage. Distributions are still useful for ratios.

Swift package build, `performance.bridge.swift.package_build`, debug config:

| Reason | n (30d) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- |
| filesystem_refresh | 207 | 948 | 8132 | 24544 |
| initial_intake | 138 | 3003 | 13734 | 17727 |
| filesystem_refresh, last 7d | 151 | 5071 | 8132 | 24544 |
| initial_intake, last 7d | 105 | 4986 | 14610 | 17727 |

In the last week a refresh build costs the same as an initial build at p50. Delta build (p50 0.05 ms) and content register (p50 0.02 ms) are negligible, so the package build is the Git comparison plus package assembly. This is the design's premise, measured.

Construction coordinator, `performance.bridge.worktree_product_construction`: 10,706 review invalidations against 271 review builds in 30 days. The epoch advances roughly forty times per build.

Swift annotation lifecycle by operation id: projection query p50 2 ms, p95 16 ms, max 129 ms; native annotation work p50 0.2 ms; content transfer p50 1.4 ms, p95 34 ms. The native side of the G4 chain is cheap on the fixtures used so far, which do not have hundreds of demanded descriptors. The chain cost (G3, G4) is proportional to demanded descriptor count and session size, neither of which the fixtures stress.

Web annotation lifecycle (Vite scenarios): review-viewer projection query, worker application, and convergence sit at p50 576 ms and p95 900 ms with a tight cluster, which looks like a scenario-imposed delay rather than real work; file-viewer phases are at 0 ms. Operation ids repeat across runs, so maxima are join artifacts. Not usable as magnitudes.

Web invalidation-to-query ratio: review viewer 5,812 invalidations to 4,446 projection queries (76%); file viewer 5,966 to 1,685 (28%). Most review-viewer invalidations become a full projection query, which is the G4 amplification path.

## 9. Does the front end redo content work for unchanged items? (2026-09-03, later pass)

Question validated: after a one-file Review refresh, do unchanged items avoid re-render and content work?

### 9.1 What the code does

| Layer | Unchanged item on a one-file refresh | Anchor |
| --- | --- | --- |
| Native delta builder | Only items whose descriptor differs are upserted; unchanged items get no operation. Handle ids are `SHA256(endpointId:itemId:role:contentHash)` with stable endpoint ids for workspace panes, and `semanticItemVersion` is a hash of semantic fields, not the generation. | `BridgePaneProductReviewMetadataSource.swift:408-460`; `BridgeProductContentHandleIdentity.swift:5-14`; `BridgePaneController+ReviewEndpointSelection.swift:6-24`; `BridgeSharedReviewPackageTemplate+Binding.swift:133-163` |
| Delta admission | A delta is admitted only when `next.revision > current.revision` and query, endpoints, origin, and label are equal. The change index gives the refreshed package a higher revision only when its review generation equals the current one. | `BridgePaneProductReviewMetadataSource.swift:497-507`; `BridgeChangeIndex.swift:93-134` |
| Refresh generation | On a workspace source with a contribution target, every refresh allocates a new generation. Without a contribution target the current generation is reused. | `BridgePaneController+DiffCommands.swift:820-840` |
| Result | Contribution-target Reviews (the default production shape) never publish a delta. Every refresh publishes reset + sourceAccepted + every metadata window, and the worker clears and rebuilds its projection (`#resetProjection`). | as above; `bridge-comm-worker-review-metadata-projection.ts:512-540` |
| Main thread | Render copies survive a reset when render identity matches: same item id, change kind, class, language, roles, and per-role content digest plus semantic document revision. Everything is invalidated only when the worker derivation epoch is replaced (re-subscribe), not on an ordinary reset. | `bridge-main-review-display-state.ts:409-450`; `bridge-main-render-snapshot-store.ts:631-650` |
| Worker content | The worker's content-source map is cleared on reset and re-registered from the windows. Whether fetched bytes are reused by digest without a transport fetch was asserted by a finder ("body registry") and not verified here. | `bridge-comm-worker-review-metadata-projection.ts:515-516` |
| Annotation overlay | Each commit mints a new publication id; the annotation identity carries publication id and revision; the projection controller treats an identity change as a presentation-authority change and re-queries the full projection; the store bumps `presentationRevision`; the effects hook re-annotates every CodeView item and bumps every version; Pierre resyncs every item. | `BridgeReviewPublicationCoordinator.swift:355`; `bridge-product-worktree-annotation-projection-query-contracts.ts:18-26`; `bridge-comm-worker-annotation-projection-query-controller.ts:163-195`; G5 anchors |

### 9.2 Telemetry

`performance.bridge.swift.review_metadata_publication` completed, last 30 days, 421 publications: emitted-event counts are 9 (175), 28 (72), 3 (53), 0 (31), 10 (26), 5 (20), 2 (19), 4 (14), and a tail. A delta publication emits exactly one event. There are no single-event publications. The zero-event rows are the unchanged short-circuit. Every changed refresh in the recorded runs was a full reset.

### 9.3 Answer

Metadata and content layers are designed to avoid re-sending or re-fetching unchanged items, and the main thread keeps render copies by digest. But the default production path (contribution target) defeats the delta at the generation gate, so today every refresh re-sends the whole catalog and rebuilds the worker projection, and the annotation overlay re-touches every item through Pierre. The other agent's diagram describes the non-contribution path and the intended design, not what the contribution path does now. The incremental Git seed design does not change this; it ends at the Git boundary, as its own text says.

Open item for the design owner: whether a proportional refresh should also keep the review generation so the delta path becomes reachable on the contribution path, or whether the generation bump is load-bearing for currentness and the publication side needs its own change.
