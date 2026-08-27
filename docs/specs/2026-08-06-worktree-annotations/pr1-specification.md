# Worktree Annotations PR1 — Specification

Status: current observable Specification for PR1

Requirements authority:
[`pr1-user-requirements.md`](./pr1-user-requirements.md)

Program Design:
[`pr1-program-design.md`](./pr1-program-design.md)

## Observable outcome

PR1 is complete when a human can create or continue one living annotation
session in File View and Review View, recover unfinished human-message drafts,
explicitly save output-eligible message content, display the current saved
messages under `New` or `All`, copy that displayed set as a path- and
line-oriented Markdown packet, export the same batch as
versioned JSON, return after the worktree changes, and continue or resolve the
inline review threads without any direct agent integration.

```text
inspect source-backed material
  → start an inline human thread, or expand it to reply/edit
  → autosave and recover message draft
  → Save intentional message content
  → open Share comments and display New or All saved messages
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
      └─► expand the same Pierre annotation row
           M-summary + M1 … Mn exactly once + reply/edit authoring
           keep that thread's range painted while open
           Pierre remeasures the row; no nested thread scrollbar

  Copy/Export displayed set → effect succeeds → success toast
                                                 Share comments closes
                                                 handled by default
  toast/history → Mark as not handled → exact saved bodies return to New

  Share comments reopened after toast
      └─► collapsed in-flow History disclosure
             inspect exact attempt
             successful attempt → Mark as not handled
             unknown attempt    → explicit exact-byte Repeat

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
  ◉── 1 annotation · Open                    Reply · Resolve
  │
  │  ╭──────────────────────────────────────────────╮
  │  │ Please keep source refresh separate.        │
  │  │                                          ✎   │ Edit
  │  ╰──────────────────────────────────────────────╯

  resolved state: same thread and history; Resolve becomes Reopen
```

When the thread contains exactly one message, M1 is the inline body; there is
no synthetic message summary. The stable thread header presents one annotation
count, status, Reply, and primary-tint Resolve/Reopen. The body is top-aligned
and content-sized. Its annotation-local command column contains only Edit when
M1 is human-authored and editable, and its height never sets the body height.
Clicking non-interactive body content or pressing Enter on the focused message
begins Edit. A one-message thread has no disclosure control; focus never implies
expansion.

### Compact multi-message thread

```text
  ◉── 3 annotations · latest 1m · Open     Expand · Reply · Resolve
  │
  │  ╭──────────────────────────────────────────────╮
  │  │ M-summary: 3 annotations · latest by You    │
  │  │ M-last: Add coverage for the failure case…  │
  │  │                                          ✎   │ Edit latest
  │  ╰──────────────────────────────────────────────╯
```

For two or more messages, the inline body contains exactly two projections:
M-summary and M-last. M-summary deterministically presents annotation count, latest
activity, resolution, and any hidden Draft, placement, or lock state
needed to avoid a false compact representation. M-last presents a bounded view
of the latest actual message. M-summary is not authored Markdown, not another
message, and not independently selectable or output content. The thread header
contains one Reply and one primary-tint Resolve/Reopen. The M-last
annotation-local command column contains only Edit when it is human-authored
and editable. Body click and focused Enter also edit M-last.

### Expanded inline complete thread

```text
  ◉── 3 annotations · latest 1m · Open   Collapse · Reply · Resolve
  │
  ◉── M1                                         ✎
  │   First message
  │
  ◉── M2                                         ✎
  │   Intermediate message
  │
  ◉── M-last                                     ✎
  │   Latest message
  │
  ◉── Draft reply                              ↶  ✓
      Reply with Markdown
```

