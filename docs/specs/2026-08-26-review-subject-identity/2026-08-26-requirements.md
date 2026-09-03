# Durable Review Subject Identity — Requirements

## Purpose

Worktree Annotations currently preserve one living human review round while a
canonical worktree remains the same. A Git branch can, however, be renamed or
checked out in another worktree while the human is still reviewing the same
body of work. The conversation must not disappear or silently attach to
unrelated work when that happens.

This correction preserves the PR0 comparison model and the PR1 durable comment
model. It changes only how a living annotation session recognizes the reviewed
subject after its current worktree association changes.

## Authority and governing sources

- Decision owner: Agent Studio owner.
- Existing comparison authority:
  [`../2026-08-06-worktree-annotations/pr0-user-requirements.md`](../2026-08-06-worktree-annotations/pr0-user-requirements.md).
- Existing annotation authority:
  [`../2026-08-06-worktree-annotations/pr1-user-requirements.md`](../2026-08-06-worktree-annotations/pr1-user-requirements.md).
- Owner-confirmed correction on 2026-08-26: a branch name, commit, and worktree
  placement may all change; one continuing review conversation must follow the
  same logical reviewed subject when continuity is proven, ask when continuity
  is uncertain, and never follow branch-name coincidence alone.
- Current implementation and incident evidence are observational: sessions are
  discovered by exact `worktree_id`, so movement to another worktree makes the
  prior session undiscoverable before the existing uncertainty choice can run.

## Affected classes

### Human reviewer

Continues one living review conversation while the agent commits, rebases,
renames the branch, or moves the branch to another worktree.

### Working agent

Receives comments from the same durable conversation. PR1 still gives the
agent no direct mutation, delivery, or acknowledgement authority.

## User journey

```text
reviewer comments on work in worktree A
        │
        ├─ branch is renamed in A
        ├─ branch advances or is rebased in A
        └─ branch is later checked out in worktree B
                    │
                    ▼
          Agent Studio evaluates continuity
                    │
        ┌───────────┼────────────┐
        ▼           ▼            ▼
   proven same   uncertain   proven different
   continue      ask human   detach safely
```

## Authorized needs

### RSI-U1 — Continue one logical review subject

- Need: One living annotation session remains the same review conversation
  when the reviewed subject continues, even if its current worktree association
  changes.
- Why: Worktree placement is an execution detail; moving the same work between
  worktrees must not fragment human review work.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.

### RSI-U2 — Preserve ordinary living Git evolution

- Need: Commits, rebases, branch-tip movement, branch rename, worktree path
  movement, and comparison-target changes do not independently create another
  annotation session.
- Why: The PR0/PR1 review is living rather than frozen, and immutable thread
  origins already preserve what was originally reviewed.
- Authority: authorized.
- Priority: must.

### RSI-U3 — Never follow a label into unrelated work

- Need: Agent Studio must not attach a session to another subject merely
  because a branch name, path, or current file set matches.
- Why: Branch names can be deleted and reused; plausible but incorrect comment
  attachment is worse than an explicit continuity question.
- Authority: authorized.
- Priority: must.

### RSI-U4 — Let the reviewer resolve uncertainty

- Need: When available repository, branch, worktree, and Git-history evidence
  cannot prove same or different continuity, Agent Studio preserves the session,
  pauses new mutations, and asks whether to continue it on the current subject.
- Why: The human owns ambiguous reassociation; heuristics may not silently
  combine or discard review work.
- Authority: authorized.
- Priority: must.

### RSI-U5 — Keep comparison target separate from conversation identity

- Need: Changing the selected comparison target creates a newly identified PR0
  comparison snapshot but does not by itself create another annotation session.
- Why: The target explains the diff basis; the living session owns the human
  conversation about the reviewed subject.
- Authority: authorized by the existing PR0/PR1 contract and reconfirmed by the
  2026-08-26 recovery.
- Priority: must.

### RSI-U6 — Preserve every existing session during cutover

- Need: Existing sessions, threads, saved messages, drafts, resolution,
  placement origins, handled state, and output history remain intact. Existing
  sessions begin with their current repository/worktree association and gain no
  fabricated branch continuity.
- Why: The correction must not trade comment loss for better future identity.
- Authority: authorized.
- Priority: must.

### RSI-U7 — Keep the common path fast and demand-driven

- Need: Ordinary source refresh in the same worktree remains on the existing
  fast path. Cross-worktree continuity work occurs only when repository-scoped
  session discovery finds a relevant foreign-worktree candidate.
- Why: Commenting and Review refresh must remain responsive and resource use
  proportional to active demand.
- Authority: authorized by the Agent Studio performance boundary and the
  owner's explicit performance requirement.
- Priority: must.

### RSI-U8 — Prove the real product boundary

- Need: Evidence must cover deterministic identity decisions, persistence
  migration, real Git worktrees and branch operations, Swift/SQLite integration,
  Vite/Chrome through the communication worker and development backend, and the
  packaged WKWebView journey.
- Why: Unit-only evidence cannot prove that the same comments survive the
  actual branch/worktree transition.
- Authority: authorized by the existing PR1 proof floor and current goal.
- Priority: must.

## Goal boundary

- Primary goal: preserve one durable Review/File comment conversation as the
  same logical reviewed subject moves through ordinary Git and worktree changes.
- Existing foundation to reuse: the current session UUID, repository/worktree
  topology IDs, `local.sqlite`, source fingerprints, continuity choice,
  `agentstudio-git`, Bridge source generations, typed command/content routes,
  and File/Review projection convergence.
- Allowed surface: Worktree Annotation session discovery, continuity evidence,
  session association persistence, existing continuity choice, Git reads in
  `agentstudio-git`, and their existing proof harnesses.
- Protected surface: PR0 comparison calculation and target selection, thread
  origin/placement, draft/Save/output semantics, Bridge transport/backpressure,
  and unrelated UI/data-model work owned by other agents.
- Non-goals: a branch registry, permanent Git branch UUID, event-sourced rename
  history, reflog dependency, new session manager UI, new transport or queue,
  watcher, cache service, polling, network or code-host identity, agent delivery,
  security expansion, or a second annotation system.
- Complexity limit: evolve the existing session and continuity owners. A new
  durable subject table/service, cross-repository identity federation, or
  historical branch graph requires a separate owner decision.
- Acceptable outcome evidence: existing behavior remains green; one real branch
  rename and one real branch transfer preserve the session; unrelated
  branch-name reuse never auto-attaches; an ambiguous rewrite requires explicit
  choice; restart restores the accepted association; and Vite and packaged
  product journeys show the same comments.

