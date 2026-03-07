# T3 Code Architecture Reference

> Research notes on [pingdotgg/t3code](https://github.com/pingdotgg/t3code) — a minimal web GUI for AI coding agents by Theo Browne / Ping.gg. Current as of March 2026 (v0.0.4).

## What It Is

T3 Code is a purpose-built web application that wraps AI coding agent CLIs (currently OpenAI Codex, with Claude Code planned) with a rich UI for conversation, diffs, terminals, and project management. It is **not** a VS Code fork — it is a standalone React app that can run in-browser (`npx t3`) or as an Electron desktop app.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Desktop shell | Electron 40 |
| Web frontend | React 19 + Vite 8 |
| Routing | TanStack Router |
| State management | Zustand v5 |
| Data fetching | TanStack React Query v5 |
| Styling | Tailwind CSS 4 + CVA |
| Terminal emulation | xterm.js v6 |
| Rich text / composer | Lexical v0.41 |
| Server runtime | Node.js on Bun |
| WebSocket | `ws` library |
| PTY / process spawning | `node-pty` |
| Database | SQLite via `@effect/sql-sqlite-bun` |
| Diff rendering | `@pierre/diffs` |
| Type system / schemas | Effect-TS (`effect` + `@effect/platform-node`) |
| Monorepo orchestration | Turborepo v2.3 |
| Linting / formatting | OxLint + OxFmt (Rust-based) |
| Testing | Vitest v4 + Playwright |
| Desktop build | `tsdown` + `electron-updater` |

## Monorepo Structure

```
t3code/
├── apps/
│   ├── server/           # Node.js/Bun WebSocket broker + Codex subprocess manager
│   │   └── src/
│   │       ├── orchestration/   # Event-sourced session management
│   │       │   ├── Services/    # OrchestrationEngine, Reactors, ProjectionPipeline
│   │       │   ├── decider.ts   # Command decision logic
│   │       │   ├── projector.ts # State projection from events
│   │       │   └── Schemas.ts   # Event/command schemas
│   │       ├── provider/        # AI provider abstraction (Codex, future Claude)
│   │       │   ├── Layers/      # Effect-TS dependency injection layers
│   │       │   ├── Services/    # Provider service implementations
│   │       │   └── Errors/      # Typed error definitions
│   │       ├── checkpointing/   # State checkpoint/recovery
│   │       ├── persistence/     # SQLite data layer
│   │       ├── git/             # Git operations
│   │       ├── terminal/        # PTY terminal management
│   │       ├── telemetry/       # Logging and metrics
│   │       ├── wsServer.ts      # WebSocket API routing
│   │       ├── codexAppServerManager.ts  # Codex process lifecycle (JSON-RPC/stdio)
│   │       └── processRunner.ts # Process execution
│   ├── web/              # React/Vite frontend (the actual UI)
│   │   └── src/
│   │       ├── components/      # ChatView, DiffPanel, Sidebar, Composer, etc.
│   │       ├── hooks/           # useTheme, useMediaQuery, useTurnDiffSummaries
│   │       ├── routes/          # TanStack Router route definitions
│   │       ├── lib/             # Utilities
│   │       ├── store.ts         # Zustand store
│   │       ├── wsTransport.ts   # WebSocket transport to server
│   │       └── nativeApi.ts     # Bridge to Electron native APIs
│   ├── desktop/          # Electron shell (main + preload + auto-updater)
│   │   └── src/
│   │       ├── main.ts          # Electron main process
│   │       ├── preload.ts       # Preload script (context bridge)
│   │       └── updateMachine.ts # Auto-update state machine
│   └── marketing/        # Landing page (Astro)
├── packages/
│   ├── contracts/        # Schema-only TypeScript definitions (Effect/Schema)
│   │   └── src/          # orchestration.ts, provider.ts, terminal.ts, ws.ts, etc.
│   └── shared/           # Cross-package runtime utilities
│                         #   → explicit subpath exports ("@t3tools/shared/git")
├── turbo.json            # Turborepo pipeline config
└── bun.lock              # Bun lockfile
```

## Architecture

### Core Data Flow

```
┌─────────────┐     ┌──────────────┐     ┌───────────────────────────┐
│  Electron    │────▶│  React/Vite  │◀───▶│  Node.js/Bun Server       │
│  (desktop    │     │  Web App     │ WS  │  (WebSocket broker)        │
│   shell)     │     │              │     │                            │
└─────────────┘     └──────────────┘     │  ┌────────────────────┐   │
                                          │  │ Codex App Server   │   │
                                          │  │ (JSON-RPC / stdio) │   │
                                          │  └────────────────────┘   │
                                          │  ┌────────────────────┐   │
                                          │  │ node-pty            │   │
                                          │  │ (terminal I/O)      │   │
                                          │  └────────────────────┘   │
                                          │  ┌────────────────────┐   │
                                          │  │ SQLite              │   │
                                          │  │ (persistence)       │   │
                                          │  └────────────────────┘   │
                                          └───────────────────────────┘
```

1. **Server spawns Codex** as a child process, communicating via JSON-RPC over stdio (`codexAppServerManager.ts`).
2. **Provider events** from Codex stream through the orchestration layer, get projected into domain events, and are pushed to the browser via WebSocket on the `orchestration.domainEvent` channel.
3. **The web app** renders conversations, diffs, and terminal output, sending user actions back through WebSocket (`wsTransport.ts`).
4. **Electron** is a thin shell — it hosts the web app, handles auto-updates, and provides native OS integration. The same React app also runs standalone in a browser via `npx t3`.

### Server-Side: Event Sourcing / CQRS

The orchestration layer uses a **decider/projector/reactor** pattern:

- **Decider** (`decider.ts`) — processes commands and decides what events to emit.
- **Projector** (`projector.ts`) — projects events into queryable state snapshots via `ProjectionPipeline`.
- **Reactors** (`OrchestrationReactor`, `CheckpointReactor`, `ProviderCommandReactor`) — react to domain events asynchronously, triggering side effects.

This gives the server replay and checkpoint capabilities — useful for recovering sessions after crashes.

### Server-Side: Effect-TS as Core Abstraction

The server uses the full **Layers/Services dependency injection pattern** from Effect-TS. This is not incidental — it is the core architectural decision:

- **Layers** provide composable dependency injection (e.g., `provider/Layers/`)
- **Services** define typed interfaces with algebraic error handling
- **Typed errors** (`provider/Errors/`) make failure modes explicit in the type system
- Platform I/O, SQLite, and HTTP are all handled through Effect abstractions

### Frontend Patterns

- **Zustand** for global state — lightweight, no boilerplate, selector-based reactivity.
- **TanStack Router** for file-based routing with type-safe route params.
- **TanStack React Query** for server state synchronization (caching, refetching).
- **Lexical** for the chat composer/prompt input (rich text editor).
- **xterm.js** for embedded terminal views.
- **Component logic separation**: `.tsx` files paired with `.logic.ts` and `.test.ts` files, keeping rendering separate from business logic.

### Provider Abstraction

The `provider/` layer abstracts the AI backend. Codex is the current provider; Claude Code would be another. Provider-specific events are projected into generic orchestration domain events server-side, then pushed to clients. This makes adding new AI backends a matter of implementing a new provider layer without changing the orchestration or UI layers.

### Schema-Only Contracts

The `packages/contracts` package contains only TypeScript schemas and types (using Effect/Schema) with **no runtime logic**. This ensures the protocol between server and client is a single source of truth. Covers: provider events, WebSocket messages, model types, orchestration events, terminal schemas, IPC, git operations, keybindings.

### Dual Deployment

The same React app runs both in-browser and inside Electron. A `nativeApi.ts` / `wsNativeApi.ts` abstraction layer bridges to Electron's IPC when running as a desktop app, and falls back to WebSocket-only when running in a browser.

## Comparison with Agent Studio

| Concern | T3 Code | Agent Studio |
|---------|---------|-------------|
| Desktop framework | Electron (web tech, cross-platform) | Native AppKit (macOS only) |
| Terminal | xterm.js (JS emulator) | Ghostty (native C API, GPU-accelerated) |
| State management | Zustand (JS stores) | `@Observable` stores + coordinators |
| Cross-component events | WebSocket + domain events | AsyncStream + PaneCoordinator |
| Type contracts | Effect/Schema in shared package | Swift protocols + typed bridges |
| Process management | node-pty + JSON-RPC stdio | zmx backend + SessionRuntime |
| UI rendering | React (virtual DOM) | AppKit NSViews + SwiftUI islands |
| Error handling | Effect-TS algebraic errors | Swift typed throws |
| Persistence | SQLite via Effect | WorkspacePersistor (disk) |
| AI provider model | Provider abstraction layer | Session backends |

T3 Code is a **web-first, cross-platform** approach (Electron + React) that trades native performance for portability. Agent Studio is a **native macOS** approach (AppKit + Ghostty) that trades portability for native integration depth and terminal performance.

### Architectural Similarities

Despite different tech stacks, both projects share structural patterns:

- **Provider/session abstraction** — both abstract the AI backend behind a provider/session layer.
- **Event-driven communication** — T3 Code uses WebSocket domain events; Agent Studio uses AsyncStream.
- **Shared contracts/protocols** — T3 Code has `packages/contracts`; Agent Studio has typed bridge protocols.
- **Coordinator/orchestration layer** — T3 Code has orchestration reactors; Agent Studio has PaneCoordinator.
- **Schema-first design** — both enforce type safety at system boundaries.
