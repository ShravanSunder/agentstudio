# Agent IPC v2 — Decision Record

Date: 2026-09-12. Pathfinding session on branch `ipc-improvements`.
Owner: product owner (Shravan). Status legend: accepted | proposed | superseded.

Companion: [user-requirements.md](user-requirements.md). Evidence receipts
(herdr, orca/t3code/Ghostex/supacode, hook ecosystems, this repo's IPC census,
sessions-spec lineage, OpenCode/Cursor CLI) live in the session scratchpad and
are summarized in the requirements record's evidence anchors.

## Scope of this slice

```text
decision: This slice sets up for success: IPC v2 plus an agent package that is
          compatible with each provider's native hooks/skills/plugins.
why:      "this slice is about setting up for success having ipc and agent
          plugin compatible."
alternatives: build the Sessions pane UI first (rejected: capability before
          surface); build ACP hosting first (rejected: secondary phase).
consequences: the Sessions sidebar pane UI, ACP client, agent-to-agent
          messaging, and macOS banners are later slices; this slice must leave
          the fact contract and socket contract ready for them.
status:   accepted
```

## D1 — Provider rounds

```text
decision: Round 1 supports Claude Code, Codex CLI, Cursor CLI. Round 2 adds
          pi and OpenCode (and others mentioned later).
why:      "round 1 is claude, codex, cursor. round 2 is pi, open code etc"
alternatives: all five in V1 (superseded by this record).
consequences: the package's installer table must be extensible; round-1
          proof fixtures cover three dialects. Cursor CLI hook applicability
          is an evidence gap (see open items).
status:   accepted (supersedes the earlier "all five in V1" reading)
```

## D2 — One package, provider-native installers

```text
decision: One Agent Studio agent package with install scripts that register,
          per provider, its native hooks / skill / plugin / extension, using
          each provider's own lifecycle events.
why:      "scripts to install skills; our plugin must be cross compatible with
          the hooks, skills and plugins etc and we should use the right
          lifecycle."
alternatives: a generic shim/wrapper around every agent (rejected: wrong
          lifecycle, herdr/orca/Ghostex all install native hooks instead).
consequences: the `agentstudio` CLI/socket is the shared layer; installers
          are thin, table-driven (Ghostex `HOOK_DEFINITIONS` is the template).
status:   accepted
```

## D3 — Questions count as needs-you

```text
decision: Provider elicitation / confirm / input / permission prompts are
          NEEDS YOU.
why:      "for questions (elicitation model has) and to get lifecycle"
alternatives: permission prompts only (rejected: questions block the same way).
consequences: each provider adapter maps its question/elicitation events to
          the needs-you fact; Cursor CLI has no such event today.
status:   accepted
```

## D4 — Agents may send any message

```text
decision: The model may send any message it wants to Agent Studio; messages
          are stored and visible in Sessions.
why:      "model should be able to send any messages it wants"; "it just has to
          be there. Something happened, so that's good."
alternatives: content-free ingress as in the 2026-08-03 Sessions spec
          (superseded for the Sessions surface); banners in V1 (deferred).
consequences: message text is never exported to OTLP/JSONL (scrub unchanged);
          macOS banners are optional and later; the 08-03 U-15 "no content in
          notifications" narrows to telemetry/logs.
status:   accepted
```

## A — Identity and trust

```text
decision: A pane gets AGENTSTUDIO pane id, workspace id, socket path, and a
          pane-scoped token in its environment. One socket, one pane-bound
          principal that both reports and controls. Self-pane actions need no
          grant; cross-pane/workspace actions need a grant. Same-UID trust is
          accepted (already accepted by 08-03 for reporting).
why:      hooks and plugins can only read env; the fd-bootstrap path requires
          Agent Studio to spawn the agent, which is not how agents are
          launched; herdr/orca prove env identity is the DX that works.
alternatives: keep the 07-24 reporting/control socket split (rejected: two
          credentials, two client paths); env ids with no token (rejected:
          any same-user process could drive the app).
consequences: `PaneAgentLaunchOwner`'s fd path is no longer the identity
          delivery mechanism; close is the authority fence. AB/AC refine the
          retained-shell behavior to canonical ineligibility, Undo eligibility
          restoration and final discard/expiry revocation without a new
          persisted suspended state.
status:   accepted; close lifecycle refined by AB
```

## B — Control scope: IPC v2

```text
decision: A curated, agent-friendly semantic API plus generic headless
          `command.execute`. UI-interactive verbs stay unexposed except where
          curated for testing. Every exposed argument contract is redesigned;
          the current IPC is not taken as-is.
why:      "Every command's argument must also ensure the IPC isn't taken as
          is; it's designed to be agent-friendly, which it isn't now." "UI
          interactive parts are for testing purposes... we can curate it."
alternatives: expose all 125 AppCommands with argument schemas (rejected:
          83 are UI-state verbs); status quo + open-file only (rejected).
consequences: `AppCommand` stays the identity; semantic methods are added
          where a verb needs parameters; the 23 headless commands remain
          reachable through `command.execute`.
status:   accepted
```

