# Terminal Session Restore: Problem Space & Design Exploration

> **Status:** Work in Progress
> **Last Updated:** 2026-02-03

---

## 1. Problem Statement

Modern development workflows involve long-running terminal processes—coding agents, build watchers, development servers—that should survive application restarts, crashes, and ideally system reboots. A terminal application that loses state when closed forces developers to manually recreate their working context, breaking flow and losing history.

**The core requirement:** When a user reopens the terminal application, they should return to exactly where they left off—same layout, same directories, same running processes, same scrollback.

---

## 2. What "Session" Means

A terminal session encompasses multiple layers of state:

| Layer | Description | Persistence Difficulty |
|-------|-------------|------------------------|
| **Layout** | Window positions, tab order, pane splits | Easy (serialize to file) |
| **Working directories** | CWD for each terminal | Easy (serialize paths) |
| **Commands** | What was running in each terminal | Medium (can re-execute) |
| **Running processes** | Actual live processes with state | Hard (requires daemon) |
| **Scrollback** | Terminal history and output | Medium (large data) |
| **In-process state** | Variables, memory, network connections | Nearly impossible |

**Key insight:** There's a spectrum from "layout restore" (trivial) to "full process continuation" (requires background daemon).

---

## 3. Terminal Usage Patterns

Different developers use terminals differently. The session restore solution must support all patterns.

### 3.1 Single-Terminal Focus

**Pattern:** One terminal per task, deep focus on a single worktree.

```
Window
└── Single terminal
    └── Working on: feature-x
```

**Requirements:**
- Remember which worktree was open
- Restore CWD and running command
- Preserve scrollback for context

### 3.2 Multi-Terminal Grid

**Pattern:** Power users running 3-8 terminals in parallel, often in the same worktree.

```
Window (3x3 grid)
├── Terminal 1: coding agent (main task)
├── Terminal 2: coding agent (refactoring)
├── Terminal 3: coding agent (tests)
├── Terminal 4: dev server
├── Terminal 5: build watcher
└── Terminal 6: git operations
```

**Requirements:**
- Preserve pane layout (splits, sizes)
- Each pane may have different process
- Quick spawning of N terminals
- Session survives stepping away

### 3.3 Repo-Centric Workspaces

**Pattern:** Each repository gets its own window with worktree tabs.

```
Window: project-alpha
├── Tab: main
├── Tab: feature-auth
└── Tab: hotfix-123

Window: project-beta
├── Tab: main
└── Tab: experiment
```

**Requirements:**
- Clear window-to-repo mapping
- Tabs represent worktrees
- Window title shows repo context
- Can open "all worktrees" at once

### 3.4 Mixed Multi-Repo

**Pattern:** Single window with terminals from different repos.

```
Window
├── Tab: alpha/main
├── Tab: alpha/feature
├── Tab: beta/main
└── Tab: shared-lib/main
```

**Requirements:**
- Terminals from multiple repos coexist
- Clear labeling of which repo each belongs to
- Search/jump across all terminals

### 3.5 Side-by-Side Comparison

**Pattern:** Two or more terminals visible simultaneously for comparison or coordination.

```
Window
├── Left pane: worktree-A (agent implementing)
└── Right pane: worktree-B (agent reviewing)
```

**Requirements:**
- Horizontal/vertical splits
- Drag-and-drop pane rearrangement
- Resize panes fluidly

---

## 4. Session Persistence Models

There are fundamentally different architectural approaches to session persistence.

### 4.1 Daemon Model (Server-Client)

A background server process owns the terminal PTYs. GUI clients connect and disconnect without affecting running processes.

```
┌─────────────────────────────────┐
│  Daemon (background process)    │
│  - Owns all PTYs                │
│  - Keeps processes alive        │
│  - Survives client disconnect   │
└─────────────────────────────────┘
          ▲           ▲
          │           │
    ┌─────┴───┐  ┌────┴────┐
    │ Client 1│  │ Client 2│
    │ (GUI)   │  │ (GUI)   │
    └─────────┘  └─────────┘
```

