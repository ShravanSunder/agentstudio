# Worktree Annotations PR1 — Specification

Status: current observable Specification for PR1

Requirements authority:
[`pr1-user-requirements.md`](./pr1-user-requirements.md)

Program Design:
[`pr1-program-design.md`](./pr1-program-design.md)

## Observable outcome

PR1 is complete when a human can create or continue one living annotation
session in File View and Review View, recover unfinished human-message drafts,
explicitly save output-eligible message content, copy any selected saved
messages as a path- and line-oriented Markdown packet, export the same batch as
versioned JSON, return after the worktree changes, and continue or resolve the
inline review threads without any direct agent integration.

```text
inspect source-backed material
  → start an inline human thread, or open its overlay to reply/edit
  → autosave and recover message draft
  → Save intentional message content
  → select saved messages
  → Copy Markdown or Export JSON
  → inspect changed worktree in the same session
  → resolve or continue inline threads; continuity may pause or detach
```

```text
main File / Review view

  drag range ──► Pierre highlight ──► endpoint + ──► inline composer
  hover line ───────────────────────► gutter + ────► inline composer

  Pierre normal flow: exactly one compact located-thread surface
      1 message   ─► M1
      2+ messages ─► M-summary + M-last
      inactive saved thread ─► endpoint-anchored card; no range paint
      focused/active thread ─► paint its complete stored range
      icon-only core commands occupy an independent right column

  explicit Expand / Edit / Reply
      │
      └─► anchored, non-modal, bounded thread overlay
           M1 … Mn + reply/edit authoring
           keep that thread's range painted while open
           no Pierre row-height change

  Copy selected → clipboard → "Copied N comments" toast
                               copy interaction closes
                               threads remain open

No PR1 global-review panel, whole-file/session comments, persistent session
chrome, or comment sidebar exists.
```

## What the inline experience looks like

These wireframes define observable anatomy and hierarchy, not final pixel
values. Radius, avatar/timeline spacing, command placement, and exact token
derivations are tuned against the running Vite and packaged viewers without
changing the relationships shown here.

### Range selection gives feedback before creating anything

```text
Pierre code canvas

  379 │ const selected = comments.filter(isOpen)
  380 │ return selected.map(renderComment)        ╭───╮
  381 │                                           │ + │  click to comment
      ╰──────── highlighted selected range ───────╰───╯

drag ends       → highlight and endpoint + remain; no composer or durable row
click +         → inline composer opens beneath the selected range
new range       → old pending range clears; new range becomes pending
outside/Escape  → pending range clears
```

For one line, hovering the gutter exposes `+`; clicking it opens the same
composer immediately without a separate drag-confirmation step.

### New comment composer

```text
  ◉── You · Draft · saved locally
  │
  │  ╭──────────────────────────────────────────────╮
  │  │ Write Markdown…                              │
  │  │                                              │
  │  │ The body starts at the top and grows with     │
  │  │ content.                                      │
  │  │                                          ↶   │ Revert
  │  │                                          ●   │ Save, primary
  │  ╰──────────────────────────────────────────────╯
       one rounded surface         independent right column
```

The avatar is the left timeline node. Author, time, and thread/message status
occupy its timeline row instead of a separate header or right-aligned date.
The composer is one rounded surface composed from the product's owned shadcn
primitives: its writing area introduces no second card, border, radius, or
divider. Revert and Save are canonical icon-only controls stacked vertically at
the bottom-right. Their column has no visible card and cannot determine the
writing area's height or alignment. Each control has a tooltip and accessible
name. `Draft` plus a warning-semantic cue communicates durability without
relying on color alone. Save is the only primary-treated action; primary
treatment does not require a visible text label.

### Saved one-message thread

```text
  ◉── You · 2m · Saved · Open    Include   Expand   More
  │
  │  ╭──────────────────────────────────────────────╮
  │  │ Please keep source refresh separate.        │
  │  │                                          ✎   │ Edit
  │  │                                          ↩   │ Reply
  │  │                                          ✓   │ Resolve
  │  ╰──────────────────────────────────────────────╯

  resolved state: same thread and history; Resolve becomes Reopen
```

When the thread contains exactly one message, M1 is the inline body; there is
no synthetic summary. The body is top-aligned and content-sized. The right
command column contains exactly Edit, Reply, and Resolve/Reopen, and its height
never sets the body height. Expand is a separate timeline action and is never
implied by focus.

### Compact multi-message thread

```text
  ◉── 3 messages · latest 1m · Open    Include   Expand   More
  │
  │  ╭──────────────────────────────────────────────╮
  │  │ M-summary: 3 messages · latest by You       │
  │  │ M-last: Add coverage for the failure case…  │
  │  │                                          ✎   │ Edit M-last
  │  │                                          ↩   │ Reply
  │  │                                          ✓   │ Resolve
  │  ╰──────────────────────────────────────────────╯
```

For two or more messages, the inline body contains exactly two projections:
M-summary and M-last. M-summary deterministically presents message count, latest
activity, resolution, and any hidden Draft, placement, inclusion, or lock state
needed to avoid a false compact representation. M-last presents a bounded view
of the latest actual message. M-summary is not authored Markdown, not another
message, and not independently selectable or output content. The right command
column contains exactly Edit M-last, Reply, and Resolve/Reopen.

### Floating complete-thread overlay

```text
  ╭─ compact inline anchor (Pierre normal flow) ─────╮
  │ M1  OR  M-summary + M-last                       │
  ╰──────────────────────────────────────────────────╯
                         │ anchored above code;
                         │ Pierre row height unchanged
                         ▼
  ╭─ complete thread overlay ─────── Resolve/Reopen ─╮
  │ M1                                          ✎  ↩ │
  │ ──────────── bounded scroll area ────────────── │
  │ M2                                             ↩ │
  │ …                                                │
  │ Mn                                          ✎  ↩ │
  │ reply/edit composer                         ↶  ● │
  ╰──────────────────────────────────────────────────╯
```

