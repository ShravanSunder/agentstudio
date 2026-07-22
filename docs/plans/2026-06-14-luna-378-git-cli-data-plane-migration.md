# LUNA-378 Git CLI Data-Plane Migration Plan

## Current Baseline

PR #165, "Build Bridge review foundation", is merged into `main`.

- GitHub REST check: `merged=true`, `merged_at=2026-06-14T00:06:56Z`, merge commit `31350898529d07c5b49a68a39581efcadbbedac5`.
- This worktree has been fast-forwarded to `origin/main` at `925049505b2b4e43d3573a0dd6b8aa5e6ed825a8`.
- The PR #165 merge commit is an ancestor of the current checkout.
- `Package.swift` already depends on the remote `agentstudio-git` package at revision `90bb17da9d7030f4ae954d45cf150a0f5fe6511b`.

## Problem

AgentStudio now has an AgentStudioGit-backed Bridge review adapter, but the app still has Git data-plane reads implemented through shell/process calls. LUNA-378 is the separate Git CLI replacement lane: inventory Git-related process invocations, classify them, and migrate the true Git data-plane reads behind AgentStudioGit-backed providers without changing Bridge ownership or eventbus facts.

This plan is not a Bridge contract plan. Bridge owns `BridgeReviewSourceProvider`, `BridgeReviewGeneration`, `BridgeContentHandle`, review packages, source endpoints, BridgeWeb contracts, and resource URL semantics. Git providers may feed Bridge, but they must not own Bridge vocabulary.

LUNA-378 should land as one PR from this worktree. The plan is sequenced internally for proof, but the outcome is not split across multiple PRs or tickets.

## Source Coverage

Line counts checked before planning:

- `docs/plans/2026-06-08-bridge-agent-review-foundation.md`: 1071 lines.
- `docs/superpowers/plans/2026-06-08-agentstudio-git-bridge-foundation.md`: 2139 lines.
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`: 329 lines.
- The removed monolithic Bridge architecture document: 2914 lines.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift`: inspected current shell provider and app-local status contracts.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`: inspected provider injection and eventbus boundary.
- `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift`: inspected default provider construction.
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift`: inspected `.git` traversal and `git rev-parse` validation.
- `Sources/AgentStudio/Infrastructure/WorktrunkService.swift`: inspected `wt` workflow commands and the live `git worktree list` discovery dependency. `discoverWorktrees` always calls Git discovery before overlaying `wt list` metadata, so this is not fallback-only behavior.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Forge/ForgeActor.swift`: inspected `gh` integration boundary.
- `Package.resolved`: inspected the app's pinned `agentstudio-git` revision, `90bb17da9d7030f4ae954d45cf150a0f5fe6511b`.
- `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git` at `3aed9a42ed1b05598a65b3c2c9e53133e946ac6f`: inspected adjacent SDK checkout only as a convenience copy.
- Pinned SDK source at `90bb17da9d7030f4ae954d45cf150a0f5fe6511b` via `git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git show <revision>:<path>`:
  - `Sources/AgentStudioGitContracts/AgentStudioGitSDK.swift`
  - `Sources/AgentStudioGitContracts/GitStatusContracts.swift`
  - `Sources/AgentStudioGitLocal/LibGit2AgentStudioGitLocalClient.swift`
  - `Sources/AgentStudioGitLocal/Runtime/GitRepositoryIdentityResolver.swift`
  - `Sources/AgentStudioGitLocal/Worktrees/LibGit2WorktreeReader.swift`
- `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitTests/ConsumerCompatibility/GitWorkingTreeStatusCompatibilityTests.swift`: inspected current SDK-side consumer compatibility mapping, which mirrors the intended AgentStudio status adapter shape.

## Source Evidence

- `docs/plans/2026-06-08-bridge-agent-review-foundation.md` is the landed Bridge foundation plan. It says the Git/backend lane supplies data behind `BridgeReviewSourceProvider` and must not own BridgeWeb TypeScript contracts, content handles, endpoint shape, package shape, or review-generation vocabulary.
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` defines the canonical Bridge review vocabulary and allows direct AgentStudioGit calls only when public SDK DTOs exactly match Bridge contracts.
- The then-current monolithic Bridge architecture document said the review foundation existed and the remaining Bridge work was source-provider-backed package data and downstream viewer rendering. Current ownership now lives in [Bridge Viewer Architecture](../architecture/bridge_viewer_architecture.md), [Bridge Native Runtime Architecture](../architecture/bridge_native_runtime_architecture.md), and [Bridge Web Runtime Architecture](../architecture/bridge_web_runtime_architecture.md).
- `docs/superpowers/plans/2026-06-08-agentstudio-git-bridge-foundation.md` built the separate AgentStudioGit package and explicitly scoped Git Tasks 1-8 away from Bridge contracts.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/AgentStudioGitBridgeReviewDataClient.swift` is already the thin Bridge-owned mapper from AgentStudioGit DTOs into Bridge review contracts.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift` still shells to `git status`, `git diff --shortstat`, and `git config --get remote.origin.url`.
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift` still shells to `git rev-parse --is-inside-work-tree` and `git rev-parse --show-superproject-working-tree`.
- `Sources/AgentStudio/Infrastructure/WorktrunkService.swift` still shells to `git worktree list --porcelain`, then overlays `wt list`, and uses `wt switch -c` / `wt remove` for mutations.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Forge/ForgeActor.swift` shells to `gh pr list`; that is forge integration, not Git data-plane.
- The pinned SDK revision exposes `AgentStudioGitLocalClient.repositoryIdentity`, `validateWorktree`, `worktrees`, and `status`, but a search of the pinned SDK source for `submodule` / `superproject` returned no dedicated API. RepoScanner migration must prove or add submodule/superproject parity, not assume it.

