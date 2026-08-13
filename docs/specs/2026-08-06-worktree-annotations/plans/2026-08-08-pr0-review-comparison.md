> **SUPERSEDED — DO NOT USE FOR COMPARISON-TARGET DISCOVERY/LOADING/CATALOG UI.** Use [`docs/specs/2026-08-10-bridge-review-comparison-target-loading/`](../../2026-08-10-bridge-review-comparison-target-loading/) for that work. This older plan remains historical/source context only.

# PR0 Review Comparison — Implementation Plan

Planning result: `draft`

## Governing authority

- Requirements: [`../pr0-user-requirements.md`](../pr0-user-requirements.md)
- Specification: [`../pr0-specification.md`](../pr0-specification.md)
- Program Design: [`../pr0-program-design.md`](../pr0-program-design.md)
- Current three-artifact review invocation:
  `pr0-legacy-cutover-three-artifact-20260808-sol`
- Current three-artifact review result:
  `pr0-legacy-cutover-three-artifact-20260808-sol/receipt-1`, candidate
  `READY`, parent-verified and accepted for planning
- Planned branch and HEAD: `review-comments` at
  `cc13787e8ff01c223dc022e30a73017a56a86fdb`
- `origin/main` at planning time: the same commit; no integration operation is
  pending.
- Planned `agentstudio-git` worktree:
  `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git.pr0-review-contribution`
  on branch `pr0-review-contribution` at
  `fdeb5b3e822f49e97b44df6d9267565d8c353f7d`.
- `agentstudio-git` `origin/main` and the selected dependency worktree's merge
  base with `origin/main` were that same commit at planning time. The generic
  `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git` checkout is
  not an S1 write surface because it is on an older unrelated branch.

## Goal and boundary

Implement one trustworthy living comparison for Review View:

```text
repository-designated integration branch or reviewer-selected target
                              │
                              ▼
              unique shared-history base
                              │
                              ▼
       committed + staged + unstaged + untracked worktree result
                              │
                              ▼
       immutable origin and clear one-row Review chrome
```

The reviewer can use `Compare to` to select a local branch,
remote-tracking branch, or Git ref. Stacked work uses that same explicit
selection; PR0 does not infer a stack parent. Narrow staged-only and
unstaged-only comparisons retain their current meanings.

Durable authority remains the symbolic comparison intent inside the existing
Bridge pane payload in `core.sqlite`. `local.sqlite` remains only the companion
opened by the production datastore composition. Calculated OIDs, file sets,
snapshots, movement summaries, and menu state are not persisted.

This plan excludes annotations, Markdown/Mermaid work, comment delivery,
guided review, comparison history, a frozen review lifecycle, new services,
watchers, caches, databases/tables, IPC systems, authentication/security
systems, generalized host frameworks, and production App boot in the focused
Debug server.

## Current repository evidence

- `BridgePaneState` persists `WorkspaceBaseline` through the pane payload; it
  has no comparison-intent type or provenance for legacy automatic defaults.
- `WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift` currently derives a
  default from the canonical main-worktree checkout, uses `ref("HEAD")` as a
  fallback, and hardcodes `main` for File View.
- `BridgePaneController` currently captures an immutable pane state, directly
  compares a resolved target tip to the working tree, and replays resolved
  endpoints during catch-up refresh.
- Review publication already has generation, reservation, commit, and content
  identity owners; BridgeWeb already retains an active predecessor while a
  candidate lineage is pending.
- The Bridge product-call and product-metadata transports already provide the
  two directions PR0 needs.
- The focused development server already loads `AgentStudioBridge`, which
  depends on `AgentStudioCore`, but currently invents pane identity and treats
  `--worktree` plus `--base` as authority.
- `WorkspaceSQLiteDatastoreFactory`, `CoreAtoms`, `WorkspaceStore`, and
  `WorkspaceStore.flushAsync()` already provide the production persistence
  path required by Debug.
- BridgeWeb already owns the one-row 36px header and shadcn-style dropdown,
  input, button, tooltip, and menu primitives.
- Agent Studio pins `agentstudio-git` in both `Package.swift` and
  `Package.resolved` at `fdeb5b3e822f49e97b44df6d9267565d8c353f7d`.
