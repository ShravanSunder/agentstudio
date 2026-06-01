# Agent Control Surface — contested decisions to lock before re-planning

> **Status: DECISIONS NEEDED (2026-05-30).** This doc holds the contested calls flagged by two independent adversarial reviews of `docs/plans/2026-05-30-agent-pane-ipc.md`. Pick a side on each before the plan is rewritten. Markers: ★ = my recommendation.

## How to use this doc

For each decision: read the options, pick one (override the recommendation if you disagree), and write the chosen letter inline. Then I'll rewrite the plan against the verified codebase using your choices.

Decisions are ordered so earlier picks constrain later ones — go top-to-bottom.

---

## D1. Which socket is the canonical agent surface?

**The call.** Reviews showed the original plan's hybrid ("two sockets, both speak overlapping verbs, Tier 1 proxies to Tier 2") gives both sides' downsides without committing to either.

### Option A — Single AgentStudio.app socket (Tier 1 fronts everything) ★

One Unix socket at `~/Library/Application Support/AgentStudio/agentctl.sock`. Every verb — `list_panes`, `send_keys`, `capture_pane`, `pipe_pane`, `new_pane`, `close_pane`, `resize_pane` — terminates here. For terminal IO, the server holds a **long-lived per-pane upstream connection to zmx** and multiplexes agent traffic over it (FIFO per agent).

