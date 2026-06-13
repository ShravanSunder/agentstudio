# AgentStudio Git Data-Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Bridge foundation spec: [`docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`](../specs/2026-06-10-bridge-review-foundation.md)

**Goal:** Build a separate SwiftPM `agentstudio-git` package and wire it into AgentStudio as the fast, typed, actor-safe Git data plane needed by AgentStudio runtime enrichment and the Bridge review surface.

**Architecture:** `agentstudio-git` owns libgit2 lifecycle, read-only worktree/status/diff/content reads, and returns only Sendable Swift DTOs. AgentStudio keeps Worktrunk as the worktree command UX layer until a deliberate replacement and adds thin adapters for current Git enrichment. Bridge owns Bridge source-provider contracts, BridgeWeb TypeScript contracts, source endpoints, review checkpoints, review queries, filters, grouping, provenance, review packages, review deltas, review generations, and content handles. Bridge UI rendering, Pierre, Shiki, Trees, annotation bodies, patch application, worktree mutation, source mutation, and BridgeWeb scaffolding are outside this Git data-plane plan.

**Tech Stack:** Swift 6.2, SwiftPM, `ibrahimcetin/libgit2` 1.9.2 as the verified raw libgit2 baseline, Swift Testing, swift-format, SwiftLint, mise, actors.

---

## Spec

### Product Boundary

This foundation is the Git data layer for agent-first review and runtime enrichment. It must let AgentStudio read worktrees, status, branches, Git commits, refs, index state, working-tree state, diffs, line metadata, and file content efficiently. Bridge checkpoint collation, Bridge review package shape, BridgeWeb contracts, and Bridge resource URLs are owned by the Bridge foundation spec and Bridge execution plan.

This foundation does not edit source files, apply patches, approve or reject hunks, own a Monaco-style editor, or build the final viewer. The review surface is read-only. Commands request data, navigation, selection, filtering, and review metadata only.

### Research Basis For This Revision

This revision is grounded in live package and libgit2 research from 2026-06-08:

1. DeepWiki for `libgit2/libgit2` confirmed the relevant native primitives: `git_worktree_list`, `git_worktree_lookup`, `git_worktree_validate`, `git_status_options`, `git_diff_options`, blob/commit/reference APIs, and the `git_error_last` negative-return-code error model.
2. Perplexity research confirmed the strategic choice: a thin custom Swift data-plane wrapper over libgit2 is better for this app than SwiftGitX when the product needs exact status, diff, worktree, pathspec, ignore, and checkpoint behavior.
3. The local bakeoff runner proved `ibrahimcetin/libgit2` exposes a SwiftPM package product and module named `libgit2`, imported with `import libgit2`; the stale C-prefixed spelling in the earlier plan was wrong.
4. `swift-developer-tools/swift-libgit2` is useful research input because it documents memory-safe Swift bindings, `SwiftLibgit2`/`CLibgit2` imports, explicit thread-safety warnings, and bundled libgit2 1.9.1. It is not the first implementation dependency in this plan because its current manifest depends on a sibling local package path `../swift-libgit2-base`, which is not a clean single Git URL dependency for the overnight execution path.
5. Official libgit2 docs and headers require `git_libgit2_init` before repository APIs, symmetric `git_libgit2_shutdown`, immediate `git_error_last` capture only after negative returns, and explicit freeing of caller-owned objects such as `git_repository`, `git_worktree`, `git_status_list`, `git_diff`, and `git_strarray`.

Primary URLs used:

- `https://libgit2.org/docs/reference/main/status/git_status_options.html`
- `https://libgit2.org/docs/reference/main/errors/git_error_last.html`
- `https://libgit2.org/docs/reference/main/worktree/git_worktree_list.html`
- `https://swiftpackageregistry.com/swift-developer-tools/swift-libgit2`
- `https://github.com/swift-developer-tools/swift-libgit2`

### Current Branch Status After Plan Review

Tasks 1-8 are a greenfield Git data-plane lane. They create and integrate a new `agentstudio-git` package; they do not describe already-landed code in this AgentStudio branch.

The Bridge review foundation already exists on this branch under `Sources/AgentStudio/Features/Bridge/{Models,Runtime}/ReviewFoundation/`, and the canonical Bridge spec now owns the query-first `BridgeReview*` / `BridgeSourceEndpoint` / `BridgeReviewGeneration` contract model. This Git plan is therefore executable only through Task 8. Any later Bridge adapter, BridgeWeb, RPC, or documentation work belongs to the Bridge spec plus `docs/plans/2026-06-08-bridge-agent-review-foundation.md`.

Do not create a second `BridgeReviewSourceProvider`, a parallel `ReviewSource` protocol tree, a separate content-handle registry, Git-owned BridgeWeb contract files, or Git-owned Bridge review DTOs from this plan.

### Architecture Decisions

1. `agentstudio-git` is a separate SwiftPM repository published at `https://github.com/ShravanSunder/agentstudio-git.git`; the local `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git` checkout is a development workspace, not an AgentStudio package dependency.
2. AgentStudio imports `agentstudio-git` by remote SwiftPM revision, with `Package.resolved` pinned to `90bb17da9d7030f4ae954d45cf150a0f5fe6511b` until a later release-tag decision replaces the revision pin.
3. The package is the only runtime code that imports libgit2 modules.
4. Public package APIs expose Swift value types only: no `OpaquePointer`, no libgit2 C structs, no SwiftGitX types.
5. `AgentStudioGitClient` is an actor. Internal libgit2 sessions are non-Sendable and never cross actor boundaries.
6. No libgit2 object is used across an `await`. A function that borrows a libgit2 pointer completes the C calls, converts to Sendable DTOs, captures errors synchronously, releases resources, and returns.
7. All expensive Git, diff, checkpoint, hashing, classification, and packaging work runs off the MainActor. MainActor code may request work and publish compact results.
8. CLI Git remains an oracle in tests and a fallback only behind an explicit test seam. Runtime should not shell out for high-frequency status, diff, content, or worktree listing once this package is integrated.
9. Worktrunk remains the current worktree command/discovery UX layer until a separate decision replaces it. This plan adds read provider capability; it does not remove Worktrunk or add create/remove worktree commands.
10. `agentstudio-git` may expose worktree listing and validation in this foundation. Worktree creation, pruning, removal, checkout, and branch mutation belong to a later Git management command lane.
11. BridgeWeb contracts use discriminated unions, `readonly` data, Zod-derived types, and no `any`, but their canonical source is the Bridge plan and `Features/Bridge`, not `agentstudio-git`.
12. Bridge checkpoints are diff targets and collation inputs, not commits. Canonical automatic checkpoints are prompt/session boundaries from the runtime event stream. Time windows, folder filters, extension filters, file-role filters, and review-state filters are collation views over the same event-backed inputs.
13. Bridge content handles are endpoint-scoped, review-generation-scoped, role-scoped, and cache-keyed by the Bridge-owned `BridgeContentHandle` model. Swift stores loaded payloads through the Bridge-owned `BridgeContentStore`; React pulls file bytes lazily through the Bridge-owned resource URL contract.

### Required Public Swift Types In `agentstudio-git`

Create these files in the new repo:

