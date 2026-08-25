# Worktree Annotation New And Pending — Requirements

Date: 2026-08-24

Status: current Requirements authority for separating inbound annotation
attention from outbound annotation handoff.

Decision authority: Agent Studio owner.

Related authority:

- [Worktree Annotations PR1 requirements](../2026-08-06-worktree-annotations/pr1-user-requirements.md)
- [Worktree Annotations PR1 specification](../2026-08-06-worktree-annotations/pr1-specification.md)
- [New/Pending backend and UI coordination contract](../../wip/communications/2026-08-20-share-comments-backend-ui-coordination-log.md#2026-08-24-1802-edt--ui-lane-separate-inbound-new-from-outbound-pending)

## Problem

PR1 uses `New` to mean a current saved human message whose output-handled
boundary is unset. The product presents that state with the blue-dot language
normally used for unread inbound activity. A reviewer therefore sees their own
newly saved comments described as New, cannot identify which exact expanded
messages carry that state, and reasonably expects viewing the thread to clear
it even though viewing has no relationship to output handoff.

Agent-authored replies require the conventional meaning that the existing
language implies: the reviewer must notice which agent revisions arrived and
which have not been deliberately viewed. Reusing the output-handled boundary
for that purpose would make viewing alter output membership and output alter
attention state.

The product needs two independent, directional states:

```text
human saved revision ── not handed off ──► Pending
agent saved revision ── not viewed ──────► New

successful output clears Pending only
deliberate viewing clears New only
```

## Affected people

### Human reviewer

Needs to see newly arrived agent replies without confusing them with the human
comments still waiting to be handed off. The reviewer must be able to identify
the exact New and Pending messages in a thread and predict which action clears
each state.

### Working agent

May author a revision only through a separately authorized agent-reply
capability. This Requirements set does not authorize delivery, agent identity,
reply admission, or mutation. Where an agent-authored revision exists, its New
state gives the reviewer truthful inbound-attention information.

## Reviewer journey

```text
reviewer saves a human comment
  → comment is visibly Pending
  → Copy, Export, or future authorized Send succeeds
  → that exact current human revision is no longer Pending

agent reply is admitted through separate authority
  → reply is visibly New in the thread summary
  → expanded chronology identifies that exact New reply
  → reviewer deliberately opens or activates it
  → that exact current agent revision is no longer New

agent later revises the reply
  → the newer unseen revision becomes New again
```

Passive rendering, projection refresh, scrolling, Copy, Export, and Share-mode
inspection do not consume inbound attention. Viewing does not claim that a
human comment was handed off.

## Authorized needs

### ANP-U1 — Distinguish inbound attention from outbound handoff

- Affected class: human reviewer.
- Need: `New` and `Pending` are independent message-revision facts with
  different causes and clearing actions. Human-authored revisions may be
  Pending but are never New to their author. Agent-authored revisions may be
  New but are never Pending for outbound human handoff.
- Why: One overloaded state cannot truthfully answer both “what did the agent
  send me?” and “what have I not sent out?”
- Evidence: owner decision on 2026-08-24 and the observed PR1 handled predicate.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U2 — Find New agent replies at thread and message level

- Affected class: human reviewer.
- Need: A collapsed or expanded thread reports how many current agent revisions
  are New. When expanded, each exact New message remains identifiable without
  relying on color alone.
- Why: A thread-level count without message-level attribution does not tell the
  reviewer what arrived.
- Evidence: owner decision on 2026-08-24.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U3 — Clear New only through deliberate viewing

- Affected class: human reviewer.
- Need: Deliberately expanding a multi-message thread marks its currently New
  agent revisions viewed. Deliberately activating a one-message agent thread
  marks that message viewed. An agent reply arriving after a thread is already
  expanded remains New until that exact message is deliberately activated.
  Passive rendering, scrolling, projection refresh, Share mode, Copy, and
  Export do not clear New.
- Why: Background presentation must not silently consume the signal that tells
  the reviewer an agent responded.
- Evidence: owner decision on 2026-08-24.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U4 — Preserve New across panes, viewers, and restart

- Affected class: human reviewer.
- Need: New/viewed state belongs to the exact current agent-authored revision
  and converges across File View and Review View. It survives document reload,
  pane recreation, and Agent Studio restart. A stale viewing action must not
  clear a newer agent revision.
- Why: A client-local dot that reappears after reload or differs between panes
  cannot be trusted.
- Evidence: owner requirement for durable clear-on-view plus PR1 cross-view
  convergence and exact-revision foundations.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U5 — Identify Pending human work before handoff

- Affected classes: human reviewer and working agent.
- Need: Every current saved human revision whose handled boundary is unset is
  visibly Pending when it has no working draft. Successful output clears
  Pending for the exact included human revisions. Marking an eligible output
  not handled returns matching current human revisions to Pending. Viewing does
  not change Pending.
- Why: The reviewer needs an explicit inventory of saved requests that still
  need handoff, independent of attention state.
- Evidence: owner decision on 2026-08-24 and the accepted PR1 output contract.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U6 — Share Pending or All without a second checklist

- Affected classes: human reviewer and working agent.
- Need: Share comments displays `Pending` or `All`. Pending includes only
  output-eligible current human revisions waiting for handoff. All includes the
  complete eligible human-and-agent conversation. Copy Markdown and Export JSON
  each consume the complete membership of the displayed scope: every Pending
  revision when Pending is active, or every eligible human and agent message
  when All is active. No manual thread or message checklist is added.
- Why: Share scope must describe outbound work rather than borrow inbound
  attention language.
- Evidence: owner decision on 2026-08-24 and accepted PR1 P1-U9 through P1-U12.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U7 — Use distinct accessible visual language

- Affected class: human reviewer.
- Need: New uses the product's primary blue attention treatment plus visible
  text. Pending uses the product's warning/amber treatment plus visible text.
  Thread summaries and exact expanded messages expose both counts and states;
  zero-valued states are omitted.
- Why: Distinct direction and clearing behavior must remain understandable
  without relying on color alone.
- Evidence: owner decision on 2026-08-24 and the existing BridgeWeb semantic
  color roles.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### ANP-U8 — Fail without consuming attention or handoff state

- Affected class: human reviewer.
- Need: If deliberate-view persistence fails, the affected agent revision
  remains New and the UI does not claim it was viewed. Existing PR1 output
  failure, cancellation, partial-success, and unknown-outcome behavior remains
  authoritative for Pending and never changes New.
- Why: Failure must preserve the signal whose durable transition did not
  complete.
- Evidence: owner requirement for durable clear-on-view and PR1 failure policy.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

## Goal boundary

- Primary goal: give the reviewer two truthful inventories—new inbound agent
  revisions requiring attention and pending outbound human revisions requiring
  handoff.
- Existing foundation to preserve: PR1 sessions, flat threads, exact current
  saved revisions, drafts, editable/locked status, handled output history,
  File/Review convergence, Share comments, Copy Markdown, Export JSON, and
  source placement.
- Missing observable behavior: genuine agent-reply New state, durable deliberate
  viewing, exact per-message New/Pending presentation, and Pending/All Share
  language.
- Allowed surface: worktree annotation Requirements and Specification, File and
  Review annotation presentation, output-scope language, durable annotation
  attention state, and its observable command result.
- Protected surface: PR1 draft, Save, Revert, locking, output-history,
  placement, resolution, and failure semantics remain unchanged except for the
  authorized New-to-Pending terminology correction.
- Non-goals: this work does not authorize agent delivery, reply admission,
  identity selection, permissions, providers, acknowledgement, retry,
  reconciliation, resolution authority, nested replies, notification center,
  sidebar, global inbox, sound, badge, or operating-system notification.
- Complexity limit: extend the existing durable annotation authority and typed
  exact-result boundary. A second annotation authority, client-only persisted
  truth, generic notification framework, or separate transport requires new
  owner approval.
- Acceptable outcome evidence: automated author/state/revision matrices;
  File/Review browser and visual proof; explicit versus passive viewing cases;
  exact failure and stale-revision cases; cross-view and restart state
  inspection; and Pending/All output/history behavior using actual effects.
- Unresolved owner choices: none.

## Confirmed language

```text
New
  agent-authored current saved revision not deliberately viewed
  primary blue dot plus text
  cleared only by the deliberate view boundary

Pending
  human-authored current saved revision with handled boundary unset
  warning/amber dot plus text
  cleared only by successful handled output

All
  complete eligible human-and-agent conversation
  Copy Markdown copies that complete conversation
  Export JSON exports that complete conversation
  JSON export uses an author-aware version
```

The Specification defines exact normal, boundary, failure, compatibility, and
proof behavior. Program Design owns storage, operation names, internal owners,
transactions, calls, and proof seams.
