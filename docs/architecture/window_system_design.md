# Window System Design

> Agent Studio — Dynamic Window System Architecture

See [JTBD & Requirements](jtbd_and_requirements.md) for the motivation, pain points, and requirements this design addresses.

---

## Design Overview

The window system has **three layers of organization**:

1. **User's Workspace** — manually arranged tabs with pane arrangements (persistent, user-controlled)
2. **Dynamic Views** — computed lenses that group panes by facet across all tabs (ephemeral, system-arranged)
3. **Pane Drawers** — contextual drawer panes attached to individual panes (persistent, per-pane)

The user's workspace is always the home base. Dynamic views are excursions. Pane drawers are local expansions. The user can always return to their workspace.

```
Workspace (user's, persistent)
  ├── Tab "my-project"
  │   ├── Default Pane Arrangement (all panes)
  │   ├── Custom: "coding" (subset)
  │   └── Custom: "testing" (subset)
  │   Each pane:
  │     ├── Content (terminal / webview / code viewer)
  │     └── Drawer (drawer panes — any content type)
  │
  └── Tab "infra"
      ├── Default Pane Arrangement
      └── Custom: "monitoring" (subset)

Dynamic Views (computed, ephemeral — generates tabs)
  "By Repo" view:
    ├── Tab: "agent-studio"       ← auto-generated, one tab per repo
    │   └── Auto-tiled panes
    ├── Tab: "askluna-backend"
    │   └── Auto-tiled panes
    └── Tab: "infra-tools"
        └── Auto-tiled panes

  "By Worktree" view:
    ├── Tab: "main"               ← auto-generated, one tab per worktree
    ├── Tab: "feature-x"
    └── Tab: "hotfix-y"

  "By Parent Folder" view:
    ├── Tab: "~/dev/askluna"      ← auto-generated, one tab per parent folder
    └── Tab: "~/dev/agent-studio"
```

---

## State Architecture

### Owned State (persisted)

All user-created entities with stable identity. Mutated only through transactional commands.

- Workspace tabs
- Panes (with content and metadata)
- Pane arrangements (default + custom per tab)
- Drawer state (drawer panes per pane)

### Transient State (not persisted, TTL-managed)

Recoverable entities that exist temporarily outside normal ownership.

- **Orphaned pane pool**: Panes promoted from DrawerPanes when their parent is deleted. TTL of 5 minutes. User can claim them into a tab or let them expire. This preserves the invariant that every DrawerPane always has a parent — when the parent is deleted, drawer panes become regular Panes in this pool.

### Computed State (ephemeral, derived)

Read-only projections recomputed from owned state. Never persisted. Cannot mutate owned state.

- Dynamic view tabs and layouts
- Facet indexes (repo → panes, worktree → panes, etc.)
- Command bar search results and MRU

This separation ensures dynamic views can never accidentally become owners of panes.

---

## Entity Model

### Core Entities

```
Pane {
  id: UUID
  content: PaneContent                 // what this pane displays
  metadata: PaneMetadata               // context: CWD, repo, worktree, tags
  drawer: Drawer?                      // optional child panes (nil on DrawerPanes)
}

DrawerPane {
  id: UUID
  content: PaneContent                 // same content types as Pane
  metadata: PaneMetadata               // inherits context from parent Pane
}

Drawer {
  panes: [DrawerPane]                  // child panes in this drawer
  activeDrawerPaneId: UUID?            // which drawer pane is expanded
  isExpanded: Bool                     // collapsed to icon bar or fully hidden
}
```

### Content Types (shared by Pane and DrawerPane)

```
PaneContent =
  | .terminal(TerminalState)           // Ghostty surface, zmx backend
  | .webview(WebviewState)             // URL, navigation state
  | .codeViewer(CodeViewerState)       // file path, scroll position
  | .future(...)                       // extensible

TerminalState {
  surfaceId: UUID?                     // Ghostty surface reference
  provider: .ghostty | .zmx           // session backend
  lifetime: .persistent | .temporary
}

WebviewState {
  url: URL
  // navigation history, zoom, etc.
}

CodeViewerState {
  filePath: String
  // scroll position, highlights, etc.
}
```

