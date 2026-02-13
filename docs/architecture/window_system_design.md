# Window System Design

> Agent Studio — Dynamic Window System Architecture

See [JTBD & Requirements](jtbd_and_requirements.md) for the motivation, pain points, and requirements this design addresses.

---

## Design Overview

The window system has **three layers of organization**:

1. **User's Workspace** — manually arranged tabs with pane arrangements (persistent, user-controlled)
2. **Dynamic Views** — computed lenses that group panes by facet across all tabs (ephemeral, system-arranged)
3. **Pane Drawers** — contextual child terminals attached to individual panes (persistent, per-pane)

The user's workspace is always the home base. Dynamic views are excursions. Pane drawers are local expansions. The user can always return to their workspace.

```
Workspace (user's, persistent)
  ├── Tab "my-project"
  │   ├── Default Pane Arrangement (all panes)
  │   ├── Custom: "coding" (subset)
  │   └── Custom: "testing" (subset)
  │   Each pane:
  │     ├── Content (terminal / webview / code viewer)
  │     └── Drawer (child terminals)
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

## Concept 1: Pane

### Definition
The atomic unit of content. A container holding exactly one thing.

### Content Types
| Type | Description | Example |
|------|-------------|---------|
| Terminal | Ghostty surface | Agent session, shell |
| Webview | Embedded web content | React dev server, diff viewer, PR status |
| Code Viewer | Source code display | File review, code annotations |
| Future | Extensible | Logs, metrics, etc. |

### Properties
- **Identity**: Stable UUID
- **Content type**: Fixed at creation (terminal pane stays terminal)
- **Metadata**: CWD (live), worktree, repo, agent type, parent session, role/tags
- **Drawer**: Optional, holds child terminals (see Concept 3)

### Rules
- A pane belongs to exactly one tab (via that tab's default pane arrangement)
- A pane cannot exist in two tabs simultaneously
- A pane cannot exist without a tab
- Content type is immutable after creation

### Metadata (per session)

| Field | Type | Existing? | Description |
|-------|------|-----------|-------------|
| `id` | UUID | Yes | Stable identity |
| `source` | worktree / floating | Yes | Origin context |
| `repo` | UUID? | Yes (via source) | Associated repository |
| `worktree` | UUID? | Yes (via source) | Associated worktree |
| `cwd` | String | Yes (propagated) | Live current working directory |
| `agentType` | AgentType? | Yes | Agent running in session |
| `parentSessionId` | UUID? | **New** | Parent session (for ephemeral children) |
| `contentType` | ContentType | **New** | Terminal, webview, code viewer |
| `tags` | [String] | **New** | User or system labels for grouping |

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
- Custom arrangements reference sessions from the default set only
- Deleting a pane from default removes it from all custom arrangements
- Sessions not in the active arrangement remain running (backgrounded)
- Switching arrangements changes visibility and tiling; sessions keep running

### Data Model Sketch

```
Tab {
  id: UUID
  name: String
  sessions: [UUID]                         // all sessions in this tab
  arrangements: [PaneArrangement]
  activeArrangementId: UUID
  activeSessionId: UUID?
}

PaneArrangement {
  id: UUID
  name: String
  isDefault: Bool                          // exactly one per tab
  layout: Layout                           // existing split tree type
  visibleSessionIds: Set<UUID>             // subset of tab's sessions
}
```

For default: `visibleSessionIds == tab.sessions` (always)
For custom: `visibleSessionIds ⊆ tab.sessions`

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Switch arrangement | Command bar | Change active arrangement, show/hide panes |
| Create custom | Command bar ("save current as...") | Snapshot visible sessions + tiling |
| Edit custom | Direct manipulation or command bar | Show/hide panes, rearrange tiling |
| Delete custom | Command bar | Remove arrangement, switch to default |
| Rename | Command bar | Update name |

---

## Concept 3: Pane Drawer

### Definition
A collapsible horizontal panel below a pane that holds child terminals tied to the parent pane's context.

### What It Holds
Terminals only. Not webviews, code viewers, or other content types.

### Visual Structure
```
┌─────────────────────────────────┐
│  Pane content                   │
│  (terminal / webview / etc)     │
│                                 │
├─────────────────────────────────┤
│ [t1] [t2] [t3] [+]             │  ← icon bar (drawer items)
│ ┌─────────────────────────────┐ │
│ │ Active drawer terminal      │ │  ← selected item expanded
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### Properties
- **Parent pane**: The pane this drawer is attached to
- **Context inheritance**: Drawer terminals inherit CWD, worktree, repo from parent pane
- **Icon bar**: Shows all drawer terminals, click to switch
- **Collapsible**: Can collapse to icon bar only, or fully hide
- **Navigable**: Keyboard and command bar accessible

