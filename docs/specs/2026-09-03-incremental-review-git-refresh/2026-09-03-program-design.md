# Incremental Review Git Refresh — Program Design

Date: 2026-09-03

This design realizes
[2026-09-03-specification.md](./2026-09-03-specification.md), authorized by
[2026-09-03-requirements.md](./2026-09-03-requirements.md).

It supersedes PR0’s structural rule that every contribution invalidation must
discard its calculation predecessor and perform an unscoped complete Git
capture, plus the use of public Review generation as per-attempt freshness for
same-source refresh. It also makes the existing Review metadata delta and
affected-item application reachable on that path. PR0 and the refresh designs
remain authoritative for selected-target intent, fresh target/HEAD/base
resolution, direct base-to-working-tree result semantics, immutable origins,
atomic publication, displayed authority, failure behavior, and generic
transport mechanics.

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
  -> successor Review generation + fresh endpoint timestamps
  -> delta rejected
  -> reset + sourceAccepted + every metadata window
  -> unchanged worker/content/annotation work repeats
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
  -> stable same-source generation + higher revision
  -> one existing bounded Review delta
  -> affected content/presentation work only
  -> exact-publication annotation query
  -> equality-checked updates for affected mounted items only
```

No path-level candidate becomes visible. Native and worker owners still build
one complete private candidate, but the existing application-specific delta and
affected-item facts prevent unchanged metadata, content, and Pierre work from
crossing their expensive boundaries.

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

The downstream crux is whether one public Review generation means one attempt
or one semantic source lineage:

| Direction | Gain | Cost and rejection reason |
| --- | --- | --- |
| Advance generation for every refresh | Existing attempt fence remains overloaded | Existing delta, body reuse, and unchanged-source authority become unreachable; fails R-IRR-011 |
| Admit deltas across generations | Preserves current generation allocation | Requires new native/worker/content replay and rebinding semantics for unchanged sources; expands the generic boundary unnecessarily |
| Stable lineage generation plus existing attempt authority | Reuses current same-generation delta/content contracts and keeps stale work fenced | Requires attempt authority in scheduler freshness, stable endpoint identity, complete unchanged comparison, and equivalent development-host revision ownership |

The selected direction is stable lineage generation plus existing attempt
authority. This does not remove a currentness fence; it stops one identifier
from doing two incompatible jobs. Cross-generation delta is rejected because
unchanged content descriptors remain bound to their prior generation and would
require a broader transport/replay redesign.

For annotations, the selected direction retains the full exact-publication
query and makes only application selective. A partial native query was rejected
because changed lines, renames, unavailable material, and target/base movement
can alter placement without changing durable message identity. A full query
with affected-item plus equality-checked apply preserves truth without adding a
new annotation protocol.

## Components and ownership

```text
Agent Studio filesystem source
  owns: symlink-canonical FileChangeset and coverage facts
  emits: exact worktree-relative paths or non-exact invalidation

Bridge refresh admission
  owns: burst union, attempt authority generation, newest-work reservation
  carries: ReviewGitRefreshScope without interpreting Git

Review lineage and revision owners
  own: stable source-lineage generation, package/query identity, and monotonic
       revision inside one lineage
  advance lineage: explicit selected-source/package/query replacement
  advance attempt authority: every invalidation and retry

Bridge Review calculation holder
  solely owns: lifetime of one opaque active Git refresh seed
  writes: seed only at the post-construction calculation-currentness commit
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
        atomic install, retained content leases, affected item identities
  does not own: Git calculation or seed interpretation

Existing Review metadata/demand owners
  own: bounded delta application, changed content-source preparation, retained
       unchanged body/render material, and exact candidate promotion

Existing Review annotation application
  owns: exact-publication query and equality-checked affected-item application
  preserves: full query/fallback for unknown, replacement, or unsafe placement
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
path, status-only change, root/overflow summary, mixed authority,
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

### Attempt authority, source lineage, revision, and publication

The existing identities have separate jobs:

```text
attempt authority generation A
  changes for every invalidation and retry
  fences refresh reservation, scheduler coalescing, cancellation, and commit

Review source-lineage generation G
  remains stable while repository, worktree, selected symbolic target,
  package, query/source, and comparison scope remain one lineage
  changes for explicit source/package/query-lineage replacement

package revision R
  strictly increases for each changed successor inside stable G

publication identity P
  uniquely identifies the exact native/worker/main installation
```

An ordinary same-lineage edit therefore advances `A`, retains `G`, advances
`R`, and creates `P`. The refresh passes `A` into the existing Git scheduler and
shared-construction freshness identity so a new attempt cannot join physical
work captured for an older attempt merely because `G` is stable.

