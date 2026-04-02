# Command Bar Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a status strip to the command bar (showing mode + app context), and fix existing visual bugs (display names, redundancy, height collapse, scope icon duplication).

**Architecture:** A new `CommandBarStatusStrip` view sits above the search field, reading mode directly from `ManagementModeMonitor` (singleton `@Observable`) and app context derived from `WorkspaceStore`'s active pane — both via SwiftUI observation, not mutable copies. Fix display names in `CommandBarDataSource` for the command bar specifically (without modifying `PaneDisplayProjector` which other views depend on). Investigate and fix the panel height collapse bug.

**Non-goals for this plan:** Context-aware command filtering (the data source API remains `scope/store/repoCache/dispatcher`). Management-mode bare-key shortcuts (those require key-routing changes in `ManagementModeMonitor` and `CommandBarTextField` which are a separate effort).

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (NSPanel)

---

## Visual Spec — Before & After

### BEFORE: Everything scope (⌘P)

```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║  🔍  Search or jump to...                                         ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Tabs                                                             ║
║  ▐ □ agent-studio | main | agent-studio | agent-studio | main...  ║
║                                                    Active · Tab 1 ║
║  Panes                                                            ║
║  ▐ ▷ agent-studio | main | agent-studio        Tab 1 · Active    ║
║  ▐ ▷ agent-studio | main | agent-studio        Tab 1             ║
║  ▐ ▷ agent-studio | main | agent-studio        Tab 1             ║
║                                                                   ║
║  Commands                                                         ║
║  ▐ ▢ Add Drawer Pane                                              ║
║  ▐ ▢ Add Folder                                       ⌘ ⇧ ⌥ 0   ║
║  ▐ ▢ Add Repo                                         ⌘ ⇧ 0     ║
║  ▐ ▢ Break Up Tab                                                 ║
║  ▐ ▢ Close Drawer Pane                                            ║
║  ▐ ▢ Close Pane...                  (dimmed)               ▸     ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W       ║
║  ▐ ▢ Delete Arrangement...                                  ▸    ║
║  ▐ ▢ Equalize Panes                                              ║
║  ▐ ▢ Expand Pane                                                  ║
║  ...more...                                                       ║
║                                                                   ║
║  Worktrees                                                        ║
║  ▐ ⑂ agent-studio                              agent-studio      ║
║  ...                                                              ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                               ║
╚═══════════════════════════════════════════════════════════════════╝

PROBLEMS:
  • No status strip — no mode or context awareness
  • Tab title: concatenates ALL pane labels ("repo | branch | folder | repo | branch | folder...")
    Source: PaneDisplayProjector.tabDisplayLabel joins pane labels with " | "
  • Pane titles: all three show identical "agent-studio | main | agent-studio"
    No way to distinguish panes in the same repo
  • Commands alphabetically sorted ("Add Drawer Pane" first — not useful)
```

### AFTER: Everything scope (⌘P), normal mode, terminal active

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  🔍  Search or jump to...                                        ║
╠═══════════════════════════════════════════════════════════════════╣
║  Tabs                                                            ║
║  ▐ □ agent-studio                        Active · Tab 1 · 3 panes║
║                                                                  ║
║  Panes                                                           ║
║  ▐ ▷ Terminal — main                          Tab 1 · Active     ║
║  ▐ ▷ Terminal — main                          Tab 1              ║
║  ▐ 🌐 Webview — localhost:3000                 Tab 1              ║
║                                                                  ║
║  Commands                          (alphabetical, unchanged)      ║
║  ▐ ▢ Add Drawer Pane                                             ║
║  ▐ ▢ Add Folder                                       ⌘ ⇧ ⌥ 0  ║
║  ▐ ▢ Add Repo                                         ⌘ ⇧ 0    ║
║  ▐ ▢ Break Up Tab                                                ║
║  ▐ ▢ Close Drawer Pane                                           ║
║  ▐ ▢ Close Pane...                  (dimmed)               ▸    ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W      ║
║  ...                                                             ║
║                                                                  ║
║  Worktrees                                                       ║
║  ▐ ⑂ agent-studio                          agent-studio         ║
║  ...                                                             ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ Status strip at top: mode (left), context (right)
  ✓ Tab title: "agent-studio" (repo name, not concatenated pane labels)
  ✓ Tab subtitle: "Active · Tab 1 · 3 panes" (includes pane count)
  ✓ Pane titles: "Terminal — main" / "Webview — localhost:3000"
  ✓ Pane labels more informative (content type + detail, not guaranteed unique)
  ✗ Command ordering unchanged (alphabetical within "Commands" group)
```

### AFTER: Everything scope, normal mode, WEBVIEW active

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           🌐 Webview   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  🔍  Search or jump to...                                        ║
╠═══════════════════════════════════════════════════════════════════╣
║  ...same items, but context icon reflects active pane...         ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ Context reads live from active pane → shows "🌐 Webview"
```

### BEFORE: Commands scope (> prefix)

```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║  ≫  >                                                             ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Pane                                                             ║
║  ▐ ▢ Add Drawer Pane                                              ║
║  ▐ ▢ Close Drawer Pane                                            ║
║  ▐ ▢ Close Pane...                  (dimmed)               ▸     ║
║  ...                                                              ║
║  Focus                                                            ║
║  ▐ ▢ Focus Next Pane                                              ║
║  ...                                                              ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                               ║
╚═══════════════════════════════════════════════════════════════════╝

PROBLEMS:
  • No status strip
  • "≫ >" — scope icon visible even though ">" is in the text (minor duplication)
```