## Inventory And Classification

| Call site | Process calls | Classification | LUNA-378 disposition |
|---|---|---|---|
| `ShellGitWorkingTreeStatusProvider` | `git status --porcelain=v1 --branch --untracked-files=normal`; `git diff --shortstat HEAD --`; `git config --get remote.origin.url` | Git data-plane read | Primary migration target. Add CLI-vs-SDK parity tests first, then replace the default provider with an AgentStudioGit-backed provider. |
| `RepoScanner.isValidGitWorkingTree` | `git rev-parse --is-inside-work-tree`; `git rev-parse --show-superproject-working-tree` | Git data-plane read for repository discovery validation | Migrate behind an app-owned repository discovery/validation provider backed by AgentStudioGit. Because the pinned SDK has no visible submodule/superproject API, this PR must add or consume that SDK capability and update the package pin before the scanner migration. A retained production shell exception requires explicit user approval and is not the default plan. |
| `WorktrunkService.discoverWithWorktrunk` | `wt list --format=json` | Worktree/workflow command and external tool integration | Keep as workflow UX. Do not replace in the status-projection slice. |
| `WorktrunkService.discoverWithGit` | `git worktree list --porcelain` | Worktree/workflow discovery dependency; read-like, but part of the Worktrunk workflow lane | Classify and isolate in this PR. Do not replace by default because `WorktrunkService` is currently synchronous and depends on merge/order/name semantics. Replacement is allowed only if this PR deliberately changes the Worktrunk discovery boundary and proves parity with dedicated tests. Creation/removal remain out of scope. |
| `WorktrunkService.createWorktree/removeWorktree` | `wt switch -c`; `wt remove` | Worktree/workflow commands | Out of scope for LUNA-378 data-plane read replacement unless a later worktree-management lane is approved. |
| `GitHubCLIForgeStatusProvider` | `gh pr list --repo ...` | External forge tool integration | Out of scope. Keep behind `ForgeStatusProvider`. |
| `ZmxBackend`, `SessionConfiguration` | `zmx`, `which zmx`, candidate `zmx --version` | Non-Git process infrastructure | Out of scope. |
| `ExternalWorkspaceOpener` | External editor launch | External app integration | Out of scope. |
| `ProcessExecutor` | Generic process infrastructure | Non-Git process infrastructure | Keep. This plan removes Git data-plane consumers, not process infrastructure globally. |

## Requirements

1. Inventory all Git-related shell/process invocations and classify each as Git data-plane read, worktree/workflow command, external tool integration, or non-Git process infrastructure.
2. Migrate the Git data-plane reads behind AgentStudioGit or app-owned providers backed by AgentStudioGit.
3. Keep `GitWorkingDirectoryProjector` public behavior stable.
4. Keep eventbus facts stable: `gitSnapshotChanged`, `branchChanged`, `originChanged`, worktree registration/removal semantics, retry behavior, and existing suppression/admission policy must not change unless explicitly amended.
5. Add CLI-vs-SDK parity tests before replacing current shell status projection.
6. Do not move Bridge contracts or BridgeWeb contracts into AgentStudioGit.
7. Do not treat Worktrunk workflow commands, `gh`, zmx, editor launches, or generic process infrastructure as Git data-plane reads.

## Security Context

Security-relevant assets:

- Local repository metadata that drives sidebar state, eventbus facts, branch/origin indicators, and watched-folder registration.
- Remote origin URLs, especially credentialed HTTP(S) remotes that could contain userinfo or query material.
- Bridge review contracts and resource URL semantics, which must remain Bridge-owned and must not leak into the SDK package.

Entry points and trust boundaries:

- Filesystem paths from workspace topology and watched-folder scans are local untrusted inputs.
- Git repository contents and config are local untrusted inputs.
- AgentStudioGit is a library boundary inside the app process; it replaces shell-based Git reads but does not make repository metadata trusted.
- `wt`, `gh`, zmx, and editor launches remain external tool/process boundaries and are not migrated as data-plane reads in this ticket.

Invariants:

- No production status or repository-validation path should execute `git` after its lane is migrated.
- SDK errors must be fail-open for app startup and sidebar refresh; they must not crash actor pipelines.
- The current status provider's degraded behavior must be preserved unless explicitly amended: primary status failure returns `nil`; shortstat/origin failures degrade to the best available snapshot.
- HTTP(S) origin credential/query redaction from the SDK is acceptable as intentional hardening if verified, but SSH, file URL, absent-origin, and credentialed HTTP(S) cases must be covered so eventbus `originChanged` behavior is understood rather than accidental.
- Bridge vocabulary and BridgeWeb contracts remain out of the SDK package.

Proof:

- Production-only process scans after implementation.
- Origin mapping parity/hardening tests.
- Boundary scans for Bridge vocabulary in the SDK source tree.
- Existing and added projector/eventbus tests for stable facts.

## Write Surfaces

