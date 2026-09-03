# Incremental Review Git Refresh — Program Design

Date: 2026-09-03

This design realizes
[2026-09-03-specification.md](./2026-09-03-specification.md), authorized by
[2026-09-03-requirements.md](./2026-09-03-requirements.md).

It supersedes only PR0’s structural rule that every contribution invalidation
must discard its calculation predecessor and perform an unscoped complete Git
capture. PR0 remains authoritative for selected-target intent, target/HEAD/base
resolution, direct base-to-working-tree result semantics, source generations,
immutable origins, publication, and failure behavior.

## The change in one picture

Today, Agent Studio has exact changed paths but removes them from the Review
lane before construction:

```text
FSEvent paths
  -> FileChangeset.paths
  -> refresh admission
       |- File dirty fact:   paths retained
       `- Review dirty fact: paths replaced with nil
  -> whole-worktree construction invalidation
  -> pathless agentstudio-git request
  -> complete base-to-worktree comparison
  -> complete package
  -> publication delta
```

The target keeps the complete published result while making the private
calculation proportional when evidence is exact:

```text
FSEvent paths + coverage facts
  -> Review refresh reservation retains change scope
  -> current native-complete calculation supplies opaque Git refresh seed
  -> agentstudio-git resolves target/HEAD/base freshly
       |- seed/identity/scope unsafe -> complete comparison
       `- safe same-path edits      -> literal-path comparison
                                      + immutable predecessor combination
  -> one complete Git snapshot + successor seed
  -> one complete Review package
  -> existing atomic publication and presentation
```

No path-level candidate becomes visible. Incrementality ends at the Git
calculation boundary; every downstream consumer still receives one complete
candidate.

## Structural crux and alternatives

The crux is where complete predecessor Git metadata lives between refreshes.

| Direction | Gain | Cost and rejection reason |
| --- | --- | --- |
| Recalculate everything | No new state or contract | One file edit repeats work for every unrelated Review item; fails R-IRR-002 |
| Global or process-wide Git cache | Reuse across panes and sessions | New eviction, identity, shutdown, and cross-worktree authority system; unnecessary for the confirmed requirement |
| Rebuild from Bridge descriptors | Reuses currently published package | Makes Bridge interpret and combine Git metadata; violates the single Git semantics owner |
| Opaque immutable seed carried by the existing Review lifecycle | Keeps combination in `agentstudio-git`; no global cache; lifecycle is already bounded | Adds one internal seed contract and carries it through construction/publication |

The selected direction is the opaque immutable seed. The seed is a calculation
value returned by `agentstudio-git`; Agent Studio may retain and return it but
cannot inspect, alter, serialize, or use it as presentation authority.

The cost is one active metadata value plus one in-flight candidate value per
Review calculation owner. The payer is native memory during an active Review.
The choice must be revisited if measurement shows the seed materially exceeds
the corresponding complete Review metadata, if multiple panes multiply it
beyond the existing construction/publication bound, or if ordinary scoped
refresh does not materially improve the rich workload.

## Components and ownership

```text
Agent Studio filesystem source
  owns: symlink-canonical FileChangeset and coverage facts
  emits: exact worktree-relative paths or non-exact invalidation

Bridge refresh admission
  owns: burst union, lane generation, newest-work reservation
  carries: ReviewGitRefreshScope without interpreting Git

Bridge Review calculation holder
  solely owns: lifetime of one opaque active Git refresh seed
  writes: seed only after a complete current native calculation commits
  clears: source/target/base retirement, pane close, incompatible recovery

agentstudio-git Review comparison
  owns: target/HEAD/base resolution, seed validation, incremental admission,
        literal-path diff, Git-row combination, complete fallback, next seed
  returns: complete snapshot, opaque successor seed, calculation disposition

Bridge shared construction
  owns: single-flight complete Review template and content backing
  passes through: opaque successor seed with the immutable template without
                  retaining it beyond the owning calculation call

Review publication and presentation
  owns: native commit, displayed predecessor, ordinary/promoted classification,
        atomic install, retained content leases
  does not own: Git calculation or seed interpretation
```

