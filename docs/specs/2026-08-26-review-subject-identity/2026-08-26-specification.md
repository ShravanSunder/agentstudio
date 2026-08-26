# Durable Review Subject Identity — Specification

Requirements:
[`2026-08-26-requirements.md`](./2026-08-26-requirements.md)

## Observable outcome

A living Worktree Annotation session is the durable review subject. Its current
repository/worktree association says where that subject is available now; it is
not the session's identity. File View and Review View discover the same session
after a proven branch transfer, preserve it for an uncertain transition, and
never attach it from branch-name coincidence alone.

```text
session identity S                    current association
stable for the review round           repository R + worktree W
        │                                      │
        └──────── continuity decision ─────────┘
                          │
              accepted association may move
              session/thread/message IDs do not
```

## Terms

- **Durable review subject**: one living annotation session and its stable
  session identity.
- **Current association**: the repository and worktree in which that subject is
  presently admitted for File/Review mutation and placement.
- **Reviewed branch evidence**: the current local branch meaning, when one
  exists, plus an exact reviewed-HEAD commit witness. A detached or unborn HEAD
  has no branch meaning.
- **Proven continuity**: evidence sufficient to continue automatically.
- **Uncertain continuity**: evidence permits a plausible continuation but
  cannot prove it.
- **Proven different**: authoritative repository lineage evidence rules out the
  session as belonging to the current source.
- **Comparison target**: PR0's selected base branch/ref/commit. It is not the
  durable review subject.

## Normative requirements

### RSI-R1 — Session identity survives association changes

The session, thread, message, draft, and output identities MUST remain unchanged
when a living session accepts a new current worktree association. Acceptance
MUST NOT copy, fork, merge, or recreate comment records.

Traces to: RSI-U1, RSI-U6.

### RSI-R2 — Same canonical worktree remains proven continuity

While repository and canonical worktree identities remain equal, ordinary
commits, rebases, branch-tip changes, branch rename, worktree path movement,
source relocation, and comparison-target changes MUST keep the session
applicable. They MAY change placement and accepted source evidence, but MUST NOT
replace session identity.

Traces to: RSI-U2, RSI-U5, RSI-U7.

### RSI-R3 — A proven branch transfer may update current association

When a living session is associated with another worktree in the same
repository, Agent Studio MAY continue it automatically only when:

1. both the accepted and current sources identify the same non-empty local
   branch meaning; and
2. current Git history proves the accepted reviewed-HEAD witness is equal to or
   an ancestor of the current reviewed HEAD.

On that transition, the current association and accepted reviewed-branch
evidence MUST advance atomically before the session becomes writable in the new
worktree. The prior worktree MUST stop presenting the session as currently
applicable.

Branch-name equality without the Git witness relationship MUST NOT satisfy this
requirement.

Traces to: RSI-U1, RSI-U3, RSI-U7.

### RSI-R4 — Uncertain movement requires reviewer choice

Agent Studio MUST classify a plausible same-repository candidate as uncertain
instead of automatically continuing or detaching when any required proof is
missing, including:

- the branch was renamed while also moving to another worktree;
- history was rebased or rewritten so the accepted witness is no longer an
  ancestor;
- either source has detached or unborn HEAD;
- required Git objects or branch evidence are unavailable; or
- several sessions could describe the current subject.

The session and all of its durable content MUST remain preserved, new mutation
in the current foreign-worktree context MUST pause, and the explicit continuity choice MUST let the
reviewer accept the current source or start another session in the current
worktree. Until acceptance, the candidate's durable association and
source-relationship state MUST remain unchanged, so a foreign-worktree question
cannot make the session non-writable in its still-valid accepted worktree.
Acceptance MUST preserve all durable content and atomically make the current
association canonical.

The current context MUST receive enough candidate summary and revision data to
render and commit that choice. It MUST NOT project the foreign candidate's
threads into current File/Review placement or output membership before
association acceptance.

Traces to: RSI-U3, RSI-U4.

### RSI-R5 — Proven different repository lineage detaches

If the current source is proven to belong to a different canonical repository
lineage, the session MUST remain durable but detached and read-only. Missing Git
evidence, branch-label mismatch, path mismatch, or failed evaluation alone MUST
be uncertain rather than proven different.

Traces to: RSI-U3, RSI-U4.

### RSI-R6 — Repository-scoped discovery cannot bypass uncertainty

When no applicable session is already associated with the current worktree,
inline admission MUST consider relevant living sessions from the same
repository before creating a new session. One proven transferable session MAY
be continued. One or more uncertain candidates MUST invoke explicit choice and
MUST NOT be bypassed by the zero-session creation rule. Several applicable or
transferable candidates MUST use the existing bounded session-choice behavior.

Completed sessions remain durable and read-only but do not block creation of a
new living session.

Traces to: RSI-U1, RSI-U3, RSI-U4.

### RSI-R7 — Comparison changes remain orthogonal

Changing PR0's selected comparison target MUST request and identify a new
comparison snapshot, retain immutable thread origin evidence, and refresh
placement. It MUST NOT independently create, split, detach, or transfer the
annotation session.

Traces to: RSI-U2, RSI-U5.

### RSI-R8 — Migration preserves existing truth

The schema cutover MUST preserve every existing session and descendant row.
Each migrated session MUST retain its existing repository/worktree association.
Existing Review source fingerprints MAY seed reviewed-HEAD evidence. The
migration MUST NOT infer a reviewed branch from a presentation label or invent
continuity where no branch evidence exists.