Expand, body/Edit, or Reply expands the same inline annotation row; merely focusing
an inline message or command does not. The expanded row displays M-summary and
M1 through Mn exactly once in one flat timeline. The compact M-last DOM remains
the same keyed message when expansion adds the missing earlier messages. Pierre
remeasures the annotation row and remains the sole scroll owner, so later diff
rows move down without a nested thread scrollbar. Every expanded
human-authored editable message exposes Edit in its annotation-local command
column and supports guarded body-click or focused Enter editing. Reply and
Resolve/Reopen remain singular thread-header commands, never independent
message states.

Reply and Edit authoring live at the end of the expanded inline timeline. Save
or Revert exits edit mode and keeps the thread expanded so the chronology
remains inspectable. Escape while editing first flushes safely, exits edit mode,
and keeps the thread expanded; a later Escape collapses it. Outside click safely
flushes any active draft and collapses the thread. Collapsing returns focus to
the exact inline control that invoked it. When collapsed, hidden chronology and
controls leave keyboard and accessibility traversal. Long-thread sticky summary
controls are deferred until the basic inline chronology is visually accepted.

### Collapsed durable draft

```text
  ◉── You · Draft · saved locally
  │  ╭──────────────────────────────────────────────╮
  │  │ Add failure coverage…                     ✎  │ Click body or use Edit
  │  ╰──────────────────────────────────────────────╯
```

An empty composer disappears. A durable non-empty new-root draft may collapse,
but its text summary, `Draft` label, author, and body/Edit Resume action remain
visible in the same shell rather than moving to a separate panel. Reply and
edit drafts remain part of their expanded-thread contract above.

### Command ownership

```text
every thread header
  status · Reply · Resolve/Reopen primary tint
  Expand/Collapse only when multi-message

human editable annotation right command column
  Edit

locked or agent-authored annotation right command column
  no Edit

composer right command column
  Revert · Save primary

expanded message right command column
  Edit only when human-authored and editable

output interaction
  File/Review header → Share comments → New | All · Copy Markdown · Export JSON

edit interaction
  guarded body click · focused Enter · E / Control-E → Edit exact annotation

reply interaction
  thread-header Reply · R / Control-R → Reply to active thread
```

The core right-column controls are icon-only owned shadcn controls with one
canonical command identity, optical-size rule, tooltip, and accessible name per
action. Save and Resolve/Reopen receive primary treatment. The stable thread
header never duplicates Edit, and annotation-local rails never duplicate
thread actions. Resolve/Reopen never appears as a message mutation, and
Copy/Export never appears as delivery or resolution. The exact glyph and
component mapping may be refined without changing this command ownership or
visible hierarchy.

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
  → Edit expands the inline thread
      → optional durable draft beside savedBody
          → Save   → replace savedBody; clear draft; thread stays expanded
          → Revert → clear draft; show savedBody; thread stays expanded
          → Escape → flush; exit edit mode; thread stays expanded

saved root or reply message
  → Reply expands the inline thread
      → durable reply draft in the same flat thread

expanded thread with no active editor
  → Escape / outside click → collapse; return focus to inline invoker

expanded thread with active editor
  → outside click → flush draft; collapse; return focus to inline invoker

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
replies do not nest. Only a message with a current saved body and no draft may
enter the New or All output projection. Lock controls editing, not output
membership. Autosave never changes thread resolution. Thread
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
focus and active state MUST clear saved-range paint. While a thread's complete
chronology remains expanded, its range MUST remain the one painted range. Focus
alone MUST NOT expand that chronology. The inline surface MUST NOT add a
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
visible. Reply and edit composers MUST instead follow R-P1-016's inline
collapse sequence.

From the first non-whitespace edit through every committed state refresh,
the same visible editor, local text, focus, and containing thread MUST remain
continuous. A successful mutation MUST complete from its exact typed command
response and MUST NOT wait for a later cross-view refresh. If replacement thread
state arrives in multiple finite-response records, the UI MUST keep the last
complete demanded thread visible until its complete replacement is ready;
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

