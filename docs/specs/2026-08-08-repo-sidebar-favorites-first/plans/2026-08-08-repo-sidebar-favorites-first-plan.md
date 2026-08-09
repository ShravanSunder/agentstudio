# Repository Sidebar Favorites-First Implementation Plan

## Goal and governing artifacts

Implement the reviewed behavior defined by the sibling Requirements, Specification, and Program Design. Terminal: draft PR, verified and unmerged.

## Task 1 — Establish red projection and row-index proof

- Replace favorites-do-not-reorder and favorites-only tests with failing expectations for By Repo/By Pane sections and By Tab stable favorite-first row partition.
- Cover no favorites, all favorites, mixed loading state, search removal of empty sections, descending sort, stable IDs, and visible-row indexing.
- Run the focused RepoExplorer model tests and retain the expected red receipt.

## Task 2 — Implement projection and list-entry structure

- Add the minimal section descriptor/list entry under RepoExplorer models.
- Partition repository-owned groups after existing mode projection; stable-partition tab rows without changing tab/group IDs, add a non-collapsible `Tabs` heading, and add per-tab Favorites/Repositories labels around the two row partitions.
- Render non-interactive section labels using existing sidebar typography/insets.
- Re-run focused model/view tests green.

## Task 3 — Hard-cut the favorites-only path

- Remove the visibility enum, snapshot input, preference atom state, toolbar button, callback wiring, command presentation/catalog/execution/IPC surfaces, favorite-only empty state, and active script invocations.
- Keep an inert legacy SQLite preference column only if current migration structure makes physical removal destructive; remove runtime hydration and persistence writes.
- Update exhaustive tests and source architecture assertions; scan Sources, Tests, scripts, active docs, and generated contracts for semantic residue.

## Task 4 — Quality and focused integration proof

- Run formatting, lint, focused Swift RepoExplorer tests, IPC/programmatic-control tests, architecture tests, and `git diff --check`.
- Inspect the complete diff against all three governing artifacts.

## Task 5 — Native visual iteration

- Start the shared observability stack and standard isolated debug app.
- Use Peekaboo/Computer Use with the exact app/PID to capture and inspect By Repo, By Pane, By Tab, no-favorites, mixed-favorites, all-favorites, and search states at normal sidebar width.
- Adjust only existing style-token-owned spacing/presentation values or a narrowly owned RepoExplorer section wrapper. Re-run focused proof after each adjustment.

## Task 6 — Full proof, independent review, and PR

- Run `mise run test` on the final HEAD and record exit code and pass counts.
- Dispatch a fresh-context read-only implementation review; remediate accepted findings and refresh affected proof/review.
- Commit scoped files, push the branch, open a draft PR, and verify exact head, checks, comments, review threads, and mergeability. Do not merge.