```text
/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/
  AGENTS.md
  Package.swift
  .mise.toml
  .swift-format
  .swiftlint.yml
  Sources/
    AgentStudioGit/
      AgentStudioGitClient.swift
      Configuration/AgentStudioGitConfiguration.swift
      Errors/GitClientError.swift
      Runtime/LibGit2Runtime.swift
      Runtime/LibGit2RepositorySession.swift
      Worktrees/GitWorktreeSnapshot.swift
      Status/GitStatusSnapshot.swift
      Status/GitFileStatus.swift
      Branches/GitBranchSnapshot.swift
      Diffs/GitDiffEndpoint.swift
      Diffs/GitDiffRequest.swift
      Diffs/GitDiffPackage.swift
      Diffs/GitDiffFile.swift
      Diffs/GitDiffHunk.swift
      Diffs/GitDiffLine.swift
      Content/GitContentHandle.swift
      Content/GitContentPayload.swift
      Checkpoints/GitCheckpointInput.swift
      Internal/LibGit2Error.swift
      Internal/PathCanonicalizer.swift
  Tests/
    AgentStudioGitTests/
      Worktrees/GitWorktreeSnapshotTests.swift
      Status/GitStatusSnapshotTests.swift
      Diffs/GitDiffPackageTests.swift
      Content/GitContentHandleTests.swift
    AgentStudioGitIntegrationTests/
      Fixtures/GitFixtureBuilder.swift
      Fixtures/CliGitOracle.swift
      Worktrees/LibGit2WorktreeIntegrationTests.swift
      Status/LibGit2StatusIntegrationTests.swift
      Diffs/LibGit2DiffIntegrationTests.swift
      Content/LibGit2ContentIntegrationTests.swift
      Concurrency/AgentStudioGitClientConcurrencyTests.swift
    AgentStudioGitBenchmarks/
      GitBackendBenchmarkCommand.swift
```

The public model names and fields are part of the contract:

```swift
public actor AgentStudioGitClient {
    public init(configuration: AgentStudioGitConfiguration = .default) async throws

    public func worktrees(for repositoryPath: URL) async throws -> [GitWorktreeSnapshot]

    public func validateWorktree(
        repositoryPath: URL,
        name: String
    ) async throws -> GitWorktreeSnapshot

    public func status(
        for worktreePath: URL,
        options: GitStatusRequestOptions = .default
    ) async throws -> GitStatusSnapshot

    public func branches(for repositoryPath: URL) async throws -> [GitBranchSnapshot]

    public func compare(_ request: GitDiffRequest) async throws -> GitDiffPackage

    public func content(for handle: GitContentHandle) async throws -> GitContentPayload

    public func checkpointInput(for endpoint: GitDiffEndpoint) async throws -> GitCheckpointInput
}
```

```swift
public struct AgentStudioGitConfiguration: Sendable, Equatable {
    public var followGlobalIgnores: Bool
    public var detectRenames: Bool
    public var maxBlobBytes: Int
    public var maxDiffBytes: Int
    public var binaryDetectionBytes: Int

    public static let `default` = AgentStudioGitConfiguration(
        followGlobalIgnores: true,
        detectRenames: true,
        maxBlobBytes: 5_000_000,
        maxDiffBytes: 50_000_000,
        binaryDetectionBytes: 8_192
    )
}
```

```swift
public enum GitClientError: Error, Sendable, Equatable {
    case repositoryNotFound(path: String)
    case worktreeNotFound(name: String)
    case invalidReference(String)
    case invalidEndpoint(String)
    case contentTooLarge(path: String, bytes: Int, limit: Int)
    case binaryContent(path: String)
    case libgit2(code: Int32, klass: Int32, message: String)
    case cancelled
}
```

```swift
public struct GitWorktreeSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: GitWorktreeId
    public var name: String
    public var path: URL
    public var repositoryPath: URL
    public var headOid: GitObjectId?
    public var branchName: String?
    public var isMainWorktree: Bool
    public var isValid: Bool
    public var isLocked: Bool
    public var pruneReason: String?
}

public struct GitWorktreeId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String
}
```

```swift
public struct GitStatusSnapshot: Sendable, Codable, Equatable {
    public var repositoryPath: URL
    public var worktreePath: URL
    public var headOid: GitObjectId?
    public var branch: GitBranchSnapshot?
    public var remoteOriginURL: String?
    public var files: [GitFileStatus]
    public var counts: GitStatusCounts
    public var capturedAt: Date
    public var snapshotHash: String
}

public struct GitStatusRequestOptions: Sendable, Codable, Equatable {
    public var includeIgnored: Bool
    public var includeUntracked: Bool
    public var includeLineStats: Bool

    public static let `default` = GitStatusRequestOptions(
        includeIgnored: false,
        includeUntracked: true,
        includeLineStats: true
    )
}

public struct GitStatusCounts: Sendable, Codable, Equatable {
    public var changed: Int
    public var staged: Int
    public var untracked: Int
    public var ignored: Int
    public var insertions: Int
    public var deletions: Int
}

public struct GitFileStatus: Sendable, Codable, Equatable, Identifiable {
    public var id: GitFileId
    public var path: String
    public var oldPath: String?
    public var indexStatus: GitChangeKind
    public var workingTreeStatus: GitChangeKind
    public var isIgnored: Bool
    public var isBinary: Bool
    public var lineStats: GitLineStats?
}

public enum GitChangeKind: String, Sendable, Codable, Equatable, CaseIterable {
    case unmodified
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case untracked
    case ignored
    case conflicted
}

public struct GitLineStats: Sendable, Codable, Equatable {
    public var insertions: Int
    public var deletions: Int
}

public enum GitPathFilter: Sendable, Codable, Equatable {
    case all
    case include(paths: [String])
    case exclude(paths: [String])
    case includeAndExclude(include: [String], exclude: [String])
}

public struct GitFileMode: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
```

```swift
public enum GitDiffEndpoint: Sendable, Codable, Equatable, Hashable {
    case head(worktreePath: URL)
    case index(worktreePath: URL)
    case workingTree(worktreePath: URL)
    case reference(repositoryPath: URL, name: String)
    case commit(repositoryPath: URL, oid: GitObjectId)
    case checkpoint(GitCheckpointId)
}

public struct GitDiffRequest: Sendable, Codable, Equatable {
    public var base: GitDiffEndpoint
    public var head: GitDiffEndpoint
    public var options: GitDiffOptions
}

public struct GitDiffOptions: Sendable, Codable, Equatable {
    public var includeBinaryMetadata: Bool
    public var detectRenames: Bool
    public var contextLineCount: Int
    public var pathFilters: GitPathFilter

    public static let bridgeDefault = GitDiffOptions(
        includeBinaryMetadata: true,
        detectRenames: true,
        contextLineCount: 3,
        pathFilters: .all
    )
}
```

```swift
public struct GitDiffPackage: Sendable, Codable, Equatable, Identifiable {
    public var id: GitDiffPackageId
    public var base: GitDiffEndpoint
    public var head: GitDiffEndpoint
    public var files: [GitDiffFile]
    public var summary: GitDiffSummary
    public var generatedAt: Date
    public var packageHash: String
}

public struct GitDiffFile: Sendable, Codable, Equatable, Identifiable {
    public var id: GitFileId
    public var path: String
    public var oldPath: String?
    public var changeKind: GitChangeKind
    public var mode: GitFileMode
    public var oldMode: GitFileMode?
    public var isBinary: Bool
    public var contentHandle: GitContentHandle?
    public var oldContentHandle: GitContentHandle?
    public var hunks: [GitDiffHunk]
    public var lineStats: GitLineStats
}

public struct GitDiffHunk: Sendable, Codable, Equatable, Identifiable {
    public var id: GitHunkId
    public var oldStartLine: Int
    public var oldLineCount: Int
    public var newStartLine: Int
    public var newLineCount: Int
    public var sectionHeading: String?
    public var lines: [GitDiffLine]
}

public struct GitDiffLine: Sendable, Codable, Equatable, Identifiable {
    public var id: GitDiffLineId
    public var origin: GitDiffLineOrigin
    public var oldLine: Int?
    public var newLine: Int?
    public var content: String
    public var contentHash: String
}

public enum GitDiffLineOrigin: String, Sendable, Codable, Equatable {
    case context
    case addition
    case deletion
    case noNewlineMarker
}

public struct GitDiffSummary: Sendable, Codable, Equatable {
    public var filesChanged: Int
    public var insertions: Int
    public var deletions: Int
    public var binaryFiles: Int
}
```

