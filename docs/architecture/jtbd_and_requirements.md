# Jobs To Be Done, Pain Points & Requirements

> Dynamic Window System — Agent Studio

---

## Mission

Agent Studio is a **workspace for agent-assisted development**. It is not just a terminal emulator — it is a context-aware environment where the user stays oriented while multiple coding agents run across multiple projects simultaneously.

The window system's job is to **keep the user oriented** as terminal count grows. It achieves this through rich session metadata, dynamic grouping, contextual auxiliary views, and switchable pane arrangements — so the user never has to hunt for "which terminal was that."

---

## Jobs To Be Done

### Pillar 1: Context Tracking

> Every terminal knows where it came from and what it's doing.

**JTBD 1 — Keep context with every terminal**
When a coding agent launches in a terminal, I want to always know its CWD, worktree, project, and parent agent so I can trace any terminal back to its origin.

**JTBD 2 — Manage ephemeral terminals**
When agents spawn sub-processes (builds, tests, tool use), I want those ephemeral terminals tied to the parent agent session so they don't become orphaned panes I have to hunt through.

**JTBD 3 — Run any coding agent**
When I choose a coding agent (Claude Code, Codex, aider, Cursor CLI, etc.), I want Agent Studio to be agent-agnostic — it provides the workspace, the agent is just a process in a terminal.

### Pillar 2: Dynamic Organization

> The user can see their terminals grouped by what matters right now, not a fixed hierarchy.

**JTBD 4 — Organize agent-assisted work across projects**
When I'm running coding agents across multiple projects and worktrees, I want a workspace that groups terminals, views, and context by project/worktree/role so I don't lose track of what's where.

**JTBD 5 — Compose workspace layouts from dynamic groups**
When I'm focused on a specific task, I want to compose my workspace layout from dynamic groups (by project, by worktree, by terminal role, or custom) so the layout reflects what I care about right now — not a fixed hierarchy.

### Pillar 3: Staying in Flow

> Don't make me leave the workspace to understand what's happening.

**JTBD 6 — See what's happening without context-switching**
When an agent finishes or a service crashes, I want notifications routed to the right workspace group and inline change visibility (diffs, PR status) so I don't alt-tab to GitHub or grep through terminals.

### Pillar 4: Future (inform constraints, not implemented now)

**JTBD 7 — Trust the security boundary** (design now, enforce later)
When agents run in my workspace, I want auth isolation and permission boundaries so credentials can't be exfiltrated across project contexts.

**JTBD 8 — Move sessions between machines** (future)
When I want to continue work on a different machine, I want to teleport my workspace session (layout, groups, terminal state) from local to remote or back.

---

## Pain Points

| # | Pain | Description | Related JTBDs |
|---|------|-------------|---------------|
| P1 | **Terminal explosion** | Each project needs agent terminals, service terminals, debug terminals; count grows fast with zero structure | JTBD 4, 5 |
| P2 | **Static grouping fails** | Need to group by project, worktree, role, or personal preference; no single hierarchy works | JTBD 4, 5 |
| P3 | **Lost context** | Can't tell which terminal belongs to which project/worktree/agent without reading the shell | JTBD 1, 4 |
| P4 | **Orphaned ephemeral terminals** | Agents spawn sub-terminals that aren't tied back to the parent agent context | JTBD 2 |
| P5 | **No workspace composition** | User has a core layout, and dynamic groups should compose into it for the moment; this doesn't exist today | JTBD 5 |
| P6 | **Context-switching for status** | Diffs, PRs, branch status require context-switching out of the workspace | JTBD 6 |
| P7 | **Fragmented context** | Project context is scattered across terminal, editor, browser, GitHub with no shared grouping | JTBD 1, 4, 6 |
| P8 | **Parallelism without tooling** | Agent runs are long, you must multitask, but nothing helps manage concurrent project threads | JTBD 4, 5 |

---

## Requirements

### R1: Rich Session Metadata

Every session must carry sufficient metadata for context tracking and dynamic grouping.