Expected AgentStudio app writes:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/`
- `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift`
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift`, if the watched-folder scanner boundary becomes async for SDK-backed repository discovery.
- `Sources/AgentStudio/Infrastructure/WorktrunkService.swift`, only for explicit classification/documentation or for a deliberate Worktrunk discovery-boundary replacement with parity tests.
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/` for runtime Git/projector/provider tests that match the existing test arc.
- `Tests/AgentStudioTests/Infrastructure/RepoScannerTests.swift`
- `Tests/AgentStudioTests/Infrastructure/WorktrunkServiceParsingTests.swift` and `Tests/AgentStudioTests/Infrastructure/WorktrunkParsingTests.swift` if Worktrunk discovery changes.
- `Tests/AgentStudioTests/Architecture/` for boundary/source-scan tests.
- `docs/plans/2026-06-14-luna-378-git-cli-data-plane-migration.md` for plan updates.

Adjacent SDK writes are expected if current public API cannot prove scanner parity:

- `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGitContracts/`
- `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGitLocal/`
- `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/`
- `Package.swift` and `Package.resolved` in this AgentStudio worktree, to pin the SDK revision that contains any new capability.

Explicitly excluded write surfaces:

- Bridge contracts, BridgeWeb contracts, Bridge review package/content-handle/source-endpoint models, and Bridge resource URL semantics.
- zmx runtime/process infrastructure.
- Forge/`gh` provider behavior.
- Worktrunk mutation UX (`wt switch -c`, `wt remove`) unless a later plan explicitly changes the workflow command lane.

## Design

### Provider Boundary

Keep the existing app-level provider seam:

```swift
protocol GitWorkingTreeStatusProvider: Sendable {
    func status(for rootPath: URL) async -> GitWorkingTreeStatus?
}
```

Add an app-owned implementation such as `AgentStudioGitWorkingTreeStatusProvider` in `Core/RuntimeEventSystem/Git`. It imports `AgentStudioGit`, calls `AgentStudioGitLocalClient.status(for:options:)`, and maps SDK DTOs into the existing app-local `GitWorkingTreeStatus`, `GitWorkingTreeSummary`, and `GitOriginResolution`.

The mapper is intentionally app-owned because the eventbus and repo-enrichment contracts are AgentStudio runtime contracts, not SDK contracts.

Use the pinned SDK revision as the implementation source of truth. The adjacent `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git` checkout may be ahead of the pin; do not rely on adjacent-only APIs until `Package.swift` and `Package.resolved` are updated to the SDK commit that contains them.

Preserve the existing projector off-actor execution contract. `GitWorkingDirectoryProjector` currently calls the provider from an off-actor `@concurrent` compute path; the SDK-backed implementation must not move libgit2 or filesystem work onto the projector actor or main actor. If an adapter wrapper is needed, keep the expensive SDK call inside a `@concurrent nonisolated` helper or an equivalent detached/off-actor path and add architecture/test coverage for that boundary.

### Status Mapping

Map AgentStudioGit fields to the current runtime status shape:

- SDK `GitStatusSnapshot.head.kind == .branch` and `shortName` -> app `branch`.
- SDK detached/unborn head -> app `branch = nil`, matching current shell parser behavior for `HEAD`.
- SDK `GitStatusSummary.unstagedFileCount` -> app `changed`.
- SDK `GitStatusSummary.stagedFileCount` -> app `staged`.
- SDK `GitStatusSummary.untrackedFileCount` -> app `untracked`.
- SDK `linesAdded` / `linesDeleted` -> app line stats.
- SDK `aheadCount` / `behindCount` -> app sync fields only when SDK `hasUpstream` is true; otherwise app `aheadCount` and `behindCount` remain nil, matching current shell parser semantics.
- SDK `hasUpstream` -> app `hasUpstream` only for branch heads; detached/unborn heads keep sync state unknown.
- SDK `GitOriginResolution.resolved(remote)` -> app `.resolved(remote.rawURL)`.
- SDK `.confirmedAbsent` -> app `.confirmedAbsent`.
- SDK origin resolution that cannot be completed yet -> app `.awaitingResolution`, preserving the projector's retry/admission behavior.
- SDK primary status failure -> app `nil`, preserving the current fail-open provider contract.
- SDK shortstat or origin-only failure -> best available degraded snapshot, not unconditional `nil`, unless the PR explicitly amends current behavior with user approval. The existing shell provider returns `(0, 0)` for shortstat failure and `.confirmedAbsent` / `.awaitingResolution` for origin failure paths, so the SDK adapter may need app-side fallback or SDK support for partial results.
- SDK HTTP(S) origin redaction -> accepted hardening only if tests cover SSH, file URL, absent origin, and credentialed HTTP(S) remotes. Do not preserve credentials in app state just to match old shell output.

### Repo Scanner Boundary

`RepoScanner` mixes filesystem traversal with Git validation. LUNA-378 should separate those responsibilities:

- Keep traversal and `.git` marker classification in `RepoScanner`.
- Add an app-owned `GitRepositoryDiscoveryProvider` or `GitWorktreeValidationProvider`.
- Default implementation uses pinned AgentStudioGit APIs where they prove equivalent behavior.
- Tests must cover clone roots, linked worktrees, unreadable `.git`, invalid worktrees, and submodule exclusion.

The current pinned SDK exposes `repositoryIdentity(for:)` and `validateWorktree`, but no dedicated submodule/superproject API is visible in the pinned source. Implementation must start this slice by adding a failing parity test for the current `RepoScanner` behavior: a Git submodule under a scanned folder is excluded because `git rev-parse --show-superproject-working-tree` returns a non-empty value. Then choose the smallest one-PR path:

1. Add or consume the missing AgentStudioGit SDK API for superproject/submodule detection, update `Package.swift` / `Package.resolved`, and migrate `RepoScanner`.
2. If SDK mutation becomes disproportionate, stop and reconverge before keeping any production scanner shell call. A retained shell exception requires explicit user approval and an architecture test that forbids any other production Git data-plane shell calls.

Do not silently keep `git rev-parse` without a written exception and proof.

Use an async scanner boundary in AgentStudio rather than blocking on an async SDK call from synchronous scanner code. `RepoScanner` should continue to own traversal and grouping, while `FilesystemActor` / watched-folder refresh should accept an async validation provider and invoke it from the existing off-actor scan path. This keeps libgit2 and filesystem work off actor executors and makes the dependency boundary visible in tests. A synchronous SDK helper is allowed only if this PR adds a genuinely synchronous public SDK API and proves it does not hide actor blocking.

### Worktrunk Boundary

Worktrunk remains the workflow UX layer for create/remove/switch. LUNA-378 should not convert worktree mutation commands to SDK calls.

The `git worktree list --porcelain` call is read-like but it lives in workflow discovery and runs on every `discoverWorktrees` call before `wt list` metadata is merged. For LUNA-378, classify it as Worktrunk workflow discovery and leave it in place unless the implementation deliberately changes the Worktrunk discovery boundary in this same PR.

If the PR does replace it, the replacement must explicitly handle the sync/async API boundary and prove:

- canonical path ordering is stable.
- display-name overlay from `wt list` still wins where appropriate.
- ID preservation and merge behavior remain stable.
- post-create lookup still finds the newly created worktree.
- no branch/status fields are added to the app `Worktree` model.

## Task Sequence

### Task 1: Commit The Inventory

Create or keep this plan as the canonical inventory for LUNA-378. Before implementation, run a fresh production scan and a separate broad scan:

```bash
rg -n 'command:\s*"git"|shell\("git"|arguments\s*=\s*\["git"|=\s*"git"|\["git"|/usr/bin/git|rev-parse|status --porcelain|diff --shortstat|worktree list' Sources/AgentStudio Package.swift Package.resolved
rg -n 'command:\s*"wt"|shell\("wt"|arguments\s*=\s*\["wt"|=\s*"wt"|\["wt"|wt list|wt switch|wt remove' Sources/AgentStudio Package.swift Package.resolved
rg -n 'command:\s*"gh"|shell\("gh"|arguments\s*=\s*\["gh"|=\s*"gh"|\["gh"|gh pr' Sources/AgentStudio Package.swift Package.resolved
rg -n 'Process\(|ProcessExecutor|DefaultProcessExecutor|/usr/bin/env|which zmx|command:\s*"zmx"|shell\("zmx"|arguments\s*=\s*\["zmx"|agentstudio-git' Sources/AgentStudio Package.swift Package.resolved
rg -n 'command:\s*"git"|shell\("git"|arguments\s*=\s*\["git"|=\s*"git"|\["git"|/usr/bin/git|rev-parse|status --porcelain|diff --shortstat|worktree list|command:\s*"wt"|command:\s*"gh"|Process\(|ProcessExecutor|DefaultProcessExecutor|which zmx|agentstudio-git' Sources Tests docs Package.swift Package.resolved
```

Acceptance criteria:

- Every production process invocation from the production scans is listed or explicitly excluded.
- The pre-implementation scan must find today's expected production call sites: `ShellGitWorkingTreeStatusProvider`, `RepoScanner`, `WorktrunkService`, `ForgeActor`, zmx/session infrastructure, external app/process helpers, and `ProcessExecutor` plumbing.
- The final production scan must show no status-projection or repository-validation Git data-plane shell calls, except an explicitly approved scanner exception.
- Test/docs-only invocations from the broad scan are classified separately and do not hide production data-plane calls.
- Git process calls are classified by lane.
- The plan does not claim `gh`, zmx, Worktrunk mutation, or editor launches are data-plane reads.

### Task 2: Add CLI-vs-SDK Status Parity Tests

Add focused tests before changing the default provider.

Suggested files:

- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/AgentStudioGitWorkingTreeStatusProviderTests.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusParityFixture.swift`