The new structural element is a value contract, not a cache service:

```text
GitReviewRefreshSeed
  package-created and package-consumed
  opaque outside agentstudio-git
  immutable and Sendable
  contains the complete prior Git file projection and exact calculation key
  never Codable and never crosses Bridge transport
```

## Internal contracts

### Review change scope

Bridge derives one internal scope from the existing `FileChangeset`:

```text
ReviewGitRefreshScope
  complete(reason: BridgeReviewCompleteScopeReason)
  exactPaths(paths: nonempty sorted unique repository-relative paths)
```

`exactPaths` is admitted only when:

- the changeset belongs to the exact reviewed worktree;
- `containsGitInternalChanges` is false;
- suppressed ignored and Git-internal counts are zero;
- no status-only invalidation was merged into the reservation;
- the coalesced path collection remains representable without dropping or
  summarizing a member.

Every other input becomes `.complete`. Set union preserves `.exactPaths` only
when both inputs are exact for the same worktree and authority. Union with
`.complete` remains `.complete`.

`BridgeReviewCompleteScopeReason` is a bounded scrub-safe classification of the
existing coverage facts: empty paths, Git-internal change, suppressed ignored
path, status-only change, root/directory or overflow summary, mixed authority,
or another non-exact input. It contains no path or source data and exists only
so admission telemetry can explain why proportional work was not attempted.

Filesystem paths at this stage are symlink-canonical, not Git-spelling-safe.
FSEvents and filesystem canonicalization do not guarantee the exact
byte-sensitive case or Unicode spelling used by Git. Therefore path coverage
can authorize a scoped attempt, but a missing scoped Git row cannot prove that
an existing predecessor row should be removed (V1); that result selects the
complete fallback.

The first realization also classifies any nonzero
`suppressedIgnoredPathCount` as `.complete`. Nested ignore rules do not threaten
proportional correctness while same-path replacement is the only admitted
splice and a missing scoped row never removes a predecessor row. This
conservative choice may reject useful proportional work during build churn, so
admission telemetry must count accepted attempts and rejected attempts by
reason.

The Review lane stops replacing `fileChangeset` with nil. The reservation
carries this classified scope through `refreshCurrentReviewPackage`,
`loadReviewPackageForRefresh`, the pipeline request, and contribution capture.

### `agentstudio-git` refresh request

The local Git contract adds a refresh input shared by contribution-base and
selected-target comparisons:

```text
GitReviewRefreshInput
  complete
  proportional(seed: GitReviewRefreshSeed, changedPaths: [String])

Git review comparison result
  resolved target
  reviewed HEAD
  effective base and base role
  complete ordered GitDiffSnapshot
  opaque successor GitReviewRefreshSeed
  calculationDisposition: complete | proportional | proportionalFallback
  calculationReason: GitReviewCalculationReason
```

`GitReviewCalculationReason` is package-owned and exhaustive over ordinary
complete request, proportional acceptance, and fallback families: missing
seed, seed identity mismatch, invalid path, structural Git-control path,
missing or ineligible scoped row, duplicate or out-of-scope row, capacity
rejection, identity movement, or scoped calculation failure. It is scrub-safe
and carries no path, hash, ref, or source content. Bridge may record the value
but may not reinterpret it as Git policy.

The existing contribution and direct-comparison entrypoints remain distinct
because they resolve different effective bases. Both delegate final projection
to the same seed validator and diff reader.

The seed key contains:

- canonical repository/worktree identity;
- comparison kind and options version;
- selected-target semantic identity;
- resolved target OID;
- reviewed HEAD OID;
- effective base role and OID;
- complete ordered `GitDiffFile` projection.

The request never trusts the seed’s identities as current. It opens the
repository once and freshly resolves target, HEAD, and effective base exactly as
PR0 requires, then compares those results with the seed key.

`agentstudio-git` also rejects proportional admission when a supplied path is
the worktree root, resolves to a directory, escapes the repository, or cannot be
classified as one current file path. Bridge carries path evidence; Git owns the
filesystem and Git interpretation.

