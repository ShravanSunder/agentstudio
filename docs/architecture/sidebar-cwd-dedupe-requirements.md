# Sidebar CWD Dedupe Requirements

## Problem Statement
The sidebar can show duplicate checkout rows when the same checkout path is present through multiple repo entries (for example: parent repo + separately added worktree repo). This creates confusing counts, duplicate rows, and empty-looking groups.

## Goals
1. Deduplicate displayed checkout rows by normalized checkout `cwd` path.
2. Keep repo/folder grouping semantics intact.
3. Ensure group counts reflect what is actually rendered.
4. Prevent new duplicate entries from being added when the checkout path already exists.

## Scope
- Sidebar grouping and checkout row projection.
- Add Repo / Add Folder dedupe guardrails.
- Unit tests for deterministic dedupe behavior.

## Out of Scope
- Auto-migration cleanup of already-persisted duplicate repos on disk.
- Changes to sidebar visual design/chips/icons.
- Worktree discovery command behavior.

## Functional Requirements

### R1 — Render Dedupe by CWD
When multiple repo entries contain worktrees resolving to the same normalized filesystem path, the sidebar must render exactly one checkout row for that path.

### R2 — Ownership Selection Rule
When duplicate checkout paths exist, ownership is chosen deterministically:
1. Prefer repo with more discovered worktrees.
2. If tied, prefer repo whose `repoPath` matches that checkout path.
3. If tied, prefer main worktree entry.
4. If tied, use stable lexical tiebreaker.

### R3 — Hide Empty Repos in Group Projection
Repo entries with zero renderable worktrees must not appear in projected group rows.

### R4 — Group Count Accuracy
`checkoutCount` must equal the number of rendered checkout rows in that group (no synthetic fallback count).

### R5 — Add-Time Dedupe Guard
Adding a repo by path must no-op if the normalized path already exists as either:
- an existing repo root path, or
- an existing worktree path.

### R6 — Path Normalization
All CWD comparisons must use standardized file URL paths (normalizing path components and trailing slash variations).

## Acceptance Criteria
1. No duplicate checkout rows for identical normalized CWD paths.
2. Group badge count equals visible checkout row count.
3. Duplicate add attempts by equivalent path are ignored.
4. Behavior is covered by unit tests and deterministic across runs.