Seed the app mapper from the SDK-side compatibility evidence in `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitTests/ConsumerCompatibility/GitWorkingTreeStatusCompatibilityTests.swift`, but reprove behavior in AgentStudio's test suite before switching defaults.

Test cases:

- clean repository on a branch with no upstream.
- staged file, unstaged file, and untracked file counts.
- line additions/deletions for working-tree diff against `HEAD`.
- origin remote present and absent.
- branch with upstream, ahead/behind zero.
- branch ahead and branch behind when fixture setup is cheap and deterministic.
- detached `HEAD` maps to `branch == nil`.
- unborn branch / no-commit repository behavior is pinned before switching defaults.
- non-Git path or invalid worktree returns `nil`.
- origin mapping covers SSH, file URL, absent origin, and credentialed HTTP(S) remotes. Credential stripping is accepted only as an explicit SDK hardening behavior.
- primary status failure returns `nil`; origin/shortstat-only failure preserves the current degraded snapshot semantics or the plan is amended before behavior changes.

The oracle may use CLI Git in tests, but only as a parity oracle. Product runtime code should not keep CLI Git as the status provider after this task passes.

### Task 3: Add AgentStudioGit Status Provider

Create `AgentStudioGitWorkingTreeStatusProvider`.

Implementation notes:

- Inject `any AgentStudioGitLocalClient`, defaulting to `LibGit2AgentStudioGitLocalClient()`.
- Call `status(for: rootPath, options: GitStatusOptions(includeIgnored: false, includeUntracked: true))`.
- Keep the existing `GitWorkingTreeStatusProvider` protocol unchanged.
- Keep the app-local status structs unchanged unless a parity test proves a current field is wrong.
- Preserve the current fail-open semantics: primary status failure returns `nil`; partial origin/shortstat failure produces the best available snapshot where the old provider did.
- Keep expensive SDK work off the projector actor/main actor via `@concurrent nonisolated` or equivalent off-actor execution.

Acceptance criteria:

- New provider tests pass.
- Existing `GitWorkingDirectoryProjectorTests` pass without event shape edits.
- The provider is app-owned; no eventbus model moves into AgentStudioGit.
- An architecture or focused concurrency-boundary test guards against constructing a provider path that runs libgit2 work on the projector actor/main actor.

### Task 4: Switch Runtime Default From Shell To SDK

Change defaults in:

- `GitWorkingDirectoryProjector.init`
- `FilesystemGitPipeline.init`
- any direct production construction still defaulting to `ShellGitWorkingTreeStatusProvider`