Before starting a scoped comparison, `agentstudio-git` classifies any
repository-relative path whose final component is `.gitattributes` or
`.gitignore`, at any depth, as a structural Git-control path and selects the
complete fallback. Existing Git-internal/index/ref/config invalidations arrive
as `.complete`; freshly resolved target/HEAD/base identity movement is rejected
by the seed key and post-calculation identity checks.

### Proportional calculation

After identity validation, `agentstudio-git` constructs a candidate from the
seed’s immutable ordered projection. It configures the existing direct
base-tree-to-working-directory diff with a literal pathspec containing the
exact changed paths and `GIT_DIFF_DISABLE_PATHSPEC_MATCH`. Existing untracked,
recursive-untracked, type-change, binary, hash, size, line-stat, and filter
options remain unchanged.

The scoped result is eligible only when every affected path produces exactly
one same-path `.modified` row with no `previousPath`, every returned row belongs
to one affected path, and every predecessor row touching an affected current or
previous path is absent or same-path `.modified`.

For each affected path:

- a scoped `.modified` row replaces the existing same-path predecessor row;
- a scoped `.modified` row without an existing predecessor row is inserted as a
  newly modified tracked path;
- no scoped row, multiple scoped rows, or an incompatible predecessor row
  rejects proportional assembly and selects a complete comparison; absence may
  be a true reversion, an irrelevant filesystem event, or a Git-path-spelling
  mismatch and cannot distinguish them;
- duplicate, added, untracked, deleted, renamed, copied, type-changed,
  conflicted, previous-path, or out-of-scope rows reject proportional assembly.

After replacement/removal, `agentstudio-git` sorts with the existing path order,
checks unique current and previous-path membership, and creates the successor
seed from that complete projection.

Any rejected condition discards the private candidate and runs the existing
unscoped direct comparison in the same repository operation. It does not return
partial state or make Bridge combine Git rows.

## State and lifecycle

The Bridge calculation holder has one bounded state machine:

| State | Stored material | Transition |
| --- | --- | --- |
| Empty | no seed | initial/source/target recovery performs complete calculation |
| Active | one seed bound to newest native-complete calculation | exact ordinary invalidation starts candidate from active seed |
| Active + candidate | active seed plus private in-flight successor | successful current commit replaces active; stale/failure discards candidate |
| Retired | no reusable seed | source/target/base retirement or close clears seed and returns to Empty/closed |

The seed becomes active only after the complete construction result passes
current generation/admission checks and the native publication commit succeeds.
It does not wait for main display installation: calculation continuity follows
newest native-complete source truth, while presentation classification continues
to use the acknowledged displayed publication. These are separate existing
planes.

An unchanged same-lineage load still validates the returned calculation
identity and replaces the active seed after native commit. Equal visible
metadata does not make the successor seed optional: it may bind fresher
calculation authority needed by the next refresh.

A held displayed predecessor may therefore coexist with a newer calculation
seed. That seed can construct another complete successor; impact classification
still measures displayed publication to the newest candidate through the
existing displayed-source receipt contract.

The calculation holder retains no seed for failed, stale, superseded, or
pre-commit candidates. Closing the pane or provider releases active and
in-flight values. Shared template copies use Swift copy-on-write storage and do
not create independent file-array buffers unless mutated inside
`agentstudio-git` candidate construction.

## Current and proposed call path

Legend: `[=]` intentionally unchanged, `[~]` changed, `[+]` added,
`[-]` removed.

