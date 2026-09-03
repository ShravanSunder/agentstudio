# Worktree Annotation New And Pending — Specification

Date: 2026-08-24

Status: current observable Specification for New and Pending.

Governing Requirements:
[2026-08-24-requirements.md](./2026-08-24-requirements.md).

Related current contract:
[Worktree Annotations PR1 specification](../2026-08-06-worktree-annotations/pr1-specification.md).

Program Design:
[2026-08-25-program-design.md](./2026-08-25-program-design.md). Internal
realization remains outside this Specification.

## Observable outcome

The annotation surface exposes two independent directional states:

```text
agent reply arrives                         human comment is saved
        │                                            │
        ▼                                            ▼
     ● New                                      ● Pending
        │                                            │
deliberate view commits                    output success commits
        │                                            │
        ▼                                            ▼
   no longer New                             no longer Pending
```

A reviewer can inspect a collapsed thread and know how many agent revisions are
New and how many human revisions are Pending. Expanding the thread identifies
each exact New or Pending message. Viewing never changes Pending. Copy, Export,
future authorized Send, and Share-mode inspection never change New.

Where no separately authorized agent-authored revision exists, New is zero and
is omitted. This Specification defines attention behavior for an admitted
agent-authored revision; it does not authorize the mechanism that creates,
delivers, authenticates, or admits that revision.

## Authority and supersession boundary

This Specification supersedes only the overloaded attention/handoff language
in the PR1 contract:

- PR1 `New` output membership becomes `Pending` output membership.
- PR1 `New | All` Share presentation becomes `Pending | All`.
- `Mark as not handled` returns matching current human revisions to Pending.
- Output failure, partial success, and unknown outcome preserve Pending wherever
  PR1 previously said they remain New.
- A thread summary may present durable New and Pending state. It still MUST NOT
  present a temporary Share filter as thread status.
- PR1 R-P1-016's blanket prohibition on agent-author behavior is superseded
  only for read-only presentation, New attention, and Copy/Export output of an
  agent-authored revision admitted through separate authority. Its human
  creation, reply, and mutation rules remain unchanged.

All other PR1 Requirements and Specification obligations remain authoritative,
including draft exclusion, exact saved revisions, locking, immutable history,
flat threads, placement, resolution, cross-view convergence, output effects,
and the PR1 no-agent-integration stop line. In particular, R-P1-015 remains
authoritative: this Specification creates no agent delivery, admission,
identity, authorization, provider, acknowledgement, retry, reconciliation, or
mutation capability. PR1 itself remains satisfiable with no agent-authored
messages and therefore no New attention state.

## Terms visible to consumers

| Term | Observable meaning | Cleared by | Not cleared by |
| --- | --- | --- | --- |
| `New` | current saved agent-authored revision has not crossed its deliberate-view boundary | exact durable view success for that current revision | rendering, scrolling, refresh, Share, Copy, Export, output history |
| `Pending` | current saved human-authored revision has no draft and its handled boundary is unset | successful output finalization for that exact current revision | viewing, expansion, focus, placement, resolution |
| `Viewed` | the exact current agent-authored revision crossed the deliberate-view boundary | superseded when a newer unseen agent revision becomes current | output handling |
| `Handled` | the exact current human-authored revision crossed the PR1 successful-output boundary | `Mark as not handled` may reverse it for matching current membership | viewing |
| `All` | every current human or agent saved revision admitted by the PR1 draft rule | not a mutable message state | New/viewed and Pending/handled do not change inclusion |

`New` is never an alias for unhandled. `Pending` is never an alias for unread.

## State matrix

| Current revision | Working draft | Viewed | Handled | New | Pending |
| --- | --- | --- | --- | --- | --- |
| human-authored saved revision | absent | not applicable | false | no | yes |
| human-authored saved revision | absent | not applicable | true | no | no |
| human-authored saved revision | present | not applicable | either | no | no; Save or Revert first |
| agent-authored saved revision | absent | false | not applicable | yes | no |
| agent-authored saved revision | absent | true | not applicable | no | no |
| newer agent revision replaces a viewed revision | absent | false for the newer revision | not applicable | yes | no |

