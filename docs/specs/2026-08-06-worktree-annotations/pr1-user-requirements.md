# Worktree Annotations PR1 — User Requirements

Status: current Requirements authority for PR1

## Purpose

PR1 establishes a durable human review loop inside the selected repository
worktree. A reviewer creates human-authored threads on source-backed material in
File View and Review View, preserves unfinished messages across reload and
restart, saves intentional message versions, and hands any selected saved
messages to the working agent through Markdown clipboard copy or versioned JSON
file export.

Located threads appear inline beside their source in the main File or Review
view. Whole-file and session-level threads remain in that same main review
surface. PR1 adds no comment sidebar; a separate navigation surface may be
considered only after the inline workflow is proven.

The working agent remains an external recipient in PR1. Agent Studio does not
deliver to, query, authorize, or accept mutations from an agent in this slice.

## Authority and sources

- Decision owner: Agent Studio owner.
- Current sequence authority:
  [`README.md`](./README.md).
- Owner-confirmed PR1 meaning: the 2026-08-14 pathfinding conversation for this
  design cycle.
- Advisory substrate:
  [`../2026-08-03-worktree-annotations/pr1-user-requirements.md`](../2026-08-03-worktree-annotations/pr1-user-requirements.md).
- Current code and architecture establish the foundation to reuse; they do not
  authorize additional product meaning.

## Affected classes

### Human reviewer

Reviews completed plans, specifications, files, and code changes in the
worktree where an agent worked. The reviewer creates durable transformation
requests, deliberately saves the versions that are ready, hands off a selected
batch, and verifies the resulting worktree changes.

### Working agent

Receives model-readable Markdown from the clipboard or a versioned JSON file
through the reviewer’s existing interaction, then edits the worktree. In PR1,
the agent has no Agent Studio annotation identity, authority, delivery receipt,
or mutation surface.

Multi-user collaborators, code-host reviewers, review administrators, provider
integrations, and automated agents are outside PR1.

## How to read the needs

```text
one human review round
  |
  +-- find and continue the right session ........ P1-U1, U7, U8, U13
  +-- comment inline without losing work ......... P1-U2, U3, U4, U5, U14
  +-- keep locations honest as source changes .... P1-U6, U7, U8
  +-- hand selected saved messages to an agent ... P1-U9, U10, U11, U12
  `-- return, inspect changes, and resolve threads  P1-U8, U14
```

The stable `P1-U*` rows below are the authority. This map only makes their
relationship easier to inspect.

## User-job sequence

```text
agent completes work in a selected worktree
  → reviewer opens File View or Review View
  → reviewer creates or continues one living annotation session
  → reviewer starts inline source-backed threads and writes Markdown messages
  → message drafts autosave; explicit Save establishes output-eligible versions
  → reviewer selects some or all saved messages
  → reviewer copies Markdown or exports versioned JSON
      → Copy shows a short confirmation and closes the copy interaction
      → copied threads remain open
  → agent changes the worktree through the existing interaction
  → reviewer returns to the same living session
  → reviewer resolves, continues, or finishes the review
```

```text
main File / Review surface

  source line or range
       +-- add comment control
       `-- inline thread
             root human message
             reply 1
             reply 2 draft
             [Save] [Revert] [Reply] [Resolve thread]

  whole-file request ---- shown at file level in this surface
  general request ------- shown at session level in this surface

  no PR1 comment sidebar
```

```text
PR1 human boundary

  File View ─┐
             ├─ one living human review session ──┬─ Copy Markdown
  Review View┘                                    └─ Export JSON

  external agent ◀── reviewer pastes or transfers output
  external agent ──X─ Agent Studio mutation, reply, or acknowledgement
```

## Authorized needs

### P1-U1 — Review one living worktree round across both viewers

- Affected class: human reviewer.
- Need: One identifiable annotation session represents a living review round in
  one selected repository worktree and spans File View and Review View. The
  session is owned by the worktree lineage: opening the same worktree from any
  workspace resumes the same living round, with workspace recorded as
  provenance at most.
- Why: Plans, specifications, files, and diffs may belong to one coherent body
  of review work; panes, viewer instances, workspaces, and ordinary worktree
  changes must not fragment it.