```swift
public struct GitContentHandle: Sendable, Codable, Equatable, Hashable {
    public var id: GitContentHandleId
    public var endpoint: GitDiffEndpoint
    public var path: String
    public var objectId: GitObjectId?
    public var contentHash: String
    public var byteCount: Int
    public var mimeType: String
    public var isBinary: Bool
}

public struct GitContentHandleId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum GitContentPayload: Sendable, Equatable {
    case text(GitTextContent)
    case binaryMetadata(GitBinaryContentMetadata)
}

public struct GitTextContent: Sendable, Equatable {
    public var handle: GitContentHandle
    public var text: String
    public var encoding: String
}

public struct GitBinaryContentMetadata: Sendable, Equatable {
    public var handle: GitContentHandle
    public var byteCount: Int
    public var mimeType: String
}
```

```swift
public struct GitCheckpointId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GitCheckpointInput: Sendable, Codable, Equatable {
    public var endpoint: GitDiffEndpoint
    public var repositoryPath: URL
    public var worktreePath: URL?
    public var headOid: GitObjectId?
    public var indexHash: String?
    public var workingTreeSnapshotHash: String?
    public var fileContentHashes: [String: String]
    public var capturedAt: Date
}
```

### AgentStudio Integration Boundary

This Git plan creates only the Git data plane and the existing runtime Git enrichment adapter:

```text
Sources/AgentStudio/Core/RuntimeEventSystem/Git/
  AgentStudioGitWorkingTreeStatusProvider.swift
```

Bridge contracts, Bridge provider protocols, Bridge review packages, BridgeWeb TypeScript schemas, resource URLs, content stores, review generations, and review fixtures are defined by `docs/plans/2026-06-08-bridge-agent-review-foundation.md`.

If a future Bridge task needs `agentstudio-git`, it should add a Bridge-owned adapter after the Bridge plan's Task 0/Task 2 cutover has established the canonical `BridgeReview*` / `BridgeSourceEndpoint` / `BridgeReviewGeneration` contracts. Do not define those contracts in `agentstudio-git`, and do not create Git-owned BridgeWeb files.

### Test Naming Rules

Swift package tests use Swift Testing and end with `Tests.swift`.

BridgeWeb tests use these suffixes only:

```text
*.unit.test.ts
*.unit.test.tsx
*.integration.test.ts
*.integration.test.tsx
*.e2e.test.ts
*.e2e.test.tsx
```

Do not create unqualified `*.test.ts` or `*.test.tsx` files.

---

## Task 1: Scaffold Separate SwiftPM Git Package

**Files:**
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Package.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.mise.toml`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.swift-format`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.swiftlint.yml`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/AGENTS.md`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitTests/Scaffold/AgentStudioGitScaffoldTests.swift`

- [ ] **Step 1: Create the repo directory**

Run:

```bash
mkdir -p /Users/shravansunder/Documents/dev/project-dev/agentstudio-git
```

Expected: command exits 0 and the directory exists.

- [ ] **Step 2: Initialize Git**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git init
```

Expected: command exits 0.

- [ ] **Step 3: Copy AgentStudio Swift standards**

Run:

```bash
cp /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/.swift-format /Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.swift-format
cp /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/.swiftlint.yml /Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.swiftlint.yml
```

Expected: command exits 0 and both files exist.

- [ ] **Step 4: Write `Package.swift`**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Package.swift`:

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "agentstudio-git",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "AgentStudioGit",
            targets: ["AgentStudioGit"]
        ),
        .executable(
            name: "agentstudio-git-benchmark",
            targets: ["AgentStudioGitBenchmark"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AgentStudioGit",
            dependencies: [
                "libgit2",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "AgentStudioGitBenchmark",
            dependencies: [
                "AgentStudioGit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "AgentStudioGitTests",
            dependencies: ["AgentStudioGit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "AgentStudioGitIntegrationTests",
            dependencies: ["AgentStudioGit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
```

- [ ] **Step 5: Write `.mise.toml`**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/.mise.toml`:

```toml
[tasks.setup]
description = "Resolve SwiftPM dependencies"
run = "swift package resolve"

[tasks.build]
description = "Build package"
run = "swift build"

[tasks.test]
description = "Run all Swift Testing suites"
run = "swift test"

[tasks.test-fast]
description = "Run unit tests only"
run = "swift test --filter AgentStudioGitTests"

[tasks.test-integration]
description = "Run integration tests only"
run = "swift test --filter AgentStudioGitIntegrationTests"

[tasks.benchmark]
description = "Run Git backend benchmark command"
run = "swift run agentstudio-git-benchmark"

[tasks.format]
description = "Format Swift sources"
run = "swift-format format --recursive --in-place Package.swift Sources Tests"

[tasks.lint]
description = "Lint Swift sources"
run = [
  "swift-format lint --recursive Package.swift Sources Tests",
  "swiftlint lint --strict",
]
```

- [ ] **Step 6: Write package `AGENTS.md`**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/AGENTS.md`:

```markdown
# AgentStudio Git Package

This package is the fast Git data plane for AgentStudio. It wraps libgit2 behind Swift 6.2 actors and returns Sendable value types for worktrees, status, branches, diffs, content handles, and checkpoint inputs.

## Standards

- Swift 6.2 language mode.
- Swift Testing only: `@Suite`, `@Test`, `#expect`. No XCTest.
- No wall-clock sleeps in tests.
- No public `OpaquePointer`, libgit2 C structs, or SwiftGitX types.
- No Git or diff work on `@MainActor`.
- No `Task.detached` unless the code comments name the isolation reason.
- No source mutation APIs unless AgentStudio explicitly adds a separate write surface.
- Every libgit2 error must be captured synchronously on the same execution segment as the failed C call.
- Every public type must conform to `Sendable`; Codable is required for transport DTOs.

## Commands

```bash
mise run setup
mise run build
mise run test
mise run test-fast
mise run test-integration
mise run benchmark
mise run format
mise run lint
```
```

- [ ] **Step 7: Add initial client shell**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
import Foundation

public actor AgentStudioGitClient {
    public init(configuration: AgentStudioGitConfiguration = .default) async throws {
        _ = configuration
    }
}

public struct AgentStudioGitConfiguration: Sendable, Equatable {
    public var followGlobalIgnores: Bool
    public var detectRenames: Bool
    public var maxBlobBytes: Int
    public var maxDiffBytes: Int
    public var binaryDetectionBytes: Int

    public static let `default` = AgentStudioGitConfiguration(
        followGlobalIgnores: true,
        detectRenames: true,
        maxBlobBytes: 5_000_000,
        maxDiffBytes: 50_000_000,
        binaryDetectionBytes: 8_192
    )
}
```

- [ ] **Step 8: Add scaffold test**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitTests/Scaffold/AgentStudioGitScaffoldTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("AgentStudioGit scaffold")
struct AgentStudioGitScaffoldTests {
    @Test("client initializes with default configuration")
    func clientInitializesWithDefaultConfiguration() async throws {
        let client = try await AgentStudioGitClient()

        _ = client
        #expect(Bool(true))
    }
}
```

- [ ] **Step 9: Run initial package validation**

Run:

```bash
mise trust /Users/shravansunder/Documents/dev/project-dev/agentstudio-git
mise run setup
mise run test-fast
mise run lint
```

Expected: all commands exit 0.

- [ ] **Step 10: Commit scaffold**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "chore: scaffold AgentStudio Git package"
```

