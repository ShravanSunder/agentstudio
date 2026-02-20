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

Your terminals multiply. Context scatters across terminal tabs, browser windows, and editor panels. You alt-tab to GitHub to check a diff, lose your place, and spend more time managing your workspace than doing the work.

Agents spawn sub-processes — builds, tests, tool calls — that float away from the parent with no association. You end up with dozens of panes and no way to tell which belongs to which project, which worktree, or which agent.

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

### Built for the keyboard

**Pane arrangements** — save named layouts per tab ("coding", "reviewing", "monitoring") and switch between them. Sessions keep running in the background.

**Session restore** — close the app, reopen, pick up where you left off. Optional zmx-backed persistence is on by default — no tmux, no scripts, no configuration.

**Any agent, any pane** — Claude Code, Codex, aider, Cursor CLI. Agent Studio provides the workspace. The agent is just a process.

**Command bar (Cmd+P)** — one interaction point for everything.

![Multi-pane agent workflow](web/images/screen2.png)

## Roadmap

### Solved

**Pane explosion** — agents and worktrees generate dozens of terminals. Pane drawers keep sub-processes associated with their parent. Split layouts and arrangements let you organize what's visible without killing what's running.

**Lost sessions** — close the app, lose your work. Optional zmx-backed session restore (on by default) brings every session back on relaunch. No tmux, no scripts.

**No project context** — terminals are anonymous. Agent Studio ties every pane to its repo, worktree, and working directory automatically.

### Solving next

**"Which pane was that?"** — you're running agents across five repos. You need to see all panes for one project, or all panes running Claude Code, or all panes in a specific worktree. Today you hunt through tabs.

Dynamic views regroup your entire workspace on demand — by repo, by worktree, by agent type, by CWD — without touching your layout. Switch to "By Agent" and every Claude pane appears in one tab, every aider pane in another. Switch back and your workspace is untouched.

**"I have to leave to review diffs"** — agents generate diffs constantly and you alt-tab to GitHub or VS Code to review them.

Agent Studio will embed a full diff viewer and code review experience directly in pane drawers — inline diffs with syntax highlighting, file tree navigation, comment threads, and review actions. When an agent finishes a task, its changes appear in the drawer right below it. Review, approve, move on. A VS Code-quality experience without leaving the workspace where your agents are running.

**"I just gave an agent root access to my machine"** — agents execute shell commands, install packages, and make network requests with your full permissions. One bad tool call and credentials leak, repos corrupt, or packages install that you didn't authorize. No guardrails.

Built-in sandboxing with network isolation (egress firewalls, domain allowlisting), credential injection (secrets stay on host, never enter the agent environment), and filesystem controls (read-only git, scoped workspace access). Full agent capability, bounded access.

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

### Clone

```bash
git clone --recurse-submodules https://github.com/ShravanSunder/agentstudio.git
cd agent-studio
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
├── vendor/zmx/               # Session persistence
├── docs/                     # Architecture and design docs
└── Package.swift             # SPM manifest
```

## Contributing

Contributions welcome. Fork, branch, test, PR. By submitting a pull request you agree to the [Contributor License Agreement](CLA.md).

## License

[AGPL-3.0](LICENSE)

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) — terminal emulator
- [zmx](vendor/zmx/) — session persistence for terminal processes