- Evidence: owner confirmation on 2026-08-14; worktree ownership confirmed by
  the owner on 2026-08-15
  ([decisions record D2](./pr1-owner-decisions-2026-08-15.md)).
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U2 — Preserve unfinished message work

- Affected class: human reviewer.
- Need: A non-empty message draft survives focus changes, view replacement,
  pane recreation, leaving Zoom, and Agent Studio restart without requiring an
  explicit Save.
- Why: Draft text is human work product and must not be lost merely because the
  review surface or process lifecycle changes.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: a hard failure may lose only changes not yet durably flushed
  under the confirmed bounded autosave policy.

### P1-U3 — Keep message autosave separate from intentional Save

- Affected class: human reviewer.
- Need: Autosave protects a working message draft, while explicit Save
  establishes a new intentional message version. Revert restores the last saved
  version or removes an unsaved new message draft.
- Why: Crash protection must not silently declare incomplete writing eligible
  for output.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U4 — Write useful Markdown thread messages

- Affected classes: human reviewer and working agent.
- Need: Human thread-message bodies support the product’s safe Markdown
  vocabulary, including H2 through H6 headings but excluding H1, and preserve
  the authored Markdown source. Each root or reply body admits at most 16 KiB
  of UTF-8 independently; a thread may contain multiple messages and may exceed
  16 KiB in total.
- Why: Review requests may need lists, code, tables, links, and subordinate
  structure, while H1 must remain reserved for the surrounding review packet.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: raw HTML is not part of the safe Markdown vocabulary.

### P1-U5 — Anchor threads to model-usable source context

- Affected classes: human reviewer and working agent.
- Need: PR1 supports source-line/range threads, whole-file threads, and
  session-level general threads. Located and whole-file threads identify
  a repository-relative path; located threads additionally identify source
  lines and the applicable old or new diff side. Located selections are made
  in the source or diff line presentation; Markdown files remain annotatable
  in that presentation. Located threads appear inline beside
  their source in the main view; whole-file and session-level threads remain
  available from that same surface without a sidebar.
- Why: The reviewer needs precise requests, file-wide requests, and general
  review requests. Every scope must make sense to the working model without
  relying on pane, DOM, SVG, or machine-local path identity.
- Evidence: owner confirmation on 2026-08-14; rendered-preview anchoring
  deferral confirmed on 2026-08-15
  ([decisions record D7](./pr1-owner-decisions-2026-08-15.md)).
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: non-text-region, DOM-node, and Mermaid-node annotations are
  outside the focused PR1 anchor contract. Rendered-Markdown preview selection
  (selecting in the rendered preview and resolving to Markdown source lines)
  is deferred to a follow-up PR; no source-map machinery exists today and the
  owner cut it from PR1 scope.

### P1-U6 — Preserve thread origin while explaining current placement

- Affected classes: human reviewer and working agent.
- Need: Every thread keeps immutable creation evidence and separately shows
  whether its current placement is exact, relocated, outdated, or unavailable.
- Why: A living worktree changes after external handoff; source drift must
  neither erase the request nor present uncertain locations as current truth.
- Evidence: owner-confirmed continuity model on 2026-08-14 and advisory PR1
  source.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U7 — Let the reviewer decide uncertain continuity

- Affected class: human reviewer.
- Need: Proven continuity keeps a living session writable; uncertain continuity
  pauses new annotations and asks the reviewer whether to continue; proven
  different repository/worktree lineage detaches the still-living session.
- Why: Heuristics may inform continuity but must not silently combine unrelated
  work or finish an unfinished review.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: exact continuity evidence and confidence mechanics belong to
  Program Design.

### P1-U8 — Keep lifecycle, continuity, placement, and thread resolution separate

- Affected class: human reviewer.
- Need: A session’s living/completed lifecycle, source applicability, each
  thread’s placement, and each thread’s open/resolved state remain independent.
  Resolution belongs to the whole thread, not individual messages. Only an
  explicit human action resolves or reopens a thread, or finishes or reopens a
  session.
- Why: Detached is not completed, copied is not resolved, and outdated is not
  detached.