### Metadata (shared by Pane and DrawerPane)

```
PaneMetadata {
  source: .worktree(id, repoId) | .floating(dir, title)
  cwd: String                          // live, propagated from shell
  agentType: AgentType?                // agent running in this pane
  tags: [String]                       // user or system labels for grouping
}
```

### Structural Entities

```
Tab {
  id: UUID
  name: String
  panes: [UUID]                        // all Pane IDs in this tab
  arrangements: [PaneArrangement]
  activeArrangementId: UUID
  activePaneId: UUID?                  // which pane has focus
}

PaneArrangement {
  id: UUID
  name: String
  isDefault: Bool                      // exactly one per tab
  layout: Layout                       // split tree of Pane IDs
  visiblePaneIds: Set<UUID>            // subset of tab's panes
}
```

### Why Two Types (Pane vs DrawerPane)

The nesting constraint — "drawer panes cannot have their own drawers" — is **enforced by construction**. `DrawerPane` has no `drawer` field. The compiler prevents nesting, eliminating a class of runtime invariant violations.

Both types share `PaneContent` and `PaneMetadata` because they hold the same kinds of content with the same context. They differ only in structural capability: Panes participate in layouts and can have drawers. DrawerPanes cannot.

| Entity | In layout tree? | Can have drawer? | Can have children? |
|--------|----------------|-----------------|-------------------|
| **Pane** | Yes | Yes | Yes (via Drawer) |
| **DrawerPane** | No | No | No |

---

## Concept 1: Pane

### Definition
The primary content container. Appears in layout trees and pane arrangements. Can optionally have a drawer containing child DrawerPanes.

### Content Types
| Type | Description | Example |
|------|-------------|---------|
| Terminal | Ghostty surface | Agent session, shell |
| Webview | Embedded web content | React dev server, diff viewer, PR status |
| Code Viewer | Source code display | File review, code annotations |
| Future | Extensible | Logs, metrics, etc. |

### Rules
- A pane belongs to exactly one tab
- A pane cannot exist in two tabs simultaneously
- A pane cannot exist without a tab
- Content type is immutable after creation
- Only panes (not drawer panes) appear in layout trees and arrangements

---

## Concept 2: Pane Arrangement

### Definition
A named layout configuration within a tab. Defines which panes are visible and how they are tiled.

### Types

**Default Pane Arrangement**
- Exactly one per tab
- Contains ALL panes in the tab
- Auto-updated when panes are created or deleted
- Cannot be deleted
- The source of truth for "what panes exist in this tab"

**Custom Pane Arrangement**
- User-created
- A subset of the default arrangement's panes
- User-defined tiling (split tree)
- Can be created, edited, renamed, deleted

### Rules
- New panes always go to the default pane arrangement (and current active arrangement)
- Custom arrangements reference panes from the default set only
- Deleting a pane from default removes it from all custom arrangements
- Panes not in the active arrangement remain running (backgrounded)
- Switching arrangements changes visibility and tiling; panes keep running

### Data Model

```
Tab {
  id: UUID
  name: String
  panes: [UUID]                        // all Pane IDs in this tab
  arrangements: [PaneArrangement]
  activeArrangementId: UUID
  activePaneId: UUID?
}

PaneArrangement {
  id: UUID
  name: String
  isDefault: Bool                      // exactly one per tab
  layout: Layout                       // split tree of Pane IDs
  visiblePaneIds: Set<UUID>            // subset of tab's panes
}
```

For default: `visiblePaneIds == tab.panes` (always)
For custom: `visiblePaneIds ⊆ tab.panes`

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Switch arrangement | Command bar | Change active arrangement, show/hide panes |
| Create custom | Command bar ("save current as...") | Snapshot visible panes + tiling |
| Edit custom | Direct manipulation or command bar | Show/hide panes, rearrange tiling |
| Delete custom | Command bar | Remove arrangement, switch to default |
| Rename | Command bar | Update name |