Save progress MUST begin when the explicit Save mutation is requested and MUST
end when its exact typed command response reports committed or failed. A
committed response MUST end editing, present the exact command-confirmed saved
message immediately, and make Save successful without waiting for a projection
query. A later invalidation, projection delay, replacement, or read failure
MUST NOT keep Save busy, hide that saved message, reverse the committed result,
or present it as a Save failure. Read-model convergence after commit is governed
separately by R-P1-014. The UI MUST NOT fabricate content beyond the exact
committed command result or treat command-confirmed presentation as output-ready
until a complete current projection confirms its output membership.

Mutations to different messages in the same living, applicable session MUST NOT
conflict merely because another message committed first. A message Save or
draft flush MAY conflict when that same message or draft changed, its edit
authority changed, or the containing session became non-writable.

Basis: P1-U2, P1-U3, P1-U14.

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
New/All output membership MUST admit an editable or locked message whose saved
body is present and whose draft is absent. It MUST NOT silently output a prior
saved body while unsaved edits exist. Draft state MUST use a visible text label
and a warning-semantic cue, never color alone. Successful or crash-unknown
output MUST change included editable messages to `locked`; locked messages
cannot be edited, but remain output-eligible under New or All and their threads
remain replyable.

Basis: P1-U3, P1-U9.

### R-P1-007 — Independent placement and thread resolution

The UI MUST expose each thread’s `exact`, `relocated`, `outdated`, or
`unavailable` placement separately from its `open` or `resolved` state.
Placement changes MUST NOT resolve or reopen a thread. Only explicit human
actions may resolve or reopen the whole thread in PR1. Individual messages MUST
NOT carry independent resolution state.

Source-range paint MUST represent only the one currently active/focused comment
or expanded thread; it MUST NOT encode open/resolved state or persist merely
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

### R-P1-010 — Deterministic New or All batch snapshot

File View and Review View MUST expose Share comments from the viewer header as
an ordinary in-layout command row rather than a popover, dialog, floating
overlay, thread command, or nested scroll surface. Share comments MUST default
to `New` and let the reviewer switch between `New` and `All`. That choice MUST
filter the inline comments shown by the viewer and MUST be the complete output
membership; PR1 MUST NOT add a second thread/message checklist or selected-count
state.

The header entry and in-flow row MUST use the same shared BridgeViewer control
language in File and Review: 24 px compact controls, 11 px control typography,
the adjacent viewer's spacing and radius scale, and identical semantic hover,
focus, selected, pressed, and disabled treatments. `New | All` MUST use the
shared compact segmented-control treatment. Copy Markdown and Export JSON MUST
be visually equal neutral destinations; neither receives solid-primary
treatment. Done MUST be the quiet exit action. The row MUST use viewer-header
surface and border roles rather than comment-card surface roles.

When the active session has durable output attempts, the same Share comments
surface in both File View and Review View MUST expose a collapsed in-flow
`History (n)` disclosure adjacent to the Share command row. Reopening Share
comments MUST make that disclosure discoverable after a success toast has
expired. Expanding History MUST take document-layout space and MUST NOT create a
popover, dialog, floating overlay, nested scroll owner, sidebar, global panel,
thread command, or persistent session surface. Opening or closing History MUST
NOT change the active New/All filter or its output membership.

`New` MUST contain every current saved body whose handled boundary is not set,
whether its message is editable or locked. `All` MUST contain every current
saved body, whether new or handled and whether editable or locked. A message
with a draft MUST contribute neither the draft nor its prior saved body until
the draft is Saved or Reverted. Outdated or unavailable located comments that
cannot render inline MUST appear in one temporary in-flow `Other saved comments`
section while Share comments is active; this section MUST NOT admit future
whole-file, session, or general-review comment kinds.