Expected: commit exits 0.

---

## Task 2: Add libgit2 Runtime And Error Boundary

**Files:**
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Runtime/LibGit2Runtime.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Runtime/LibGit2RepositorySession.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Errors/GitClientError.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Internal/LibGit2Error.swift`
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Runtime/LibGit2RuntimeIntegrationTests.swift`

**libgit2 safety rules this task must encode:**

- `git_libgit2_init()` is called before any repository API and `git_libgit2_shutdown()` is called symmetrically when the package runtime is released.
- Every negative libgit2 return code is converted to `GitClientError` immediately. `git_error_last()` is read only after a negative return, on the same execution segment, and the C pointer is never stored.
- Every pointer returned through an output pointer is freed by the matching libgit2 free function using `defer`: `git_repository_free`, `git_worktree_free`, `git_status_list_free`, `git_diff_free`, `git_blob_free`, `git_commit_free`, `git_tree_free`, and `git_strarray_free`.
- Raw libgit2 pointers stay private to one session method. They are not stored in public types, not returned, not captured by escaping closures, and not used across `await`.
- Actor methods convert libgit2 objects to Sendable Swift DTOs before returning.
- Status APIs must initialize `git_status_options` with `git_status_options_init`, set explicit include flags, and apply pathspecs through `git_strarray`.
- Diff APIs must initialize `git_diff_options`, set pathspecs, context line count, rename behavior, and max file size limits explicitly.
- Worktree reads use `git_worktree_list`, `git_worktree_lookup`, `git_worktree_validate`, `git_worktree_path`, and free every worktree/list result.

- [ ] **Step 1: Write failing runtime test**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Runtime/LibGit2RuntimeIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("libgit2 runtime")
struct LibGit2RuntimeIntegrationTests {
    @Test("opening a missing repository returns typed repositoryNotFound error")
    func missingRepositoryReturnsTypedError() async throws {
        let client = try await AgentStudioGitClient()
        let missingPath = URL(fileURLWithPath: "/tmp/agentstudio-git-missing-repository")

        await #expect(throws: GitClientError.repositoryNotFound(path: missingPath.path)) {
            _ = try await client.worktrees(for: missingPath)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mise run test-integration -- --filter "libgit2 runtime"
```

Expected: FAIL because `GitClientError` and `worktrees(for:)` do not exist.

- [ ] **Step 3: Add typed error**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Errors/GitClientError.swift`:

```swift
import Foundation

public enum GitClientError: Error, Sendable, Equatable {
    case repositoryNotFound(path: String)
    case worktreeNotFound(name: String)
    case invalidReference(String)
    case invalidEndpoint(String)
    case contentTooLarge(path: String, bytes: Int, limit: Int)
    case binaryContent(path: String)
    case libgit2(code: Int32, klass: Int32, message: String)
    case cancelled
}
```

- [ ] **Step 4: Add libgit2 error capture**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Internal/LibGit2Error.swift`:

```swift
import Foundation
import libgit2

struct LibGit2Error: Error, Sendable, Equatable {
    var code: Int32
    var klass: Int32
    var message: String

    static func capture(code: Int32) -> LibGit2Error {
        guard let lastError = git_error_last() else {
            return LibGit2Error(code: code, klass: 0, message: "libgit2 error \(code)")
        }

        let message = lastError.pointee.message.map { String(cString: $0) } ?? "libgit2 error \(code)"
        return LibGit2Error(code: code, klass: lastError.pointee.klass, message: message)
    }

    var clientError: GitClientError {
        .libgit2(code: code, klass: klass, message: message)
    }
}
```

- [ ] **Step 5: Add runtime lifecycle**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Runtime/LibGit2Runtime.swift`:

```swift
import Foundation
import libgit2

final class LibGit2Runtime: @unchecked Sendable {
    static let shared = LibGit2Runtime()

    private let lock = NSLock()
    private var retainCount = 0

    func retain() {
        lock.lock()
        defer { lock.unlock() }

        if retainCount == 0 {
            _ = git_libgit2_init()
        }
        retainCount += 1
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }

        guard retainCount > 0 else {
            return
        }
        retainCount -= 1
        if retainCount == 0 {
            _ = git_libgit2_shutdown()
        }
    }
}
```

- [ ] **Step 6: Add repository session**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Runtime/LibGit2RepositorySession.swift`:

```swift
import Foundation
import libgit2

final class LibGit2RepositorySession {
    private let path: URL
    private var repositoryPointer: OpaquePointer?

    init(path: URL) throws {
        self.path = path
        var pointer: OpaquePointer?
        let result = git_repository_open_ext(&pointer, path.path, 0, nil)
        guard result == 0, let pointer else {
            if result == GIT_ENOTFOUND {
                throw GitClientError.repositoryNotFound(path: path.path)
            }
            throw LibGit2Error.capture(code: result).clientError
        }
        repositoryPointer = pointer
    }

    deinit {
        if let repositoryPointer {
            git_repository_free(repositoryPointer)
        }
    }

    func withRepository<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let repositoryPointer else {
            throw GitClientError.repositoryNotFound(path: path.path)
        }
        return try body(repositoryPointer)
    }
}
```

- [ ] **Step 7: Store runtime in the actor**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
import Foundation

public actor AgentStudioGitClient {
    private let configuration: AgentStudioGitConfiguration
    private let runtime: LibGit2Runtime

    public init(configuration: AgentStudioGitConfiguration = .default) async throws {
        self.configuration = configuration
        runtime = .shared
        runtime.retain()
    }

    deinit {
        runtime.release()
    }

    public func worktrees(for repositoryPath: URL) async throws -> [GitWorktreeSnapshot] {
        _ = try LibGit2RepositorySession(path: repositoryPath)
        return []
    }
}

public struct AgentStudioGitConfiguration: Sendable, Equatable {
    public var followGlobalIgnores: Bool
    public var detectRenames: Bool
    public var maxBlobBytes: Int
    public var maxDiffBytes: Int
    public var binaryDetectionBytes: Int

    public static let `default` = AgentStudioGitConfiguration(
        followGlobalIgnores: true,
        detectRenames: true,
        maxBlobBytes: 5_000_000,
        maxDiffBytes: 50_000_000,
        binaryDetectionBytes: 8_192
    )
}
```

- [ ] **Step 8: Add temporary worktree snapshot type required by compile**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Worktrees/GitWorktreeSnapshot.swift`:

```swift
import Foundation

public struct GitWorktreeSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: GitWorktreeId
    public var name: String
    public var path: URL
    public var repositoryPath: URL
    public var headOid: GitObjectId?
    public var branchName: String?
    public var isMainWorktree: Bool
    public var isValid: Bool
    public var isLocked: Bool
    public var pruneReason: String?
}

public struct GitWorktreeId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GitObjectId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
```

- [ ] **Step 9: Run runtime tests**

Run:

```bash
mise run test-integration -- --filter "libgit2 runtime"
```

Expected: PASS.

- [ ] **Step 10: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS.

- [ ] **Step 11: Commit runtime boundary**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "feat: add libgit2 runtime boundary"
```

Expected: commit exits 0.

---

## Task 3: Implement Worktree Listing And Validation