Expand, Edit, or Reply opens the anchored overlay; merely focusing an inline
message or command does not. The overlay is non-modal, bounded in height, and
internally scrollable. It displays M1 through Mn exactly once in flat
chronological order above the compact inline anchor. Opening or closing it does
not change Pierre's annotation-row height or scroll anchor. Each overlay message
exposes Edit when editable and Reply in its right command column. The whole
overlay exposes Resolve/Reopen once for the thread, never once per message.

Reply and Edit authoring live inside the overlay. Save or Revert exits edit mode
and keeps the overlay open so the resulting chronology remains inspectable.
Escape while editing first flushes safely, exits edit mode, and keeps the
overlay open; a later Escape closes it. Outside click safely flushes any active
draft and closes the overlay. Closing returns focus to the exact inline control
that invoked it. When closed, overlay content and controls leave keyboard and
accessibility traversal.

### Collapsed durable draft

```text
  ◉── You · Draft · saved locally
  │  ╭──────────────────────────────────────────────╮
  │  │ Add failure coverage…                  ▶     │ Resume
  │  ╰──────────────────────────────────────────────╯
```

An empty composer disappears. A durable non-empty new-root draft may collapse,
but its text summary, `Draft` label, author, and Resume action remain visible in
the same shell rather than moving to a separate panel. Reply and edit drafts
remain part of their thread overlay contract above.

### Command ownership

```text
M1 right command column
  Edit · Reply · Resolve/Reopen

multi-message compact right command column
  Edit M-last · Reply · Resolve/Reopen

composer right command column
  Revert · Save primary

timeline row
  status · Include/Exclude · Expand · More
  never Edit, Reply, or Resolve/Reopen

overlay message right command column
  Edit when editable · Reply

overlay thread level
  Resolve/Reopen exactly once

output interaction
  Copy selected · Export selected as JSON
```

The core right-column controls are icon-only owned shadcn controls with one
canonical command identity, optical-size rule, tooltip, and accessible name per
action. Save alone receives primary treatment. The timeline uses one Expand
action immediately before More and never duplicates Edit or the other core
commands. Resolve/Reopen never appears as a message mutation, and Copy/Export
never appears as delivery or resolution. The exact glyph and component mapping
may be refined without changing this command ownership or visible hierarchy.

## Consumers and surfaces

```text
Human reviewer
  ├─ File View annotation interaction
  ├─ Review View annotation interaction
  ├─ output-history interaction
  ├─ system clipboard output
  └─ user-selected JSON file output

Working agent
  ├─ pasted Markdown packet
  └─ exported JSON file

Outside the PR1 boundary
  direct delivery · agent mutation · acknowledgement · providers · App IPC
```

File View and Review View remain the only visible viewer surfaces. Annotation
Mode is an interaction state within them, not a third viewer or review
application. PR1 presents only located inline threads in the main viewer; it
does not require or expose a global review panel, whole-file/session comment
surface, persistent session chrome, or comment sidebar.

PR1 uses three distinct terms:

```text
output batch
  immutable selected human-message content

output event
  successful clipboard copy or JSON file export for one output batch

agent handoff
  the reviewer pastes or transfers that output outside Agent Studio
```

An output event never claims that the external agent handoff occurred.

```text
Agent Studio authority                         Outside Agent Studio authority

saved bodies → batch → Copy/Export success    → reviewer transfers output
                         │
                         └→ durable event         recipient may consume it

The durable event proves the left side only. It does not prove transfer,
receipt, acknowledgement, acceptance, or resolution on the right side.
```

## State model visible to the reviewer

### Session lifecycle and source relationship

Session lifecycle and source relationship are independent:

```text
lifecycle:            living | completed
source relationship:  applicable | uncertain | detached

writable = living AND applicable
```

| Lifecycle | Source relationship | Observable result |
| --- | --- | --- |
| living | applicable | annotations may be created or edited |
| living | uncertain | existing work remains readable/exportable; new annotation pauses pending reviewer choice |
| living | detached | existing work remains readable/exportable; new annotation is unavailable for the proven different lineage |
| completed | any | session is read-only until an explicit human reopen action |

Completion does not resolve annotations. Detachment does not complete the
session. Returning source continuity does not automatically reopen a completed
session.

```text
                     source relationship
                 applicable  uncertain  detached
               ┌───────────┬───────────┬───────────┐
living         │ writable  │ readable  │ readable  │
               │           │ paused    │ detached  │
               ├───────────┼───────────┼───────────┤
completed      │ read-only │ read-only │ read-only │
               └───────────┴───────────┴───────────┘

Only explicit session-management actions cross living ↔ completed; PR1 adds no
customer-facing action for that transition.
Continuity assessment moves only across the columns.
```

### Thread and message authoring

```text
new thread composer
  ├─ untouched/whitespace-only
  │    └─ focus loss / Escape / abandoned selection → removed, never durable
  └─ first non-whitespace edit
      → durable root-message draft
          ├─ focus loss → immediate flush; remain visible
          ├─ Escape / new range → immediate flush; collapse
          ├─ Save / Command+Enter → set savedBody; clear draft
          └─ Revert → empty composer

saved root or reply message
  → Edit opens anchored thread overlay
      → optional durable draft beside savedBody
          → Save   → replace savedBody; clear draft; overlay stays open
          → Revert → clear draft; show savedBody; overlay stays open
          → Escape → flush; exit edit mode; overlay stays open

saved root or reply message
  → Reply opens anchored thread overlay
      → durable reply draft in the same flat thread

overlay with no active editor
  → Escape / outside click → close; return focus to inline invoker

overlay with active editor
  → outside click → flush draft; close; return focus to inline invoker

savedBody absent + draft present   → new unsaved message
savedBody present + draft absent   → saved message
savedBody present + draft present  → saved message with unsaved edits

Clearing a never-saved message removes it when flushed. Clearing an existing
saved message persists an empty draft, disables Save, and preserves Revert.

saved message
  → successful Copy or Export
      → status locked
          → Reply → new human-message draft in the same thread
```

