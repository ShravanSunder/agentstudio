# Agent Pane IPC — drive panes from external processes (tmux-style)

> **Status: DRAFT (2026-05-30).** Branch: `claude/tmux-socket-integration-Tlule`. Sibling to `docs/architecture/remote_zmx_architecture_ideas.md` — that doc owns transport/security; this doc owns the verb surface and where it lands in the stack. No code yet — review before implementing.

## Goal

Give external processes (AI agents, scripts, the user's other tools) a stable IPC surface to:

- read what's on a pane's screen (`capture-pane`)
- type into a pane (`send-keys`)
- subscribe to live output as it streams (`pipe-pane`)
- enumerate panes with their metadata (`list-panes`)
- create/close panes from outside (`new-pane`, `kill-pane`)

In tmux, all of this works because tmux is a server with a Unix-socket IPC. Agent Studio's equivalent split is: **Ghostty owns the screen state**, **zmx owns the PTY and survives the GUI**, **AgentStudio.app composes them**. The plan decides which of those processes hosts the agent-facing socket and which verbs each is on the hook for.

## Prerequisites

- [ ] zmx submodule pinned to a commit that exposes the current IPC tag set (Input/Output/Resize/Detach/DetachAll/Kill/Info/Init/History/Run/Ack). Confirmed via DeepWiki research 2026-05-30 — already true on `main`.
- [ ] `SessionRuntimeAtom` exposes a stable `Pane.id ↔ zmx session name` mapping (today the mapping lives inside `ZmxBackend.swift` — confirm it's readable from outside Terminal feature before externalizing).
- [ ] `PaneRuntimeEventBus` is wired for output facts on terminal panes. Pipe-pane subscriptions ride on top of this — if output isn't already a bus event, that lands first.

---

## What zmx already gives us (no changes needed)

Researched via DeepWiki against `neurosnap/zmx` main on 2026-05-30. The daemon already speaks 11 IPC tags. Five of them are direct equivalents of tmux's agent verbs:

| tmux verb | zmx IPC tag | Notes |
|-----------|-------------|-------|
| `send-keys` | `Input` (0) | Byte slice → PTY stdin. Indistinguishable from human typing. |
| `capture-pane -p -S -` | `History` (8) | Payload byte selects `plain | vt | html` format. Backed by `libghostty-vt` state. Returns full scrollback. |
| `list-sessions` / `list-panes` | `Info` (6) + `zmx list` | Returns `clients_len, pid, cmd, cwd, created_at, task_ended_at, task_exit_code`. |
| `new-session -d ... <cmd>` | `Run` (9) | Send a command without taking an interactive client slot. |
| `kill-session` | `Kill` (5) | Terminates the session. |
| `attach -t` (multi-client) | `Init` + broadcast | Multiple clients on one session; daemon fans output to all. |

Plus: Unix socket at `/tmp/zmx-{uid}/...` with mode 0700. Same trust model as tmux. No token layer.

**Implication:** for a *zmx-only* pane (one zmx session = one Agent Studio pane), an agent can already do 70% of the tmux workflow today, by talking to zmx directly. The missing pieces are pipe-pane, agent-friendly identity, and structured pane metadata.

## What's missing

### G1. Live output streaming (`pipe-pane`)

zmx broadcasts PTY output only to *attached clients*. There is no IPC tag for "subscribe to output as a passive observer without taking a client slot." An agent that wants to watch a build run today has to either repeatedly poll `History` (lossy, expensive on large scrollback) or attach as a real client (which then receives input/resize semantics it doesn't want).

This is the single biggest gap. tmux's `pipe-pane -o 'cat >> log'` is what lets agents tail output cheaply.

### G2. Pane vs session identity

zmx is session-only by design. Agent Studio adds tabs, splits, and drawers. An agent driving Agent Studio needs to reference *panes*, not zmx session names. We need a documented mapping and a stable external pane handle.

### G3. Pane-shaped enumeration

`Info` returns *one zmx session's* metadata. Agents want `list_panes` that returns *all panes in the workspace* with their tab, split position, and feature kind (terminal vs bridge vs webview). zmx doesn't know about any of that — it can't.

### G4. Capture filtering

`History` returns everything in scrollback. Agents typically want "last N lines" or "since I last asked." Polling the full history on every tick is wasteful on long-running sessions.

### G5. Non-terminal panes

Bridge and Webview panes have no zmx session. Agents that want a unified `capture_pane` across pane types need something above zmx.

### G6. Authorization granularity

Today's `0700` model: any process running as your UID can do anything to any session. That matches tmux. It does not match "I want my coding agent to read all panes but only type into the one I gave it."

---

## Decision: two-tier surface

Don't pick between "extend zmx" and "AgentStudio shim." Do both, split by what each is good at.

```
+----------------------------------------------+
|  External agent / CLI tool                   |
+----------------+-------------+---------------+
                 |             |
        Agent Studio sock      zmx sock (existing)
        (workspace verbs)      (session verbs)
                 |             |
+----------------v-----+   +---v---------------+
|  AgentControlServer  |   |  zmx daemon       |
|  (in AgentStudio.app)|   |  (separate proc)  |
|                      |   |                   |
|  - list_panes        |   |  Input, History,  |
|  - new_pane          |   |  Info, Run, Kill, |
|  - close_pane        |   |  Resize, Init,    |
|  - resolve_pane_to_  |   |  Detach, Ack      |
|    zmx_session       |   |                   |
|  - pipe_pane (proxy) |   |  + new: Subscribe |
|                      |   |    (G1 only)      |
+----------------------+   +-------------------+
```

**Tier 1 — Agent Studio socket (NEW, in `AgentStudio.app`).** Owns workspace-shaped verbs: things that need to know about tabs, splits, pane types, and the workspace command planes. Routes through `PaneActionCommand` / `WorkspaceCommandValidator` like a user action would. Dies with the app, which is fine — these verbs don't make sense when the GUI is closed.

**Tier 2 — zmx socket (EXTEND, in zmx fork).** Already speaks the per-session verbs. Add **one** new IPC tag — `Subscribe` — to close G1. Everything else (Input, History, etc.) is reused as-is. zmx daemon survives the GUI; agents tailing logs work without Agent Studio running.

The Tier 1 socket *also exposes* `send_keys` and `capture_pane`, but as a **proxy** to the zmx socket for terminal panes — so an agent that only learns one socket gets the full vocabulary. The proxy lets us layer G2/G3/G4/G5/G6 on top.

This matches the doc-of-record at `docs/architecture/remote_zmx_architecture_ideas.md` line 210: *"Agent Studio needs richer session metadata, health reporting, and potentially new IPC tags"* — `Subscribe` is the first such tag. It also keeps the "Phase 2 soft fork" trajectory from that doc intact: one upstream-mergeable addition, no architectural divergence.

---

## Tier 1 protocol — Agent Studio socket

**Transport.** Unix domain socket at `~/Library/Application Support/AgentStudio/agentctl.sock`, mode 0700. Created at app launch, removed on quit.

**Framing.** Length-prefixed JSON (`u32 length` + UTF-8 JSON body). One request, one response. Subscriptions: server sends a `subscription_ack` then streams JSON events with the same framing until the client closes or sends `unsubscribe`.

**Verbs.** Versioned envelope: `{"v": 1, "op": "...", "id": "<request-id>", "params": {...}}`.

### list_panes

Request: `{"op": "list_panes", "params": {"workspaceId": "?optional"}}`

Response:
```json
{
  "panes": [
    {
      "paneId": "pane_018f...",
      "workspaceId": "ws_018f...",
      "tabId": "tab_018f...",
      "kind": "terminal" | "bridge" | "webview",
      "title": "zsh — ~/agent-studio",
      "cwd": "/Users/me/agent-studio",
      "command": "zsh",
      "pid": 12345,
      "size": {"cols": 120, "rows": 40},
      "zmxSession": "as-pane-018f..." | null,
      "runtimeStatus": "running" | "exited" | "starting"
    }
  ]
}
```

Read-only. Built from `WorkspacePaneAtom` + `SessionRuntimeAtom` + `WorkspaceTabLayoutAtom`. No command-plane routing.

### send_keys

Request: `{"op": "send_keys", "params": {"paneId": "pane_...", "text": "...", "enter": true}}`

For terminal panes: server resolves `paneId → zmxSession`, opens a short-lived connection to the zmx socket, sends `Input` tag with `text` (and a trailing `\r` if `enter`), closes. Returns `{"ok": true}`.

For bridge/webview panes: out of scope for v1 (returns `{"ok": false, "error": "unsupported_pane_kind"}`).

### capture_pane

Request: `{"op": "capture_pane", "params": {"paneId": "pane_...", "lines": 200, "format": "plain" | "vt" | "html", "includeScrollback": false}}`

For terminal panes: server proxies to zmx `History` with the requested format, then truncates to last `lines` rows server-side (closes G4 without changing zmx). Returns:
```json
{"format": "plain", "content": "...", "truncated": true, "totalLines": 12345}
```

For bridge/webview panes: returns DOM text snapshot via existing webview surface APIs. Document the divergence — these are not terminals, so `vt` format is unavailable.

### pipe_pane

Request: `{"op": "pipe_pane", "params": {"paneId": "pane_...", "sinceCursor": "opaque-token-or-null"}}`

For terminal panes: server resolves to zmx session, opens a streaming connection to zmx with the new `Subscribe` tag (see Tier 2 below), and forwards each output chunk to the agent as:
```json
{"event": "output", "paneId": "pane_...", "bytes": "<base64>", "cursor": "<opaque>"}
```

The cursor lets a reconnecting agent ask `sinceCursor` and resume without losing bytes. Implementation note: cursor maps to a byte offset in zmx's internal output buffer; bounded by `History` retention.

End conditions: `{"event": "exit", "exitCode": 0}` when the PTY ends; `{"event": "error", "reason": "..."}` on transport failure.

### new_pane

Request: `{"op": "new_pane", "params": {"workspaceId": "...", "tabId": "?", "kind": "terminal", "cwd": "/path", "command": "?", "splitOf": "?paneId", "side": "?right|below"}}`

Routes through `PaneActionCommand.openPane(...)` so it passes `WorkspaceCommandValidator`. Returns `{"paneId": "pane_..."}` once the pane is live. Idempotent on a client-provided `idempotencyKey` to survive retry.

### close_pane

Request: `{"op": "close_pane", "params": {"paneId": "pane_..."}}`

Routes through `PaneActionCommand.closePane(...)`. Honors undo semantics — does **not** kill the underlying zmx session; the existing close-with-undo flow applies.

### resize_pane

Request: `{"op": "resize_pane", "params": {"paneId": "pane_...", "cols": 120, "rows": 40}}`

Terminal panes only. Proxies to zmx `Resize`. Bridge/webview return `unsupported_pane_kind`.

### Errors

Single error envelope: `{"ok": false, "error": "<code>", "message": "<human>", "id": "<request-id>"}` with codes: `unknown_pane`, `unsupported_pane_kind`, `permission_denied`, `protocol_version`, `invalid_params`, `runtime_unavailable`.

---

## Tier 2 protocol — zmx extension

**One new IPC tag: `Subscribe` (12).**

Request payload: empty (or `u64 sinceOffset` for resume).

Daemon behavior: register the client as a passive observer. Send all subsequent `Output` frames to this client, but do **not** treat it as an attached interactive client — i.e. it doesn't appear in `clients_len`, doesn't get `Detach` broadcasts, doesn't receive `Resize` echoes, can't send `Input`.

Closing the connection unsubscribes. No explicit `Unsubscribe` tag needed.

**Why not just attach as a regular client?** Three reasons:
1. Attached clients count toward `clients_len` — the user's `zmx list` would show ghost clients.
2. Attached clients receive `Detach`/`DetachAll` broadcasts intended for human users.
3. Future: passive observers can be rate-limited or coalesced differently from interactive clients.

This is the smallest possible upstream addition. Single tag, single handler, no protocol versioning headache (existing clients ignore unknown tags).

**Open question for upstream:** does `neurosnap/zmx` want this verb, or is this our first soft-fork patch? Sequence the upstream PR before the Agent Studio implementation — if it's accepted, Tier 2 is one git bump; if not, we carry the patch.

---

## Pane identity bridging (G2)

`Pane.id` is the external handle. Agents never see zmx session names directly.

**Mapping owner.** `SessionRuntimeAtom` already keys runtime status by `Pane.id`. Add a small read-only projection:

```swift
struct PaneRuntimeHandle {
    let paneId: Pane.ID
    let zmxSession: String?     // nil for non-terminal panes
    let kind: PaneKind
}
```

Exposed to `AgentControlServer` via `atom(\.sessionRuntime).handle(for: paneId)`. No new atom; this is a derivation on the existing one.

**Lifetime guarantee.** `Pane.id` is stable across:
- detach/reattach (zmx session persists)
- app relaunch (workspace store restores)
- crash (PaneCoordinator's restore path)

This is the property agents need. Document it explicitly in [Session Lifecycle](../architecture/session_lifecycle.md) when the implementation lands.

---

## Authorization (G6)

**v1: tmux-equivalent.** Socket at mode 0700. Any process running as the user can do anything. Ship this first; it's the same trust users already accept for tmux.

**v2 (deferred): capability tokens.** Per-agent token issued by the GUI ("grant my coding agent read access to pane X"). Sent in every request envelope. Server validates. Token store lives next to settings. Not in v1 because it requires UX (token issuance UI) that we shouldn't design before we know the verb set is right.

Note in protocol: `{"v": 1, ...}` envelope reserves room for `{"v": 1, "token": "...", ...}` without breaking v1 clients.

---

## CLI shim

`AgentStudio.app/Contents/MacOS/agentctl` (symlinked to `/usr/local/bin/agentctl` via the existing CLI install flow if the user opts in).

Verbs map 1:1 to the JSON ops. tmux-style flags so existing agent prompts port over:

```
agentctl list-panes [--workspace <id>] [--format json|tsv]
agentctl send-keys -t <paneId> [--enter] -- <text>
agentctl capture-pane -t <paneId> [-S <lines>] [-f plain|vt|html]
agentctl pipe-pane -t <paneId> [--since <cursor>]
agentctl new-pane [--workspace <id>] [--tab <id>] [--kind terminal] [--cwd <path>] [--command <cmd>]
agentctl close-pane -t <paneId>
agentctl resize-pane -t <paneId> -x <cols> -y <rows>
```

The shim is a thin socket client. No logic. Connects to `~/Library/Application Support/AgentStudio/agentctl.sock`, writes JSON, reads response, exits.

**Why a shim and not just "use the socket"?** Agents trained on tmux know the CLI shape. Free porting work.

---

## Where each piece lands (folder map)

| Component | Path | Role |
|-----------|------|------|
| `AgentControlServer` | `Sources/AgentStudio/Core/AgentIPC/AgentControlServer.swift` | Owns the Unix listener, framing, dispatch. `@MainActor` for the dispatch loop; I/O on `@concurrent nonisolated`. |
| `AgentControlVerbs.swift` | `Sources/AgentStudio/Core/AgentIPC/` | Codable request/response types per verb. |
| `AgentControlVerbHandlers.swift` | `Sources/AgentStudio/Core/AgentIPC/` | One handler per verb. Workspace verbs go through `PaneActionCommand`; runtime verbs proxy to zmx. |
| `ZmxAgentClient` | `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxAgentClient.swift` | Lightweight client used by `pipe_pane` / `send_keys` / `capture_pane` to reach the zmx daemon. Separate from `ZmxBackend` (which is the per-pane runtime); this is short-lived per request. |
| `Pane runtime handle` | `Core/State/MainActor/Atoms/SessionRuntimeAtom.swift` | Add `handle(for:)` projection. No new atom. |
| `agentctl` CLI target | `Sources/AgentCtl/main.swift` | New SwiftPM executable target. |
| zmx `Subscribe` tag | `vendor/zmx/src/ipc.zig`, `daemon.zig` | Upstream PR first, soft-fork fallback. |

**Imports** (per `directory_structure.md` rules): `AgentIPC` is in `Core/`, so it may import `Infrastructure/` and `Core/`, never `Features/` or `App/`. Verb handlers that need to dispatch `PaneActionCommand` use the existing `CommandDispatcher` — no new cross-import.

---

## Implementation phases

Each phase is independently shippable and observable. Don't skip ahead — each one closes a concrete agent workflow.

### Phase 0 — Verify foundation (no code)

- Confirm `Pane.id ↔ zmxSession` mapping is reachable from `Core/` without importing `Features/Terminal/`.
- Confirm zmx submodule pin is recent enough for IPC tag set researched here.
- Confirm `PaneRuntimeEventBus` carries output facts on terminal panes (gating for Phase 3).

### Phase 1 — Read-only shim (list + capture)

- `AgentControlServer` skeleton with framing + dispatch.
- Verbs: `list_panes`, `capture_pane` (proxy to zmx `History` only — no streaming yet).
- `agentctl list-panes`, `agentctl capture-pane`.
- Tests: integration test that drives the socket against a fake `WorkspacePaneAtom` + fake `ZmxAgentClient`.

**Closes:** "agent can see what's running and read a build log."

### Phase 2 — Input (send-keys)

- Add `send_keys` verb. Reuses `ZmxAgentClient` to send `Input` to zmx.
- `agentctl send-keys`.
- Decision needed: rate limit? log to a transcript? Default: no rate limit, log every send to a per-session event-bus fact so the user can audit.

**Closes:** "agent can drive a CLI prompt or TUI."

### Phase 3 — Streaming (pipe-pane) + zmx Subscribe

- Upstream PR for zmx `Subscribe` tag. Land or fork-and-carry.
- `pipe_pane` verb + streaming framing.
- `agentctl pipe-pane`.
- Tests: kill the agent mid-stream, reconnect with `sinceCursor`, verify no byte loss within retention window.

**Closes:** "agent can tail a long-running process cheaply."

### Phase 4 — Workspace mutations (new/close/resize)

- `new_pane`, `close_pane`, `resize_pane`. Routes through validator + coordinator.
- Idempotency keys.
- Tests: external creation participates in undo; external close honors the undo TTL.

**Closes:** "agent can prepare its own workspace."

### Phase 5 — CLI install + docs

- Opt-in `/usr/local/bin/agentctl` symlink from Preferences.
- Update [Session Lifecycle](../architecture/session_lifecycle.md) with the pane-identity stability guarantee.
- Update [Pane Runtime Architecture](../architecture/pane_runtime_architecture.md) with a new section: "External control surface."

---

## Out of scope (call it out)

- **Remote agent control.** The transport story for "agent on host A drives panes on host B" is owned by `remote_zmx_architecture_ideas.md`. Tier 1 is local-only in v1.
- **Bridge/webview send_keys.** No DOM event injection. Webview pipe-pane = no.
- **Per-feature verb extension.** No "send a bridge RPC" verb here — that surface belongs in the Bridge feature.
- **Token authorization UX.** Deferred to v2.
- **Cross-app pane sharing.** Two AgentStudio installs sharing a socket is not a goal.
- **Backwards-compatibility shims for v0.** This is v1 from day one. No upgrade path needed yet.

## Open questions

1. **Naming.** `agentctl` clashes with no Apple tool, but is generic. Alternatives: `aspane`, `asctl`, `studioctl`. User pick.
2. **Audit log location.** Send-keys transcript: in-memory only, or persisted to a per-workspace log file? Persistence helps debugging but raises a small privacy surface — anything an agent types lands on disk.
3. **`Subscribe` upstream PR.** Worth opening before we implement Phase 3, so we know if we're carrying a patch.
4. **Capture window default.** `agentctl capture-pane` with no `-S` — return last 200 lines? Full screen? tmux defaults to visible-only. Match that.
5. **Pane creation race.** `new_pane` returns when the pane exists, but before the shell prompt is ready. Should it block until first prompt, or return immediately and let the agent poll? tmux returns immediately; matching that is simpler.
6. **`Pane.id` shape.** Today it's a UUID. Agents type these — shorter handle (`%12` style) would be friendlier. Worth a separate small plan.

## References

- Transport/security baseline: `docs/architecture/remote_zmx_architecture_ideas.md`
- zmx IPC surface (researched 2026-05-30 via DeepWiki): `neurosnap/zmx` main — 11 tags, Unix socket, mode 0700, `libghostty-vt` for state
- Pane runtime contracts: `docs/architecture/pane_runtime_architecture.md`
- Event bus model: `docs/architecture/pane_runtime_eventbus_design.md`
- Command planes (where workspace verbs route): `docs/architecture/commands_and_shortcuts.md`
