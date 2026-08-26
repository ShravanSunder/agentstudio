# Worktree Annotations PR1 — User Requirements

Status: current Requirements authority for PR1

## Purpose

PR1 establishes a durable human review loop inside the selected repository
worktree. A reviewer creates human-authored threads on source-backed material in
File View and Review View, preserves unfinished messages across reload and
restart, explicitly saves intentional message content, and hands the current
saved messages in the review's `New` or `All` view to the working agent through
Markdown clipboard copy or versioned JSON file export.

PR1's customer-facing annotation surface is only located inline threads beside
their source in the main File or Review view. It adds no whole-file or
session-level comment UI, global review panel, persistent session chrome, or
comment sidebar. Those surfaces may be considered only after the inline
workflow is proven.

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
requests, deliberately saves the messages that are ready, hands off the
displayed New or All batch, and verifies the resulting worktree changes.

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
  +-- hand New or All saved messages to an agent . P1-U9, U10, U11, U12
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
  → message drafts autosave; explicit Save establishes output-eligible content
  → reviewer opens Share comments from the File or Review header
  → reviewer displays New or All current saved comments
  → reviewer copies that displayed set as Markdown or exports versioned JSON
      → success shows a short confirmation and closes Share comments
      → copied threads remain open
  → agent changes the worktree through the existing interaction
  → reviewer returns to the same living session
  → reviewer resolves or continues inline threads
```

```text
main File / Review surface

  source line or range
       +-- select range → highlighted range + endpoint add control
       `-- inline thread
             one message  → show M1 directly
             two or more → show compact M-summary + M-last
             explicit Expand / Edit / Reply
                         → expand the same inline timeline to M1 ... Mn
                           with reply/edit authoring below
             new root    → inline Save / Revert
             whole thread → Resolve / Reopen

  no PR1 global-review panel, whole-file comments, session comment chrome,
  or comment sidebar
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
  workspace resumes the same living round. Workspace identity is neither
  session identity nor retained annotation-session provenance.
- Why: Plans, specifications, files, and diffs may belong to one coherent body
  of review work; panes, viewer instances, workspaces, and ordinary worktree
  changes must not fragment it.
- Evidence: owner confirmation on 2026-08-14; worktree ownership confirmed by
  the owner on 2026-08-15.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U2 — Preserve unfinished message work

- Affected class: human reviewer.
- Need: An untouched or whitespace-only composer is ephemeral and disappears
  on focus loss, Escape, or abandoned selection. From the first non-whitespace
  edit, a message draft survives focus changes, view replacement, pane
  recreation, leaving Zoom, and Agent Studio restart without requiring an
  explicit Save. Focus loss flushes the draft immediately; Escape or starting
  another range flushes and collapses a non-empty new-root draft. Clearing a
  never-saved message back to empty removes that unsaved message when the change
  is flushed. Reply and edit composers follow P1-U14's inline-expansion close behavior.
  Clearing an existing saved message creates a durable empty working draft so
  the edit is not lost; Save remains unavailable until the body is valid, while
  Revert restores the saved body. The active editor, visible text, focus, and
  containing thread remain continuous while a first edit becomes durable and
  its updated thread becomes visible; an intermediate update must not make the
  editor or thread disappear. An exact committed Save ends editing immediately
  and keeps the committed saved message visible even when the shared read model
  is still refreshing or unavailable. Saving or flushing a different message
  in the same living session must not make this message conflict.
- Why: Draft text is human work product and must not be lost merely because the
  review surface or process lifecycle changes.
- Evidence: owner confirmation on 2026-08-14 and live save/convergence correction
  on 2026-08-20.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: a hard failure may lose only changes not yet durably flushed
  under the confirmed bounded autosave policy.

### P1-U3 — Keep message autosave separate from intentional Save

- Affected class: human reviewer.
- Need: Autosave protects one optional working draft, while explicit Save
  replaces the message's one current saved body and clears that draft. Revert
  clears the draft to restore the current saved body, or removes an unsaved new
  message draft. A message does not retain a pre-output history of saved bodies.
  Command+Enter invokes Save; Enter and Shift+Enter insert a newline. Save
  progress ends when the exact Save command reports committed or failed; later
  cross-view/read-model convergence is separate and must not leave a committed
  Save looking busy or turn it into a failure. While that read model refreshes
  or is unavailable, the last complete annotation state plus any exact
  command-confirmed local result remains usable. Before the first complete read,
  the UI must say that annotation membership is unknown rather than presenting
  a fabricated empty state or zero New/All counts.
- Why: Crash protection must not silently declare incomplete writing eligible
  for output.
- Evidence: owner confirmation on 2026-08-14 and live save/convergence correction
  on 2026-08-20.
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
- Need: PR1 supports only located source-line/range threads. Each thread
  identifies a repository-relative path, source lines, and the applicable old
  or new diff side. A dragged range remains highlighted but does not open a
  composer until the reviewer clicks its endpoint `+`; selecting another range,
  clicking outside, or pressing Escape clears the pending range. A single-line
  gutter `+` opens its composer directly. Located selections are made in the
  source or diff line presentation; Markdown files remain annotatable there.
  Located threads appear inline beside their source in the main view, anchored
  at the range endpoint. At most one comment is active: focusing its compact
  surface or controls paints its complete stored range but does not expand its
  chronology. Once expanded explicitly, that thread keeps the range painted
  while open. Moving activity to another comment moves the paint
  to that comment's range; clearing comment-system focus/activity removes
  saved-range paint. Inactive saved threads keep only their inline card and no
  range paint. No separate location command is needed.
- Why: The reviewer needs precise requests that remain useful to the working
  model without relying on pane, DOM, SVG, or machine-local path identity, and
  range selection must provide feedback before it commits the reviewer to a
  comment.
- Evidence: owner confirmation on 2026-08-14; rendered-preview anchoring
  deferral confirmed on 2026-08-15.
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
  whether its current placement is exact, relocated, outdated, or unavailable
  whenever that located thread is presented or exported. PR1 preserves but does
  not invent a global fallback panel for a thread that has no renderable inline
  location.
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
  explicit human action resolves or reopens a thread. PR1 preserves session
  lifecycle as durable model state but adds no customer-facing finish/reopen
  chrome.
- Why: Detached is not completed, copied is not resolved, and outdated is not
  detached.
- Evidence: owner confirmation on 2026-08-14, carrying forward the advisory PR1
  distinction.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: completed-session management is outside PR1's visible UI;
  no automatic event changes lifecycle.

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
Copy New or All displayed messages
        +-- changes only included editable messages to locked
        +-- leaves every containing thread open
        `-- never means the requested work was addressed

