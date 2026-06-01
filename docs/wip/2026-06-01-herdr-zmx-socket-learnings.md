# Learning from herdr — sockets, agent-state, and zmx (grounded study)

**Date:** 2026-06-01 · **Status:** research note (brainstorm). Not a plan, not scoped. Anything
in §5 that adds an atom/store/event-type/coordinator responsibility or an external command
surface is a CLAUDE.md "ask-first" decision — this doc exists to make those conversations
concrete and accurate, not to pre-decide them.

**What this is:** a source-grounded study of [`ogulcancelik/herdr`](https://github.com/ogulcancelik/herdr)
(Rust "agent multiplexer that lives in your terminal") and what it concretely teaches Agent
Studio about (a) an external control/observation socket, (b) semantic agent-state detection, and
(c) getting more out of our zmx fork. herdr solves the same problem from the opposite host (a TUI
server vs. a native macOS app), which makes almost every design decision in it a usable data
point for us.

### Method & sources

herdr facts below are grounded in its source via DeepWiki (it cites `src/…` paths inline) plus
`SKILL.md`; I mark file paths so claims are checkable. Agent Studio facts are grounded in the
in-repo zmx specs and a codebase sweep. Where I'm proposing rather than reporting, it says so.

- herdr source-of-truth modules referenced: `src/api/schema.rs` (socket API), `src/detect.rs`
  (state detection), `src/pane.rs` (detection loop), `src/terminal/state.rs` (authority model),
  `src/integration/mod.rs` (hooks), `src/server/headless.rs` (server + live handoff),
  `src/persist.rs` / `src/persist/restore.rs` (persistence).
- Agent Studio source-of-truth: [`session_lifecycle.md`](../architecture/session_lifecycle.md),
  [`zmx_restore_and_sizing.md`](../architecture/zmx_restore_and_sizing.md),
  [`zmx_terminal_integration_lessons.md`](../architecture/zmx_terminal_integration_lessons.md),
  [`remote_zmx_architecture_ideas.md`](../architecture/remote_zmx_architecture_ideas.md).

---

## 1. The thesis and the one insight that should anchor everything

Agent Studio and herdr make **opposite multiplexing bets**:

- **herdr is a thick server.** Its `HeadlessServer` *is* the multiplexer: it owns the PTYs, a
  persistent virtual-terminal (VT) per pane, the workspace/tab/pane tree, **and** it runs agent
  detection server-side against each pane's VT `screen_content`. Clients (the TUI) attach/detach
  over a binary protocol; external tools/agents drive it over a JSON socket API.
- **Agent Studio is a thick app + thin persistence.** The native app owns the
  workspace/tab/pane tree (the atom system); **zmx** owns only per-session persistence — one
  daemon per session, each holding a `ghostty_vt` shadow terminal and the live PTY. zmx
  deliberately has no tabs/splits/panes.

Two gaps vs herdr fall out of this:

1. **No external control/observation plane.** Nothing outside the app process can watch or drive
   the workspace. herdr's JSON socket API is exactly this.
2. **No semantic agent state.** `SessionRuntimeStatus` is `initializing/running/exited/unhealthy`
   — *process health*, not *agent* state (blocked / working / done / idle).

**The anchoring insight:** herdr detects agent state **where the persistent VT lives** — in its
server, against `screen_content`. Agent Studio's equivalent persistent VT is **the zmx daemon's
`ghostty_vt` shadow terminal** (it already parses every byte for state capture and is alive for
backgrounded panes too). So the architecturally faithful home for *background* agent-state
detection is **at/near the zmx daemon, surfaced as a new IPC tag** — not ANSI-scraping in Swift,
and not only the focused Ghostty surface. This single observation reframes Idea A/D in §5 and is
the highest-value takeaway in the doc.

---

## 2. herdr, completely (grounded)

### 2.1 Two protocols / two layers (this is the model we should copy)

herdr runs **two** transports, and the separation is the lesson:

| Layer | Transport | Who talks | herdr module |
|---|---|---|---|
| Internal client↔server | **bincode v2 Varint, `u32` LE length-prefixed** binary frames | TUI client ↔ `HeadlessServer` | server internals |
| External automation | **newline-delimited JSON, JSON-RPC-style** over a Unix socket | tools / agents / scripts ↔ server | `src/api/schema.rs` |

Socket discovery order for the JSON API: `--session <name>` → `HERDR_SOCKET_PATH` →
`HERDR_SESSION=<name>` → default `$XDG_CONFIG_HOME/herdr/herdr.sock` (named sessions live at
`~/.config/herdr/sessions/<name>/herdr.sock`). The two transports are on **physically separate
sockets** — the JSON API on `herdr.sock`, the binary client transport on `herdr-client.sock`
beside it — so the two-layer split (§3) is physical, not merely logical.

Envelope (`src/api/schema.rs`), encoded `#[serde(tag = "method", content = "params")]` so the
wire JSON is `{"id", "method", "params"}`:

```rust
struct Request { id: String, #[serde(flatten)] method: Method }   // -> {"id","method","params"}
struct SuccessResponse { id: String, result: ResponseResult }     // id echoes the request
```

### 2.2 Full JSON-API method surface (the `Method` enum)

| Namespace | Methods |
|---|---|
| server | `ping` (→ version/protocol/capabilities), `server.stop`, `server.live_handoff`, `server.reload_config` |
| workspace | `create`, `list`, `get`, `focus`, `rename`, `close` |
| worktree | `list`, `create`, `open`, `remove` |
| tab | `create`, `list`, `get`, `focus`, `rename`, `close` |
| agent | `list`, `get`, `read`, `send`, `rename`, `focus`, `start` |
| pane | `split`, `list`, `get`, `rename`, `send_text`, `send_keys`, `send_input`, `read`, **`wait_for_output`**, **`report_agent`**, **`release_agent`**, `report_metadata`, **`clear_agent_authority`**, `close` |
| events | **`subscribe`** (stream), **`wait`** (block until one matching event) |
| integration | `install`, `uninstall` |

Note herdr models **agents as first-class** alongside panes (`agent.*`), and exposes the inbound
authority channel (`pane.report_agent`) plus **two distinct releases**: `pane.release_agent`
(drop the agent entirely) and `pane.clear_agent_authority` (drop only the hook authority, keep
heuristic detection). The `events` namespace has **both** a streaming `subscribe` and a
block-until-one `wait` — the latter is the real precedent for "spawn helper, await done" (Idea F),
not a CLI poll. `pane.read` takes `--source {visible|recent|recent-unwrapped} --lines N`;
`pane.split` takes `--direction {right|down} [--no-focus]`. IDs are human-friendly: workspace `1`,
tab `1:1`, pane `1-1`, and "ids can compact when tabs/panes/workspaces close."

### 2.3 Agent-state detection (`src/detect.rs`, `src/pane.rs`, `src/terminal/state.rs`)

**The enum is only four values:**

```rust
enum AgentState { Idle, Working, Blocked, Unknown }
// Idle    = agent finished, prompt visible, nothing happening
// Working = actively processing/streaming
// Blocked = needs human input/approval
// Unknown = plain shell / unrecognized program
```

**"done" is not a fifth state — it's `Idle` + a UI `seen` flag.** `Idle & seen==false` renders
as **done** (teal ●); `Idle & seen==true` renders as **idle** (green ✓). "Reviewed" is a
UI-interaction bit, not a detector output. (The `SKILL.md` status vocabulary
`idle/working/blocked/done/unknown` is the *presentation* projection of `AgentState` + `seen`.)

**Two detection sources, combined:**

1. **Foreground-process probe** — `spawn_basic_detection_task` / `probe_foreground_process`
   (`src/pane.rs`) periodically identify which known agent owns the foreground (→ an `Agent`
   enum). This answers "*is* there an agent, and which."
2. **Terminal-output analysis** — `detect_agent(agent, screen_content)` (`src/detect.rs`)
   matches the bottom-of-buffer text against **per-agent** patterns, dispatching to **16
   per-agent detectors** (Claude, Codex, Gemini, Cursor, Antigravity, Cline, OpenCode, GitHub
   Copilot, Kimi, Kiro, Droid, Amp, Grok, Hermes, Pi, Qodercli). Returns an
   `AgentDetection { state, visible_blocker, visible_idle, visible_working }`. **The breadth is
   itself a lesson:** 16 hand-written detectors (and growing) is an open-ended maintenance tax —
   which is the strongest argument that for Agent Studio, **hook authority (Idea D) should be the
   *primary* state source and heuristics the fallback**, not the reverse.

**Per-agent heuristics (concrete, portable):**

| State | Example signals (by agent) |
|---|---|
| Blocked | Claude: structured prompt box, "do you want to proceed?" + "bash command" + yes/no. Codex: "press enter to confirm or esc to cancel", "[y/n]". Gemini: "waiting for user confirmation", box-draw "│ Apply this change". Hermes: "allow once / allow for this session / deny" + "enter to confirm". |
| Working | Droid/Grok: `has_braille_spinner` (Unicode braille spinner glyphs — agent-specific, not a general signal). Pi: "Working…". Claude: `has_claude_working_chrome`. Codex: `has_interrupt_pattern` / working header. Gemini: "esc to cancel". Hermes: "msg=interrupt" / "ctrl+c cancel". |
| Idle | default when no blocked/working match **and** `has_visible_idle` (e.g. `has_claude_prompt_box`, `has_codex_prompt`). |

**Timing constants (the debounce that makes it not-flicker):**
`PROCESS_RECHECK_IDENTIFIED=5s`, `PROCESS_RECHECK_UNIDENTIFIED=30s`,
`PROCESS_ACQUISITION_WINDOW=8s` (fast window 1500ms, fast recheck 500ms, slow recheck 2s),
`AGENT_MISS_CONFIRMATION_ATTEMPTS=6`. Detection tick varies with state:
`TICK_UNIDENTIFIED=500ms`, `TICK_IDENTIFIED=300ms`, `TICK_PENDING_RELEASE=50ms`. A
`CLAUDE_WORKING_HOLD` keeps "working" **sticky** briefly so a momentary idle read doesn't flap.

**The authority model — the hardest and most valuable part** (`src/terminal/state.rs`): heuristic
and hook signals can disagree, so herdr has explicit precedence. `TerminalState.hook_authority`
stores the integration-reported state; `recompute_effective_state` combines it with the live
screen signals:

- hook `Blocked` wins **outright** (highest priority); a `visible_blocker` can independently
  *raise* Blocked only when there is no fresh hook-Blocked — it never overrides one,
- `visible_working_overrides_hook` (a live spinner beats a stale "idle" hook),
- `visible_idle_stales_hook` (a visible prompt invalidates a stale "working" hook, but only after
  it persists ~`STALE_HOOK_IDLE_GRACE = 2s`),
- authority is **cleared** (`clear_agent_authority`) when the process exits or the detected agent
  conflicts with the hook source.

This "heuristic baseline + authoritative hook + tie-break rules + staleness eviction" is exactly
the reconciliation Agent Studio would need, already worked out.

### 2.4 Integration / hook contract (`src/integration/mod.rs`)

herdr injects three env vars into **every** managed pane: `HERDR_ENV` (am I inside herdr?),
`HERDR_PANE_ID` (which pane), `HERDR_SOCKET_PATH` (where to report).

`herdr integration install claude` writes `~/.claude/hooks/herdr-agent-state.sh` and edits
Claude's `settings.json` to map hook events → herdr actions:

| Claude hook event | herdr action/state |
|---|---|
| `SessionStart` | idle |
| `UserPromptSubmit` | working |
| `PreToolUse` | working |
| `PermissionRequest` | **blocked** |
| `Stop` | idle |
| `SessionEnd` | release |
| `PostToolUse`, `SubagentStop` | (not configured) |

Flow: the shell hook takes an `action` arg, slurps Claude's JSON payload from stdin, then a
Python shim reads `HERDR_ACTION` / `HERDR_PANE_ID` / `HERDR_SOCKET_PATH` / `HERDR_HOOK_INPUT_FILE`,
parses the event, and emits a JSON-RPC `pane.report_agent` (for working/idle/blocked) or
`pane.release_agent` (for release) over the socket. Payload: `pane_id`, `source: "herdr:claude"`,
`agent: "claude"`, `state`, `seq`, and optional `agent_session_id` / `agent_session_path` /
`message` / `custom_status` — the last being a **visual-only** status string that does **not**
drive the state machine (a useful precedent for surfacing agent-provided text without coupling it
to transitions; see Ideas D/G). Subtlety: `SubagentStop` and subagent `idle/release` are
**ignored** so a finished subagent doesn't prematurely mark the parent pane "done."

### 2.5 Persistence — five distinct paths (`src/persist.rs`, `src/server/headless.rs`)

herdr separates concerns we tend to lump together:

1. **Live persistence** — client detach (`ctrl+b q`) leaves `HeadlessServer` + pane process
   groups running. Reattach reconnects the UI.
2. **Snapshot restore** — `capture()` (`src/persist.rs`) writes `session.json` (+ optional
   `session-history.json`). Structs (`src/persist/snapshot.rs`): `SessionSnapshot` →
   `WorkspaceSnapshot` → `TabSnapshot` → `LayoutSnapshot` (serializable **BSP tree**) →
   `PaneHistorySnapshot` (ANSI + line count) + `PaneAgentSessionSnapshot`. `restore()`
   (`src/persist/restore.rs`) rebuilds the **layout + cwd**; shell processes are **re-spawned**
   (not preserved across a full restart).
3. **Pane screen-history replay** — restores recent terminal contents visually.
4. **Native agent session restore** — `PaneAgentSessionSnapshot` stores `{source, agent, kind,
   value}` (an agent **resume ID**); `pane_restore_startup` relaunches the agent **into its prior
   conversation** (e.g. `claude --resume <id>`) and **skips history replay** for that pane. This
   recovers the *agent*, not just the terminal.
5. **Live handoff** — `server.live_handoff` updates the binary **without killing processes** by
   passing PTY master FDs to a new server. Steps (`live_handoff` in `src/server/headless.rs`):
   pause PTY readers → `capture()` app snapshot → **`dup` PTY master FDs** → spawn new herdr in
   import mode → send manifest + FDs over a private Unix socket via **`SCM_RIGHTS`** → new server
   rebuilds pane runtimes around the received masters → bind public sockets, signal ready → old
   server commits and exits **without** terminating the process groups.

### 2.6 Notifications & suppression (`src/app/actions.rs`)

On `AppEvent::HookStateReported`, `HeadlessServer::handle_app_event` compares `prev_state` →
`next_state` and calls `notification_sound_for_state_change`: a **"done"** sound fires **only on
genuine background completions** (`Working`/`Blocked` → `Idle`, not e.g. `Unknown`→`Idle`), an
**"attention"** sound on transitions to `Blocked`; toasts fire if `ui.toast.delivery != off`.
**Suppression rule:** popups are suppressed when the pane is in the **active tab *and* the
terminal is focused** (`active_tab_suppresses_notifications`) — you don't get notified about what
you're already looking at. A live `visible_blocker` can override a `working` state and still
trigger attention.

---

## 3. Agent Studio today (grounded substrate)

| Concept | herdr | Agent Studio (file) |
|---|---|---|
| Internal persistence transport | bincode client↔server | **zmx IPC** — 11-tag binary protocol, 5-byte header (`tag:u8` + `len:u32 LE`), one socket/session ([`session_lifecycle.md`](../architecture/session_lifecycle.md)). Tags: Input/Output/Resize/Detach/DetachAll/Kill/Info/Init/History/Run/Ack. Driven via `attach`/`kill`/`list` shell-outs today; **`ZmxIPCClient` (LUNA-354)** is the planned direct-IPC replacement. |
| Server-side VT for state capture | `HeadlessServer` per-pane VT | **zmx daemon's `ghostty_vt`** shadow terminal (already parses all bytes, alive for background panes) |
| External JSON control plane | JSON socket API | **none — the gap** |
| Internal JSON-RPC machinery (reusable shape) | — | `RPCRouter` (JSON-RPC 2.0, `__commandId` dedup, error codes) — `Features/Bridge/Transport/RPCRouter.swift` (React↔Swift only today) |
| Event fan-out | `events.subscribe` | `EventBus<RuntimeEnvelope>` w/ per-source replay; `PaneRuntimeEventBus.shared`. Already carries `terminalActivity(burst settled)` and `agentNotificationRequested(title,body)` — `Core/RuntimeEventSystem/…` |
| Validator-gated verbs | `Method` enum | `PaneActionCommand` + `RuntimeCommand` (incl. `terminal(.sendInput)`), gated by `WorkspaceCommandValidator`/`DrawerCommandValidator` — `Core/Actions/…` |
| Agent state | `AgentState{Idle,Working,Blocked,Unknown}` + `seen` | **`SessionRuntimeStatus{initializing,running,exited,unhealthy}` — process health only** |
| Pane identity in-shell | `HERDR_PANE_ID` | **`ZMX_SESSION`** auto-injected (deterministic IDs) — free identity for hooks |
| Update-without-kill | `live_handoff` (SCM_RIGHTS) | zmx daemon already survives **app** restart; **zmx-binary** bumps can break IPC/restore (R2) — handoff not yet designed |
| Fork plan | n/a | already documented: extend IPC with **health/snapshot/config** tags, optional session tokens, TCP listener ([`remote_zmx_architecture_ideas.md`](../architecture/remote_zmx_architecture_ideas.md)) |

Critical alignment: herdr's two-transport split (binary internal + JSON external) **is** the
two-layer model Agent Studio should keep — zmx IPC = the binary internal layer; a new JSON
control socket = the external layer. Don't merge them; don't push orchestration into zmx.

---

## 4. Concept → mechanism → Agent Studio mapping

| herdr capability | herdr mechanism (file) | Agent Studio path | Status |
|---|---|---|---|
| Observe everything | `events.subscribe` | expose `PaneRuntimeEventBus` over a new AF_UNIX JSON socket, reusing `RPCRouter` shape | **gap → Idea B** |
| Drive workspace | `Method` enum → server | JSON method → `PaneActionCommand`/`RuntimeCommand` via validators | **gap → Idea C** |
| Send text to a pane | `pane.send_text` | `RuntimeCommand.terminal(.sendInput)` | exists internally |
| Semantic agent state | `detect.rs` + `seen` + authority | new agent-lifecycle state; detect in zmx `ghostty_vt`; reconcile per herdr's rules | **gap → Idea A** |
| Hook authority | `pane.report_agent` + `~/.claude/hooks` | Claude hook → control socket; `ZMX_SESSION` as pane id | **gap → Idea D** |
| Focus-aware notify | `suppress_active_tab_notifications` | `WorkspaceFocusDerived` + `agentNotificationRequested` + `InboxNotification`; rule in `AppPolicies` | **partial → Idea E** |
| Spawn helper agent + await | `agent.start` + **`events.wait`** | zmx **`Run` tag** + control verb + event plane (Idea B) | **gap → Idea F** |
| Resume an agent convo | `PaneAgentSessionSnapshot` (`--resume`) | capture agent resume IDs in pane metadata; relaunch on restore | **gap → Idea G** |
| Update w/o killing | `live_handoff` (SCM_RIGHTS) | FD handoff to a new zmx daemon on binary bump | **gap → Idea H** |

---

## 5. Grounded ideas (each cites the herdr precedent it copies)

Each: **What / Why / How (real files) / herdr precedent / Risk / Effort / Decision.**
Effort: S=days, M=~week, L=multi-week.

### A — Semantic agent-lifecycle state
- **What:** per-pane agent state `{idle, working, blocked, unknown}` **distinct from**
  `SessionRuntimeStatus`, plus a UI **reviewed** bit (herdr's `seen`) so "done = finished &
  unreviewed" vs "idle = reviewed."
- **Why:** "who is blocked on me / waiting for review" is the highest-value glance for a
  worktree-per-agent app; process health can't express it.
- **How (proposed):** detect in the **zmx daemon's `ghostty_vt`** (it has `screen_content` for
  every pane incl. background) and surface via a new **`AgentState` IPC tag** (fits the planned
  health/snapshot/config fork extension). Port herdr's per-agent patterns (§2.3) and its
  reconciliation rules (`recompute_effective_state`, sticky working, staleness eviction). Reuse
  herdr's debounce constants as starting points.
- **herdr precedent:** `src/detect.rs`, `src/terminal/state.rs`.
- **Decision (CLAUDE.md):** new `AgentLifecycleAtom` vs derived vs property on
  `SessionRuntimeAtom` (**prior: not the last** — different reason-to-change). Settle first.
- **Risk:** false positives (quiet "thinking" looks done); flap (→ port sticky/hold + confirmation
  attempts); where detection runs (zmx fork = Rust work). **Effort:** M (Swift-side) / L (zmx tag).

### B — External control socket: `events.subscribe`, read-only first
- **What:** AF_UNIX JSON socket streaming `PaneRuntimeEventBus` envelopes; **no mutation verbs**.
- **Why:** smallest blast radius, immediately useful for integration tests, dogfoods the
  subscription before any write path.
- **How:** new `App/`-level server; reuse `RPCRouter` dispatch/error-codes; dir perms `0700`
  (matches zmx daemon). Discovery via a new `AGENTSTUDIO_CONTROL_SOCKET` env var injected into
  panes (complement to the free `ZMX_SESSION` identity).
- **herdr precedent:** `events.subscribe`, socket discovery order (§2.1).
- **Risk:** even read-only leaks workspace structure → perms + per-user dir; slow clients drop
  (bus `bufferingNewest`). **Decision:** external plane = surface expansion → confirm. **Effort:** S–M.

### C — External control socket: mutating verbs
- **What:** JSON methods → `PaneActionCommand`/`RuntimeCommand` through existing validators.
- **herdr precedent:** the `Method` enum surface (§2.2).
- **Risk:** **largest security item.** Anything local could drive the workspace → socket perms +
  capability token in `AGENTSTUDIO_CONTROL_SOCKET` + method allowlist; re-entrancy guarded by
  main-actor serialization + validators (load-test). **Decision:** yes. **Effort:** M.

### D — Claude Code hook → authoritative state
- **What:** ship `~/.claude/hooks/agentstudio-agent-state.sh` + an installer; map Claude hook
  events to our states **exactly as herdr does** (table §2.4); report over the Idea-B/C socket.
- **Why:** authoritative beats heuristic; herdr's event→state map and "ignore SubagentStop"
  subtlety are battle-tested and directly reusable.
- **How:** pane identity from **`ZMX_SESSION`** (no new identity plumbing); socket from
  `AGENTSTUDIO_CONTROL_SOCKET`. Reconcile against heuristic per §2.3.
- **herdr precedent:** `src/integration/mod.rs`. **Risk:** versioned Claude hook schema; install
  UX. **Effort:** S (after B/C). **Decision:** hook vs zmx-tag-only as the authoritative source.

### E — Focus-aware notifications
- **What:** notify on background **→blocked** (attention) and **→done**; **suppress the active
  tab**.
- **How:** Idea-A transitions + `WorkspaceFocusDerived` + `agentNotificationRequested` +
  `InboxNotification`; suppression rule + sound mapping live in **`AppPolicies`**.
- **herdr precedent:** `notification_sound_for_state_change`, `suppress_active_tab_notifications`
  (§2.6). **Risk:** spam → gate on blocked/done + debounce. **Effort:** S (after A).

### F — Detached helper agents
- **What:** "spawn a helper agent, await its done state."
- **How:** zmx **`Run` tag already exists** → expose `agent.spawn` via Idea C; persistence-backed,
  survives restart. Await completion via the **event plane (Idea B)**, not polling.
- **herdr precedent:** `agent.start` to spawn + **`events.wait`** (block until one matching
  `pane.agent_status_changed`) to await — the same event stream Idea B exposes, so F reuses B
  rather than inventing a separate wait mechanism.
- **Risk:** orphan accumulation → tie GC to workspace + existing orphan-TTL (LUNA-324). **Effort:** M.

### G — Native agent session restore (resume IDs)
- **What:** capture each pane's agent **resume ID** (e.g. `claude --resume <id>`, also surfaced by
  the §2.4 hook as `agent_session_id` / `agent_session_path`) in pane metadata; on restore where
  the process is gone, relaunch the agent into its prior conversation.
