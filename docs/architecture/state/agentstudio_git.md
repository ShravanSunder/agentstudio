# agentstudio-git

> **Owns:** how AgentStudio **links** the external `agentstudio-git` Swift
> package and which adapters consume it.
> **Does not own:** Ghostty/zmx vendor builds, EventBus hop shape, Forge remote
> API, or Bridge Web rendering.
> **Companions:** [Workspace Data Architecture](workspace_data_architecture.md)
> (git facts on the bus), [Bridge Native Runtime](../bridge/bridge_native_runtime_architecture.md)
> (Review/File reads), [SwiftPM Module Graph](../structure/directory_structure.md#swiftpm-module-graph).

<a id="agentstudio-git"></a>
## What it is

[`agentstudio-git`](https://github.com/ShravanSunder/agentstudio-git) is a
**separate Swift package**. AgentStudio consumes the `AgentStudioGit` product.
It is **not** a git submodule, **not** a Ghostty/zmx vendor, and **not** a
license to shell out to `git` or `wt`.

Git policy and libgit2-backed reads live in that package. This repo owns
adapters, demand/admission, EventBus facts, and Bridge mapping.

## How AgentStudio links it

[`Package.swift`](../../../Package.swift) declares:

```swift
.package(
    url: "https://github.com/ShravanSunder/agentstudio-git.git",
    revision: "<pinned commit>"
)
```

The pin is a **git revision**, not a version range. Bump Git behavior by
changing that revision (and `Package.resolved`) in the same change that needs
the new package API. Do **not** use `mise run setup --use-local-vendors` for
this package; that flag is Ghostty/zmx vendor work only.

Product import: `import AgentStudioGit`.

Targets that depend on `.product(name: "AgentStudioGit", package: "agentstudio-git")`
today:

| Target | Why |
| --- | --- |
| `AgentStudioInfrastructure` | `RepoScannerGitDiscoveryClient` |
| `AgentStudioCore` | `GitWorkingDirectoryProjector` / `AgentStudioGitWorkingTreeStatusProvider` |
| `AgentStudioBridge` | `AgentStudioGitBridgeReviewDataClient` |
| Matching test targets | Fakes and adapter tests |

Verify the list in `Package.swift`; do not add a fourth production consumer
without an adapter that already exists for that job.

## How it works in this app

```text
FilesystemActor (FSEvents, no Git)
  -> EventBus filesystem facts
  -> GitWorkingDirectoryProjector
       -> GitWorkingTreeStatusProvider
            -> AgentStudioGitWorkingTreeStatusProvider
                 -> LibGit2AgentStudioGitLocalClient.status(...)
       -> GitWorkingDirectoryEvent on EventBus

RepoScanner
  -> RepoScannerGitDiscoveryClient
       -> LibGit2AgentStudioGitDiscoveryReadClient
  -> topology (clone vs linked worktree)

Bridge File/Review
  -> AgentStudioGitBridgeReviewDataClient
       -> LibGit2AgentStudioGitLocalClient (diff/status/content)
       -> BridgeGitReadScheduler (queue, not Git policy)
```

Default local client is `LibGit2AgentStudioGitLocalClient`. Discovery uses
`LibGit2AgentStudioGitDiscoveryReadClient` and must not grow status, remote, or
mutation capabilities.

`@concurrent nonisolated` on status helpers is an **I/O isolation** rule (do
not block the actor executor). It is not permission to spawn `git`.

## Forbidden

- Production `git` / `wt` / Worktrunk CLI as a data plane
- TypeScript `git` except marked Vite dev-server or test-fixture utilities
- Duplicating Git semantics in AgentStudio (pathspec fold, worktree
  classification, ignore) when `agentstudio-git` already owns them
- Treating this package like Ghostty: no submodule hydrate, no vendor worktree
  flag

## Files to load

| File | Owns |
| --- | --- |
| [`Package.swift`](../../../Package.swift) | URL + revision pin and target product deps |
| [`AgentStudioGitWorkingTreeStatusProvider.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift) | Status adapter + timeout/in-flight policy |
| [`GitWorkingDirectoryProjector.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift) | Demand-gated local git facts |
| [`RepoScannerGitDiscoveryClient.swift`](../../../Sources/AgentStudio/Infrastructure/RepoScannerGitDiscoveryClient.swift) | Discovery-only Git reads for scanning |
| [`AgentStudioGitBridgeReviewDataClient.swift`](../../../Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/AgentStudioGitBridgeReviewDataClient.swift) | Bridge Git DTO mapping |
| [`FilesystemGitPipeline.swift`](../../../Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift) | Composition: filesystem + projector + forge |
