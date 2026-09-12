# Worktree Annotations PR2 — Vision and Product Research

Status: non-normative vision and rough research notes
Date: 2026-08-19
Authority: input to a future PR2 Requirements and design cycle; this is not a
Requirements identity, Specification, Program Design, implementation plan, or
implementation authority.

## Why this document exists

PR1 establishes durable human-authored inline annotations, drafts, flat reply
threads, source placement, Copy Markdown, and JSON export. PR2 is intended to
close the local human/agent loop through bidirectional agent participation and
automated delivery.

Plannotator is useful product evidence because it has independently converged
on several ideas already present in the Agent Studio direction: visual review
of plans and diffs, precise inline annotations, structured agent feedback, and
iterative resubmission. This document inventories that overlap, explains why
the workflow appears attractive, and sets a rough boundary for Agent Studio.

The current PR2 design entry point remains
[`README.md`](./README.md). PR2 still requires its own owner-confirmed
Requirements identity and bounded Requirements → Specification → Program
Design cycle.

Companion WIP research:

- [`../../wip/2026-08-19-pr2-pierre-calldiff-coordinate-and-call-graph-research.md`](../../wip/2026-08-19-pr2-pierre-calldiff-coordinate-and-call-graph-research.md)
  examines Pierre text coordinates and CallDiff syntactic call-tree analysis;
- [`../../wip/2026-08-19-pr2-guided-review-vision-and-prior-art.md`](../../wip/2026-08-19-pr2-guided-review-vision-and-prior-art.md)
  develops a bounded Guided Review vision from Codiff, Plannotator, Hunk, and
  earlier Agent Studio substrate.

## Vision

Agent Studio should make review a durable conversation between one human and
the agents already working in the selected worktree:

```text
agent produces a plan, specification, Markdown artifact, or code change
        |
        v
human reviews the real artifact in Agent Studio
        |
        +-- comments on exact source/diff/rendered content
        +-- asks questions or requests transformations
        `-- chooses the saved messages ready to send
        |
        v
Agent Studio delivers one immutable batch to an explicit current agent
        |
        v
agent replies or changes the worktree
        |
        v