```text
[=] DarwinFSEventStreamClient
      -> FilesystemActor
      -> FileChangeset(paths, coverage facts)

[~] WorkspaceSurfaceCoordinator
      -> construction invalidation still advances freshness epoch
      -> forwards the same path-bearing changeset

[~] BridgePaneRefreshAdmissionCoordinator.recordInvalidation
      File lane   keeps changeset                         [=]
      Review lane classifies and retains refresh scope   [+]
      Review lane writes fileChangeset: nil              [-]

[~] BridgePaneController refresh catch-up
      reservation.refreshScope
      + active opaque seed
      -> Review pipeline/contribution capture

[~] AgentStudioGitBridgeReviewDataClient
      maps scope and opaque seed only
      -> agentstudio-git contribution/direct refresh request

[~] agentstudio-git
      freshly resolves target/HEAD/base                  [=]
      validates seed and scoped result                   [+]
      exact safe scoped comparison OR complete fallback [+]
      -> complete snapshot + successor seed

[~] Bridge shared Review template
      complete template/content backing                 [=]
      carries opaque successor seed                     [+]

[~] native publication commit
      commits complete package                          [=]
      replaces active seed after the same current check [+]

[=] Review metadata publication
      complete-package delta/reset
      -> worker candidate
      -> atomic main install or promoted hold
      -> result/failure to existing owners
```

No new process, watcher, queue, worker, scheduler, transport message, or browser
state is added.

## Normal sequences

### One ordinary tracked edit

```text
Filesystem       Refresh          Bridge             agentstudio-git      Publication
    |                |               |                      |                  |
    |-- file path -->|               |                      |                  |
    |                |-- exact ----->|                      |                  |
    |                |               |-- seed + path ------>|                  |
    |                |               |                      | resolve IDs      |
    |                |               |                      | scoped direct diff
    |                |               |                      | assemble complete
    |                |               |<-- snapshot + seed --|                  |
    |                |               |-- complete package -------------------->|
    |                |               |                      |                  | atomic commit
    |                |               |<---------------- current/failure result|
```

### Structural or uncertain change

The same sequence carries `.complete`. `agentstudio-git` runs the existing
complete direct comparison and returns a new seed. Downstream construction and
publication are identical.

## Concurrency and consistency

The existing Review generation remains the public currentness fence. Refresh
scope and active seed are read under the same reservation authority used to
start construction.

If a newer invalidation arrives:

1. refresh admission advances Review authority and restores/merges dirty facts;
2. the running blocking Git call may finish physically;
3. its generation/admission check rejects native commit;
4. its successor seed is discarded;
5. the newest reservation receives the merged exact paths, or `.complete` if
   any merged fact is uncertain.

The Git request opens one repository and resolves target/HEAD/base before using
the seed. It rechecks the resolved identities after scoped calculation before
returning proportional success. Identity movement converts the attempt to
complete fallback; it never commits a seed assembled across two identities.

No lock is placed on the worktree. A filesystem mutation racing either scoped
or complete calculation is handled by the existing observer-before-capture and
newest-generation rejection model. Proportional calculation does not claim
stronger repository atomicity than the current complete reader.

## Failure and recovery

```text
invalid or missing seed
  -> complete comparison

non-exact/structural scope
  -> complete comparison

unexpected scoped Git result
  -> discard private candidate
  -> complete comparison in the current attempt

newer invalidation or identity movement
  -> current attempt becomes stale
  -> discard candidate seed
  -> newest reservation retries from active seed or complete scope

complete comparison failure
  -> no successor seed commit
  -> retain active seed and last complete Review
  -> existing retryable/unavailable presentation

pane/provider close
  -> reject new calculation
  -> await existing physical work through scheduler ownership
  -> release active/candidate seed values

missing scoped row for an existing predecessor path
  -> do not interpret absence as deletion or reversion
  -> discard private candidate
  -> complete comparison in the current attempt
```

Proportional-to-complete fallback is calculation selection inside one attempt,
not a user-visible retry. It does not consume the existing automatic retry.
A later automatic retry receives the newest retained dirty fact and active seed.

## Capacity, performance, and data lifecycle

The seed stores Git metadata only. It never stores worktree or blob bytes,
patches, rendered content, comments, or transport frames.

The holder retains at most one active seed and one in-flight candidate seed.
The candidate uses copy-on-write predecessor storage and materializes changed
rows plus the final complete ordered array. It does not retain one seed per
generation or per filesystem batch.