## C — Open-file placement

```text
decision: Default target is the caller's drawer as a CodeViewer pane; reuse an
          existing viewer in that drawer; focus an already-open file elsewhere
          in the tab instead of duplicating; overrides for split / tab / new /
          focus.
why:      "one is drawer"
alternatives: split default; new-tab default (both remain overrides).
consequences: first `file.*` semantic method; `showViewer` (currently
          `.notExposed`) gains a parameterized path. Replace-vs-add for a
          second file is still open.
status:   proposed (drawer default accepted; replace-vs-add open)
```

## E — Evidence trust

```text
decision: Per-provider evidence labels stay (reported > agent-reported >
          estimated). Typed terminal signals (OSC 9, title, progress) via the
          September Ghostty are admitted as provider-authored facts. Screen
          manifests are deferred (maybe later).
why:      "If there are any OSC systems we can use, that's good. If a screen
          manifest is necessary... we could do that later."
alternatives: herdr-style screen manifests in V1 (deferred); no terminal
          signals at all (rejected).
consequences: Cursor CLI needs-you is UNKNOWN in round 1; OSC admission uses
          the existing Contract 7 path, not a new evidence lane.
status:   accepted
```

## F — Persistence and reliability

```text
decision: Sessions are rebuildable; agent messages and seen/attention state
          are durable. A collector for facts emitted while the app is down is
          required; whether it is an in-app socket + disk spool or a small
          always-on Rust daemon (codex-router crates) is OPEN.
why:      "Sessions can be rebuilt... We might need a small daemon to collect
          messages, but it doesn't have to be the story."
alternatives: fire-and-forget only (rejected: messages are the value of D4).
consequences: socket contract must be daemon-fronting-compatible either way.
status:   proposed (durability accepted; daemon fork open)
```

## G — Delivery owner

```text
decision: Inbox stays retired. Sessions owns message and attention delivery.
          This slice builds the capability (ingest + store); the Sessions
          pane UI is a later slice.
why:      "The Inbox is retired. Delivery should be in sessions... we don't
          have to build that now. The important thing is to have the
          capability."
alternatives: revive Inbox rows/schema behind Sessions (rejected: reconnects
          what was retired for MainActor cost).
consequences: eight 08-03 obligations that pointed at Inbox are re-homed to
          Sessions in the spec.
status:   accepted
```

## H — Needs-you: observe-only, answer-through designed in

```text
decision: V1 observes needs-you; every needs-you report carries a request id
          so a later reply channel is a slice, not a redesign.
why:      owner selection (form): "Observe-only now, answer-through designed
          in".
alternatives: answer-through in V1 (deferred: puts the hook in the agent's
          critical path); observe-only with no ids (rejected).
consequences: hook-side waits and fail-open release are designed later.
status:   accepted
```

## I — Agent ↔ agent messaging, codex-router, ACP

```text
decision: Agent ↔ Agent Studio is the primary channel and is bidirectional.
          Agent ↔ agent messaging (codex-router libraries, ACP) is a
          secondary phase. Both ACP-connected and terminal/hook-connected
          agents are to be accepted eventually; this slice keeps the internal
          fact vocabulary ACP-shaped so an ACP adapter is additive.
why:      "The most important communication is agent <-> Agent Studio." "ACP
          is programmatic, others are not... you should be able to do both."
          "secondary phase; we don't need to do it now."
alternatives: ACP client in this slice (rejected: requires a chat pane —
          t3code-scale surface).
consequences: Studio→agent in V1 = terminal input plus a Studio→agent
          message channel the skill can read (mechanism proposed, not yet
          confirmed).
status:   accepted (ACP-shaped vocabulary is the agent's proposal, proposed)
```

## J — Protocol owner, wire shape, CLI

```text
decision: IPC v2 is Swift-owned in this slice. The wire is JSON-RPC 2.0 with
          a discoverable schema: a method list with typed params/results
          (MCP-like), so the same surface can back an MCP adapter or SDK
          later. A CLI is required now (generated from that schema) so agents
          can call it easily; an SDK for composing calls comes later. A Rust
          CLI built to codex-router standards is a later, separate PR.
why:      "ipc should resemble json rpc schema so that we can use it for
          anything if it's v2 (like mcp)"; "it's just swift owned now. the cli
          makes it easy for agents to call, later we make sdk to compose";
          "the cli can be rust, like codex-router, done later with those
          standards as separate pr."
alternatives: Rust core from codex-router crates with Swift as client now
          (deferred to the ACP / agent-to-agent phase); carry the phase-1
          command/data shapes forward (rejected: "not great to call").
consequences: the registry gains a schema; `agentstudio-ipc` becomes the
          `agentstudio` CLI driven by that schema; no daemon in this slice.
status:   accepted
```

