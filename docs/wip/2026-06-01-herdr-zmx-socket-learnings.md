# 2026-06-01 — Learning from herdr: sockets, systems, and getting more out of zmx

**Status:** brainstorm / research note. **Not scoped, not a plan.** Every "Idea" below
that touches an atom, store, event type, coordinator responsibility, or an external command
surface is a CLAUDE.md "ask-the-user-first" decision. This doc exists to make those
conversations concrete, not to pre-decide them.

**Source of inspiration:** [`ogulcancelik/herdr`](https://github.com/ogulcancelik/herdr) —
"agent multiplexer that lives in your terminal" (Rust, single binary). It solves the same
problem Agent Studio solves (run/observe/orchestrate many coding agents) from the opposite
host: a TUI server instead of a native macOS app.

**zmx reference:** [`neurosnap/zmx`](https://github.com/neurosnap/zmx) upstream; Agent Studio
vendors the fork [`ShravanSunder/zmx`](https://github.com/ShravanSunder/zmx) (per
`.gitmodules`). Because it is **our fork**, "use zmx better" includes "extend zmx," not just
"call more of its CLI."

> ⚠️ Grounding caveat: the zmx CLI surface in §4 is the documented **upstream** surface. We
> confirmed `attach`/`list`/`kill` are what Agent Studio calls today (`ZmxBackend.swift`). The
> other subcommands (`run -d`, `wait`, `history`, `tail`, `send`, `print`, `write`) should be
> verified against the pinned fork commit before anyone builds on them. They are a menu of
> capabilities, not a promise about the current submodule.

---

## 1. The one idea that reframes everything: opposite multiplexing bets

| | **herdr** | **Agent Studio** |
|---|---|---|
| Who owns workspaces/tabs/panes? | The **herdr server** (it *is* the multiplexer) | The **native app** (the atom system) |
| Who owns session persistence? | The herdr server (same process) | **zmx**, and only zmx — one daemon + one Unix socket per session |
| How do agents/tools drive it? | **Unix socket, newline-delimited JSON-RPC** (`workspace.*`, `tab.*`, `pane.*`, `agent.*`, `events.subscribe`) | **Nothing.** No external control plane exists. |
| Persistence philosophy | Server keeps panes alive across client detach | zmx keeps PTY alive across app restart; zmx *refuses* to do tabs/splits/panes — defers to host |
| State awareness | Sidebar: blocked / working / done / idle, heuristic + hook | `SessionRuntimeStatus`: initializing / running / exited / unhealthy — **process health only** |

**The takeaway:** Agent Studio's *app* already plays herdr's *server* role for layout, and zmx
correctly plays a role herdr doesn't even separate out (pure persistence). The two genuine
gaps versus herdr are:

1. **No socket front door** — nothing outside the process can observe or drive the workspace.
2. **No semantic agent state** — we track whether the *process* is alive, not whether the
   *agent* is blocked / working / done / awaiting review.

Everything below is about closing those two gaps **using assets we already have**, and about
using zmx for more than `attach`.

---

## 2. What we already have (the reusable substrate)

Grounded in the current codebase. These are the building blocks the ideas in §5 reuse — the
point is that most of "becoming herdr-like" is *exposure and reconciliation*, not new
infrastructure.

| Asset | File | Why it matters |
|---|---|---|
| **JSON-RPC 2.0 router** with method dispatch, `__commandId` dedup, standard error codes | `Features/Bridge/Transport/RPCRouter.swift` | An external control socket would **reuse this dispatch shape**. We are not inventing a protocol — herdr's protocol is *literally the same idea* (newline-delimited JSON-RPC) over a different transport (AF_UNIX instead of the WebKit bridge). |
| **Generic fan-out EventBus** with per-source replay (256) | `Core/RuntimeEventSystem/Events/EventBus.swift`, `EventChannels.swift` | herdr's `events.subscribe` is exactly "expose your event bus." We already have `PaneRuntimeEventBus.shared` carrying a rich taxonomy. |
| **Rich envelope taxonomy** incl. `agentNotificationRequested(title,body)` and `terminalActivity(activity burst settled)` | `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` | "Activity burst settled" is *already* a heuristic "agent went quiet" signal — the seed of working→done detection. `agentNotificationRequested` already exists as a pane fact. |
| Envelope metadata: `correlationId` / `causationId` / `commandId`, global `seq` | `RuntimeEnvelopeCore.swift` | An external subscriber can trace causality and resume from a sequence — herdr-grade subscription semantics for free. |
| **Two typed command planes** | `Core/Actions/PaneActionCommand.swift`, `Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift` | The verbs an external API would expose already exist and are **validator-gated**. See mapping in §3.1. |
| **Validators** | `WorkspaceCommandValidator`, `DrawerCommandValidator` | Any external caller goes through the same gate as the UI — security/correctness for free. |
| **Deterministic, resumable zmx session IDs** | `Features/Terminal/Restore/TerminalRestoreRuntime.swift`, `ZmxBackend.swift` | `as-<repoKey16>-<wtKey16>-<pane16>` etc. Pane identity ⇄ session identity is already a pure function. |
| **`ZMX_SESSION` auto-injected into every pane's shell env** (zmx behavior) | (zmx runtime) | This is the **identity channel for hooks** — see §3.3. We get it for free; herdr had to invent `HERDR_PANE_ID`. |
| Focus reader | `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` | Needed for focus-aware notification suppression (§5, Idea E). |

**Net:** the socket-API and agent-state features are mostly *wiring existing things together*,
not greenfield. That is the single most important grounding result in this doc.

---

## 3. Sockets & systems lessons from herdr

### 3.1 A local control socket speaking newline-delimited JSON-RPC

herdr exposes a Unix socket; clients send newline-delimited JSON request envelopes and read
responses. Method families mirror the domain model: `workspace.*`, `tab.*`, `pane.*`,
`agent.*`, plus `events.subscribe`.

**How it maps to us (concrete):**

| herdr method | Agent Studio equivalent (existing) |
|---|---|
| `pane.send_text` / `pane send-text` | `RuntimeCommand.terminal(.sendInput(String))` |
| `pane.split` | `PaneActionCommand.insertPaneRequest(PaneInsertRequest)` |
| `workspace.create` | `PaneActionCommand.openWorktree` / `.openNewTerminalInTab` |
| `pane.read` (scrollback) | zmx `history`/`tail` (see §4) **or** Ghostty surface snapshot |
| `pane.focus` / `tab.focus` | `PaneActionCommand.selectTab`, focus routing |
| `events.subscribe` | subscribe to `PaneRuntimeEventBus.shared` |
| `pane.report_agent` / `release_agent` (inbound) | **new** pane fact → agent-lifecycle atom (§5 Idea A) |

The verbs already exist and are validator-gated. The new work is a **transport + a thin
translation layer** from JSON-RPC method → `PaneActionCommand`/`RuntimeCommand`, reusing
`RPCRouter`'s dispatch/dedup/error-code machinery.

### 3.2 `events.subscribe` — expose the bus read-only first

The lowest-risk, highest-signal first step. A read-only `events.subscribe` over the socket
lets external tools (and our own test harnesses) watch pane/agent/topology facts without any
ability to *mutate* the workspace. No validator surface, no destructive verbs, trivially
sandboxable. It also dogfoods the subscription semantics before we expose write verbs.

### 3.3 Environment injection for identity + discovery — and we already have half of it

herdr injects three env vars into each pane's shell: `HERDR_SOCKET_PATH` (where to connect),
`HERDR_PANE_ID` (who am I), `HERDR_ENV` (am I inside herdr at all). An in-pane hook reads these
to phone home.

**We already have the identity half for free:** zmx injects `ZMX_SESSION` into every session's
environment, and our session IDs are deterministic functions of pane identity. So a hook
running inside an Agent Studio pane can already answer "which pane am I." To complete the
pattern we'd inject one more var (e.g. `AGENTSTUDIO_CONTROL_SOCKET`) pointing at the §3.1
socket. That's the entire discovery story.

### 3.4 Two-tier state: zero-config heuristics + authoritative hook override

herdr classifies state from foreground process + terminal output **with no config**, and lets
first-party agents forward *semantic* state over the socket (`pane.report_agent`). For Claude
Code specifically, herdr installs a hook at `~/.claude/hooks/herdr-agent-state.sh`.

This is the right shape for us:
- **Heuristic baseline** so *every* pane gets a state with zero setup. We already emit
  `terminalActivity(activity burst settled)` — quiet-after-busy is a working→done candidate.
- **Authoritative override** when a Claude Code hook can emit `Stop`/`Notification`/
  `PreToolUse(approval)` events. These reconcile against the heuristic the same way the
  topology accumulator reconciles scanned vs cached worktrees.

### 3.5 Integration installers

herdr ships `herdr integration install claude` that writes the hook file for you. If we go the
hook route, a one-shot installer that drops `~/.claude/hooks/agentstudio-agent-state.sh`
(reading `ZMX_SESSION` + `AGENTSTUDIO_CONTROL_SOCKET`) is the difference between "works for the
author" and "works for users."

### 3.6 MCP wrapper + recipe engine

herdr's ecosystem wraps the CLI in an MCP server and adds a recipe engine with template
interpolation (`{{ stepId.result.path }}`). For us, an MCP server in front of the §3.1 socket
would let a Claude agent orchestrate panes via *tools* rather than raw socket calls — arguably
the most natural fit given our users are already driving Claude. (Bigger surface; later phase.)

### 3.7 Client library

herdr ships a Python client that handles socket discovery, envelopes, subscriptions, typed
errors. Worth noting as a DX multiplier *if* the socket API ships — not a day-one item.

---

## 4. How to better use zmx

Today `ZmxBackend.swift` calls exactly three subcommands: `attach`, `list`, `kill`. zmx's
(upstream) surface offers far more, and several primitives map directly onto the herdr
capabilities we admire. **Verify against the pinned fork before building.**

| zmx primitive (upstream) | What it unlocks for us | Maps to herdr |
|---|---|---|
| **`ZMX_SESSION`** auto-injected env var | Free per-pane identity inside the shell → hooks (§3.3) | `HERDR_PANE_ID` |
| `ZMX_SESSION_PREFIX` | Namespace sessions per workspace / per release channel | herdr named sessions w/ separate sockets |
| `zmx tail <name>` | **Follow live output of a backgrounded pane** the Ghostty surface isn't rendering | `wait output --match` source |
| `zmx history <name> [--vt\|--html]` | Read scrollback of any session without attaching a surface | `pane read --source recent` |
| `zmx run <name> -d [cmd]` + `zmx wait <name>` | Detached execution + block-until-done → "spawn helper, await completion" | `wait agent-status --status done` |
| `zmx send <name> <text\r>` | Fire-and-forget input to a non-focused session | `pane send-text` |
| `zmx print <name> <text>` | Inject a **status banner into scrollback without touching the agent's PTY input** (e.g. "⏸ paused by Agent Studio", "✓ reviewed") | (herdr has no equivalent) |
| `zmx write <name> <file>` (chunked ~48KB) + SSH-first design | File transfer + **remote worktrees/agents over SSH as a first-class citizen** | herdr remote attach |
| `zmx list --short` (PID, client count, cwd) | Richer health than "is it in the list" | — |

**The big two:**

1. **`zmx tail`/`history` is the missing input for background heuristics.** Our state detection
   today can only see the *focused* Ghostty surface. For the herdr-style "which of my 8
   background agents is blocked" sidebar, we need output from panes that aren't rendering. zmx
   already buffers all of it (via `libghostty-vt`) and exposes it. This is the cleanest source.

2. **We own the fork — so the best "use zmx better" may be to extend zmx itself.** Instead of
   scraping `zmx tail` text and re-parsing it in Swift, we could add a structured control/agent-
   state channel to our zmx fork (e.g. a JSON line emitted on the per-session socket when the
   foreground process or VT state changes). That turns heuristic detection from "scrape stdout"
   into "consume an event," and it's *upstreamable*. This is a strategic option herdr doesn't
   have (their multiplexer and their socket API are the same binary; ours are separable).

**zmx design facts that constrain us (not negotiable):**
- One daemon + one Unix socket **per session**; socket path lives under `ZMX_DIR`
  (`~/.agentstudio/z/`). **Unix socket paths max out at ~103 chars** — already tracked in
  `ZmxAttachDiagnostics`. Any session-ID scheme change must respect this.
- zmx restoration is **`libghostty-vt`-based** — same VT engine as the embedded terminal. This
  is *why* the pairing is clean and why scrollback fidelity is high.
- zmx deliberately has **no tabs/splits/panes**. Do not push layout responsibilities down into
  zmx; that's the app's job and the boundary is correct.

---

## 5. Grounded brainstorming ideas

Each: **What / Why / How (real files) / Risk / Effort / Decision needed.** Ordered roughly
smallest-safest first. Effort is rough: S = days, M = a week-ish, L = multi-week.

### Idea A — Semantic agent-lifecycle state (blocked / working / done / idle)

- **What:** A per-pane *agent* state distinct from `SessionRuntimeStatus` (which stays
  process-health). Four states with a **human-review axis**: Done = finished-unreviewed,
  Idle = finished-reviewed. This is herdr's single best product idea.
- **Why:** For a worktree-per-agent app, "who is blocked on me vs. waiting for my review" is
  the highest-value glance on the sidebar. Process health can't express it.
- **How:**
  - Heuristic source: extend the `terminalActivity` path (`PaneRuntimeEvent`) — quiet-after-busy
    → Done-candidate; prompt-for-input pattern → Blocked-candidate.
  - Authoritative source (optional): Claude Code hook → §3.1 socket → `pane.report_agent`.
  - State lands somewhere observable by the sidebar reader.
- **Decision needed (CLAUDE.md atom-boundary rule):** Does this earn a **new atom**
  (`AgentLifecycleAtom`), a **derived** reader over existing facts, or a property on
  `SessionRuntimeAtom`? Strong prior: **not** a property on `SessionRuntimeAtom` — its job is
  process health; semantic agent state is a different reason-to-change. Likely a new atom or a
  derived. *This is the first thing to settle with Shravan.*
- **Risk:** Heuristic false positives (an agent quietly thinking looks "Done"); review-state
  persistence semantics; scope-creep into per-agent config. Mitigate by shipping heuristic as
  "best-effort, hook overrides," and keeping the state machine tiny.
- **Effort:** M (heuristic) / +S (hook path).

### Idea B — Local control socket (`events.subscribe` read-only first)

- **What:** An AF_UNIX listener that speaks newline-delimited JSON-RPC, starting with
  **read-only** `events.subscribe` (no mutation verbs).
- **Why:** Unlocks external observation (and our own integration tests) with near-zero blast
  radius. Proves the transport before any write verb exists.
- **How:** New `App/`-level server; reuse `RPCRouter`'s dispatch/error-code shape; subscribe a
  client to `PaneRuntimeEventBus.shared` and stream envelopes as JSON lines. Socket path under
  `~/.agentstudio/`, perms `0700`-dir like zmx's `0750`.
- **Risk:** Even read-only leaks workspace structure to anything on the machine → socket file
  perms + per-user dir. Backpressure: bus uses `bufferingNewest(256)`; slow clients drop, not
  block.
- **Effort:** S–M.
- **Decision needed:** "external control plane" = surface-area expansion → confirm before build.

### Idea C — Mutating control verbs over the socket

- **What:** Add write methods that translate JSON-RPC → `PaneActionCommand` / `RuntimeCommand`,
  through the existing validators.
- **Why:** This is what makes agents able to *orchestrate* (split panes, send text, open
  worktrees) — herdr's core capability.
- **How:** Thin method→command map (table in §3.1). **Every** call goes through
  `WorkspaceCommandValidator`/`DrawerCommandValidator` — same gate as the UI.
- **Risk:** **Biggest security item in this doc.** Anything on the machine could drive the
  workspace. Needs: socket perms, possibly a capability token in `AGENTSTUDIO_CONTROL_SOCKET`,
  and an allowlist of methods. Also re-entrancy: external mutations interleaving with UI
  mutations — the validators + main-actor serialization are the defense, verify under load.
- **Effort:** M.
- **Decision needed:** yes — this is the load-bearing architecture conversation.

### Idea D — zmx output-tap for background heuristics

- **What:** Use `zmx tail`/`history` (or an extended zmx event channel, §4) as the output source
  for Idea A on **non-focused** panes.
- **Why:** Without this, agent-state detection only works for the pane you're looking at —
  useless for "watch my herd."
- **How:** `ZmxBackend` gains read/tail calls; a runtime actor consumes them and emits
  heuristic `terminalActivity`/agent-state facts. Prefer the **extend-zmx** route (structured
  events) over scraping text if we're investing.
- **Risk:** N panes × continuous `tail` = N subprocesses/streams → resource cost; parsing ANSI
  for state is fragile (the case *for* extending zmx). Throttle; only tap backgrounded panes
  that have agents.
- **Effort:** M (scrape) / L (extend zmx, but far more robust).

### Idea E — Focus-aware notifications

- **What:** Fire notifications for **background** agent transitions (esp. → Blocked); suppress
  for the focused pane. herdr does exactly this ("tab-aware suppression").
- **Why:** Notifications are only useful for what you *aren't* looking at.
- **How:** Combine Idea A's state transitions + `WorkspaceFocusDerived` + the existing
  `agentNotificationRequested` pane fact + the `InboxNotification` feature. The suppression rule
  is a behavioral constant → **`AppPolicies`** (per CLAUDE.md: changes state/behavior, not just
  visuals).
- **Risk:** Notification spam if heuristic is noisy → gate on Blocked/Done only, debounce.
- **Effort:** S (once A exists).

### Idea F — MCP server / skill for agent-driven orchestration

- **What:** An MCP server (or Claude Code skill) in front of the §3.1 socket so Claude agents
  orchestrate panes via tools.
- **Why:** Our users already drive Claude; tools are a more natural surface than a raw socket.
  Mirrors herdr's MCP + `SKILL.md` ecosystem.
- **How:** Depends on C. MCP tools = thin wrappers over the socket methods.
- **Risk:** Largest surface; do last. Inherits all of C's security concerns plus prompt-driven
  misuse.
- **Effort:** M–L. **Decision needed:** yes.

### Idea G — Detached helper agents via `zmx run -d` + `wait`

- **What:** "Spawn a helper agent in a detached session, await completion" as a first-class op.
- **Why:** herdr's `pane split → run claude → wait agent-status done` workflow, but persistence-
  backed and survivable across app restart.
- **How:** `ZmxBackend` adds `run -d`/`wait`; expose via Idea C method (e.g. `agent.spawn`).
- **Risk:** Orphaned detached sessions accumulating; need lifecycle/GC tied to workspace.
- **Effort:** M (depends on C + zmx verb verification).

### Idea H — Update/handoff resilience

- **What:** A deliberate story for "update Agent Studio (and/or bump the zmx submodule) without
  killing every running agent."
- **Why:** herdr ships experimental `update --handoff` (move live panes incl. dev servers to a
  new server). Our analogue is harder: **zmx itself warns that IPC-version changes across zmx
  upgrades kill existing sessions.** So bumping the vendored zmx is a session-killer unless
  managed.
- **How:** (a) Pin/gate zmx IPC compatibility and detect version skew before reattach; (b) drain
  /warn users before a zmx-affecting update; (c) long-term, an explicit handoff protocol in our
  fork.
- **Risk:** Silent agent loss on update = worst-possible UX. Treat as a correctness requirement
  the day zmx gets bumped, not a nice-to-have.
- **Effort:** M–L. Mostly process + a version check now (S), full handoff later (L).

---

## 6. Risk register (consolidated)

| # | Risk | Where | Severity | Mitigation |
|---|---|---|---|---|
| R1 | Control socket = local privilege/automation surface; any process can drive/observe the workspace | Ideas B/C/F | **High** | Per-user dir perms (`0700`), capability token in env, read-only first, method allowlist, validator-gated mutations |
| R2 | zmx IPC version skew kills live sessions on upgrade | Idea H, submodule bumps | **High** | Version check before reattach; drain/warn; eventual handoff protocol |
| R3 | Heuristic agent-state false positives ("thinking" looks "Done"; prompt looks "Blocked") | Ideas A/D | Medium | Hook override is authoritative; conservative transitions; debounce; "best-effort" framing |
| R4 | Unix socket path length ≤ ~103 chars (zmx) | session IDs, new socket | Medium | Already tracked (`ZmxAttachDiagnostics`); keep IDs short; short socket dir |
| R5 | N background `zmx tail` streams = resource cost | Idea D | Medium | Tap only agent-bearing background panes; throttle; prefer structured zmx events |
| R6 | ANSI scraping for state is brittle | Idea D | Medium | Extend zmx with structured state events instead of parsing text |
| R7 | External mutations interleaving with UI mutations (re-entrancy) | Idea C | Medium | Main-actor serialization + validators; load-test |
| R8 | **Architecture-boundary governance** — new atom/store/event-type/coordinator-responsibility/external-command-surface all require Shravan's sign-off per CLAUDE.md | Ideas A/B/C/F/G | Process | This doc *is* the pre-work; do not implement boundary changes before the conversation |
| R9 | Notification spam | Idea E | Low | Gate on Blocked/Done, debounce, focus-aware suppression |
| R10 | Scope creep toward "rebuild herdr" | All | Medium | Stay native-app-first; only expose, don't re-implement multiplexing; zmx stays persistence-only |

---

## 7. Suggested sequencing (smallest safe first)

1. **Settle Idea A's home** (new atom vs derived vs property) with Shravan — gates everything
   agent-state. *Pure conversation, no code.*
2. **Idea B** — read-only `events.subscribe` socket. Smallest blast radius, proves transport,
   immediately useful for integration tests.
3. **Idea A heuristic** using existing `terminalActivity`, focused panes only.
4. **Idea D** — background output source (start with `zmx tail`; evaluate extending the fork).
5. **Idea E** — focus-aware notifications (cheap once A exists).
6. **Idea C** — mutating verbs (the big security/architecture conversation).
7. **Ideas F/G/H** — MCP/skill, detached helpers, update handoff.

R8 means steps 1 and 6 are **conversations before code**.

---

## 8. Open questions for Shravan

1. **Agent-state home:** new `AgentLifecycleAtom`, a derived reader, or a property on
   `SessionRuntimeAtom`? (Prior: not the last.)
2. **Do we want an external control plane at all**, or keep Agent Studio closed and pursue only
   internal agent-awareness (Ideas A/D/E)? This is the fork in the road.
3. **Extend the zmx fork** (structured agent-state/control channel) vs. **stay CLI-only** and
   scrape `tail`/`history`? Extending is more robust and upstreamable but is real Rust work.
4. **Hooks vs heuristics priority:** ship heuristic-only first, or invest in the Claude Code
   hook + installer immediately for accuracy?
5. **MCP vs raw socket** as the eventual agent-facing surface (if any).

---

## 9. References

- herdr — <https://github.com/ogulcancelik/herdr> (README, `SKILL.md`)
- awesome-herdr ecosystem — <https://github.com/yigitkonur/awesome-herdr>
- herdr on lib.rs — <https://lib.rs/crates/herdr>
- zmx upstream — <https://github.com/neurosnap/zmx>
- zmx fork (vendored) — <https://github.com/ShravanSunder/zmx>
- Internal: `ZmxBackend.swift`, `SessionRuntime.swift`, `SessionRuntimeAtom.swift`,
  `EventBus.swift`, `EventChannels.swift`, `RuntimeEnvelopeCore.swift`, `PaneRuntimeEvent.swift`,
  `PaneActionCommand.swift`, `RuntimeCommand.swift`, `RPCRouter.swift`,
  `TerminalRestoreRuntime.swift`, `WorkspaceFocusDerived.swift`
