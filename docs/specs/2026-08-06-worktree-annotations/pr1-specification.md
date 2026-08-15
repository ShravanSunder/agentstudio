# Worktree Annotations PR1 — Specification

Status: current observable Specification for PR1

Requirements authority:
[`pr1-user-requirements.md`](./pr1-user-requirements.md)

Program Design:
[`pr1-program-design.md`](./pr1-program-design.md)

## Observable outcome

PR1 is complete when a human can create or continue one living annotation
session in File View and Review View, recover unfinished human-message drafts,
explicitly save output-eligible message versions, copy any selected saved
messages as a path- and line-oriented Markdown packet, export the same batch as
versioned JSON, return after the worktree changes, and continue or finish the
review without any direct agent integration.

```text
inspect source-backed material
  → start or reply to an inline human thread in the main view
  → autosave and recover message draft
  → Save intentional message version
  → select saved messages
  → Copy Markdown or Export JSON
  → inspect changed worktree in the same session
  → resolve, continue, detach, or finish explicitly
```

```text
main File / Review view

  [session-level general thread]

  file header
    [whole-file thread]

  line/range  +  [inline located thread]
                   root + flat replies
                   draft / Save / Revert
                   Reply / Resolve thread

  Copy selected → clipboard → "Copied N comments" toast
                               copy interaction closes
                               threads remain open

No PR1 comment sidebar exists.
```

## Consumers and surfaces

```text
Human reviewer
  ├─ File View annotation interaction
  ├─ Review View annotation interaction
  ├─ session and output-history interaction
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
application. All PR1 thread scopes remain accessible from the main viewer
surface; PR1 does not require or expose a comment sidebar.

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

saved versions → batch → Copy/Export success  → reviewer transfers output
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

Only explicit reviewer actions cross living ↔ completed.
Continuity assessment moves only across the columns.
```

### Thread and message authoring

```text
new thread composer
  → first non-empty edit
      → durable root-message draft
          → Save   → saved root message
          → Revert → empty composer

saved root or reply message V1
  → edit
      → durable message draft based on V1
          → Save   → saved version V2
          → Revert → saved version V1

saved message
  → successful Copy or Export
      → immutable output message
          → Reply → new human-message draft in the same thread
```

Every annotation is a thread with one root human message. Every later PR1
message is a human reply in one flat chronological sequence in that thread;
replies do not nest. Only saved message versions may enter output selection.
Autosave never changes thread resolution or output eligibility. Thread
resolution is `open | resolved`, applies to the whole thread rather than an
individual message, and changes only through an explicit human action.

```text
thread OPEN
  root V1 ── successful output ──► immutable root V1
  reply 1 V1 ────────────────────► immutable reply 1 V1
  reply 2 draft ── Save ─────────► saved reply 2 V1
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

Failure expectation: if no session applies, the viewer MUST offer creation and
MUST let the reviewer's first annotation create the session in that same
motion without a separate creation step; if one applies, it MUST show
continuation; if several apply, it MUST require an explicit reviewer choice
rather than infer one from recency.

Uncertain, detached, and completed sessions MUST remain separately discoverable
so the reviewer can inspect, decide continuity, or explicitly reopen them.

### R-P1-002 — Annotation scope admission

PR1 MUST admit three annotation scopes:

- `located`: repository-relative path, source line or contiguous source-line
  range, source role sufficient to distinguish a current file or diff side,
  immutable source/version evidence, and selected source excerpt;
- `wholeFile`: repository-relative path plus immutable file/source evidence;
- `session`: one general request scoped to the annotation session, with no
  fabricated file or line identity.

Located selection MUST be admitted from the source or diff line presentation;
Markdown files remain annotatable in that presentation. Rendered-Markdown
preview selection is not a PR1 admission source (see negative space). PR1 MUST
reject a located or whole-file annotation that has only absolute path,
pane, DOM, SVG, rendered-pixel, or Mermaid-node identity.

Located threads MUST render inline beside trustworthy current source in the
main File or Review view. Whole-file threads MUST render at file scope and
session threads at general-review scope in that same surface. Outdated or
unavailable located threads MUST remain accessible there with their immutable
origin and warning rather than silently disappearing.

Basis: P1-U5.

### R-P1-003 — First-non-empty durable draft

Opening an empty composer MUST create no durable message. The first non-empty
edit MUST create a durable working message draft. While the composer remains
focused, changed draft content MUST be scheduled for persistence one second
after the latest edit and MUST be persisted at least once every five seconds
during continuous editing. Losing composer focus MUST request an immediate
flush of current draft content.

Basis: P1-U2, P1-U3.

Failure expectation: after restart, the reviewer MUST see the latest completely
persisted draft. A hard failure may lose an edit whose persistence had not
completed, but MUST NOT lose an earlier completed flush.

### R-P1-004 — Explicit message Save and Revert

Save MUST first flush the current message draft and then establish a new saved
message version only if that flush and version transition succeed. Revert on an
existing message MUST restore its latest saved version. Revert on a never-saved
message MUST remove its draft. Pane closure, focus loss,
autosave, copy, export, placement change, and restart MUST NOT perform Save.

Basis: P1-U3.

Failure expectation: failed Save MUST leave the recoverable draft and previous
saved version unchanged and MUST visibly report that no new saved version was
established.

### R-P1-005 — Safe Markdown bodies

Message bodies MUST preserve authored Markdown source and MUST render using
the product’s safe Markdown vocabulary. H2 through H6 headings MUST be admitted;
H1 and raw HTML MUST be rejected or prevented before Save. Clipboard rendering
MUST preserve the annotation’s Markdown meaning without allowing its headings
to replace the packet or file hierarchy.

Each root or reply body MUST be at most 16 KiB of UTF-8. The limit applies to
each draft and saved version independently, not to the whole thread. An
oversized edit MUST be visibly rejected without discarding the editor's unsent
text. A thread MAY contain multiple messages and exceed 16 KiB in total.

Basis: P1-U4.

### R-P1-006 — Message version and draft visibility

When a message has both a saved version and a changed durable draft, the UI
MUST distinguish them and offer Save and Revert. Output selection MUST use the
latest saved version and MUST NOT silently include working-draft text. A
never-saved message draft MUST NOT be selectable for output.

Basis: P1-U3, P1-U9.

### R-P1-007 — Independent placement and thread resolution

The UI MUST expose each thread’s `exact`, `relocated`, `outdated`, or
`unavailable` placement separately from its `open` or `resolved` state.
Placement changes MUST NOT resolve or reopen a thread. Only explicit human
actions may resolve or reopen the whole thread in PR1. Individual messages MUST
NOT carry independent resolution state.

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

### R-P1-009 — Explicit finish and reopen

The reviewer MUST be able to finish a living session. If open annotations
remain, the UI MUST warn with the count of open threads and allow the
reviewer to confirm completion without auto-resolving any thread. PR1 does not
require thread enumeration or navigation in this warning; that affordance
belongs to the follow-up comment-sidebar PR. A completed
session MUST remain read-only until an explicit human reopen action.

Basis: P1-U8.

### R-P1-010 — Deterministic batch snapshot

The reviewer MUST be able to select any non-empty subset of saved human-message
versions or all eligible saved messages. Invoking Copy or Export MUST construct
one immutable batch snapshot containing the exact selected message identities,
versions, Markdown bodies, immutable origins, trustworthy current
thread-placement summaries, source excerpts, thread-resolution states, and
deterministic order.

The order MUST place session-level threads first, then order file-backed threads
by repository-relative path, then place whole-file requests before located
requests for that path, then use the trustworthy current line or original line
when no current line is trustworthy, and finally stable thread and message
identity. Later message edits or thread-placement changes MUST NOT alter the
batch.

```text
selection
   │ validate saved versions only
   ▼
