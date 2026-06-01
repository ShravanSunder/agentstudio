# 2026-06-01 — Learning from herdr: sockets, systems, and getting more out of zmx

**Status:** brainstorm / research note, **reconciled against the existing Agent Studio zmx
specs** (see §0). **Not scoped, not a plan.** Every "Idea" in §6 that touches an atom, store,
event type, coordinator responsibility, or an external command surface is a CLAUDE.md
"ask-the-user-first" decision. This doc makes those conversations concrete; it does not
pre-decide them.

**Source of inspiration:** [`ogulcancelik/herdr`](https://github.com/ogulcancelik/herdr) —
"agent multiplexer that lives in your terminal" (Rust, single binary). Same problem Agent
Studio solves (run / observe / orchestrate many coding agents), opposite host: a TUI server vs.
a native macOS app.

**zmx:** upstream [`neurosnap/zmx`](https://github.com/neurosnap/zmx); Agent Studio vendors the
fork [`ShravanSunder/zmx`](https://github.com/ShravanSunder/zmx) (per `.gitmodules`).

---

## 0. Reconciliation with existing zmx specs (read these first)

The first draft of this note was written before I'd read the in-repo zmx specs. After reading
them, several things changed. **The authoritative docs are these, not this note:**

| Doc | What it owns |
|---|---|
| [`architecture/session_lifecycle.md`](../architecture/session_lifecycle.md) | **zmx IPC binary protocol (the 11 tags), header format, ZMX_DIR isolation, CLI commands, restore flow, identity contract** |
| [`architecture/zmx_restore_and_sizing.md`](../architecture/zmx_restore_and_sizing.md) | Deferred attach, geometry readiness, SIGWINCH relay, restart reconcile (LUNA-324), orphan TTL, **LUNA-354 ZmxIPCClient mapping** |
| [`architecture/zmx_terminal_integration_lessons.md`](../architecture/zmx_terminal_integration_lessons.md) | Two-terminal problem, OSC 133 `redraw=0` fix (PR #112), design principles, upstream status |
| [`architecture/remote_zmx_architecture_ideas.md`](../architecture/remote_zmx_architecture_ideas.md) | **Remote zmx: Option C (SSH tunnel + socket forwarding), 4-layer security model, fork strategy (Phase 1/2/3), "What a Fork Would Change"** |
| [`debugging/zmx-environment-isolation.md`](../debugging/zmx-environment-isolation.md) | ZMX_DIR environment isolation details |

### What I corrected after reading them

1. **zmx is not CLI-only.** It has a **binary IPC protocol over Unix sockets** with an 11-tag
   message set (§3). My first draft framed "use zmx better" as "call more upstream CLI
   subcommands (`tail`/`history`/`run -d`/`print`/…)." That menu was speculative against *current
   neurosnap*; **this fork is a ~1000 LOC Zig tool whose Agent Studio surface is `attach`/`kill`/
   `list` + the IPC tags.** The real lever is the IPC, not more shell-outs.
2. **The roadmap already names the lever: `ZmxIPCClient` (LUNA-354)** — direct IPC replacing CLI
   shell-outs. (Its design spec `2026-03-30-zmx-ipc-client-design.md` was removed as superseded
   in commit `bcc45b7`; revive/replace it rather than treating this note as the spec.)
3. **The fork strategy already exists in detail** (`remote_zmx_architecture_ideas.md` → "Why
   Fork", "Fork Strategy", "What a Fork Would Change"). My "you own the fork, so extend zmx"
   idea is correct but **subordinate to that plan** — extensions go in as new IPC tags
   (health/snapshot/config), not ad-hoc.
4. **Socket security is already specified:** daemon has **no auth**; **socket perms `0700`** are
   the boundary; remote uses **Option C (SSH tunnel + Unix-socket forwarding)** with a 4-layer
   model. I'd written `0750` and generic SSH — corrected.
5. **Minor doc/code drift to verify:** `session_lifecycle.md` says `ZMX_DIR=~/.agentstudio/zmx/`;
   `AppDataPaths.swift` appends `z` → `~/.agentstudio/z/`. Flagging, not asserting — worth a
   one-line reconcile in the canonical doc.

The herdr lessons in §2/§5 still stand — but they live at a **different layer** than zmx (§1).

---

## 1. The clarifying frame: two socket layers, don't conflate them

My first draft blurred "use sockets like herdr" with "use zmx." They are **two different
sockets at two different layers.** This distinction is the most important correction in the doc.

```
                         ┌─────────────────────────────────────────┐
  LAYER 2 (does NOT      │  External tool / Claude agent / MCP      │
  exist today)          │            │  JSON-RPC over AF_UNIX        │
  "App control plane"   │            ▼  (herdr's actual lesson)      │
  = herdr's socket API  │  ┌───────────────────────────────────┐   │
                        │  │   Agent Studio (native app)        │   │
                        │  │   owns workspaces/tabs/panes/atoms │   │
                        │  └───────────────┬───────────────────┘   │
                        └──────────────────┼───────────────────────┘
  LAYER 1 (exists,                         │  binary IPC, 11 tags
  being upgraded by      ┌─────────────────▼───────────────────┐
  LUNA-354 ZmxIPCClient) │  zmx daemon (one per session)        │
  "Persistence transport"│  ghostty_vt shadow term + PTY + shell│
                         └──────────────────────────────────────┘
```

- **Layer 1 — zmx IPC (persistence transport).** Per-session binary protocol (§3). Internal
  plumbing between Agent Studio and the zmx daemon that keeps the shell alive across restarts.
  Today driven via CLI shell-outs (`attach`/`kill`/`list`) + the attach socket; **LUNA-354**
  moves this to a direct `ZmxIPCClient`. This is **not** an agent-orchestration API.
- **Layer 2 — app control plane (the herdr lesson).** An app-level socket for *external* tools
  and agents to **observe and drive the workspace** (`events.subscribe`, `pane.split`,
  `pane.send_text`, …). **Does not exist.** This is what herdr's socket API actually teaches.

**herdr collapses these two layers** (its multiplexer *is* its API surface). **Agent Studio
keeps them separate, and that's correct** — zmx stays persistence-only, the app owns layout and
would own any external API. Keep them separate; do not push Layer-2 orchestration concerns into
the zmx fork, and don't expect zmx IPC to be your agent API.

| | **herdr** | **Agent Studio** |
|---|---|---|
| Owns workspaces/tabs/panes | herdr server | the native app (atoms) |
| Persistence | same process | **zmx, Layer 1 only** (one daemon+socket/session) |
| External drive/observe | Unix socket JSON-RPC (`workspace.*`/`pane.*`/`agent.*`/`events.subscribe`) | **nothing (Layer 2 gap)** |
| Semantic agent state | blocked/working/done/idle (heuristic+hook) | `SessionRuntimeStatus`: initializing/running/exited/unhealthy — **process health only** |

The two real gaps vs herdr: **(A)** no Layer-2 control plane; **(B)** no semantic agent state.

---

## 2. What we already have (the reusable substrate)

Grounded in the current codebase. The point: closing the herdr gaps is mostly *exposure +
reconciliation*, not greenfield.

| Asset | File | Why it matters |
|---|---|---|
| **JSON-RPC 2.0 router** (dispatch, `__commandId` dedup, error codes) | `Features/Bridge/Transport/RPCRouter.swift` | A Layer-2 control socket **reuses this shape**; herdr's protocol is the same idea over AF_UNIX instead of the WebKit bridge. |
| **Generic fan-out EventBus** w/ per-source replay (256) | `Core/RuntimeEventSystem/Events/EventBus.swift`, `EventChannels.swift` | herdr's `events.subscribe` = "expose your bus." `PaneRuntimeEventBus.shared` already carries a rich taxonomy. |
| Envelope taxonomy incl. `agentNotificationRequested`, `terminalActivity(burst settled)` | `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` | "Activity burst settled" is already a working→done heuristic seed; the notification fact already exists. |
| Envelope metadata: `correlationId`/`causationId`/`commandId`, global `seq` | `RuntimeEnvelopeCore.swift` | herdr-grade subscription semantics (causality, resume-from-seq) for free. |
| **Validator-gated command planes** | `Core/Actions/PaneActionCommand.swift`, `RuntimeCommand.swift`, `WorkspaceCommandValidator`, `DrawerCommandValidator` | The verbs a Layer-2 API exposes already exist and are gated (mapping in §5.1). |
| Deterministic, resumable zmx session IDs | `TerminalRestoreRuntime.swift`, `ZmxBackend.swift`, [identity contract](../architecture/session_lifecycle.md) | Pane identity ⇄ session identity is a pure function. |
| `ZMX_SESSION` auto-injected into every pane shell (zmx) | (zmx runtime) | Free per-pane **identity for hooks** (§5.3); herdr had to invent `HERDR_PANE_ID`. |
| Focus reader | `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` | Needed for focus-aware notification suppression (§6 Idea E). |

---

## 3. The zmx IPC protocol (ground truth, from `session_lifecycle.md`)

Binary protocol over Unix domain sockets. **Header = 5 bytes:** `tag: u8` + `payload_len: u32
LE`, then a variable payload. Daemon accepts any connection (**no auth — socket perms `0700`
are the boundary**); all clients receive broadcast `Output`. One-shot connect→send→read→close is
safe (matches `probeSession()`).

| Tag | Val | Dir | Purpose |
|---|---|---|---|
| `Input` | 0 | client→daemon | keystrokes / stdin |
| `Output` | 1 | daemon→client | **PTY output, broadcast to all clients** |
| `Resize` | 2 | client→daemon | cols/rows |
| `Detach` | 3 | client→daemon | disconnect this client |
| `DetachAll` | 4 | client→daemon | disconnect all |
| `Kill` | 5 | client→daemon | terminate session |
| `Info` | 6 | bidir | metadata: pid, cmd, cwd, created_at, task_exit (552-byte struct) |
| `Init` | 7 | client→daemon | handshake w/ client dimensions |
| `History` | 8 | daemon→client | serialized terminal state on attach |
| `Run` | 9 | client→daemon | **execute a command in the session** |
| `Ack` | 10 | daemon→client | acknowledgment |

Three facts here change my earlier ideas:
- **`Output` is a broadcast.** A *read-only* IPC client can connect to a backgrounded session's
  socket and receive its PTY bytes **without a visible Ghostty surface.** This — not a
  speculative `zmx tail` — is the in-protocol source for background agent-state heuristics.
- **`Run` already exists.** Detached command execution ("spawn a helper") is in-protocol; no new
  CLI verb needed.
- **`Info` already carries health** (pid/cmd/cwd/created_at/`task_exit`) — richer than parsing
  `zmx list`.

---

## 4. How to get more out of zmx (reframed onto the IPC reality)

The lever is **the IPC client and the fork's tag set**, not more CLI shell-outs.

1. **Land `ZmxIPCClient` (LUNA-354).** Direct IPC replaces `attach`/`kill`/`list` shell-outs:
   removes subprocess/escaping/latency overhead, enables structured reads (`Info`, `History`),
   and is the prerequisite for everything below. Revive the superseded design spec.
2. **Background output via the `Output` broadcast** (§3) — the grounded version of "read a
   backgrounded pane." Connect a read-only client per agent-bearing background session; feed
   bytes into heuristic agent-state (§6 Idea A/D). Throttle; only tap agent panes.
3. **Authoritative agent state via a new IPC tag in the fork** — e.g. `AgentState`/`Health`,
   matching the already-planned *"Extended with health, snapshot, config"* fork change
   (`remote_zmx_architecture_ideas.md`). Robust alternative to ANSI scraping; backward-compatible
   tag addition (see R2).
4. **Use `Info` for health** instead of `zmx list` parsing once the IPC client exists.
5. **Remote = Option C, already chosen.** SSH tunnel + **Unix-socket forwarding** (not TCP port
   forwarding), 4-layer security (SSH auth → remote socket `0700` → local socket `0700` →
   daemon). `ZmxIPCClient` code is identical local vs remote; only the socket path changes. Don't
   re-derive this — implement `remote_zmx_architecture_ideas.md` §"Security Model (Option C)".

**zmx invariants (non-negotiable, from the specs):**
- One daemon + one socket **per session**; **Unix socket path ≤ ~103 chars** (tracked in
  `ZmxAttachDiagnostics`) — constrains any ID/socket-dir scheme.
- The **two-terminal problem** (outer Ghostty + inner `ghostty_vt`) is the root of every zmx bug;
  OSC 133 `redraw=0` (PR #112) fixed prompt loss. Keep the inner terminal **passive**.
- **SIGWINCH relay latency is inherent** (3 extra hops) — accept cosmetic resize artifacts.
- zmx has **no tabs/splits/panes by design** — never push layout into it.
- Restore uses **deferred attach after readiness** + **restart reconcile** (LUNA-324) + orphan
  TTL. Any new IPC use must respect that sequencing.

---

## 5. Sockets & systems lessons from herdr (Layer 2)

### 5.1 A local control socket speaking newline-delimited JSON-RPC

herdr exposes `workspace.*`/`tab.*`/`pane.*`/`agent.*` + `events.subscribe`. Maps onto verbs we
already have (validator-gated):

| herdr method | Agent Studio equivalent (existing) |
|---|---|
| `pane.send_text` | `RuntimeCommand.terminal(.sendInput(String))` |
| `pane.split` | `PaneActionCommand.insertPaneRequest(PaneInsertRequest)` |
| `workspace.create` | `PaneActionCommand.openWorktree` / `.openNewTerminalInTab` |
| `pane.read` | zmx `History`/`Output` over IPC (§3) **or** Ghostty snapshot |
| `pane.focus` / `tab.focus` | `PaneActionCommand.selectTab` + focus routing |
| `events.subscribe` | subscribe to `PaneRuntimeEventBus.shared` |
| `pane.report_agent` (inbound) | **new** pane fact → agent-lifecycle state (§6 Idea A) |

New work = a transport + thin JSON-RPC→command translation, reusing `RPCRouter`.

### 5.2 `events.subscribe` read-only first — the safe wedge

Read-only event streaming over the Layer-2 socket: no mutation surface, no validators exposed,
trivially sandboxed, immediately useful for integration tests. Dogfood subscription semantics
before any write verb exists.

### 5.3 Env injection for identity + discovery — half is already free

herdr injects `HERDR_SOCKET_PATH` / `HERDR_PANE_ID` / `HERDR_ENV`. **zmx already injects
`ZMX_SESSION`** (identity) and our IDs are deterministic, so "which pane am I" is solved. Add one
var (`AGENTSTUDIO_CONTROL_SOCKET`) pointing at the Layer-2 socket and discovery is complete.

### 5.4 Two-tier state: heuristic default + authoritative hook override

Zero-config heuristic baseline (we already emit `terminalActivity(burst settled)`) + a Claude
Code hook forwarding semantic state (`Stop`/`Notification`/approval) over the Layer-2 socket
(`pane.report_agent`). Reconcile the way the topology accumulator reconciles scanned vs cached.
herdr installs hooks at `~/.claude/hooks/herdr-agent-state.sh`; an installer that drops
`~/.claude/hooks/agentstudio-agent-state.sh` (reading `ZMX_SESSION` + `AGENTSTUDIO_CONTROL_SOCKET`)
is the works-for-users step (§5.5).

### 5.5 / 5.6 Integration installers, MCP wrapper

herdr ships `integration install claude` (writes the hook) and an MCP wrapper + recipe engine.
For us: a hook installer (small, high-leverage) and — later — an MCP server in front of the
Layer-2 socket so Claude agents orchestrate via *tools*. Both depend on §5.1 existing.

---

## 6. Grounded brainstorming ideas

Each: **What / Why / How (real files+docs) / Risk / Effort / Decision.** Smallest-safest first.

### Idea A — Semantic agent-lifecycle state (blocked/working/done/idle, + reviewed axis)
- **What/Why:** per-pane *agent* state distinct from `SessionRuntimeStatus` (which stays process
  health). Done=finished-unreviewed vs Idle=finished-reviewed. Highest-value sidebar glance for a
  worktree-per-agent app.
- **How:** heuristic from `terminalActivity` (+ background `Output` broadcast, §3/§4.2);
  authoritative from a Claude hook (§5.4) **or** a new zmx `AgentState` IPC tag (§4.3).
- **Decision (CLAUDE.md atom boundary):** new `AgentLifecycleAtom` vs derived vs property on
  `SessionRuntimeAtom`. Prior: **not** the last (different reason-to-change). Settle first.
- **Risk:** heuristic false positives (quiet "thinking" looks Done); review-state persistence.
- **Effort:** M (+S hook).

### Idea B — Layer-2 control socket, `events.subscribe` read-only
- **How:** new `App/`-level AF_UNIX server, reuse `RPCRouter` dispatch, stream
  `PaneRuntimeEventBus.shared` as JSON lines. Dir perms `0700` (matches zmx).
- **Risk:** even read-only leaks workspace structure → perms + per-user dir. Backpressure:
  `bufferingNewest(256)` drops, not blocks. **Decision:** external plane = surface expansion.
- **Effort:** S–M.

### Idea C — Layer-2 mutating verbs
- **How:** JSON-RPC→`PaneActionCommand`/`RuntimeCommand` through existing validators (§5.1).
- **Risk:** **biggest security item.** Anything local could drive the workspace → socket perms +
  capability token in `AGENTSTUDIO_CONTROL_SOCKET` + method allowlist; re-entrancy guarded by
  main-actor serialization + validators (load-test). **Decision:** yes.
- **Effort:** M.

### Idea D — Background agent-state input via zmx `Output` broadcast
- **How:** read-only `ZmxIPCClient` per agent-bearing background session subscribes to `Output`
  (§3); runtime actor emits heuristic facts. Prefer a structured `AgentState` tag (§4.3) over
  ANSI scraping if investing.
- **Risk:** N sockets/streams = cost; ANSI parsing brittle (→ the case for the new tag).
  **Depends on** LUNA-354. **Effort:** M (broadcast) / L (new tag, robust).

### Idea E — Focus-aware notifications
- **How:** Idea A transitions + `WorkspaceFocusDerived` + `agentNotificationRequested` +
  `InboxNotification`. Suppression rule is behavioral → **`AppPolicies`**. Notify on Blocked
  (background) primarily. **Risk:** spam → gate+debounce. **Effort:** S (after A).

### Idea F — MCP server / skill (agent-driven orchestration)
- Depends on C; thin tools over Layer-2 methods; mirrors herdr MCP + `SKILL.md`. **Effort:** M–L.
  **Decision:** yes. Largest surface, do last.

### Idea G — Detached helper agents
- **How:** the zmx **`Run` tag already exists** (§3) → expose `agent.spawn` via Idea C; survives
  restart via persistence. **Risk:** orphaned sessions → tie GC to workspace + existing orphan
  TTL (LUNA-324). **Effort:** M.

### Idea H — Update/handoff resilience
- **What/Why:** update the app and/or bump the vendored zmx **without killing live agents.**
  herdr ships experimental `update --handoff`. Ours is harder: **IPC-protocol changes across zmx
  versions can break attach/restore** — adding tags must stay backward-compatible (R2).
- **How:** (a) version/tag-capability check before reattach; (b) drain/warn before a zmx-affecting
  update; (c) long-term explicit handoff in the fork. **Effort:** S (version check now) / L (full).

---

## 7. Risk register

| # | Risk | Where | Sev | Mitigation |
|---|---|---|---|---|
| R1 | Layer-2 socket = local automation/observation surface | B/C/F | **High** | dir perms `0700`, capability token, read-only first, method allowlist, validators (per `remote_zmx_architecture_ideas.md` §Security) |
| R2 | zmx IPC tag/version skew breaks attach/restore on fork bump | H, §4.3 | **High** | additive, backward-compatible tags; capability handshake via `Info`; version-gate before reattach |
| R3 | Heuristic agent-state false positives | A/D | Med | hook/`AgentState` tag authoritative; conservative transitions; debounce |
| R4 | Unix socket path ≤ ~103 chars | IDs, sockets | Med | already tracked (`ZmxAttachDiagnostics`); keep IDs/dirs short |
| R5 | N background `Output` clients = resource cost | D | Med | tap only agent-bearing background panes; throttle |
| R6 | ANSI scraping brittle | D | Med | prefer structured `AgentState` IPC tag |
| R7 | External mutations interleaving with UI mutations | C | Med | main-actor serialization + validators; load-test |
| R8 | Two-terminal divergence (resize/cursor) regressions if new IPC use disturbs inner term | §4, IPC clients | Med | keep inner term passive; reuse PR #112 invariants; don't add live-resize paths |
| R9 | **Architecture-boundary governance** (new atom/store/event/coordinator/external plane) | A/B/C/F/G | Process | this doc is the pre-work; do not implement boundary changes before sign-off |
| R10 | Doc/code drift: `ZMX_DIR` `zmx/` vs `z/` | §0.5 | Low | reconcile canonical doc with `AppDataPaths.swift` |
| R11 | Scope creep toward "rebuild herdr" | all | Med | native-app-first; expose, don't re-implement multiplexing; zmx stays Layer-1 |

---

## 8. Suggested sequencing

1. **Settle Idea A's home** (atom vs derived vs property) — pure conversation. Gates agent-state.
2. **Land `ZmxIPCClient` (LUNA-354)** — unblocks structured reads + `Output`/`Info`/`Run` use.
3. **Idea B** — read-only `events.subscribe` Layer-2 socket (smallest blast radius).
4. **Idea A heuristic** via `terminalActivity` (focused panes), then **Idea D** (background
   `Output`).
5. **Idea E** — focus-aware notifications.
6. **Idea C** — Layer-2 mutating verbs (the big security/architecture conversation).
7. **Ideas F/G/H** — MCP/skill, `Run`-tag helpers, update handoff.
8. **Remote (Option C)** is independently sequenced per `remote_zmx_architecture_ideas.md`.

R9 ⇒ steps 1 and 6 are conversations before code.

---

## 9. Open questions for Shravan

1. **Agent-state home:** new `AgentLifecycleAtom`, derived, or property on `SessionRuntimeAtom`?
2. **Do we want a Layer-2 control plane at all**, or stay closed and pursue only internal
   awareness (A/D/E)? The fork in the road.
3. **Authoritative state source:** Claude Code hook vs a new zmx `AgentState` IPC tag (the fork's
   planned health/snapshot/config extension)? Or both?
4. **Revive LUNA-354 `ZmxIPCClient` spec now** as the prerequisite, or keep CLI shell-outs until a
   concrete consumer (D) needs IPC?
5. **MCP vs raw socket** as the eventual agent-facing surface (if any)?

---

## 10. References

**In-repo (authoritative):** `architecture/session_lifecycle.md`,
`architecture/zmx_restore_and_sizing.md`, `architecture/zmx_terminal_integration_lessons.md`,
`architecture/remote_zmx_architecture_ideas.md`, `debugging/zmx-environment-isolation.md`.
Code: `ZmxBackend.swift`, `SessionRuntime.swift`, `SessionRuntimeAtom.swift`, `EventBus.swift`,
`EventChannels.swift`, `RuntimeEnvelopeCore.swift`, `PaneRuntimeEvent.swift`,
`PaneActionCommand.swift`, `RuntimeCommand.swift`, `RPCRouter.swift`, `TerminalRestoreRuntime.swift`,
`WorkspaceFocusDerived.swift`, `AppDataPaths.swift`.
**External:** herdr <https://github.com/ogulcancelik/herdr> (+ `SKILL.md`); awesome-herdr
<https://github.com/yigitkonur/awesome-herdr>; zmx upstream <https://github.com/neurosnap/zmx>;
zmx fork <https://github.com/ShravanSunder/zmx>; zmx PR #112 (OSC 133 redraw fix).
