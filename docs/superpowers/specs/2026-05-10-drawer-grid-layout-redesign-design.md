# Drawer Grid Layout Redesign — Design (Stub)

**Date:** 2026-05-10 (created as placeholder)
**Status:** STUB — not yet brainstormed. Awaits dedicated session.
**Branch:** TBD (will fork from same baseline as Spec 1 once started)

**Source session:**
- Session ID: `22280aad-8c90-4aba-a02d-0add40634a2b`
- Resume: `claude --resume 22280aad-8c90-4aba-a02d-0add40634a2b`
- Transcript: `~/.claude/projects/-Users-shravansunder-Documents-dev-project-dev-agent-studio-drawer-improvements/22280aad-8c90-4aba-a02d-0add40634a2b.jsonl`

**Foundation spec (already drafted):**
- `2026-05-02-pane-arrangement-state-system-design.md` — pane
  arrangement state model. Drawer state shape from that spec is
  the substrate this design builds on.

---

## What this stub covers

Two interrelated workstreams that both touch the drawer grid layer
and the sizing/resize system. They were brainstormed at a high level
in the 2026-05-02 session but deferred to a dedicated design pass.

### Workstream A — Sizing / minimize / resize / drag matrix

**Linear:** LUNA-371 (preserve source size on slot drop) is one
specific cell. The full matrix is bigger.

The user pain:

> "you cannot drag a pane next to minimized without the resizing
> going bonkers. everything related to minimize panes is fucked
> up. we need to rethink minimize panes and resizing fully."

Open design questions to answer in the dedicated session:

- **Pane state machine.** Expanded / minimized / dragging-from-
  minimized / dragging-to-minimized / etc. State transitions and
  guards.
- **Resize matrix with minimized siblings.** Divider drag adjacent
  to a minimized pane. What happens to ratio space? Does the
  visible budget shrink/grow correctly?
- **Drag matrix with minimized siblings.** Source pane minimized
  → drop target rules. Drop target adjacent to minimized → ratio
  semantics on insert. Cross-row drag into a row with minimized
  panes.
- **Sizing primitive: `DropSizingMode.preserveSource`** (Issue B
  from the prior session). Add a new sizing mode that preserves
  source pane's pre-removal ratio on slot drop. Plumbing through
  `DropSizingModeResolver` + `DropSizingRatioPolicy` +
  `Layout.insertingWithPolicy` + the column-major equivalent.
- **Same-row reorder optimization.** Within-row drag should be
  pure permutation (no ratio rebalance), not remove-then-insert.
- **Cross-row source ratio transfer.** When moving across rows,
  preserve RATIO (model-pure) vs preserve PIXEL WIDTH (requires
  view-layer info). Recommendation from prior session: preserve
  ratio.
- **Minimized + showsMinimizedPanes interaction with sizing.**
  The Spec 1 derivation rule changes which panes count toward
  visible-budget. Resize math must respect the same rule.
- **Single source of truth for "what's visible in this row right
  now".** Today FlatTabStripMetrics computes it ad hoc; should
  it route through `WorkspaceArrangementViewDerived` from Spec 1?

### Workstream B — Drawer column-major refactor

**Linear:** LUNA-372 (drawer column-major refactor).

**The product limitation:**

```
   ┌──────────┬──────────┐
   │          │  pane C  │
   │  pane A  ├──────────┤      ← desired but impossible today
   │          │  pane D  │
   └──────────┴──────────┘
```

Current `DrawerGridLayout` is row-major: 1 row × N panes OR 2 rows
× N panes each. No way for a single drawer pane to span the full
panel height while siblings stay split.

**The replacement model (user-picked, prior session):**

Column-major. The drawer is a list of columns; each column has
1 or 2 panes stacked vertically.

Open design questions to answer in the dedicated session:

- **Data model.** New `DrawerColumnLayout` (replaces
  `DrawerGridLayout`)? Persist as list of `Column` items, each
  with its own pane stack and column-width ratio.
- **Drag-target matrix updates.** What new targets does column-
  major enable? "Promote to tall column" zone? Per-column resize
  handles? Per-column row split drag?