- ✅ One socket for agents to learn.
- ✅ Within one agent, `send_keys` ordering is guaranteed FIFO (one upstream connection).
- ✅ Audit/auth/policy all enforce at one boundary.
- ✅ Bridge/webview verbs and terminal verbs live in the same protocol — no kind-based routing on the agent side.
- ❌ Agent surface dies with the GUI. If the user quits AgentStudio, headless agents lose access (they can still attach to zmx directly, but that's now an escape hatch, not a documented path).
- ❌ GUI becomes the chokepoint. Latency = AgentStudio dispatch hop + zmx hop. For 50KB paste: ~one round-trip if chunked once.
- ❌ Concurrent agents on the same pane: server must serialize their `send_keys` into the single upstream queue. Documented contract: per-agent FIFO, cross-agent unspecified.

### Option B — zmx socket is canonical; AgentStudio is metadata-only

Two sockets but with a clean responsibility split. AgentStudio.app socket only knows workspace shape: `list_panes`, `new_pane`, `close_pane`, `resize_pane`. All per-session IO (`send_keys`, `capture_pane`, `pipe_pane`) is the zmx socket's job — agents talk to zmx directly via the session name returned by `list_panes`.

- ✅ Headless agents work without the GUI for the most-used verbs (capture, send-keys, pipe).
- ✅ zmx is already the persistence boundary — putting IO there is conceptually cleaner.
- ✅ Less proxy overhead — no double-hop for streaming.
- ❌ Agents now must speak two protocols. Tooling (the CLI shim) hides this but agents using the socket directly don't get that.
- ❌ zmx session names leak into the agent vocabulary (we can't keep `Pane.id` as the exclusive external handle for IO verbs).
- ❌ Auth/audit must live in zmx for IO and in AgentStudio for workspace — double the policy surface.
- ❌ Bridge/webview have no zmx socket — capture/send for those kinds has nowhere to go in this model. We'd add a third surface or refuse those verbs entirely.

### Option C — Status quo hybrid (do not pick)

Listed only for completeness. Both reviews rejected this. Two sockets, overlapping verbs, agents may pick either. Doubled failure modes.

### Tradeoff summary

| Concern | A (recommended) | B | C |
|---------|-----------------|---|---|
| Sockets agents must learn | 1 | 2 | 2 |
| Headless agent support | No | Yes | Mixed |
| Auth surface | Single | Double | Double |
| Bridge/webview path | Same protocol | Needs third surface | Mixed |
| `send_keys` ordering | FIFO per agent | FIFO per agent (direct to zmx) | Race |
| Streaming latency | +1 hop | Direct | Mixed |

**Rationale for ★A.** Agent Studio is a GUI product. "Agent surface works only when the GUI runs" is acceptable — that's tmux's model too in practice (you need a tmux server running). The "headless agent" benefit of B is real but smaller than the cost of teaching agents two protocols and doubling the policy surface. The clean single-boundary story is worth the GUI chokepoint.

**Your pick: ____**

---

## D2. v1 verb scope

**The call.** Each verb has a different validator-design cost and a different failure-mode profile. Shipping all of them in v1 maximizes blast radius. Shipping only some reduces it.

### Option A — Read-only

`list_panes`, `capture_pane`. Nothing else.

- ✅ Lowest risk surface. Cannot affect user's panes.
- ✅ No validator work, no undo questions.
- ❌ Doesn't enable the headline use case ("agent drives a CLI").
- ❌ Almost certainly insufficient to justify shipping a new socket at all.

### Option B — Read + input (no creation/close) ★

`list_panes`, `capture_pane`, `pipe_pane`, `send_keys`. Optionally `resize_pane` (terminal-only, idempotent).

- ✅ Covers the 90% agent workflow: drive a TUI, watch a build, read prompts.
- ✅ No `new_pane` validator design needed (the verb→command mapping is the hardest part of v1).
- ✅ No `close_pane` undo-policy debate to resolve (D3 deferred to v2).
- ✅ Bridge/webview can be silently terminal-only (`unsupported_pane_kind` returned) without losing real value.
- ❌ Agents can't prep their own workspace. Workaround: user creates the pane, agent drives it.

### Option C — Full surface

All of B plus `new_pane`, `close_pane`. The original plan's scope.

- ✅ Agents can spin up their own workspace.
- ❌ Requires resolving D3 (undo policy) for v1.
- ❌ Requires designing the verb→command shim that bridges plan-shaped requests (`{kind, cwd, command}`) to the actual three different `PaneActionCommand` cases.
- ❌ Drawer/backgrounded pane close requires multi-command dispatch (`closePane | removeDrawerPane | purgeOrphanedPane`). Verifier #2 found this; non-trivial.
- ❌ Concurrent creation/close races against user actions need ordering guarantees vs the action coordinator.

**Rationale for ★B.** The risk/value curve flattens hard after `send_keys` + `pipe_pane`. Creation can ship v2 once we know what agents actually do with v1, which informs whether `new_pane` should be terminal-only or grow a kind matrix. Shipping less means a cleaner audit of how the surface is used before adding mutation power.

**Your pick: ____**

---

## D3. Auth model for v1

**The call.** Original plan said "tmux-equivalent — any UID-process can do anything." Both reviewers flagged this as wrong framing for an AI-agent product. They differ on what to add.

### Option A — 0700 socket only (no audit, no tokens)

Same as the original plan. Match tmux.

- ✅ Trivial to ship. Zero new code.
- ❌ No forensics. When an agent does something the user didn't expect, "what did Claude type at 3am" is unanswerable.
- ❌ For an AI-agent product, the threat model is fundamentally different from a CLI multiplexer.

### Option B — 0700 socket + per-request audit log ★

Same access control as A. Every mutation (`send_keys`, plus any of `new_pane/close_pane/resize_pane` if D2 lands on C) writes to a per-workspace JSONL audit file. Capped retention (e.g., last 10k entries or 30d, whichever first).

- ✅ Forensics for free. Grep-able transcript of every agent action.
- ✅ No UX surface needed (no token issuance flow).
- ✅ Audit transcript also serves as a debug aid during plan/implementation phases — "what did the agent actually send?"
- ✅ Retrofits naturally to bearer tokens in v2 (request envelope reserves `token` field, audit log gains an `agentId`).
- ❌ Disk writes per `send_keys` — at high frequencies (a benchmark spamming keys) this is real I/O. Buffered, async, capped.
- ❌ Privacy surface: audit log contains everything agents typed. Lives on disk. Plain text. Mitigation: mode-0600 file, in `~/Library/Application Support/AgentStudio/audit/`, opt-out flag exists.

### Option C — 0700 socket + audit + bearer tokens (v1)

Above plus optional `token` field in the request envelope, validated against a per-agent registry the GUI populates on agent spawn. No-token requests fall back to full access (CLI shim continues working).

- ✅ Defense in depth — a misbehaving agent with a token scoped to pane X can't reach pane Y if we add scope later.
- ✅ Audit log now has stable agent provenance.
- ❌ Requires designing the issuance mechanism. Even the cheap version (env var passed at agent spawn) needs a UI to manage active tokens, revoke, list.
- ❌ Without scopes, tokens are just identifiers — the actual access control is still 0700. Cosmetic security in v1 unless we ship scopes too.
- ❌ Token UX is something to design with care; rushing it in v1 commits to a shape we may regret.

### Tradeoff summary

| Concern | A | B (recommended) | C |
|---------|---|-----------------|---|
| New code | None | Audit logger | Audit + token registry + UX |
| Forensics | None | Yes | Yes |
| Real access control | UID only | UID only | UID only (until scopes ship) |
| v2 migration cost | Add audit + tokens | Add tokens | Add scopes |

**Rationale for ★B.** Audit is the cheap, high-value addition; tokens without scopes are theater. Defer C to v2 when we have evidence about what scopes agents actually need.

**Your pick: ____**

---

## D4. AgentControlServer placement

**The call.** Plan placed it in `Core/AgentIPC/`. Reviewer #2 caught that this requires `Core/` to import `Features/Terminal/Restore/` (where `zmxSessionId(for:store:)` lives), violating the project's import rule.

### Option A — `Core/AgentIPC/`

Lift `zmxSessionId(for:store:)` and the surrounding session-name derivation logic from `Features/Terminal/Restore/TerminalRestoreRuntime` into `Core/`.

- ✅ Server is in `Core/`, matches the original plan.
- ❌ Forces a Terminal-feature concern into Core. The session-name derivation knows about repo stable keys, worktree stable keys, drawer parent relationships — these are terminal-pane-specific. They don't belong in `Core/` per the boundary rules.
- ❌ Sets precedent for future cross-feature concerns to dump shared bits into Core.

### Option B — `App/AgentIPC/` ★

Place server alongside `App/Coordination/PaneCoordinator`. `App/` is allowed to import `Core/` and `Features/` by the import rules. The server composes across features and core, which is the definition of an `App/`-level composition concern.

- ✅ Respects the import rule as-written.
- ✅ AgentControlServer fundamentally orchestrates across Terminal, Bridge, Webview, and Core state — it's a composition concern.
- ✅ Future per-feature handlers (`captureBridgePane`, `sendKeysToTerminalPane`) can live in their features and be wired from `App/`.
- ❌ Server's protocol types might want to be in `Core/` so a test target can build them without `App/`. Fix: split — protocol types/codables in `Core/AgentIPCProtocol/`, server (the listener, dispatcher, handlers) in `App/AgentIPC/`.

**Rationale for ★B.** The agent control surface is *exactly* the kind of cross-feature orchestration that motivated the App/Core/Features split in the first place. Putting it in Core inverts the boundary.

**Your pick: ____**

---

## D5. External `Pane.id` shape — only matters if D2 ≥ B

**The call.** Today `Pane.id` is a UUID (36 chars). Original plan flagged "worth a separate plan." Both reviewers said state the blast radius up front.

### Option A — Use UUID as-is

Agents type `agentctl send-keys -t 018f3a8b-1c2d-7d4e-9f1a-1234567890ab ...`.

- ✅ Zero new code. Existing IDs already stable.
- ❌ Painful to type, painful to read in logs.
- ❌ Doesn't match the `%12` ergonomics tmux-trained agents expect.

### Option B — Short alias (`p_<last8hex>`) mapped at the IPC layer ★

Server maintains a `[String: UUID]` map of aliases → real IDs, rebuilt on startup. `list_panes` returns both; verbs accept either.

- ✅ Friendly for shell/agent interaction.
- ✅ Zero changes to persistence, runtime, or the rest of the app.
- ✅ Collision handling: detect on rebuild, fall back to longer prefix for collisions (10-hex, 12-hex). Unlikely with UUIDv7 distribution within a single workspace.
- ❌ Alias is *not* persistence-stable; a UUID minted later could in theory collide with an alias issued earlier. Mitigated by rebuild-on-collision-expand. Document the lifetime.

### Option C — Migrate `Pane.id` to short ID throughout (do not pick)

102 files reference `Pane.id`. Persistence schema migration, validator changes, surface registry keys, runtime status keys. Months of work, no upside over B.

**Rationale for ★B.** Cheap, isolated change. Doesn't touch persistence. The "alias lifetime" caveat is small in practice and easy to document.

**Your pick: ____**

---

## D6. Pane-identity stability claim

**The call.** Reviewer #2 verified that `WorkspaceStore.restore()` quarantines corrupt files and boots with empty state. So `Pane.id` is *not* stable in that case — and the original plan asserted otherwise.

### Option A — Document the gap, accept it ★

Promise: `Pane.id` is stable across normal app relaunches, detach/reattach, and clean crashes. Document explicitly that workspace-store corruption is the one case where IDs can churn (the existing recovery is "quarantine and start empty"; agents see all their pane handles return `unknown_pane` after this).

- ✅ No new code. Existing recovery is correct for the user; agents just need to know.
- ✅ Honest contract.
- ❌ Agents holding long-lived handles must handle `unknown_pane` and re-list.

### Option B — Add recovery hooks

On workspace quarantine, the AgentControlServer broadcasts an event (`{"event": "workspace_reset"}`) to all open `pipe_pane` subscribers and any future "control plane" subscribers. Agents can re-list and rebuild their state.

- ✅ Agents get a clear signal vs silent failure.
- ❌ Requires implementing a control-plane subscription channel separate from `pipe_pane`. New scope.
- ❌ Workspace quarantine is rare (it requires actual disk corruption). May be over-engineering.

**Rationale for ★A.** Document it, defer reactive recovery until we see real user reports of agents getting confused. Less code, honest contract.

**Your pick: ____**

---

## D7. Bridge/Webview capture in v1

**The call.** Original plan promised `capture_pane` for bridge/webview "returns DOM text snapshot via existing webview surface APIs." Both reviewers verified: no such API exists.

### Option A — Return `unsupported_pane_kind` for non-terminal panes in v1 ★

`capture_pane` works only for `kind == "terminal"`. Bridge/webview return a typed error. `list_panes` continues to include all kinds (with `kind` field), so agents can filter.

- ✅ Honest. No fabricated functionality.
- ✅ Leaves design space for bridge/webview capture as a separate v2 feature with its own contract.
- ❌ Agents driving a multi-pane workflow can't unify "read state" across pane kinds.

### Option B — Add minimal `evaluateJavaScript("document.body.innerText")` for webview

Bridge gets DOM text via the existing bridge state-snapshot infra (`capture: { state in ... }`). Webview gets a thin `evaluateJavaScript` wrapper.

- ✅ Unified verb across kinds.
- ❌ New feature in v1, with its own design questions (shadow DOM, iframes, scroll position, timing).
- ❌ Webview JS execution is a potential security/policy surface — needs review.

**Rationale for ★A.** Stay honest. Bridge/webview capture is a real feature with non-trivial design; don't shoehorn it in v1 as a side concern.

**Your pick: ____**

---

## Decisions summary (fill in)

| Decision | Recommendation | Your pick |
|----------|---------------|-----------|
| D1. Canonical socket | A (single AgentStudio.app socket, proxies to zmx) | _____ |
| D2. v1 verb scope | B (read + input, no creation/close) | _____ |
| D3. Auth v1 | B (0700 + audit log, no tokens yet) | _____ |
| D4. Server placement | B (App/AgentIPC + Core/AgentIPCProtocol for types) | _____ |
| D5. External `Pane.id` shape | B (short alias `p_<last8hex>`, map at IPC) | _____ |
| D6. Identity stability claim | A (document the quarantine gap) | _____ |
| D7. Bridge/webview capture v1 | A (terminal-only, return `unsupported_pane_kind` for others) | _____ |

## Notes & references

- Original plan: `docs/plans/2026-05-30-agent-pane-ipc.md`
- Companion design doc: `docs/architecture/remote_zmx_architecture_ideas.md`
- Reviews summary: in conversation; key fabrications verified via direct file reads of `Core/Actions/PaneActionCommand.swift`, `Core/State/MainActor/Atoms/SessionRuntimeAtom.swift`, `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`.

## What happens after these are picked

Once you fill in the seven picks, I rewrite `docs/plans/2026-05-30-agent-pane-ipc.md` against the verified codebase:
- Verb shapes mapped to real `PaneActionCommand` cases (or v1-scoped down per D2).
- Server placement and types-split per D4.
- Pane identity contract per D5/D6.
- Auth/audit per D3.
- Bridge/webview scoped per D7.
- The "pipe-pane rides on the event bus" claim removed entirely (verified factually wrong regardless of decisions here — `PaneRuntimeEvent` has no `output(bytes:)` case).
- Phases re-sequenced to match v1 scope.

The rewritten plan goes through one more review (lighter — verifying it tracks the decisions and the codebase, not adversarial) before any code.
