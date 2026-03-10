# Sidebar Identity Resolution Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate the transient wrong sidebar tree by introducing an explicit repo identity-resolution state machine so newly discovered repos stay in `Scanning...` until they are confirmed as either remote-backed or local-only, then make the sidebar re-render from that stable state without needing resize-driven correction.

**Architecture:** Replace the current 2-state repo enrichment model (`.unresolved` / `.resolved`) with an explicit 3-state identity-resolution model that distinguishes `awaitingOrigin`, `localOnly`, and `remote`. `GitWorkingDirectoryProjector` must stop collapsing "origin empty right now" into "local-only" immediately. `WorkspaceCacheCoordinator` and the sidebar projection will consume the new state directly. No backward compatibility layer, no heuristic delays, no time-based grace window.

**Tech Stack:** Swift 6.2, AppKit + SwiftUI, `@Observable`, `AsyncStream` EventBus, `Testing`, `mise`

---

## Context and Root Cause

The bug is not just sidebar layout. The tree becomes logically wrong because the model resolves too early.

Current flow:

```text
.repoDiscovered
  -> WorkspaceCacheCoordinator seeds .unresolved

first git snapshot with empty origin
  -> GitWorkingDirectoryProjector emits .originChanged("", "")

WorkspaceCacheCoordinator.handleEnrichment(.originChanged)
  -> treats empty origin as resolved local identity
  -> repo leaves loading state too early
  -> sidebar renders it as a normal grouped item

later actual remote appears
  -> repo identity changes again
  -> sidebar regroups / re-sorts
```

This produces the "many weird top-level items, then later grouped/merged" behavior.

Relevant current code:

- `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift:253-269`
- `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift:147-170`
- `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift:56-69`

The correct fix is to introduce an explicit state for:

```text
identity unknown yet
```

instead of inferring:

```text
empty origin == local-only
```

---

## Target Model

Replace the repo identity model with explicit resolution states:

```text
RepoEnrichment
  .awaitingOrigin(repoId:)
  .resolvedLocal(repoId:, identity:, updatedAt:)
  .resolvedRemote(repoId:, raw:, identity:, updatedAt:)
```

Rules:

```text
newly discovered repo
  -> .awaitingOrigin

origin found
  -> .resolvedRemote

origin explicitly confirmed absent
  -> .resolvedLocal
```

Sidebar rule:

```text
.awaitingOrigin
  -> Scanning...

.resolvedLocal
  -> normal grouped section

.resolvedRemote
  -> normal grouped section
```

No backward compatibility:

```text
- update all codepaths to the new enum shape
- update tests in one pass
- do not preserve old .unresolved/.resolved dual model alongside new states
```

---

## Task 1: Redesign `RepoEnrichment` for explicit identity-resolution states

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/RepoEnrichment.swift`
- Test: `Tests/AgentStudioTests/Core/Models/RepoEnrichmentTests.swift`

**Step 1: Write the failing tests for the new enum shape**

Update `RepoEnrichmentTests.swift` to reflect the new states:

```swift
@Test
func awaitingOrigin_carriesRepoIdOnly() {
    let repoId = UUID()
    let enrichment = RepoEnrichment.awaitingOrigin(repoId: repoId)

    #expect(enrichment.repoId == repoId)
    #expect(enrichment.identity == nil)
    #expect(enrichment.raw == nil)
}

@Test
func resolvedLocal_hasIdentityButNoRawOrigin() {
    let repoId = UUID()
    let identity = RepoIdentity(
        groupKey: "local:agent-studio",
        remoteSlug: nil,
        organizationName: nil,
        displayName: "agent-studio"
    )
    let enrichment = RepoEnrichment.resolvedLocal(
        repoId: repoId,
        identity: identity,
        updatedAt: Date()
    )

    #expect(enrichment.repoId == repoId)
    #expect(enrichment.raw == nil)
    #expect(enrichment.identity == identity)
}

@Test
func resolvedRemote_hasRawOriginAndIdentity() {
    let repoId = UUID()
    let identity = RepoIdentity(
        groupKey: "remote:acme/agent-studio",
        remoteSlug: "acme/agent-studio",
        organizationName: "acme",
        displayName: "agent-studio"
    )
    let raw = RawRepoOrigin(origin: "git@github.com:acme/agent-studio.git", upstream: nil)
    let enrichment = RepoEnrichment.resolvedRemote(
        repoId: repoId,
        raw: raw,
        identity: identity,
        updatedAt: Date()
    )

    #expect(enrichment.repoId == repoId)
    #expect(enrichment.raw == raw)
    #expect(enrichment.identity == identity)
}
```

**Step 2: Run the targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoEnrichmentTests"
```

Expected:

```text
FAIL because the enum cases no longer match the tests
```

**Step 3: Implement the new enum shape**

In `RepoEnrichment.swift`, replace:

```swift
case unresolved(repoId: UUID)
case resolved(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)
```

with:

```swift
case awaitingOrigin(repoId: UUID)
case resolvedLocal(repoId: UUID, identity: RepoIdentity, updatedAt: Date)
case resolvedRemote(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)
```