## K — Spool is the collector

```text
decision: When the app socket is absent, the CLI appends the exact JSON-RPC
          request it would have sent as one line to an owner-only, per-pane
          spool file; the app drains it on launch through the same admission
          path, marking lines "late" so they can create durable messages but
          never override newer live state. No bearer token is written to
          disk; the same-user directory plus pane-id filename is the scope.
          "No message lost across an app restart" is a MUST for accepted or
          durably spooled notifications. AB's explicit reachable-app auth
          rejection is not an accepted/queued message and never falls back to
          spooling.
why:      owner asked how a spool works and accepted the explanation
          ("spool makes sense"); durability of messages is the value of D4.
alternatives: small always-on daemon (deferred to the ACP phase);
          fire-and-forget (rejected).
consequences: resolves A2 and F. A running agent in a restored pane reports
          through the spool/socket with its existing env; token lifetime and
          restart handling are design's to settle within this contract.
status:   accepted; non-durable credential failure boundary refined by AB
```

## L — Spool loss tolerance (from independent review finding F1)

```text
decision: Messages are never dropped: if a message cannot be appended to the
          spool or durably accepted, that is an explicit failure. Lifecycle
          STATE facts (session/turn/tool/subagent activity) emitted while the
          app is down MAY be capped per pane; when the cap drops lines the
          affected context carries a "some facts lost" disclosure. Live state
          on relaunch supersedes late state facts anyway.
why:      owner selection 2026-09-12 ("Bounded loss for state facts only").
alternatives: unbounded spool for all facts (rejected: unbounded growth);
          age-based cap (rejected: same disclosure, more rules).
consequences: U14/U21 narrowed: "no message lost" is absolute; "state facts
          not lost" becomes "not lost silently". Specification R-23 keeps
          its disclosure obligation with this owner authority.
status:   accepted
```

## M — Cross-pane grants in round 1 (from independent review finding F2)

```text
decision: No grants are issuable in round 1. A request whose effect reaches
          another pane or workspace-wide scope returns a stable missing-grant
          error naming the required scope. Round 1 authority = self-pane
          actions, reporting, discovery. Grant issuance (approval UI or
          policy configuration) is a later slice.
why:      owner selection 2026-09-12 ("No grants in round 1"); phase-1 IPC's
          approval port answers `.ask` with no approver flow (ipc.md).
alternatives: static policy pre-grants (deferred); interactive approval in
          round 1 (rejected: UI work; reopens observe-only).
consequences: Specification C1/R-02 name the missing-grant outcome; proof V1
          has no "granted case" in round 1; U16 amended.
status:   accepted
```

## N — Round-1 scope cut: no steering, no spool (2026-09-13)

```text
decision: Round 1 (this PR) does NOT include Studio→agent instruction
          delivery (steering) and does NOT include the offline spool. If
          Agent Studio is not running, facts emitted meanwhile are not
          collected. Both move to a later PR (PR2).
why:      "for round 1 we shouldn't have agent studio to agent instructions
          and also spool, that's pr2. we should assume if it's not running
          we don't need it."
alternatives: keep both in round 1 as designed (rejected by owner: build
          less now).
consequences: U11 deferred to round 2 (priority should); U14/U21 narrow to
          "messages and seen/attention state accepted while the app is
          running survive restart" — no app-down collection, no late
          admission, no per-pane cap/loss disclosure for offline facts;
          decision K (spool) and decision L (spool loss) are deferred with
          it; decision I's V1 mechanism note is moot; Specification R-03's
          credential late-report path as then designed, R-21/C7/V8 (steering),
          R-22/R-23/C6 (spool) and Program Design D6/D7, PaneReportSpool,
          LockedRequestSpool, SessionsInstructionDelivery, the
          sessions_instruction table and the mailbox methods are removed
          from round 1. Live-ingress overload disclosure (R-15/C8) stays.
status:   accepted
```

## O — Round-1 scope cut: no CLI (2026-09-13)

```text
decision: Round 1 ships no `agentstudio` CLI. The schema-generated CLI, the
          SDK, and the Rust CLI are later PRs ("a good progression, but we
          don't need this right now"). Round-1 hook scripts and the skill
          send JSON-RPC to the socket directly through a small inline
          sender bundled in the agent package; that sender is package
          plumbing, not a CLI product or a second catalog.
why:      owner selection 2026-09-13 ("No CLI in round 1 at all"; "i think
          it was something i misrepresented").
alternatives: keep the schema-generated CLI (deferred); a hand-rolled
          minimal CLI (rejected: would be a second hand-maintained mapping
          the later generated CLI must replace).
consequences: J narrows for round 1 to the wire/schema half — JSON-RPC 2.0
          with a discoverable typed catalog stays (it is what the later CLI
          and MCP adapter consume); U20 deferred; Specification R-11 and the
          CLI clauses of R-10/C2 leave round 1; Program Design's catalog
          export mode and generated-CLI parity gate leave round 1; the
          existing `agentstudio-ipc` smoke client is retired with phase-1
          shapes (hard cutover) rather than kept as a parallel path.
status:   accepted (supersedes the CLI-now half of J; the wire half stands)
```