An existing session without reviewed-branch evidence remains fully usable in
its current canonical worktree. Cross-worktree continuation for that session is
uncertain until the reviewer confirms it or later accepted evidence exists.

Migration or decoding failure MUST follow the existing annotation fail-closed
recovery contract and MUST NOT publish fabricated empty state.

Traces to: RSI-U6.

### RSI-R9 — Common-path performance remains bounded

Same-worktree discovery and refresh MUST require no repository-wide ancestry
evaluation. Repository-scoped candidate loading and Git continuity evaluation
MUST occur only for active File/Review annotation demand when a living candidate
is associated with another worktree. Intermediate invalidations MAY coalesce;
the newest source generation alone may commit an association decision.

Traces to: RSI-U7.

### RSI-R10 — File and Review expose the same decision

File View and Review View MUST resolve the same applicable, uncertain, or
detached session result for the same current repository/worktree and Git state.
A decision accepted in either viewer MUST converge to the other viewer and
survive process restart without creating another session.

Traces to: RSI-U1, RSI-U4, RSI-U8.

## Observable scenarios

### Scenario A — Branch rename in one worktree

Given a living session on `feature/old` in worktree W, renaming the branch to
`feature/new` while W retains its canonical identity keeps the session
applicable. Comments do not disappear; accepted reviewed-branch evidence
advances when current Git truth is next captured.

### Scenario B — Branch transfers to another worktree

Given session S accepted `feature/review` at H1 in worktree A, the same branch
is later checked out in worktree B at H1 or descendant H2. Opening File or
Review in B discovers S, atomically associates S with B, and shows the same
threads and drafts. A no longer presents S as currently applicable.

### Scenario C — Branch name is reused for unrelated history

Given session S accepted `feature/review` at H1, that branch is deleted and a
new `feature/review` points to history for which H1 is not an ancestor. Agent
Studio does not attach S automatically. It preserves S and asks the reviewer.

### Scenario D — Rebase while staying in one worktree

Rebasing or rewriting the branch in the same canonical worktree preserves S
automatically. Thread placement may become relocated, outdated, or unavailable;
those results do not detach the session.

### Scenario E — Rename and transfer happen together

When both worktree identity and branch meaning differ, Agent Studio cannot
prove continuity from the accepted evidence. It asks the reviewer. Accepting
continues S and establishes the current association/evidence; declining leaves
S durable and non-writable for the new source.

### Scenario F — Comparison target changes

Changing `Compare: origin/main` to another branch or pinned commit publishes a
new PR0 snapshot in S. It does not create another session.

## Surface contracts

### Session discovery and admission

- Consumer: File/Review annotation admission.
- Input: current repository/worktree authority and current Git subject evidence.
- Output: zero, one, or several applicable/uncertain session candidates.
- Invariant: zero-session creation occurs only after relevant uncertain and
  transferable candidates have been considered.
- Failure: inability to evaluate a plausible candidate produces uncertainty or
  unavailable discovery, never fabricated absence.
- Cancellation: a superseded source generation cannot change association.
- Compatibility: existing session identifiers and command semantics remain.

### Continuity choice

- Consumer: human reviewer.
- Input: one uncertain durable session and current source evidence.
- Accept: preserve the session and atomically adopt the current association.
- Start another: preserve the candidate's accepted association and durable
  source relationship, then create or select a session associated with the
  current worktree. Once that current-worktree session exists, the foreign
  candidate no longer blocks its ordinary admission.
- Partial success: none; content is never copied as part of the decision.

## Cross-cutting obligations

- Reliability: association change and accepted evidence are one atomic durable
  transition guarded by the expected session revision and newest source
  generation.
- Performance: same-worktree behavior adds no Git work; foreign-worktree
  evaluation is demand-driven and bounded to relevant living candidates.
- Privacy: no new content, branch history, or paths are exported. Existing OTLP
  scrubbing remains authoritative.
- Security: no new actor, privilege, network route, or authorization system is
  introduced.
- Compatibility: one hard schema/model cutover; no dual discovery path or
  compatibility shim remains.

## Proof obligations

| Proof | Observable obligation |
| --- | --- |
| RSI-V1 deterministic behavior | same-worktree, transfer, rewrite, uncertain, different-repository, and multi-candidate decisions |
| RSI-V2 migration/state inspection | existing IDs/content survive and legacy sessions remain usable in their current worktree |
| RSI-V3 real-Git integration | actual branch rename, worktree transfer, descendant witness, detached HEAD, rewrite, and name reuse |
| RSI-V4 native integration | service/repository association transaction, old/new invalidations, File/Review convergence, restart |
| RSI-V5 Vite/Chrome journey | production React → comm worker → Swift development backend → SQLite preserves one session across transfer |
| RSI-V6 packaged WKWebView journey | actual Agent Studio File/Review comments remain visible and writable after accepted movement |
| RSI-V7 aggregate quality | existing PR0/PR1 behavior, lint, typecheck, architecture checks, and complete repository test gate remain green |

## Negative space

This specification does not define branch identity outside one repository,
automatic continuity for simultaneous rename plus cross-worktree transfer,
reflog retention, code-host pull-request identity, historical branch browsing,
session finish/reopen UI, or any new transport/backpressure behavior.