Every annotation is a thread with one root human message. Every later PR1
message is a human reply in one flat chronological sequence in that thread;
replies do not nest. Only an `editable` message with a saved body and no draft
may enter output selection. Autosave never changes thread resolution. Thread
resolution is `open | resolved`, applies to the whole thread rather than an
individual message, and changes only through an explicit human action.

```text
thread OPEN
  root savedBody ── successful output ──► root status LOCKED
  reply 1 savedBody ────────────────────► reply 1 status LOCKED
  reply 2 draft ── Save ────────────────► reply 2 savedBody
       │
       ├─ Resolve whole thread ───► thread RESOLVED
       └─ Reopen whole thread  ◀─── explicit reviewer action

Messages stay in one flat chronological sequence. Resolution never belongs to
an individual message.
```

### Annotation placement

Each thread has immutable origin evidence and one current placement result:

| Placement | Observable meaning |
| --- | --- |
| `exact` | the current material proves the annotation still refers to its original location |
| `relocated` | the current material proves a trustworthy corresponding location different from the origin |
| `outdated` | the review subject remains applicable, but no current location can be presented as trustworthy |
| `unavailable` | the source required to evaluate or display placement cannot currently be obtained |

Large source change or relocation failure alone does not detach a session.
Placement never changes immutable origin evidence.

## Normative requirements

### R-P1-001 — One canonical living session

File View and Review View MUST project one canonical annotation session when
they display material admitted by that session. Session identity MUST be owned
by the stable repository/worktree lineage: the same worktree opened from any
workspace MUST resolve to the same session set, and workspace identity MUST NOT
partition, fragment, or duplicate a session. Session identity MUST NOT be
derived from a pane, WebKit instance, worker generation, renderer node, or Zoom
companion. Ordinary edits and comparison-target changes with proven continuity
MUST NOT replace the session.

Basis: P1-U1, P1-U13.

Failure expectation: if no living session applies and no relevant uncertain
candidate exists, the first non-whitespace annotation edit MUST create the
session and root draft in one motion without a separate creation step; if one
applies, inline admission MUST continue it without persistent session chrome;
if several apply, admission MUST require an explicit bounded choice rather than
infer one from recency. A relevant uncertain candidate MUST invoke R-P1-008's
reviewer choice before admission and MUST NOT be treated as the zero-session
case.

Uncertain, detached, and completed sessions MUST remain durable and distinctly
represented in canonical state. PR1 MUST NOT add persistent session-selection,
finish, reopen, or history chrome; an ambiguity choice may appear only when
several applicable sessions or relevant uncertain continuity blocks inline
comment admission.

### R-P1-002 — Located inline annotation admission

PR1 MUST admit only located annotations carrying a repository-relative path,
source line or contiguous source-line range, source role sufficient to
distinguish a current file or diff side, immutable source/version evidence, and
selected source excerpt.

Located selection MUST come from the source or diff line presentation;
Markdown files remain annotatable in that presentation. A dragged range MUST
remain visibly selected without opening a composer. The composer MUST open only
after the reviewer clicks the range endpoint `+`. Selecting another range,
clicking outside, or pressing Escape before that action MUST clear the pending
range. Hovering one source line MUST expose a gutter `+` whose activation opens
a single-line composer directly.

Rendered-Markdown preview selection is not a PR1 admission source. PR1 MUST
reject an annotation that has only absolute path, pane, DOM, SVG,
rendered-pixel, or Mermaid-node identity. Located threads with trustworthy
current placement MUST render inline beside that source in the main File or
Review view. Placement and immutable origin MUST remain durable when an inline
slot is unavailable; PR1 MUST NOT invent a global fallback panel or fabricated
line slot.

An inactive saved thread MUST retain its inline annotation card anchored at its
range endpoint and MUST NOT keep its source range painted. Focusing or otherwise
activating a compact thread surface or one of its controls MUST paint that
thread's complete stored range through Pierre's `selectedLines` presentation.
While any saved comment is active, exactly that one comment's range MUST be
painted; otherwise no saved comment range may be painted. Activating another
thread MUST move the paint to that thread's range, and clearing comment-system
focus and active state MUST clear saved-range paint. While a thread's
complete-thread overlay remains open, its range MUST remain the one painted
range. Focus alone MUST NOT open that overlay. The inline surface MUST NOT add a
separate location command.

Basis: P1-U5.

### R-P1-003 — First-non-empty durable draft

Opening an empty new-message composer MUST create no durable message. Its first
non-whitespace edit MUST create a durable working message draft. Clearing that
never-saved message back to empty MUST remove it when the change is flushed. An
existing saved message's first changed edit MUST create a draft even when the
new body is empty, because that empty working edit must survive recovery and
remain Revertible. While the composer remains focused, changed draft content
MUST be scheduled for persistence one second
after the latest edit and MUST be persisted at least once every five seconds
during continuous editing. Losing composer focus MUST request an immediate
flush of current draft content. An untouched or whitespace-only composer MUST
disappear on focus loss, Escape, or selection abandonment without creating a
thread or message. Escape or admission of another range while a non-empty
new-root draft is expanded MUST request an immediate flush and collapse that
composer; focus loss after non-empty input MUST flush but leave the draft
visible. Reply and edit composers MUST instead follow R-P1-016's overlay close
sequence.