A message MUST NOT be both New and Pending. Human authorship excludes New;
agent authorship excludes Pending.

## Reviewer journeys

### Outbound handoff

```text
save human revision
  → show Pending in exact message and thread count
  → open Share comments
  → Pending is the default complete output scope
  → successful output finalizes handled membership
  → remove Pending from matching current human revisions
  → do not change any agent New state
```

### Inbound attention

```text
agent revision is admitted
  → show blue New in exact message and thread count
  → passive paint/scroll/refresh leaves it New
  → reviewer deliberately opens or activates it
  → exact durable view result succeeds
  → remove New from that current revision in every viewer
```

### Concurrent revision

```text
agent revision 3 is New
  → reviewer starts viewing revision 3
  → agent revision 4 becomes current before view result commits
  → revision-3 result must not clear revision 4
  → revision 4 remains New
```

## Normative requirements

### R-ANP-001 — Independent author-directed states

The product MUST derive New and Pending independently for the exact current
saved revision. A human-authored revision MUST NOT be New. An agent-authored
revision MUST NOT be Pending. A view transition MUST NOT change handled output
state, and an output transition MUST NOT change viewed attention state.

Basis: ANP-U1, ANP-U4, ANP-U5.

Failure expectation: if author direction or current-revision attention truth is
unknown, the UI MUST NOT infer New from `handled`, infer Pending from unread
presentation, or fabricate a zero count.

### R-ANP-002 — Exact Pending membership

Pending MUST contain every current human-authored saved revision whose handled
boundary is unset and whose message has no working draft. Pending membership is
independent of editable or locked status. A human message with a working draft
MUST contribute neither its draft nor its prior saved body until Save or Revert
restores output eligibility.

Successful output finalization MUST clear Pending only for matching included
current human revisions. `Mark as not handled` MUST return only matching current
human revisions to Pending without unlocking them, changing viewed state, or
rewriting output history. A later human edit creates a new current saved
revision that is Pending until successfully handled.

Basis: ANP-U1, ANP-U5, ANP-U6.

### R-ANP-003 — Exact New membership

New MUST contain every current agent-authored saved revision that has not
crossed the durable deliberate-view boundary for that exact revision. A viewed
older revision MUST NOT make a newer current agent revision viewed. Human
messages MUST NOT enter New when saved, edited, marked not handled, or restored
after output failure.

Where agent-authored revision admission is unavailable or outside the active
product slice, New MUST remain absent rather than reusing Pending membership.

Basis: ANP-U1, ANP-U2, ANP-U4.

### R-ANP-004 — Deliberate view boundary

The following actions MUST request a durable viewed transition for the current
New membership they deliberately expose:

- activating Expand on a collapsed multi-message thread marks the currently
  New agent revisions in that thread viewed;
- deliberately activating a one-message agent thread or one of its message
  controls marks that current agent revision viewed; and
- when an agent revision arrives after its thread is already expanded, that
  revision remains New until the reviewer deliberately activates that exact
  message or one of its controls.

Passive rendering, viewport intersection, scrolling, source-range paint,
projection refresh, page reload, thread collapse, Share-mode entry, Copy,
Export, output-history inspection, and placement or resolution change MUST NOT
request or imply a viewed transition.

The UI MUST remove New only after the exact view request reports durable
success. It MAY show in-progress feedback without suppressing the New marker.

Basis: ANP-U3, ANP-U4, ANP-U8.

### R-ANP-005 — Stale, failed, and repeated viewing

A view request MUST be fenced to the exact current agent revision it intends to
mark viewed. If that revision is stale, the operation fails, the operation is
cancelled, or the durable outcome is unknown, the UI MUST retain New for every
revision not proven viewed and MUST NOT report success. Ordinary projection
convergence MUST present the latest durable result before another attempt.

Repeated deliberate viewing of an already viewed current revision MUST be
observably idempotent: it does not create a newer message revision, affect
Pending, alter thread resolution, or regress another viewer.

Basis: ANP-U4, ANP-U8.

### R-ANP-006 — Thread-summary presentation

Each compact or expanded multi-message thread MUST present non-zero status
counts in this order:

```text
● N new · ● M pending · K messages · latest … · Open|Resolved
```

