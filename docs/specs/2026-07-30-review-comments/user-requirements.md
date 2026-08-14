# Deprecated Review Comments User Requirements Draft

> Source material only. This document is not current requirements or design
> authority. The current design entry point is
> `../2026-08-06-worktree-annotations/README.md`.

Source identity: Agent Studio owner conversation, 2026-08-03
Authority: row-level owner statements captured below
Status: deprecated source snapshot; no current authority

## User and stakeholder classes

- **Human reviewer** — reviews completed agent work in a repository worktree and records actionable feedback without moving back and forth between disconnected tools.
- **Working agent** — receives a correlated set of reviewer comments that it can act on.

The first release does not require a multi-user collaboration class, review administrator, buyer, or external repository host.

## Authorized needs

### U1 — Find recently changed plans and specifications

- Affected class: human reviewer
- Need/outcome: When an agent finishes work on a worktree, the reviewer can use the system's existing filters to focus on plans and specifications updated recently rather than manually finding every document.
- Why it matters: The reviewer needs a bounded set of completed design artifacts to inspect.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct workflow description
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: none

### U2 — Read plans and specifications and comment in place

- Affected class: human reviewer
- Need/outcome: The reviewer can read the selected plans and specifications in a review-capable rendered view and leave comments on the relevant content.
- Why it matters: Feedback must remain connected to the material being reviewed.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct workflow description
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: none

### U3 — Review the changes an agent made in a worktree

- Affected class: human reviewer
- Need/outcome: After an agent finishes implementation work, the reviewer can inspect the worktree's changes as a diff and leave comments while moving through those changes.
- Why it matters: The reviewer needs to respond to the actual implementation delta, not an unscoped file collection.
- Evidence anchor/type: owner statements in the 2026-08-03 conversation; direct workflow description and correction to the prior boundary
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: none

### U4 — Choose what the worktree is compared against

- Affected class: human reviewer
- Need/outcome: Review View lets the reviewer choose the repository/worktree or branch comparison needed to define the diff under review; the current fixed comparison is insufficient.
- Why it matters: Comments cannot be interpreted correctly unless the reviewer and later consumer know which change set was reviewed.
- Evidence anchor/type: owner correction in the 2026-08-03 conversation; direct product requirement
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: exact supported comparison choices and default remain unresolved

### U5 — Accumulate a batch of review comments

- Affected class: human reviewer
- Need/outcome: The reviewer can move through plans, specifications, files, or diffs and leave multiple comments before handing feedback to the agent.
- Why it matters: Reviewing item-by-item should not require interrupting the review to send every comment immediately.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct workflow description
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: none

### U6 — Send only part of the current feedback and continue reviewing

- Affected class: human reviewer
- Need/outcome: The reviewer can select and hand off some comments, continue adding comments, and hand off another batch later.
- Why it matters: Review and agent work may proceed iteratively rather than as one all-or-nothing submission.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct workflow description
- Authority state: authorized
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: none

### U7 — Copy or export feedback for the agent as the MVP handoff

- Affected classes: human reviewer; working agent
- Need/outcome: The reviewer can export or copy the chosen comment batch to the clipboard and paste it to the working agent in a model-readable form.
- Why it matters: This completes the useful review loop without requiring direct agent transport in the MVP.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; explicit MVP selection
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: exact human-readable and machine-readable output formats remain to be selected

### U8 — Keep the review beside the working terminal

- Affected class: human reviewer
- Need/outcome: Zooming into a worktree places its working terminal beside the File View or Review View for one review round, so the reviewer can inspect diffs or files, leave comments, and hand feedback back without losing context.
- Why it matters: The side-by-side workflow is the intended ergonomic path for reviewing completed agent work.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; explanation of why Zoom mode exists
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: exact right-side surface switching between diff, file, plan, and specification remains to be confirmed against the existing Zoom foundation

### U10 — Preserve review comments as durable reviewer work