human returns to the same durable thread, verifies, continues, or resolves
```

The product is not a hosted collaboration or link-sharing service. Its center
is the local worktree, durable review truth, explicit agent authority, and the
shortest trustworthy path from precise human feedback to verified change.

## Product boundary

### In the vision

- one human reviewer and the agents already operating through Agent Studio;
- plans, specifications, Markdown documents, files, and code diffs as
  reviewable worktree artifacts;
- precise source-backed annotations and later rendered-Markdown selection
  resolved back to trustworthy source lines;
- durable drafts, threads, replies, delivery attempts, receipts, and history;
- explicit selection of saved messages for agent delivery;
- visible agent identity and provenance for agent-authored replies;
- repeated review → delivery → worktree change → verification cycles;
- optional guided review and agent review findings when they use the same
  durable annotation model and explicit authority boundaries;
- local-first operation and offline usefulness wherever the selected agent and
  repository evidence are locally available.

### Explicitly outside this vision

- public or private link sharing;
- hosted team workspaces or teammate collaboration;
- encrypted paste links or portable hosted review pages;
- multi-user review identity, presence, synchronization, or permissions;
- a generic public HTTP annotations API, SSE stream, or polling fallback;
- GitHub/GitLab review posting as the PR2 delivery mechanism;
- issue-tracker integration;
- a provider marketplace or replacement agent runtime;
- a new cloud service, telemetry product, or analytics pipeline;
- copying Plannotator's local HTTP-server/session-memory architecture;
- arbitrary URL or raw-HTML annotation in the first PR2 delivery slice;
- automatic claims that an agent received, understood, accepted, or completed
  work without evidence for that exact state.

## Plannotator signal

Snapshot inspected on 2026-08-19:

| Signal | Observed value |
| --- | ---: |
| GitHub stars | 7,894 |
| Forks | 582 |
| Listed contributors returned by GitHub API | 100 |
| Repository created | 2025-12-28 |
| Latest inspected release | v0.27.4, 2026-08-17 |
| Recent release cadence | twelve v0.26.x/v0.27.x releases from 2026-08-06 through 2026-08-17 |
| License | Apache-2.0 |

Stars and forks demonstrate substantial interest but do not prove why each user
adopted the product. Plannotator states that it collects no product analytics,
so the causal analysis below distinguishes observable product facts from
reasoned adoption hypotheses.

## What Plannotator actually provides

### Reviewable artifacts

- automatic plan review at an agent's plan handoff point;
- rendered Markdown plan/spec/document annotation;
- annotation of the agent's last message;
- folder browsing for Markdown, HTML, text, configuration, and data files;
- local code review and GitHub/GitLab review;
- Git, Jujutsu, GitButler, and Perforce-oriented comparison modes;
- unified and split diff presentation with file navigation and viewed progress;
- commit, branch, staged, unstaged, uncommitted, and full-stack/layer views.

### Human feedback tools

- text-selection comments and deletions;
- quick labels such as clarification, tests, and out-of-scope feedback;
- “looks good” marks and global comments;
- line/range code annotations and suggested replacement code;
- image attachments and lightweight image markup;
- structured Markdown export grouped by document selection or file/line;
- keyboard-first review and submission;
- approve, annotate, and dismiss gate outcomes;
- revision history and plan diff after agent resubmission.

### Agent loop

- automatic hooks at plan or turn boundaries;
- one-click structured feedback returned to Claude Code, Codex, OpenCode, Pi,
  Gemini CLI, Copilot CLI, Kiro, Droid, and Amp integrations;
- configurable feedback prompts per workflow and runtime;
- optional agent switching after plan approval;
- Ask AI against the selected document or diff context;
- background AI review agents that create inline findings;
- guided review that organizes a large change into an ordered walkthrough;
- external-tool annotations inserted into a live session through HTTP.

### Local-first and extensibility signals

- plans, diffs, drafts, annotations, and history remain local by default;
- open-source Apache-2.0 distribution;
- one installer detects several agent harnesses;
- provider credentials remain owned by the provider CLIs;
- fast release cadence and many host-specific integrations;
- feedback history can be analyzed to improve later agent planning.

Link sharing and hosted Workspaces exist in Plannotator but are intentionally
excluded from the Agent Studio vision in this document.

## Why the product appears to attract users

The following are evidence-backed hypotheses rather than claimed analytics.

### 1. It fixes a painful interface mismatch

Agent output is often reviewed as terminal text, raw Markdown, or a flat diff.
Plannotator replaces free-form “something around line 40 is wrong” feedback
with a visual artifact, exact selection, and structured response. That reduces
the work required to communicate a correction precisely.

Transfer to Agent Studio: strongly aligned. File View, Review View, Markdown
rendering, and durable annotations can provide this without leaving the app.

### 2. It closes the feedback loop instead of producing another review artifact

The user does not merely export a report. The feedback returns to the active
agent and a revised plan or code change can be reviewed again. Automatic plan
interception makes the review moment difficult to forget.

Transfer to Agent Studio: this is the center of PR2. Agent Studio can make the
loop stronger by binding delivery to its existing worktree and agent/session
identity rather than shell stdout or host-specific hooks.

### 3. Precision improves agent usefulness

Structured feedback contains selected text, path, side, line range, original
code, suggested code, and surrounding review identity. This is materially more
actionable than a general chat message.

Transfer to Agent Studio: already aligned with PR1's immutable origin,
placement, excerpt, deterministic batch, and versioned JSON model.

### 4. One mental model covers plans, documents, and code

The same basic review interaction works for plans, rendered Markdown, source
files, diffs, and agent messages. Users learn one selection/comment/send loop
instead of separate tools for each artifact.

Transfer to Agent Studio: aligned, but artifact anchors must remain honest.
Source/diff lines can use the PR1 model. Rendered Markdown should first resolve
back to source lines. Arbitrary HTML/DOM anchors require a later, separately
designed anchor contract.

### 5. It meets users inside many existing agent harnesses

Plannotator integrates with several popular coding-agent runtimes and usually
requires little workflow change. Broad integration expands the audience and
lets a team keep its preferred agent.

Transfer to Agent Studio: the lesson is low-friction agent handoff, not a new
multi-provider plugin system. Agent Studio should use the agents and sessions it
already owns.

### 6. It is local-first, open source, and inspectable

Review content remains local in the default workflow, the code is inspectable,
and provider credentials remain with existing CLIs. This lowers adoption and
trust cost for private repositories.

Transfer to Agent Studio: deeply aligned. Agent Studio's SQLite authority,
local worktree identity, offline posture, and native process boundaries are a
stronger durable foundation.

### 7. It provides familiar review affordances with low ceremony

File trees, unified/split diffs, inline comments, suggested code, viewed state,
approval gates, keyboard shortcuts, and revision diffs resemble established
code-review tools. Users receive the precision of a pull-request review without
first pushing work to a remote host.

Transfer to Agent Studio: PR0/PR1 already establish comparison provenance and
inline comments. PR2 should preserve the small local loop rather than grow a
second GitHub-like review application.

### 8. It keeps adding leverage beyond comments

Ask AI, automated review findings, guided review, semantic-change summaries,
call-flow views, and feedback-history analysis turn review data into navigation
and future improvement. These features make the product useful after the first
annotation is sent.

Transfer to Agent Studio: promising PR2+ territory. Each feature must consume
the same review truth and agent boundary rather than introduce an independent
comment or job system.

## Where Agent Studio is already aligned

| Product direction | Existing Agent Studio foundation | PR2 opportunity |
| --- | --- | --- |
| visual review of real work | File View, Review View, Markdown rendering, PR0 comparison provenance | unify artifact review around the durable annotation interaction |
| precise inline feedback | PR1 located path/side/line-range origin and Pierre integration | reuse for automated delivery and agent replies |
| unfinished work protection | PR1 durable SQLite drafts and restart recovery | keep authoring continuous across agent turns |
| intentional feedback boundary | PR1 explicit Save and output eligibility | explicit Send operates only on saved selected messages |
| structured agent context | deterministic Markdown and versioned JSON batches | deliver the immutable batch directly to the chosen agent |
| iterative correction | living worktree session and open/resolved threads | return after agent changes and continue the same threads |
| trustworthy history | exact output attempts/events and immutable locked messages | add transport-independent delivery attempts and evidence |
| local-first privacy | local SQLite, local repository evidence, no PR1 network dependency | use established Agent Studio agent runtime rather than hosted relay |
| source change honesty | immutable origin plus exact/relocated/outdated/unavailable placement | keep agent replies attached to the same evolving source evidence |

## Where Agent Studio should be deliberately stronger

### Durable authority rather than browser-session memory

Plannotator's external annotations are stored in local server memory for the
session and broadcast by SSE with polling fallback. Agent Studio should retain
SQLite as the sole durable annotation authority and use compact invalidations
plus finite demanded projections. Full messages never belong in push metadata.

### Exact operation results rather than projection-shaped acknowledgement

Send, reply, retry, cancel, and acknowledgement must finish from exact typed
command results. A later projection refresh must not keep a command busy or
reverse its confirmed result.

### Worktree and lineage ownership

Review threads belong to the durable worktree lineage and survive pane,
workspace, viewer, worker, and restart replacement. Agent delivery should bind
to an explicit Agent Studio agent/session that is authorized for that worktree.

### Honest delivery vocabulary

`prepared`, `submitted`, `accepted by transport`, `received by agent runtime`,
`agent replied`, and `human verified` are different facts. PR2 should expose
only states for which its owning boundary has evidence. None automatically
means that the requested work was completed or that the thread is resolved.

### One annotation model

Human comments, agent replies, guided-review findings, and later automated
review findings should project through one durable thread/message model with
explicit author and provenance. No agent-only sidebar, ephemeral findings
store, or second comment authority should appear.

## Rough PR2 product slices

These are candidate slices for Requirements discussion, not an implementation
sequence or accepted PR topology.

### PR2-A — Deliver selected saved feedback to the current agent

```text
saved eligible messages
        |
        v