### AFTER: Commands scope (> prefix), normal mode

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  >                                  ← scope icon HIDDEN          ║
╠═══════════════════════════════════════════════════════════════════╣
║  Pane                                                            ║
║  ▐ ▢ Add Drawer Pane                                             ║
║  ▐ ▢ Close Drawer Pane                                           ║
║  ▐ ▢ Close Pane...                  (dimmed)               ▸    ║
║  ▐ ▢ Equalize Panes                                             ║
║  ▐ ▢ Extract Pane to Tab...                                ▸    ║
║  ▐ ▢ Move Pane to Tab...                                   ▸    ║
║  ▐ ▢ Split Left                                                  ║
║  ▐ ▢ Split Right                                                 ║
║  ▐ ▢ Toggle Drawer                                               ║
║  Focus                                                           ║
║  ▐ ▢ Focus Next Pane                                             ║
║  ▐ ▢ Focus Pane Down                                             ║
║  ▐ ▢ Focus Pane Left                                             ║
║  ▐ ▢ Focus Pane Right                                            ║
║  ▐ ▢ Focus Pane Up                                               ║
║  Tab                                                             ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W      ║
║  ▐ ▢ Break Up Tab                                                ║
║  ▐ ▢ New Terminal in Tab                                         ║
║  ...                                                             ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ Status strip always present
  ✓ Scope icon HIDDEN — prefix ">" visible in text, no duplication
  ✓ Height STABLE — same panel height as everything scope
```

### AFTER: Commands scope (> prefix), searching "close"

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  > close                            ← scope icon hidden          ║
╠═══════════════════════════════════════════════════════════════════╣
║  Pane                                                            ║
║  ▐ ▢ Close Pane...                  (dimmed)               ▸    ║
║  ▐ ▢ Close Drawer Pane                                          ║
║  Tab                                                             ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W      ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝
```

### BEFORE: Repos scope (# prefix)

```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║  #  #                                ← DOUBLED: icon + typed char ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  agent-studio                                                     ║
║  ▐ ★ ★ agent-studio                 agent-studio    ← TRIPLED    ║
║                                                                   ║
║  agent-studio.ghostty-runtime-isolation-split                     ║
║  ▐ ★ ★ agent-studio.ghostty-runt... agent-studio.ghostty-runt... ║
║                                                                   ║
║  agent-studio.luna-295-stable-terminal-host                       ║
║  ▐ ★ ★ agent-studio.luna-295-st...  agent-studio.luna-295-st...  ║
║                                                                   ║
║  askluna                                                          ║
║  ▐ ★ ★ askluna                      askluna                      ║
║                                                                   ║
║  askluna-agent-design                                             ║
║  ▐ ★ ★ askluna-agent-design         askluna-agent-design         ║
║                                                                   ║
║  ...8 more repos, each 1 header + 1 item...                      ║
║                                                  ← HEIGHT COLLAPSED║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                               ║
╚═══════════════════════════════════════════════════════════════════╝

PROBLEMS:
  • "# #" — scope icon duplicates typed prefix character
  • "★ ★ agent-studio  agent-studio" — TRIPLE redundancy:
    star icon + "★" char in title + subtitle repeats title
  • Every repo gets its own group header, even with ONE worktree
    → 50% vertical space wasted on headers
  • Long worktree names truncated in title AND subtitle
  • Panel height collapsed and doesn't restore when switching scopes
```

### AFTER: Repos scope (# prefix), normal mode

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  # agent                            ← scope icon hidden          ║
╠═══════════════════════════════════════════════════════════════════╣
║  Repos                              ← flat group for 1-wt repos  ║
║  ▐ ★ agent-studio                       main worktree            ║
║  ▐ ★ askluna                            main worktree            ║
║  ▐ ★ askluna-agent-design               main worktree            ║
║                                                                   ║
║  agent-studio (worktrees)            ← per-repo group for multi   ║
║  ▐ ★ agent-studio                       main worktree            ║
║  ▐ ⑂ ghostty-runtime-isolation-split                             ║
║  ▐ ⑂ luna-295-stable-terminal-host                               ║
║  ▐ ⑂ luna-337-domain-models                                      ║
║  ▐ ⑂ ux-fixes-helpers                                            ║
║                                                                   ║
║  askluna (worktrees)                                              ║
║  ▐ ★ askluna                            main worktree            ║
║  ▐ ⑂ finance                                                     ║
║  ▐ ⑂ finance-rlvr-forking                                        ║
║  ▐ ⑂ finance.rlvr-art-patches                                    ║
║                                                                   ║
║                                      ← height STABLE, not collapsed║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ No "# #" — scope icon hidden when prefix in text
  ✓ No "★" in title text — star icon is enough
  ✓ Subtitle: "main worktree" for main, nothing for branches
  ✓ Single-worktree repos in flat "Repos" group — no per-repo header waste
  ✓ Multi-worktree repos get "repoName (worktrees)" headers
  ✓ Panel height stable across scope switches
```

### BEFORE: Drill-in (Close Pane → pick target)

```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║  ┌─────────────────────────┐                                      ║
║  │ Commands · Close Pane ⊗ │                                      ║
║  └─────────────────────────┘                                      ║
║  🔍  Filter...                                                    ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Panes                                                            ║
║  ▐ ▷ agent-studio | main | agent-studio       Tab 1              ║
║  ▐ ▷ agent-studio | main | agent-studio       Tab 1              ║
║  ▐ ▷ agent-studio | main | agent-studio       Tab 1              ║
║                          ^^^ all identical, can't tell apart      ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Select   ⌫ Back   ↑↓ Navigate   esc Dismiss                    ║
╚═══════════════════════════════════════════════════════════════════╝

PROBLEMS:
  • No status strip
  • All pane targets show identical labels — can't pick the right one
```

### AFTER: Drill-in, normal mode

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  ┌─────────────────────────┐                                     ║
║  │ Commands · Close Pane ⊗ │                                     ║
║  └─────────────────────────┘                                     ║
║  🔍  Filter...                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Panes                                                           ║
║  ▐ ▷ Terminal — main                          Tab 1              ║
║  ▐ ▷ Terminal — main                          Tab 1              ║
║  ▐ 🌐 Webview — localhost:3000                 Tab 1              ║
║           ^^^ more informative (not unique if same worktree)      ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Select   ⌫ Back   ↑↓ Navigate   esc Dismiss                   ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ Status strip persists through drill-in
  ✓ Pane labels more informative in target selection
```