- The pinned Git package has branch, revision, diff, and content seams but no
  default designation or correlated contribution operation. Its bundled
  libgit2 exposes symbolic-reference lookup and all-best-merge-base APIs.

## Slice graph

```text
S1 agentstudio-git contracts + native reads ──────────────┐
                                                          │
S2 pane intent + atomic Core mutations + codec cutover ───┼─► S3
                                                          │
                                                          ▼
                    S3 native contribution/origin/controller integration
                         │                    │
                         │                    └──────────────► S6 invalidation
                         ▼
                    S4 transport/schema cutover
                         │
                         ├──────────────► S5 Review header UX
                         │
                         └──────────────► S7 durable Debug + Vite restart

S3 + S4 + S5 + S6 + S7 ──────────────────────────────────► S8 packaged proof
S1..S8 ───────────────────────────────────────────────────► S9 full gates/PR
```

`S1` and `S2` are advisory-parallel because they modify different
repositories and neither consumes the other's source. All other arrows are
required dependencies. The executor may serialize everything.

## Proof-bearing slices

### S1 — Add the two bounded Git capabilities first

Repository:
`/Users/shravansunder/Documents/dev/project-dev/agentstudio-git.pr0-review-contribution`

Source preflight:

- Before the first edit, require branch `pr0-review-contribution`, clean status,
  HEAD `fdeb5b3e822f49e97b44df6d9267565d8c353f7d`, local
  `refs/remotes/origin/main` at that same revision, and live
  `git ls-remote origin refs/heads/main` at that same revision. The merge base
  with `origin/main` must also equal that revision.
- Stop for owner-directed dependency integration if those facts no longer
  hold. Do not switch to the stale generic checkout or silently merge/rebase.

Write surfaces:

- `Sources/AgentStudioGitContracts/AgentStudioGitSDK.swift`
- adjacent Git diff/default DTO contracts under
  `Sources/AgentStudioGitContracts/`
- `Sources/AgentStudioGitLocal/LibGit2AgentStudioGitLocalClient.swift`
- focused readers/helpers under `Sources/AgentStudioGitLocal/Status/` and
  `Sources/AgentStudioGitLocal/Review/`
- focused Swift Testing coverage under `Tests/AgentStudioGitTests/`

Behavior:

1. Add a local-default read that looks up symbolic
   `refs/remotes/origin/HEAD`, accepts only
   `refs/remotes/origin/<branch>`, and returns the matching resolvable local
   `refs/heads/<branch>` name.
2. Return no designation for absent, direct, malformed, or missing-local-branch
   cases. Do not fetch or fall back to `main`, `master`, checkout, upstream, or
   `HEAD`.
3. Add one correlated contribution read over one repository handle: resolve
   selected target and reviewed worktree HEAD, obtain all best merge bases,
   require exactly one, and produce base-to-working-tree diff plus captured
   target/HEAD/base identities.
4. Return typed failures for unresolved target, missing/unborn HEAD, missing
   objects, no shared history, and multiple best bases. Return no partial
   successful snapshot.

Red/green proof:

- First add tests for symbolic `origin/HEAD`, malformed/direct/absent
  designation, symbolic `origin/HEAD` whose same-name local branch is missing,
  local commits beyond the remote-tracking tip, unique/no/multiple best bases,
  target-only advance, reviewed-branch merge, reviewed-branch rebase, target
  containing reviewed HEAD, committed/staged/unstaged/untracked content retained
  across those history shapes, unresolved target, unborn/missing HEAD, missing
  required objects, rename/delete/binary cases, and Codable round trips. Every
  failure case returns no partial snapshot.
- Run the focused package tests during development using the repo's established
  Swift Testing filter support in `scripts/run-swift-test-suites.sh`.
- Completion gate in the dependency repository: `mise run check`.

Publication gate:

- Review the exact dependency diff, run `mise run check`, intentionally commit
  and push the bounded change, and open/update its non-draft PR before Agent
  Studio consumes it.
- Require passing dependency checks, no unresolved actionable review threads,
  and mergeable state at the current dependency commit; record the PR identity
  and exact remotely reachable commit for S3. Do not pin an unpushed local-only
  object and do not merge without separate authorization.