explicit target: current authorized worktree agent/session
        |
        v
immutable delivery batch
        |
        v
exact delivery attempt result + durable evidence
```

Candidate behavior:

- Send is explicit and names the target before invocation;
- it reuses PR1's arbitrary selection and immutable batch semantics;
- command progress ends on an exact typed result;
- failed delivery leaves the saved messages and batch inspectable;
- retry is explicit unless the selected transport can prove safe automatic
  retry;
- Copy and Export remain useful alternatives and do not become delivery;
- delivery does not resolve threads.

### PR2-B — Agent replies in the same durable threads

Candidate behavior:

- a reply names one authenticated/authorized agent identity and originating
  Agent Studio session/turn;
- agent replies append to the same flat thread chronology;
- human and agent authors are visually distinguishable without color alone;
- an agent may reply to a delivered message but cannot silently rewrite human
  content, resolve a thread, or impersonate the reviewer;
- human follow-up remains durable and may be delivered again;
- inbound agent mutation commits through the annotation service and SQLite,
  followed by compact invalidation and finite projection refresh.

### PR2-C — Verification loop

Candidate behavior:

- the reviewer returns to the same open threads after the worktree changes;
- placement is recomputed without changing immutable origin;
- agent claims and actual worktree evidence remain distinguishable;
- the human explicitly resolves or reopens the whole thread;
- unresolved or unanswered delivery remains visible without a global comment
  panel.

### Parallel follow-up — Rendered Markdown annotation

```text
rendered selection
        |
        v
Markdown source-map resolver
        |
        v
repository-relative path + source identity + source line/range + excerpt
        |
        v