Keep the shell provider only if needed for parity tests or explicit test fixtures. Do not leave a production fallback unless the plan is amended with a specific SDK parity gap.

Acceptance criteria:

- A source scan shows no production default uses `ShellGitWorkingTreeStatusProvider`.
- Eventbus tests prove `gitSnapshotChanged`, `branchChanged`, and `originChanged` behavior remains stable.
- Integration coverage runs against the new provider where current shell-provider defaults were used. Do not claim E2E proof unless an E2E test is deliberately updated and run with its repo-local opt-in environment, such as `SWIFT_TEST_INCLUDE_E2E=1`.

### Task 5: Migrate RepoScanner Git Validation

Extract repository validation behind an app-owned provider.

Suggested shape:

```swift
protocol GitRepositoryDiscoveryProvider: Sendable {
    func validateWorkingTree(at path: URL) async -> GitRepositoryDiscoveryValidation
}
```

Because `RepoScanner.scanForGitRepos` is synchronous today and `FilesystemActor` injects a synchronous `@Sendable (URL) -> [RepoScanner.RepoScanGroup]` scanner that is called from an off-actor `@concurrent` scan function, make the boundary explicit instead of hiding async SDK work behind a synchronous wrapper:

Make the watched-folder scan provider async at the call boundary and use `AgentStudioGitLocalClient` directly, preserving the existing off-actor scan behavior. Do not wrap an async SDK call in a synchronous semaphore-style scanner. A synchronous helper is allowed only if this PR adds a real synchronous SDK API and updates the package pin deliberately.

This must not move blocking filesystem or Git work onto the actor executor. Update existing stubbed topology tests or add a focused `FilesystemActor` watched-folder test so the async scanner boundary is exercised, not only `RepoScanner` unit behavior.

Acceptance criteria:

- `RepoScannerTests` still cover clone root and linked worktree grouping.
- Submodules remain excluded.
- Existing filesystem topology integration tests pass.
- Any retained shell fallback has explicit user approval, a documented SDK gap, and a source-scan architecture test.

### Task 6: Decide Worktrunk Discovery Scope

Classify `WorktrunkService.discoverWithGit` as Worktrunk workflow discovery and leave it in place by default for LUNA-378. This satisfies the inventory requirement without changing workflow semantics.

Only replace it if the implementation deliberately takes on Worktrunk discovery-boundary work in this PR. In that case, run parity between `git worktree list --porcelain` parsing and `AgentStudioGitLocalClient.worktrees(for:)` for representative repositories.

If replacement is taken and parity is stable:

- Replace `discoverWithGit` with `discoverWithAgentStudioGit`.
- Keep `wt list --format=json` as the workflow-enhanced display-name source.
- Keep `wt switch -c` and `wt remove`.

If replacement is taken and parity is not stable:

- Leave `discoverWithGit` classified as workflow discovery.
- Add a follow-up ticket for Worktrunk/Git worktree discovery semantics.

Acceptance criteria:

- `WorktrunkServiceParsingTests` and `WorktrunkParsingTests` still pass.
- If discovery is replaced, add deterministic parity/reconciliation coverage for canonical path ordering, display-name overlay, ID preservation, merge behavior, and post-create lookup.
- Worktree model remains structure-only: no branch/status fields are added.
- No worktree mutation command is moved into AgentStudioGit in this ticket.

### Task 7: Boundary Guard Tests

Add or update architecture tests so the boundary stays stable:

- Bridge contracts stay under `Sources/AgentStudio/Features/Bridge`.
- AgentStudioGit does not define `BridgeReview*`, `BridgeContentHandle`, `BridgeReviewGeneration`, BridgeWeb TypeScript contracts, or `agentstudio://resource` URL semantics.
- Production `GitWorkingDirectoryProjector` construction uses the SDK provider.
- Shell Git process usage is absent from production data-plane status and repo-validation code.
- Any allowed Worktrunk Git process usage is limited to `WorktrunkService` workflow discovery and is documented as out of the Git data-plane read migration.

## Requirements/Proof Matrix

Requirement / claim:
Inventory is complete and all production process/Git invocations are classified.
Proof source:
Fresh production scans from Task 1 for Git, `wt`, `gh`, zmx/process infrastructure, plus broad scan over `Sources Tests docs Package.swift Package.resolved`, reviewed against the inventory table.
Proof owner:
parent plus implementation executor.
Stale-proof guard:
Run after final implementation diff, not only before edits.
Proof layer:
architecture/source scan.
Red/green required:
No, inventory proof is source inspection.
Sized for one PR:
Yes.