Stop/replan if libgit2 cannot return all best bases or the existing executor
cannot keep the correlated read off `MainActor` without a new ownership model.

### S2 — Cut pane persistence to one comparison intent

Write surfaces:

- `Sources/AgentStudio/Core/Models/BridgePaneState.swift`
- `WorkspacePaneGraphAtom.swift` and `WorkspacePaneAtom.swift`
- existing Bridge-pane codec/persistence tests, especially
  `BridgePaneStateTests.swift` and file-backed workspace persistence tests
- `Tests/AgentStudioTests/Core/Stores/WorkspaceComparisonIntentProcessRestartTests.swift`
- `scripts/verify-workspace-comparison-intent-restart.sh`
- the three App pane-creation paths in
  `WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift` and
  `WorkspaceSurfaceCoordinator+ZoomCompanion.swift`

Behavior:

1. Replace `WorkspaceBaseline` runtime authority with a discriminated intent:
   active `contribution | stagedOnly | unstagedOnly` plus an optional retained
   symbolic contribution target.
2. Add the typed pane-state mutation and one atomic
   set-initial-contribution-target-if-absent mutation on the existing
   non-suspending `MainActor` pane graph; expose both through the existing pane
   facade.
3. Make Review, File View, and Zoom-companion pane creation start with no
   fabricated target.
4. Decode legacy explicit branch/origin/non-`HEAD` ref and `HEAD~1` meanings as
   retained explicit targets; decode legacy `localDefaultBranch` and
   `ref("HEAD")` as absent target intent; preserve staged/unstaged narrow kinds.
5. Emit only the new payload shape. Add no SQL table or migration.

Red/green proof:

- Codec round trips and hard-cut legacy decode table.
- Explicit race test: reviewer target commits before a late automatic default;
  the atomic mutation must return the reviewer target unchanged.
- File-backed `core.sqlite` restart proves symbolic intent restores and no
  calculated revision/snapshot is stored.
- Add one bounded proof-only script that creates an isolated root and invokes
  two separately launched filtered Swift test processes. Process A commits
  contribution intent for a fixed test pane, reports
  `flushAsync() == .persisted`, and exits normally. Only after A terminates,
  process B opens the same root and proves the exact pane UUID and symbolic
  intent restore while no calculated target, HEAD, base, or snapshot origin was
  persisted. The script records both PIDs and fails on forced/abnormal exit.
  Run it as `bash scripts/verify-workspace-comparison-intent-restart.sh`.
- Keep this Core-only receipt independent from the Debug + Vite restart. It may
  use the existing file-backed workspace fixture and production datastore
  composition, but it must not start Bridge, HTTP, Vite, or the packaged App.
- Legacy hotfix checkout value with designated `master`, legacy literal `main`,
  and missing designation all reach the intended guarded-default or attention
  behavior once S3 is integrated.
- Contribution → narrow → contribution retains the explicit target across
  persistence and restore. The no-retained-target path returns through guarded
  designation lookup or attention. Narrow origins contain neither target nor
  contribution-base identity.

Integration gate S2→S3: the controller must consume and return the canonical
pane intent; no second writable `reviewBase` or target field may survive.

### S3 — Build and publish truthful native contribution snapshots

Write surfaces:

- `Package.swift`, then the generated `Package.resolved`
- `AgentStudioGitBridgeReviewDataClient.swift` and the existing Review source
  provider boundary
- `BridgeReviewPipeline`, `BridgeReviewPackage`, package builders, content
  loaders, and metadata source contracts
- `BridgePaneController` diff/refresh/publication files
- `WorkspaceSurfaceCoordinator+BridgeReviewSourceProvider.swift` and controller
  composition
- existing Swift contract, pipeline, real-Git, controller, publication, and
  WebKit tests

Behavior:

1. Pin the exact remotely reachable S1 revision in `Package.swift` and resolve
   `Package.resolved`; update `AgentStudioGitDependencyTests.swift` to the same
   exact revision and keep that three-owner equality authoritative.
2. Map the new Git DTOs into one Bridge-owned pure builder:
   committed intent + captured contribution + subject label → resolved pipeline
   request + immutable origin. Production controller and Debug host share only
   this mapping, not a host framework.
