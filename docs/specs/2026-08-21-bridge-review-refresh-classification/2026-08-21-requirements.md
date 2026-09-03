# Bridge Review Refresh Classification — Requirements

Date: 2026-08-21

Decision authority: Agent Studio owner.

Related authority:

- [Bridge latest-generation operations requirements](../2026-08-18-bridge-latest-generation-operations/2026-08-18-requirements.md)
- [Worktree annotation PR1 specification](../2026-08-06-worktree-annotations/pr1-specification.md)

## Problem

Bridge already computes current Review replacements while retaining the last
complete usable Review. It does not distinguish a routine same-source update
from an update likely to disrupt the reviewer’s visual position and active
comment work.

A routine update should remain quiet and install normally. A disruptive update
should be explained and should hold only the completed presentation swap while
the reviewer is actively interacting. Neither class should stop background
computation or disable reviewing and commenting.

## Affected people

- Human reviewers reading and annotating a changing worktree.
- Developers and agents changing that worktree while review remains open.

## Goal boundary

Extend the existing Review replacement and last-complete lifecycle with two
same-source presentation classes:

```text
one Review update pipeline
  ordinary presentation  -> silent, installs normally
  promoted presentation  -> explained, may hold the completed display swap
```

The work may refine Review presentation, interaction continuity, and proof. It
must preserve current comparison computation, target selection, latest-
generation authority, annotation durability, and the existing command,
metadata, and content routes.

## Authorized needs

### U-RRC-001 — Keep review work uninterrupted

- Affected class: human reviewer.
- Need: Reading, scrolling, selecting, commenting, replying, editing, resolving,
  sharing, and other available Review interactions remain usable while a
  same-source replacement computes.
- Why: Source churn must not interrupt the reviewer’s train of thought.
- Priority: must.

### U-RRC-002 — Keep ordinary updates quiet

- Affected class: human reviewer.
- Need: A routine same-source update computes in the background, shows no
  global update bar, and installs through the normal Review presentation path.
- Why: Routine updates should not create notification noise or unnecessary
  coordination.
- Priority: must.

### U-RRC-003 — Explain disruptive updates without blocking the UI

- Affected class: human reviewer.
- Need: A disruptive same-source update uses promoted presentation with concise
  stable chrome while an affected Review context remains the reviewer’s current
  focus; the current Review remains interactive.
- Why: The reviewer should understand why a visible replacement is being held
  without losing access to current work.
- Priority: must.

### U-RRC-004 — Preserve active comment work across every replacement

- Affected class: human reviewer.
- Need: An open composer, message edit, reply edit, durable draft, and in-flight
  comment command are not lost, closed, duplicated, or rebound to an
  untrustworthy source location by any Review replacement.
- Why: Presentation freshness must not trade away authored work.
- Priority: must.

### U-RRC-005 — Keep comment anchors truthful

- Affected class: human reviewer.
- Need: Comments created against the displayed Review retain that source as
  immutable origin evidence and are evaluated as exact, relocated, outdated,
  or unavailable after a replacement installs.
- Why: Continuing to comment is safe only when the product never pretends a
  stale coordinate is current.
- Priority: must.

### U-RRC-006 — Prefer the newest complete replacement

- Affected class: human reviewer.
- Need: If several updates complete while presentation is held, only the newest
  complete current replacement remains eligible to install.
- Why: Replaying intermediate Reviews would create repeated jumps and obsolete
  presentation.
- Priority: must.

### U-RRC-007 — Let the reviewer release a held replacement

- Affected class: human reviewer.
- Need: When a promoted replacement is ready but held for the affected focused
  context, the reviewer can choose `Apply now`. If the reviewer moves to another
  file, mode, pane, or tab first, the replacement installs automatically. Both
  transitions preserve active comment work and re-evaluate its anchors.
- Why: The reviewer should control a replacement while using affected material,
  without leaving an update waiting after that context is abandoned.
- Priority: must.

### U-RRC-008 — Fail without losing the current Review

- Affected class: human reviewer.
- Need: Classification or replacement failure retains the last complete Review,
  keeps safe interactions available, and exposes a retryable outcome when the
  underlying refresh is retryable.
- Why: A failed replacement must not fabricate empty success or erase useful
  state.
- Priority: must.

## Initial promotion policy

A same-source replacement is promoted when any incoming-delta limit is reached:

- 10 newly imported commits;
- 25 affected files;
- 1,000 added plus deleted lines.

It is also promoted when direct installation cannot preserve an active editor’s
source anchor. The numeric limits are initial behavioral policy and may be
tuned from scrubbed evidence without changing the two-class model.

## Non-goals

- No second Review computation pipeline.
- No blocking or disabling the comment UI during refresh.
- No refresh behavior based on guessed command provenance.
- No global interaction manager, polling loop, durable refresh-task history,
  new physical route, queue increase, or compatibility path.
- No redesign of comparison targets, Review package meaning, annotation
  placement states, or PR2 agent delivery.
- No inserted loading row or other geometry-changing refresh notice.