The filter applies at message granularity. Under `New`, a thread is present only
when it has at least one new current saved message, and only those new messages
participate in its compact or expanded projection. Under `All`, every current
saved message participates. A filtered thread with one participating message
renders that message directly; one with two or more derives M-summary, M-last,
message count, latest activity, and expansion chronology from only the
participating messages. Handled or draft-bearing messages hidden by the active
filter MUST NOT remain in keyboard or accessibility traversal. `Other saved
comments` uses the same message filter and ordering but presents the original
location and placement warning because no trustworthy Pierre slot exists.

While Share comments is active, clicking a comment body MUST activate and paint
its complete Pierre range without beginning Edit. Explicit Edit, Reply, and
Resolve/Reopen controls retain their normal contracts; a committed mutation may
change New/All membership through ordinary projection convergence. `Escape` and
`Done` MUST close the mode without output, while Command+A retains ordinary
text-selection meaning. An empty New or All display MUST disable Copy and
Export. Before the first complete annotation projection, Share MUST present
membership as unknown rather than `New (0)` / `All (0)` and MUST disable both
destinations. While a successor projection is refreshing or unavailable, the
row MUST distinguish last-known counts from current confirmed membership and
MUST NOT present stale counts as current zero.

Invoking Copy or Export MUST construct one immutable batch snapshot containing
the exact displayed message identities, saved bodies, immutable origins,
trustworthy current thread-placement summaries, source excerpts,
thread-resolution states, and deterministic order. The invocation MUST bind the
displayed annotation projection and source generation. If either is stale,
native MUST return an exact no-effect conflict, Share comments MUST remain open,
and normal projection convergence MUST refresh the displayed membership before
another output attempt.

The order MUST group located threads by repository-relative path, then use the
trustworthy current line or original line when no current line is trustworthy,
and finally stable thread and message identity. Later message edits or
thread-placement changes MUST NOT alter the batch.

```text
New or All display
   │ validate current savedBody present + draft absent
   ▼
snapshot exact saved bodies + source context + thread state
   │ deterministic order
   ├─► Markdown projection ──► native clipboard effect
   └─► JSON projection     ──► native save-panel/file effect

Both projections consume the same immutable snapshot; neither rebuilds the
displayed membership independently.
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
included editable message immutable. History MUST allow the reviewer to inspect
and reproduce the original output semantics. It MUST NOT mark any thread or
message delivered, agent-acknowledged, accepted, or resolved. Later
clarification MUST be a new human reply in the same thread.

After normal Copy or Export success, the UI MUST show a concise result-specific
confirmation using the product-owned shadcn-style toast presentation, mark the
exact output saved bodies handled by default, close Share comments, and leave
every containing thread open and visible. The toast and durable output history
MUST both offer `Mark as not handled` for that exact output membership. That
action MUST return those exact current saved bodies to `New` without unlocking
their messages or mutating the immutable output event. Copy and Export MUST NOT
resolve, collapse, or hide a thread or claim that an agent addressed it.

Generation or validation failure MUST cause no clipboard/file effect and no
history entry. User-cancelled file selection MUST cause neither a file nor
history entry. Failure or cancellation MUST leave Share comments open and MUST
not create a new lock or handled transition. If an external output succeeds but
durable history subsequently fails, the UI MUST report partial success
accurately and MUST NOT claim that history was recorded. This partial success
MUST close Share comments because the external effect is known to have occurred,
leave the exact included messages locked, leave their handled boundary unset so
they remain `New`, and expose no `Mark as not handled` action. The warning MUST
direct the reviewer to the inspectable prepared/unknown attempt rather than
offering an ordinary retry that could duplicate the external effect.

If restart recovers a prepared attempt whose clipboard/file outcome cannot be
proven, history MUST show the attempt as `unknown`, included messages MUST stay
immutable, and the exact bytes MUST remain available for an explicit Copy or
Export repetition. Recovery MUST NOT automatically replay the external effect
or invent success/failure. The history UI MUST expose inspection and explicit
repetition without forcing a recovery-choice modal.

The durable history interaction MUST be owned by the shared File/Review Share
comments surface described by R-P1-010. Each entry MUST identify output kind,
message count, time, and `succeeded | unknown | finalization failed` outcome in
plain language. Every retained attempt MUST allow exact-byte inspection. An
eligible successful attempt MUST expose `Mark as not handled`; an unknown
attempt MUST expose an explicit `Repeat` action that uses the stored bytes
rather than rebuilding current New/All membership. A finalization-failed attempt
MUST remain inspectable but MUST NOT expose Repeat because its external effect
is known to have occurred. A merely prepared in-process attempt MUST also remain
inspectable but MUST NOT be repeatable until recovery has classified it. No
history action may alter placement, resolution, message bodies, or immutable
output bytes.

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

The initiating viewer MUST receive the exact success, failure, conflict, or
admission result from its typed command response. Other open viewers MAY learn
only that their cached annotation data is stale before requesting their current
demanded replacement. Intermediate stale notifications MAY coalesce, but every
interested viewer MUST eventually converge on current durable repository truth.
A notification-stream reset or reconnect MUST force a fresh current-state
request rather than treating an earlier notification as the annotation data.

Each visible annotation read MUST expose one of these independent states:

```text
unknown(no complete projection)
  └─ demand/subscription snapshot ──► refreshing(no complete projection)
                                      ├─ complete current replacement ──► ready(first complete)
                                      └─ real read failure ─────────────► unavailable(no complete projection)

