# AgentStudio Improvements for Power Users

## Current State Analysis

AgentStudio v1.0 provides a solid foundation for managing AI agent worktrees with integrated terminals. The Ghostty-based terminal renders beautifully with Metal acceleration, and the Zellij integration works correctly.

### What's Working Well
- Clean dark theme with good contrast
- Project/worktree hierarchy with disclosure groups
- Status indicators on worktrees (idle, running, pending review, error)
- Agent type badges (Claude Code, Codex, Gemini, Aider)
- Tab-based terminal management
- Zellij session naming convention (`project-worktree`)

---

## Keyboard Shortcuts (Current)

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New Tab |
| `Cmd+W` | Close Tab |
| `Cmd+Shift+O` | Add Project |
| `Cmd+,` | Settings |
| `Cmd+Ctrl+S` | Toggle Sidebar |
| `Cmd+Ctrl+F` | Full Screen |
| `Cmd+1-9` | Select Tab 1-9 |

### Conflict Analysis
These shortcuts are **safe** and do not conflict with:
- **Zellij**: Uses `Ctrl+G` as prefix by default
- **Zsh**: Uses `Ctrl+C`, `Ctrl+D`, `Ctrl+Z` for signals
- **Vim/Neovim**: Uses `Ctrl+` and modal keys
- **Claude Code**: Uses its own keybindings within terminal

---

## Suggested Improvements

### 1. Navigation & Window Management

**Add shortcuts:**
| Shortcut | Action | Rationale |
|----------|--------|-----------|
| `Cmd+Shift+]` | Next Tab | iTerm2/Terminal.app convention |
| `Cmd+Shift+[` | Previous Tab | iTerm2/Terminal.app convention |
| `Cmd+Option+Left/Right` | Move Tab | Reorder tabs |
| `Cmd+Shift+D` | Split Terminal Pane | For side-by-side comparisons |
| `Cmd+K` | Clear Terminal | Safe - not used by Zellij |
| `Cmd+Shift+N` | New Window | Multiple windows |
| `Cmd+\`` | Cycle Windows | Quick window switching |

### 2. Sidebar Enhancements

**Current:** Shows worktree name + badge count
**Suggested additions:**
- Show branch name inline (currently in model but not displayed)
- Add "last opened" timestamp for recently used worktrees
- Add quick-filter/search (`Cmd+P` style) for projects
- Right-click context menu with:
  - Open in VS Code/Cursor
  - Open in Finder
  - Copy path
  - Delete worktree (with confirmation)
- Drag-and-drop to reorder worktrees

### 3. Terminal Features

**Quick Actions:**
- `Cmd+Shift+C` - Copy selected text (without Ctrl key to avoid terminal conflicts)
- `Cmd+Shift+V` - Paste (match iTerm2)
- `Cmd+F` - Find in terminal output (scrollback search)
- `Cmd+G` - Find next
- `Cmd+Shift+G` - Find previous

**Font & Display:**
- `Cmd+=` - Increase font size
- `Cmd+-` - Decrease font size
- `Cmd+0` - Reset font size

**Session Management:**
- Auto-attach to existing Zellij session if found
- Option to detach vs kill session on tab close
- "Session browser" view showing all Zellij sessions

### 4. Status & Monitoring

**Add to toolbar or status bar:**
- Git status indicator (dirty/clean/ahead/behind)
- Active agent indicator (which AI is running)
- Resource usage (optional: CPU/memory of child processes)

**Notifications:**
- Desktop notification when agent completes task
- Sound alert option for status changes
- Badge count in dock icon for pending reviews

### 5. Worktree Lifecycle

**Add commands:**
- `Cmd+Shift+W` - Create new worktree from current project
- Quick-switch dialog (`Cmd+Shift+P`) to jump between worktrees
- "Recent Worktrees" submenu in File menu
- Auto-cleanup of stale worktrees (with confirmation)

### 6. Agent Integration

**Enhancements:**
- Quick-launch agent commands:
  - `Cmd+Shift+1` - Launch Claude Code
  - `Cmd+Shift+2` - Launch Aider
  - etc.
- Agent configuration per-project (`.agentstudio/config.json`)
- Agent status streaming to sidebar
- "Stop Agent" button/shortcut (`Cmd+.`)

### 7. Settings & Customization

**Add settings for:**
- Default shell (bash/zsh/fish)
- Terminal font family and size
- Color scheme selection
- Zellij config path
- Default agent per project type
- Auto-start behavior (restore last session)

### 8. Command Palette

**Add `Cmd+Shift+P` command palette** with:
- All menu actions searchable
- Recent commands
- Fuzzy matching
- Keyboard-driven navigation

---

## Keyboard Shortcut Design Principles

To avoid conflicts with terminal applications:

1. **Use `Cmd` modifier** - Terminal apps use `Ctrl`
2. **Avoid `Cmd+C/V/X/Z`** in terminal context - pass to terminal
3. **Use `Cmd+Shift+` prefix** for actions that modify state
4. **Never override `Ctrl+` combinations** - reserved for terminal
5. **Provide passthrough mode** - `Cmd+Shift+T` to toggle keyboard passthrough to terminal

### Reserved Combinations (Never Override)
These are used by Zellij, tmux, zsh, or common CLI tools:
- `Ctrl+A-Z` (signal characters, readline, etc.)
- `Ctrl+[` (ESC equivalent)
- `Ctrl+G` (Zellij prefix)
- `Ctrl+B` (tmux prefix)
- `Ctrl+Space` (set mark)

---

## Priority Order

### P0 (Critical for Power Users)
1. Tab navigation shortcuts (`Cmd+Shift+[/]`)
2. Command palette (`Cmd+Shift+P`)
3. Quick-switch worktrees dialog
4. Copy/paste that works correctly in terminal

### P1 (High Value)
5. Find in terminal
6. Font size controls
7. Git status in sidebar
8. Desktop notifications for agent completion

### P2 (Nice to Have)
9. Split panes
10. Agent quick-launch shortcuts
11. Session browser
12. Drag-and-drop tab reordering

---

## Technical Notes

### Ghostty Integration
The current Ghostty integration uses the C API directly. Future improvements could leverage:
- `ghostty_surface_scroll_history()` for scrollback search
- `ghostty_surface_selection_*()` for better copy/paste
- Font config via `ghostty_config_set()`

### Accessibility
Ensure all new features have:
- VoiceOver labels
- Keyboard-only navigation path
- High contrast mode support