New MUST use the product primary blue attention role plus the text `N new`.
Pending MUST use the product warning/amber role plus the text `M pending`.
The dot and text form one status; neither state may rely on color alone. A
zero-valued status MUST be omitted with its adjacent separator. Message count,
latest activity, resolution, Draft, placement, lock, and read-availability
status retain their existing meanings.

A one-message thread has no synthetic summary; its exact message-level marker
is the status presentation.

Basis: ANP-U2, ANP-U5, ANP-U7.

### R-ANP-007 — Exact message presentation

Expanded chronology and one-message threads MUST identify each exact state:

- an agent-authored New revision shows a primary blue dot and visible `New`
  text adjacent to its author/time/state metadata;
- a human-authored Pending revision shows a warning/amber dot and visible
  `Pending` text adjacent to its author/time/state metadata;
- viewed agent revisions and handled human revisions show neither marker; and
- Draft remains a separate warning-semantic message state and does not become
  Pending until Save creates an eligible current revision.

Agent and human authorship MUST remain distinguishable without color alone.
Collapsed hidden messages MUST still contribute to the correct thread counts,
and expansion MUST reveal the exact messages responsible for those counts.

Basis: ANP-U2, ANP-U5, ANP-U7.

### R-ANP-008 — Pending or All Share scope

File View and Review View Share comments MUST default to `Pending` and offer
`Pending | All` using the existing shared compact segmented-control language.
The visible and accessible word `New` MUST NOT remain as an alias for Pending.

Pending scope MUST contain only output-eligible current human revisions whose
handled boundary is unset. All MUST contain the complete eligible current
human-and-agent conversation, subject to PR1's draft exclusion. The displayed
scope remains the complete output membership; no manual thread or message
checklist is added.

Copy Markdown and Export JSON MUST each consume the complete membership of the
active scope. With Pending active, each action consumes every eligible Pending
revision. With All active, each action consumes every eligible current human
and agent message. Neither action offers or implies a second per-thread or
per-message selection step.

Successful output of Pending or All MUST change handled/Pending state only for
matching current human revisions, using the PR1 default that a successful Copy
or Export marks those revisions handled. The reviewer MAY use `Mark as not
handled` after success to return matching current human revisions to Pending.
Output MUST NOT clear New agent revisions, even when All includes them as
conversation context. Output failure, cancellation, partial success, unknown
recovery, exact-byte Repeat, and `Mark as not handled` retain PR1 behavior with
`Pending` replacing the old output meaning of `New`.

Basis: ANP-U1, ANP-U5, ANP-U6, ANP-U8.

### R-ANP-011 — Author-aware JSON v2

After adopting New/Pending and agent-authored messages, every new JSON export
MUST emit `agentstudio.worktree-annotations.batch` format version `2`. Version
2 preserves the complete PR1 v1 document shape and ordering except that each
message author is the closed union:

```text
AuthorV2 =
  { kind: "human" }
  | { kind: "agent" }
```

Pending and All exports MUST use the same v2 projector. Pending therefore emits
human authors only by membership, while All may emit both union members. The
projector MUST preserve each snapshotted author kind and MUST reject an unknown
author kind rather than omit, coerce, or mislabel the entry. Copy Markdown MUST
likewise label human and agent authors without relying on color or hidden UI
context.

Existing immutable version-1 output history MUST remain inspectable and
explicitly repeatable under its existing contract. It MUST NOT be rewritten as
version 2. New output MUST NOT silently fall back to v1, because v1 can encode
only `{ kind: "human" }` and would misrepresent an agent-authored entry.

This author-kind union does not define agent identity, authorization, or
provenance fields. A separately authorized agent-identity contract may require
a later format version; it MUST NOT add unknown fields to closed v2 objects.

Basis: ANP-U1, ANP-U6, ANP-U7.

### R-ANP-009 — Cross-view and restart convergence

File View and Review View MUST converge on the same durable New/viewed and
Pending/handled truth for each exact current revision. A successful deliberate
view in one viewer MUST eventually remove New in every interested viewer. A
successful output or `Mark as not handled` action in one viewer MUST eventually
update Pending in every interested viewer. Reload and Agent Studio restart MUST
restore the same states rather than reset New, duplicate Pending, or infer
either from local presentation history.