---

## Concept 3: Drawer

### Definition
A collapsible horizontal panel below a pane that holds DrawerPanes. DrawerPanes can hold any content type (terminal, webview, code viewer) and inherit context from their parent pane.

### Visual Structure
```
┌─────────────────────────────────┐
│  Pane content                   │
│  (terminal / webview / etc)     │
│                                 │
├─────────────────────────────────┤
│ [dp1] [dp2] [dp3] [+]          │  ← icon bar (drawer panes)
│ ┌─────────────────────────────┐ │
│ │ Active drawer pane content  │ │  ← selected drawer pane expanded
│ │ (terminal / webview / etc)  │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### Properties
- **Parent pane**: The pane this drawer is attached to
- **Context inheritance**: DrawerPanes inherit CWD, worktree, repo from parent pane
- **Icon bar**: Shows all drawer panes, click to switch
- **Collapsible**: Can collapse to icon bar only, or fully hide
- **Navigable**: Keyboard and command bar accessible
- **Any content type**: DrawerPanes can be terminals, webviews, code viewers — same as Panes

### Rules
- Drawer can only exist attached to a parent Pane
- DrawerPanes cannot have their own drawers (enforced by type — no `drawer` field)
- Parent pane deletion cascades to drawer panes (backgrounded)
- Drawer state (which drawer panes, collapsed/expanded) persists with the pane

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Add drawer pane | Command bar or icon bar [+] | Create DrawerPane in drawer |
| Switch drawer pane | Click icon or keyboard | Show different drawer pane |
| Collapse/expand | Click or keyboard | Toggle drawer visibility |
| Close drawer pane | Command bar or icon | Remove DrawerPane from drawer |
| Navigate to | Command bar | Focus a specific drawer pane |

---

## Concept 4: Tab

### Definition
A named group of panes with switchable pane arrangements.

### Properties
- **Panes**: The full set of Pane IDs in this tab
- **Arrangements**: One default + zero or more custom pane arrangements
- **Active arrangement**: Which arrangement is currently displayed
- **Active pane**: Which pane has focus

### Rules
- A tab must have at least one pane
- A tab always has exactly one default pane arrangement
- New panes are added to the default arrangement and the current active arrangement
- Closing the last pane closes the tab (with undo)

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Create pane | Command bar | New pane added to default arrangement |
| Delete pane | Command bar | Removed from default and all custom arrangements; drawer panes cascaded |
| Receive pane | Pane movement | Pane added to default arrangement |
| Send pane | Pane movement | Pane removed from default and all customs |
| Switch arrangement | Command bar | Change which arrangement is visible |
| Close tab | Command bar / shortcut | Close tab with undo support |
| Reorder | Drag in tab bar | Change tab position |

---

## Concept 5: Dynamic View

### Definition
A computed, read-only lens that shows panes from across all tabs, grouped by a facet. Each dynamic view type **generates its own tab bar** where each tab corresponds to one group (one repo, one worktree, one parent folder, etc.). Pane layouts within each tab are auto-tiled by the system.

### View Types

Each dynamic view type slices all workspace panes differently:

| View Type | Each tab = | Example |
|-----------|-----------|---------|
| **By Repo** | One repository | Tab "agent-studio", Tab "askluna-backend" |
| **By Worktree** | One worktree | Tab "main", Tab "feature-x", Tab "hotfix-y" |
| **By CWD** | One working directory | Tab "~/dev/myapp", Tab "~/dev/infra" |
| **By Agent Type** | One agent type | Tab "Claude Code", Tab "Codex", Tab "aider" |
| **By Parent Folder** | One parent directory of repos | Tab "~/dev/askluna/", Tab "~/dev/agent-studio/" |
| **By Tag** (future) | One tag value | Tab "frontend", Tab "backend", Tab "infra" |

### Structure

```
Dynamic View (type: By Repo)
  ├── Tab: "agent-studio"          ← auto-generated tab
  │   └── [pane A | pane B]        ← auto-tiled layout
  ├── Tab: "askluna-backend"
  │   └── [pane C | pane D | pane E]
  └── Tab: "infra-tools"
      └── [pane F]

