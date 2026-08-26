# Durable Review Subject Identity — Program Design

Requirements:
[`2026-08-26-requirements.md`](./2026-08-26-requirements.md)

Specification:
[`2026-08-26-specification.md`](./2026-08-26-specification.md)

## The correction evolves the existing session

The existing session UUID remains the durable review-subject identity. The
existing repository/worktree columns become its current association rather than
its permanent identity. One new accepted reviewed-subject evidence value lets
the existing continuity owner decide whether that association may move.

```text
WorktreeAnnotationSession.id                 durable review subject
        │
        ├─ repositoryID                      repository authority
        ├─ worktreeID                        current association
        ├─ acceptedReviewedSubjectEvidence   branch + HEAD witness
        └─ acceptedSourceFingerprint         File/Review placement evidence
```

No subject table, subject service, branch registry, rename history, event log,
watcher, cache, queue, port, or second annotation path is introduced.

## Current system and exact gap

Current source has three load-bearing behaviors:

1. `annotation_session` stores `repository_id`, `worktree_id`, and
   `accepted_source_fingerprint_json`.
2. discovery selects rows only where `worktree_id = currentWorktreeID`;
3. `WorktreeAnnotationSourceEvaluator` treats equal repository/worktree IDs as
   lineage proof and every mismatch as detached.

```text
CURRENT

File/Review session.discover(current worktree W2)
  → WorktreeAnnotationTransportAdapter
  → WorktreeAnnotationServiceActor.discoverSessions(W2)
  → WorktreeAnnotationSQLiteRepository
  → SELECT ... WHERE worktree_id = W2
  ← sessions already associated with W2 only

session associated with W1 never reaches continuity evaluation
```

Source anchors:

- `WorktreeAnnotationDomainModels.swift`
- `WorktreeAnnotationSourceEvaluation.swift`
- `WorktreeAnnotationSQLiteRepository.swift`
- `WorktreeAnnotationSQLiteRepository+Loading.swift`
- `WorktreeAnnotationTransportAdapter.swift`
- `WorkspaceLocalMigrations.swift`

The current association key works for branch rename, rebase, and filesystem
movement that preserves the canonical worktree UUID. It cannot represent a
branch transfer because the prior session is filtered out before the existing
uncertain-continuity behavior can run.

## Structural crux and alternatives

The crux is not creating a permanent Git branch ID—Git supplies no such
identity. It is deciding where durable conversation identity ends and mutable
source association begins.

| Direction | Gain | Cost/failure | Decision |
| --- | --- | --- | --- |
| Key sessions by branch name | small schema | silently follows deleted/reused names; detached HEAD has no key | rejected |
| Add a subject table/service and branch-history registry | explicit generalized identity | duplicate lifecycle, migration, watcher/history policy, and new coordination with no current consumer | rejected |
| Keep exact worktree ownership | no change | loses the conversation on a real branch transfer | rejected |
| Keep session UUID; make worktree association movable under bounded continuity evidence | preserves existing model and content; reuses continuity choice | one evidence field, repository-scoped candidate read, and association transaction | selected |

The accepted cost is that simultaneous rename plus transfer and rewritten
cross-worktree history ask the reviewer. Reflog or code-host identity would
reduce questions but would add unreliable or external lifecycle authority. The
revisit signal is measured reviewer-choice churn, not a desire for a more
general identity system.

## Components and ownership

```text
WorktreeAnnotationSQLiteRepository
  owns: durable session association/evidence transaction and queries
  changes when: annotation schema or atomic invariants change

WorktreeAnnotationServiceActor
  owns: session discovery/reconciliation sequencing and semantic admission
  changes when: annotation behavior or mutation ordering changes

WorktreeAnnotationContinuityClassifier
  owns: pure same / uncertain / different candidate decision from captured evidence
  changes when: continuity policy changes

WorktreeAnnotationSourceResolver
  owns: current File/Review source and reviewed-subject evidence capture
  changes when: native source material enters annotations differently

AgentStudioGitBridgeReviewDataClient
  owns: mapping existing agentstudio-git revision/head/ancestry results and
        retaining the correlated reviewed branch in Review capture
  changes when: Bridge and agentstudio-git contracts meet differently

agentstudio-git
  owns: HEAD resolution and Git ancestry semantics
  changes when: Git read behavior changes

existing pane notification/projection owners
  own: old/new worktree invalidation, finite replacement, and React convergence
  changes when: annotation publication/demand changes
```

Ownership rules:

- SQLite remains the only durable comment truth.
- The service actor decides semantic continuity; the repository does not infer
  it from SQL columns.