Before the first complete annotation projection, both counts are unknown and
MUST NOT be rendered as confirmed zero. During refresh or read failure, the UI
retains the last complete state plus any exact command-confirmed result under
the existing PR1 convergence contract.

Basis: ANP-U4, ANP-U5, ANP-U8.

### R-ANP-010 — Compatibility cutover and stop line

Existing human saved revisions with handled boundary unset MUST appear as
Pending without changing their handled value or output history. Existing human
revisions MUST NOT appear New. Existing handled human revisions remain neither
New nor Pending. Where no agent-authored revisions exist, New is absent.

This is a hard terminology and behavior cutover. Product UI and accessible
labels MUST NOT expose the old `New = unhandled` meaning after adoption. Stored
or transported internal representations are Program Design concerns, but no
compatibility realization may present two visible meanings of New.

This Specification does not authorize agent delivery, author identity
selection, reply admission, mutation permission, acknowledgement, retry,
reconciliation, provider behavior, or resolution authority. Those capabilities
require their own governing Requirements and Specification. Where they admit an
agent-authored revision, that revision MUST obey this Specification's New
contract.

PR1 R-P1-015's no-agent-integration obligation remains authoritative.
R-P1-016's no-agent-author-behavior clause is superseded only where it would
prevent read-only presentation, New attention, or output of an agent-authored
revision already admitted under separate authority. This exception MUST NOT be
interpreted as permission to create, deliver, admit, identify, authorize,
mutate, acknowledge, retry, reconcile, or resolve agent work.

Basis: ANP-U1, ANP-U2, ANP-U6 and the narrowed PR1 stop line.

## Observable surface contracts

### Thread attention and handoff status

| Contract slot | Observable behavior |
| --- | --- |
| Consumer | human reviewer |
| Input | complete annotation projection containing current author, revision, viewed, handled, draft, and thread facts |
| Success | exact summary count and exact per-message New/Pending markers render in File and Review |
| Deliberate view | durable exact-revision success removes New and converges across viewers |
| Passive view | no state transition |
| Stale revision | newer agent revision remains New |
| Failure or unknown | New remains; no false viewed claim |
| Compatibility | human unhandled revisions cut over to Pending without data loss |

### Share comments

| Contract slot | Observable behavior |
| --- | --- |
| Consumer | human reviewer and output recipient |
| Input | complete current Pending or All human-and-agent display under PR1 eligibility rules |
| Pending + Copy or Export | consumes every eligible Pending human revision; success marks matching current revisions handled by default; New is unchanged |
| All + Copy or Export | consumes the complete eligible human-and-agent conversation; success marks matching current human revisions handled by default; agent New is unchanged |
| After success | `Mark as not handled` may return matching current human revisions to Pending under the PR1 contract |
| Empty Pending | Copy and Export unavailable without effect |
| Unknown membership | counts are unknown, never fabricated zero; output unavailable |
| Failure/cancellation | PR1 behavior; Pending and New remain truthful |
| Partial/unknown external effect | PR1 locks/history behavior; affected unhandled human revisions remain Pending; New remains unchanged |
| Compatibility | visible and accessible scope is Pending/All only |

### JSON export compatibility

| Contract slot | Observable behavior |
| --- | --- |
| Consumer | human reviewer and structured-file recipient |
| New export | one complete format-version-2 document with exact author kind per entry |
| Pending | contains only eligible human entries because of membership |
| All | contains the complete eligible human-and-agent conversation |
| Unknown author | validation fails with no output effect or history success |
| Historical v1 | remains immutable, inspectable, and explicitly repeatable as v1 |
| Compatibility | v2 closed objects reject unknown fields; v1 is never rewritten or used for new agent-capable output |

## Cross-cutting obligations

- Accessibility: New and Pending MUST use text plus semantic color, remain
  exposed in accessible message/thread names or descriptions, and preserve the
  existing keyboard order and two-stage Escape behavior.
- Reliability: New and Pending MUST be derived from durable exact-revision
  truth, not browser-session memory, viewport observation, toast lifetime, or
  DOM identity.