Same-lineage refresh requests reuse the current logical base/head endpoint
values, including their original creation timestamps. Contribution capture
updates resolved content/provider identity from freshly resolved Git facts.
Resolved target/HEAD/base movement changes origin or endpoint authority and
therefore selects reset even when the symbolic source lineage remains stable.
An explicit selected target, package, query, repository, or worktree lineage
replacement advances `G`.

The unchanged test compares normalized query, endpoint authority, comparison
origin, reviewed subject, ordered items, groups, summary, and content identities.
Equal file rows alone cannot discard an origin-only successor.

`BridgeDevelopmentProductHost` derives the same stable package/query lineage
and next revision from its existing current committed publication instead of
minting package/query identities with revision zero for every observed refresh.
Its existing refresh reservation and publication coordinator remain the
attempt and commit owners; no development-only state service is added.

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

Every successful complete, proportional, or proportional-fallback result
returns a successor seed, including when its complete projection equals the
predecessor. Equal projection does not imply equal freshly resolved calculation
identity.

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

After replacement/insertion, `agentstudio-git` sorts with the existing path order,
checks unique current and previous-path membership, and creates the successor
seed from that complete projection.

Any rejected condition discards the private candidate and runs the existing
unscoped direct comparison in the same repository operation. It does not return
partial state or make Bridge combine Git rows.

### Proportional Review delivery and annotation application

For a changed same-source package inside the existing delta bounds,
`BridgeChangeIndex` keeps `G`, advances `R`, and builds the existing complete
package delta. `BridgePaneProductReviewMetadataSource` emits one sealed
`review.delta`. A new or reopened subscription with no delivered predecessor
receives the existing `sourceAccepted` plus complete windows, with no reset.
An active incompatible predecessor, unknown impact, or over-cap delta receives
the existing reset, `sourceAccepted`, and complete windows.

The worker applies the delta to a private clone of the active complete
projection. Its existing runtime-signature comparison produces exact affected
item identities; unchanged content-source descriptors, resident bodies, demand
preparations, and main render copies remain valid because their lineage and
content identities did not change.

Those affected item identities remain application-specific Review data. The
existing candidate/promotion/render-store path carries them through atomic main
promotion and publishes keyed changes for affected items rather than a catalog
reset for a same-source delta. The generic product transport gains no field,
message, queue, or application knowledge. Unknown or replacement affectedness
means all items, never none.

Before Review annotation source refresh opens any content, its existing source
capture derives affected current/previous Review item identities from the
installed publication's same-`G` delta and exact retained predecessor. It asks
the existing `BridgeReviewContentLoaderCache` whether every unaffected demanded
handle can be served under the same exact content identity without a provider
load. This is an admission check on the current bounded cache, not a new cache
or retention promise.

When every unaffected handle is reusable, Review annotation capture continues
to query the complete currently demanded-session projection against the exact
installed publication. Unaffected source loads are cache-only; affected handles
may open through the provider. When any unaffected handle is not reusable,
source affectedness becomes unknown and the existing full safe query/application
path runs without claiming proportional source work. Telemetry records this
fallback reason. The full path remains correct under ordinary LRU eviction,
including demanded material larger than the cache.

This preserves placement truth for changed lines, unavailable material,
renames, held candidates, and active editors. After query installation, the
Review-specific annotation application forms candidate item identities from:

- promoted affected current and previous Review item identities;
- previous/current owners of changed annotation placements;
- active composer/editor item identities.

It derives annotations only for those candidates, compares the derived
annotation presentation with the currently installed Pierre item, and advances
the item version/calls `applyItemUpdate` only when presentation changed.
Replacement, unknown affectedness, target/base movement, or unsafe placement
uses full application with the same equality check. Candidate annotations never
touch the active surface before the installed-publication receipt.

## State and lifecycle

The Bridge calculation holder has one bounded state machine:

| State | Stored material | Transition |
| --- | --- | --- |
| Empty | no seed | initial/source/target recovery performs complete calculation |
| Active | one seed bound to newest native-complete calculation | exact ordinary invalidation starts candidate from active seed |
| Active + candidate | active seed plus private in-flight successor | successful current commit replaces active; stale/failure discards candidate |
| Retired | no reusable seed | source/target/base retirement or close clears seed and returns to Empty/closed |

The seed becomes active synchronously after the complete construction result
passes the final post-construction attempt-authority, foreground/product,
identity, and predecessor-publication checks. This calculation commit occurs
before the unchanged-versus-publication branch. It does not wait for main
display installation: calculation continuity follows newest native-complete
source truth, while presentation classification continues to use the
acknowledged displayed publication. These are separate existing planes.