- `agentstudio-git` decides Git HEAD and ancestry facts. Agent Studio does not
  shell out or walk commits.
- Source fingerprints continue to own placement provenance. Reviewed-subject
  evidence does not replace immutable thread origin or PR0 comparison origin.
- BridgeWeb renders the existing applicable/uncertain/detached result and
  invokes the existing choice; it does not classify Git identity.

## Durable model and migration

Add one nullable JSON column to the pre-release annotation schema:

```text
annotation_session.accepted_reviewed_subject_json

WorktreeAnnotationReviewedSubjectEvidence
  branchName: String?       local checked-out branch shorthand
  reviewedHeadOID: String?  exact full commit object ID
```

The existing row fields keep these meanings:

```text
id             durable review-subject/session identity; immutable
repository_id  current canonical repository authority; immutable in this scope
worktree_id    current canonical worktree association; transactionally movable
source_relationship
               relationship to the accepted current association;
               applicable | uncertain | detached
accepted_source_fingerprint_json
               File/Review placement and comparison provenance
```

Migration rules:

1. add the nullable column and a repository discovery index over
   `(repository_id, lifecycle, source_relationship)`;
2. preserve every existing row and foreign key unchanged;
3. when an existing Review fingerprint has `reviewedHeadOID`, seed only that
   witness; do not infer a branch from `reviewedSubjectLabel` or PR0's symbolic
   comparison target;
4. leave File-only and branch-unknown sessions with null branch evidence;
5. current-worktree use remains applicable because exact canonical worktree ID
   is sufficient; a later cross-worktree attempt becomes uncertain without
   branch evidence.

This is one hard schema/model cutover. There is no old/new runtime path and no
backfill task.

## Git evidence uses existing agentstudio-git reads

For Review, the correlated contribution snapshot already supplies the reviewed
HEAD OID and its checked-out branch shorthand. The existing
`AgentStudioGitBridgeReviewDataClient` mapping retains both values on
`BridgeContributionComparisonCapture`; `BridgeReviewContributionOrigin` then
carries `reviewedSubjectBranchName` beside `reviewedHeadOID`. The annotation
Review source resolver reads only those correlated fields from the retained
publication. It must not use PR0 `symbolicTarget`, `reviewedSubjectLabel`, pane
metadata, or a second HEAD read as branch authority.

For File, the existing `resolveRevision(HEAD)` read supplies the same branch and
HEAD pair. A cross-worktree candidate uses `countCommitRange` with the accepted
witness as base and current HEAD as candidate under bounded count and traversal
limits:

```text
exact(0 or more)   accepted witness is equal/ancestor → proven ancestry
atLeastLimit       bounded read cannot prove ancestry → uncertain
traversalLimitReached
                   traversal budget cannot prove ancestry → uncertain
unrelated          rewritten/unrelated history       → uncertain
read failure       missing evidence                   → uncertain/unavailable
```

The read runs through the existing `BridgeGitReadScheduler` Review-metadata
admission. Same-worktree discovery performs no ancestry read. No new Git
scheduler class, cache, watcher, polling, or upstream API is required.

The bounded maximum is an App policy and not a product compatibility promise.
If ordinary real-worktree proof shows legitimate transfers frequently exceed
it, the follow-up is a focused `agentstudio-git` ancestry predicate—not a
Bridge commit walk or a higher unmeasured limit.

## Continuity classifier

The pure classifier consumes accepted and current evidence. Its result for a
foreign-worktree candidate is transient admission state; it does not overwrite
the session's durable relationship to its accepted association:

```text
accepted
  repositoryID, worktreeID, branchName?, reviewedHeadOID?

current
  repositoryID, worktreeID, branchName?, reviewedHeadOID?
  ancestry result when worktree differs and branch names match
```

Decision table:

| Guard, in order | Result |
| --- | --- |
| accepted-association refresh proves repository IDs different | detached |
| repository and worktree IDs match | applicable; accept current evidence |
| same repository, non-empty equal branch names, ancestry is exact | applicable transfer |
| same repository, foreign worktree, any other evidence state | uncertain candidate |
| evidence capture fails before repository relation is known | uncertain/unavailable candidate; never fabricate no candidate |

Target branch/ref, contribution base, paths, file content, and presentation
labels are not classifier keys. They continue to affect comparison and
placement independently.

The foreign-candidate query is already scoped to the same repository, so its
contextual classifier has only `applicable transfer` or `uncertain candidate`
results. `detached` belongs exclusively to evaluation of a session against its
accepted current association.

## Repository interfaces

### Two-stage candidate discovery

