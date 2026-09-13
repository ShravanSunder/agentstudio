# Agent IPC v2 and Agent Package — User Requirements (draft)

Date: 2026-09-12. Extracted in a pathfinding session with the product owner on
branch `ipc-improvements`. Authority state is per row; only `authorized` rows
are normative-eligible for `spec-design`. Decisions and their rationale live
in [decision-record.md](decision-record.md).

Status: **goal boundary confirmed by the owner on 2026-09-12** ("ok lets go
through orchestrate design"), with the amendments in decision-record.md J
(Swift-owned, JSON-RPC schema, CLI now / Rust CLI later) and K (spool as the
collector; no message lost across restart is a must).

## Who this is for

| Class | Distinguishing behavior | Outcome that matters |
| --- | --- | --- |
| C1 Developer running agents in Agent Studio panes | starts several Claude/Codex/Cursor turns, leaves panes, returns later | knows what each agent is doing and when one needs them, without visiting every pane |
| C2 Agent running inside a pane (downstream agent consumer of the CLI/skill) | executes a skill; can only read its environment and run a CLI | can identify its pane, open files in the app, report status, send messages, with a herdr-simple DX |
| C3 Provider package installer/operator | installs and upgrades the Agent Studio agent package on a machine | one install registers the right native hooks/skills/plugins per provider without hand-editing config |
| C4 Agent Studio maintainers | keep `AppCommand`/`ipcSpec` exhaustive and the IPC boundary lint-clean | IPC v2 does not create a second command catalog or leak renderer/daemon internals |
| S1 Future ACP / codex-router integration (stakeholder, no journey) | later slices connect ACP-hosted agents and agent-to-agent messaging | this slice's contracts remain additive for them |

Out of scope (deliberately): users of the retired Inbox; users of other
terminals not running Agent Studio; remote/multi-machine operators.

## Evidence anchors used by the rows

- E-IPC: this repo's IPC census (2026-09-12) — 42 registered methods; 23/125
  `AppCommand`s headless; a normal pane shell receives no Agent Studio
  identity (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:404-446`);
  `PaneAgentLaunchOwner` has zero callers; one `eventBroker.publish` site
  (`AgentStudioAppIPCServer+AuthenticatedRouting.swift:376`).
- E-HERDR: herdr @ a5d5f6f6 — `HERDR_ENV`/`HERDR_PANE_ID`/`HERDR_SOCKET_PATH`
  injection, `skills/herdr/SKILL.md` guardrail, per-source seq and session
  fencing in `src/terminal/state.rs`, one status authority per pane.
- E-ORCA / E-GHOSTEX: orca hook scripts POST hook stdin JSON to a persisted
  local endpoint; `orca file open` resolves cwd → worktree; Ghostex
  `gxserver/src/agent-hooks.ts:58-153` writes native hook files for 12 CLIs.
- E-HOOKS: Claude Code hooks reference (Notification matchers, Stop,
  SubagentStop, `session_id`/`transcript_path`/`cwd`); Cursor hooks reference
  (no idle/permission event; `afterAgentResponse`, `stop`; CLI applicability
  undocumented beyond `workspaceOpen`); Codex `hooks.json`, legacy `notify`,
  `[tui] notification_method = "osc9"`; pi extension API; OpenCode plugin
  events and herdr's OpenCode plugin mapping.
- E-SPEC: 2026-08-03 Agent Sessions family (latest authority, design-only) and
  2026-08-21 Inbox Retirement (shipped structurally: Inbox boot functions have
  zero callers, all Inbox commands `.notPresented` / `.notExposed`).
- E-OWNER: owner statements in this session (quoted in the decision record).

## Rows

| ID | Class | Need or outcome | Evidence | Authority | Priority | Assigner |
| --- | --- | --- | --- | --- | --- | --- |
| U1 | C2 | An agent in a pane can identify its own pane and workspace and reach Agent Studio using only its environment (ids, socket path, pane-scoped token). | E-IPC (nothing injected today), E-HERDR, E-OWNER (A) | authorized | must | owner |
| U2 | C2, C1 | An agent can open a file (path, line) in Agent Studio placed relative to its own pane — default the caller's drawer — instead of printing a link. **This slice designs only the IPC contract at the boundary (method, params, results, errors) as a reserved, unadvertised contract; the internals are a separate later piece of work (decisions P, V).** | E-IPC (no `file.*` method; `showViewer` unexposed), E-ORCA, E-OWNER (C, P, V) | authorized (contract only) | must (contract) / deferred (internals) | owner |
| U3 | C2 | An agent can drive Agent Studio through a curated, agent-friendly semantic API plus generic headless command execution; UI-interactive verbs are not exposed in stable/beta. In DEBUG mode the full command spec — every `AppCommand`, with explicit typed arguments — is callable from IPC with good DX (decision Z). | E-IPC (83 verbs rejected today), E-OWNER (B, S, Z) | authorized | must | owner |
| U23 | C2 (test agents), C4 | Running and controlling a debug app is zero-ceremony: a small model (Haiku/Luna class) given only the skill can discover the running debug app and drive it — no tokens, socket paths, or flags to assemble; repeated CLI calls authenticate without manual steps. | E-OWNER (Y) | authorized | must | owner |
| U4 | C2, C4 | Every exposed IPC argument contract is redesigned to be agent-friendly; the current phase-1 shapes are not carried forward as-is. | E-IPC (zero argument-bearing commands executable), E-OWNER (B) | authorized | must | owner |
| U5 | C3 | One installable Agent Studio package registers, per provider, the provider's native hooks / skill / plugin using that provider's own lifecycle. Round 1: Claude Code, Codex CLI, Cursor CLI. | E-GHOSTEX, E-HOOKS, E-OWNER (D1, D2) | authorized | must | owner |
| U6 | C3 | Round 2 adds pi and OpenCode through the same package. | E-HOOKS, E-OWNER (D1) | authorized | should | owner |
| U7 | C1 | Agent Studio learns each agent's lifecycle from provider-native events: session start/end, turn start/done, needs-you (permission, question, elicitation), tool use, subagent activity. | E-HOOKS, E-OWNER (D3) | authorized | must | owner |
| U8 | C2, C1 | An agent can send any message to Agent Studio; the message is stored durably and visible in Sessions. | E-OWNER (D4) | authorized | must | owner |
| U9 | C1 | Message text is never exported to OTLP/JSONL telemetry. | E-OWNER (D4), existing scrub rule in CLAUDE.md | authorized | must | owner |
| U10 | C1 | macOS notification banners for agent messages/attention can be enabled later. | E-OWNER (D4) | authorized | could | owner |
| U11 | C1 | Agent Studio can talk to the agent in a pane (bidirectional), so the user can steer agents programmatically. **Deferred to round 2 / PR2 by decision N (2026-09-13); not part of this slice.** | E-OWNER (I, N) | authorized (deferred) | should | owner |
| U12 | C1 | Status honesty: each fact carries whether the provider reported it, the agent asserted it, or it was estimated; typed terminal signals (OSC 9, title, progress) count as provider-authored; screen manifests are not used in this slice. | E-SPEC (08-03 labels), E-HOOKS (Codex OSC 9), E-OWNER (E) | authorized | must | owner |
| U13 | C1 | Needs-you is observed and shown in this slice; each needs-you carries a request id so answering from Agent Studio can be added later without redesign. | E-OWNER (H) | authorized | must | owner |
| U14 | C1 | Sessions state is rebuildable after restart; agent messages and seen/attention state survive restart; agent messages and deliberate agent reports emitted while the app is down are never lost (the CLI spools notifications, never commands). Hook lifecycle state facts emitted while the app is down are not collected in round 1 (decision X). | E-ORCA (spool), E-OWNER (F, K, U, X) | authorized | must | owner |
| U15 | C1, C4 | Inbox stays retired; Sessions owns message/attention delivery; this slice delivers the capability (ingest, store, query) and the Sessions pane UI follows in a later slice. | E-SPEC (retirement shipped), E-OWNER (G) | authorized | must | owner |
| U16 | C2 | Self-pane actions need no grant; cross-pane or workspace-wide actions require an explicit grant, and in round 1 no grant is issuable — such requests fail with a stable missing-grant outcome naming the scope. Same-UID trust is the accepted boundary. | E-SPEC (08-03 trust boundary), E-OWNER (A, M) | authorized | must | owner |
| U17 | S1 | The internal fact vocabulary is shaped so an ACP-connected agent later produces the same facts without translation. | agent proposal | advisory | should | agent (needs owner) |
| U18 | S1 | Agent-to-agent messaging (codex-router libraries, ACP) is a secondary phase and not part of this slice. | E-OWNER (I) | authorized (non-goal) | — | owner |
| U19 | C2, C4 | IPC v2 is JSON-RPC 2.0 with a discoverable schema (method list with typed params and results, MCP-like) so the same surface can back an MCP adapter or SDK later; the CLI is generated from that schema. | E-OWNER (J), ipc.md "MCP should be an adapter over the same registry" | authorized | must | owner |
| U20 | C2 | The `agentstudio` CLI exists in this slice, generated from the catalog (decision J, reaffirmed by R after O was superseded); an SDK and a Rust CLI to codex-router standards are later separate work. | E-OWNER (J, O superseded, R) | authorized | must (CLI) / could (SDK, Rust CLI) | owner |
| U22 | C2 | The surface a model touches costs few tokens: plain scalar arguments (no JSON), no hand-typed identifiers, a closed tiny report vocabulary, one-line replies. | E-OWNER (Q) | authorized | must | owner |
| U21 | C1 | No agent message or deliberate agent report is lost across an app restart: the CLI spools these notifications while the app is down and the app admits them on launch marked as late. Commands (controls, queries, auth) are never buffered offline (decisions K, U, X). | E-OWNER (K, U, X), E-ORCA | authorized | must | owner |

## User-job sequence inputs (C1, C2)

- C2: agent starts in a pane → reads its environment → runs the skill's
  guard → opens a file in its drawer / reports status / sends a message →
  keeps working. Pain today: none of this is possible; the agent prints paths
  and the user copies them (U1, U2, U3, U8).
- C1: starts three agents → leaves → an agent asks a question → Agent Studio
  records needs-you with a request id → user returns, sees it in Sessions,
  answers in the pane (U7, U13); later slices let them answer from Sessions.
- C3: runs one install → each provider's config gains the Agent Studio hooks
  → uninstall removes exactly those entries (U5, U6).

## Goal boundary (proposed — owner to confirm or correct)

```text
goal            agents inside Agent Studio panes get a first-class, agent-
                friendly IPC (v2) and a cross-provider package so Agent Studio
                knows what each agent is doing and agents can act in the app
affected        C1 developer, C2 agent, C3 installer, C4 maintainers; S1 future
                ACP/codex-router
reuse           phase-1 socket, JSON-RPC, principal/grant model, AppCommand +
                ipcSpec catalog, Contract 7 terminal admission, local.sqlite,
                08-03 evidence labels and state contract
missing         pane identity in env; curated semantic methods (session
                bind/report/message/query); agent-friendly argument contracts
                (typed catalog); the Swift `agentstudio` CLI compiled from
                that catalog; hook/skill package whose hooks call the CLI;
                message and needs-you ingress with durable store; the spool
may change      Sources/AgentStudioAppIPC, AgentStudioProgrammaticControl,
                AgentStudioIPCClientCore (retained as the client library) and
                the AgentStudioIPCClient executable (reused as `agentstudio`;
                phase-1 verb mapping and the `agentstudio-ipc` product name
                retired), App/IPCComposition, App/PaneAgents (fd helper
                retired), Terminal env injection, Core command catalog
                (ipcSpec), a new Sessions ingest/store owner, a new
                agent-package repo folder
must not change Inbox sources/rows (stay dormant), Ghostty/zmx vendors,
                Bridge product behavior, OTLP scrub rules
non-goals       Sessions pane UI, ACP client / chat pane, agent-to-agent
                messaging, macOS banners, screen manifests, transcript storage,
                answer-through replies, Inbox revival, remote/multi-machine;
                PR2 (decision N): Studio→agent steering; later (R): SDK,
                Rust CLI; later separate work (P, V): file-open INTERNALS
                (its boundary contract is designed here, unadvertised)
complexity      one IPC v2 registry with typed catalog, one fact vocabulary,
                one Swift CLI compiled from the catalog (model shorthands +
                hook/tool verbs + the debug-channel test-control surface +
                the spool), one package with per-provider installer table,
                one durable message store; a new daemon process or any
                file-open realization requires renewed approval
evidence        live: an agent in a pane reports and sends a message through
                the CLI and the facts appear in a Sessions query with correct
                labels (fixture-proven per round-1 provider); a message sent
                while the app is down is present after relaunch; a debug
                build's testing verbs drive the app while a stable build
                refuses them; `mise run test` green; architecture lint green
unresolved      owner: none. design-owned: pane-token lifetime across
                restart. evidence gap: Cursor CLI interactive hook
                applicability (headless start/end proven 2026-09-12)
```
