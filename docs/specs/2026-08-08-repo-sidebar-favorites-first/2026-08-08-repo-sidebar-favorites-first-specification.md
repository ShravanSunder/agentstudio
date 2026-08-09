# Repository Sidebar Favorites-First Specification

## Observable contract

### S1 — Favorites are part of the normal list

The repository sidebar MUST NOT expose a Show Favorites Only / Show All toggle. All matching content remains present in one normal view.

### S2 — Repository and pane modes

In By Repo and By Pane:

- when at least one visible favorite repository has a resolved group or is still loading, a non-collapsible `Favorites` section header appears first;
- favorite repository groups appear under that header in the selected sort direction;
- the normal non-collapsible header is always present after Favorites: `Repositories` in By Repo and `Panes` in By Pane;
- non-favorite groups appear under the normal header and favorite groups MUST NOT be repeated there;
- the `Favorites` section is omitted when it has neither resolved groups nor loading repositories, while the normal section remains visible when empty.

Within each section, resolved groups appear first and loading repositories follow under the existing `Scanning…` status label. Loading rows are classified by the loading repository's favorite state; the unpartitioned global loading section is removed. Search can independently remove either partition and its loading rows.

### S3 — Tab mode

In the normal By Tab content state, a top-level non-collapsible `Favorites` section appears first when favorite-backed worktree occurrences are visible. A top-level non-collapsible `Tabs` section always follows, including when no non-favorite tab rows are visible. Favorites MUST NOT be nested inside a tab group. Each favorite-backed leaf appears exactly once under Favorites, each remaining leaf appears exactly once under Tabs, and each partition preserves existing tab and repository/worktree ordering. A mixed tab may therefore have a group presentation in each top-level section, with distinct section-qualified group and row identities, but no destination is duplicated. The existing no-results and degraded states continue to replace the list when applicable.

### S4 — Search and disclosure

Search applies before favorite section presentation. An empty Favorites section disappears as the query changes; the normal Repositories, Panes, or Tabs header remains present in normal content. Filtering continues to force matching repository groups open. Clearing the query restores stored group disclosure. Section headers are labels, not another disclosure tier.

### S5 — Favorite mutation

The existing bookmark and context-menu actions remain available with Add Favorite / Remove Favorite accessibility labels. A favorite-state mutation updates ordering/sections without changing the selected grouping mode, sort direction, search query, or group collapse identity.

### S6 — Empty and boundary states

- No favorite-specific empty screen exists because non-favorites remain visible.
- A query with no matches retains the existing no-results state.
- A repository collection with no favorites shows no `Favorites` header.
- A collection containing only favorites still shows its empty normal `Repositories`, `Panes`, or `Tabs` header after Favorites.
- Every grouping mode retains its normal header in the normal content state even when that section has no visible group; the existing no-results and degraded states remain headerless replacement views.
- A loading-only partition remains visible under its corresponding section header and `Scanning…` label.
- Degraded topology behavior remains unchanged.

### S7 — Cutover

The favorites-only visibility enum/state, toolbar control, command catalog entry, command execution and IPC contracts, projection branch, dedicated empty state, persistence read/write, and active tests/scripts MUST be removed or updated in the same change. Persisted legacy preference data may remain physically readable only where schema compatibility requires it, but it MUST NOT influence current behavior or remain an active application preference.

### S8 — Visual and accessibility quality

Sidebar and Command Bar subheadings use one shared component: system 13-point semibold small caps, the app accent color at the shared secondary foreground opacity, 12-point horizontal padding, 8-point top padding, and 4-point bottom padding. Sidebar headers expose meaningful accessibility labels. Native visual proof MUST cover no favorites, mixed favorites, all favorites, search, all three grouping modes, and Command Bar at normal widths.

## Proof obligations

- Projection tests prove partitioning, ordering, mixed-tab uniqueness, search, loading, and empty boundaries.
- Command/persistence/IPC tests prove removal of the active favorites-only contract.
- Focused Swift and architecture checks pass.
- The complete `mise run test` PR gate passes on current HEAD.
- A running debug app is inspected with PID-targeted native UI tooling and screenshots demonstrate spacing, hierarchy, and all three modes.