## P — Round-1 scope cut: no file opening via IPC (2026-09-13)

```text
decision: File opening through IPC (the `file.open` method, drawer
          placement, viewer choice) is OUT of this slice. Another agent adds
          it later as its own piece of work. Remove it from the
          Specification and Program Design now.
why:      "this is a complex thing, and it's out of scope, so file opening in
          ipc in our viewers for now — another agent will add it, let's
          remove this asap." Discussion surfaced that the design had
          targeted the dormant plain-text CodeViewer pane (no product entry
          point) under the unrelated `showViewer` zoom identity, whereas the
          product's file experience is the Bridge file view; choosing and
          wiring that is a separate design.
alternatives: Bridge file view in the caller's drawer with CodeViewer
          fallback (the recommended target when the later work happens);
          CodeViewer as designed (rejected: dormant pane, wrong identity).
consequences: U2 deferred; decision C superseded for this slice;
          Specification R-06, C3, V3 and the P1/O1 file clause removed;
          Program Design D3, FileOpenPlacementResolver, the file-open App
          adapter, the `showViewer` parameterized overload, and the
          CodeViewer/SwiftPaneRuntime prepare/apply changes removed. The
          agent skill's "open a file" journey leaves round 1.
status:   accepted (supersedes C for this slice)
```

## Q — Model-facing minimal surface (2026-09-13)

```text
decision: The surface a MODEL touches must cost few tokens and carry no
          hand-typed identifiers: (1) model commands take plain scalar
          arguments, never JSON — e.g. `agentstudio message "text"`,
          `agentstudio needs-you "why"`, `agentstudio done`; (2) the model
          never types a pane id, correlation id, request id, or sequence —
          `self` targeting, sender-generated correlation, app-derived
          needs-you identity (one current assertion per conversation, so
          clearing needs no id); (3) the deliberate report vocabulary is a
          closed tiny set (needs-you, done, note); (4) replies to a model
          call are one short line unless detail is requested; the catalog
          and query pages are for tooling, never echoed into a model call.
          JSON-RPC with full params remains the wire for hooks and tools.
why:      "did we make sure it's not too verbose and ceremony while being
          straightforward for ipc such that agents don't have to waste
          tokens or send numbers and ids that may have issues."
consequences: a new obligation group in the Specification beside the Agent
          DX group, and a review rubric item ("model token economy") for
          design and final review.
status:   accepted; NARROWED 2026-09-13 by three-artifact review finding F1
          (Opus): `note` was removed from the vocabulary because `message`
          already carries arbitrary text and the two had identical
          observable behavior. The deliberate vocabulary is needs-you,
          needs-you --clear, done; `message` is the one free-text call.
          Decision X's parenthetical list of spooled notifications reads
          accordingly (message, needs-you, done).
```

## R — CLI returns to round 1 (2026-09-13; supersedes O)

```text
decision: Round 1 ships the `agentstudio` CLI after all, in the shape
          decision J set: generated from the catalog (no hand-maintained
          verb switch), one invocation per method for hooks/tools, plus the
          model-facing shorthands from decision Q. `agentstudio-ipc`'s
          phase-1 verb executable is retired; `AgentStudioIPCClientCore`
          (framing, auth, response-id checks, event stream) stays as the
          Swift client library under the new CLI and the test/smoke harness.
why:      "right, so then we should have a cli then with these changes" —
          after establishing that the package sender would be a de-facto
          CLI, that agents are grandchildren of zmx shells (env, not fd,
          is the identity path), and that a hand-rolled minimal CLI would
          be a second catalog mapping.
alternatives: no CLI / inline sender (decision O — superseded); hand-rolled
          minimal CLI (rejected again: second mapping ported twice).
consequences: U20 returns to must; Specification R-11 and the CLI clauses
          of R-10/C2/V2/V3 return (V3 now covers report/message, not file
          open); Program Design restores the catalog export mode, the
          generated CLI, and the parity gate. SDK and Rust CLI stay later.
status:   accepted
```

## S — The CLI is also the agent test-control surface in debug (2026-09-13)

```text
decision: Part of the round-1 CLI's job is to let agents control Agent
          Studio so they can test app features well in DEBUG mode. Against
          a debug-channel app (existing debug-token escrow / unsafe-no-auth
          composition), the CLI exposes the curated testing surface —
          layout (split/close/focus/drawer), terminal send/wait/status,
          bridge.*, `ui.*` presentation, headless `command.execute`, and
          read snapshots — through the same generated catalog. Stable/beta
          builds do not expose that surface. This replaces the phase-1
          `agentstudio-ipc` debug client, which the owner finds poor.
why:      "part of this cli is also allow agents to control agent studio so
          they can test the app features well in debug mode"; "i do want
          debugging enabled right now, the debugging cli is not great."
alternatives: keep the old `agentstudio-ipc` for debug (rejected: its verbs
          are phase-1 shapes); a separate debug tool (rejected: second
          catalog).
consequences: decision B's "UI interactive parts are for testing" becomes
          a concrete exposure class in `ipcSpec`/the catalog (debug-channel
          only); the proof scripts re-point at the new CLI; the Program
          Design's hard cutover keeps `ClientCore` and retires only the
          verb executable.
status:   accepted
```