Dynamic View (type: By Worktree)
  ├── Tab: "main"
  │   └── [pane A | pane C | pane F]
  ├── Tab: "feature-x"
  │   └── [pane B | pane D]
  └── Tab: "hotfix-y"
      └── [pane E]
```

Same panes, different slicing. The panes themselves don't move — the dynamic view borrows them for display.

### Properties
- **View type**: Which facet to group by (repo, worktree, CWD, etc.)
- **Generated tabs**: One tab per group, each with auto-tiled panes
- **Live**: Tabs and pane membership update as pane metadata changes
- **Interactive**: Full terminal interaction (typing, scrolling) within each tab
- **Non-owning**: Panes remain owned by their home tab in the user's workspace
- **Drawer accessible**: Pane drawers are visible and interactive in dynamic views

### Rules
- Dynamic views never own, create, delete, or move panes
- User cannot rearrange the tiling within dynamic view tabs (system-generated only)
- Switching to a dynamic view does not disturb the user's workspace
- Switching back returns to the exact workspace state
- User can switch between dynamic view types while in a dynamic view (e.g., "By Repo" → "By Worktree")
- Recent dynamic view selections are remembered in command bar MRU
- Empty groups (no matching panes) are hidden — no empty tabs shown

### Facet Sources

**Auto-detected (no user setup)**:
- Repo — already tracked per pane via metadata.source
- Worktree — already tracked per pane via metadata.source
- CWD — already propagated from shell
- Agent type — already tracked in metadata
- Parent folder — auto-detected from repo path on disk (e.g., `~/dev/askluna/` groups all repos under it)

**User-configured (requirement now, UX later)**:
- Tags per repo — stored in Agent Studio's own metadata. User assigns tags like "frontend", "backend", "infra" to repos. Panes inherit tags from their repo.
- Tags per pane — direct labels on individual panes for finer control.
- Effective tags = repo tags + pane tags (inheritance rule)
- Tag management UX is a future design concern; the data model must support tags now.

**Recommendation**: Start with auto-detected facets (repo, worktree, CWD, parent folder). Add tag-based grouping when the auto-detected facets prove insufficient. Parent folder is a natural zero-config project grouping.

### Navigation Flow
```
User's Workspace
  ↕ ⌘P → "View: By Repo"                    (switch to dynamic view)
Dynamic View: By Repo
  ├── Browse tabs (one per repo)
  ├── ⌘P → "View: By Worktree"              (switch view type)
  └── ⌘P → "Workspace" or ⌘+Escape          (back to workspace)
User's Workspace (unchanged)
```

Dynamic view selections appear in command bar MRU for quick re-access.

---

## Concept 6: Pane Movement

### Definition
The ability to relocate a pane from one tab to another via the command bar.

### What Moves Together
- The pane itself
- Its drawer (all DrawerPanes)
- Its metadata (CWD, worktree, repo, tags, etc.)

### Rules
- Pane moves from source tab's default arrangement → target tab's default arrangement
- Pane is removed from all custom arrangements in the source tab
- Cannot move to a dynamic view (dynamic views don't own panes)
- Cannot clone — pane exists in exactly one tab at a time
- Cannot move a DrawerPane independently — it moves only with its parent pane
- Movement is atomic: pane + drawer panes move as a unit

### Flow
```
⌘P → "Move pane to Tab: infra"
  1. Remove pane from source tab's default arrangement
  2. Remove pane from source tab's custom arrangements
  3. Add pane to target tab's default arrangement
  4. Drawer (with all DrawerPanes) moves with pane