3. Keep `BridgeReviewPipeline` as the sole assembler. Contribution uses the
   prepared correlated result once; narrow comparisons retain their existing
   endpoint diff path.
4. Add discriminated comparison origin and optional reviewed-subject label to
   package/reset/snapshot contracts. Origin includes symbolic target, resolved
   target, reviewed HEAD, unique base, endpoint roles, snapshot identity, and
   existing content handles.
5. On the existing initial Review-package-load trigger, ask the existing Git
   provider for the designation only while target intent is absent. Carry
   generation/admission, then use S2's atomic conditional Core mutation.
6. Adopt only the canonical committed intent, advance generation for every
   intent change/fresh contribution attempt, capture fresh Git truth, and check
   generation after package construction and immediately before the existing
   synchronous publication commit.
7. Remove direct target-tip contribution construction, contribution endpoint
   replay, and unresolved-`HEAD`→unstaged fallback.

Red/green proof:

- Adapter contract tests plus temporary real-Git controller/pipeline tests for
  target-only movement exclusion and complete dirty state.
- Package/metadata Codable and fixture tests for every origin variant and
  invalid combination.
- Default-designation tests across Review, File View→Review, Zoom companion,
  late result, missing/malformed designation, symbolic remote designation with
  no same-name local branch, and legacy cutover. The missing-local-branch case
  returns no designation and presents attention without a false default.
- Generation/interleaving tests for A→B target races and invalidation after
  capture/lease but before commit.
- Real-repository contribution cases for merge, rebase, and target containing
  reviewed HEAD, each retaining staged, unstaged, and untracked state.
- Real-repository failure cases for unresolved target, unrelated history,
  multiple best bases, unborn/missing reviewed HEAD, and missing required
  objects. Adapter/controller mapping proves none publishes a current snapshot.
- Transition tests for retained-target contribution → narrow → contribution,
  the no-retained-target guarded default/attention path, and target-free narrow
  origins.
- Successor-publication tests where only file content changes and where only
  file membership/path-side identity changes. Each publishes a distinct
  successor snapshot and leaves the predecessor immutable.
- Real-Git controller/publication transitions for target-only movement,
  reviewed-HEAD movement, contribution-base movement, and combined movement.
  Each advances snapshot identity, retains the immutable visible predecessor
  while pending, and derives the admitted successor's movement explanation from
  that predecessor.
- Pin proof: `AgentStudioGitDependencyTests` plus SwiftPM resolution/build.

Integration gate: a real temporary repository must travel from committed pane
intent through the pinned Git implementation, pipeline, publication, and
package read-back with one matching origin before transport/UI work is treated
as integrated.

### S4 — Cut both existing Bridge transports to comparison-aware contracts

Write surfaces:

- Swift `BridgeProductStreamFrame`, product-session/control/scheme contracts,
  committed-call target, presentation snapshot, metadata codecs, and corpora
- BridgeWeb `bridge-product-call-contracts.ts`, worker RPC/control/routing,
  `bridge-product-session-contracts.ts`, pane-presentation projection, Review
  metadata projection/transaction/display contracts, review-package schema,
  fixtures, and exhaustive contract tests

Behavior:

1. Add only `review.comparison.update` to the existing committed product-call
   path. Acknowledgement leaves only after Core mutation and controller adoption
   complete; errors cannot acknowledge an unapplied intent.
2. Cut `activityRevision` to one `presentationRevision` and add the optional
   Review comparison slice: canonical active intent, attempt status, and exact
   displayed snapshot identity.
3. Carry immutable comparison origin and subject through snapshot/reset and
   worker projection. Stop fabricating `Base`, `Head`, or presentation-only
   endpoint identity in React.
4. Preserve the currently displayed predecessor as stale while a successor is
   pending; never relabel it with the requested target.

Red/green proof:

- Swift/TypeScript schema, codec, corpus, exhaustive-switch, committed-effect
  ordering, invalid-request, worker-routing, and projection tests.
- Transport fixtures cover the content-only and membership/path-side-only
  successor cases with distinct snapshot identities and immutable predecessor
  payloads.