## T — CLI language: Swift (2026-09-13)

```text
decision: The round-1 `agentstudio` CLI is Swift, in this repo, shipped
          inside the app bundle with the same signing/notarization. It is
          compiled from the same descriptor definitions the server
          registers (the CLI target links the catalog types), so there is
          no JSON export step and no parity gate for the CLI itself; the
          JSON catalog export remains for MCP/SDK/Rust later.
why:      "i don't think we need rust, we can do swift, it makes more sense
          and has better type safety and shipped with same notarization."
alternatives: Rust to codex-router standards now (deferred to the phase
          where the CLI must run without the app).
consequences: Program Design adds a thin Swift CLI target over
          `AgentStudioIPCClientCore`; no cargo toolchain in this slice.
status:   accepted
```

## U — Spool returns with the CLI (2026-09-13; narrows N)

```text
decision: With the CLI back in round 1, the offline spool (decisions K and
          L) returns to round 1: the CLI spools reports when the app socket
          is absent; the app drains after IPC readiness without gating launch;
          messages are never dropped;
          state facts may be capped with disclosure. Studio→agent steering
          STAYS in PR2 (that half of N stands).
why:      "if we have a cli then we can do spool and we can do the ipc unix
          socket."
consequences: U14/U21 return to their K/L wording; Specification R-22 and
          the spool halves of R-03/R-23/C6/C8/V6 return; Program Design
          restores PaneReportSpool, LockedRequestSpool, D6, the credential
          late-report path as then designed, and the related lint and proof
          seams. AC later supersedes credential supersession without changing
          notification-spool recovery.
status:   accepted; drain timing refined by AA
```

## V — File-open: contract at the boundary only (2026-09-13; refines P)

```text
decision: File opening's INTERNALS stay off the table for this slice, but
          its IPC contract may be designed at the boundary: the method
          identity, typed params (path, line, target, placement/focus
          intent, correlation), result alternatives, error reasons, and the
          `AppCommand` relationship it will declare. It is documented as a
          reserved contract — not registered, not advertised by discovery
          in this slice (R-26). Another agent designs the internals behind
          that boundary later.
why:      "the file open stuff is off the table, but we can design the ipc;
          another agent will use them to design the internals after the ipc
          boundary."
consequences: Specification keeps a "reserved contracts" section holding
          the file-open wire contract with no realization obligation and no
          proof in this slice; Program Design names the seam (where a later
          adapter plugs in) and nothing else; the earlier CodeViewer /
          showViewer realization is gone.
status:   accepted
```

## W — Consolidated rewrite to remove cruft (2026-09-13)

```text
decision: After the sequence of cuts and restorations (N, O, P, R, U, V),
          the Specification and Program Design are rewritten coherently
          against the final decision set rather than patched again:
          continuous numbering, no "removed by decision X" markers, no
          stale cross-references, no residue of superseded realizations.
why:      "step back, reassess the spec and make sure we clean it up from
          old cruft."
status:   accepted
```

## X — Spool buffers notifications only, never commands (2026-09-13; narrows L, U)

```text
decision: The spool holds NOTIFICATIONS — "what happened" — and never
          COMMANDS — "do this". When Agent Studio is not running, nothing
          that would make the app do something is buffered: no control, no
          query, no auth frame. In round 1 the spooled notifications are
          agent messages and deliberate agent reports (needs-you, done,
          note). Hook-emitted lifecycle state facts are NOT spooled in round
          1: when the app is down they are dropped at the source (the
          provider's own history remains the record), which removes the
          per-pane state cap, the loss sidecar, and the offline "some facts
          lost" disclosure. Live-ingress overload disclosure stays.
why:      "basically notifications (events is what happened) vs commands
          which is 'do this'; if agentstudio is not up there is nothing
          [command-like] that should be buffered if it's offline" — and
          "yes" to messages-only after seeing that late state facts can never
          change current state by rule.
alternatives: keep capped lifecycle-state spooling (L) — permitted by the
          principle, deferred as unnecessary machinery; can be added later
          under this same rule without new authority.
consequences: U14/U21 narrowed to messages + deliberate reports; decision L
          superseded (no state-fact cap/loss for offline); Specification
          R-20/C6/C8/V7 and Program Design spool section, `.state.ndjson`,
          loss marker, cap policies, and `sessions_loss`'s offline role
          are removed; a single per-pane message spool remains; controls/
          queries never queue (already a MUST) is restated as the rule.
status:   accepted (supersedes L)
```