**Files:**
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Worktrees/GitWorktreeSnapshot.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Internal/PathCanonicalizer.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Fixtures/GitFixtureBuilder.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Fixtures/CliGitOracle.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Worktrees/LibGit2WorktreeIntegrationTests.swift`

- [ ] **Step 1: Write failing worktree integration tests**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Worktrees/LibGit2WorktreeIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("libgit2 worktrees")
struct LibGit2WorktreeIntegrationTests {
    @Test("lists main and linked worktrees with canonical paths")
    func listsMainAndLinkedWorktrees() async throws {
        let fixture = try GitFixtureBuilder.makeRepositoryWithLinkedWorktree()
        let client = try await AgentStudioGitClient()

        let worktrees = try await client.worktrees(for: fixture.repositoryPath)

        let paths = Set(worktrees.map(\.path.resolvingSymlinksInPath))
        #expect(paths.contains(fixture.repositoryPath.resolvingSymlinksInPath))
        #expect(paths.contains(fixture.linkedWorktreePath.resolvingSymlinksInPath))
        #expect(worktrees.contains { $0.isMainWorktree })
        #expect(worktrees.contains { !$0.isMainWorktree && $0.name == "agent-worktree" })
    }

    @Test("validates linked worktree and reports canonical path")
    func validatesLinkedWorktreeAndReportsCanonicalPath() async throws {
        let fixture = try GitFixtureBuilder.makeRepositoryWithLinkedWorktree()
        let client = try await AgentStudioGitClient()

        let snapshot = try await client.validateWorktree(
            repositoryPath: fixture.repositoryPath,
            name: "agent-worktree"
        )

        #expect(snapshot.name == "agent-worktree")
        #expect(snapshot.isValid)
        #expect(snapshot.path.resolvingSymlinksInPath() == fixture.linkedWorktreePath.resolvingSymlinksInPath())
    }
}
```

- [ ] **Step 2: Add fixture builder**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Fixtures/GitFixtureBuilder.swift`:

```swift
import Foundation

struct GitFixture {
    var root: URL
    var repositoryPath: URL
    var linkedWorktreePath: URL
}

enum GitFixtureBuilder {
    static func makeRepository() throws -> GitFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-git-\(UUID().uuidString)", isDirectory: true)
        let repositoryPath = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)

        try runGit(["init"], in: repositoryPath)
        try runGit(["config", "user.email", "test@example.com"], in: repositoryPath)
        try runGit(["config", "user.name", "AgentStudio Test"], in: repositoryPath)
        try "first\n".write(to: repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "file.txt"], in: repositoryPath)
        try runGit(["commit", "-m", "initial"], in: repositoryPath)

        return GitFixture(root: root, repositoryPath: repositoryPath, linkedWorktreePath: root.appendingPathComponent("agent-worktree"))
    }

    static func makeRepositoryWithLinkedWorktree() throws -> GitFixture {
        let fixture = try makeRepository()
        try runGit(["worktree", "add", "-b", "agent-worktree", fixture.linkedWorktreePath.path], in: fixture.repositoryPath)
        return fixture
    }

    static func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "GitFixtureBuilder", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
mise run test-integration -- --filter "libgit2 worktrees"
```

Expected: FAIL because worktree APIs return empty results and `validateWorktree(repositoryPath:name:)` does not exist.

- [ ] **Step 4: Add path canonicalizer**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Internal/PathCanonicalizer.swift`:

```swift
import Foundation

enum PathCanonicalizer {
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
```

- [ ] **Step 5: Implement `worktrees(for:)` and `validateWorktree(repositoryPath:name:)`**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift` so the actor opens a repository session, calls `git_worktree_list`, `git_worktree_lookup`, `git_worktree_validate`, and `git_worktree_path`, and returns `GitWorktreeSnapshot` values. Resource release order must be local to the same function body.

Use these method signatures exactly:

```swift
public func worktrees(for repositoryPath: URL) async throws -> [GitWorktreeSnapshot]

public func validateWorktree(
    repositoryPath: URL,
    name: String
) async throws -> GitWorktreeSnapshot
```

The implementation must include main worktree plus linked worktrees. Main worktree id is `main:<canonical-repository-path>`. Linked worktree id is `linked:<worktree-name>:<canonical-worktree-path>`.

- [ ] **Step 6: Run worktree tests**

Run:

```bash
mise run test-integration -- --filter "libgit2 worktrees"
```

Expected: PASS.

- [ ] **Step 7: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS.

- [ ] **Step 8: Commit worktree support**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "feat: add libgit2 worktree support"
```

Expected: commit exits 0.

---

## Task 4: Implement Status, Branch, Ignore, And Ahead/Behind Reads

**Files:**
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Status/GitStatusSnapshot.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Status/GitFileStatus.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Branches/GitBranchSnapshot.swift`
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Status/LibGit2StatusIntegrationTests.swift`

- [ ] **Step 1: Write failing status tests**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Status/LibGit2StatusIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("libgit2 status")
struct LibGit2StatusIntegrationTests {
    @Test("reports staged unstaged untracked ignored counts and line stats")
    func reportsStatusCounts() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        try "tracked\nchanged\n".write(to: fixture.repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: fixture.repositoryPath.appendingPathComponent("new-file.swift"), atomically: true, encoding: .utf8)
        try "ignored.log\n".write(to: fixture.repositoryPath.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "ignored\n".write(to: fixture.repositoryPath.appendingPathComponent("ignored.log"), atomically: true, encoding: .utf8)
        try GitFixtureBuilder.runGit(["add", ".gitignore"], in: fixture.repositoryPath)

        let client = try await AgentStudioGitClient()
        let status = try await client.status(for: fixture.repositoryPath, options: .default)

        #expect(status.counts.changed >= 1)
        #expect(status.counts.staged >= 1)
        #expect(status.counts.untracked >= 1)
        #expect(status.files.contains { $0.path == "file.txt" && $0.workingTreeStatus == .modified })
        #expect(status.files.contains { $0.path == ".gitignore" && $0.indexStatus == .added })
        #expect(status.files.contains { $0.path == "new-file.swift" && $0.workingTreeStatus == .untracked })
        #expect(!status.files.contains { $0.path == "ignored.log" })
        #expect(!status.snapshotHash.isEmpty)
    }

    @Test("reports current branch and upstream ahead behind counts")
    func reportsBranchAheadBehind() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        let client = try await AgentStudioGitClient()

        let status = try await client.status(for: fixture.repositoryPath, options: .default)

        #expect(status.branch?.name == "main" || status.branch?.name == "master")
        #expect(status.branch?.headOid != nil)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
mise run test-integration -- --filter "libgit2 status"
```

Expected: FAIL because status types and methods do not exist.

- [ ] **Step 3: Add status and branch types**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Status/GitStatusSnapshot.swift` and `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Status/GitFileStatus.swift` with the public fields from the Spec section. Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Branches/GitBranchSnapshot.swift`:

```swift
import Foundation

public struct GitBranchSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var headOid: GitObjectId?
    public var upstreamName: String?
    public var aheadCount: Int
    public var behindCount: Int
    public var isCurrent: Bool
}
```

- [ ] **Step 4: Implement status**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
public func status(
    for worktreePath: URL,
    options: GitStatusRequestOptions = .default
) async throws -> GitStatusSnapshot
```

Implementation requirements:

- Use `git_status_list_new` with untracked enabled by default.
- Respect `.gitignore`, repo excludes, and global excludes when `followGlobalIgnores` is true.
- Map index and working tree statuses separately.
- Compute line stats with libgit2 diff APIs only when `includeLineStats` is true.
- Compute `snapshotHash` from repository path, worktree path, head oid, branch name, sorted file statuses, and line stats.
- Return paths relative to worktree root with `/` separators.