- `scripts/bridge-web-sync-fixtures.sh --fix` only when source fixtures change;
  `mise run bridge-web-sync-fixtures` must then be clean.
- Focused gates: `mise run test:bridge-web:unit`,
  `mise run test:bridge-web:integration`, and matching filtered Swift tests.

### S5 — Add the one-row `Compare to` experience

Before edits, apply the repository's `agentstudio-bridgeweb-react-ui` skill and
reuse existing owned primitives and Agent Studio tokens.

Write surfaces:

- one App-owned comparison-control composition under `BridgeWeb/src/app/`
- `bridge-app-review-viewer-mode.tsx`, presentation adapter, render-snapshot
  controller, and Review shell title
- owned UI primitives only if an exact missing primitive is proven
- unit, Browser Mode, integration, accessibility, and Vite E2E tests

Behavior:

1. Keep the existing 36px single header row:
   `[Files | Review] [Compare to: target ▾] [View settings]`.
2. Show `<reviewed subject> changes`, falling back to `Current worktree`, and
   retain the selected file suffix.
3. The closed control shows `Compare to: <target>`, `Choose target`,
   `Staged only`, or `Unstaged only` as applicable. Narrow modes never display
   the retained contribution target.
4. The menu accepts a bounded typed ref and Apply action; it shows current exact
   target/base revisions, the shared-history explanation, pending/current/
   stale/unavailable meaning, and choose/retry actions.
5. Use keyboard/focus semantics and a stable accessible description available
   while closed; hover/title is not the sole explanation.
6. Derive the successor-only movement summary from adjacent immutable origins:
   target moved, base unchanged; base moved; both moved; or no claim without a
   matching predecessor. Keep it transient.

Red/green proof:

- Add focused control Browser Mode tests for keyboard input, arbitrary ref,
  accessibility, all comparison states, movement variants, and 24px control
  scale.
- Add a Vite product fixture whose default target is the designated integration
  branch while the reviewed branch is stacked on another local branch. Through
  the actual `Compare to` control, select that stack parent and prove the
  published projection and origin change from the default to the explicit
  stack target; no ancestry/upstream inference may satisfy the journey.
- Extend header geometry proof for one 36px non-overlapping row.
- Update Review shell/title and stale predecessor tests.
- Extend the real product-provider/worker/DOM Vite E2E journey.
- Run `mise run test:bridge-web` and `mise run bridge-web-build`.

Manual gate: browser screenshot/interaction proof must show the one-row header,
menu facts, keyboard use, pending/stale/unavailable/current states, and no
`Head vs Base`, `Default`, `Contribution`, `three-dot`, or `merge base` as the
normal user-facing label.

### S6 — Re-resolve living targets on the right invalidations

Write surfaces:

- `WorkspaceSurfaceCoordinator+FilesystemSource.swift`
- `BridgePaneController+RefreshAdmission.swift` and related controller refresh
  files
- existing filesystem/coordinator/controller integration tests

Behavior:

1. Ordinary file/status changes remain exact-worktree scoped.
2. Git-internal or suppressed-Git-internal changes additionally route to active
   contribution panes in the same repository.
3. Relax controller exact-worktree admission only for that Git-internal +
   contribution case. Narrow modes remain exact-worktree scoped.
4. Immediately advance generation and publish pending before catch-up. Fresh
   contribution capture replaces endpoint replay; existing per-pane coalescing
   remains the only scheduler.

Red/green proof:

- Same-repository worktree A Git-internal event refreshes contribution pane B.
- The same event does not widen a narrow pane; ordinary file changes do not
  cross worktrees.
- Duplicate invalidations coalesce; already-leased predecessors cannot commit.

### S7 — Make focused Debug prove production durability

Write surfaces:

- `Package.swift`
- `AgentStudioBridgeDevelopmentServerMain.swift`,
  `BridgeDevelopmentServerConfiguration.swift`, and existing HTTP application
- `BridgeDevelopmentProductContracts.swift` and
  `BridgeDevelopmentProductHost.swift`
- `BridgeWeb/scripts/dev-server/bridge-development-server-process.ts` and its
  unit tests
- every existing BridgeWeb dev-server caller/fixture that supplies
  `worktreeRoot` plus `baseRef`, including the product E2E fixture and real
  router regression path