## Y — Debug auth is a reusable verifier-backed credential; debug control must be zero-ceremony (2026-09-13)

```text
decision: (1) Debug builds write an owner-only (0600), runtime-bound
          debug credential when off-critical IPC readiness succeeds; the CLI
          reads it on every call; the app verifies a SHA-256 verifier (the same mechanism as
          pane tokens); it is revoked and deleted at app shutdown or runtime
          replacement; debug channel only — stable/beta never write it.
          (2) Running and controlling a debug app MUST NOT be onerous: a
          small model (Haiku/Luna class) must be able to drive it. The CLI
          discovers the running debug app from its runtime metadata (no
          socket paths, tokens, or flags to hand-assemble), and debug
          control verbs have the same plain-argument, short-reply ergonomics
          as the model-facing surface. Owner-facing goal: "I want to run
          debug to debug the app as I develop it."
why:      final review finding ASTRA-01 (single-use escrow cannot
          authenticate a second CLI call); owner: "if we do 1, I want to
          make sure debug apps and running them and controlling them are
          not onerous… say a haiku or luna needs to control the debug app."
alternatives: unsafe-no-auth for debug (rejected: weakest); per-call
          re-escrow (rejected: race + file churn).
consequences: Specification C4/R-13 gain the reusable-credential lifecycle
          and a debug-DX obligation with a proof (a Luna/Haiku-class agent
          given only the skill drives a debug app end-to-end); Program
          Design replaces the single-use escrow path in the debug channel
          with the verifier-backed debug credential, and adds the discovery
          rule; ASTRA-02's diagnostic correlation namespace keys on the
          debug runtime id + credential generation.
status:   accepted; startup timing and authenticated principal provenance
          refined by AA
```

## Z — The full command spec is callable from IPC in debug mode (2026-09-13; widens S)

```text
decision: In debug mode the `debugTesting` class exposes EVERY
          `AppCommand` through typed `command.execute` — interactive verbs
          included — each with explicit typed arguments where the
          interactive form would have used focus, a picker, or UI state.
          Commands whose only meaning is presentation (e.g. open the
          command bar) are callable and report presentation, not completion.
          Stable/beta keep the headless-only exposure. Good DX applies:
          discoverable, typed, plain-argument CLI verbs.
why:      "I want to make sure command spec is callable fully from IPC with
          good DX in debug mode."
consequences: `ipcSpec` gains a debug argument variant for every
          interactive command (the exhaustive switch forces it); the
          Specification's C4 inventory becomes "all AppCommands (debug) +
          pane/terminal/bridge/ui/snapshot methods"; V4 proves every
          AppCommand is dispatchable in debug and refused in stable/beta.
status:   accepted
```

## AA — IPC never gates normal startup or terminal availability (2026-09-15)

```text
decision: Normal IDE startup, the first interactive frame, fresh terminal
          construction, and attachment to an existing zmx shell do not wait
          for IPC communication, credential persistence, Sessions/IPC schema
          readiness, server/catalog publication, or spool recovery. Any IPC
          failure leaves the IDE and terminal usable. Existing-zmx attachment
          performs no IPC readiness preload, external check, durable write, or
          running-shell environment rewrite. AC confirms restoration is only
          reattachment: the existing zmx shell keeps its original token.
why:      owner correction on 2026-09-15: "i do not want the ide to impacted
          by ipc comm on startup if that maek sens". The surrounding owner
          instructions extended that boundary to new-shell creation,
          existing-zmx attachment, credential persistence, and spool readiness,
          then authorized bringing the full accepted scope home under it.
alternatives: persist the pane verifier before exposing shell environment
          (rejected: makes terminal construction wait on optional SQLite);
          keep Sessions/IPC DDL in the pre-window migrator because it appears
          cheap (rejected: assumed cost is not independence); preload restored
          credentials before zmx attachment (rejected: reattachment must remain
          an existing-shell operation).
consequences: Program Design must realize the boundary without a second
          persistence owner, pool, daemon, atom, store or coordinator, while
          preserving the accepted token, spool, Sessions and debug-control
          scope. Specification R-03 must state the resulting non-durable window and
          the proof obligations must cover delayed readiness and retirement.
limitation: Superseded by the owner decisions in AB. The non-durable window
          covers any process end before verifier durability, including normal
          exit after optional schema/storage failure, with explicit failure
          after relaunch until a new shell.
advisory: Fable Advisor posts 84 and 85 identified the Program Design's
          structural consequence as the smallest response to the owner boundary
          and required the R-03 crash-window guarantee to become explicit. That
          advice informs the structural choice; it is not owner authority.
status:   accepted (owner boundary); refined by AB after independent review
```

## AB — Undo credential lifecycle and non-durable exit (2026-09-16)