| Field | Description | Source |
|-------|-------------|--------|
| `id` | Stable UUID identity | Existing |
| `repo` | Associated repository | Existing (via source) |
| `worktree` | Associated worktree | Existing (via source) |
| `cwd` | Live current working directory | Existing (propagated) |
| `agentType` | Agent running in this session | Existing |
| `parentSession` | Parent session for ephemeral children | **New** |
| `contentType` | Terminal, webview, code viewer, etc. | **New** |
| `role / tags` | User-defined or auto-detected labels | **New** |

**Solves**: P3, P4, P7 | **Enables**: JTBD 1, 2, 3

### R2: Pane Content Types

Panes must support content beyond terminals. Each pane holds exactly one content type.

- Terminal (Ghostty surface)
- Webview (React app, diffs, PR status)
- Code viewer
- Future: extensible to other types

**Solves**: P6, P7 | **Enables**: JTBD 6

### R3: Pane Drawer

Each pane can have a collapsible drawer below it holding child terminals tied to the parent pane's context.

- Drawer holds terminals only (not webviews or other content)
- Inherits parent pane's CWD, worktree, repo
- Icon bar for switching between drawer terminals
- Navigable via keyboard and command bar
- Parent pane deletion closes or backgrounds drawer children

**Solves**: P1, P4, P6 | **Enables**: JTBD 2, 4, 6

### R4: Pane Arrangements

Each tab supports multiple named layout configurations (pane arrangements) that the user can switch between.

- **Default arrangement**: Exactly one per tab. Contains all panes. Auto-updated on pane creation/deletion.
- **Custom arrangements**: User-created subsets of default's panes in user-defined tilings.
- Switchable via command bar
- Custom arrangements can be created, edited, renamed, deleted
- Sessions not in active arrangement remain running (backgrounded)

**Solves**: P1, P5, P8 | **Enables**: JTBD 4, 5

### R5: Dynamic Views

Computed, read-only lenses that show panes from across all tabs, grouped by a facet. Each dynamic view type generates a tab bar where each tab represents one group.

- **View types**: By repo, by worktree, by CWD, by agent type, by parent folder, by tags (future)
- Each view type generates tabs — one tab per group (e.g., "By Repo" creates one tab per repo)
- Auto-tiled pane layout within each tab (system-generated, not user-arranged)
- Full terminal interaction (typing, scrolling) — read-only refers to layout, not content
- Switchable via command bar with MRU (recent selections remembered)
- Can switch between view types while in a dynamic view
- Panes remain owned by their home tab — dynamic view borrows for display
- Live updates as session metadata changes
- Parent folder auto-detected from repo path on disk
- Tags: requirement exists now, management UX designed later

**Solves**: P1, P2, P3, P5 | **Enables**: JTBD 4, 5

### R6: Pane Movement

Panes can be moved between tabs via command bar.

- Pane moves from source tab's default arrangement to target tab's default arrangement
- Drawer (child terminals) moves with the pane
- Pane removed from any custom arrangements in source tab
- Cannot move to a dynamic view (dynamic views don't own panes)

**Solves**: P1, P2 | **Enables**: JTBD 4

### R7: Command Bar as Central Interaction Point

All window system operations are triggered through the command bar and routed through the action validator/executor pipeline.

- Switch pane arrangements
- Open dynamic views (with MRU)
- Create/delete custom arrangements
- Move panes between tabs
- Open/navigate drawer terminals
- Keybindings added later as shortcuts to command bar actions

**Solves**: P5 | **Enables**: all JTBDs (interaction layer)

---

## Coverage Matrix

```
                    P1       P2       P3       P4       P5       P6       P7       P8
                    terminal static   lost     orphan   no       context  fragment parallel
                    explode  groups   context  ephem    compose  switch   context  tooling

R1: Metadata         .        .       ==        ==       .       .        ==       .
R2: Content Types    .        .        .         .       .       ==       ==       .
R3: Pane Drawer     ==        .        .        ==       .       ==        .       .
R4: Arrangements    ==        .        .         .      ==        .        .      ==
R5: Dynamic Views   ==       ==       ==         .      ==        .        .       .
R6: Pane Movement   ==       ==        .         .       .        .        .       .
R7: Command Bar      .        .        .         .      ==        .        .       .

== = directly solves     . = not primary solve
```