```text
discoverCurrentWorktreeSessions(currentWorktreeID)
  → existing indexed current-worktree living candidates

when active demand has no controlling current-worktree candidate
  discoverForeignLivingSessionCandidates(repositoryID, excluding: currentWorktreeID)
  → indexed same-repository living applicable/uncertain candidates
  → stable order
```

Both queries return durable session values only. They perform no Git work and
no classification. Completed sessions are excluded from admission candidates
but remain queryable through their existing identities. A current-worktree
applicable or uncertain candidate controls admission and short-circuits the
foreign query. Only active demand with no such candidate admits repository-wide
fallback and ancestry work.

The service projects a foreign candidate's classifier result beside the durable
session. It never persists that contextual candidate result into
`annotation_session.source_relationship`. This preserves the accepted
association's truth while another worktree asks whether to adopt it.

### Contextual candidate projection

The finite projection's session-summary list includes current-association
sessions plus relevant foreign-worktree candidates. For a foreign candidate it
projects the classifier's contextual relationship (`uncertain`) and the durable
session semantic revision needed by `continuity.choose`; it does not change the
stored session row. Thread details, placement, New/All membership, and output
history remain limited to sessions associated with the current worktree until
acceptance.

This preserves the existing browser admission path:

```text
admission_required(candidateSessionIds)
  → WorktreeAnnotationAdmissionPopover
  → find each ID in projection session summaries
  → Continue uses summary semantic revision
  → Start Another uses explicit newSession admission
```

Without this contextual summary, the existing popover would receive an ID it
cannot render. No new UI surface or session-detail query is introduced.

The service retains the newest contextual candidate projection only for the
existing annotation demand generation and source generation. It is derived
runtime admission state, not a durable cache, and is discarded on demand
release, source replacement, or pane close.

### Atomic association acceptance

```text
acceptCurrentAssociation(
  sessionID,
  expectedSessionRevision,
  expectedRepositoryID,
  previousWorktreeID,
  currentWorktreeID,
  acceptedReviewedSubjectEvidence,
  acceptedSourceFingerprint,
  relationship: applicable,
  now
)
```

Postconditions:

- the session still matches the expected revision, repository, and previous
  association;
- worktree association, reviewed-subject evidence, source fingerprint,
  relationship, semantic revision, and timestamp commit together;
- the result returns both previous and current worktree IDs for invalidation;
- no descendant row or session identity changes.

Conflict commits nothing and restarts current discovery once through the
existing newest-demand path. It does not retry indefinitely.

The existing browser admission choice keeps its two paths:

```text
continue selected uncertain candidate
  → continuity.choose(acceptCurrentSource)
  → call this association transaction

start another
  → existing create-root admission newSession
  → repository transaction rechecks current-worktree living admission
       zero applicable candidates  → insert one session + root draft
       one applicable candidate    → continue it + create root draft
       several applicable          → return bounded session choice
  → leave the foreign candidate row unchanged
```

The unused `continuity.choose(keepDetached)` variant is removed because a
contextual foreign-worktree decline must not globally detach a session that
remains valid in its accepted worktree. It gains no replacement command or
compatibility alias.

`newSession` therefore means an explicit request to establish current-worktree
admission, not an unconditional insert. The recheck and possible insert occur
in the same SQLite transaction. A stale contextual popover still carries its
source/demand and candidate revisions; if those no longer match, the request
returns conflict and performs no insert. Two panes choosing Start Another can
produce at most one new current-worktree session.

## Proposed call paths

### Same-worktree path — intentionally unchanged fast path

```text
File/Review demand
  → annotation session discovery
  → current worktree indexed sessions found
  → equal repository/worktree classifier result
  → normal projection/source refresh
  ← existing applicable threads and placement
```

No ancestry read or association write is added when accepted evidence is
already current.

### Foreign-worktree candidate — changed path

```text
File/Review demand in worktree B
  → WorktreeAnnotationTransportAdapter
  → WorktreeAnnotationServiceActor.discoverAndReconcileSessions
  → repository exact-worktree lookup for B
  ← no controlling current-worktree candidate
  → repository foreign-candidate lookup for repository R excluding B
  ← session S associated with worktree A
  → source resolver captures B branch/head evidence
  → agentstudio-git bounded ancestry read when branch meanings match
  → pure classifier
      ├─ applicable transfer
      │   → repository.acceptCurrentAssociation(A → B) [atomic]
      │   → existing snapshotRequired fact for A and B
      │   ← normal projection in B
      ├─ uncertain candidate
      │   → retain session association/relationship unchanged
      │   → publish contextual uncertain session summary; no thread details
      │   ← continuity choice: accept transfer or start another session
```