From the first non-whitespace edit through every committed projection update,
the same visible editor, local text, focus, and containing thread MUST remain
continuous. If replacement thread state arrives in parts, the UI MUST keep the
last complete demanded thread visible until its complete replacement is ready;
it MUST NOT expose a temporary empty or partial projection that unmounts the
editor, loses the first character, releases editing authority, or creates a
duplicate reply.

Basis: P1-U2, P1-U3.

Failure expectation: after restart, the reviewer MUST see the latest completely
persisted draft. A hard failure may lose an edit whose persistence had not
completed, but MUST NOT lose an earlier completed flush. A successful first
draft commit MUST NOT cause even a transient disappearance, replacement, or
focus loss of the editor or containing thread.

### R-P1-004 — Explicit message Save and Revert

Save MUST first flush the current message draft and then atomically replace the
message's one current saved body and clear the draft. PR1 MUST NOT retain a
pre-output history of earlier saved bodies. Revert on an existing saved message
MUST clear its draft and restore presentation of the current saved body. Revert
on a never-saved message MUST remove its draft and unsaved message. Pane closure,
focus loss,
autosave, copy, export, placement change, and restart MUST NOT perform Save.
Command+Enter MUST invoke Save; Enter and Shift+Enter MUST insert a newline.

Basis: P1-U3.

Failure expectation: failed Save MUST leave both the recoverable draft and
current saved body unchanged and MUST visibly report that Save did not complete.

### R-P1-005 — Safe Markdown bodies

Message bodies MUST preserve authored Markdown source and MUST render using
the product’s safe Markdown vocabulary. H2 through H6 headings MUST be admitted;
H1 and raw HTML MUST be rejected or prevented before Save. Clipboard rendering
MUST preserve the annotation’s Markdown meaning without allowing its headings
to replace the packet or file hierarchy.

Each root or reply body MUST be at most 16 KiB of UTF-8. The limit applies to
the optional draft and current saved body independently, not to the whole thread. An
oversized edit MUST be visibly rejected without discarding the editor's unsent
text. A thread MAY contain multiple messages and exceed 16 KiB in total.

Basis: P1-U4.

### R-P1-006 — Message content, draft, and status

Each message MUST contain one optional current saved body, one optional durable
draft, and one status of `editable | locked`. The combinations mean:

```text
saved body   draft      meaning
absent       absent     no durable message; invalid stored state
absent       present    new unsaved message
present      absent     saved message
present      present    saved message with unsaved edits
```

A never-saved draft MUST contain non-whitespace content; clearing it removes the
unsaved message when flushed. An existing saved message MAY retain an empty
draft so clearing the editor is durable; Save remains unavailable while the
body is invalid and Revert remains available.

The UI MUST distinguish a draft from the saved body and offer Save and Revert.
Output selection MUST admit only an `editable` message whose saved body is
present and whose draft is absent. It MUST NOT silently output a prior saved
body while unsaved edits exist. Draft state MUST use a visible text label and a
warning-semantic cue, never color alone. Successful or crash-unknown output
MUST change included messages to `locked`; locked messages cannot be edited or
selected again, but their threads remain replyable.

Basis: P1-U3, P1-U9.

### R-P1-007 — Independent placement and thread resolution

The UI MUST expose each thread’s `exact`, `relocated`, `outdated`, or
`unavailable` placement separately from its `open` or `resolved` state.
Placement changes MUST NOT resolve or reopen a thread. Only explicit human
actions may resolve or reopen the whole thread in PR1. Individual messages MUST
NOT carry independent resolution state.

Source-range paint MUST represent only the one currently active/focused comment
or overlay-open thread; it MUST NOT encode open/resolved state or persist merely
because a saved thread is visible. Moving or clearing that paint MUST remain a
presentation-only change and MUST NOT change placement or resolution.

Basis: P1-U6, P1-U8.

### R-P1-008 — Continuity assessment and reviewer authority

When session continuity is proven, the session MUST remain applicable
automatically regardless of change size. When continuity is uncertain, the
session MUST preserve existing work, pause new annotation, explain the
uncertainty, and let the reviewer continue the session or leave it paused and
start another. When repository/worktree lineage is proven different, the session MUST become
detached from that source without becoming completed or changing annotation
resolution.

Basis: P1-U7, P1-U8.

Failure expectation: matching paths or branch labels alone MUST NOT be
presented as proof of continuity. A continuity-evaluation failure MUST become
`uncertain`, not silently `applicable` or `detached`.

### R-P1-009 — Preserve session lifecycle without session-management UI

Living/completed lifecycle and open-thread counts MUST remain durable canonical
facts and MUST NOT be changed by Save, Copy, Export, placement updates, or
thread resolution. PR1 MUST NOT expose customer-facing session finish/reopen,
session-history, or open-thread warning chrome. This prohibition does not remove
R-P1-013's output-event history interaction. A completed session remains
read-only; its management surface is follow-up scope.

Basis: P1-U8.

### R-P1-010 — Deterministic batch snapshot

The reviewer MUST be able to select any non-empty subset of eligible saved
human messages or all eligible saved messages. Eligibility requires status
`editable`, a present saved body, and no draft. Invoking Copy or Export MUST
construct one immutable batch snapshot containing the exact selected message
identities, saved bodies, immutable origins, trustworthy current
thread-placement summaries, source excerpts, thread-resolution states, and
deterministic order.

The order MUST group located threads by repository-relative path, then use the
trustworthy current line or original line when no current line is trustworthy,
and finally stable thread and message identity. Later message edits or
thread-placement changes MUST NOT alter the batch.