Resolve whole thread
        `-- explicit reviewer action after inspecting the resulting work
```

### P1-U9 — Produce the displayed New or All saved-message batch

- Affected classes: human reviewer and working agent.
- Need: File View and Review View expose one header-owned, in-layout Share
  comments mode. The reviewer displays either `New` current saved messages or
  `All` current saved messages and produces that complete displayed set as one
  deterministic, model-readable batch. There is no second manual thread or
  message checklist. `New` membership is independent of whether a message is
  editable or locked; `All` includes both new and handled saved messages. Draft
  text never enters either set, so a message with a working draft must be Saved
  or Reverted before its current body can participate.
- Why: The reviewer needs a fast review-level handoff without reproducing the
  inline thread hierarchy as a second selection interface, while explicit Save
  remains the output boundary. The header entry and in-flow Share row must look
  and behave like one shared File/Review toolbar surface: the same compact
  control height, typography, spacing, radius, focus, hover, selected, and
  disabled treatments as adjacent BridgeViewer chrome. Copy and Export are peer
  destinations; neither is promoted as the primary action merely because of its
  position.
- Evidence: owner confirmation on 2026-08-14, the established partial-output
  workflow, and the shared-shadcn visual correction on 2026-08-20.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U10 — Copy a path- and line-oriented Markdown packet

- Affected classes: human reviewer and working agent.
- Need: Clipboard copy groups located threads by repository-relative path and
  source order. Entries contain
  a trustworthy current or explicit original line reference, numbered source
  excerpt, diff side when applicable, placement status, and adjacent Markdown
  thread message. The packet owns one H1, plain field labels, horizontal-rule
  separators, and adaptive fenced source excerpts. Authored message bodies
  remain untouched Markdown and may use H2 through H6.
- Why: The pasted packet must make sense to a model without hidden UI context.
- Evidence: owner confirmation on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U11 — Export the same batch as versioned JSON

- Affected classes: human reviewer and working agent.
- Need: File export writes a versioned, lossless JSON representation of the same
  New or All message-batch semantics used by clipboard Markdown.
- Why: A file output must preserve identities, exact snapshotted content,
  source evidence, ordering, and request bodies without parsing prose.
- Evidence: owner selection of structured file export on 2026-08-14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U12 — Preserve exact successful output history