**Characteristics:**
- Processes truly continue running
- Survives app crash (daemon still running)
- Does NOT survive system reboot (daemon dies)
- Requires background service management
- Multiple clients can view same session

**Examples in ecosystem:** tmux, Zellij, WezTerm mux mode

### 4.2 File-Based Model (Serialize-Restore)

Session state is serialized to disk. On restore, layout is recreated and commands are re-executed.

```
App Running                    App Closed                    App Restored
┌─────────┐                   ┌─────────┐                   ┌─────────┐
│ Layout  │  ──serialize──►   │ .json   │  ──deserialize──► │ Layout  │
│ + state │                   │ file    │                   │ + re-exec│
└─────────┘                   └─────────┘                   └─────────┘
```

**Characteristics:**
- Processes stop when app closes
- Commands re-execute on restore
- Survives system reboot (file persists)
- Simpler architecture (no daemon)
- State may drift from saved file

**Examples in ecosystem:** Kitty sessions, iTerm arrangements

### 4.3 Hybrid Model

Combine daemon for runtime persistence with file-based for reboot survival.

```
Runtime: Daemon keeps processes alive
         ↓
On quit: Serialize state to file
         ↓
On reboot: Restore from file + re-execute commands
```

**Characteristics:**
- Best of both worlds
- Crash recovery via daemon
- Reboot recovery via file
- More complex implementation

---

## 5. What Survives in Each Model

| Scenario | Daemon Model | File Model | Hybrid |
|----------|--------------|------------|--------|
| App crash (OS running) | Processes live | Processes die | Processes live |
| App quit + reopen | Reconnect | Re-execute | Reconnect |
| System reboot | Processes die* | Re-execute | Re-execute |
| Sleep/wake | Processes live | Depends | Processes live |

*Daemon model can serialize on shutdown to enable re-execution on reboot.

**Critical realization:** No model preserves actual process memory across reboot. "Session restore" after reboot always means re-launching commands in the right directories with the right layout.

For coding agents (like Claude Code): The terminal restarts the agent in the same worktree. The agent's conversation history is in the cloud, so context is largely preserved.

---

## 6. Hierarchy and Mental Model

Based on exploration, the cleanest mental model for a worktree-centric workflow:

```
Repo (git repository)
└── Worktrees (branches checked out in parallel)
    └── Terminals (one or more per worktree)
```

Mapping to UI:

| Concept | UI Element |
|---------|------------|
| Repo | Window (with clear title) |
| Worktree | Tab |
| Terminal | Pane (within tab) |

This means:
- Opening a repo → new window
- Adding a worktree → new tab in that window
- Splitting terminal → new pane in that tab
- Window title → repo name
- Tab title → worktree/branch name

---

## 7. Workflow Requirements

### 7.1 Navigation

- **Search:** Find any repo, worktree, or terminal by name
- **Recents:** Quick access to recently used terminals
- **Jump:** Keyboard shortcut to switch terminals instantly

### 7.2 Spawning

- **Open repo:** Open window with selected worktrees as tabs
- **Open all worktrees:** Spawn tabs for every worktree in repo
- **New terminal:** Add terminal to current worktree
- **New with agent:** Spawn terminal + start coding agent with prompt

### 7.3 Layout

- **Split panes:** Horizontal and vertical splits
- **Drag/drop:** Rearrange panes and tabs
- **Resize:** Fluid pane resizing

### 7.4 IDE Integration

- **Open in editor:** Button to open worktree in VS Code/Cursor
- **Quick commands:** Post commands to terminal via UI

### 7.5 Persistence

- **Crash recovery:** Processes survive app crash
- **Quit/reopen:** Return to exact state
- **Reboot recovery:** Restore layout + re-execute commands

---

## 8. Solution Exploration

### 8.1 Option A: Zellij as Persistence Layer

Use Zellij as the session daemon. Agent Studio becomes a GUI that manages Zellij sessions.