### AFTER: Drill-in, management mode

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦▪ Manage                                          ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  ┌─────────────────────────┐                                     ║
║  │ Commands · Close Pane ⊗ │                                     ║
║  └─────────────────────────┘                                     ║
║  🔍  Filter...                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Panes                                                           ║
║  ▐ ▷ Terminal — main                          Tab 1              ║
║  ▐ ▷ Terminal — feature-branch                Tab 2              ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Select   ⌫ Back   ↑↓ Navigate   esc Dismiss                   ║
╚═══════════════════════════════════════════════════════════════════╝
```

### AFTER: Management mode, everything scope

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦▪ Manage                                          ⌨ Terminal   ║
║  ~~accent~~                                                      ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  🔍  Search or jump to...                                        ║
╠═══════════════════════════════════════════════════════════════════╣
║  Tabs                                                            ║
║  ▐ □ agent-studio                        Active · Tab 1 · 3 panes║
║                                                                  ║
║  Panes                                                           ║
║  ▐ ▷ Terminal — main                          Tab 1 · Active     ║
║  ▐ ▷ Terminal — main                          Tab 1              ║
║  ▐ 🌐 Webview — localhost:3000                 Tab 1              ║
║                                                                  ║
║  Commands                                                        ║
║  ▐ ▢ Split Right                                       ⌘ ⇧ R    ║
║  ▐ ▢ Add Drawer Pane                                             ║
║  ▐ ▢ Close Pane...                                         ▸    ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W      ║
║  ...                                                             ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ "▦▪ Manage" in ACCENT COLOR (blue) — matches toolbar button icon
  ✓ Context still muted on right
  ✓ Footer unchanged (no bare-key hints — separate effort)
```

### AFTER: Management mode, > scope, searching "close"

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦▪ Manage                                          ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  > close                                                         ║
╠═══════════════════════════════════════════════════════════════════╣
║  Pane                                                            ║
║  ▐ ▢ Close Pane...                                         ▸    ║
║  ▐ ▢ Close Drawer Pane                                          ║
║  Tab                                                             ║
║  ▐ ✕ Close Tab...                                    ▸ ⌘ W      ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝
```

### AFTER: Panes scope ($ prefix), normal mode

```
╔═══════════════════════════════════════════════════════════════════╗
║  ▦ Normal                                           ⌨ Terminal   ║
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·  ║
║  $ term                              ← scope icon hidden         ║
╠═══════════════════════════════════════════════════════════════════╣
║  Tab 1: agent-studio                                             ║
║  ▐ □ agent-studio                        Active Tab              ║
║  ▐ ▷ Terminal — main                     Active Pane             ║
║  ▐ ▷ Terminal — main                                             ║
║  ▐ 🌐 Webview — localhost:3000                                    ║
╠═══════════════════════════════════════════════════════════════════╣
║  ↵ Open   ↑↓ Navigate   esc Dismiss                              ║
╚═══════════════════════════════════════════════════════════════════╝

CHANGES:
  ✓ Prefix changed from @ to $ (shell prompt association)
  ✓ Searches pane cwd, branch, repo, worktree — not just display title
```

---

## Vertical Layout Structure

```
╔══════════════════════════════════════════════════════════════╗
║  [mode icon] [mode label]      [ctx icon] [ctx label]       ║  STATUS STRIP (~28pt)
║  · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ║  thin separator
║  ┌──────────────────────┐                                   ║  SCOPE PILL
║  │ breadcrumb (if nested)│                                   ║  (conditional)
║  └──────────────────────┘                                   ║
║  [scope icon]  [search text _______________]                ║  SEARCH (44pt)
╠══════════════════════════════════════════════════════════════╣  divider
║  [Group Header]                                             ║  RESULTS
║  [  result row  ]                                           ║  (scrollable)
║  [  result row  ]                                           ║
╠══════════════════════════════════════════════════════════════╣  divider
║  [keyboard hints]                                           ║  FOOTER (32pt)
╚══════════════════════════════════════════════════════════════╝
```

### Status strip styling

| Element | Normal Mode | Management Mode |
|---------|-------------|-----------------|
| Mode icon | `rectangle.split.2x2` (outline) | `rectangle.split.2x2.fill` (accent) |
| Mode label | "Normal", 0.35 opacity | "Manage", accent color |
| Context icon | pane-type icon, 0.35 opacity | same |
| Context label | pane-type name, 0.35 opacity | same |

### Context icon mapping

| Active Pane Content | Icon | Label |
|---------------------|------|-------|
| Terminal | `terminal` | Terminal |
| Webview | `globe` | Webview |
| Bridge Panel | `rectangle.split.2x1` | Bridge |
| Code Viewer | `doc.text` | Code Viewer |
| No active pane | `terminal` | Terminal |

### Scope icon behavior

| State | Left icon | Reasoning |
|-------|-----------|-----------|
| No prefix typed | `magnifyingglass` | Default search icon |
| Prefix typed (`>`, `$`, `#`) | **Hidden** | Prefix char visible in text — icon would duplicate it |
| Nested (drill-in) | `magnifyingglass` | Scope pill shows context, icon stays default |

### Data flow — mode and context are live-observed

```
ManagementModeMonitor.shared ──(@Observable)──► CommandBarView.currentMode
                                                       │
WorkspaceStore.activeTabId ──(@Observable)──────────────┤
WorkspaceStore.pane(activePaneId).content ──────────────┤
                                                       ▼
                                              CommandBarStatusStrip(
                                                  mode: currentMode,
                                                  context: currentContext
                                              )

NOT stored on CommandBarState — derived live in CommandBarView.
If user toggles management mode while bar is open, strip updates immediately.
```