- [ ] **Step 5: Implement branch listing**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
public func branches(for repositoryPath: URL) async throws -> [GitBranchSnapshot]
```

Implementation requirements:

- Use libgit2 reference iteration.
- Include local branches.
- Mark current branch.
- Resolve head oid.
- Compute ahead/behind when upstream exists.

- [ ] **Step 6: Run status tests**

Run:

```bash
mise run test-integration -- --filter "libgit2 status"
```

Expected: PASS.

- [ ] **Step 7: Run all package tests**

Run:

```bash
mise run test
```

Expected: PASS.

- [ ] **Step 8: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS.

- [ ] **Step 9: Commit status support**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "feat: add libgit2 status and branch reads"
```

Expected: commit exits 0.

---

## Task 5: Implement Diff Packages With Stable Identity And Line Semantics

**Files:**
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffEndpoint.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffRequest.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffPackage.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffFile.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffHunk.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Diffs/GitDiffLine.swift`
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Diffs/LibGit2DiffIntegrationTests.swift`

- [ ] **Step 1: Write failing diff tests**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Diffs/LibGit2DiffIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("libgit2 diffs")
struct LibGit2DiffIntegrationTests {
    @Test("diff head to working tree preserves old and new line numbers")
    func diffHeadToWorkingTreePreservesLineNumbers() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        try "one\ntwo changed\nthree\nfour\n".write(to: fixture.repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let client = try await AgentStudioGitClient()

        let package = try await client.compare(
            GitDiffRequest(
                base: .head(worktreePath: fixture.repositoryPath),
                head: .workingTree(worktreePath: fixture.repositoryPath),
                options: .bridgeDefault
            )
        )

        let file = try #require(package.files.first { $0.path == "file.txt" })
        let lines = file.hunks.flatMap(\.lines)
        #expect(lines.contains { $0.origin == .deletion && $0.oldLine == 2 && $0.newLine == nil && $0.content == "two" })
        #expect(lines.contains { $0.origin == .addition && $0.oldLine == nil && $0.newLine == 2 && $0.content == "two changed" })
    }

    @Test("diff reports rename delete binary and no newline marker")
    func diffReportsRenameDeleteBinaryAndNoNewlineMarker() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        try GitFixtureBuilder.runGit(["mv", "file.txt", "renamed.txt"], in: fixture.repositoryPath)
        try "renamed without newline".write(to: fixture.repositoryPath.appendingPathComponent("renamed.txt"), atomically: true, encoding: .utf8)
        let binaryData = Data([0, 1, 2, 3, 4, 5])
        try binaryData.write(to: fixture.repositoryPath.appendingPathComponent("image.bin"))
        try GitFixtureBuilder.runGit(["add", "renamed.txt", "image.bin"], in: fixture.repositoryPath)

        let client = try await AgentStudioGitClient()
        let package = try await client.compare(
            GitDiffRequest(
                base: .head(worktreePath: fixture.repositoryPath),
                head: .index(worktreePath: fixture.repositoryPath),
                options: .bridgeDefault
            )
        )