- Affected class: human reviewer.
- Need: A successful copy or export preserves an immutable ordered snapshot of
  the exact saved message bodies and thread source context used for that action.
  Every included editable message becomes immutable; clarification or correction
  is a new human reply. The successful output marks its exact current saved
  messages handled by default. The success toast and durable output history both
  let the reviewer mark that output's exact saved messages not handled, which
  returns them to `New` without unlocking them or changing historical output.
  After the short success toast disappears, reopening Share comments in either
  File View or Review View exposes the same durable history through a collapsed
  in-flow History disclosure. The reviewer can inspect an attempt there, undo
  handling for an eligible success, and explicitly repeat the exact saved bytes
  of an unknown attempt. History does not require a sidebar, global panel,
  thread command, popover, or persistent session surface.
  Later work does not rewrite the historical batch. Normal Copy and Export
  success show a concise confirmation, close Share comments, and leave every
  containing thread open. A crash-recovered attempt whose external
  outcome cannot be proven remains inspectable as unknown; its messages remain
  locked and its exact bytes may be copied again explicitly. If the external
  effect succeeds but durable finalization fails, Share comments closes with a
  truthful partial-success warning; included messages remain locked and New,
  and the product offers no ordinary retry that could silently duplicate the
  effect.
- Why: The reviewer must be able to determine and reproduce what was prepared
  without claiming that an agent received it.
- Evidence: owner-confirmed PR1 output boundary and the advisory PR1 durable
  batch-history requirement.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U13 — Discover and resume applicable sessions predictably

- Affected class: human reviewer.
- Need: Inline comment admission resolves the applicable session predictably
  without persistent session chrome. With no living applicable session and no
  relevant uncertain candidate, the first non-whitespace annotation edit
  creates a session and root draft in the same motion. With one applicable
  session, admission continues it; with several, admission pauses for explicit
  disambiguation rather than inferring from recency. Any relevant uncertain
  candidate invokes P1-U7's human choice and MUST NOT be bypassed by the
  zero-applicable creation rule. Detached and completed sessions remain durable
  and distinguishable in the data model for later management surfaces.
- Why: Session identity must never be inferred silently from pane recency or
  path coincidence, and inline-comment PR1 must not grow a session-management
  interface.
- Evidence: owner-directed efficiency boundary plus the advisory PR1 session
  requirement; implicit first-annotation creation confirmed on 2026-08-15.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### P1-U14 — Keep every PR1 comment in a flat human-authored thread

- Affected classes: human reviewer and working agent.
- Need: Creating an annotation creates a thread with one root human message.
  Every root message and reply belongs to that thread and may receive a later
  human reply. Replies form one flat chronological sequence; they do not nest.
  A one-message thread shows M1 directly. A thread with two or more messages
  keeps exactly one compact inline projection containing M-summary plus M-last.
  Explicit Expand, Edit, or Reply expands that same Pierre annotation row into
  one timeline containing M-summary followed by M1 through Mn exactly once;
  focus alone does not expand it. Reply and Edit authoring occur at the end of
  that inline timeline. Save or Revert ends editing but keeps the thread
  expanded. Escape during active editing first flushes and exits edit mode
  while leaving the thread expanded; a later Escape collapses it. Outside click
  safely flushes an active draft and collapses the thread. Collapsing returns
  focus to the inline control that invoked the expansion. Pierre remains the
  sole scroll owner and remeasures the expanded row, so later diff rows move
  down and return on collapse; the thread adds no nested scrollbar. The summary
  is presentation, not another message. PR1 has no standalone comments and no
  agent-authored messages.
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
- Missing capabilities: durable sessions, optional autosaved drafts and current
  saved message bodies,
  source-backed human threads shared across both viewers, explicit lifecycle and
  continuity, New/All review-level output scope, deterministic Markdown copy, versioned
  JSON export, and immutable output history.
- Allowed surface: Agent Studio’s existing worktree, File/Review viewer,
  persistence, Markdown, clipboard, and file-export capabilities.
- Protected boundary: PR0 comparison behavior remains authoritative foundation;
  PR1 does not redesign comparison selection or target loading.
