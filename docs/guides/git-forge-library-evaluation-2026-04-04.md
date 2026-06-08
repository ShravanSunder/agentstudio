# Git + Forge Runtime Evaluation: SwiftGitX vs Zig FFI

Date: 2026-05-03  
Audience: Agent Studio maintainers working on `GitWorkingDirectoryProjector`, `ShellGitWorkingTreeStatusProvider`, and `ForgeActor`.

---

## Executive Summary

For this codebase, **SwiftGitX is the right first experiment for local Git projection**, while **forge enrichment should stay on its own provider track**.

- Use SwiftGitX only to replace shell parsing in `GitWorkingTreeStatusProvider`.
- Keep `ForgeStatusProvider` independent; PR counts are forge API concerns, not Git object concerns.
- Defer Zig unless profiling proves SwiftGitX/libgit2 cannot meet latency/reliability goals.

---

## Current Runtime Responsibilities (Grounded in Code)

## 1) Local Git projection path

Pipeline composition currently wires:
- `FilesystemActor` (fact ingestion)
- `GitWorkingDirectoryProjector` (derives git facts)
- `ForgeActor` (forge enrichment)

This split is instantiated in `FilesystemGitPipeline` via independent provider seams:
- `gitWorkingTreeProvider: any GitWorkingTreeStatusProvider`
- `forgeStatusProvider: any ForgeStatusProvider`

### What local Git currently executes

`ShellGitWorkingTreeStatusProvider` performs three commands:

1. `git status --porcelain=v1 --branch --untracked-files=normal`
   - Parses branch name, ahead/behind, staged/changed/untracked counts.
2. `git diff --shortstat HEAD --`
   - Parses insertion/deletion line deltas.
3. `git config --get remote.origin.url`
   - Resolves origin URL (or confirms absence).

### What the projector emits from this

`GitWorkingDirectoryProjector` converts provider output into event-bus facts:
- `.snapshotChanged(...)`
- `.branchChanged(...)` when branch transitions
- `.originChanged(...)` / `.originUnavailable(...)`

These facts are idempotent/coalesced and tied to worktree/repo identity.

## 2) Forge enrichment path

`GitHubCLIForgeStatusProvider` executes:
- `gh pr list --repo <slug> --state open --json headRefName --limit 200`

`ForgeActor` maps the result into:
- `.pullRequestCountsChanged(repoId:countsByBranch:)`
- `.refreshFailed(...)` on provider failure

It also tracks branch scope from git projector facts and polls periodically.

**Key implication:** forge behavior depends on remote host API/auth (`gh`) and is not replaced by a Git library swap.

---

## Capability Fit Analysis

## SwiftGitX fit (for Git actor only)

### Likely wins

1. **Typed access instead of CLI text parsing**
   - Reduces parser fragility around porcelain output formatting.

2. **Better error taxonomy opportunity**
   - Can map libgit2/SwiftGitX failures to structured provider errors instead of command stderr heuristics.

3. **Potential latency/CPU improvements**
   - Avoiding process spawn per refresh can reduce overhead under many watched worktrees.

### Practical caveats

1. **Coverage parity work required**
   - Need equivalent computations for:
     - branch name and ahead/behind
     - staged/changed/untracked summary
     - line add/delete counts
     - origin URL resolution

2. **Behavior parity must be proven**
   - Existing tests encode event semantics (branch transitions, origin changes, shutdown behavior).
   - The new provider must keep payload shape/timing expectations unchanged.

3. **No forge replacement**
   - SwiftGitX cannot provide PR counts by branch from GitHub/GitLab APIs.

---

## Zig FFI fit (for local Git)

### Where Zig can help
- If you need highly specialized, profiled native implementations beyond Swift/libgit2 ergonomics.

### Why this is higher-risk now

1. **Build/distribution complexity**
   - Additional artifact management, ABI boundaries, and platform packaging.

2. **Debugging and ownership overhead**
   - Harder crash forensics and memory ownership verification across Swift ↔ C ABI boundary.

3. **Same forge gap remains**
   - Still requires a separate forge API provider for PR counts.

**Conclusion:** Zig is a second-stage optimization path, not the first migration candidate.

---

## Recommended Migration Strategy

## Step 1 — SwiftGitX prototype behind existing seam

Introduce:
- `SwiftGitXWorkingTreeStatusProvider: GitWorkingTreeStatusProvider`

Do **not** change actor/event architecture; only swap provider implementation.

## Step 2 — Keep forge provider independent

Retain current `ForgeStatusProvider` behavior (`gh`-based) during Git provider experiment.

## Step 3 — Validate with hard acceptance criteria

A provider swap is acceptable only if all are met:

1. **Correctness parity**
   - Same branch/origin transition semantics as current provider.

2. **Operational reliability**
   - No regression in failure handling (`origin absent`, transient errors, cancellation/shutdown).

3. **Performance non-regression (or improvement)**
   - Equal or lower refresh latency and CPU under representative worktree counts.

4. **No architecture drift**
   - Preserve current event-bus flow and store/coordinator boundaries.

---

## Decision

- **Do now:** SwiftGitX spike as alternate `GitWorkingTreeStatusProvider`.
- **Do not bundle:** forge redesign in the same change.
- **Defer:** Zig FFI unless benchmark evidence justifies complexity.
