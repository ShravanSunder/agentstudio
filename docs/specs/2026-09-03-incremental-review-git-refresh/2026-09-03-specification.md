# Incremental Review Git Refresh — Specification

Date: 2026-09-03

Governing requirements:
[2026-09-03-requirements.md](./2026-09-03-requirements.md).

Program realization:
[2026-09-03-program-design.md](./2026-09-03-program-design.md).

## Observable model

An already-published Review may be refreshed by either proportional
calculation or complete calculation. Both produce the same externally
observable result: one complete current Review candidate installed through the
existing atomic presentation path.

```text
worktree invalidation
        |
        v
is the affected scope exact and safely proportional?
        |
        +-- yes --> recompute affected Git facts
        |             |
        |             v
        |         assemble complete private successor
        |
        `-- no ---> fresh complete comparison
                      |
                      v
             one complete current candidate
                      |
                      v
          existing ordinary/promoted presentation
```

The calculation choice is not visible product state. Review still presents
complete snapshots, complete deltas between snapshots, retained predecessors,
and explicit failure according to the existing Review contracts.

## Terms

**Complete predecessor** means one previously completed Review calculation with
its exact repository, worktree, selected-target intent, resolved target,
reviewed HEAD, effective base, comparison options, ordered file metadata, and
calculation identity.

**Exact affected scope** means a nonempty, worktree-relative path set whose
producer confirms that no relevant path was suppressed, overflowed, replaced by
a directory/root marker, or reduced to status-only or Git-internal evidence.

**Ordinary proportional modification** means an exact affected scope for which
both predecessor and fresh affected-path calculation contain only same-path
tracked modifications with no rename/copy relationship or structural control
effect.

**Structural or uncertain change** means any case that does not satisfy the
ordinary proportional modification contract.

## Normative requirements

### R-IRR-001 — Complete-result equivalence

Every successful proportional refresh MUST produce the same complete ordered
Review file metadata that a fresh complete comparison would produce for the
same captured repository state.

Equivalence includes file membership, current and previous paths, change kind,
file identity, old and new modes, content hashes and algorithms, size, binary
classification, additions, deletions, and ordering.

A proportional calculation MUST NOT publish partial success or expose its
intermediate path results.

Basis: U-IRR-002, U-IRR-004.

### R-IRR-002 — Proportional ordinary modification

When a complete predecessor is current, source identities are unchanged, the
affected scope is exact, and every affected path is an ordinary proportional
modification, the refresh MUST avoid content loading, hashing, filtering, patch
generation, and line-stat calculation for unrelated Review paths.

An ordinary proportional modification may either replace an existing
same-path modified predecessor row or insert a newly modified tracked path that
had no predecessor row.

The cost of this refresh class MUST be bounded by affected-path work plus
complete-successor metadata assembly; it MUST NOT repeat per-file Git content
calculation across the unrelated predecessor file set.

Basis: U-IRR-001, U-IRR-008.

### R-IRR-003 — Exact-scope admission

Proportional calculation MUST be admitted only when all affected paths belong
to the reviewed worktree and the invalidation explicitly establishes complete
path coverage.

An empty path set, directory/root notification, suppressed path, overflow,
status-only notification, Git-internal notification, cross-worktree event, or
unknown coverage MUST NOT establish proportional authority.

Repeated ordinary invalidations MAY be coalesced by set union only while their
common worktree, source authority, and complete-coverage guarantees remain
valid.

Basis: U-IRR-003, U-IRR-005.

### R-IRR-004 — Conservative complete fallback

The refresh MUST use a fresh complete comparison when any affected or returned
file is added, untracked, deleted, renamed, copied, type-changed, conflicted, or
paired with a different previous path.

It MUST also use a fresh complete comparison when an affected path can change
Git interpretation outside itself, including `.gitattributes`, `.gitignore`,
repository configuration, index or ref state, comparison target, reviewed HEAD,
effective base, or comparison options.

An unexpected affected-path result, a missing predecessor entry when the fresh
result requires one, an incompatible predecessor row, duplicate path, identity
mismatch, capacity violation, or calculation failure MUST NOT be silently
spliced into the predecessor.

For every affected path, the scoped Git result MUST contain exactly one
same-path tracked modification before proportional assembly is allowed. That
row replaces a compatible predecessor row or is inserted when the predecessor
contains no row for the path. No row, multiple rows, an incompatible
predecessor row, a previous path, or any other change kind MUST use a fresh
complete comparison.

A missing scoped row may mean a true reversion to the comparison base, an
irrelevant filesystem event, or a symlink-canonical filesystem path that does
not match Git's byte-sensitive path spelling, case, or Unicode normalization.
Absence alone cannot safely remove a predecessor row or prove that no Review
fact changed.

Any refresh scope with one or more suppressed ignored paths MUST use the
complete comparison. This first realization deliberately keeps the existing
conservative filesystem classification rather than trying to prove whether a
suppressed path is tracked. The system MUST report proportional-admission
counts and rejection reasons so the cost of this fallback is measurable.

Basis: U-IRR-002, U-IRR-003.

### R-IRR-005 — Current identity and generation

Every attempt MUST freshly resolve and bind the selected target, reviewed HEAD,
effective comparison base, worktree identity, and newest admitted Review
generation before its result may become current.

A proportional attempt MUST use a predecessor whose bound identities and
comparison options equal the attempt’s identities. A mismatch retires
proportional authority and requires a complete comparison.

Only the newest admitted generation may install. A stale proportional or
complete result MUST be rejected without changing the retained complete Review.

Basis: U-IRR-002, U-IRR-005.

### R-IRR-006 — Private candidate and atomic installation

Proportional calculation MUST construct one complete immutable successor away
from displayed state. The existing Review publication and presentation owners
MUST install that successor atomically using the same ordinary/promoted
classification, display-predecessor, annotation, selection, and comment
continuity rules as a complete refresh.

The calculation mechanism MUST NOT become a second presentation class or
source of visible Review truth.

Basis: U-IRR-004.

### R-IRR-007 — Concurrent mutation and retry

If a newer invalidation arrives while proportional work is running, the current
attempt MUST become ineligible to install. Its exact affected paths MUST remain
eligible for union into the newest work when their coverage remains complete.

If proportional validation fails while the attempt remains current, the system
MAY perform the existing complete comparison as that attempt’s conservative
calculation path. This fallback is not a second user-visible retry and MUST NOT
create an automatic retry loop.

If complete fallback fails, the existing retry and failure contract applies:
retain the last complete Review, expose retry only when the failure is
retryable, and admit at most the existing bounded automatic retry.

Basis: U-IRR-003, U-IRR-005.

### R-IRR-008 — Retention and release

The system MAY retain complete Git metadata needed to calculate a successor.
Retained material MUST be bounded to current calculation authority and MUST be
released when its owning worktree/session closes, its comparison identity is
retired, or its successor is no longer eligible for reuse.

The calculation optimization MUST NOT retain source-file bytes, rendered
content, transport frames, comments, or an unbounded history of snapshots or
generations.

Retained calculation metadata is disposable acceleration. It MUST NOT replace
persisted comparison-target intent, published Review authority, or displayed
publication identity.

Basis: U-IRR-006, U-IRR-007.

### R-IRR-009 — Compatibility and negative space

Initial Review construction without a compatible complete predecessor MUST use
a complete comparison. Existing target selection, contribution-base semantics,
staged-deletion/same-path-recreation behavior, content demand, annotation
commands, metadata transport, and ordinary/promoted presentation MUST remain
unchanged.

No caller may emulate Git combination or rename policy outside
`agentstudio-git`. No path-by-path result may cross the metadata transport as a
partially current Review.

Basis: U-IRR-002, U-IRR-004, U-IRR-006.

### R-IRR-010 — Proof obligations

Proof MUST compare proportional results with fresh complete results across:

- one and multiple same-path tracked modifications;
- a reversion to the comparison base whose missing scoped row selects complete
  fallback and remains equivalent to a fresh result;
- staged and unstaged modifications;
- edit bursts and a mutation racing calculation;
- add, untracked, delete, rename, copy, type-change, conflict, binary, symlink,
  executable-mode, case-variant and NFC/NFD path spelling, nested
  attribute/ignore, index, ref, target, and base changes;
- missing, stale, mismatched, and capacity-rejected predecessors.

The rich-fixture proof MUST establish identical complete encoded metadata and
must separately measure complete initial capture, ordinary one-file refresh,
fallback refresh, complete successor assembly, publication, and usable paint.
It MUST show that ordinary one-file Git content calculation does not scale with
the unrelated Review file count.

Both the development-server composition and packaged WKWebView composition
MUST exercise the real filesystem, `agentstudio-git`, native construction,
metadata transport, and displayed Review. Failed or missing attempts remain
failed evidence rather than discarded samples.

Basis: U-IRR-008.

## Observable journeys

### One tracked file changes

```text
reviewer sees complete Review A
  -> one tracked file is edited
  -> Review A remains usable
  -> one complete Review B becomes ready
  -> B is semantically identical to a fresh complete comparison
  -> existing presentation policy installs or holds B