- **Why:** complements zmx's process-persistence — covers full-restart, non-zmx/floating panes,
  and crashed agents; a strong "resume agent" UX. **This is a capability zmx alone doesn't give.**
- **herdr precedent:** `PaneAgentSessionSnapshot`, `pane_restore_startup`. **Decision:** new pane
  metadata field (atom-boundary). **Effort:** M.

### H — Update / zmx-bump handoff
- **What:** update the app and/or bump vendored zmx **without killing live agents.**
- **Why:** zmx IPC-version changes can break attach/restore (R2); today a zmx bump risks dropping
  every agent. herdr proves the mechanism.
- **How:** the herdr `live_handoff` blueprint — **`dup` PTY master FDs and pass them via
  `SCM_RIGHTS`** to a new zmx daemon; new daemon rebuilds around the masters; old exits without
  killing the process group. Near-term cheaper step: a tag/version capability handshake
  (via `Info`/`ping`) + drain/warn before a zmx-affecting update.
- **herdr precedent:** `live_handoff` (`src/server/headless.rs`). **Effort:** S (version check) / L
  (full FD handoff in the zmx fork). **Decision:** fork-scope.

---

## 6. Risk register

| # | Risk | Where | Sev | Mitigation |
|---|---|---|---|---|
| R1 | Control socket = local automation/observation surface | B/C/F | **High** | dir perms `0700`, capability token, **read-only first**, method allowlist, validator-gated mutations (mirror `remote_zmx_architecture_ideas.md` §Security: daemon has no auth → socket perms are the boundary) |
| R2 | zmx IPC tag/version skew breaks attach/restore on fork bump | A/H | **High** | additive backward-compatible tags; capability handshake via `Info`/`ping`; version-gate before reattach; FD handoff (Idea H) |
| R3 | Heuristic agent-state false positives / flapping | A/D | Med | port herdr's sticky `CLAUDE_WORKING_HOLD`, `AGENT_MISS_CONFIRMATION_ATTEMPTS=6`, recheck cadences; hook/`AgentState`-tag authoritative |
| R4 | Detection-home cost: parsing in zmx (Rust) vs Swift scraping | A | Med | prefer the zmx `ghostty_vt` (herdr's server-side model) — robust but real Zig/Rust work; scope explicitly |
| R5 | Unix socket path ≤ ~103 chars | sockets/IDs | Med | already tracked (`ZmxAttachDiagnostics`); short IDs/dirs |
| R6 | Two-terminal divergence regressions if new IPC use disturbs inner term | A, IPC clients | Med | keep inner term passive; preserve PR #112 (OSC 133 `redraw=0`) invariants; no new live-resize paths |
| R7 | External mutations interleaving with UI mutations | C | Med | main-actor serialization + validators; load-test |
| R8 | **Architecture-boundary governance** (new atom/store/event/coordinator/external plane) | A/B/C/F/G | Process | this doc is the pre-work; no boundary changes before sign-off |
| R9 | Notification spam | E | Low | gate on blocked/done, debounce, suppress active tab (herdr's rule) |
| R10 | Doc/code drift: `ZMX_DIR` `zmx/` (`session_lifecycle.md`) vs `z/` (`AppDataPaths.swift`) | — | Low | reconcile canonical doc |
| R11 | Scope creep toward "rebuild herdr" | all | Med | native-app-first; expose, don't re-implement multiplexing; zmx stays Layer-1 |

---

## 7. Sequencing (smallest-safest first)

1. **Settle Idea A's home** (atom vs derived vs property) — conversation; gates agent-state.
2. **Land `ZmxIPCClient` (LUNA-354)** — prerequisite for structured `Output`/`Info`/`Run`/`History`
   use and any zmx-side detection tag.
3. **Idea B** — read-only `events.subscribe` socket (smallest blast radius).
4. **Idea A heuristic** — start in Swift against `terminalActivity` for focused panes; then move
   detection to the zmx `ghostty_vt` for background panes (the faithful home).
5. **Idea D** — Claude hook authority (reuse herdr's event→state map + reconciliation).
6. **Idea E** — focus-aware notifications.
7. **Idea C** — mutating verbs (the big security/architecture conversation).
8. **Ideas F / G / H** — helper agents, agent-resume restore, FD handoff.

R8 ⇒ steps 1 and 7 are conversations before code.

---

## 8. Open questions for Shravan

1. **Agent-state home:** new `AgentLifecycleAtom`, derived, or property on `SessionRuntimeAtom`?
2. **Detection home:** zmx `ghostty_vt` + new IPC tag (herdr's server-side model, robust, Zig
   work) vs Swift-side scraping of focused surfaces (cheap, focused-only)?
3. **Authoritative source:** Claude Code hook (Idea D) vs zmx `AgentState` tag vs both with herdr's
   precedence rules?
4. **Do we want an external control plane at all**, or stay closed and pursue only internal
   awareness (A/D/E)?
5. **Agent-resume restore (G)** worth the pane-metadata addition now, or later?
6. **Revive the LUNA-354 `ZmxIPCClient` spec** now (prerequisite) or defer until a concrete
   consumer needs it?

---

## 9. References

**herdr (source via DeepWiki + `SKILL.md`):** `src/api/schema.rs`, `src/detect.rs`, `src/pane.rs`,
`src/terminal/state.rs`, `src/integration/mod.rs`, `src/server/headless.rs`, `src/persist.rs`,
`src/persist/snapshot.rs`, `src/persist/restore.rs`, `src/app/actions.rs`. Repo:
<https://github.com/ogulcancelik/herdr> · ecosystem: <https://github.com/yigitkonur/awesome-herdr>.

**Agent Studio (authoritative):** [`session_lifecycle.md`](../architecture/session_lifecycle.md),
[`zmx_restore_and_sizing.md`](../architecture/zmx_restore_and_sizing.md),
[`zmx_terminal_integration_lessons.md`](../architecture/zmx_terminal_integration_lessons.md),
[`remote_zmx_architecture_ideas.md`](../architecture/remote_zmx_architecture_ideas.md),
[`debugging/zmx-environment-isolation.md`](../debugging/zmx-environment-isolation.md). Code:
`ZmxBackend.swift`, `SessionRuntime.swift`, `SessionRuntimeAtom.swift`, `EventBus.swift`,
`EventChannels.swift`, `RuntimeEnvelopeCore.swift`, `PaneRuntimeEvent.swift`,
`PaneActionCommand.swift`, `RuntimeCommand.swift`, `RPCRouter.swift`, `TerminalRestoreRuntime.swift`,
`WorkspaceFocusDerived.swift`, `AppDataPaths.swift`.

**zmx:** upstream <https://github.com/neurosnap/zmx> · fork <https://github.com/ShravanSunder/zmx>
· OSC 133 fix PR neurosnap/zmx#112.