        #expect(package.files.contains { $0.path == "renamed.txt" && $0.changeKind == .renamed && $0.oldPath == "file.txt" })
        #expect(package.files.contains { $0.path == "image.bin" && $0.isBinary })
        #expect(package.files.flatMap(\.hunks).flatMap(\.lines).contains { $0.origin == .noNewlineMarker })
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
mise run test-integration -- --filter "libgit2 diffs"
```

Expected: FAIL because diff types and `compare` do not exist.

- [ ] **Step 3: Add public diff types**

Create the `Diffs/` files using the public fields from the Spec section. Stable identities must be deterministic:

```swift
public struct GitDiffPackageId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GitFileId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GitHunkId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GitDiffLineId: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
```

- [ ] **Step 4: Implement diff endpoint resolution**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
public func compare(_ request: GitDiffRequest) async throws -> GitDiffPackage
```

Endpoint rules:

- `.head(worktreePath)` resolves to the worktree HEAD tree.
- `.index(worktreePath)` resolves to the worktree index.
- `.workingTree(worktreePath)` resolves to workdir state.
- `.reference(repositoryPath, name)` resolves named ref to tree.
- `.commit(repositoryPath, oid)` resolves commit oid to tree.
- `.checkpoint` is accepted by type but returns `.invalidEndpoint("checkpoint resolution is owned by AgentStudio")` inside this package.

- [ ] **Step 5: Implement line mapping**

Inside diff callbacks, track both old and new line counters:

```swift
switch origin {
case GIT_DIFF_LINE_CONTEXT:
    oldLine = currentOldLine
    newLine = currentNewLine
    currentOldLine += 1
    currentNewLine += 1
case GIT_DIFF_LINE_DELETION:
    oldLine = currentOldLine
    newLine = nil
    currentOldLine += 1
case GIT_DIFF_LINE_ADDITION:
    oldLine = nil
    newLine = currentNewLine
    currentNewLine += 1
case GIT_DIFF_LINE_CONTEXT_EOFNL, GIT_DIFF_LINE_ADD_EOFNL, GIT_DIFF_LINE_DEL_EOFNL:
    oldLine = nil
    newLine = nil
default:
    oldLine = nil
    newLine = nil
}
```

Expected DTO behavior:

- Deleted lines have `oldLine` and nil `newLine`.
- Added lines have nil `oldLine` and `newLine`.
- Context lines have both.
- No-newline markers have nil line numbers and `origin == .noNewlineMarker`.

- [ ] **Step 6: Run diff tests**

Run:

```bash
mise run test-integration -- --filter "libgit2 diffs"
```

Expected: PASS.

- [ ] **Step 7: Run all package tests and lint**

Run:

```bash
mise run test
mise run lint
```

Expected: both commands PASS.

- [ ] **Step 8: Commit diff package support**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "feat: add typed diff packages"
```

Expected: commit exits 0.

---

## Task 6: Implement Content Handles And Payload Loading

**Files:**
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Content/GitContentHandle.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Content/GitContentPayload.swift`
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Content/LibGit2ContentIntegrationTests.swift`

- [ ] **Step 1: Write failing content tests**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Content/LibGit2ContentIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("libgit2 content handles")
struct LibGit2ContentIntegrationTests {
    @Test("loads text content by handle for head and working tree")
    func loadsTextContentByHandle() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        try "changed\n".write(to: fixture.repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let client = try await AgentStudioGitClient()
        let package = try await client.compare(
            GitDiffRequest(
                base: .head(worktreePath: fixture.repositoryPath),
                head: .workingTree(worktreePath: fixture.repositoryPath),
                options: .bridgeDefault
            )
        )
        let file = try #require(package.files.first { $0.path == "file.txt" })
        let handle = try #require(file.contentHandle)

        let payload = try await client.content(for: handle)

        guard case .text(let textContent) = payload else {
            Issue.record("expected text payload")
            return
        }
        #expect(textContent.text == "changed\n")
        #expect(textContent.handle == handle)
    }

    @Test("rejects oversized text content with typed error")
    func rejectsOversizedTextContent() async throws {
        let configuration = AgentStudioGitConfiguration(
            followGlobalIgnores: true,
            detectRenames: true,
            maxBlobBytes: 4,
            maxDiffBytes: 50_000_000,
            binaryDetectionBytes: 8_192
        )
        let fixture = try GitFixtureBuilder.makeRepository()
        try "changed\n".write(to: fixture.repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let client = try await AgentStudioGitClient(configuration: configuration)
        let package = try await client.compare(
            GitDiffRequest(
                base: .head(worktreePath: fixture.repositoryPath),
                head: .workingTree(worktreePath: fixture.repositoryPath),
                options: .bridgeDefault
            )
        )
        let file = try #require(package.files.first { $0.path == "file.txt" })
        let handle = try #require(file.contentHandle)

        await #expect(throws: GitClientError.contentTooLarge(path: "file.txt", bytes: 8, limit: 4)) {
            _ = try await client.content(for: handle)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
mise run test-integration -- --filter "libgit2 content handles"
```

Expected: FAIL because content types and `content(for:)` do not exist.

- [ ] **Step 3: Add content types**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Content/GitContentHandle.swift` and `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/Content/GitContentPayload.swift` using the public fields from the Spec section.

- [ ] **Step 4: Populate handles from diff packages**

Modify diff package creation so each non-binary file receives:

```swift
GitContentHandle(
    id: GitContentHandleId(rawValue: "\(packageId.rawValue):head:\(fileId.rawValue)"),
    endpoint: request.head,
    path: path,
    objectId: resolvedObjectId,
    contentHash: contentHash,
    byteCount: byteCount,
    mimeType: "text/plain",
    isBinary: false
)
```

The `oldContentHandle` uses `base` instead of `head`.

- [ ] **Step 5: Implement content loading**

Modify `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGit/AgentStudioGitClient.swift`:

```swift
public func content(for handle: GitContentHandle) async throws -> GitContentPayload
```

Rules:

- Blob content comes from object id when `objectId` exists.
- Working tree content comes from the canonical worktree path and relative file path.
- If byte count exceeds `configuration.maxBlobBytes`, throw `.contentTooLarge`.
- If binary content is requested, return `.binaryMetadata` rather than decoding text.
- Text content must verify `contentHash` before returning.

- [ ] **Step 6: Run content tests**

Run:

```bash
mise run test-integration -- --filter "libgit2 content handles"
```

Expected: PASS.

- [ ] **Step 7: Run package validation**

Run:

```bash
mise run test
mise run lint
```

Expected: both commands PASS.

- [ ] **Step 8: Commit content handles**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "feat: add content handles"
```

Expected: commit exits 0.

---

## Task 7: Add CLI Parity Fixtures And Benchmark Harness

**Files:**
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Fixtures/CliGitOracle.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGitBenchmark/GitBackendBenchmarkCommand.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Parity/CliParityIntegrationTests.swift`

- [ ] **Step 1: Add CLI oracle**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Fixtures/CliGitOracle.swift`:

```swift
import Foundation

enum CliGitOracle {
    static func statusPorcelain(in directory: URL) throws -> String {
        try run(["status", "--porcelain=v1", "--branch", "--untracked-files=normal"], in: directory)
    }

    static func diffNameStatus(in directory: URL, arguments: [String]) throws -> String {
        try run(["diff", "--name-status"] + arguments, in: directory)
    }

    static func worktreePorcelain(in directory: URL) throws -> String {
        try run(["worktree", "list", "--porcelain"], in: directory)
    }

    private static func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "CliGitOracle", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 2: Add parity tests**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Tests/AgentStudioGitIntegrationTests/Parity/CliParityIntegrationTests.swift`:

```swift
import AgentStudioGit
import Foundation
import Testing

@Suite("CLI parity")
struct CliParityIntegrationTests {
    @Test("worktree list includes every CLI worktree path")
    func worktreeListMatchesCliPaths() async throws {
        let fixture = try GitFixtureBuilder.makeRepositoryWithLinkedWorktree()
        let client = try await AgentStudioGitClient()

        let packagePaths = Set(try await client.worktrees(for: fixture.repositoryPath).map(\.path.resolvingSymlinksInPath.path))
        let cliOutput = try CliGitOracle.worktreePorcelain(in: fixture.repositoryPath)

        #expect(cliOutput.contains(fixture.repositoryPath.path))
        #expect(cliOutput.contains(fixture.linkedWorktreePath.path))
        #expect(packagePaths.contains(fixture.repositoryPath.resolvingSymlinksInPath.path))
        #expect(packagePaths.contains(fixture.linkedWorktreePath.resolvingSymlinksInPath.path))
    }

    @Test("status file paths match CLI changed file paths")
    func statusPathsMatchCliChangedPaths() async throws {
        let fixture = try GitFixtureBuilder.makeRepository()
        try "changed\n".write(to: fixture.repositoryPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: fixture.repositoryPath.appendingPathComponent("new.swift"), atomically: true, encoding: .utf8)
        let client = try await AgentStudioGitClient()

        let statusPaths = Set(try await client.status(for: fixture.repositoryPath).files.map(\.path))
        let cliStatus = try CliGitOracle.statusPorcelain(in: fixture.repositoryPath)

        #expect(cliStatus.contains("file.txt"))
        #expect(cliStatus.contains("new.swift"))
        #expect(statusPaths.contains("file.txt"))
        #expect(statusPaths.contains("new.swift"))
    }
}
```

- [ ] **Step 3: Add benchmark command**

Create `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git/Sources/AgentStudioGitBenchmark/GitBackendBenchmarkCommand.swift`:

```swift
import AgentStudioGit
import ArgumentParser
import Foundation

@main
struct GitBackendBenchmarkCommand: AsyncParsableCommand {
    @Option(name: .long)
    var repositoryPath: String?

    mutating func run() async throws {
        let path = repositoryPath.map(URL.init(fileURLWithPath:)) ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let client = try await AgentStudioGitClient()

        let startedAt = ContinuousClock.now
        _ = try await client.worktrees(for: path)
        let worktreeDuration = startedAt.duration(to: ContinuousClock.now)

        let statusStartedAt = ContinuousClock.now
        _ = try await client.status(for: path)
        let statusDuration = statusStartedAt.duration(to: ContinuousClock.now)

        print("worktree.list.ms=\(milliseconds(worktreeDuration))")
        print("status.ms=\(milliseconds(statusDuration))")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds * 1_000) + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
```

- [ ] **Step 4: Run parity and benchmark**

Run:

```bash
mise run test-integration -- --filter "CLI parity"
mise run benchmark -- --repository-path /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
```

Expected: parity tests PASS and benchmark prints `worktree.list.ms=` plus `status.ms=`.

- [ ] **Step 5: Run package validation**

Run:

```bash
mise run test
mise run lint
```

Expected: both commands PASS.

- [ ] **Step 6: Commit parity and benchmarks**

Run:

```bash
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git add .
git -C /Users/shravansunder/Documents/dev/project-dev/agentstudio-git commit -m "test: add git parity and benchmark coverage"
```

Expected: commit exits 0.

---

## Task 8: Integrate Package Into AgentStudio Git Projector

**Files:**
- Modify: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Package.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Sources/AgentStudio/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift`
- Create: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitProviderFixture.swift`
- Test: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProviderTests.swift`

- [ ] **Step 1: Write failing provider test**

Create `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProviderTests.swift`:

```swift
import AgentStudioGit
@testable import AgentStudio
import Foundation
import Testing

@Suite("AgentStudioGitWorkingTreeStatusProvider")
struct AgentStudioGitWorkingTreeStatusProviderTests {
    @Test("maps package status snapshot into existing GitWorkingTreeStatus")
    func mapsPackageStatusSnapshot() async throws {
        let fixture = try AgentStudioGitProviderFixture.makeRepositoryWithModification()
        let provider = try await AgentStudioGitWorkingTreeStatusProvider()

        let status = try #require(await provider.status(for: fixture.repositoryPath))

        #expect(status.changedCount >= 1)
        #expect(status.insertions >= 1)
        #expect(status.branchName?.isEmpty == false)
    }
}
```

- [ ] **Step 2: Add AgentStudio Git test fixture**

Create `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitProviderFixture.swift`:

```swift
import Foundation

struct AgentStudioGitProviderFixture {
    var root: URL
    var repositoryPath: URL
    var repositoryId: String
    var worktreeId: String
    var headOid: String