```text
decision: (1) SUPERSEDED by AC: no per-surface/per-attachment candidate issuance.
          (2) Undo-eligible close immediately denies all requests and closes
          leases through canonical ineligibility. Undo restores that same
          retained-shell credential's eligibility after membership restoration;
          expiry/discard revokes permanently. No new persisted suspension or forced
          shell recreation and no new timer/coordinator.
          (3) The owner accepts explicit IPC failure after any process end before
          credential durability, including normal exit after storage failure.
          The terminal remains usable, IPC is explicitly unavailable until a
          new shell, and authentication rejection never triggers spooling.
why:      Owner answered all three startup-correction review questions on
          2026-09-16 and selected the recommended Undo-preserving path while
          restating concern that terminal startup/attachment stay on their
          existing behavior rails.
alternatives: IPC/vendor probe before attach (rejected: adds dependency and
          changes vendor/terminal path); permanent credential loss on Undo or
          forced shell recreation (rejected); seamless unknown-token admission
          or auth-rejection spool fallback (rejected: weakens authority); new
          mount owner/coordinator (rejected).
consequences: Specification R-03/R-20 and C1/C8 state the retained outcomes.
          Program Design uses existing identity/principal, canonical membership
          and undo-deadline owners for deny/restore/revoke transitions and starts optional
          IPC work only at the existing first-frame/terminal-release edges.
status:   items 2 and 3 accepted; item 1 superseded by AC
```

## AC — Restoration reattaches; it does not replace credentials (2026-09-16)

```text
decision: Pane restoration reattaches to the existing zmx shell. That shell
          retains its original environment and raw token; restoration does not
          save, recover, rotate or replace the credential. IPC owns logical pane
          identity and verifies a token presented on the request path through
          the stored hash. A genuinely new shell may receive a new token and
          need not recover an old raw token.
why:      Owner rejected the candidate design as unnecessary mount coordination:
          "no do not save with terminal mounting" and then clarified that an
          existing zmx session retains the shell/token and restoration is only
          reattachment.
alternatives: per-surface candidate issuance/promotion/retention (rejected as an
          invented problem and mount coupling); raw-token recovery during restore
          (rejected). No HMAC/master key, raw-token persistence or alternate
          storage mechanism is selected.
consequences: Remove automatic issuance and supersession tied to renderer/surface
          recreation. Program Design assigns the existing PaneIPCIdentityOwner one
          cached environment token per logical pane/app runtime: its first request
          mints the token and opaque credential record ID, admits the verifier to
          the existing principal registry and caches the environment entirely in
          RAM. It submits no persistence. The existing IPC service independently
          schedules hash persistence at post-frame readiness, newly used
          authenticated admission and normal shutdown. Graceful shutdown first
          snapshots every still-unsaved issued RAM verifier, including credentials
          never used for IPC, and then drains accepted writes. Storage-unavailable
          or interrupted shutdown retains AB's explicit non-durable window. Every
          later mount receives the same environment; existing zmx ignores it and
          a genuine new shell inherits it. Previously durable verifier rows remain
          valid for the same canonical live pane, and new issuance does not
          supersede them. Opaque
          record IDs key persistence/correlation/replay, not authority ordering.
          AB's close/Undo/discard and non-durable-exit outcomes remain. This is the
          selected structural How for the accepted outcomes, not implementation
          authority or a new owner-visible product outcome.
status:   accepted restoration correction; structural realization updated for owner review
```

## AD — No control replay journal (2026-09-17)

```text
decision: Controls (commands, layout, terminal input, events) have no durable or
          in-memory correlation replay journal in round 1. Correlation stays
          required on the wire and echoed in results. A repeated correlation is
          a new request. Durable deduplication exists only for reports and
          messages through the Sessions occurrence journal, which already
          commits domain outcome and correlation atomically.
why:      No owner requirement asks for control replay: U14 and U21 cover
          reports and messages, and U21 says commands are never buffered. The
          CLI mints a fresh correlation on every run, so no round-1 caller can
          resupply one. The planned local_ipc_operation journal (reserved/
          started/final, fingerprints, in-flight joins, restart classification)
          protected nobody and repeated the credential over-engineering pattern.
          Owner: "drop S4c, it's really off the rails."
alternatives: durable journal (rejected as above); bounded in-memory per-runtime
          map (deferred until a retrying caller exists).
consequences: local_ipc_operation table, control journal section and S4c are
          removed from the Program Design and plan; R-09 and the C2 correlation
          paragraph are narrowed to reports and messages. The S4c draft test is
          parked outside the tree.
status:   accepted (owner, 2026-09-17)
```

## AE — Minimal offline spool (2026-09-17)

