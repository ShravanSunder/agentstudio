# Agent Studio

![Agent Studio workspace](web/images/screen3.png)

A macOS workspace for agent-assisted development. Run multiple coding agents across projects simultaneously — and stay oriented while they work.

Agent-agnostic. Keyboard-first. Native macOS. Built on [Ghostty](https://github.com/ghostty-org/ghostty).

## Install

```bash
brew tap ShravanSunder/agentstudio
brew install --cask agent-studio
```

Requires macOS 26+. No external dependencies.

## Why

Development is changing. Coding agents run alongside you now — sometimes several at once, across multiple projects and worktrees. But the tools weren't built for this.

Your terminals multiply. Context scatters across terminal tabs, browser windows, and editor panels. You alt-tab to GitHub to check a diff, lose your place, and spend more time managing your workspace than doing the work. Agents spawn sub-processes — builds, tests, tool calls — that float away from the parent with no association. You end up with dozens of panes and no way to tell which belongs to which project, which worktree, or which agent.

Agent Studio is a ground-up redesign of the development experience around agents. Not a terminal with extra features — a workspace where agents, terminals, diffs, PRs, and project context live together.

## How It Works

### One pane per unit of work. Everything else in its drawer.

Each worktree, agent, or task gets a main terminal pane. Below it, a **drawer** holds everything associated with that work — sub-terminals, git operations, build output, webviews, whatever context belongs together.

```
┌─────────────────────────────────────┐
│  Claude Code — feature-auth         │  ← main pane (your agent)
│  > Implementing OAuth flow...       │
│                                     │
├─────────────────────────────────────┤
│ [shell] [git log] [build] [+]       │  ← drawer (associated context)
│ ┌─────────────────────────────────┐ │
│ │ $ git diff --stat               │ │
│ │  src/auth.swift | 42 +++---     │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

Agent spawns a build? It lands in the drawer. Need to check git status? It's already there. Open a webview to review the PR? Drawer. Close the main pane — the drawer goes with it. Move it to another tab — the drawer follows.

This is what keeps you oriented. Not a flat list of 30 terminals — a structured workspace where every pane has a home.

![Pane drawers and project context](web/images/screen1.png)

### GitHub, PRs, and diffs without leaving the workspace

Webview panes sit alongside your terminals. Review a pull request, check CI status, or browse documentation right next to the agent doing the work. No alt-tab. No lost context.

![GitHub and terminals in one workspace](web/images/screen4.png)

### The rest

**Pane arrangements** — save named layouts per tab ("coding", "reviewing", "monitoring") and switch between them. Sessions keep running in the background.

**Session restore** — close the app, reopen, pick up where you left off. zmx handles persistence with no tmux, no scripts, no configuration.

**Any agent, any pane** — Claude Code, Codex, aider, Cursor CLI. Agent Studio provides the workspace. The agent is just a process.

**Command bar (Cmd+P)** — one interaction point for everything.

![Multi-pane agent workflow](web/images/screen2.png)

## Roadmap

### Window System

- [x] Multi-pane split layouts with drag-to-rearrange
- [x] Pane arrangements — saved layout configurations per tab
- [x] Pane drawers — contextual sub-panes with cascade lifecycle
- [x] Webview panes — embedded browser alongside terminals
- [x] Session restore via zmx
- [x] Project and worktree sidebar
- [ ] Dynamic views — computed grouping by repo, worktree, agent type, or CWD
- [ ] Pane movement between tabs
- [ ] Ghostty integration layer improvements (type-safe bridge, @Observable surface state)

### Bridge and Diff Viewer

A Swift-to-React bridge that embeds rich UI panels inside webview panes. The first use case is an inline diff viewer and code review system.

- [ ] Transport foundation — bidirectional Swift-to-JavaScript messaging
- [ ] State push pipeline — Swift @Observable changes synced to React stores
- [ ] JSON-RPC command channel — React commands back to Swift
- [ ] Diff viewer — inline diffs with file tree navigation
- [ ] Review system — comment threads, review actions, agent event integration
- [ ] Security hardening — content world isolation, navigation policy

### Future

- Auth isolation per project context
- Session teleportation between machines
- Tag-based dynamic grouping
- Notification routing per workspace group

## Architecture

AppKit-main with SwiftUI views. Single `WorkspaceStore` owns all state. Immutable layout trees. Sessions exist independently of views or surfaces.

Built with Swift 6.2, Swift Package Manager, Ghostty (via C API), and Zig build system. Targets macOS 26.

See the [Architecture Overview](docs/architecture/README.md) for the full system design.

## Development

### Prerequisites

- macOS 26+, Xcode 26+, Swift 6
- [mise](https://mise.jdx.dev/) (`brew install mise`)

### Build and Run

```bash
mise install                  # Install pinned tool versions
mise run build                # Full debug build (ghostty + zmx + swift)
.build/debug/AgentStudio      # Launch
```

### Test, Format, and Lint

```bash
mise run test                 # Run tests
mise run format               # Auto-format Swift sources
mise run lint                 # swift-format + swiftlint
```

### Project Structure

```
agent-studio/
├── Sources/AgentStudio/      # Swift source
│   ├── App/                  # Window/tab controllers
│   ├── Ghostty/              # Ghostty C API wrapper
│   ├── Models/               # TerminalSession, Layout, Tab, Pane
│   └── Services/             # WorkspaceStore, SessionRuntime, WorktrunkService
├── Frameworks/               # Generated: GhosttyKit.xcframework (not in git)
├── vendor/ghostty/           # Git submodule: Ghostty source
├── vendor/zmx/               # Session multiplexer
├── docs/                     # Architecture and design docs
└── Package.swift             # SPM manifest
```

### Clone with Submodules

```bash
git clone --recurse-submodules https://github.com/ShravanSunder/agentstudio.git
cd agent-studio
```

## Contributing

Contributions welcome. Fork, branch, test, PR. By submitting a pull request you agree to the [Contributor License Agreement](CLA.md).

## License

[AGPL-3.0](LICENSE)

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) — terminal emulator
- [zmx](vendor/zmx/) — session multiplexer for persistence