- Debug server/host tests and file-backed Core persistence integration tests

Behavior:

1. Add `AgentStudioCore` as a direct dependency of the existing
   `AgentStudioBridgeDevelopmentServer` executable target. Do not add a
   dependency on the `AgentStudio` executable or unrelated Feature targets.
2. The Vite process owner supplies an exclusive isolated data root and exact
   pane UUID. Worktree/initial target are seed inputs only for a missing fixture
   pane.
3. The server composes `CoreAtoms`, `WorkspaceSQLiteDatastoreFactory` over that
   root's `core.sqlite` and `local.sqlite`, and `WorkspaceStore`; it prepares,
   loads, and requires the exact restored Bridge pane.
4. Hard-cut `BridgeDevelopmentProductSource`, executable configuration, and all
   TypeScript process-owner callers from writable `reviewBase` authority to the
   isolated data-root and exact-pane seed/restore contract. Replace synthetic
   identity with restored Core topology and intent. Keep the existing
   `BridgeDevelopmentProductHost`, product session, Git adapter, pipeline,
   publication, and Hummingbird carrier.
5. Reuse S3's pure resolved-contribution mapping and the same typed committed
   Core effect. Do not instantiate the WebKit-owning controller.
6. On controlled process-A shutdown, require
   `WorkspaceStore.flushAsync() == persisted`; a failed outcome fails the run.
7. Restart process B with the same root/pane, freshly resolve changed Git truth,
   and publish a new origin. Only symbolic intent crosses the restart.

Red/green proof:

- Wrong, missing, and non-Bridge pane cases fail clearly.
- The Vite process owner creates one harness-unique root and never overlaps two
  server processes on it. Process B may reuse it only after A has exited. PR0
  adds no arbitrary shared-root detector, process lock, or lifecycle owner.
- File-backed Core reopen restores exact symbolic intent.
- Extend the existing
  `BridgeWeb/tests/e2e/bridge-viewer-vite-product.e2e.test.tsx` fixture and Vite
  product process-owner seam with the cross-process journey: browser commits in
  A, the harness observes a graceful process-A exit and persisted flush, mutates
  target history, starts B with the identical isolated root and pane UUID, and
  DOM/package read-back shows a freshly resolved target/base/origin. Run the
  exact journey with `mise run test:bridge-web:e2e`.
- The restart receipt reports process-A PID, graceful exit without forced
  termination, `.persisted` flush outcome, process-B PID, identical isolated
  root and pane UUID, restored symbolic intent, predecessor origin, and newly
  captured successor origin.
- Build the executable with `mise run build-bridge-development-server`; run its
  focused Swift coverage with
  `mise run test:swift -- --filter "BridgeDevelopmentHTTPRoutingTests"`, then
  run the Vite E2E command above.
- Static dependency proof forbids `AgentStudio` executable, packaged resources,
  Terminal/Ghostty, direct SQL, Debug repository/facade, and generalized host
  framework.

Stop on a design break if existing Core + Bridge composition cannot support
this bounded host. Do not invent a new host system to force the slice through.

### S8 — Extend the existing packaged production journey

Write surfaces:

- `scripts/run-bridge-packaged-product-journey.sh`
- `scripts/verify-bridge-packaged-product-journey.sh`
- `BridgePackagedProductJourneyScriptTests.swift`
- only the existing semantic IPC/read-back surfaces required by that harness

Behavior and proof:

1. Reuse the existing packaged candidate, LaunchServices, authenticated
   semantic control, real Git fixture, package/render read-back, observability,
   and PID-targeted Peekaboo paths.
2. Drive the actual one-row target control through the production
   controller→coordinator→pane graph path.
3. Verify current package/render origin, inspect the isolated candidate's
   `core.sqlite` for symbolic intent, and prove target/base refresh after Git
   movement.
4. Capture visual/keyboard evidence for target selection, narrow modes,
   pending/current/stale/unavailable, exact facts, and one-row layout.
5. Keep Core restart, Debug+Vite restart, and packaged production as three
   non-substitutable receipts. No release/tag proof is required.

Commands:

```text
mise run observability:up
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

### S9 — Full quality, review, and PR readiness

Focused proof before the aggregate:

```text
agentstudio-git: mise run check
Agent Studio:    mise run lint
Agent Studio:    mise run test:architecture
Agent Studio:    mise run test:bridge-web
Agent Studio:    mise run bridge-web-build
Agent Studio:    mise run test:swift
Agent Studio:    git diff --check
```

Required aggregate gate from the Agent Studio repository root:

```text
mise run test
```

Then rerun the three runtime receipts from S2/S7/S8 on the exact candidate
HEAD. Report commands, exit codes, test counts where emitted, process identities,
and observed behavior separately; no one gate substitutes for another.

Obtain fresh independent implementation reviews from OpenAI Sol xhigh and
Claude Opus 5 xhigh against the exact diff and proof receipts. Parent-verify
every candidate finding, remediate only accepted in-scope findings, rerun
affected proof and the aggregate gate, and refresh affected review coverage.

Finally, intentionally stage only PR0 files, commit, push `review-comments`,
open/update a non-draft Agent Studio PR, and use the repository PR wrap-up flow
to verify current HEAD, checks, comments, review threads, mergeability, and the
remotely reachable dependency revision. Do not merge without separate owner
authorization.

## Obligation → slice → proof map

| Obligation | Slices | Proof |
| --- | --- | --- |
| P0-R1 designated default or attention | S1, S2, S3 | designation fixtures; all pane entry paths; late-default race; legacy cutover; no-retained-target restore |
| P0-R2 visible/changeable comparison | S2, S4, S5 | committed-effect ordering; target input; retained-target narrow-mode restore; one-row/accessibility/manual proof |
| P0-R3 contribution from unique shared history | S1, S3 | real Git unique/no/multiple-base, merge, rebase, and target-contains-HEAD tests; origin read-back |
| P0-R4 complete current worktree | S1, S3 | committed/staged/unstaged/untracked state across history shapes; rename/delete/binary fixtures |
| P0-R5 moving target/history | S3, S4, S5, S6 | fresh capture; content-only and membership/path-side successor identity/immutability; cross-worktree Git invalidation; successor movement UI |
| P0-R6 honest failure and races | S1, S3, S4, S5, S6 | typed failures; generation races; stale/unavailable presentation |
| P0-R7 immutable correlation | S3, S4 | package/metadata/fixture contracts; content and membership/path-side identities; immutable predecessors; production/Debug mapping equality |
| P0-R8 durable intent, fresh truth | S2, S3, S7, S8 | named file-backed Core restart; retained/no-retained target transitions; legacy codec; named Debug process restart; packaged SQLite/package proof |

## False-green risks

- A Git unit test over a helper cannot replace temporary real-repository
  contribution proof.
- A Bridge fake cannot prove the pinned external implementation or production
  adapter mapping.
- A successful Core mutation without a successful `flushAsync()` cannot prove
  cross-process durability.
- A Debug HTTP journey cannot prove packaged WebKit/App composition.
- A packaged screenshot cannot prove stored symbolic intent or fresh origin.
- A generic full-suite green cannot replace accessible one-row UI interaction
  or the three distinct runtime receipts.
- A pinned local commit that is not remotely reachable cannot make the Agent
  Studio PR merge-ready.

## Stop and replan conditions

Stop and return to design before continuing if:

- the repository designation requires a source other than local symbolic
  `refs/remotes/origin/HEAD` or a fetch/network policy;
- all-best-merge-base or base-to-working-tree semantics cannot remain inside
  `agentstudio-git`;
- Core cannot atomically apply target-if-absent through the existing pane graph;
- production and Debug need a new generalized host/persistence owner rather
  than the bounded shared pure mapping;
- the existing product-call or metadata transports cannot express the contract
  without a new communication system;
- any proof requires weakening/removing an existing gate or writing live
  production/beta data;
- implementation begins adding annotation, history, lifecycle, cache, service,
  watcher, security, or unrelated Debug machinery.

## Plan record

```text
plan path: docs/specs/2026-08-06-worktree-annotations/plans/2026-08-08-pr0-review-comparison.md
originating planner: plan-implementation
planning result: draft
result payload: owner approval recorded after reading this plan must name this exact path and current meaning
```

Approval evidence: absent.