- Affected classes: human reviewer; working agent
- Need/outcome: Comments created during a worktree annotation session persist when the reviewer leaves Zoom, closes and reopens the view, or restarts Agent Studio. Reopening the same annotation session restores its comments rather than starting over.
- Why it matters: This is a human-agent review system; reviewer feedback is work product and must not be lost before or after it is handed to the agent.
- Evidence anchor/type: owner statement and Zoom screenshot in the 2026-08-03 conversation; direct durability requirement
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: the minimum durable annotation-session identity and how comments behave when its comparison changes remain unresolved

### U11 — Review one identifiable annotation session

- Affected classes: human reviewer; working agent
- Need/outcome: The comments visible on the Zoom review side belong to one identifiable annotation session for the selected worktree rather than an ephemeral viewer instance or every comment ever made on the same path.
- Why it matters: The reviewer must be able to leave, return to, export from, and continue the same body of review work without mixing unrelated rounds.
- Evidence anchor/type: owner statements in the 2026-08-03 conversation; direct correction that Zoom reviews diffs or files “for a round” and subsequent use of “annotation session”
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: how a new annotation session is created, named, or selected remains unresolved

### U12 — Anchor comments to the reviewed material

- Affected classes: human reviewer; working agent
- Need/outcome: Comments in an annotation session retain an anchor to the reviewed file, diff location, plan, specification, or selected content so the reviewer and agent can identify what each comment refers to.
- Why it matters: Persistent comment text without durable reviewed-material context is not usable review feedback.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct anchor requirement
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: the exact anchor evidence required for files, rendered Markdown, and diff sides remains a Specification decision after comparison semantics are settled

### U13 — Explicitly start an annotation session from File View

- Affected class: human reviewer
- Need/outcome: In File View, the reviewer can explicitly start a new annotation session for the material being viewed.
- Why it matters: A standalone file does not by itself identify which body of review work the reviewer intends to create or continue.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; direct interaction requirement
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: how the session is named and whether an applicable existing session is also offered remain unresolved

### U14 — Offer a correlated default annotation session in Review View

- Affected class: human reviewer
- Need/outcome: Review View can use commit or other comparison-correlation anchors to identify a likely default annotation session while still allowing the reviewer to start one manually.
- Why it matters: The common worktree-review path should not require repeated setup when Review View already knows the compared work.
- Evidence anchor/type: owner-proposed behavior in the 2026-08-03 conversation
- Authority state: unresolved — “maybe” proposal requires confirmation
- Priority: unresolved — owner must assign `must`, `should`, or `could`
- Priority assigner: Agent Studio owner
- Hypothesis state: whether the default is automatically opened, merely preselected for confirmation, or created only after the first comment remains unresolved

### U15 — Keep an annotation session living as its worktree changes

- Affected classes: human reviewer; working agent
- Need/outcome: An annotation session remains the same persistent review body while its associated worktree, files, branch state, and current comparison result change. File View and Review View can both continue that session.
- Why it matters: The reviewer may hand off some feedback, let the agent continue working, and then continue reviewing without starting over or losing earlier comments.
- Evidence anchor/type: owner selection in the 2026-08-03 conversation after explicit living-versus-frozen comparison
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: the explicit user action, if any, that ends or closes a living annotation session remains unresolved

Required consequences of this need:

- Git, file, branch, worktree, and current-working-directory facts inform the session's current source and comparison projection; they do not silently replace its identity.
- Every located comment retains immutable origin evidence captured when it was created.
- Current exact, relocated, outdated, pending, or unavailable placement is derived against the session's current reviewed material.
- Worktree edits, commits, branch movement, view switching, partial export, app restart, or temporary source unavailability must not automatically freeze, close, or replace the session.

### U16 — Protect a session when its reviewed source can no longer be correlated safely

- Affected class: human reviewer
- Need/outcome: When Agent Studio can no longer establish that an annotation session still refers to the same repository, worktree, or comparison source, it prevents new comments from being silently anchored to unrelated material while preserving every existing comment for reading and export.
- Why it matters: Persistence must not turn into false attachment after repository replacement, worktree removal, branch/ref loss, or unresolvable source drift.
- Evidence anchor/type: owner proposal in the 2026-08-03 conversation; explicit source-drift safety requirement
- Authority state: authorized for the protection outcome; exact automatic state name and predicate remain unresolved
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: automatic `frozen` presentation is proposed; whether all-outdated anchors alone are sufficient or only loss of repository/worktree/comparison continuity qualifies remains unresolved