ready(last complete + no command-confirmed overlay)
  └─ applicable invalidation ──► refreshing(last complete)
                                  ├─ complete current replacement ──► ready(new complete)
                                  └─ real read failure ─────────────► unavailable(last complete)

unavailable(last complete)
  └─ retry, new invalidation, or reactivation ──► refreshing(last complete)

exact committed command response
  └─ present command-confirmed message immediately
      ├─ complete projection contains same/newer message ──► reconcile overlay
      └─ refresh fails ──► retain command-confirmed message + unavailable status
```

`refreshing` MUST mean that a live current read is converging, not that a Save
is still running. `unavailable` MUST retain the last complete projection and a
truthful retryable/non-retryable read-status treatment; it MUST NOT replace it
with fabricated empty state. A partial or superseded finite response MUST NOT
replace the last complete projection. `unknown` MUST NOT be represented by the
same data shape as a confirmed empty projection. An initiating viewer MUST
retain exact command-confirmed message state until a complete projection at the
same or newer committed message revision reconciles it; a different or missing
successor at that revision MUST remain visibly degraded rather than silently
discarding the committed result.

Basis: P1-U1, P1-U2, P1-U6, P1-U8, P1-U12, P1-U14.

### R-P1-015 — PR1 stop line

Every requirement above MUST be satisfiable when no agent integration,
delivery target, provider, authorization binding, agent-acknowledgement state,
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
exactly M-summary plus M-last while collapsed. M-summary MUST derive
deterministically from the current thread projection and identify message count,
latest activity, resolution, and any hidden Draft, placement, or lock state
needed to avoid a false compact representation. Temporary New/All presentation
differences MUST remain inside Share comments and MUST NOT appear as
thread-summary status. M-summary MUST NOT become a
stored, selectable, exportable, or replyable message. M-last MUST remain the
projection of the actual latest message.

The inline surface MUST own one rounded visual boundary composed from the
product's owned shadcn primitives. Its message body MUST be top-aligned and
content-sized; its annotation-local right command column MUST NOT determine
body height. Every human-authored editable message MUST expose exactly Edit in
that local column; locked and agent-authored messages MUST expose no Edit.
Editable message bodies MUST also begin Edit on a non-interactive body click or
focused Enter, while links and non-collapsed text selection remain undisturbed.
Composer right columns MUST contain Revert and the primary-treated Save. These
core controls MUST be icon-only controls with a canonical identity, tooltip,
and accessible name. Thread-header, annotation-local, and composer commands
MUST use the quiet rounded owned shadcn treatment rather than circular chrome.

Every thread MUST expose one stable thread header, including a one-message
thread. That header MUST own status plus exactly one Reply and one
primary-tint Resolve/Reopen. Only a multi-message thread MUST add Expand or
Collapse in that header. PR1 MUST present no direct-action ellipsis or
annotation-local More menu. Copy and Export
MUST remain owned by the File/Review header Share comments mode. The annotation
thread header MUST NOT expose output controls or a permanent inclusion toggle.

Explicit activation of Expand, body/Edit, or Reply MUST expand the same Pierre
annotation row; focus alone MUST NOT expand it. Focus on the compact surface or
any of its controls MUST instead activate that thread and paint its complete
stored range. The expanded row MUST keep the thread active and its range painted
while focus moves within it. It MUST contain exactly one timeline: M-summary
followed by M1 through Mn exactly once in flat chronological order. The existing
M-last element MUST retain its keyed DOM identity while the missing earlier
messages are added. Each expanded human-authored editable message's right
column MUST expose Edit. Reply and Resolve/Reopen MUST remain singular
thread-level commands and continue to affect the whole thread only. Threads
MUST remain independently expandable and resolvable when several projections
share one physical annotation row or source coordinate.

Pierre MUST remeasure the expanded annotation row and remain the sole scroll
owner. Expansion therefore moves later diff rows down and collapse restores
their prior layout. PR1 MUST NOT add a thread-owned scrollbar, floating
chronology layer, or duplicate nested timeline. Long-thread sticky summary
controls are deferred follow-up design work. Expanded message nodes use the
comment spacing scale at 4 px between nodes, and their shared neutral timeline
rail provides grouping without an outer bordered thread card.

Selected source lines MUST retain Pierre's selection paint while the full
annotation row retains Pierre's neutral annotation background. The active
standalone thread frame MUST use a translucent 14% overlay derived from
Pierre's inherited selection hue so Pierre remains visible beneath it. The
frame MUST cap at 48rem (`max-w-3xl`) while shrinking to the available row
width, and MUST introduce no outer border or opacity on text and controls.

Reply and Edit authoring MUST occur at the end of the expanded timeline. `R`
and `Control-R` MUST open Reply only for the active annotation thread. `E` and
`Control-E` MUST edit only the exact keyboard-focused human-authored editable
annotation. These shortcuts MUST NOT dispatch from text inputs, content-editable
surfaces, menus, non-collapsed text selection, or modifier combinations other
than the exact admitted `Control-R` and `Control-E` aliases.
Tooltips MUST show only the canonical `R`, `E`, and `Command-Enter` bindings;
the Control variants remain accepted aliases. Save or Revert MUST exit editing
while leaving the thread expanded. Escape during
editing MUST first flush the active draft, exit edit mode, and leave the thread
expanded; a later Escape MUST collapse it. Outside click MUST safely flush an
active draft and collapse the thread. Collapse MUST return focus to the exact
inline control that invoked expansion. Expand, Edit, Reply, and expanded-thread
controls MUST be keyboard operable, and collapsed chronology content MUST NOT
remain in keyboard or accessibility traversal.

Basis: P1-U14 and the confirmed PR1/PR2 boundary.

### R-P1-017 — Bounded complete-message transport

Every browser-to-native mutation and every native-to-browser finite projection
response MUST carry each admitted message as one complete semantic record. A
message record MUST NOT be split or reassembled across physical data frames.
Multiple complete message records MAY be packed dynamically while the encoded
frame remains within the existing 128 KiB wire bound. If the next complete
message would exceed the frame, it MUST begin the next frame. Metadata
notifications MUST contain no message body. Clipboard and JSON output size is
not limited by the physical frame bound.

Basis: P1-U4, P1-U14 and the existing Bridge wire limit.

```text
finite projection response
     |
     v