Update all computed properties:

```text
- repoId
- raw
- identity
- origin
- upstream
- groupKey
- remoteSlug
- organizationName
- displayName
```

Semantics:

```text
awaitingOrigin
  raw = nil
  identity = nil

resolvedLocal
  raw = nil
  identity = local identity

resolvedRemote
  raw = remote facts
  identity = remote identity
```

**Step 4: Run the targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoEnrichmentTests"
```

Expected:

```text
PASS
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/RepoEnrichment.swift Tests/AgentStudioTests/Core/Models/RepoEnrichmentTests.swift
git commit -m "feat: add explicit repo identity resolution states"
```

---

## Task 2: Make discovery seed `awaitingOrigin`, not generic unresolved

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift`

**Step 1: Write the failing tests for discovery seeding**

Update coordinator tests to assert:

```swift
@Test
func repoDiscovered_seedsAwaitingOrigin() async {
    let store = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: store,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )
    let repoPath = URL(fileURLWithPath: "/tmp/test-repo")

    coordinator.consume(
        AppDelegate.makeTopologyEnvelope(
            repoPath: repoPath,
            source: .builtin(.coordinator)
        )
    )

    let repo = try #require(store.repos.first)
    #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
}
```

Also update any tests that currently assert `.unresolved`.

**Step 2: Run targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "WorkspaceCacheCoordinatorTests"
```

Expected:

```text
FAIL because code still writes the old state
```

**Step 3: Update discovery handling**

In `WorkspaceCacheCoordinator.handleTopology(.repoDiscovered)`:

Replace:

```swift
repoCache.setRepoEnrichment(.unresolved(repoId: repo.id))
```

with:

```swift
repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
```

Apply this consistently in:

```text
- existing repo / missing enrichment branch
- new repo branch
```

**Step 4: Run targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "WorkspaceCacheCoordinatorTests"
```

Expected:

```text
PASS
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift
git commit -m "feat: seed awaiting-origin state for discovered repos"
```

---

## Task 3: Add explicit "local-only confirmed" vs "awaiting origin" handling in the git projector

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`
- Test: `Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift`

**Step 1: Write failing projector tests for the new meaning**

Add tests that distinguish:

```swift
@Test
func firstEmptyOrigin_doesNotMeanLocalOnlyYet() async { ... }

@Test
func explicitNoRemoteFact_marksRepoLocalOnly() async { ... }

@Test
func laterRemoteStillConvergesToResolvedRemote() async { ... }
```

The test names matter more than exact fixture shape, but behavior must prove:

```text
- empty origin on first compute does not immediately collapse to local-only
- some explicit projector condition marks local-only
- remote discovery later wins and resolves to remote
```

**Step 2: Run targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "GitWorkingDirectoryProjectorTests"
```

Expected:

```text
FAIL because projector still emits empty origin as a generic originChanged("")
```

**Step 3: Introduce an explicit local-only fact**

Do not overload `originChanged("", "")` for both "unknown" and "confirmed absent".

Recommended change:

```text
Add a new worktree-scoped git event for local-only confirmation.
```

For example in `RuntimeEnvelopeCore.swift`:

```swift
case originUnavailable(repoId: UUID)
```

Then update `GitWorkingDirectoryProjector.computeAndEmit(...)`:

```text
if origin is empty on initial compute
  do not emit remote/local resolution immediately unless this path is the explicit
  "confirmed absent" case
```

The implementation may use a projector-owned per-repo state machine, but it must be explicit:

```text
unknown origin
confirmed no origin
known origin string
```

No time-based heuristic.
No retry-delay shortcut.
No "wait N ms then assume local."
```

**Step 4: Update pipeline integration tests**

Update `FilesystemGitPipelineIntegrationTests.swift` so the integration path asserts:

```text
initial registration
  -> snapshot arrives
  -> repo remains awaitingOrigin until identity is confirmed

git config update with remote
  -> resolves to remote
```

Add a separate integration case for confirmed local-only if the codebase has a stable signal for that path.

**Step 5: Run targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "GitWorkingDirectoryProjectorTests"
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "FilesystemGitPipelineIntegrationTests"
```

Expected:

```text
PASS
```

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeCore.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift
git commit -m "feat: distinguish awaiting-origin from local-only repos"
```

---

## Task 4: Consume the new local-only / remote / awaiting-origin states in the coordinator

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing tests for enrichment handling**

Add tests that assert:

```swift
@Test
func originUnavailable_resolvesLocalOnlyIdentity() { ... }

@Test
func originChanged_remote_resolvesRemoteIdentity() { ... }
```

Update any existing tests that currently expect empty origin to map to the old `.resolved(...)` case.

**Step 2: Run targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "WorkspaceCacheCoordinatorTests"
```

Expected:

```text
FAIL
```

**Step 3: Update coordinator enrichment handling**

In `handleEnrichment`:

```text
originChanged(remote string)
  -> .resolvedRemote

originUnavailable
  -> .resolvedLocal
```

Do not use:

```text
empty origin string -> local-only
```