- Non-goals: direct or automated agent delivery; agent query, identity,
  authorship, replies, or mutation; agent acknowledgement, retry, reconciliation,
  bindings, providers, Codex App Server, App IPC annotation operations, guided
  review, quick edit, multi-user collaboration, external code-host review,
  issue tracking, arbitrary source editing, DOM/SVG/Mermaid-node anchoring, and
  a new authentication or security system. Thread or message deletion is
  deferred to PR2 with its semantics already decided (open threads, whole
  thread only; resolved threads never). Rendered-Markdown preview selection
  anchoring and a batch save-all-drafts affordance are outside PR1. A comment
  sidebar (the planned follow-up PR for thread navigation), whole-file or
  session-level comment UI, a global review panel, persistent session chrome,
  session finish/reopen management, and a Pierre dependency upgrade are also
  outside PR1; each requires separate work.
- Complexity limit: extend existing owners. A new delivery system, provider
  control plane, collaboration platform, security system, separate physical
  Bridge transport, or exactly-once machinery requires renewed owner approval.
- Acceptable outcome evidence: automated state/format/failure proof; restart and
  recovery state inspection; manual or packaged interaction proof in File View
  and Review View; a real Vite/comm-worker-to-Swift development-backend journey
  for create, flush, Save, projection convergence, and retry/recovery; actual
  clipboard Markdown inspection; actual exported JSON validation; and proof
  that no PR2 capability is required for the loop.

## Confirmed policy decisions

```text
session identity
  one living worktree review round across File View and Review View
  owned by the worktree lineage; workspaces never partition a round
  first non-whitespace annotation edit creates the session when none applies
  and no relevant uncertain candidate requires human choice

durability
  annotation history fails closed on storage corruption
  never silently empty; the reviewer is informed; data held for recovery

continuity
  proven same → continue automatically
  uncertain   → pause and let the reviewer decide
  different lineage → detach without completing the session

draft durability
  empty focus loss/Escape/abandonment creates nothing
  first non-whitespace edit creates a durable draft
  focused typing uses 1-second debounce with 5-second maximum wait
  focus loss, Escape/new range, and explicit Save flush immediately

message content
  savedBody absent + draft present   → new unsaved message
  savedBody present + draft absent   → saved and output-eligible
  savedBody present + draft present  → unsaved edits; Save or Revert first
  Save replaces the one current saved body and clears the draft
  Revert clears the draft or removes a never-saved message

message status
  editable | locked
  prepared output may temporarily block writes without adding a third status

thread history
  every annotation is a thread with a human root message
  replies form one flat chronological sequence
  one message is shown directly
  two or more show compact M-summary + M-last inline
  explicit Expand/Edit/Reply expands the same inline row; focus alone does not
  expanded chronology is M-summary + M1...Mn exactly once, with no nested scroll
  Reply/Edit authoring lives at the end; Save/Revert keeps the row expanded
  Escape exits editing before collapse; outside click safely flushes and
  collapses; focus returns to the invoking inline control
  the summary is not a message
  resolution applies to the whole thread
  successful or crash-unknown output changes each included message to locked
  later clarification is a new human reply

message size
  each root or reply body <= 16 KiB UTF-8
  a thread may contain multiple independently bounded messages

output
  Copy   → deterministic Markdown clipboard packet
           → concise copied toast; Share comments closes; threads stay open
  Export → versioned lossless JSON file; Share comments closes on success
  New    → every new current saved body, whether editable or locked
  All    → every current saved body, whether new/handled or editable/locked
  success → included editable messages lock and exact saved bodies become handled
            by default
  toast and durable history → Mark as not handled returns those exact saved
            bodies to New without unlocking or rewriting history
  failure/cancellation → no new lock or handled transition; Share comments remains

main-view presentation
  located threads → inline beside source
  focused/active compact thread → paint its complete stored range
  inline thread expanded → keep that one thread's range painted
  another thread active → move paint to the new thread's range
  comment activity cleared → clear saved-range paint
  inactive saved thread → endpoint-anchored inline card only
  pending range → Pierre highlight; composer only after endpoint +
  single line → gutter + opens composer directly
  no PR1 global-review panel, whole-file/session comments, or sidebar
  located anchoring uses source/diff line presentation only in PR1

projection presentation
  before first complete read → unknown, never fabricated empty or zero counts
  refreshing/unavailable → retain last complete plus exact command-confirmed result
  committed Save → end editing and keep saved message visible immediately

Share comments chrome
  one shared File/Review BridgeViewer toolbar composition
  New/All → compact segmented control using adjacent viewer semantics
  Copy/Export → peer neutral destinations
  Done → quiet exit action
  History → collapsed in-flow disclosure in both viewers; inspect/unhandle/repeat
```

Exact internal storage, relocation, continuity evidence, transport,
output-effect sequencing, and recovery mechanisms belong to Program Design.