existing located root-create path
```

This is strongly aligned with the vision but orthogonal to automated delivery.
It should reuse the located annotation model when a trustworthy source mapping
exists. It must fail closed rather than store a DOM node or pixel location as
source truth. Mermaid-node, arbitrary HTML-node, and non-text-region anchors
remain later decisions.

### PR2+ candidates

- Ask the current agent about a selected source range or thread without
  creating a durable mutation until the reviewer chooses to save it;
- agent-generated review findings admitted as clearly labeled agent-authored
  threads or replies;
- guided review over large changes using the existing File/Review presentation
  and durable annotation model;
- plan/spec approval gates and revision comparison where Agent Studio has a
  trustworthy artifact identity;
- suggested replacements or quick-edit handoff that remain proposals until the
  existing agent editing path applies them;
- analysis of durable human feedback patterns to improve later agent plans,
  only after privacy, retention, and explicit-use decisions are made;
- image attachments when their storage, lifecycle, export, and agent-readable
  handoff semantics are specified.

## Architectural fit

```text
SQLite
  sessions, threads, human and later agent messages, drafts,
  immutable batches, delivery attempts/evidence, provenance

exact typed commands
  Send, cancel, retry, agent reply admission, target binding,
  delivery/history queries

compact pushed invalidations
  sessionChanged, discoveryChanged, recoveryChanged,
  later deliveryChanged only if a distinct scoped fact is justified

finite demanded projections
  complete current messages, delivery evidence, placement, output history

BridgeWeb local interaction state
  selection, focus, active range, open overlay, unsent text

Atom
  no PR2 authority role; add only if a separately specified native UI
  genuinely needs an observable consumer projection
```

Delivery is an external effect coordinated from a durable immutable batch. It
is not a browser projection mutation. Agent replies are authenticated semantic
mutations through the service actor. They are not pushed message bodies.

## Decisions required before PR2 Requirements

1. Agent target: is Send initially limited to the one current worktree-bound
   agent/session, or may the reviewer choose among several authorized agents?
2. Delivery evidence: which exact facts can the first transport prove—submitted,
   accepted, runtime-received, turn-created—and which remain unknown?
3. Agent authorship: may an agent only reply to delivered threads, or also create
   new located threads?
4. Human authority: may an agent ever resolve/reopen a thread, or is resolution
   permanently human-only?
5. Message locking: does successful automated delivery lock selected messages
   exactly like successful Copy/Export, or does it require a distinct immutable
   delivery membership state?
6. Retry: which failures are safe to retry automatically without duplicating
   agent input, and what idempotency identity does the target honor?
7. Selection: may Send include any eligible saved messages across threads, as
   PR1 output does, or only one thread at a time?
8. Agent response: is an agent reply a normal durable message, a delivery
   receipt, or two distinct records when both facts exist?
9. Rendered Markdown: which rendered elements must map to source in the first
   slice—paragraphs, headings, lists, tables, code blocks, Mermaid—and what is
   the fail-closed behavior when mapping is ambiguous?
10. Guided review and automated findings: are these PR2 scope, PR2+ discovery,
    or explicitly separate products consuming the same annotation foundation?

## Product falsifiers and scope guards

Reconsider or split the direction if:

- direct agent delivery requires a second durable comment or message store;
- agent participation cannot reuse the selected worktree's existing Agent
  Studio identity and authority boundaries;
- rendered selection cannot resolve to stable source evidence without storing
  renderer/DOM identity as truth;
- guided review requires a separate viewer or global comments application;
- delivery state can only be guessed from projection arrival;
- automatic retry cannot avoid duplicate agent input;
- the first usable slice requires hosted sharing, multi-user collaboration, or
  a generic external-tool platform.

## Research sources

Primary sources inspected on 2026-08-19:

- Plannotator repository and README:
  <https://github.com/backnotprop/plannotator>
- Plan Review:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/commands/plan-review.md>
- Annotate:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/commands/annotate.md>
- Code Review:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/commands/code-review.md>
- External Annotations API:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/integrations/external-annotations-api.md>
- Custom Feedback:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/guides/custom-feedback.md>
- AI Code Review Agents:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/docs/guides/ai-code-review.md>
- Structured feedback implementation:
  <https://github.com/backnotprop/plannotator/blob/main/packages/review-editor/utils/exportFeedback.ts>
- Product articles describing local diff review and feedback-history analysis:
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/blog/local-diff-review-for-coding-agents.md>
  and
  <https://github.com/backnotprop/plannotator/blob/main/apps/marketing/src/content/blog/continuously-improve-claude-code-plans.md>

Advisory deprecated Agent Studio PR2 source material was inspected only to
recover earlier questions, not as current authority:

- `../2026-08-03-worktree-annotations/pr2-user-requirements.md`