- Evidence: owner confirmation on 2026-08-14, carrying forward the advisory PR1
  distinction.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: reopening a completed session is admitted only through an
  explicit human action; no automatic event reopens it.

```text
One session                Each thread

lifecycle                  placement
  living | completed         exact | relocated | outdated | unavailable

source relationship        resolution
  applicable | uncertain     open | resolved
  | detached

These axes may change independently. Resolve and reopen operate on the whole
thread; neither action changes session lifecycle, source relationship, or
placement.
```

```text
Copy selected messages
        +-- locks only those message identities
        +-- leaves every containing thread open
        `-- never means the requested work was addressed

Resolve whole thread
        `-- explicit reviewer action after inspecting the resulting work
```

### P1-U9 — Produce any selected saved-message output batch

- Affected classes: human reviewer and working agent.
- Need: The reviewer can select some or all saved message versions and
  produce one deterministic, model-readable batch without including unsaved
  message drafts.
- Why: Review may proceed in partial rounds, while explicit Save remains the
  readiness boundary.
- Evidence: owner confirmation on 2026-08-14 and the established partial-output
  workflow.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U10 — Copy a path- and line-oriented Markdown packet

- Affected classes: human reviewer and working agent.
- Need: Clipboard copy presents session-level threads first, then groups file
  threads by repository-relative path and source order. Located entries contain
  a trustworthy current or explicit original line reference, numbered source
  excerpt, diff side when applicable, placement status, and adjacent Markdown
  thread message. Whole-file and session-level entries identify their
  broader scope explicitly rather than inventing a line number. The packet owns
  one H1, plain field labels, horizontal-rule separators, and adaptive fenced
  source excerpts. Authored message bodies remain untouched Markdown and may
  use H2 through H6.
- Why: The pasted packet must make sense to a model without hidden UI context.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U11 — Export the same batch as versioned JSON

- Affected classes: human reviewer and working agent.
- Need: File export writes a versioned, lossless JSON representation of the same
  selected message-batch semantics used by clipboard Markdown.
- Why: A file output must preserve identities, versions, source evidence,
  ordering, and request bodies without parsing prose.
- Evidence: owner selection of structured file export on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U12 — Preserve exact successful output history

- Affected class: human reviewer.
- Need: A successful copy or export preserves an immutable ordered snapshot of
  the exact message versions and thread source context used for that action.
  Every included message becomes immutable; clarification or correction is a new
  human reply. Later work does not rewrite the historical batch. Normal Copy
  success shows a concise copied confirmation, closes the copy interaction, and
  leaves every containing thread open. A crash-recovered attempt whose external
  outcome cannot be proven remains inspectable as unknown; its messages remain
  locked and its exact bytes may be copied again explicitly.
- Why: The reviewer must be able to determine and reproduce what was prepared
  without claiming that an agent received it.
- Evidence: owner-confirmed PR1 output boundary and the advisory PR1 durable
  batch-history requirement.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

```text
saved human messages
        │ select
        ▼
immutable output batch
        ├─ Copy succeeds   ──► clipboard + durable output event
        │                    └─ copied toast + close copy UI
        └─ Export succeeds ──► JSON file + durable output event

successful or crash-unknown output locks included messages
        │
        └─ correction or clarification ──► new human reply

thread state remains open until explicit Resolve
```

### P1-U13 — Discover and resume applicable sessions predictably

- Affected class: human reviewer.
- Need: File View and Review View expose the active session and an obvious
  create-or-continue action. Discovery exposes living applicable, living
  uncertain, living detached, and completed sessions distinctly. With zero
  applicable sessions, the reviewer's first annotation creates the session in
  the same motion — no separate creation ceremony — while other sessions
  remain inspectable; one applicable session offers continuation; several
  applicable sessions require an explicit choice. Uncertain sessions remain discoverable
  so the reviewer can decide continuity, and completed sessions remain
  discoverable so the reviewer can explicitly reopen them.
- Why: Session identity must never be inferred silently from pane recency or
  path coincidence.
- Evidence: owner-directed efficiency boundary plus the advisory PR1 session
  requirement; implicit first-annotation creation confirmed on 2026-08-15
  ([decisions record D5](./pr1-owner-decisions-2026-08-15.md)).
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U14 — Keep every PR1 comment in a flat human-authored thread