An unchanged same-lineage load therefore replaces the active seed without
creating a publication. Equal visible metadata does not make the successor seed
optional: it binds fresher calculation authority needed by the next refresh.

A held displayed predecessor may therefore coexist with a newer calculation
seed. That seed can construct another complete successor; impact classification
still measures displayed publication to the newest candidate through the
existing displayed-source receipt contract.

The calculation holder retains no seed for failed, stale, superseded, or
pre-calculation-commit candidates. A later publication rejection does not undo
an already current calculation seed; restored dirty scope and newer attempt
authority still prevent it from authorizing stale installation. Closing the
pane or provider releases active and in-flight values. Shared template copies
use Swift copy-on-write storage and do not create independent file-array
buffers unless mutated inside `agentstudio-git` candidate construction.

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
      + attemptAuthorityGeneration
      + active opaque seed
      -> Review pipeline/contribution capture

[~] AgentStudioGitBridgeReviewDataClient
      maps attempt authority, scope, and opaque seed only
      -> existing Git scheduler freshness includes attempt authority
      -> agentstudio-git contribution/direct refresh request

[~] agentstudio-git
      freshly resolves target/HEAD/base                  [=]
      validates seed and scoped result                   [+]
      exact safe scoped comparison OR complete fallback [+]
      -> complete snapshot + successor seed

[~] Bridge shared Review template
      complete template/content backing                 [=]
      carries opaque successor seed                     [+]

[+] native calculation commit
      final attempt/currentness check
      -> replaces active seed, including unchanged result

[~] native publication commit
      same-source: stable G, higher R, new P
      replacement: higher G, reset lineage
      commits complete package atomically              [=]

[~] Review metadata publication
      same-source bounded delta OR complete reset
      -> worker candidate
      -> affected identities survive atomic main install or promoted hold
      -> unchanged content/render work remains retained
      -> result/failure to existing owners

[~] Review annotation application
      exact installed-publication query                [=]
      -> affected/full candidate set by known authority
      -> equality-checked Pierre updates only           [+]

[~] BridgeDevelopmentProductHost
      stable package/query lineage and monotonic revision
      -> same generation/delta behavior as packaged controller
```

No new process, watcher, queue, worker, scheduler, transport message, or browser
state is added.

## Normal sequences

### One ordinary tracked edit

```text
Filesystem   Refresh authority   Bridge/Git          Worker/Main       Annotation/Pierre
    |                |               |                    |                    |
    |-- file path -->|               |                    |                    |
    |                |-- A+1 ------->|                    |                    |
    |                |               | seed + path + A    |                    |
    |                |               | resolve IDs        |                    |
    |                |               | scoped direct diff |                    |
    |                |               | complete snapshot  |                    |
    |                |               | calculation commit |                    |
    |                |               | G stable, R+1, P   |                    |
    |                |               |-- review.delta --->|                    |
    |                |               |                    | affected content   |
    |                |               |                    | atomic promotion   |
    |                |               |                    |-- installed P ---->|
    |                |               |                    |                    | exact query
    |                |               |                    |                    | changed items only