message records (each body <= 16 KiB)
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
| Input | non-empty deterministic New or All display of current saved bodies with no drafts |
| Success | packet replaces clipboard; exact history is recorded; messages lock as needed; bodies become handled by default; toast and durable history offer Mark as not handled; Share comments closes; threads remain open |
| Empty display | action is unavailable or rejected without effect |
| Generation/validation failure | no clipboard mutation and no history |
| Clipboard succeeds/history fails | Share comments closes; visible partial success; clipboard content remains; included messages stay locked and New; no Mark as not handled or false history claim; prepared attempt is inspectable and recovers unknown |
| Recovered unknown attempt | inspectable unknown history; messages locked; exact bytes may be copied again only by explicit action |
| Cancellation | not applicable after invocation |
| Compatibility | Markdown is model-readable output, not a machine parsing contract |

### JSON File Export

| Contract slot | PR1 behavior |
| --- | --- |
| Consumer | human reviewer and structured-file recipient |
| Input | non-empty deterministic New or All display of current saved bodies with no drafts, plus a user-selected destination |
| Success | one complete versioned JSON file is present; exact history is recorded; messages lock as needed; bodies become handled by default; toast and durable history offer Mark as not handled; Share comments closes |
| User cancellation | no output file and no history |
| Generation/validation failure | no output file and no history |
| File succeeds/history fails | Share comments closes; visible partial success; file remains; included messages stay locked and New; no Mark as not handled or false history claim; prepared attempt is inspectable and recovers unknown |
| Compatibility | unsupported format versions fail closed; PR1 makes no cross-version compatibility promise |