---

## Change Summary

| What | Before | After |
|------|--------|-------|
| Status strip | none | mode (left) + context (right), always visible |
| Mode display | none | `▦ Normal` (muted) or `▦▪ Manage` (accent) |
| Context display | none | `⌨ Terminal` / `🌐 Webview` / etc. (muted) |
| Tab title | `"repo \| branch \| folder \| repo \| branch..."` | `"repo-name"` (active pane's repo) |
| Tab subtitle | `"Active · Tab 1"` | `"Active · Tab 1 · 3 panes"` |
| Pane title | `"repo \| branch \| folder"` (all identical) | `"Terminal — branch"` / `"Webview — host"` (more informative, not guaranteed unique) |
| Scope icon with prefix | Shows (e.g., `# #`) | Hidden (prefix in text is enough) |
| Repo scope: title | `"★ repo-name"` | `"repo-name"` (star icon suffices) |
| Repo scope: subtitle | repeats title | `"main worktree"` or nothing |
| Repo scope: grouping | 1 header per repo (wasteful) | flat "Repos" group for 1-wt repos |
| Panel height on scope switch | collapses, doesn't restore | stable across all scopes |
| Panes prefix | `@` | `$` (shell prompt association) |
| Pane search keywords | title + generic keywords | cwd, branch, repo, worktree folder, content type |
| Footer in mgmt mode | same as normal | same as normal (bare keys are future work) |

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Features/CommandBar/CommandBarItem.swift` | Modify | Add `CommandBarAppMode` enum, `CommandBarAppContext` struct |
| `Features/CommandBar/CommandBarDataSource.swift` | Modify | Fix repo scope redundancy + grouping, fix tab/pane display names |
| `Features/CommandBar/CommandBarPanel.swift` | Modify | Investigate + fix height collapse bug |
| `Features/CommandBar/Views/CommandBarView.swift` | Modify | Add status strip, derive mode/context from observable sources |
| `Features/CommandBar/Views/CommandBarStatusStrip.swift` | Create | New view: mode (left) + app context (right) |
| `Features/CommandBar/Views/CommandBarSearchField.swift` | Modify | Fix scope icon redundancy with typed prefix |
| `Features/CommandBar/Views/CommandBarResultsList.swift` | Modify | Ensure fill on empty state (height fix) |
| `Features/CommandBar/CommandBarState.swift` | Modify | Add `hasPrefixInText` computed property |
| `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift` | Create | Tests for mode and context types |

---

## Task 1: Add `CommandBarAppMode` and `CommandBarAppContext` types

These types represent the two new dimensions in the command bar status strip. Pure value types with no app state dependencies.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
- Create: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`

- [ ] **Step 1: Write tests for mode and context types**

```swift
import Testing
@testable import AgentStudio

@Suite("CommandBarAppMode")
struct CommandBarAppModeTests {

    @Test func normalModeProperties() {
        let mode = CommandBarAppMode.normal
        #expect(mode.label == "Normal")
        #expect(mode.icon == "rectangle.split.2x2")
        #expect(mode.isAccented == false)
    }

    @Test func managementModeProperties() {
        let mode = CommandBarAppMode.management
        #expect(mode.label == "Manage")
        #expect(mode.icon == "rectangle.split.2x2.fill")
        #expect(mode.isAccented == true)
    }
}

@Suite("CommandBarAppContext")
struct CommandBarAppContextTests {

    @Test func terminalContext() {
        let ctx = CommandBarAppContext(paneContentType: .terminal)
        #expect(ctx.label == "Terminal")
        #expect(ctx.icon == "terminal")
    }

    @Test func webviewContext() {
        let ctx = CommandBarAppContext(paneContentType: .webview)
        #expect(ctx.label == "Webview")
        #expect(ctx.icon == "globe")
    }

    @Test func bridgeContext() {
        let ctx = CommandBarAppContext(paneContentType: .bridge)
        #expect(ctx.label == "Bridge")
        #expect(ctx.icon == "rectangle.split.2x1")
    }

    @Test func codeViewerContext() {
        let ctx = CommandBarAppContext(paneContentType: .codeViewer)
        #expect(ctx.label == "Code Viewer")
        #expect(ctx.icon == "doc.text")
    }

    @Test func noActivePane() {
        let ctx = CommandBarAppContext(paneContentType: nil)
        #expect(ctx.label == "Terminal")
        #expect(ctx.icon == "terminal")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarAppMode" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: FAIL — types don't exist yet.

- [ ] **Step 3: Implement types**

Add to `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`:

```swift
// MARK: - CommandBarAppMode

/// Global app mode that changes the command bar's behavior and available commands.
/// Matches ManagementModeMonitor icons for visual consistency.
enum CommandBarAppMode {
    case normal
    case management

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .management: return "Manage"
        }
    }

    /// SF Symbol name — matches ManagementModeToolbarButton icons.
    var icon: String {
        switch self {
        case .normal: return "rectangle.split.2x2"
        case .management: return "rectangle.split.2x2.fill"
        }
    }

    /// Whether the mode indicator should use accent color.
    var isAccented: Bool {
        switch self {
        case .normal: return false
        case .management: return true
        }
    }
}

// MARK: - CommandBarAppContext

/// Coarse app context derived from the active pane's content type.
/// Shown on the right side of the status strip.
struct CommandBarAppContext {

    /// Simplified content type for the command bar.
    enum ContentType {
        case terminal
        case webview
        case bridge
        case codeViewer
    }

    let paneContentType: ContentType?

    var label: String {
        switch paneContentType {
        case .terminal, nil: return "Terminal"
        case .webview: return "Webview"
        case .bridge: return "Bridge"
        case .codeViewer: return "Code Viewer"
        }
    }