Requirement / claim:
Status projection no longer uses production shell Git and preserves current runtime status semantics.
Proof source:
CLI-vs-SDK parity tests for clean, staged, unstaged, untracked, line stats, origin present/absent, origin awaiting-resolution behavior, upstream/ahead/behind, detached head, unborn/no-commit repository, invalid worktree, and credentialed HTTP(S) origin hardening; app mapper cross-check against SDK-side `GitWorkingTreeStatusCompatibilityTests`; production source scan showing defaults use `AgentStudioGitWorkingTreeStatusProvider`.
Proof owner:
implementation executor; parent verifies evidence.
Stale-proof guard:
Run parity tests after the provider switch and rerun source scan against final diff.
Proof layer:
unit plus integration.
Red/green required:
Yes; parity tests must fail or be impossible against the pre-switch SDK provider path before the runtime default is changed, then pass after implementation.
Sized for one PR:
Yes.

Requirement / claim:
`GitWorkingDirectoryProjector` and eventbus facts stay stable.
Proof source:
`mise run test -- --filter GitWorkingDirectoryProjector`, `mise run test -- --filter GitEnrichmentEventPipelineIntegrationTests`, and `mise run test -- --filter FilesystemGitPipelineIntegrationTests`, plus origin retry/admission coverage for `.awaitingResolution`.
Proof owner:
implementation executor; parent verifies output.
Stale-proof guard:
Run after all status-provider and scanner changes are complete.
Proof layer:
unit plus integration.
Red/green required:
No new failing test is required unless implementation changes event semantics; existing suite is the stability guard.
Sized for one PR:
Yes.

Requirement / claim:
`RepoScanner` Git validation is behind an AgentStudioGit-backed app provider.
Proof source:
`mise run test -- --filter RepoScanner` plus topology or focused `FilesystemActor` watched-folder tests that exercise the async scanner boundary; a submodule/superproject parity test; source scan showing `git rev-parse` no longer appears in production scanner code. If explicit user approval changes this to a temporary exception, add a documented exception and a source-scan architecture test.
Proof owner:
implementation executor; parent verifies final source and tests.
Stale-proof guard:
Run after any SDK API additions and after the app's package pin is updated.
Proof layer:
unit plus integration.
Red/green required:
Yes for any new provider behavior that replaces submodule/superproject handling.
Sized for one PR:
Yes, with allowed SDK writes if needed.

Requirement / claim:
Worktrunk workflow commands remain workflow-owned, and `git worktree list --porcelain` is explicitly classified as workflow discovery unless deliberately replaced with parity proof.
Proof source:
`mise run test -- --filter WorktrunkService`, `mise run test -- --filter WorktrunkParsing`; source scan and inventory classification if discovery remains. If discovery is replaced, add parity/reconciliation coverage for canonical path ordering, display-name overlay, ID preservation, merge behavior, and post-create lookup.
Proof owner:
implementation executor; parent verifies final decision.
Stale-proof guard:
Run after scanner/status changes so fallback semantics are judged against final worktree model.
Proof layer:
unit plus source inspection.
Red/green required:
Yes if replacing discovery; no if only classification/documentation changes.
Sized for one PR:
Yes.

Requirement / claim:
Bridge contracts and BridgeWeb contracts do not move into AgentStudioGit.
Proof source:
Bridge review provider tests plus SDK-source negative scan `rg -n "BridgeReview|BridgeContentHandle|BridgeReviewGeneration|agentstudio://resource|BridgeWeb" /Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources`; app-side positive ownership remains under `Sources/AgentStudio/Features/Bridge`.
Proof owner:
parent plus implementation executor.
Stale-proof guard:
Run after any SDK changes and after final AgentStudio diff.
Proof layer:
architecture/source scan plus tests.
Red/green required:
No, unless architecture test is added.
Sized for one PR:
Yes.

Requirement / claim:
Code quality and changed-surface validation pass.
Proof source:
`mise run lint`; focused tests above; `mise run test` if the full suite is practical for the PR closeout, otherwise report focused gates and the reason full suite was not run.
Proof owner:
parent.
Stale-proof guard:
Run from this worktree after all edits, with final `git status` and changed-file summary.
Proof layer:
lint, unit, integration, optional full suite.
Red/green required:
No.
Sized for one PR:
Yes.