```text
selection
   │ validate editable + savedBody present + draft absent
   ▼
snapshot exact saved bodies + source context + thread state
   │ deterministic order
   ├─► Markdown projection ──► native clipboard effect
   └─► JSON projection     ──► native save-panel/file effect

Both projections consume the same immutable snapshot; neither rebuilds the
selection independently.
```

Basis: P1-U9, P1-U12.

### R-P1-011 — Markdown clipboard contract

Copy MUST render the batch as deterministic model-readable Markdown. The packet
MUST include:

- review/session label and safe worktree/comparison context;
- one section per repository-relative path;
- current line/range when trustworthy, otherwise an
  explicit original line/range;
- placement status and diff side when applicable;
- a source excerpt whose lines carry visible line numbers;
- the adjacent transformation request with Markdown meaning preserved.

The packet MUST own exactly one H1. Generated context MUST use plain field
labels and `---` separators rather than generated H2-H6 headings. Authored
message bodies MUST be inserted as unchanged Markdown source and may use H2
through H6, lists, tables, blockquotes, links, and fenced code. Generated source
excerpts MUST choose a fence longer than any matching fence in the excerpt.

An outdated or unavailable thread MUST explicitly tell the recipient to
verify the current location. Generated packet fields MUST NOT contain an
absolute local filesystem path or claim agent receipt. Authored Markdown is
preserved unchanged even when the human wrote text that resembles an absolute
path; the projector MUST NOT silently rewrite message content.

Basis: P1-U10.

Example shape:

````markdown
# Worktree annotation batch

Session: Review current implementation
Worktree: `agent-studio.review-comments`

---

File: `Sources/App/ReviewView.swift`
Location: lines 84–91
Placement: relocated
Side: new

Source:

```swift
84 │ private func refreshReview() {
85 │     reviewSource.reload()
86 │ }
```

Request:

## Separate source refresh from presentation

- Preserve the current owner.
- Add failure coverage.
````

### R-P1-012 — Versioned JSON file contract

Export MUST write a versioned JSON document representing the same batch
semantics and order as R-P1-010. The document MUST preserve full thread and
message identities, raw snapshotted Markdown bodies, immutable origins,
thread-placement summaries, source excerpts and roles, thread-resolution state,
session context, batch identity, format version, and creation time without
requiring Markdown parsing.

PR1 emits exactly `agentstudio.worktree-annotations.batch` format version `1`.
The following closed shape is the authoritative v1 contract; every shown field
is required, every object rejects unknown fields, and a union member admits
only the fields shown for that member.

```text
WorktreeAnnotationBatchV1 = {
  schema: "agentstudio.worktree-annotations.batch"
  formatVersion: 1
  batchId: UUIDv7 string
  createdAt: RFC 3339 UTC string
  session: {
    sessionId: UUIDv7 string
    label: non-empty string
    repositoryId: non-empty string
    worktreeId: non-empty string
    lifecycle: "living" | "completed"
    sourceRelationship: "applicable" | "uncertain" | "detached"
  }
  entries: non-empty ordered array of BatchEntryV1
}

BatchEntryV1 = {
  batchOrdinal: non-negative integer
  thread: {
    threadId: UUIDv7 string
    resolution: "open" | "resolved"
    origin: OriginV1
    placement: PlacementV1
  }
  message: {
    messageId: UUIDv7 string
    messageOrdinal: non-negative integer
    author: { kind: "human" }
    savedRevision: positive integer
    bodyMarkdown: string with 1...16384 UTF-8 bytes
  }
}

OriginV1 = {
  path: repository-relative path string
  source: SourceV1
  startLine: positive integer
  endLine: positive integer
  excerpt: non-empty ordered array of {
    lineNumber: positive integer
    text: string
  }
}

SourceV1 =
  { kind: "file"; sourceIdentity: non-empty string }
  | {
      kind: "diff"
      side: "old" | "new"
      sourceIdentity: non-empty string
      comparisonOrigin: ComparisonOriginV1
    }

ComparisonOriginV1 = {
  kind: "contribution"
  baseRole: "commonCommit" | "selectedTarget"
  comparedRole: "capturedWorkingTree"
  symbolicTarget: ComparisonTargetV1
  resolvedTargetOID: non-empty string
  reviewedHeadOID: non-empty string
  baseOID: non-empty string
}

ComparisonTargetV1 =
  { kind: "localDefaultBranch"; basis: "commonCommit" | "branchTip";
    branchName: non-empty string }
  | { kind: "originDefaultBranch"; basis: "commonCommit" | "branchTip";
      branchName: non-empty string; remoteName: non-empty string }
  | { kind: "branch"; basis: "commonCommit" | "branchTip";
      name: non-empty string }
  | { kind: "commit"; oid: 40- or 64-character hexadecimal string }
  | { kind: "ref"; basis: "commonCommit" | "branchTip";
      name: non-empty string }

CoordinateV1 = {
  path: repository-relative path string
  source: SourceV1
  startLine: positive integer
  endLine: positive integer
}

PlacementV1 =
  { status: "exact"; current: CoordinateV1 }
  | { status: "relocated"; current: CoordinateV1 }
  | { status: "outdated"; current: null }
  | { status: "unavailable"; current: null }
```

Array order is batch order and `batchOrdinal` MUST equal the zero-based array
index. Message identities MUST be unique. Repeated thread identities MUST carry
byte-equivalent thread context. `startLine` MUST be less than or equal to
`endLine`; excerpt line numbers MUST be strictly increasing and include the
selected origin range. Paths MUST be repository-relative. The exact v1 shape
uses no optional properties: variant-only data lives only on its discriminated
union member, and semantic absence is the required JSON value `null`.

Representative complete document:

```json
{
  "schema": "agentstudio.worktree-annotations.batch",
  "formatVersion": 1,
  "batchId": "0198f0b4-6d66-7e42-9a2c-621d34e37f9f",
  "createdAt": "2026-08-16T18:42:00Z",
  "session": {
    "sessionId": "0198f0a8-2e30-7f2d-ae34-1b28b52e10fa",
    "label": "Review current implementation",
    "repositoryId": "repo-agent-studio",
    "worktreeId": "worktree-review-comments",
    "lifecycle": "living",
    "sourceRelationship": "applicable"
  },
  "entries": [
    {
      "batchOrdinal": 0,
      "thread": {
        "threadId": "0198f0b0-d129-7bdd-86f6-b9e96747d5fd",
        "resolution": "open",
        "origin": {
          "path": "Sources/App/ReviewView.swift",
          "source": {
            "kind": "file",
            "sourceIdentity": "sha256:4b30d9f3"
          },
          "startLine": 84,
          "endLine": 86,
          "excerpt": [
            { "lineNumber": 84, "text": "private func refreshReview() {" },
            { "lineNumber": 85, "text": "    reviewSource.reload()" },
            { "lineNumber": 86, "text": "}" }
          ]
        },
        "placement": {
          "status": "relocated",
          "current": {
            "path": "Sources/App/ReviewView.swift",
            "source": {
              "kind": "file",
              "sourceIdentity": "sha256:6c620871"
            },
            "startLine": 91,
            "endLine": 93
          }
        }
      },
      "message": {
        "messageId": "0198f0b2-5518-7776-bf53-e725b2b465d2",
        "messageOrdinal": 0,
        "author": { "kind": "human" },
        "savedRevision": 1,
        "bodyMarkdown": "## Keep refresh asynchronous\n\nPreserve the current owner."
      }
    }
  ]
}
```

An unsupported format version, missing required field, invalid discriminant,
unknown field, duplicate identity, inconsistent repeated-thread context, or
order/membership inconsistency MUST be rejected rather than partially
interpreted by contract validation. PR1 emits one version and defines no JSON
import UI or cross-version compatibility promise.

Basis: P1-U11.

### R-P1-013 — Output success and immutable output history

A successful clipboard replacement or completed file write MUST create durable
output history for the exact immutable batch and output kind and MUST make every
included message immutable. History MUST allow the reviewer to inspect and
reproduce the original output semantics. It MUST NOT mark any thread or message
delivered, acknowledged, accepted, or resolved. Later clarification MUST be a
new human reply in the same thread.

After normal Copy success, the UI MUST show a concise `Copied N comments`
confirmation using the product-owned shadcn-style toast presentation, close the
copy interaction, and leave every containing thread open and visible. Copy MUST
NOT resolve, collapse, or hide a thread and MUST NOT claim that an agent
addressed it.

Generation or validation failure MUST cause no clipboard/file effect and no
history entry. User-cancelled file selection MUST cause neither a file nor
history entry. If an external output succeeds but durable history subsequently
fails, the UI MUST report partial success accurately and MUST NOT claim that
history was recorded.

If restart recovers a prepared attempt whose clipboard/file outcome cannot be
proven, history MUST show the attempt as `unknown`, included messages MUST stay
immutable, and the exact bytes MUST remain available for an explicit Copy or
Export repetition. Recovery MUST NOT automatically replay the external effect
or invent success/failure. The history UI MUST expose inspection and explicit
repetition without forcing a recovery-choice modal.

```text
prepared batch
    +-- effect fails --------> no event; preparation cancelled
    +-- effect + finalize ---> successful event; status = locked
    `-- crash, result unknown -> unknown history; status = locked
                                explicit exact-byte repetition only