## Reliability and quality obligations

- Durable reviewer work MUST survive normal restart and recover from the latest
  completed draft flush after abnormal termination.
- Draft persistence MUST remain bounded by the one-second debounce and
  five-second maximum wait while focused; focus loss and Save request immediate
  flushes.
- Each message body MUST remain within 16 KiB UTF-8 and complete message records
  MUST fit dynamically into 128 KiB encoded finite-content frames without
  chunking. Metadata invalidations contain no message bodies.
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
  keyboard/focus accessibility for shared actions. Shared viewer controls MUST
  use one owned shadcn/BridgeViewer composition; importing a primitive while
  recreating route-local geometry or emphasis does not satisfy this obligation.
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
| R-P1-002, R-P1-007 | automated selection/admission and placement-state behavior using real source evidence plus manual pending-range and endpoint/gutter `+` proof; focus each compact thread and its controls, move activity between threads, keep expanded-thread activity, and clear comment activity to prove exactly one full stored range is painted through `selectedLines`, inactive cards retain no range paint, and no location command exists |
| R-P1-003, R-P1-004, R-P1-006 | automated draft/save/revert behavior with controlled time and restart state inspection, plus same-session different-message mutation proof and a real-thread Reply/Edit projection-reconciliation case proving the first character, editor identity, local value, focus, containing thread, immediate command-confirmed saved presentation, and single editing authority remain continuous while state and content updates arrive separately |
| R-P1-005, R-P1-017 | automated Markdown/size/frame admission plus manual visual inspection and boundary rejection |
| R-P1-010, R-P1-011 | deterministic New/All scope and Markdown behavior; File/Review browser plus screenshot/geometry proof that both use one shared 24 px BridgeViewer/shadcn composition with peer neutral Copy/Export actions, viewer-header roles, no checklist/popover/nested scroll, unknown-before-first-read rather than false zero, body range activation without editing, empty-scope disablement, Other saved comments, Escape/Done, and actual clipboard inspection |
| R-P1-012 | schema validation, encode/decode, malformed-input, and unsupported-version evidence |
| R-P1-013 | automated Copy/Export success dismissal, default handled transition, toast/history Mark as not handled, failure/cancellation retention, partial-success behavior, actual file/clipboard effect inspection, and File/Review proof that reopening Share after toast expiry exposes in-flow History with exact inspection and explicit unknown-byte repetition |
| R-P1-014 | real Vite + comm worker + Swift development-backend behavior for create, repeated flush, Save, exact command-confirmed presentation, invalidation, projection query/content completion, two different messages in one session, stream reset/retry, File/Review convergence, and restart with canonical SQLite/projection inspection; mocked browser and direct HTTP tests remain lower layers and cannot substitute for this boundary |
| R-P1-016 | automated M1-only and collapsed M-summary-plus-M-last rendering, focus activation without expansion, expanded-thread active range, one inline M-summary-plus-M1-through-Mn chronology, Pierre row growth with stable row top/scroll anchor, singular thread-header Reply/Resolve, annotation-local Edit eligibility, canonical tooltip copy, `R`/`Control-R` and exact-focused `E`/`Control-E` routing with text-input/selection guards, independent same-coordinate threads, inline authoring, Escape/outside-click/focus-return behavior, and collapsed-content accessibility exclusion plus manual File/Review, narrow-width, 200% text, reduced-motion, and packaged VoiceOver interaction |
| R-P1-015 | dependency/surface inspection proving the complete journey without PR2 machinery |
| Reliability obligations | corrupt-local-database recovery proving visible pre-acknowledgement degradation, rejected mutations, retained recovery witness, and retained quarantined files |