```text
decision: The round-1 spool is one append-only per-pane file written by the CLI
          under flock when the app is unreachable, fsynced before "queued", and
          drained after IPC readiness by reading every line, admitting each as
          late through common admission, and truncating the file only when
          every line is admitted or a duplicate. Malformed lines are counted and
          skipped. No claim/rename generations, quarantine, lock files, per-line
          removal or operator cleanup route.
why:      U14/U21 require that spooled notifications are never lost while the
          app is down; the accepted design grew generation, quarantine and
          cleanup machinery beyond that need. Owner: "do the minimum offline and
          then we can change that later."
alternatives: the full generation/quarantine design (deferred, not deleted from
          history).
consequences: Program Design spool section rewritten; R-20 unchanged in meaning.
status:   accepted (owner, 2026-09-17)
```

## AF — Debug discovery through the existing escrow path (2026-09-17)

```text
decision: Debug CLI discovery uses the existing AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW
          file path passed by the launcher: the App writes runtime ID, socket
          path and the reusable debug credential into that 0600 file at IPC
          readiness. No per-user runtime registry directory, entry enumeration,
          pruning or multi-runtime selection in round 1. Full AppCommand
          coverage with typed debug arguments (U3, decision Z) stays in scope.
why:      The registry was new machinery; the escrow file and its launcher
          plumbing already exist and the proof scripts already use it.
alternatives: shared 0700 registry directory (deferred).
consequences: Program Design debug discovery paragraphs replaced; R-13 unchanged.
status:   accepted (owner, 2026-09-17)
```

## AG — Package delivery order and minimal installer (2026-09-17)

```text
decision: Ship the bundled CLI first as Contents/Helpers/agentstudio from the
          agentstudio-cli product (renamed from agentstudio-ipc; Contents/MacOS
          is impossible because agentstudio and AgentStudio collide on the
          case-insensitive default volume), then providers in the order Codex CLI, Claude
          Code, Cursor CLI. The installer is a CLI subcommand that writes and
          removes only marker-owned entries and prints a one-line notice before
          overwriting a marked entry that differs. No last-installed manifest or
          conflict-diff engine.
why:      The pane environment already advertises a CLI path that nothing
          copies, so bundling blocks every agent use. Owner: Codex first, test
          with Luna, then the others; all three matter.
alternatives: ownership-aware manifest installer (deferred).
consequences: S8 split into bundling (this PR gate) and three provider slices.
status:   accepted (owner, 2026-09-17)
```

## AH — Wrap-up cleanup of committed divergence (2026-09-17)

```text
decision: Delete the never-called debugAutomationIPCPermissionScopes catalog and
          the dead writeDebugToken path; remove the wall-clock optional-migration
          measurement suite from the pull-request test lane and record its
          measured bounds in the Program Design proof view instead; defer the
          Sessions acknowledgment port and the Contract 7 terminal-fact
          subscriber out of S5 until a consumer exists.
why:      Independent drift audit findings A–C; repository rule against
          wall-clock tests; no UI consumes acknowledgment or terminal facts in
          round 1.
status:   accepted (owner, 2026-09-17)
```

## AI — Deliberate verbs require a bound provider session (2026-09-17)

```text
decision: needs-you, needs-you --clear and done are admitted only for a pane
          with an active provider binding; an unbound pane returns the finite
          reason bindingRequired with a one-line reply telling the model to
          install the Agent Studio hooks for its provider. Free-text message
          is admitted on any pane and is stored unattributed when no binding
          exists. session.bind (explicit model bind) stays deferred.
why:      R-17 coalesces one deliberate assertion per conversation/generation;
          without a binding there is no conversation to coalesce against. The
          committed reducer already enforces this (SessionsEvidenceReducer
          requireActiveBinding). In round 1 every supported provider installs
          hooks, so the binding exists whenever a model can run the skill.
alternatives: undefer session.bind (rejected for round 1: a model-typed bind
          contradicts Q's no-identifier vocabulary and invents a conversation
          identity the provider did not report).
consequences: W3 proves report-after-bind, report-on-unbound-pane failure, and
          unattributed message durability. The skill text states the
          precondition. Revisit only if a provider without hooks must report.
status:   accepted structural note; no owner-visible product change
```

## Open items (owner decisions still needed)

- None. Program Design inventory approved by the owner on 2026-09-13
  ("it looks good") subject to decision X.

- The remaining items below are design-owned, not owner decisions:
  second-file replace-vs-add in the drawer (C) and the Studio→agent mechanism
  in V1 (I). Pane-token lifetime across restart is resolved by AA with the
  explicit AB non-durable process-end limitation and Undo lifecycle.

## Evidence gaps (not owner decisions)

- Cursor CLI: live check on this machine (2026-09-12, `cursor-agent`
  2026.09.02, headless `-p`, project-scope `hooks.json`): `sessionStart` and
  `sessionEnd` fire and carry `session_id` (= `conversation_id`);
  `beforeSubmitPrompt`, `afterAgentResponse`, `stop` did not fire;
  `stream-json` `result` carries the same `session_id`. Interactive TUI case
  (the pane case) not yet exercised. Round 1 may promise Cursor identity via
  hooks; turn-done via hooks remains unproven.