No output branch changes thread resolution.
```

Basis: P1-U12, P1-U14.

### R-P1-014 — Cross-view convergence and recovery

A saved message, draft update, thread-resolution change, session lifecycle
change, or successful output-history entry from one open viewer MUST become
visible in every other open viewer of the same session without creating an
independent copy. Reopening after restart MUST restore the same session
identity, saved messages, recoverable drafts, thread resolution, immutable
origins, and output history. Rebuildable placement may be recomputed and MUST
remain explicitly unavailable until trustworthy.

Basis: P1-U1, P1-U2, P1-U6, P1-U8, P1-U12, P1-U14.

### R-P1-015 — PR1 stop line

Every requirement above MUST be satisfiable when no agent integration,
delivery target, provider, authorization binding, acknowledgement state,
reconciliation state, Codex process, or annotation App IPC operation exists.

Basis: all P1-U rows and the confirmed PR1/PR2 boundary.

### R-P1-016 — Human-only threaded replies

Creating an annotation MUST create one thread with one root human message.
Every PR1 reply MUST be human-authored, belong to an existing thread, and appear
in one flat chronological sequence; replies MUST NOT nest. Every saved root or
reply message MUST be replyable, including after it becomes immutable through
successful output. PR1 MUST expose no agent author, reply, query, or mutation
behavior.

A thread containing exactly one message MUST render M1 directly in its one
compact inline surface. A thread containing two or more messages MUST render
exactly M-summary plus M-last in that same compact surface; it MUST NOT render
M1 through Mn as stacked content in Pierre normal flow. M-summary MUST derive
deterministically from the current thread projection and identify message
count, latest activity, resolution, and any hidden Draft, placement, inclusion,
or lock state needed to avoid a false compact representation. It MUST NOT
become a stored, selectable, exportable, or replyable message. M-last MUST
remain the projection of the actual latest message.

The inline surface MUST own one rounded visual boundary composed from the
product's owned shadcn primitives. Its message body MUST be top-aligned and
content-sized; the vertically stacked right command column MUST NOT determine
body height. The M1 right column MUST contain exactly Edit M1 when M1 is
editable, Reply, and Resolve/Reopen. The multi-message right column MUST contain
exactly Edit M-last when M-last is editable, Reply, and Resolve/Reopen. Composer
right columns MUST contain Revert and the primary-treated Save. These core
controls MUST be icon-only controls with a canonical identity, tooltip, and
accessible name. The separate timeline row MUST own status, contextually
available Include/Exclude, Expand, and More; it MUST NOT duplicate Edit, Reply,
or Resolve/Reopen, and Expand MUST appear immediately before More.

Explicit activation of Expand, Edit, or Reply MUST open an anchored, non-modal,
bounded-height, internally scrollable overlay above the compact inline anchor;
focus alone MUST NOT open it. Focus on the compact surface or any of its controls
MUST instead activate that thread and paint its complete stored range without
changing Pierre row height. An open overlay MUST keep its thread active and its
range painted while focus moves within the overlay. The overlay MUST expose M1
through Mn exactly once in flat chronological order and MUST NOT change Pierre's
annotation-row height or scroll anchor. Each overlay message's right column MUST
expose Edit when that message is editable and Reply. Resolve/Reopen MUST appear
once at overlay thread level and continue to affect the whole thread only.
Threads MUST remain independently openable and resolvable when several thread
projections share one physical annotation row or source coordinate.

Reply and Edit authoring MUST occur in the overlay. Save or Revert MUST exit
editing while leaving the overlay open. Escape during editing MUST first flush
the active draft, exit edit mode, and leave the overlay open; a later Escape
MUST close it. Outside click MUST safely flush an active draft and close the
overlay. Closing MUST return focus to the exact inline control that opened it.
Expand, Edit, Reply, and overlay controls MUST be keyboard operable, and closed
overlay content MUST NOT remain in keyboard or accessibility traversal.

Basis: P1-U14 and the confirmed PR1/PR2 boundary.

### R-P1-017 — Bounded complete-message transport

Every browser-to-native mutation and native-to-browser projection MUST carry
each admitted message as one complete unit. A message MUST NOT be split or
reassembled across physical frames. Multiple complete messages MAY be packed
dynamically while the encoded frame remains within the existing 128 KiB wire
bound. If the next complete message would exceed the frame, it MUST begin the
next frame. Clipboard and JSON output size is not limited by the physical frame
bound.

Basis: P1-U4, P1-U14 and the existing Bridge wire limit.

```text
message bodies (each <= 16 KiB)
     |
     v
dynamic complete-message packing
     +-- frame 1 <= 128 KiB encoded
     +-- frame 2 <= 128 KiB encoded
     `-- never split one message
```

## Observable output contracts

### Clipboard Copy

| Contract slot | PR1 behavior |
| --- | --- |
| Consumer | human reviewer and pasted-text recipient |
| Input | one non-empty deterministic selection of editable messages with saved bodies and no drafts |
| Success | packet replaces clipboard; exact history is recorded; copied toast appears; copy UI closes; threads remain open |
| Empty selection | action is unavailable or rejected without effect |
| Generation/validation failure | no clipboard mutation and no history |
| Clipboard succeeds/history fails | visible partial success; clipboard content remains; no false history claim |
| Recovered unknown attempt | inspectable unknown history; messages locked; exact bytes may be copied again only by explicit action |
| Cancellation | not applicable after invocation |
| Compatibility | Markdown is model-readable output, not a machine parsing contract |

### JSON File Export

| Contract slot | PR1 behavior |
| --- | --- |
| Consumer | human reviewer and structured-file recipient |
| Input | one non-empty deterministic selection of editable messages with saved bodies and no drafts, plus a user-selected destination |
| Success | one complete versioned JSON file is present and exact batch history is recorded |
| User cancellation | no output file and no history |
| Generation/validation failure | no output file and no history |
| File succeeds/history fails | visible partial success; file remains; no false history claim |
| Compatibility | unsupported format versions fail closed; PR1 makes no cross-version compatibility promise |

## Reliability and quality obligations

- Durable reviewer work MUST survive normal restart and recover from the latest
  completed draft flush after abnormal termination.
- Draft persistence MUST remain bounded by the one-second debounce and
  five-second maximum wait while focused; focus loss and Save request immediate
  flushes.
- Each message body MUST remain within 16 KiB UTF-8 and complete messages MUST
  fit dynamically into 128 KiB encoded transport frames without chunking.
- A failed mutation MUST preserve the last complete durable state and MUST NOT
  publish a newer live state as successful.
- Migration, database-corruption, or hydration failure MUST expose annotation
  state as unavailable, MUST inform the reviewer, and MUST NOT publish a
  fabricated empty replacement. Annotation history fails closed: recovery MUST
  preserve the affected database content for later recovery, and the
  default-and-continue recovery used by UX/cache lanes MUST NOT apply to
  annotation data. An empty annotation state after recovery MUST be
  distinguishable from "no annotations ever existed." After quarantine and
  replacement, annotation state MUST remain visibly recovered-degraded and
  MUST reject annotation mutations until the reviewer explicitly acknowledges
  continuing from the fresh database. Acknowledgement MAY clear the warning and
  permit new annotation work, but MUST NOT delete the durable recovery witness
  or quarantined database files.
- Generated clipboard and file fields MUST never include absolute local paths,
  secret material, agent credentials, or provider-native identifiers. Authored
  Markdown remains verbatim and is not treated as a generated field.
- Markdown rendering MUST use the existing safe-rendering posture and MUST not
  admit raw HTML through message bodies.
- File View and Review View MUST expose equivalent annotation semantics and
  keyboard/focus accessibility for shared actions.
- PR1 introduces no external network dependency and MUST remain useful offline
  against locally available worktree and repository evidence.

## Explicit negative space

PR1 does not define or imply:

- direct Send or terminal injection;
- sent, received, acknowledged, accepted, retrying, reconciling, or delivered
  annotation state;