Packaged interaction proof MUST demonstrate the complete human journey in both
viewers, including drag feedback without composer creation, endpoint and
single-line gutter `+` admission, empty-composer dismissal, non-empty draft
collapse/recovery, first Reply/Edit character continuity without editor remount,
M1-only inline rendering, collapsed M-summary plus M-last rendering, inline
M-summary plus M1-through-Mn chronology, independent same-coordinate thread
expansion, keyboard Save/newline/expansion behavior, exact thread-header and
annotation-local commands,
top-aligned content-sized bodies, and one rounded shared-shell visual quality.
It MUST prove that focus activates but does not expand a compact comment, an
an expanded thread retains its range, activity moves paint to another complete stored
range, clearing comment activity removes range paint, and inactive saved
threads retain only endpoint-anchored cards. It MUST inspect actual clipboard
Markdown and JSON export, then demonstrate worktree change, placement
degradation, explicit whole-thread resolution, and restoration. Expanding and
collapsing MUST remeasure Pierre's annotation row, move later diff rows without
changing the expanded row's top or scroll anchor, and restore the compact
geometry with no clipping, overlap, nested scrollbar, editor disappearance,
first-character loss, persistent flicker, duplicate reply, or competing scroll
writer.

The development-browser proof MUST drive the production React composer through
the production comm worker into the real Swift development backend. It MUST
type and Save at least two different messages in one session, observe no
unrelated-message conflict, prove the initiating saved row never disappears,
prove `unknown` is never rendered as confirmed zero, and observe the worker
return to `ready` after its real notification and projection-content cycle.
Direct Swift HTTP routing, repository tests, and mocked browser surfaces do not
satisfy this proof by themselves.

## Traceability

```text
P1-U1  → R-P1-001, R-P1-014
P1-U2  → R-P1-003, R-P1-004, R-P1-014
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
P1-U14 → R-P1-004, R-P1-013, R-P1-014, R-P1-016, R-P1-017
all    → R-P1-015
```

## Structural constraints

The linked Program Design defines these internal boundaries without changing
this observable contract:

- canonical feature-state, persistence, and App-composed native-effect owners;
- typed Web URL-scheme command responses, compact pushed invalidations, and
  finite demanded projection responses;
- stable identities, saved-body/optional-draft/status representation, and transaction
  boundaries;
- source-origin capture, placement evaluation, and continuity-evidence policy;
- cross-view publication and restart recovery;
- deterministic Markdown/JSON batch construction and native output sequencing;
- proof seams for controlled autosave time, failure, partial external effects,
  actual clipboard/file output, and packaged File/Review behavior.