unless the projector has already transformed that into an explicit local-only confirmation event.

**Step 4: Run targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "WorkspaceCacheCoordinatorTests"
```

Expected:

```text
PASS
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "feat: resolve repo identity as remote or local-only explicitly"
```

---

## Task 5: Make the sidebar projection consume the new state model

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Write failing sidebar projection tests**

Add or update tests to prove:

```swift
@Test
func awaitingOrigin_reposAppearOnlyInLoadingSection() { ... }

@Test
func resolvedLocal_reposAppearInNormalGroups() { ... }

@Test
func resolvedRemote_reposAppearInNormalGroups() { ... }
```

Also add a regression test that encodes the bug you saw:

```text
multiple newly discovered repos with snapshots but unresolved identity
  -> should not appear as many top-level normal groups
  -> should remain in Scanning...
```

**Step 2: Run targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoSidebarContentViewTests"
```

Expected:

```text
FAIL
```

**Step 3: Update the projection logic**

In `RepoSidebarContentView.projectSidebar(...)` and helper methods:

```text
loadingRepos
  = awaitingOrigin only

resolvedRepos
  = resolvedLocal + resolvedRemote
```

Also update any `buildRepoMetadata(...)` switch logic so it reflects the new enum cases.

**Step 4: Run targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoSidebarContentViewTests"
```

Expected:

```text
PASS
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "feat: keep awaiting-origin repos in sidebar scanning section"
```

---

## Task 6: Fix the resize-only correction by keying the sidebar to projection topology

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Write the failing projection fingerprint test**

Add a pure helper and test it:

```swift
@Test
func sidebarProjectionFingerprint_changesWhenGroupTopologyChanges() {
    // same repos, different identity grouping / loading split
    // fingerprint must change
}
```

**Step 2: Run targeted tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoSidebarContentViewTests"
```

Expected:

```text
FAIL
```

**Step 3: Add a projection fingerprint and use it as the reset boundary**

Add a pure helper like:

```swift
static func projectionFingerprint(_ projection: SidebarProjection) -> String
```

Fingerprint inputs:

```text
- resolved group ids
- repo ids inside each group
- loading repo ids
```

Then use it to reset the render boundary, for example on the `List` or the immediate container:

```swift
.id(projectionFingerprint)
```

Use the projection fingerprint, not `store.repos` fingerprint, because the bug is driven by projection topology.

**Step 4: Run targeted tests to verify they pass**

Run:

```bash
swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "RepoSidebarContentViewTests"
```

Expected:

```text
PASS
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "fix: reset sidebar tree when projection topology changes"
```

---

## Task 7: Update architecture docs for the new identity model

**Files:**
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: any sidebar-specific architecture doc if identity states are documented elsewhere

**Step 1: Update the repo identity state description**

Document:

```text
awaitingOrigin
resolvedLocal
resolvedRemote
```

**Step 2: Update the Add Folder / sidebar transition docs**

Document:

```text
newly discovered repos remain in Scanning... until identity is confirmed
```

**Step 3: Remove old references to `.unresolved` / `.resolved` as the only identity states**

Search and replace all stale architecture wording in the touched docs.

**Step 4: Commit**

```bash
git add docs/architecture/workspace_data_architecture.md docs/architecture/pane_runtime_architecture.md docs/architecture/pane_runtime_eventbus_design.md
git commit -m "docs: describe explicit sidebar identity resolution states"
```

---

## Task 8: Full verification

**Files:**
- Verify all touched files

**Step 1: Run full build**

Run:

```bash
AGENT_RUN_ID="codex-$(uuidgen | tr '[:upper:]' '[:lower:]')" mise run build
```

Expected:

```text
PASS, exit 0
```

**Step 2: Run full test suite**

Run:

```bash
AGENT_RUN_ID="codex-$(uuidgen | tr '[:upper:]' '[:lower:]')" mise run test
```

Expected:

```text
PASS, exit 0
```

**Step 3: Run lint**

Run:

```bash
AGENT_RUN_ID="codex-$(uuidgen | tr '[:upper:]' '[:lower:]')" mise run lint
```

Expected:

```text
PASS, exit 0
```

**Step 4: Native app verification**

Run:

```bash
pkill -9 -x AgentStudio || true
"/abs/path/to/built/AgentStudio" &
PID=$(pgrep -x AgentStudio)
peekaboo app switch --to "PID:$PID"
peekaboo see --app AgentStudio --json
```

Manual checks:

```text
1. Add watched folder with multiple repos
2. Verify all newly discovered repos remain under Scanning...
3. Verify they do not appear as weird temporary top-level groups
4. Verify confirmed local-only repos leave Scanning... and appear as normal groups
5. Verify remote repos leave Scanning... and merge into remote groups
6. Verify sidebar does not need resize to correct itself
```

**Step 5: Final commit**

```bash
git add Sources/AgentStudio Tests/AgentStudioTests docs/architecture
git commit -m "fix: resolve sidebar identity before grouping repos"
```

---

Plan complete and saved to `docs/plans/2026-03-06-sidebar-identity-resolution-fix.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