Requirement / claim:
Any adjacent AgentStudioGit SDK changes are proved before updating the app pin.
Proof source:
From `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git`: `swift test --filter GitWorktreeIntegrationTests`, `swift test --filter GitWorkingTreeStatusCompatibilityTests`, and `swift test --filter GitStatusIntegrationTests`, plus any new SDK tests for submodule/superproject validation.
Proof owner:
implementation executor; parent verifies output and updated `Package.swift` / `Package.resolved`.
Stale-proof guard:
Run before the app package pin is consumed by AgentStudio tests.
Proof layer:
SDK unit/integration.
Red/green required:
Yes when SDK files change.
Sized for one PR:
Yes.

## Validation Gates

Run in this order:

1. Fresh inventory/source scan.
2. Pinned SDK API check: inspect `Package.resolved` and the resolved/pinned `agentstudio-git` source, not only the adjacent checkout.
3. Status parity tests before runtime default switch.
4. Status provider tests after implementation.
5. Projector/eventbus integration tests after provider switch.
6. RepoScanner unit, submodule/superproject parity, and topology integration tests after scanner migration.
7. SDK tests from the adjacent AgentStudioGit checkout if SDK files changed, before relying on the updated app pin.
8. Worktrunk classification tests, and parity/reconciliation tests if discovery is changed.
9. Bridge boundary source scan and Bridge provider tests if any SDK or Bridge-adjacent imports change.
10. `mise run lint`.
11. `mise run test` when feasible for PR closeout; if not feasible, record the focused proof set and blocker/reason.

## Risks And Tradeoffs

- Hard status cutover reduces runtime shell usage and aligns with the SDK boundary, but any libgit2-vs-CLI semantic mismatch will surface in the sidebar/eventbus path. The parity tests are the guardrail.
- Making `RepoScanner` validation async broadens the changed surface into watched-folder refresh and filesystem topology tests, but it keeps libgit2 work off actor executors and avoids a hidden synchronous wrapper around async SDK APIs. If the boundary reveals a larger architecture issue, stop product-code edits and reconverge before continuing.
- Keeping Worktrunk mutation commands is intentional. Replacing them would conflate data-plane reads with user workflow commands and would change UX ownership.
- Leaving `git worktree list --porcelain` in WorktrunkService is a conscious workflow-lane classification, not a missed status data-plane migration. The cost is that Worktrunk discovery remains a later replacement lane if the product wants zero production Git process invocations.
- Shell Git in tests is acceptable as an oracle. Shell Git in production status projection is what LUNA-378 should remove.

## Rollback / Recovery

- If status parity fails after reasonable SDK mapping fixes, revert only the runtime default switch and keep the new provider/tests for diagnosis; do not remove the inventory.
- If `RepoScanner` requires SDK functionality not present in the pinned dependency, add the SDK API and update the AgentStudio pin in this PR. If that becomes disproportionate, stop and ask before retaining any scanner shell call. Do not hide an exception in code comments only.
- If Worktrunk discovery replacement is attempted and changes ordering or names, keep the workflow discovery call classified and defer replacement; do not change Worktrunk mutation UX to compensate.
- If full `mise run test` fails outside this changed surface, stop edits, report focused pass/fail status and unrelated blocker evidence, and ask before touching infrastructure.

## Locked Decisions For Execution

- LUNA-378 lands as one PR from this worktree.
- Status projection is a hard runtime cutover to an app-owned AgentStudioGit provider after parity tests.
- `RepoScanner` validation migrates behind an AgentStudioGit-backed app provider; SDK capability and app pin updates are in scope if required for submodule/superproject parity.
- `FilesystemActor` / watched-folder scanning should expose an async validation boundary instead of blocking on async SDK calls.
- `WorktrunkService.discoverWithGit` is classified as workflow discovery and left in place unless the PR deliberately takes on Worktrunk discovery-boundary replacement with parity proof.
- Bridge contracts stay in Bridge-owned app code, not in AgentStudioGit.

No user decisions are required before implementation. If code inspection invalidates one of these decisions, stop product-code edits and reconverge with evidence.

## Recommended Slice

LUNA-378 should land as one PR from this worktree. Keep the implementation sequenced internally so each boundary has proof before the next boundary changes:

1. Add CLI-vs-SDK status parity tests.
2. Add `AgentStudioGitWorkingTreeStatusProvider`.
3. Switch `GitWorkingDirectoryProjector` and `FilesystemGitPipeline` defaults.
4. Prove eventbus facts and sidebar enrichment stay stable.
5. Migrate `RepoScanner` Git validation behind an AgentStudioGit-backed app provider, adding SDK API in `agentstudio-git` if required for submodule/superproject parity.
6. Classify `WorktrunkService.discoverWithGit` as workflow discovery and leave it in place unless implementation deliberately expands into Worktrunk discovery replacement with parity proof.
7. Run the full LUNA-378 proof matrix before PR handoff.