- agent-authored threads, messages, replies, resolution, or mutation;
- agent identity, authorization binding, provider target, Codex App Server, or
  annotation App IPC operations;
- guided review, quick edit, multi-user collaboration, code-host review, issue
  tracking, or source mutation through the annotation interface;
- DOM, rendered-pixel, SVG, Mermaid-node, or arbitrary non-text-region anchors;
- rendered-Markdown preview selection anchoring (source-map machinery is a
  deferred follow-up; located admission uses source/diff line presentation);
- thread or message deletion (deferred to PR2 with decided semantics: open
  threads, whole thread only; resolved threads never deletable);
- a batch save-all-drafts affordance;
- a third visible viewer surface or separate physical Bridge transport;
- a global/general-review panel, whole-file or session-level comment UI,
  persistent session chrome, or a comment sidebar (the planned follow-up PR
  owning thread navigation);
- customer-facing session finish/reopen/session-history or open-thread warning
  UI; output-event history remains required by R-P1-013;
- a Pierre dependency upgrade; 1.3.5 is stable follow-up work, not part of PR1.

Stable session, thread, message, and batch identities; immutable
origins; deterministic ordering; and versioned JSON are PR1 facts. They are not
authorization to prebuild PR2 delivery machinery.

## Requirement-to-proof coverage

| Requirements | Required evidence class |
| --- | --- |
| R-P1-001, R-P1-008, R-P1-009 | automated lifecycle/thread behavior plus manual cross-view interaction |
| R-P1-002, R-P1-007 | automated selection/admission and placement-state behavior using real source evidence plus manual pending-range and endpoint/gutter `+` proof; focus each compact thread and its controls, move activity between threads, keep overlay activity, and clear comment activity to prove exactly one full stored range is painted through `selectedLines`, inactive cards retain no range paint, and no location command exists |
| R-P1-003, R-P1-004, R-P1-006 | automated draft/save/revert behavior with controlled time and restart state inspection, plus a real-thread Reply/Edit projection-reconciliation case proving the first character, editor identity, local value, focus, containing thread, and single editing authority remain continuous while state and content updates arrive separately |
| R-P1-005, R-P1-017 | automated Markdown/size/frame admission plus manual visual inspection and boundary rejection |
| R-P1-010, R-P1-011 | deterministic snapshot/Markdown behavior plus actual clipboard inspection |
| R-P1-012 | schema validation, encode/decode, malformed-input, and unsupported-version evidence |
| R-P1-013 | automated failure/partial-success behavior plus actual file/clipboard effect inspection |
| R-P1-014 | integration behavior across File/Review and restart with canonical state inspection |
| R-P1-016 | automated M1-only and M-summary-plus-M-last inline rendering, focus activation without overlay expansion, overlay-retained active range, overlay-only flat chronology, unchanged Pierre row height/scroll anchor, exact command ownership, independent same-coordinate threads, overlay authoring, Escape/outside-click/focus-return behavior, and closed-overlay accessibility exclusion plus manual File/Review, narrow-width, 200% text, reduced-motion, and packaged VoiceOver interaction |
| R-P1-015 | dependency/surface inspection proving the complete journey without PR2 machinery |
| Reliability obligations | corrupt-local-database recovery proving visible pre-acknowledgement degradation, rejected mutations, retained recovery witness, and retained quarantined files |

Packaged interaction proof MUST demonstrate the complete human journey in both
viewers, including drag feedback without composer creation, endpoint and
single-line gutter `+` admission, empty-composer dismissal, non-empty draft
collapse/recovery, first Reply/Edit character continuity without editor remount,
M1-only inline rendering, M-summary plus M-last inline rendering, overlay-only
M1-through-Mn chronology, independent overlays for same-coordinate threads,
keyboard Save/newline/overlay behavior, exact timeline/right-column commands,
top-aligned content-sized bodies, and one rounded shared-shell visual quality.
It MUST prove that focus activates but does not expand a compact comment, an
open overlay retains its range, activity moves paint to another complete stored
range, clearing comment activity removes range paint, and inactive saved
threads retain only endpoint-anchored cards. It MUST inspect actual clipboard
Markdown and JSON export, then demonstrate worktree change, placement
degradation, explicit whole-thread resolution, and restoration. Opening and closing the
overlay MUST leave Pierre row height and scroll anchoring unchanged, with no
clipping, overlap, editor disappearance, first-character loss, persistent
flicker, duplicate reply, or competing scroll writer.

## Traceability

```text
P1-U1  → R-P1-001, R-P1-014
P1-U2  → R-P1-003, R-P1-014
P1-U3  → R-P1-003, R-P1-004, R-P1-006
P1-U4  → R-P1-005, R-P1-017
P1-U5  → R-P1-002
P1-U6  → R-P1-007, R-P1-014
P1-U7  → R-P1-008
P1-U8  → R-P1-007, R-P1-008, R-P1-009, R-P1-014
P1-U9  → R-P1-006, R-P1-010
P1-U10 → R-P1-011
P1-U11 → R-P1-012
P1-U12 → R-P1-010, R-P1-013, R-P1-014
P1-U13 → R-P1-001
P1-U14 → R-P1-013, R-P1-014, R-P1-016, R-P1-017
all    → R-P1-015
```

## Structural constraints

The linked Program Design defines these internal boundaries without changing
this observable contract:

- canonical feature-state, persistence, and App-composed native-effect owners;
- stable identities, saved-body/optional-draft/status representation, and transaction
  boundaries;
- source-origin capture, placement evaluation, and continuity-evidence policy;
- cross-view publication and restart recovery;
- deterministic Markdown/JSON batch construction and native output sequencing;
- proof seams for controlled autosave time, failure, partial external effects,
  actual clipboard/file output, and packaged File/Review behavior.
