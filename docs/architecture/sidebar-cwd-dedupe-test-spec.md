# Sidebar CWD Dedupe Test Spec

References: `docs/architecture/sidebar-cwd-dedupe-requirements.md`

## Test Strategy
Use unit tests against sidebar grouping projection to validate path dedupe and deterministic ownership, plus add-time dedupe guard behavior where testable in pure logic.

## Test Matrix

### T1 (R1, R2): Duplicate checkout path collapses to one rendered row
- Arrange:
  - Repo A and Repo B in same group share checkout path `/tmp/repo/feature-x`.
  - Repo A has more worktrees than Repo B.
- Assert:
  - Shared path appears once after projection.
  - Owner is Repo A.

### T2 (R2): Tie-break by `repoPath` match
- Arrange:
  - Repo A and Repo B share one checkout path and same worktree count.
  - Only Repo B has `repoPath == checkoutPath`.
- Assert:
  - Shared checkout is owned by Repo B.

### T3 (R6): Path normalization dedupe
- Arrange:
  - Duplicate checkout represented as `/tmp/repo/wt` and `/tmp/repo/./wt/`.
- Assert:
  - Projection keeps one row.

### T4 (R3): Empty repos are omitted from projection
- Arrange:
  - Group includes one repo with zero worktrees.
- Assert:
  - Empty repo is not returned in projected group repos.

### T5 (R4): Group checkout count reflects rendered rows only
- Arrange:
  - Group with deduped and unique worktrees.
- Assert:
  - `checkoutCount` equals flattened projected worktree count.

### T6 (R1): Distinct checkout paths are preserved
- Arrange:
  - Multiple repos with unique worktree paths.
- Assert:
  - All unique paths remain visible.

## Test Fixtures / Mocks
- Build deterministic mock repos/worktrees using fixed UUIDs and paths.
- Build metadata map keyed by `repo.id` with shared `groupKey`.
- Keep fixture builders reusable so design regressions can be tested with minimal setup.

## Exit Criteria
1. All T1–T6 pass.
2. No flaky ordering assumptions (assert via sets where needed).
3. Build remains green.