```

### Structural or uncertain change

The same sequence carries `.complete`. `agentstudio-git` runs the existing
complete direct comparison and returns a new seed. If semantic source lineage
and bounded delta admission still hold, publication may remain same-generation;
otherwise generation advances and downstream uses reset plus full safe
application. Uncertainty never becomes an empty affected set.

## Concurrency and consistency

Attempt authority generation is the physical-work/current-attempt fence. Review
generation remains the public source-lineage fence; revision orders successors
inside that lineage; publication identity fences exact installation. Refresh
scope and active seed are read under the same attempt authority used in Git
scheduler freshness and construction.

If a newer invalidation arrives:

1. refresh admission advances attempt authority and restores/merges dirty facts;
2. the running blocking Git call may finish physically;
3. its attempt-authority/admission check rejects calculation/publication commit;
4. its successor seed is discarded;
5. the newest reservation receives the merged exact paths, or `.complete` if
   any merged fact is uncertain.

The Git request opens one repository and resolves target/HEAD/base before using
the seed. It rechecks the resolved identities after scoped calculation before
returning proportional success. Identity movement converts the attempt to
complete fallback; it never commits a seed assembled across two identities.

No lock is placed on the worktree. A filesystem mutation racing either scoped
or complete calculation is handled by the existing observer-before-capture and
newest-attempt-authority rejection model. Proportional calculation does not
claim stronger repository atomicity than the current complete reader.

A stable-`G` successor cannot join an older Git read because `A` participates in
the scheduler freshness identity. A late lower `R`, mismatched predecessor
publication, or retired `P` is rejected. Source/query-lineage replacement
advances `G`; resolved-origin movement within the same symbolic lineage keeps
`G` but forces reset and publishes the changed origin at higher `R`.

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

same-source delta is absent, incompatible, or over capacity
  -> keep complete candidate truth
  -> reset + sourceAccepted + complete windows
  -> affected annotation identity becomes all

affected item identity is unknown or placement cannot be preserved
  -> never interpret empty as no change
  -> full annotation application with per-item equality suppression

unaffected demanded annotation handle is not resident under exact identity
  -> do not claim proportional native source work
  -> full safe query/application may open provider content
  -> record cache-residency fallback reason

active composer/editor item is affected
  -> existing preparation/hold policy decides installation
  -> no candidate annotation touches active Pierre state before promotion
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

Complete native/worker candidate assembly, rollback capture, and internal index
maintenance may remain linear in metadata cardinality. This design does not add
a persistent tree or copy-on-write graph to remove those scans. The required
proportional boundary is expensive unrelated I/O and externally propagated
work: Git/content reads, metadata frames, demand preparation, keyed main
notifications, annotation derivation, and Pierre updates. Measurement may
justify a later internal data-structure change; it is not assumed here.

The existing annotation content-loader cache remains bounded by current policy;
this design neither enlarges it nor turns residency into correctness authority.
Residency only admits the no-unaffected-provider-load performance claim. An
evicted unaffected handle selects the full safe path, which remains correct and
observable as a proportional-admission rejection.

Performance probes distinguish:

- changed-path admission and count;
- proportional admitted/rejected/fallback disposition;
- seed validation and candidate assembly;
- scoped Git comparison;
- complete Git comparison;
- package construction, publication event kind/count, and usable paint;
- unchanged/changed worker content opens and preparations;
- affected identities carried through promotion;
- annotation query scope, cache-hit/provider-load counts for affected and
  unaffected handles, and changed/unchanged Pierre item update counts.

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
| R-IRR-005 currentness | attempt authority, fresh resolver, lineage generation, revision, and publication identity | deterministic old-read coalescing, target/HEAD/base, origin-only, lower-revision, and newer-invalidation races |
| R-IRR-006 atomic install | existing publication and worker/main final barrier | browser integration proving no partial candidate is observable |
| R-IRR-007 retry | refresh admission plus existing retry owner | deterministic proportional rejection, fallback failure, retry, and no-loop tests |
| R-IRR-008 bounds | calculation holder and opaque value lifecycle | active/candidate count and retained-byte stress inspection |
| R-IRR-009 compatibility | hard-cut local client/provider integration | current PR0 semantic fixtures plus Vite and packaged comment journeys |
| R-IRR-010 real proof | packaged and development complete-journey harnesses | rich fixture, one-file edits, failed-attempt retention, and usable-paint distributions |
| R-IRR-011 proportional downstream application | existing Review delta, runtime affected identities, content/body retention, pre-source-load cache admission, and annotation equality application | 4,096-item one-change delta, zero unchanged provider opens when admitted, over-128-MiB eviction fallback, keyed promotion notifications, placement/rename/unavailable/editor/held tests, and unchanged Pierre update count zero |

Cheap proof layers own pure scope classification, seed-key equality,
same-path replacement/insertion behavior, A/G/R/P state transitions, delta admission,
affected-identity propagation, and annotation equality. Real Git integration
owns filters, hashes, binary, modes, pathspec behavior, and complete fallback
parity. Vite and packaged tests own end-to-end filesystem observation,
construction, transport, content-opening counts, presentation, annotation
placement, and comment continuity.

## Dependency rules

- Agent Studio may retain and return the opaque seed but may not inspect or
  combine its Git rows.
- `agentstudio-git` may not import Agent Studio, Bridge, UI, transport, comment,
  or publication types.
- Refresh admission may classify path coverage but may not decide Git change
  kind or rename behavior.
- Attempt authority must reach Git/shared-construction freshness; public Review
  generation must not substitute for per-attempt freshness.
- Shared construction may carry the seed but may not make it presentation
  authority.
- The calculation holder commits or retires the seed with native source truth;
  publication may not use it as displayed-publication identity.
- Generic transport remains unaware of proportional calculation and affected
  annotation semantics; existing Review application owners carry those facts.
- Annotation application may suppress equal item updates but may not weaken the
  exact installed-publication query or replacement/unknown full fallback.
- Annotation cache residency may admit a proportional performance path but may
  never establish placement truth or suppress the full safe fallback.