    var icon: String {
        switch paneContentType {
        case .terminal, nil: return "terminal"
        case .webview: return "globe"
        case .bridge: return "rectangle.split.2x1"
        case .codeViewer: return "doc.text"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarAppMode|CommandBarAppContext" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift
git commit -m "feat(command-bar): add CommandBarAppMode and CommandBarAppContext types"
```

---

## Task 2: Create the `CommandBarStatusStrip` view and wire it into `CommandBarView`

The status strip reads mode and context directly from observable sources — `ManagementModeMonitor.shared` and `WorkspaceStore` — via SwiftUI observation. No mutable copies on `CommandBarState`.

**Why no copies on CommandBarState:** `ManagementModeMonitor` and `WorkspaceStore` are both `@Observable`. If the user toggles management mode while the command bar is open, the status strip updates live. Storing a mutable copy on `CommandBarState` would create stale snapshots and duplicated ownership. `CommandBarState` should remain purely command-bar-local UI state (visibility, input, selection, navigation).

**Files:**
- Create: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`

- [ ] **Step 1: Create the status strip view**

```swift
import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing mode (left) and app context (right).
/// Mode uses accent color when in management mode; normal mode is muted.
/// App context is always muted.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: CommandBarAppContext

    var body: some View {
        HStack {
            // Mode indicator (left)
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                Text(mode.label)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
            }
            .foregroundStyle(mode.isAccented ? Color.accentColor : .primary.opacity(0.35))

            Spacer()

            // App context indicator (right)
            HStack(spacing: 4) {
                Image(systemName: context.icon)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                Text(context.label)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
```

- [ ] **Step 2: Add derived mode/context computed properties to CommandBarView**

In `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`, add computed properties that read from the observable sources directly:

```swift
// MARK: - Mode & Context (derived from observable app state)

/// Current mode — reads live from ManagementModeMonitor.
private var currentMode: CommandBarAppMode {
    ManagementModeMonitor.shared.isActive ? .management : .normal
}

/// Current app context — derived from the active pane's content type.
private var currentContext: CommandBarAppContext {
    guard let activeTabId = store.activeTabId,
          let tab = store.tab(activeTabId),
          let activePaneId = tab.activePaneId,
          let pane = store.pane(activePaneId)
    else {
        return CommandBarAppContext(paneContentType: nil)
    }

    let contentType: CommandBarAppContext.ContentType = {
        switch pane.content {
        case .terminal: return .terminal
        case .webview: return .webview
        case .bridgePanel: return .bridge
        case .codeViewer: return .codeViewer
        case .unsupported: return .terminal
        }
    }()
    return CommandBarAppContext(paneContentType: contentType)
}
```

- [ ] **Step 3: Wire the status strip into CommandBarView body**

In the `body` VStack, add the status strip as the first element:

```swift
var body: some View {
    VStack(spacing: 0) {
        // Status strip: mode (left) + app context (right)
        CommandBarStatusStrip(
            mode: currentMode,
            context: currentContext
        )

        // Thin separator
        Divider()
            .opacity(0.15)

        // Scope pill (only when nested)
        if state.isNested {
```

The rest of the body remains unchanged.

- [ ] **Step 4: Build to verify compilation**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
git commit -m "feat(command-bar): add status strip reading live mode and context from observable stores"
```

---

## Task 3: Fix the height collapse bug

The panel height collapses when switching to scopes with fewer items (e.g., `#` repos scope) and doesn't restore when switching back.

**Root cause:** The `NSHostingView` intrinsic content size shrinks when SwiftUI content is small. Since the hosting view is edge-pinned to the panel's content view and the panel uses `.fullSizeContentView`, AppKit auto-sizes the panel to match the hosting view's preferred size. `updateHeight` is called once during `presentPanel` but the hosting view's intrinsic size overrides the panel frame on subsequent layout passes.

**Fix:** Set `contentMinSize` on the panel after computing height. This is the direct AppKit API for "don't shrink below this." Additionally, lower the hosting view's content hugging priority so it doesn't fight the panel frame, and ensure the empty state fills available space.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarPanel.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultsList.swift`

- [ ] **Step 1: Set `contentMinSize` in `updateHeight`**

In `Sources/AgentStudio/Features/CommandBar/CommandBarPanel.swift`, update `updateHeight` to lock the panel size:

```swift
func updateHeight(parentWindow: NSWindow) {
    let contentFrame = parentWindow.contentLayoutRect
    let offsetFraction: CGFloat = 0.2
    let remainingBelow = contentFrame.height * (1 - offsetFraction)
    let panelHeight = min(contentFrame.height * 0.6, remainingBelow)

    var frame = self.frame
    let heightDelta = panelHeight - frame.height
    frame.size.height = panelHeight
    frame.origin.y -= heightDelta  // Grow downward
    setFrame(frame, display: true)

    // Lock the panel size so NSHostingView intrinsic content size
    // can't shrink it when SwiftUI content changes (scope switch).
    contentMinSize = NSSize(width: frame.width, height: panelHeight)
    contentMaxSize = NSSize(width: frame.width, height: panelHeight)
}
```

- [ ] **Step 2: Lower hosting view content hugging priority**

In `Sources/AgentStudio/Features/CommandBar/CommandBarPanel.swift`, update `setContent` to prevent the hosting view from fighting the panel frame:

```swift
func setContent<V: View>(_ view: V) {
    hostingView?.removeFromSuperview()

    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.translatesAutoresizingMaskIntoConstraints = false
    // Prevent SwiftUI from collapsing the view — the panel owns the height.
    hosting.setContentHuggingPriority(.defaultLow, for: .vertical)
    hosting.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    effectView.addSubview(hosting)
    NSLayoutConstraint.activate([
        hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
        hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
        hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
    ])
    hostingView = hosting
}
```

- [ ] **Step 3: Ensure the results list fills available space in all states**

In `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultsList.swift`, update the empty state to fill available height:

```swift
private var emptyState: some View {
    VStack(spacing: 4) {
        Text("No results")
            .font(.system(size: AppStyle.textBase, weight: .medium))
            .foregroundStyle(.primary.opacity(0.5))
        Text("Try a different search term")
            .font(.system(size: AppStyle.textXs))
            .foregroundStyle(.primary.opacity(0.3))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 24)
}
```

Changed `frame(maxWidth: .infinity)` to `frame(maxWidth: .infinity, maxHeight: .infinity)`.

- [ ] **Step 4: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Visual verification**

Launch the app and test:
1. Open command bar with no prefix (everything scope) — note the panel height
2. Type `#` to switch to repos scope — panel height should NOT collapse
3. Delete `#` to return to everything scope — panel height should be the same
4. Type `>` to switch to commands scope — panel height should be the same

```bash
pkill -9 -f "AgentStudio" 2>/dev/null
mise run build && .build/debug/AgentStudio &
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarPanel.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultsList.swift
git commit -m "fix(command-bar): prevent height collapse when switching scopes via contentMinSize"
```

---

## Task 4: Fix repo scope display — remove redundancy and fix one-item grouping

The `#` repos scope has triple redundancy (star icon + "★" in title + name in subtitle) and wastes 50% of vertical space on group headers for repos with a single worktree.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

- [ ] **Step 1: Write test for improved repo scope items**

Look at existing tests in `Tests/AgentStudioTests/` first to understand how `WorkspaceStore` is populated in tests. Then write:

```swift
import Testing
@testable import AgentStudio

@Suite("CommandBarDataSource repo scope")
@MainActor
struct CommandBarDataSourceRepoScopeTests {

    @Test func worktreeItemTitleDoesNotContainStarEmoji() {
        let store = WorkspaceStore()
        // Use the store's API to add a repo with a main worktree.
        // Check existing test helpers for the pattern.

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            dispatcher: CommandDispatcher.shared
        )

        for item in items {
            #expect(!item.title.hasPrefix("★ "),
                "Repo scope item title should not contain star emoji prefix: \(item.title)")
        }
    }

    @Test func worktreeSubtitleIsNotNameRepetition() {
        let store = WorkspaceStore()
        // ... setup

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            dispatcher: CommandDispatcher.shared
        )

        for item in items {
            if let subtitle = item.subtitle {
                #expect(subtitle != item.title,
                    "Subtitle should not repeat the title: \(item.title)")
            }
        }
    }

    @Test func singleWorktreeReposUseFlatsGroup() {
        let store = WorkspaceStore()
        // Add two repos, each with only one worktree (the main one)

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            dispatcher: CommandDispatcher.shared
        )
        let groups = CommandBarDataSource.grouped(items)

        // Single-worktree repos should be in a flat "Repos" group, not per-repo groups
        let reposGroup = groups.first { $0.name == "Repos" }
        #expect(reposGroup != nil, "Single-worktree repos should be in a 'Repos' group")
    }
}
```

Note: Exact test setup depends on `WorkspaceStore` test helpers — the implementing agent must look at existing test patterns.

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceRepo" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: FAIL

- [ ] **Step 3: Fix `repoScopeItems` — remove star prefix, fix subtitle, fix one-item grouping**

In `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`, replace the `repoScopeItems` method:

```swift
private static func repoScopeItems(store: WorkspaceStore) -> [CommandBarItem] {
    var items: [CommandBarItem] = []

    // Separate repos into single-worktree (flat group) and multi-worktree (per-repo groups)
    let singleWorktreeRepos = store.repos.filter { $0.worktrees.count <= 1 }
    let multiWorktreeRepos = store.repos.filter { $0.worktrees.count > 1 }

    // Single-worktree repos go into a flat "Repos" group — no per-repo header.
    // Sorted alphabetically since store order is arbitrary.
    for repo in singleWorktreeRepos.sorted(by: { $0.name < $1.name }) {
        for worktree in repo.worktrees {
            items.append(
                CommandBarItem(
                    id: "repo-wt-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: worktree.isMainWorktree ? "main worktree" : nil,
                    icon: worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch",
                    group: "Repos",
                    groupPriority: 0,
                    keywords: ["repo", "worktree", repo.name, worktree.name],
                    action: .dispatchTargeted(.openWorktree, target: worktree.id, targetType: .worktree),
                    command: .openWorktree
                ))
        }
    }

    // Multi-worktree repos get per-repo group headers
    for (repoIndex, repo) in multiWorktreeRepos.enumerated() {
        let groupName = "\(repo.name) (worktrees)"
        for worktree in repo.worktrees {
            items.append(
                CommandBarItem(
                    id: "repo-wt-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: worktree.isMainWorktree ? "main worktree" : nil,
                    icon: worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch",
                    group: groupName,
                    groupPriority: 1 + repoIndex,
                    keywords: ["repo", "worktree", repo.name, worktree.name],
                    action: .dispatchTargeted(.openWorktree, target: worktree.id, targetType: .worktree),
                    command: .openWorktree
                ))
        }
    }

    return items
}
```

Changes vs current:
- `title`: `worktree.name` — no more `"★ "` prefix
- `subtitle`: `"main worktree"` or `nil` — no more repeating the title
- Grouping: single-worktree repos in flat `"Repos"` group; multi-worktree repos get `"repoName (worktrees)"` headers

- [ ] **Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceRepo" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
git commit -m "fix(command-bar): remove repo scope redundancy, use flat group for single-worktree repos"
```

---

## Task 5: Fix tab display names — show pane count instead of concatenated labels

The tab title currently concatenates ALL pane labels with `" | "` via `PaneDisplayProjector.tabDisplayLabel`, creating unreadable strings. Fix in the data source only — don't modify `PaneDisplayProjector` which the tab bar and other views depend on.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

- [ ] **Step 1: Override tab display title for command bar use**

In `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`, replace the `tabDisplayTitle` helper:

```swift
/// Tab display title optimized for the command bar.
/// Shows the active pane's repo name (or first pane's label) with pane count.
/// Avoids the tab bar's pane-label concatenation which is unreadable in a list.
private static func tabDisplayTitle(
    tab: Tab,
    store: WorkspaceStore,
    repoCache: WorkspaceRepoCache
) -> String {
    let primaryPaneId = tab.activePaneId ?? tab.paneIds.first
    guard let paneId = primaryPaneId else { return "Empty Tab" }

    let parts = PaneDisplayProjector.displayParts(for: paneId, store: store, repoCache: repoCache)
    return parts.repoName ?? parts.primaryLabel
}
```

- [ ] **Step 2: Update tab item subtitle to include pane count**

In the `tabItems` method, update the subtitle computation:

```swift
private static func tabItems(
    store: WorkspaceStore,
    repoCache: WorkspaceRepoCache
) -> [CommandBarItem] {
    store.tabs.enumerated().map { index, tab in
        let title = tabDisplayTitle(tab: tab, store: store, repoCache: repoCache)
        let isActive = tab.id == store.activeTabId
        let paneCount = tab.paneIds.count

        let subtitle: String = {
            var parts: [String] = []
            if isActive { parts.append("Active") }
            parts.append("Tab \(index + 1)")
            if paneCount > 1 { parts.append("\(paneCount) panes") }
            return parts.joined(separator: " · ")
        }()

        let tabId = tab.id
        return CommandBarItem(
            id: "tab-\(tab.id.uuidString)",
            title: title,
            subtitle: subtitle,
            icon: "rectangle.stack",
            group: Group.tabs,
            groupPriority: Priority.tabs,
            keywords: ["tab", "switch"],
            action: .dispatchTargeted(.selectTab, target: tabId, targetType: .tab),
            command: .selectTab
        )
    }
}
```

- [ ] **Step 3: Also update `paneAndTabItems` which generates tab items for the `@` panes scope**

The `paneAndTabItems` method has its own tab item creation that also calls `tabDisplayTitle`. Verify it uses the same updated `tabDisplayTitle` helper (it should, since both call the same private method). No code change needed here — just verify.

- [ ] **Step 4: Build and verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
git commit -m "fix(command-bar): show repo name + pane count for tab titles instead of concatenated labels"
```

---

## Task 6: Fix pane display names — make them more informative

When multiple panes are in the same repo/branch, they all show the same `"repoName | branchName | worktreeFolderName"` label. Add a content-type prefix and use distinguishing detail to make labels more informative.

**Note:** This does not guarantee uniqueness. Two terminals in the same worktree will both show `"Terminal — branchName"`. The subtitle (`Tab 1 · Active` vs `Tab 1`) provides some differentiation. Guaranteed uniqueness (e.g., ordinal suffixes) is a separate effort.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

- [ ] **Step 1: Create a command-bar-specific pane label helper**

Add a new helper in `CommandBarDataSource`. Note: `WebviewState.url` is `URL` (non-optional), not `String?`.

```swift
/// Pane display label optimized for the command bar.
/// Format: "[ContentType] — [distinguishing detail]"
/// More informative than the raw projector label, but not guaranteed unique
/// when multiple terminals share the same worktree/branch.
private static func paneDisplayLabel(
    for pane: Pane,
    store: WorkspaceStore,
    repoCache: WorkspaceRepoCache
) -> String {
    let parts = PaneDisplayProjector.displayParts(for: pane, store: store, repoCache: repoCache)

    switch pane.content {
    case .webview(let webState):
        let host = webState.url.host() ?? webState.url.absoluteString
        return "Webview — \(host)"
    case .bridgePanel:
        return "Bridge — \(parts.repoName ?? "Panel")"
    case .codeViewer:
        return "Code — \(parts.repoName ?? "Viewer")"
    default:
        // Terminal panes: use branch name or worktree folder to distinguish
        if let branch = parts.branchName {
            return "Terminal — \(branch)"
        }
        if let folder = parts.cwdFolderName {
            return "Terminal — \(folder)"
        }
        return parts.primaryLabel
    }
}
```

- [ ] **Step 2: Use the new label in `paneItems`**

In the `paneItems` method, replace the `PaneDisplayProjector.displayLabel(...)` call:

```swift
title: paneDisplayLabel(for: pane, store: store, repoCache: repoCache),
```

- [ ] **Step 3: Use the new label in `paneAndTabItems`**

In the `paneAndTabItems` method, replace the `PaneDisplayProjector.displayLabel(...)` call for pane items:

```swift
title: paneDisplayLabel(for: pane, store: store, repoCache: repoCache),
```

- [ ] **Step 4: Use the new label in drill-in target levels**

Update all places that show pane labels in drill-in targets. In `buildTargetLevel`, `buildMovePaneSourceLevel`, and `buildDrawerPaneTargetLevel`, replace `PaneDisplayProjector.displayLabel(...)` calls with:

```swift
title: paneDisplayLabel(for: pane, store: store, repoCache: repoCache),
```

There are 5 call sites total — search for `PaneDisplayProjector.displayLabel` in `CommandBarDataSource.swift` and update each one.

- [ ] **Step 5: Build and verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
git commit -m "fix(command-bar): distinguish identical panes with content-type prefix and detail"
```

---

## Task 7: Fix scope icon redundancy

The scope icon (`#`, `≫`, `@`) duplicates the prefix character the user typed. When you type `#`, the search field shows `# #` — the scope icon and the character in the text field.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`

- [ ] **Step 1: Add `hasPrefixInText` to CommandBarState**

In `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`, add a computed property:

```swift
/// Whether the rawInput starts with a recognized prefix character.
/// When true, the search field hides the scope icon to avoid redundancy (e.g., "# #").
var hasPrefixInText: Bool {
    activePrefix != nil && !rawInput.isEmpty
}
```

- [ ] **Step 2: Hide scope icon when prefix char is visible in text**

In `Sources/AgentStudio/Features/CommandBar/CommandBarSearchField.swift`, replace the body:

```swift
var body: some View {
    HStack(spacing: 10) {
        // Scope icon — hidden when prefix char is visible in text to avoid "# #" redundancy
        if !state.hasPrefixInText {
            Image(systemName: state.scopeIcon)
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 16, height: 16)
        }

        // Text input with keyboard interception
        CommandBarTextField(
            text: $state.rawInput,
            placeholder: state.placeholder,
            onArrowUp: onArrowUp,
            onArrowDown: onArrowDown,
            onEnter: onEnter,
            onBackspaceOnEmpty: onBackspaceOnEmpty
        )
    }
    .padding(.horizontal, 12)
    .frame(height: 44)
}
```

- [ ] **Step 3: Build and verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift Sources/AgentStudio/Features/CommandBar/CommandBarState.swift
git commit -m "fix(command-bar): hide scope icon when prefix character is visible in text"
```

---

## Task 8: Rename panes prefix `@` → `$` and enrich pane search keywords

The `@` prefix for panes doesn't have a strong association. `$` (shell prompt) is a better fit for a terminal app. Also enrich pane keywords so `$` scope searches cwd, branch, repo — not just the display title.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

- [ ] **Step 1: Update `CommandBarScope` and prefix parsing**

In `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`, the `CommandBarScope` enum stays the same (`.panes` is the semantic name). No change needed here.

In `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`, update `activePrefix` to recognize `$` instead of `@`:

```swift
var activePrefix: String? {
    guard navigationStack.isEmpty else { return nil }
    guard let first = rawInput.first else { return nil }
    let char = String(first)
    return [">", "$", "#"].contains(char) ? char : nil
}
```

Update `activeScope` to map `$` to `.panes`:

```swift
var activeScope: CommandBarScope {
    switch activePrefix {
    case ">": return .commands
    case "$": return .panes
    case "#": return .repos
    default: return .everything
    }
}
```

Update `scopeIcon` to use `$` icon:

```swift
var scopeIcon: String {
    if isNested { return "magnifyingglass" }
    switch activeScope {
    case .everything: return "magnifyingglass"
    case .commands: return "chevron.right.2"
    case .panes: return "dollarsign"
    case .repos: return "number"
    }
}
```

Update `placeholder` for panes scope:

```swift
case .panes: return "Search panes..."
```

Update `show(prefix:)` to accept `$`:

```swift
func show(prefix: String? = nil) {
    if let prefix, !prefix.isEmpty, [">", "$", "#"].contains(prefix) {
        rawInput = prefix + " "
    } else {
        rawInput = prefix ?? ""
    }
    navigationStack = []
    selectedIndex = 0
    isVisible = true
    stateLogger.debug("Command bar shown with prefix: \(prefix ?? "(none)")")
}
```

- [ ] **Step 2: Enrich pane keywords for better `$` scope search**

In `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`, update `keywordsForPane` to include cwd, branch, and repo:

```swift
private static func keywordsForPane(
    _ pane: Pane,
    store: WorkspaceStore,
    repoCache: WorkspaceRepoCache
) -> [String] {
    let parts = PaneDisplayProjector.displayParts(for: pane, store: store, repoCache: repoCache)
    var keywords = ["pane"]

    // Core identifiers for search
    if let repoName = parts.repoName { keywords.append(repoName) }
    if let branchName = parts.branchName { keywords.append(branchName) }
    if let worktreeFolder = parts.worktreeFolderName { keywords.append(worktreeFolder) }
    if let cwdFolder = parts.cwdFolderName { keywords.append(cwdFolder) }

    // Content-type keywords
    if case .webview = pane.content {
        keywords.append(contentsOf: ["web", "browser", "url"])
    } else if case .bridgePanel = pane.content {
        keywords.append(contentsOf: ["diff", "review", "bridge"])
    } else {
        keywords.append("terminal")
    }

    // Worktree name if available
    if let worktreeId = pane.worktreeId, let wt = store.worktree(worktreeId) {
        keywords.append(wt.name)
    }

    return keywords
}
```

Changes vs current: uses `PaneDisplayProjector.displayParts` instead of `paneKeywords` to get structured access to repo, branch, worktree folder, and cwd folder individually. Each is added as a separate keyword for better fuzzy matching.

- [ ] **Step 3: Build and verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Sources/AgentStudio/Features/CommandBar/CommandBarState.swift Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
git commit -m "feat(command-bar): rename panes prefix @ to $, enrich pane search keywords"
```

---

## Task 9: Run full test suite, lint, and visual verification

- [ ] **Step 1: Run all tests**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS — all tests should pass.

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS — zero lint errors.

- [ ] **Step 3: Visual verification with Peekaboo**

```bash
pkill -9 -f "AgentStudio" 2>/dev/null
mise run build && .build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Verify:
1. Status strip shows `▦ Normal` on the left, `⌨ Terminal` on the right
2. Toggle management mode (⌘E), reopen command bar — status strip shows `▦▪ Manage` in accent color
3. Toggle management mode off and back — status strip updates live (no stale state)
4. Type `#` — no duplicate `# #`, worktree names clean, single-worktree repos in flat group
5. Type `>` — commands scope, panel height stable
6. Type `$` — panes scope, shows panes grouped by tab
7. Type `@` — should NOT trigger panes scope (old prefix removed)
8. Switch between scopes — panel height remains stable
9. Tab titles show repo name + pane count, not concatenated labels
10. Pane titles show `Terminal — branchName` format
11. In `$` scope, search by cwd folder name or branch name — should find panes

- [ ] **Step 4: Final commit if any formatting fixes needed**

```bash
git add -A
git commit -m "chore: formatting fixes from lint"
```
