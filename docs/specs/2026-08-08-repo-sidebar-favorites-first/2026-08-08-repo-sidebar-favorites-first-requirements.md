# Repository Sidebar Favorites-First Requirements

## Goal

People with many repositories need their deliberately favorited repositories to remain immediately reachable without switching the whole sidebar into a temporary filtered state.

## Authorized needs

- U1 (high): A favorite repository is visibly prioritized in the normal repository sidebar.
- U2 (high): The remaining repositories stay available immediately after favorites; favoriting is organization, not exclusion.
- U3 (high): By Repo, By Pane, and By Tab retain their existing grouping meaning and destination identity.
- U4 (high): Favorite and unfavorite actions remain direct, legible, and accessible.
- U5 (high): Search, sort direction, group disclosure, loading, empty, keyboard, and command behavior remain coherent after the favorites-only path is removed.
- U6 (high): The resulting sidebar must match Agent Studio's existing native visual system and be verified in the running macOS app.
- U7 (high): Every grouping mode always shows its normal top-level subheading; Favorites is an optional top-level sibling above it and is never nested inside a repository, pane, or tab.
- U8 (high): Sidebar and Command Bar subheadings share the same typography, accent color, and spacing, with a small-caps treatment that does not overpower row content.

## Boundaries

- Favorite state remains repository-owned and persisted by the existing topology owner.
- The feature does not add manual favorite ordering, recency ordering, drag-and-drop, new persistence, or a fourth grouping mode.
- A worktree or pane destination appears only once in a view.
- Existing By Tab order remains tab-owned. Favorites may partition leaf occurrences into a top-level Favorites section, but no leaf destination is duplicated.
- Favorites and Tabs presentations of the same mixed tab keep independent disclosure state because they are separate visible groups.
- This is a hard cutover from favorites-only visibility. No hidden compatibility UI, alias command, or parallel projection path remains.

## Evidence

- User-provided command-palette reference: named priority section followed by the complete collection.
- Current Agent Studio sidebar reference: repository headers, worktree rows, direct bookmark control, and By Repo/By Pane/By Tab modes.
- Apple Finder and Linear use an optional Favorites section above the ordinary navigation collection; Apple HIG recommends concise sidebar hierarchy and avoids unnecessary depth.