```

---

## Concept 7: Command Bar (extended)

### Definition
The central interaction point for all window system operations. All actions route through the command pipeline: **Parse → Validate (invariants) → Execute (state mutation) → Emit (domain events)**.

### New Capabilities

| Category | Commands |
|----------|----------|
| Pane Arrangements | Switch arrangement, create custom, edit, delete, rename |
| Dynamic Views | Open by facet, recent queries (MRU), back to workspace, switch view type |
| Pane Movement | Move pane to tab |
| Drawer | Add drawer pane, navigate to drawer pane, collapse/expand |
| Pane Content | Create terminal pane, create webview pane, create code viewer pane |

### Principles
- Command bar is always the primary interaction method
- Keybindings are added later as shortcuts to existing command bar actions
- Recent dynamic view queries appear in MRU for fast re-access
- All commands are typed intents validated against invariants before execution
- Commands that mutate multiple entities are transactional (atomic success or rollback)

---

## Invariants

### By Construction (compiler-enforced)

These invariants are impossible to violate because the type system prevents it:

1. **DrawerPanes cannot have drawers** — `DrawerPane` has no `drawer` field
2. **DrawerPanes cannot appear in layout trees** — `Layout.leaf` takes `Pane.id`, not `DrawerPane.id` (different types)
3. **Only Panes appear in arrangements** — `visiblePaneIds` is `Set<Pane.ID>`

### By Runtime Enforcement (command validation)

These invariants are checked by the command validator before every mutation:

**Pane ownership:**
4. Every Pane has a unique ID across the workspace
5. Every active Pane belongs to exactly one tab (orphaned panes in recoverable pool have no tab)
6. Every DrawerPane belongs to exactly one Pane's drawer (no orphaned DrawerPanes — they are promoted to orphaned Panes on parent deletion)

**Arrangement consistency:**
7. Default arrangement `visiblePaneIds` equals the full tab pane set
8. Custom arrangement `visiblePaneIds` is a subset of default
9. Exactly one default arrangement per tab
10. `activePaneId` references a pane visible in the active arrangement (or nil)

**Drawer rules:**
11. DrawerPanes cannot be moved independently of their parent Pane
12. A DrawerPane's parent Pane must be in the same tab

**Tab rules:**
13. A tab always has at least one Pane (enforced by escalation: deleting the last pane triggers CloseTab, not a validation error)
14. `activeArrangementId` references an arrangement in this tab

**Orphaned pane pool:**
15. Orphaned panes (promoted from DrawerPanes on parent deletion) exist in a workspace-level recoverable pool
16. Orphaned panes have a TTL (5 min) — auto-destroyed if not claimed
17. User can claim orphaned panes into a tab via command bar

**Dynamic view rules:**
18. Dynamic views cannot mutate owned state
19. Dynamic views display tab-owned Panes only (DrawerPanes accessible via drawer UI, orphaned panes not shown)

### Transactional Command Invariants

Multi-entity operations must be atomic. If any step fails, all steps roll back:

| Command | Steps (all-or-nothing) |
|---------|----------------------|
| **DeletePane** | Remove from all arrangements → promote drawer panes to orphaned pool (with TTL) → if tab has 0 panes: escalate to CloseTab |
| **MovePane** | Remove from source arrangements → add to target default → move drawer panes → validate both tabs |
| **CloseTab** | Snapshot for undo → teardown all panes + promote drawer panes to orphaned pool → remove tab |
| **SwitchArrangement** | Validate arrangement exists → hide non-visible panes → show visible panes → update active |

Note on **DeletePane**: The invariant "tab must have ≥1 pane" is maintained by escalation, not by preventing deletion. Deleting the last pane in a tab triggers CloseTab (with undo), which closes the tab entirely. The invariant is never violated because the tab ceases to exist.

---

## Lifecycle Policies

| Scenario | Policy |
|----------|--------|
| Parent pane deleted | DrawerPanes are **promoted to orphaned Panes** in a workspace-level recoverable pool with TTL (5 min). They are no longer DrawerPanes — they become regular Panes without a tab. This preserves invariant 6 (every DrawerPane always has a parent). User can claim orphaned panes via command bar or let them expire. |
| Empty groups in dynamic views | Hidden. No empty tabs shown. |
| Drawers in dynamic views | Visible and accessible. Interacting with a pane in a dynamic view shows its drawer. |
| Dynamic view tab sort order | Alphabetical by group name. Stable and predictable. |
| New pane created | Added to default arrangement AND current active arrangement. |
| Pane backgrounded (not in active arrangement) | Content keeps running. Surfaces detached for resource efficiency. |

---

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Pane vs Session identity | Pane is the universal identity. Session/terminal is just one content type (PaneContent). |
| Entity model | Two types: Pane (in layout, can have drawer) and DrawerPane (in drawer, no children). Nesting prevented by construction. |
| Drawer content types | Any PaneContent (terminal, webview, code viewer) — not limited to terminals. |
| Drawer nesting | One level only. DrawerPanes cannot have drawers. Enforced by type system. |
| Dynamic view structure | Generates tabs (one per group), not a single flat layout. |
| Dynamic view navigation | Can switch between view types while in dynamic view (repo → worktree). |
| Parent folder detection | Auto-detected from repo path on disk. |
| Tag management UX | Requirement exists now (data model supports tags); UX designed later. |
| Tag inheritance | Effective tags = repo tags + pane tags. |
| Owned vs computed state | Explicit separation. Dynamic views are computed projections that can never mutate owned state. |
| Command pipeline | Typed intents: Parse → Validate (invariants) → Execute (mutation) → Emit (events). |
| Multi-entity operations | Transactional. Atomic success or full rollback. |

## Open Questions

1. **Auto-tiling algorithm for dynamic views**: Equal grid? Most-recently-active gets more space? Does it matter initially?

2. **Drawer pane limit**: Is there a limit on how many DrawerPanes a drawer can hold? Or unlimited with scroll in the icon bar?

3. **Custom arrangement editing**: "Save current as..." captures visible panes + tiling. Is there also a way to edit which panes are in an arrangement after creation?

---

## Diagrams

### Entity Relationship

```mermaid
erDiagram
    Tab ||--o{ Pane : "owns (via panes[])"
    Tab ||--|{ PaneArrangement : "has arrangements"
    PaneArrangement ||--|| Layout : "contains"
    Layout ||--o{ Pane : "references (leaf nodes)"
    Pane ||--o| Drawer : "optionally has"
    Drawer ||--o{ DrawerPane : "contains"
    Pane ||--|| PaneContent : "displays"
    DrawerPane ||--|| PaneContent : "displays"
    Pane ||--|| PaneMetadata : "carries"
    DrawerPane ||--|| PaneMetadata : "inherits"
```

### Ownership Hierarchy

```mermaid
graph TD
    WS[Workspace - Owned State]
    DV[Dynamic Views - Computed State]

    WS --> T1[Tab 1]
    WS --> T2[Tab 2]

    T1 --> DA1[Default Arrangement]
    T1 --> CA1[Custom: 'coding']
    T1 --> CA2[Custom: 'testing']

    DA1 --> L1[Layout - split tree]
    CA1 --> L2[Layout - split tree]

    L1 --> P1[Pane A - terminal]
    L1 --> P2[Pane B - webview]
    L1 --> P3[Pane C - terminal]

    P1 --> DR1[Drawer]
    DR1 --> DP1[DrawerPane - terminal]
    DR1 --> DP2[DrawerPane - webview]

    DV -.->|borrows| P1
    DV -.->|borrows| P2
    DV -.->|borrows| P3

    style WS fill:#2d5016,color:#fff
    style DV fill:#4a1942,color:#fff
    style DR1 fill:#1a3a5c,color:#fff
```

### Dynamic View Projection

```mermaid
graph LR
    subgraph Owned[Owned State - Workspace]
        T1[Tab: my-project]
        T2[Tab: infra]
        T1 --> PA[Pane A<br/>repo: agent-studio]
        T1 --> PB[Pane B<br/>repo: askluna]
        T2 --> PC[Pane C<br/>repo: agent-studio]
        T2 --> PD[Pane D<br/>repo: askluna]
    end

    subgraph Computed[Dynamic View: By Repo]
        DT1[Tab: agent-studio]
        DT2[Tab: askluna]
        DT1 -.-> PA
        DT1 -.-> PC
        DT2 -.-> PB
        DT2 -.-> PD
    end

    style Owned fill:#1a3a1a,color:#fff
    style Computed fill:#3a1a3a,color:#fff
```

### Command Pipeline

```mermaid
flowchart LR
    CB[Command Bar] --> P[Parse<br/>typed intent]
    P --> V[Validate<br/>check invariants]
    V -->|pass| E[Execute<br/>mutate owned state]
    V -->|fail| R[Reject<br/>show error]
    E --> EM[Emit<br/>domain events]
    EM --> UI[UI Update<br/>Combine publishers]

    style V fill:#8b4513,color:#fff
    style R fill:#8b0000,color:#fff
```

### Pane Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: CreatePane command
    Created --> Active: Added to default arrangement
    Active --> Backgrounded: Switch to arrangement<br/>where pane not visible
    Backgrounded --> Active: Switch to arrangement<br/>where pane visible
    Active --> PendingUndo: DeletePane / CloseTab
    Backgrounded --> PendingUndo: DeletePane
    PendingUndo --> Active: Undo
    PendingUndo --> Destroyed: TTL expired
    Active --> Destroyed: Force delete

    note right of Backgrounded
        Content keeps running
        Surfaces detached
    end note

    note right of PendingUndo
        In undo stack
        5 min TTL
    end note
```

### Navigation Flow

```mermaid
stateDiagram-v2
    WS: User's Workspace
    DV_R: Dynamic View: By Repo
    DV_W: Dynamic View: By Worktree
    DV_C: Dynamic View: By CWD

    [*] --> WS
    WS --> DV_R: ⌘P → "View: By Repo"
    WS --> DV_W: ⌘P → "View: By Worktree"
    WS --> DV_C: ⌘P → "View: By CWD"

    DV_R --> WS: ⌘+Escape / "Workspace"
    DV_W --> WS: ⌘+Escape / "Workspace"
    DV_C --> WS: ⌘+Escape / "Workspace"

    DV_R --> DV_W: Switch view type
    DV_W --> DV_R: Switch view type
    DV_R --> DV_C: Switch view type
    DV_C --> DV_R: Switch view type
```

---

## Gap Analysis: Current Codebase → New Design

### Entity Mapping

| Current Entity | New Entity | Key Changes |
|----------------|-----------|-------------|
| `TerminalSession` | `Pane` | Add `content: PaneContent` enum, add `drawer: Drawer?`, rename fields |
| `TerminalSource` | `PaneMetadata.source` | Same shape, moved into metadata struct |
| `Tab.layout` | `PaneArrangement.layout` | Layout moves from Tab into PaneArrangement; Tab gains `arrangements[]` |
| `Tab.activeSessionId` | `Tab.activePaneId` | Rename |
| `Tab.zoomedSessionId` | Removed | Zoom becomes arrangement-specific or view state |
| `ViewDefinition` (.main/.saved) | Workspace `tabs: [Tab]` | Views flattened to just tabs; no view hierarchy |
| `ViewDefinition` (.dynamic/.worktree) | Dynamic View (computed) | No longer persisted; generated at runtime by facet |
| `Layout` | `Layout` (unchanged) | `leaf(sessionId)` → `leaf(paneId)` semantic rename |
| — (new) | `DrawerPane` | Entirely new entity |
| — (new) | `Drawer` | Entirely new entity |
| — (new) | `PaneArrangement` | Entirely new entity |
| — (new) | `PaneContent` | Entirely new enum (`.terminal \| .webview \| .codeViewer`) |

### What Can Be Reused

| Current Code | Reuse | Changes |
|-------------|-------|---------|
| `Layout.swift` — split tree logic | Direct reuse | Rename `sessionId` → `paneId` in leaf nodes |
| `WorkspaceStore` — mutation pattern, debounced persistence | Reuse pattern | Rename fields, add arrangement/drawer methods |
| `ViewRegistry.renderTree()` | Direct reuse | No structural changes |
| `SurfaceManager` — public API | Direct reuse | Internal `sessionId` → `paneId` rename |
| `ActionExecutor` — dispatch pattern | Reuse pattern | Add new action cases + validation layer |
| Undo stack (`CloseSnapshot`) | Extend | Add arrangements + drawer panes to snapshot |
| `WorkspacePersistor` — JSON serialization | Reuse | Update schema, add migration code |

### What's Entirely New

| New Component | Purpose |
|---------------|---------|
| `Pane` type with `PaneContent` enum | Universal content container replacing `TerminalSession` |
| `DrawerPane` type | Child pane in drawer (no drawer field — nesting prevented by construction) |
| `Drawer` struct | Drawer state: child panes, active pane, expanded/collapsed |
| `PaneArrangement` | Named layout config within a tab (default + custom) |
| `PaneMetadata` struct | Consolidated metadata: source, CWD, agent, tags |
| Dynamic view generator | Facet indexing + tab generation (computed, ephemeral) |
| Command validation layer | Pre-execution invariant checks |
| Content renderers | Rendering logic per `PaneContent` type (webview, code viewer) |
| Tag storage + inheritance | Repo tags + pane tags → effective tags |

### Service Impact

| Service | Impact Level | Changes |
|---------|-------------|---------|
| `WorkspaceStore` | **Critical** | State shape change (`sessions` → `panes`, `views` → `tabs`), add arrangement/drawer/movement methods, persistence migration |
| `ActionExecutor` | **High** | New action types (arrangements, drawers, movement, dynamic views), validation layer, transactional operations |
| `TerminalTabViewController` | **High** | Arrangement switching, drawer UI, dynamic view rendering |
| `ViewRegistry` | **Low** | Internal `sessionId` → `paneId` rename |
| `SurfaceManager` | **Low** | Internal ID rename only, API unchanged |

### Migration Risk

| Risk | Level | Mitigation |
|------|-------|------------|
| WorkspaceStore state shape change | 🔴 Critical | Phased migration, keep old format readable |
| Tab structure overhaul (layout → arrangements) | 🔴 Critical | Create default arrangement from existing layout during migration |
| ViewDefinition split (owned vs computed) | 🔴 Critical | Build dynamic views as isolated service |
| Drawer implementation | 🟠 High | Additive feature, implement after foundation stable |
| Multi-arrangement tabs | 🟠 High | Ship default arrangement first, add custom in Phase 2 |
| Dynamic views (computed) | 🟠 High | Build facet indexer as pure function, test independently |

### Suggested Implementation Phases

| Phase | Scope | Risk |
|-------|-------|------|
| **1. Foundation** | Rename `TerminalSession` → `Pane` + `PaneContent`, migrate `Tab.layout` → default `PaneArrangement`, split `ViewDefinition` → workspace tabs + computed views, update `WorkspaceStore` + persistence migration | 🔴 Critical |
| **2. Arrangements** | Custom arrangement CRUD, arrangement switching, backgrounded pane lifecycle | 🟠 High |
| **3. Drawers** | `Drawer` + `DrawerPane` types, lifecycle cascade, UI (icon bar + expand/collapse) | 🟠 High |
| **4. Dynamic Views** | Facet indexer, tab generator, auto-tiling, navigation (workspace ↔ dynamic view), MRU | 🟠 High |
| **5. Movement + Validation** | Pane movement commands, command validation layer, transactional operations | 🟡 Medium |