- Affected classes: human reviewer and working agent.
- Need: Creating an annotation creates a thread with one root human message.
  Every root message and reply belongs to that thread and may receive a later
  human reply. Replies form one flat chronological sequence; they do not nest.
  PR1 has no standalone comments and no agent-authored messages.
- Why: Once output has exposed a message, its content must remain stable while
  later clarification remains possible without erasing history. A flat thread
  remains readable in both the product and its external outputs.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

## Goal boundary

- Primary goal: complete a durable human annotation-to-transformation loop for
  one living review round in a selected repository worktree.
- Existing foundation to preserve: worktree/repository context, Pane Zoom, File
  View, Review View, PR0 comparison provenance and selection, existing file
  filters, the currently pinned `@pierre/diffs` 1.2.10 source presentation and
  annotation affordances, safe rich Markdown rendering, and native
  clipboard/file effects.
- Missing capabilities: durable sessions, autosaved drafts and saved versions,
  source-backed human threads shared across both viewers, explicit lifecycle and
  continuity, partial/all selection, deterministic Markdown copy, versioned
  JSON export, and immutable output history.
- Allowed surface: Agent Studio’s existing worktree, File/Review viewer,
  persistence, Markdown, clipboard, and file-export capabilities.
- Protected boundary: PR0 comparison behavior remains authoritative foundation;
  PR1 does not redesign comparison selection or target loading.
- Non-goals: direct or automated agent delivery; agent query, identity,
  authorship, replies, or mutation; acknowledgement, retry, reconciliation,
  bindings, providers, Codex App Server, App IPC annotation operations, guided
  review, quick edit, multi-user collaboration, external code-host review,
  issue tracking, arbitrary source editing, DOM/SVG/Mermaid-node anchoring, and
  a new authentication or security system. Thread or message deletion is
  deferred to PR2 with its semantics already decided (open threads, whole
  thread only; resolved threads never). Rendered-Markdown preview selection
  anchoring and a batch save-all-drafts affordance are outside PR1. A comment
  sidebar (the planned follow-up PR for thread navigation) and a Pierre
  dependency upgrade are also outside PR1; each requires separate work.
- Complexity limit: extend existing owners. A new delivery system, provider
  control plane, collaboration platform, security system, separate physical
  Bridge transport, or exactly-once machinery requires renewed owner approval.
- Acceptable outcome evidence: automated state/format/failure proof; restart and
  recovery state inspection; manual or packaged interaction proof in File View
  and Review View; actual clipboard Markdown inspection; actual exported JSON
  validation; and proof that no PR2 capability is required for the loop.

## Confirmed policy decisions

```text
session identity
  one living worktree review round across File View and Review View
  owned by the worktree lineage; workspaces never partition a round
  first annotation creates the session when none applies

durability
  annotation history fails closed on storage corruption
  never silently empty; the reviewer is informed; data held for recovery

continuity
  proven same → continue automatically
  uncertain   → pause and let the reviewer decide
  different lineage → detach without completing the session

draft durability
  first non-empty edit creates a durable draft
  focused typing uses 1-second debounce with 5-second maximum wait
  focus loss and explicit Save flush immediately

message readiness
  autosave protects draft work
  Save creates an output-eligible message version
  Revert restores the last saved version or removes a new message draft

thread history
  every annotation is a thread with a human root message
  replies form one flat chronological sequence
  resolution applies to the whole thread
  successful output locks each included message
  later clarification is a new human reply

message size
  each root or reply body <= 16 KiB UTF-8
  a thread may contain multiple independently bounded messages

output
  Copy   → deterministic Markdown clipboard packet
           → concise copied toast; copy UI closes; threads stay open
  Export → versioned lossless JSON file

main-view presentation
  located threads → inline beside source
  whole-file and session threads → same main review surface
  no PR1 comment sidebar; finish warning shows an open-thread count
  located anchoring uses source/diff line presentation only in PR1
```

Exact internal storage, relocation, continuity evidence, transport,
output-effect sequencing, and recovery mechanisms belong to Program Design.