**Architecture:**
```
Agent Studio (GUI)
├── Manages which Zellij sessions exist
├── Provides sidebar, search, quick actions
├── Renders via Ghostty surfaces
└── Each surface runs: zellij attach <session>

Zellij (daemon)
├── Owns all PTYs
├── Handles pane/tab management
├── Serializes to ~/.cache/zellij/
└── Survives app crashes
```

**Pros:**
- Proven persistence implementation
- Native pane/tab management
- CLI for programmatic control
- Already in the dependency tree

**Cons:**
- Visible Zellij chrome (can minimize)
- Keyboard-centric (limited mouse)
- Two mental models (Agent Studio + Zellij)
- State sync complexity

**Mapping:**
```
Agent Studio Window  →  Zellij session (named: repo)
Agent Studio Tab     →  Zellij tab (named: worktree)
Agent Studio Pane    →  Zellij pane
```

### 8.2 Option B: Custom Daemon

Build our own session daemon purpose-built for Agent Studio.

**Architecture:**
```
agentstudio-daemon (background service)
├── Creates/owns PTYs
├── Manages sessions (repos) and panes (worktrees)
├── Exposes Unix socket for IPC
├── Serializes state periodically
└── Survives GUI crashes

Agent Studio (GUI)
├── Connects to daemon via socket
├── Receives terminal output
├── Sends user input
├── Manages UI state
└── Can disconnect/reconnect
```

**Pros:**
- Full control over protocol
- No visible external UI
- Optimized for our use case
- Native macOS feel

**Cons:**
- Significant implementation effort
- Must solve PTY management
- Must build serialization
- Must handle process lifecycle

### 8.3 Option C: WezTerm Mux Model

WezTerm has a built-in multiplexer that can run as a headless daemon.

**How it works:**
- `wezterm-mux-server` daemon owns PTYs via Unix socket
- GUI clients connect/disconnect without affecting sessions
- Sessions survive client closure while daemon runs
- **No built-in disk serialization** — state is purely in-memory

**Protocol:**
- Binary PDU format over Unix domain socket
- `leb128` length encoding
- **Undocumented and proprietary** — not interoperable with other terminals
- Version-sensitive: client/server must match WezTerm versions

**CLI control available:**
```bash
wezterm cli spawn -- command      # Spawn new pane
wezterm cli list                  # List sessions/panes
wezterm cli send-text "input"     # Send to pane
```

**For Agent Studio evaluation:**

| Aspect | Assessment |
|--------|------------|
| Session persistence | In-memory only, lost on daemon crash |
| Disk persistence | Requires external plugin (resurrect.wezterm) |
| Protocol | Undocumented binary, version-sensitive |
| CLI control | Good — spawn, list, send-text |
| Integration | Would require replacing Ghostty with WezTerm |

**Verdict:** WezTerm's mux is tightly coupled to WezTerm rendering. Using it would mean abandoning Ghostty. The undocumented protocol and lack of built-in persistence make it less suitable than Zellij for our use case.

### 8.4 Option D: Hybrid (Zellij + File Checkpoints)

**Recommended approach.** Use Zellij for runtime, add file-based layer for reboot survival.

**Architecture:**
```
Runtime:
  Agent Studio → Zellij daemon → PTYs

On app quit:
  Serialize current state to JSON:
  - Which sessions exist
  - Which tabs/panes in each
  - CWDs and last commands

On system reboot:
  1. Check for running Zellij sessions
  2. If none, restore from JSON checkpoint
  3. Re-create sessions + re-execute commands
```

**Pros:**
- Zellij handles the hard runtime stuff
- File checkpoint adds reboot resilience
- Clear separation of concerns

**Cons:**
- Two persistence mechanisms
- Must keep checkpoint in sync

---

## 9. Solution Comparison Matrix