### Rules
- Drawer can only exist attached to a parent pane
- Drawer holds terminals only
- Parent pane deletion closes or backgrounds drawer children
- Drawer terminals have `parentSessionId` pointing to parent pane's session
- Drawer state (which terminals, collapsed/expanded) persists with the pane

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Add terminal | Command bar or icon bar [+] | Create child terminal in drawer |
| Switch terminal | Click icon or keyboard | Show different drawer terminal |
| Collapse/expand | Click or keyboard | Toggle drawer visibility |
| Close terminal | Command bar or icon | Remove terminal from drawer |
| Navigate to | Command bar | Focus a specific drawer terminal |

---

## Concept 4: Tab

### Definition
A named group of panes with switchable pane arrangements.

### Properties
- **Sessions**: The full set of panes in this tab
- **Arrangements**: One default + zero or more custom pane arrangements
- **Active arrangement**: Which arrangement is currently displayed
- **Active session**: Which pane has focus

### Rules
- A tab must have at least one pane
- A tab always has exactly one default pane arrangement
- New panes are added to the default arrangement and the current active arrangement
- Closing the last pane closes the tab (with undo)

### Operations
| Operation | Via | Effect |
|-----------|-----|--------|
| Create pane | Command bar | New pane added to default arrangement |
| Delete pane | Command bar | Removed from default and all custom arrangements |
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
- **Live**: Tabs and pane membership update as session metadata changes
- **Interactive**: Full terminal interaction (typing, scrolling) within each tab
- **Non-owning**: Panes remain owned by their home tab in the user's workspace

### Rules
- Dynamic views never own, create, delete, or move panes
- User cannot rearrange the tiling within dynamic view tabs (system-generated only)
- Switching to a dynamic view does not disturb the user's workspace
- Switching back returns to the exact workspace state
- User can switch between dynamic view types while in a dynamic view (e.g., "By Repo" → "By Worktree")
- Recent dynamic view selections are remembered in command bar MRU

### Facet Sources

**Auto-detected (no user setup)**:
- Repo — already tracked per session
- Worktree — already tracked per session
- CWD — already propagated from shell
- Agent type — already tracked
- Parent folder — auto-detected from repo path on disk (e.g., `~/dev/askluna/` groups all repos under it)

**User-configured (requirement now, UX later)**:
- Tags per repo — stored in Agent Studio's own metadata. User assigns tags like "frontend", "backend", "infra" to repos. Sessions inherit tags from their repo.
- Tags per session — direct labels on individual sessions for finer control.
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
- Its drawer (all child terminals)
- Its metadata (CWD, worktree, repo, tags, etc.)

### Rules
- Pane moves from source tab's default arrangement → target tab's default arrangement
- Pane is removed from all custom arrangements in the source tab
- Cannot move to a dynamic view (dynamic views don't own panes)
- Cannot clone — pane exists in exactly one tab at a time
- Cannot move drawer independently of parent pane

### Flow
```
⌘P → "Move pane to Tab: infra"
  1. Remove pane from source tab's default arrangement
  2. Remove pane from source tab's custom arrangements
  3. Add pane to target tab's default arrangement
  4. Drawer children move with pane
```

---

## Concept 7: Command Bar (extended)

### Definition
The central interaction point for all window system operations. All actions route through command bar → action validator → action executor pipeline.

### New Capabilities

| Category | Commands |
|----------|----------|
| Pane Arrangements | Switch arrangement, create custom, edit, delete, rename |
| Dynamic Views | Open by facet, recent queries (MRU), back to workspace |
| Pane Movement | Move pane to tab |
| Pane Drawer | Add terminal to drawer, navigate to drawer terminal, collapse/expand |
| Pane Content | Create webview pane, create code viewer pane |

### Principles
- Command bar is always the primary interaction method
- Keybindings are added later as shortcuts to existing command bar actions
- Recent dynamic view queries appear in MRU for fast re-access
- All commands go through the action validator before execution

---

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Dynamic view structure | Generates tabs (one per group), not a single flat layout |
| Dynamic view navigation | Can switch between view types while in dynamic view (repo → worktree) |
| Parent folder detection | Auto-detected from repo path on disk |
| Tag management UX | Requirement exists now; UX designed later |

## Open Questions

1. **Auto-tiling algorithm for dynamic views**: Equal grid? Most-recently-active gets more space? Does it matter initially?

2. **Pane drawer — max terminals**: Is there a limit on how many terminals a drawer can hold? Or unlimited with scroll in the icon bar?

3. **Custom arrangement creation UX**: "Save current as..." captures visible panes + tiling. Is there also a way to edit which panes are in an arrangement after creation?

4. **Dynamic view — empty groups**: If a repo has no active panes, does it still show as an empty tab in the dynamic view, or is it hidden?

5. **Dynamic view — pane drawers**: When viewing a pane in a dynamic view, are its drawers visible/accessible? Or only the main pane content?