- Privacy and security: attention state MUST NOT add comment bodies, source
  excerpts, paths, agent credentials, or raw identities to telemetry.
- Performance: passive rendering MUST NOT produce view mutations. One
  deliberate thread action may cover its bounded current New membership without
  issuing one user-visible transition per message.
- Offline behavior: locally available durable New/Pending state remains
  inspectable without a network dependency. This Specification adds no promise
  that an external agent can reply while offline.
- File/Review parity: shared semantics, colors, text, counts, clearing behavior,
  and failure treatment MUST match in both viewers.

## Explicit negative space

This Specification does not define or imply:

- how agent-authored messages are delivered, authenticated, authorized, or
  admitted;
- a global unread inbox, sidebar, notification center, operating-system badge,
  sound, email, push notification, or background read receipt;
- viewport-intersection, dwell-time, hover, or scroll-based viewed state;
- nested replies, per-message resolution, automatic thread resolution, or agent
  resolution authority;
- client-only seen state, localStorage authority, or pane-specific truth;
- automatic output when a message becomes Pending;
- automatic viewed state when a message is copied, exported, selected by Share,
  painted by Pierre, or included under All; or
- Program Design choices such as schema columns, operation names, repositories,
  actors, transaction layout, event shape, or transport routing.

## Requirement-to-proof coverage

| Requirements | Problem / outcome | Normative requirements | Observable contracts | Required evidence class |
| --- | --- | --- | --- | --- |
| ANP-U1 | overloaded New cannot represent direction | R-ANP-001, R-ANP-010, R-ANP-011 | both | automated author/state matrix, author-aware output validation, and UI/accessibility inspection |
| ANP-U2 | thread count cannot identify exact arrivals | R-ANP-003, R-ANP-006, R-ANP-007 | thread status | browser and visual File/Review proof for collapsed and expanded threads |
| ANP-U3 | passive presentation can silently consume attention | R-ANP-004, R-ANP-005 | thread status | automated explicit-action versus passive-render cases and manual keyboard/pointer proof |
| ANP-U4 | client-local read state diverges or resets | R-ANP-003, R-ANP-005, R-ANP-009 | thread status | cross-view, reload, restart, stale-revision, failure, and exact state inspection |
| ANP-U5 | reviewer cannot identify unsent human work | R-ANP-002, R-ANP-006, R-ANP-007, R-ANP-009 | both | message/thread membership matrix, browser/visual proof, and output state inspection |
| ANP-U6 | Share uses inbound language for outbound scope | R-ANP-002, R-ANP-008, R-ANP-010, R-ANP-011 | Share comments and JSON export | complete-scope Pending/All browser behavior; actual Copy/Export/history inspection; v2 human/agent author matrix; malformed or unknown author rejection; and immutable v1 Repeat |
| ANP-U7 | status meaning is ambiguous or color-only | R-ANP-006, R-ANP-007, R-ANP-011 | thread status and exported author identity | normal, narrow-width, 200% text, keyboard, screen-reader, and color-role visual evidence plus v2 author-label validation |
| ANP-U8 | failure falsely consumes state | R-ANP-004, R-ANP-005, R-ANP-008, R-ANP-009 | both | failed, cancelled, partial, unknown, repeat, and stale-result behavior with durable state inspection |

## Traceability

```text
ANP-U1 → R-ANP-001, R-ANP-010, R-ANP-011
ANP-U2 → R-ANP-003, R-ANP-006, R-ANP-007
ANP-U3 → R-ANP-004, R-ANP-005
ANP-U4 → R-ANP-003, R-ANP-005, R-ANP-009
ANP-U5 → R-ANP-002, R-ANP-006, R-ANP-007, R-ANP-009
ANP-U6 → R-ANP-002, R-ANP-008, R-ANP-010, R-ANP-011
ANP-U7 → R-ANP-006, R-ANP-007, R-ANP-011
ANP-U8 → R-ANP-004, R-ANP-005, R-ANP-008, R-ANP-009
```

Program Design must consume these distinct Requirements and Specification
identities without changing the confirmed New/Pending membership,
deliberate-view, failure, compatibility, author-aware All behavior, or proof
obligations defined here.