Contextual foreign-candidate classification has no durable `detached` branch.
Proven detachment remains on the separate accepted-association source-refresh
path: when current topology/source authority for S's accepted worktree proves a
different repository lineage, that path transactionally persists
`sourceRelationship = detached`. A foreign worktree merely asking about S can
never perform that write.

Changed edges:

| Edge | Status | Consequence |
| --- | --- | --- |
| discovery by exact worktree only | changed, preserved as stage one | current admission stays on the indexed fast path |
| service → repository foreign-candidate fallback read | added conditionally | foreign candidates arrive before zero-session creation only when stage one has no controller |
| source resolver → reviewed-subject evidence | added | branch/head facts are captured by native authority |
| Git contribution mapping → Review origin reviewed branch | added | annotation capture receives correlated subject branch, never target/label |
| Git client → bounded ancestry result | added only for plausible transfer | name reuse cannot auto-attach |
| projection sessions → contextual foreign candidate summaries | changed | existing admission popover can render candidate/revision without projecting threads |
| relationship-only acceptance | changed | accepted choice also moves association atomically |
| unconditional explicit new-session insert | changed | transactional current-worktree recheck prevents duplicate sessions |
| compact invalidation/projection routes | intentionally unchanged | no transport or queue redesign |
| PR0 comparison capture/publication | intentionally unchanged | comparison target remains orthogonal |
| thread placement evaluator | intentionally unchanged | origin truth and relocation stay separate |

## State transitions

```text
Applicable(session S, association A)
  ├─ same canonical worktree refresh
  │      └─► Applicable(S, A; refreshed evidence)
  ├─ proven branch transfer to B
  │      └─► Applicable(S, B; accepted evidence)
  ├─ plausible but unproven movement to B
  │      └─► CandidateUncertain(S, accepted A, proposed B) [transient]
  │               ├─ reviewer accepts ──► Applicable(S, B)
  │               └─ start another ─────► Applicable(S, A) unchanged
  │                                        + new/current session in B
  └─ accepted-association refresh proves different repository lineage
         └─► Detached(S; durable content retained)
```

Illegal transitions:

- a stale source generation or session revision cannot move association;
- branch name without ancestry cannot auto-transfer;
- a completed session cannot become writable through discovery;
- placement degradation cannot move or detach association;
- a comparison-target change cannot move association.
- contextual candidate uncertainty cannot overwrite the durable relationship
  to the accepted association.
- contextual foreign-candidate mismatch cannot persist detached; only the
  accepted-association refresh path may do so.

## Ordering, concurrency, and notifications

One service actor sequences discovery classification and association writes.
Git reads may suspend, so every result retains:

- current annotation demand generation;
- File/Review source generation;
- expected session semantic revision;
- accepted repository/worktree association observed before the read.

All four must still match at association-admission linearization. The service
owns one in-flight association admission per session. In one non-suspending
service-actor turn it:

1. performs the final demand/source/session/association checks;
2. records the in-flight generation; and
3. invokes the repository-access association mutation, enqueueing that
   transaction on `WorkspaceSQLiteDatastoreActor` before the service actor can
   process another message.

That enqueue is the admission linearization point. An invalidation already
admitted before it changes the generation and prevents enqueue. An invalidation
arriving afterward is ordered after the admitted commit: it records one newest
pending reconciliation and runs after the transaction settles. It does not
retroactively revoke an already-linearized predecessor. The SQLite transaction
still rechecks session revision, repository, and previous association and
remains the durable atomic boundary.

No lock, new queue, or non-reentrant actor is introduced. The small in-flight
record lives with the service's existing demand/source fences and is removed on
success, failure, or cancellation.

Association A → B publishes the existing compact `snapshotRequired` fact for
both worktree IDs. This wakes an old viewer so it stops presenting S as
currently applicable and wakes the new viewer so it fetches S. No new event
case is introduced; the service adds only a two-worktree publication helper
around its existing per-worktree publication operation.

If two panes race to move S, one expected-revision transaction wins. The loser
re-discovers current durable truth and either converges on the winner or becomes
uncertain. Session identity is never duplicated.

If two panes race through Start Another, the repository's current-worktree
admission recheck and insert share one transaction. The first may insert; the
second observes that session and continues it or returns the existing bounded
choice. It cannot insert a second row from the stale popover.

## Failure and recovery