| Criteria | Zellij | WezTerm Mux | Custom Daemon | File-Only |
|----------|--------|-------------|---------------|-----------|
| **Crash recovery** | Daemon survives | Daemon survives | Daemon survives | Lost |
| **Reboot recovery** | Resurrect from cache | External plugin | Must implement | File persists |
| **Disk persistence** | Built-in (KDL) | None (external) | Must implement | Native |
| **Protocol** | CLI + documented | Undocumented binary | Full control | N/A |
| **Ghostty compatible** | Yes (run inside) | No (replaces) | Yes | Yes |
| **Implementation effort** | Low | High | Very high | Low |
| **Community/ecosystem** | Active, growing | Mature | None | N/A |

**Recommendation: Option D (Zellij + File Checkpoints)**

Rationale:
1. Zellij handles the hard runtime persistence (PTY ownership, daemon lifecycle)
2. Built-in resurrection covers most reboot scenarios
3. CLI interface enables Agent Studio to control sessions programmatically
4. Ghostty remains the renderer (no replacement needed)
5. File checkpoints add extra safety for edge cases
6. Worktrunk integration is natural (both designed for parallel agents)

---

## 10. Integration with Worktree Management

The session system should integrate with git worktree tooling.

**Expected workflow:**
```bash
# Create worktree + terminal in one action
wt switch -c feature-auth

# Agent Studio detects new worktree
# Offers to open terminal for it

# Or: from Agent Studio UI
# Click "New Worktree" → creates via wt → opens terminal
```

**Data flow:**
```
Worktree tool (wt/worktrunk)
  ↓ discovers worktrees
Agent Studio SessionManager
  ↓ maps to sessions
Zellij / Daemon
  ↓ owns terminals
Ghostty
  ↓ renders
```

---

## 11. Open Questions

1. **Should Agent Studio hide Zellij UI completely?**
   - Pros: Native feel
   - Cons: Complex state sync, lose Zellij features

2. **How to handle multiple windows per repo?**
   - Same Zellij session attached in both?
   - Separate sessions that sync?

3. **What's the session naming scheme?**
   - Must be short (Unix socket path limits: ~108 bytes)
   - Must be stable across renames
   - Suggestion: `repo-name` or `parent--repo-name`

4. **How to discover externally-created sessions?**
   - User runs `zellij` directly in terminal
   - Should Agent Studio see and manage it?

5. **What's the reboot UX?**
   - Transparent re-execution?
   - Prompt user "Restore previous session?"
   - Show what's being restored?

---

## 12. Invisible Zellij: Experimental Validation

**Objective:** Validate that Zellij can operate "invisibly" - no visible UI chrome, all keyboard shortcuts pass through, controlled entirely via CLI.

### 12.1 Configuration for Invisible Mode

Tested with Zellij 0.43.1:

```kdl
// invisible.kdl - Agent Studio Zellij Configuration

// Start in locked mode - all keys pass through to terminal
default_mode "locked"

// Clear ALL default keybindings - Zellij intercepts nothing
keybinds clear-defaults=true {
    // Optional escape hatch for testing (production: use zellij kill-session)
    locked {
        bind "Ctrl q" { Quit; }
    }
}

// Disable visual elements
pane_frames false
simplified_ui true
show_startup_tips false
show_release_notes false

// Session persistence
session_serialization true
serialize_pane_viewport true
scrollback_lines_to_serialize 10000

// Disable mouse (Agent Studio handles mouse events)
mouse_mode false

// Large scrollback
scroll_buffer_size 50000
```

### 12.2 Minimal Layout (No Bars)

```kdl
// minimal.kdl - No tab-bar, no status-bar
layout {
    pane command="bash"
}
```

**Key finding:** The default Zellij layout includes `tab-bar` and `status-bar` plugins. To remove them, you MUST use a custom layout file that omits these plugins.

### 12.3 Verified Capabilities

| Capability | Status | Notes |
|------------|--------|-------|
| Create background session | ✅ | `zellij attach <name> --create-background` |
| List sessions | ✅ | `zellij list-sessions` |
| Query tab names | ✅ | `zellij action query-tab-names` |
| Rename tabs | ✅ | `zellij action rename-tab` |
| Create new tabs | ✅ | `zellij action new-tab --name <name>` |
| Dump layout | ✅ | `zellij action dump-layout` |
| Kill session | ✅ | `zellij kill-session <name>` |
| No visible bars | ✅ | Requires custom minimal layout |
| Locked mode (key passthrough) | ✅ | `default_mode "locked"` + `keybinds clear-defaults=true` |