The active seed shares the complete ordered Git-file array already returned by
the calculation through Swift copy-on-write storage. The candidate may allocate
one successor array of the same cardinality while it replaces affected rows.
The bound is therefore one active complete metadata array plus one candidate
array; it does not introduce a new product-visible item or byte limit.

Performance probes distinguish:

- changed-path admission and count;
- proportional admitted/rejected/fallback disposition;
- seed validation and candidate assembly;
- scoped Git comparison;
- complete Git comparison;
- package construction, publication, and usable paint.

Admission metrics use the existing observability path and the two bounded
reason enums above. Bridge reports exact-path admission versus
`.complete(reason:)`; `agentstudio-git` reports proportional success versus
the result's `calculationDisposition` and `calculationReason`. Neither layer
reconstructs the other layer's policy, and no new event or transport route is
introduced.

For each measurement window and runtime configuration, admission telemetry
reports the proportional accepted-to-attempted ratio and rejected-to-attempted
ratios grouped by reason. Raw counts are reported only with that same window
and configuration.

Paths, raw hashes, and source contents remain excluded from exported telemetry.
Only counts, dispositions, durations, and scrubbed operation identity are
reported.

## Cutover

Agent Studio is the only `agentstudio-git` consumer. The library contract and
Agent Studio call sites cut over together through an exact revision pin; there
is no compatibility shim, optional legacy route, persisted migration, or mixed
runtime version.

The existing complete path remains the fallback inside the new contract, not a
second externally selectable implementation. Removing the new seed from a
request deterministically selects complete calculation.

PR0 Program Design is amended after this design is accepted to replace its
“no Git-result cache” and “fresh unscoped capture for every invalidation”
mechanism with a pointer to this design. Its observable requirements and other
structural owners remain unchanged.

## Proof architecture

| Requirement | Realization owner | Proof seam |
| --- | --- | --- |
| R-IRR-001 complete equivalence | `agentstudio-git` seed validator and assembler | real-Git full-versus-proportional encoded snapshot parity |
| R-IRR-002 proportional work | literal-path diff and immutable combination | clean-tracked insertion and modified-row replacement parity plus per-path work counters and rich-fixture timing showing unrelated content work absent |
| R-IRR-003 exact admission | refresh coordinator scope classifier | table-driven exact/overflow/suppressed/root/status/Git-internal tests |
| R-IRR-004 full fallback | `agentstudio-git` refresh operation | real Git missing-row, nested attribute/ignore, add/delete/rename/type/index/ref fixtures reporting complete disposition, bounded reason, and exact result |
| R-IRR-005 currentness | fresh resolver plus Review generation | deterministic target/HEAD/base and newer-invalidation races |
| R-IRR-006 atomic install | existing publication and worker/main final barrier | browser integration proving no partial candidate is observable |
| R-IRR-007 retry | refresh admission plus existing retry owner | deterministic proportional rejection, fallback failure, retry, and no-loop tests |
| R-IRR-008 bounds | calculation holder and opaque value lifecycle | active/candidate count and retained-byte stress inspection |
| R-IRR-009 compatibility | hard-cut local client/provider integration | current PR0 semantic fixtures plus Vite and packaged comment journeys |
| R-IRR-010 real proof | packaged and development complete-journey harnesses | rich fixture, one-file edits, failed-attempt retention, and usable-paint distributions |

Cheap proof layers own pure scope classification, seed-key equality,
same-path splice/remove behavior, ordering, and state transitions. Real Git
integration owns filters, hashes, binary, modes, pathspec behavior, and complete
fallback parity. Vite and packaged tests own end-to-end filesystem observation,
construction, transport, presentation, and comment continuity.

## Dependency rules

- Agent Studio may retain and return the opaque seed but may not inspect or
  combine its Git rows.
- `agentstudio-git` may not import Agent Studio, Bridge, UI, transport, comment,
  or publication types.
- Refresh admission may classify path coverage but may not decide Git change
  kind or rename behavior.
- Shared construction may carry the seed but may not make it presentation
  authority.
- Publication may commit or retire the seed with native source truth but may not
  use it as displayed-publication identity.
- Browser and transport remain unaware of proportional calculation.