    static func makeRepositoryWithModification() throws -> AgentStudioGitProviderFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-provider-\(UUID().uuidString)", isDirectory: true)
        let repositoryPath = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)

        try runGit(["init"], in: repositoryPath)
        try runGit(["config", "user.email", "test@example.com"], in: repositoryPath)
        try runGit(["config", "user.name", "AgentStudio Test"], in: repositoryPath)
        try FileManager.default.createDirectory(at: repositoryPath.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "let value = 1\n".write(to: repositoryPath.appendingPathComponent("Sources/File.swift"), atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/File.swift"], in: repositoryPath)
        try runGit(["commit", "-m", "initial"], in: repositoryPath)
        let headOid = try runGitOutput(["rev-parse", "HEAD"], in: repositoryPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "let value = 2\n".write(to: repositoryPath.appendingPathComponent("Sources/File.swift"), atomically: true, encoding: .utf8)

        return AgentStudioGitProviderFixture(
            root: root,
            repositoryPath: repositoryPath,
            repositoryId: repositoryPath.resolvingSymlinksInPath().path,
            worktreeId: repositoryPath.resolvingSymlinksInPath().path,
            headOid: headOid
        )
    }

    static func runGit(_ arguments: [String], in directory: URL) throws {
        _ = try runGitOutput(arguments, in: directory)
    }

    static func runGitOutput(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "AgentStudioGitProviderFixture", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 3: Run test to verify failure**

Run from AgentStudio root:

```bash
mise run test -- --filter "AgentStudioGitWorkingTreeStatusProvider"
```

Expected: FAIL because provider does not exist.

- [x] **Step 4: Add remote package dependency**

Modify `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Package.swift`:

```swift
.package(
    url: "https://github.com/ShravanSunder/agentstudio-git.git",
    revision: "90bb17da9d7030f4ae954d45cf150a0f5fe6511b"
),
```

Add product dependency to `AgentStudio` and test targets:

```swift
.product(name: "AgentStudioGit", package: "agentstudio-git"),
```

Do not wire hosted libgit2 artifact environment in AgentStudio. The pinned `agentstudio-git` revision owns the public hosted binary target default; AgentStudio should not duplicate artifact URL/checksum configuration.

- [ ] **Step 5: Add provider adapter**

Create `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/Sources/AgentStudio/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift`:

```swift
import AgentStudioGit
import Foundation

struct AgentStudioGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private let client: AgentStudioGitClient

    init(client: AgentStudioGitClient? = nil) async throws {
        if let client {
            self.client = client
        } else {
            self.client = try await AgentStudioGitClient()
        }
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        do {
            let snapshot = try await client.status(for: rootPath)
            let summary = GitWorkingTreeSummary(
                changed: snapshot.counts.changed,
                staged: snapshot.counts.staged,
                untracked: snapshot.counts.untracked,
                linesAdded: snapshot.counts.insertions,
                linesDeleted: snapshot.counts.deletions,
                aheadCount: snapshot.branch?.aheadCount,
                behindCount: snapshot.branch?.behindCount,
                hasUpstream: snapshot.branch?.upstreamName != nil
            )
            return GitWorkingTreeStatus(
                summary: summary,
                branch: snapshot.branch?.name,
                originResolution: snapshot.remoteOriginURL.map(GitOriginResolution.resolved) ?? .awaitingResolution
            )
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 6: Run provider test**

Run:

```bash
mise run test -- --filter "AgentStudioGitWorkingTreeStatusProvider"
```

Expected: PASS.

- [ ] **Step 7: Run Bridge/Git focused tests**

Run:

```bash
mise run test -- --filter "GitWorkingDirectoryProjector"
mise run test -- --filter "Bridge"
```

Expected: both commands PASS.

- [ ] **Step 8: Run AgentStudio lint**

Run:

```bash
mise run lint
```

Expected: PASS.

- [ ] **Step 9: Commit AgentStudio adapter**

Run:

```bash
git add Package.swift Sources/AgentStudio/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitProviderFixture.swift Tests/AgentStudioTests/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProviderTests.swift
git commit -m "feat: add AgentStudio Git status provider"
```

Expected: commit exits 0.

---

## Deferred Bridge Integration

Execution of this Git data-plane plan stops after Task 8.

The previous draft had Bridge adapter, BridgeWeb, RPC, and Bridge documentation tasks here. Those tasks are intentionally removed from the executable path because the canonical Bridge spec owns the query-first `BridgeReview*` / `BridgeSourceEndpoint` / `BridgeReviewGeneration` model.

Bridge-owned follow-up work lives in:

```text
docs/superpowers/specs/2026-06-10-bridge-review-foundation.md
docs/plans/2026-06-08-bridge-agent-review-foundation.md
```

When Bridge is ready to consume the Git data plane, create a new Bridge-owned task that:

1. imports `AgentStudioGit`,
2. conforms to the canonical Bridge provider protocol from the Bridge plan,
3. maps Git DTOs into Bridge-owned review DTOs,
4. keeps BridgeWeb TypeScript contracts generated from Bridge fixtures,
5. preserves Worktrunk as the current worktree UX layer unless a separate Git management plan replaces it.

Do not execute stale BridgeDiff, raw epoch, `agentstudio://resource/file`, or `foundation/diff-package` instructions from older drafts of this plan.

---

## Definition Of Done

The foundation is complete when all of these are true:

1. `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git` exists as a separate SwiftPM repo.
2. `agentstudio-git` builds and tests with Swift 6.2 and Swift Testing only.
3. `agentstudio-git` exposes no public libgit2 pointers or SwiftGitX types.
4. Worktree listing/validation, status, branches, diffs, content handles, and checkpoint inputs are covered by unit and integration tests.
5. Diff lines preserve separate `oldLine` and `newLine` semantics.
6. Git ignores, repo excludes, and global excludes are respected in status and filtering.
7. AgentStudio imports the package through the remote `agentstudio-git` revision; the pinned SDK revision owns the hosted libgit2 artifact URL/checksum default, so AgentStudio does not duplicate artifact environment configuration.
8. `GitWorkingDirectoryProjector` can use `AgentStudioGitWorkingTreeStatusProvider` behind the existing provider seam.
9. The plan contains no executable Bridge adapter, BridgeWeb, Bridge RPC, or Bridge contract tasks after Task 8.
10. Package validation passes: `mise run test`, `mise run lint`, and benchmark command.
11. AgentStudio validation passes for the Git adapter lane: `git diff --check`, `mise run test -- --filter "Git"`, and `mise run lint`.

## Notes For Execution Agents

- Start in a clean worktree for AgentStudio and a fresh separate repo for `agentstudio-git`.
- Use TDD task by task.
- Do not replace Worktrunk command UX during this plan.
- Do not fork SwiftGitX for this plan.
- Do not create Bridge domain DTOs, BridgeWeb contracts, Bridge resource URL contracts, or a parallel review-source folder from this Git plan.
- For Bridge contract work, stop and use `docs/plans/2026-06-08-bridge-agent-review-foundation.md`.
- Keep test files small and named by behavior.
- If a validation failure is outside this foundation, stop edits and report the exact failing command, exit code, and first relevant error block.