- **Migration path.** Existing 2-row drawers map to N columns,
  each with 2 stacked panes. Or 1×N with each pane in its own
  column? Pick deterministic mapping.
- **Resize behavior.** Column-width drag (horizontal). Per-column
  row-split drag (vertical, only when column has 2 panes). Both
  need ratio storage.
- **Persistence shape.** `DrawerGridLayout` JSON →
  `DrawerColumnLayout` JSON. Schema version bump on
  `WorkspaceStore`.
- **Affected components.** `DrawerGridLayout(+Rearrange).swift`,
  `DrawerPaneDragCoordinator.swift`, `DropTargetConfig.swift`,
  `DrawerCommandValidator.swift`, `TerminalPaneGeometryResolver
  .swift`, `DrawerPanel.swift`. AppPolicies: `drawerMaxRows` →
  `drawerMaxStackedPerColumn`.

### Drawer expansion contract

`Drawer.isExpanded` remains global to the parent pane, not per
arrangement. The drawer is part of the parent pane shell.
Arrangements own how drawer children are ordered, which drawer
child is active, and which drawer children are minimized. They do
not own whether the shell is open.

When switching arrangements, an expanded drawer remains expanded.
The active drawer child and minimized drawer children are read
from the destination arrangement's `DrawerView`. An empty drawer
renders as an explicit empty drawer state, not as persisted fake
drawer view data.

### Why workstream B is at the bottom

Workstream A is implementation-ready (sizing primitives + drag
matrix on the existing row-major model). Workstream B is a
feature-level refactor that needs its own spec doc and migration
plan first.

Recommended order from the prior session: A first, then B. The
`.preserveSource` primitive and the resize-with-minimized-panes
fixes from A become reusable on B's column-major model.

---

## Why this is one stub instead of two

Both workstreams touch:

- The drawer grid layout (A's resize math, B's data-model rewrite)
- `DropSizingMode` / `DropSizingRatioPolicy` (A defines the
  primitive, B uses it on the new model)
- The drag-target system (A adjusts matrix for minimized siblings;
  B redesigns the matrix entirely for column-major)
- Tests in `DrawerGridLayoutRearrangeTests` and
  `DropSizingRatioPolicyTests`

Designing them in isolation risks A landing decisions that B then
has to undo. A single design session that scopes both, then ships
A first and B second, gives coherence without losing the phasing.

If a future review decides A and B are truly independent, this
stub can split into two specs (one per workstream) without losing
work.

---

## Pending questions surfaced in the prior session

These didn't get answered before deferral; they need to be answered
in this stub's dedicated brainstorm:

1. Same-row reorder semantic: pure permutation or remove-then-
   insert with `.preserveSource`? (Permutation is simpler;
   `.preserveSource` is more uniform.)
2. Cross-row source: preserve RATIO or PIXEL WIDTH?
3. Plumbing for source ratio: parameter on `projectedMove`, or
   carried inside the enum value, or atomic move primitive?
4. Cross-container drag fall-back: silent `.proportional` or
   reject the move?
5. Empty-row insertion (`createSecondRow`): trivial source ratio
   = 1.0 — confirm.
6. Drag rules for minimized panes: can minimized be a drag
   SOURCE? Can drop create a minimized pane? Drag minimized to
   unminimize?
7. Resize behavior near minimized panes: does ratio space include
   minimized siblings?
8. Column-major specific: per-column resize handles (drag column
   width OR drag intra-column split)?
9. Migration mapping: row-major 2×N → column-major. Each pane in
   own column, or pair them up?

---

## Out of scope (for this stub)

This stub is a placeholder. The real spec is written in a
dedicated brainstorming session. This file should be replaced (or
filled in) at that point.

What's NOT here yet:

- DATA / VIEW classification (Spec 1 set the foundation; this
  spec inherits)
- Detailed atom changes (Spec 1 already shaped Drawer + DrawerView)
- Test surface enumeration
- Implementation phasing
- Observability records (likely reuses `arrangement` trace tag
  from Spec 1, plus possibly a new `drag` or `sizing` tag)

---

**Next step:**

Open a new brainstorming session against this stub. Bring the
prior session transcript (`22280aad...jsonl`) for context.
Decide A-then-B split; answer the pending questions above; then
draft the full spec content here.