| Failure | Containment and recovery |
| --- | --- |
| current HEAD/branch unavailable | candidate remains uncertain/unavailable; content retained |
| ancestry result capped or unrelated | no auto-transfer; ask reviewer |
| ancestry traversal limit reached | no auto-transfer; ask reviewer |
| Git read cancelled/superseded | no write; newest demand may retry |
| invalidation admitted before association enqueue | generation mismatch; no write |
| invalidation admitted after association enqueue | admitted write settles, then one newest reconciliation runs |
| session revision/association conflict | no write; one bounded rediscovery |
| association commit succeeds before notification | SQLite remains authority; reset/reconnect forces current discovery |
| notification to one pane is superseded | aggregate snapshot-required converges from repository truth |
| process exits after association commit | restart reads new association/evidence atomically |
| migration/decoding corrupt | existing fail-closed annotation recovery; never fabricate empty |

Choosing Start Another has no partial transfer: the candidate remains unchanged,
and the transactional current-worktree admission recheck owns selection or
insertion. If that transaction fails, no association moved and the reviewer can
retry.

There is no automatic external effect and therefore no partial-success
compensation path. The only durable effect is one SQLite transaction.

## Performance and observability

- Same-worktree common path: indexed current-association query, no
  repository-scoped fallback query or Git ancestry work.
- Foreign candidate path: conditionally admitted repository-indexed living candidate query, one current
  branch/head capture per source generation, and ancestry only for candidates
  sharing that branch meaning.
- The service deduplicates equal accepted witness pairs within one discovery so
  identical ancestry questions run once.
- Existing source-generation coalescing prevents intermediate filesystem events
  from committing obsolete decisions.
- Telemetry records controlled result class, candidate count, ancestry outcome,
  association-change boolean, and latency. It exports no branch name, path,
  commit OID, session/worktree ID, comment body, or SQL error.

No latency threshold is added as product behavior. Marker-scoped performance
proof compares same-worktree discovery before/after and measures the explicit
foreign-candidate path under real Git worktrees.

## Proof architecture

```text
pure classifier tests
  real values, no Git/SQLite
        │
        ▼
repository migration/transaction tests
  real GRDB SQLite; exact IDs and old/new association
        │
        ▼
agentstudio-git integration
  real temporary repository + real linked worktrees + rename/rewrite/transfer
        │
        ▼
Swift Bridge integration
  real service + repository + source resolver; controlled pane/source generations
        │
        ▼
Vite/Chrome development journey
  production React + comm worker + Swift HTTP backend + real SQLite/Git worktrees
        │
        ▼
packaged WKWebView journey
  actual app composition, File/Review comments, restart and visual interaction
```

| Requirement | Owner/realization | Proof seam |
| --- | --- | --- |
| RSI-R1/R8 | session row migration and association transaction | migration plus SQLite state inspection |
| RSI-R2/R7 | classifier same-worktree precedence; unchanged PR0/placement paths | focused regression and target-change journey |
| RSI-R3 | conditional foreign-candidate read, correlated Review branch/head, Git ancestry, atomic association | pure + real-Git + service integration |
| RSI-R4/R5/R6 | uncertainty/detach rules and existing choice/admission | decision matrix, multi-candidate integration, browser choice |
| RSI-R9 | fast-path split and existing source-generation admission | marker-scoped measurement and cancellation interleavings |
| RSI-R10 | existing compact invalidation and finite projection convergence | two-view Swift/Vite/restart and packaged proof |

Fakes may control source generations and conflicts. They cannot replace the
real Git worktree operations, file-backed SQLite restart, production comm
worker, or packaged WKWebView boundary.

The association integration proof includes two continuation-gated orderings:

```text
G checked → before enqueue admit G+1 → resume → no association write
G enqueued → admit G+1              → G commits in order → reconcile G+1
```

Admission proof also starts File and Review at one barrier, chooses Start
Another in both, and observes one current-worktree session or one bounded
choice/conflict—never two inserts. Review evidence separately uses checked-out
`feature/x` against comparison target `origin/main` and proves the retained
subject branch is `feature/x`; detached HEAD produces no branch meaning. A
bounded traversal-limit result produces uncertainty and no association write.

## Complexity spent and preserved boundaries

Spent:

- one nullable evidence column and repository index;
- one pure continuity classifier;
- one conditional repository-scoped foreign-candidate read;
- one atomic association-acceptance transaction;
- existing agentstudio-git HEAD/range reads on the foreign-candidate path;
- old/new invalidations using existing event vocabulary.

Not spent:

- no new table, store, atom, coordinator responsibility, event type, transport,
  queue, port, scheduler class, cache, watcher, timer, poll, branch registry,
  reflog history, external identity, or UI system.

The design expands only if evidence shows the bounded ancestry read produces
unacceptable uncertainty for ordinary legitimate transfers. That evidence may
justify a focused `agentstudio-git` ancestry predicate; it does not justify a
general review-subject service or branch-history database.
