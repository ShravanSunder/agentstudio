# Repository Sidebar Favorites-First Specification

## Observable contract

### S1 — Favorites are part of the normal list

The repository sidebar MUST NOT expose a Show Favorites Only / Show All toggle. All matching content remains present in one normal view.

### S2 — Repository-owned modes

In By Repo and By Pane:

- when at least one visible favorite repository has a resolved group or is still loading, a non-collapsible `Favorites` section header appears first;
- favorite repository groups appear under that header in the selected sort direction;
- a non-collapsible `Repositories` section header follows when a visible non-favorite repository has a resolved group or is still loading;
- favorite groups MUST NOT be repeated in `Repositories`;
- a section with neither resolved groups nor loading repositories is omitted.

Within each section, resolved groups appear first and loading repositories follow under the existing `Scanning…` status label. Loading rows are classified by the loading repository's favorite state; the unpartitioned global loading section is removed. Search can independently remove either partition and its loading rows.

### S3 — Tab-owned mode

In By Tab, a non-collapsible `Tabs` section header always appears, including when the tab list has no visible groups. Each visible tab group appears exactly once in existing tab order beneath that header. Within each tab, favorite-backed worktree occurrences appear before non-favorite occurrences. A `Favorites` label precedes the favorite-backed occurrences when that partition is non-empty, and a `Repositories` label precedes the non-favorite occurrences when that partition is non-empty. Each partition preserves the configured repository/worktree ordering. The labels are inside the existing tab group; they do not repartition tabs or duplicate destinations.

### S4 — Search and disclosure

Search applies before favorite section presentation. Empty sections disappear as the query changes. Filtering continues to force matching repository groups open. Clearing the query restores stored group disclosure. Section headers are labels, not another disclosure tier.

### S5 — Favorite mutation

The existing bookmark and context-menu actions remain available with Add Favorite / Remove Favorite accessibility labels. A favorite-state mutation updates ordering/sections without changing the selected grouping mode, sort direction, search query, or group collapse identity.

### S6 — Empty and boundary states

- No favorite-specific empty screen exists because non-favorites remain visible.
- A query with no matches retains the existing no-results state.
- A repository collection with no favorites shows no `Favorites` header.
- A collection containing only favorites shows no empty `Repositories` header.
- By Tab retains its `Tabs` header even when no tab group is visible.
- A loading-only partition remains visible under its corresponding section header and `Scanning…` label.
- Degraded topology behavior remains unchanged.

### S7 — Cutover

The favorites-only visibility enum/state, toolbar control, command catalog entry, command execution and IPC contracts, projection branch, dedicated empty state, persistence read/write, and active tests/scripts MUST be removed or updated in the same change. Persisted legacy preference data may remain physically readable only where schema compatibility requires it, but it MUST NOT influence current behavior or remain an active application preference.

### S8 — Visual and accessibility quality

Section headers use the existing sidebar section-header typography and insets, with enough vertical separation to distinguish them from repository disclosure headers without introducing a card or divider-heavy visual language. They expose meaningful accessibility labels. Native visual proof MUST cover no favorites, mixed favorites, all favorites, search, and all three grouping modes at normal sidebar width.

## Proof obligations

- Projection tests prove partitioning, ordering, mixed-tab uniqueness, search, loading, and empty boundaries.
- Command/persistence/IPC tests prove removal of the active favorites-only contract.
- Focused Swift and architecture checks pass.
- The complete `mise run test` PR gate passes on current HEAD.
- A running debug app is inspected with PID-targeted native UI tooling and screenshots demonstrate spacing, hierarchy, and all three modes.