### U17 — Expose comment status and lifecycle without conflating independent facts

- Affected classes: human reviewer; working agent
- Need/outcome: A reviewer can tell whether a comment is still being written, ready for handoff, included in a clipboard/export batch or direct delivery, open or resolved, and currently exact, relocated, outdated, or unavailable against the reviewed material.
- Why it matters: The reviewer must know what still needs to be handed off or addressed without treating source drift, export, or delivery as resolution.
- Evidence anchor/type: owner requirement in the 2026-08-03 conversation plus the previously stated partial-handoff workflow
- Authority state: authorized
- Priority: must
- Priority assigner: Agent Studio owner
- Hypothesis state: exact transitions, whether status applies to a top-level thread or every reply, and which clipboard/export facts persist remain unresolved

## Advisory or later capabilities

### U9 — Deliver directly to the working terminal or agent

- Affected classes: human reviewer; working agent
- Need/outcome: The reviewer may send a chosen comment batch directly to the terminal or agent instead of copying and pasting it.
- Evidence anchor/type: owner statement in the 2026-08-03 conversation; desired alternative to clipboard handoff
- Authority state: authorized
- Priority: could, after the clipboard/export MVP
- Priority assigner: Agent Studio owner
- Hypothesis state: provider transport, acknowledgement, retry, and agent mutation behavior are not established by this need

## User-job sequence inputs

```text
Agent finishes work in a worktree
  -> reviewer zooms into that worktree and opens or continues an annotation session
  -> reviewer opens recently changed plans/specs or the worktree diff on the review side
  -> reviewer chooses the intended comparison when reviewing code changes
  -> reviewer reads and accumulates anchored comments
  -> reviewer chooses all or part of the comments
  -> reviewer copies/exports that batch and pastes it to the agent
  -> reviewer may continue commenting and export another batch
```

Observed pain: Review View does not currently let the reviewer choose the comparison that defines the worktree diff, and the reviewer cannot yet accumulate artifact-connected feedback and hand off selected batches through one coherent workflow.

## Provisional goal boundary

- Primary goal: use a persistent human-agent annotation session in a zoomed worktree to review completed work, leave contextual comments across recently changed plans/specs and code diffs, and hand all or part of that feedback to the working agent.
- Affected classes: human reviewer and working agent.
- Existing foundation to reuse: repository/worktree context, existing plan/spec filters, File View, Review View, Pane Zoom, rich Markdown rendering, and existing clipboard/export conventions where available.
- Missing observable capabilities: explicit diff comparison selection; persistent annotation-session identity; durable anchors and comment accumulation; partial/all selection; clipboard/export handoff; shared projection in File View and Review View.
- Allowed capability surface: repository/worktree review, File View, Review View, Comment Mode, comparison selection, comment storage sufficient for the workflow, and clipboard/export.
- Explicit non-goals unless separately authorized: generic collaboration, multi-user review, issue tracking, a new security system, provider plugin marketplace, agent rebinding, acknowledgement protocols, exactly-once delivery machinery, archive/search/retention policy, and direct source editing through comments.
- Complexity budget: reuse current repository, viewer, Bridge, persistence, and Zoom foundations. Any new service, authentication system, generalized collaboration lifecycle, provider control plane, or delivery-reconciliation subsystem requires renewed owner approval.
- Open owner choices: comparison modes/defaults; priority of U1-U6; whether one annotation session spans both plans/specs and code diffs; how Review View selects or proposes a default session; exact export formats; whether replies and agent-authored comments belong to the MVP; whether sessions have an explicit finish/close action; the automatic source-detachment/frozen predicate; exact comment/thread authoring, handoff, and resolution transitions; what happens when the user deliberately changes the comparison definition rather than the worktree merely advancing.

## Current authority gaps

This record is not yet ready for Specification derivation. The owner must confirm or correct the provisional goal boundary and resolve the open choices that change observable MVP behavior. The existing Specification and Program Design cannot supply those decisions themselves.