snapshot exact versions + source context + thread state
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
- one explicit general-review section when session-level threads are selected;
- one section per repository-relative path;
- an explicit whole-file label for whole-file requests;
- for located requests, current line/range when trustworthy, otherwise an
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
message identities and versions, raw Markdown bodies, immutable origins,
thread-placement summaries, source excerpts and roles, thread-resolution state,
session context, batch identity, format version, and creation time without
requiring Markdown parsing.

An unsupported format version, missing required field, invalid discriminant,
duplicate identity, or order/membership inconsistency MUST be rejected rather
than partially interpreted by contract validation. PR1 emits one version and
defines no JSON import UI or cross-version compatibility promise.

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
    +-- effect + finalize ---> successful event; messages locked
    `-- crash, result unknown -> unknown history; messages locked
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
| Input | one non-empty deterministic selection of saved message versions |
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
| Input | one non-empty deterministic selection of saved message versions and a user-selected destination |
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
- a comment sidebar (the planned follow-up PR owning thread navigation) or a
  Pierre dependency upgrade.

Stable session, thread, message, saved-version, and batch identities; immutable
origins; deterministic ordering; and versioned JSON are PR1 facts. They are not
authorization to prebuild PR2 delivery machinery.

## Requirement-to-proof coverage

| Requirements | Required evidence class |
| --- | --- |
| R-P1-001, R-P1-008, R-P1-009, R-P1-016 | automated lifecycle/thread behavior plus manual cross-view interaction |
| R-P1-002, R-P1-007 | automated anchor admission and placement-state behavior using real source evidence |
| R-P1-003, R-P1-004, R-P1-006 | automated draft/save/revert behavior with controlled time and restart state inspection |
| R-P1-005, R-P1-017 | automated Markdown/size/frame admission plus manual visual inspection and boundary rejection |
| R-P1-010, R-P1-011 | deterministic snapshot/Markdown behavior plus actual clipboard inspection |
| R-P1-012 | schema validation, encode/decode, malformed-input, and unsupported-version evidence |
| R-P1-013 | automated failure/partial-success behavior plus actual file/clipboard effect inspection |
| R-P1-014 | integration behavior across File/Review and restart with canonical state inspection |
| R-P1-015 | dependency/surface inspection proving the complete journey without PR2 machinery |
| Reliability obligations | corrupt-local-database recovery proving visible pre-acknowledgement degradation, rejected mutations, retained recovery witness, and retained quarantined files |

Packaged interaction proof MUST demonstrate the complete human journey in both
viewers, including draft recovery, Save/Revert, selection, actual clipboard
Markdown, actual JSON export, worktree change, placement degradation, explicit
resolution, warning-assisted finish, and session restoration.

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
- stable identities, saved-version/draft representation, and transaction
  boundaries;
- source-origin capture, placement evaluation, and continuity-evidence policy;
- cross-view publication and restart recovery;
- deterministic Markdown/JSON batch construction and native output sequencing;
- proof seams for controlled autosave time, failure, partial external effects,
  actual clipboard/file output, and packaged File/Review behavior.