```

Unrelated Review files must not undergo new Git content calculation during this
journey.

### Several ordinary edits arrive together

The system may coalesce exact affected paths and produce one newest complete
successor. It must not install one intermediate Review per filesystem callback.

### Structural or uncertain change arrives

The system performs the existing complete comparison. The retained Review stays
usable, and failure cannot fabricate a current partial candidate.

### A new edit races proportional calculation

The earlier candidate cannot install. The newest attempt receives the combined
eligible affected scope or performs complete fallback, then produces one newest
complete successor.

### No compatible predecessor exists

Initial load, source replacement, target/HEAD/base movement, retired state, and
recovery without compatible retained metadata use a complete comparison.

## Requirement coverage

| Need | Problem/outcome | Requirement | Observable contract | Proof modality |
| --- | --- | --- | --- | --- |
| U-IRR-001 | one edit currently scales with unrelated Review size | R-IRR-002 | unrelated paths receive no Git content calculation | trace plus performance measurement |
| U-IRR-002 | speed cannot weaken Review truth | R-IRR-001, R-IRR-004, R-IRR-005 | proportional and full snapshots are equivalent | real-Git automated behavior plus encoded-state inspection |
| U-IRR-003 | incomplete paths cannot authorize partial truth | R-IRR-003, R-IRR-004 | uncertain input selects complete calculation | automated boundary and failure behavior |
| U-IRR-004 | visible Review remains complete and interactive | R-IRR-006, R-IRR-009 | one atomic successor through existing presentation | browser and packaged runtime evidence |
| U-IRR-005 | bursts converge on newest work | R-IRR-005, R-IRR-007 | stale candidates never install | deterministic concurrency behavior plus runtime trace |
| U-IRR-006 | one Git semantics owner | R-IRR-009 | callers cannot combine Git rows independently | architecture enforcement and integration behavior |
| U-IRR-007 | acceleration remains bounded | R-IRR-008 | no source bytes or unbounded history retained | state inspection and stress measurement |
| U-IRR-008 | improvement is real | R-IRR-010 | parity and proportional cost on rich fixture | automated parity, performance, Vite, and packaged evidence |