### 12.4 Client Attachment Model

**Important discovery:** Some `zellij action` commands require an attached client:

- `go-to-tab`, `switch-mode`, `write-chars` - need a client viewing the session
- `query-tab-names`, `dump-layout`, `new-tab` - work without a client

**Implication for Agent Studio:**
1. Create Zellij session with `--create-background`
2. Each Ghostty surface runs `zellij attach <session>` as its command
3. Ghostty becomes the "client" - provides PTY for rendering
4. Once attached, all `zellij action` commands work

### 12.5 Integration Pattern

```
┌───────────────────────────────────────────────────────────┐
│  Agent Studio                                              │
│  ┌─────────────────┐     ┌────────────────────────────┐   │
│  │  SessionManager │────►│ zellij attach <session>    │   │
│  │                 │     │ --create-background        │   │
│  └─────────────────┘     └────────────────────────────┘   │
│           │                                               │
│           ▼                                               │
│  ┌─────────────────┐     ┌────────────────────────────┐   │
│  │  GhosttySurface │────►│ command: zellij attach X   │   │
│  │  (per worktree) │     │ (becomes Zellij client)    │   │
│  └─────────────────┘     └────────────────────────────┘   │
│           │                                               │
│           ▼                                               │
│  ┌─────────────────┐                                      │
│  │  zellij action  │◄───── Tab/pane control               │
│  │  CLI commands   │                                      │
│  └─────────────────┘                                      │
└───────────────────────────────────────────────────────────┘
```

### 12.6 Remaining Questions

1. **Mouse events in locked mode:** Does `mouse_mode false` affect mouse interaction in the terminal?
2. **Scrollback behavior:** Does locked mode affect scrollback with mouse wheel?
3. **Performance:** What's the overhead of Zellij layer between Ghostty and shell?

---

## 13. Next Steps

1. **Implement Invisible Zellij Prototype**
   - Create `ZellijService` in Agent Studio
   - Ghostty surface running `zellij attach <session>`
   - Verify keyboard passthrough in real app
   - Test mouse scrollback behavior

2. **Design session naming scheme**
   - Short, stable identifiers for repos/worktrees
   - Handle Unix socket path limits (~108 bytes)
   - Suggestion: `agentstudio--<repo-hash>` or `agentstudio--<repo-name>`

3. **Design checkpoint file format**
   - JSON schema for session state
   - What's the minimum viable data?

4. **Define Agent Studio ↔ Zellij mapping**
   - How tabs/panes translate
   - How to sync state bidirectionally

5. **Integrate with Worktrunk**
   - Discover worktrees via `wt list`
   - Spawn agents via `wt switch -x claude`

---

## 14. References

### Session Persistence
- [Zellij Documentation](https://zellij.dev/documentation/)
- [Zellij Session Resurrection](https://zellij.dev/documentation/session-resurrection.html)
- [WezTerm Multiplexing](https://wezterm.org/multiplexing.html)
- [WezTerm resurrect.wezterm plugin](https://mwop.net/blog/2024-10-21-wezterm-resurrect.html)
- [Kitty Sessions](https://sw.kovidgoyal.net/kitty/sessions/)

### Worktree Management
- [Worktrunk](https://worktrunk.dev/)
- [Git Worktrees for AI Agents (Nx Blog)](https://nx.dev/blog/git-worktrees-ai-agents)

### Power User Workflows
- [Simon Willison: Parallel Coding Agents](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/)
- [Peter Steinberger: AI Dev Workflow](https://steipete.me/posts/2025/optimal-ai-development-workflow)
- [Claude Squad: Multi-agent Terminal Manager](https://github.com/smtg-ai/claude-squad)
