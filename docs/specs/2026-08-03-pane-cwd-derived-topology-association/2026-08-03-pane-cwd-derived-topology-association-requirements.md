# Pane CWD-Derived Topology Association — Requirements

Status: candidate requirements for one specification/program-design review cycle.

## Problem and required outcome

Agent Studio stable 0.0.68 lost recently created panes and drawer ordering after
a restart. The workspace had stopped committing snapshots more than 25 hours
earlier because live pane metadata retained a deleted worktree UUID. Every later
save validated that stale UUID against SQLite, failed as one indivisible
workspace save, and left the last older snapshot as the only state available to
restore.

The required outcome is narrower than a general persistence redesign:

- a pane owns its filesystem location as a CWD when its content requires one;
- current repository topology derives any repo/worktree association from that
  CWD;
- generic pane persistence does not store topology UUID associations;
- malformed legacy pane or topology state cannot crash the scoped startup path
  or wedge later workspace saves; and
- a normal registered repository has one truthful main worktree at its repo
  path rather than making a repo-without-a-worktree a supported product model.

The production incident and evidence are recorded in
`tmp/debug-workflows/2026-08-03-agent-studio-fix-bugs-save-production-workspace-save-loss/debug-investigation.md`.

## Evidence boundary

Directly observed:

- stable emitted 62,349 `workspace.save` / `commit_core` failures before the
  restart;
- live telemetry showed 47 panes while the restored committed database held 44;
- two logged panes retained worktree identities that topology no longer held;
- SQLite had applied `ON DELETE SET NULL` to their committed facet references,
  while the pre-restart live graph retained the deleted UUIDs;
- production `quick_check` and `foreign_key_check` passed, and saving resumed
  after restart;
- all 44 currently committed production Terminal panes have both a CWD and a
  launch directory; and
- production topology currently contains 164 repos, including 12 with no
  worktree and 2 whose repo-path worktree is not marked main. The schema and
  `RepositoryTopologyReplacement` currently permit those degraded states.

Inferred from the incident evidence and current source:

- the data loss was rollback to an older coherent snapshot, not zmx loss or
  SQLite file corruption;
- a generic pane-to-topology foreign key is the wrong consistency boundary
  because topology can legitimately change independently of pane lifetime; and
- repo/worktree association is a current projection, not durable pane identity.

## Terms

`CWD`
: The normalized absolute filesystem directory that locates a pane's current
  filesystem context. It is a pane fact, not proof that a matching repo or
  worktree is registered.

`required-location pane`
: A pane whose product content cannot be truthful without a filesystem
  directory: Terminal, Bridge Files, Bridge Review, and Code Viewer.

`optional-location pane`
: A pane whose product content may be truthful without filesystem context:
  generic Webview and an unsupported future/plugin pane whose preserved content
  contract does not declare a filesystem requirement.

`derived association`
: The repo/worktree projection obtained by path-aware lookup of the pane CWD in
  the current repository topology. It is never independently persisted as a
  generic pane fact.

`available repository`
: A registered non-bare working repository whose local checkout is admitted by
  the existing topology/discovery lifecycle. A deliberately unavailable or
  missing checkout is retained as degraded topology but is not a source of a
  fabricated pane association.

## Scope

This specification governs:

- pane location requirements at product creation, runtime update, restore, and
  save boundaries;
- path-derived pane association to the current repo/worktree topology;
- the available-repository main-worktree invariant needed to make repo-root
  containment unambiguous;
- removal of generic pane `facet_repo_id` and `facet_worktree_id` persistence;
- migration of existing production SQLite databases; and
- failure containment, telemetry, and proof for this incident class.

This specification does not:

- redesign Git discovery, watched paths, repo lifecycle, zmx, pane/drawer/tab
  layout, or the workspace transaction model;
- add a second mapping table, durable path-to-UUID cache, compatibility write
  path, feature flag, or parallel persistence format;
- define dormant Docker, Gondolin, remote, or bare-repository behavior without
  evidence that the current product path uses it;
- make generic Webviews filesystem-backed;
- reinterpret Bridge content-specific source intent as generic pane topology
  identity; or
- promise that unrelated failures can never crash the application. The crash
  and continuity requirements below apply to pane location, topology
  association, migration, restore, and workspace-save behavior in this scope.

## Required behavior

### PR-01 — CWD is the durable pane-owned association input

Generic pane persistence must store at most the pane's normalized CWD as its
filesystem association input. It must not store generic repo or worktree UUIDs,
and it must not require either UUID to encode, validate, save, or restore a pane.

Names, branches, checkout refs, Bridge source parameters, and other
content-specific facts retain their existing owners. None may silently become a
second generic repo/worktree association authority.

Acceptance:

- deleting, replacing, or re-identifying topology rows cannot make an otherwise
  valid pane row unsavable;
- the `pane` schema has no `facet_repo_id` or `facet_worktree_id` columns,
  foreign keys, or validation triggers; and
- state bridges/codecs do not round-trip those UUIDs as durable pane graph data.

### PR-02 — Required-location versus optional-location panes

The product location contract is exhaustive for current pane content:

| Pane content | Location contract | Canonical source when creating or repairing |
| --- | --- | --- |
| Terminal | required CWD | accepted explicit/inherited directory; otherwise a deliberate local fallback directory |
| Bridge Files | required CWD | selected workspace/worktree root |
| Bridge Review | required CWD | selected workspace/worktree root |
| Code Viewer | required CWD | parent directory of its file path |
| generic Webview | optional CWD | explicit contextual CWD when present; otherwise none |
| unsupported/plugin | optional unless its recognized contract says otherwise | preserved contract or none |

The implementation may use a discriminated location type or equally exhaustive
content policy, but it must not preserve today's accidental “all fields are
optional for all panes” semantics at creation and validation boundaries.

For a context-free Terminal action, the fallback must be an existing, stable,
user-safe local directory such as the user's home directory. A temporary
directory is not the normal fallback because cleanup would make the durable CWD
ephemeral.

Acceptance:

- every newly accepted required-location pane has a non-nil normalized absolute
  CWD before it enters a durable layout;
- generic Webview creation remains valid without CWD; and
- unsupported content remains round-trippable and cannot block a workspace
  save merely because its location policy is unknown.

### PR-03 — Runtime CWD updates preserve the last valid required location

A valid absolute runtime CWD update replaces the pane's current CWD. An invalid,
relative, malformed, or transiently unavailable runtime sample must not clear
the last valid CWD of a required-location pane.

An optional-location pane may remain locationless. Runtime updates do not write
repo/worktree UUIDs into pane-owned state; association changes through the
derived projection.

Acceptance:

- a required-location pane receiving an invalid CWD sample remains saveable and
  retains its last accepted CWD;
- a later valid sample changes its CWD and immediately changes derived
  association if containment changes; and
- no runtime CWD event needs a topology mutation or pane UUID-facet cleanup.

### PR-04 — Deterministic deepest-path association

Given a normalized pane CWD and valid current topology, association uses
path-component containment, not string-prefix coincidence.

1. Choose the deepest registered worktree path equal to or containing the CWD.
2. Return that worktree and its owning repo as one coherent pair.
3. The main worktree at `repo.repoPath` therefore owns the repo root and all
   descendants not captured by a deeper linked-worktree path.
4. If no admitted worktree contains the CWD, return no association.

Tie-breaking for duplicate-depth corrupt candidates must be deterministic and
must emit a scrubbed diagnostic; valid topology must reject or repair the
ambiguity rather than make arbitrary association a normal state.

Acceptance examples:

| CWD | Registered topology | Required result |
| --- | --- | --- |
| `/repo` | main `/repo` | repo + main |
| `/repo/Sources/A` | main `/repo` | repo + main |
| `/worktrees/feature/Sources` | linked `/worktrees/feature` | repo + linked worktree |
| `/repo-tools` | only main `/repo` | no match |
| `/deleted/path` | no admitted containing worktree | no match; pane remains saveable |

### PR-05 — Available repository main-worktree invariant

Every available registered non-bare repository must expose exactly one main
worktree, and that worktree's normalized path and stable key must correspond to
`repo.repoPath`.

Topology admission and restore must handle historical violations before the
topology becomes association-authoritative:

- a unique existing worktree whose canonical stable identity equals the
  repository root may be normalized as main while preserving its UUID and
  note;
- a missing main worktree may be reconstructed only from existing authoritative
  Git discovery for a verified primary checkout;
- multiple worktrees claiming the repository root's canonical stable identity
  must not be guessed between: every ambiguous root claimant is discarded,
  unrelated linked-worktree rows retain their UUIDs and notes, and the repo
  becomes unavailable/degraded until authoritative discovery repairs it;
- topology replacement rejects duplicate repository, worktree, and watched-path
  stable identities globally, including within or across unavailable repos;
- a repo path that cannot be verified becomes unavailable/degraded and is
  excluded from pane association until ordinary discovery repairs it; and
- removing a linked worktree is ordinary reconciliation, while removing the
  main worktree transitions the repo to unavailable instead of admitting an
  available repo with no main; and
- every normalization or degradation decision must be deterministic,
  observable, and explicitly persisted through the existing topology owner so
  the same invalid snapshot is not reconsidered on every launch.

This is topology normalization, not pane lookup. Pane lookup must never create a
repo, worktree, UUID, or filesystem directory.

Acceptance:

- admitted topology cannot expose an available repo with zero or multiple main
  worktrees;
- the existing production cases with a repo-path worktree but `is_main_worktree
  = 0` retain that worktree ID when normalized;
- ambiguous canonical root claimants are removed without removing unrelated
  linked worktrees, and the cleaned degraded topology is persisted before any
  authoritative repair attempt;
- direct main-worktree unregistration cannot recreate an available repo with no
  main, and a later authoritative scan can restore availability;
- missing or ambiguous topology does not crash startup; and
- a repo left degraded cannot fabricate a pane worktree association.

### PR-06 — Association follows topology without pane mutation

Registering, unregistering, deleting, restoring, or re-identifying a worktree
must change pane association solely by changing topology and recomputing the
projection from CWD.

The pane's CWD and residency do not change merely because topology changes.
Existing topology-effect behavior that intentionally changes pane residency is
separate and must not be required to keep persistence valid.

Acceptance:

- unregistering a matched worktree removes or changes the derived association
  without changing the pane's CWD;
- re-registering a containing worktree makes the association reappear without
  rewriting the pane; and
- direct and scanned topology-event paths cannot diverge in save validity.

### PR-07 — Legacy restore is loss-averse and non-crashing

Migration and restore must preserve every structurally valid pane, drawer, tab,
arrangement, cursor, and ordering row. Legacy facet UUIDs are discarded as
non-authoritative; they are never used to override a CWD-derived result.

For a restored required-location pane with missing pane CWD, repair uses only an
existing trustworthy content fact:

- Terminal: persisted launch directory;
- Bridge Files/Review: workspace source root;
- Code Viewer: file-path parent.

If neither pane CWD nor a trustworthy content source exists, retain the pane in
an explicit degraded, non-crashing state rather than inventing repo/worktree
identity or silently deleting it. The degraded pane must remain representable,
closable, and saveable. Normal product creation must not create this state.

Acceptance:

- a legacy stale/missing facet UUID does not reject restore or save;
- a repairable missing CWD is restored deterministically;
- an unrepairable required-location pane does not disappear; and
- startup reports a scrubbed repair/degradation reason without raw paths or
  UUIDs in OTLP.

### PR-08 — One bad association cannot wedge workspace persistence

Workspace persistence must not validate or resolve derived repo/worktree UUIDs
while saving generic pane rows. A missing topology match is a valid projection
result, not a workspace-save error.

An invalid pane-location record may be diagnosed or represented as degraded,
but it must not cause all later unrelated pane/drawer/tab changes to remain
uncommitted. Structural composition corruption outside this specification may
still reject an atomic snapshot; this requirement does not weaken graph
integrity checks.

Acceptance:

- the exact sequence “worktree-backed pane → worktree unregistered → more pane
  and drawer mutations → save → restart” restores the later mutations;
- repeated autosaves and termination flush do not fail with
  `repoNotFound`/`worktreeNotFound` due to pane facets; and
- failure reporting distinguishes migration, structural composition, location
  degradation, and database-write failures using scrubbed reason codes.

### PR-09 — Scoped crash and startup-continuity guarantee

Pane location, topology normalization, migration, association lookup, restore,
and save paths must use recoverable validation. They must not call
`preconditionFailure`, force-unwrap malformed persisted values, or terminate the
application for the recoverable states defined above.

Acceptance:

- malformed legacy facet UUIDs, missing topology targets, missing required CWD,
  and missing-main topology each have a tested non-crashing outcome;
- startup reaches a usable workspace or the existing explicit database
  quarantine/recovery boundary; and
- termination flush accurately reports success only after the latest accepted
  snapshot commits.

### PR-10 — Production-safe hard-cut migration

The migration must make one forward schema cut:

1. drop the four pane-facet validation triggers;
2. drop `pane.facet_repo_id` and `pane.facet_worktree_id`;
3. retain `pane.cwd` and all unrelated pane/layout/content rows;
4. remove obsolete foreign-key/validation and bridge-codec behavior; and
5. validate the migrated schema, rows, foreign keys, and application restore.

The migration must use the existing GRDB migrator transaction and current
SQLite support. It must not rebuild the heavily referenced `pane` table when
direct column drop is supported, and it must not introduce a compatibility
write path or second durable mapping.

Acceptance:

- representative current, stale-facet, null-facet, missing-CWD, and topology-
  degraded fixtures migrate transactionally;
- `PRAGMA quick_check` and `PRAGMA foreign_key_check` pass after migration;
- pane, drawer membership, tab membership, arrangement, ordering, content,
  zmx anchor, CWD, launch-directory, note, and checkout-ref data are unchanged
  except for the two removed facet columns; and
- an interrupted/failed migration leaves the previous committed schema usable
  through SQLite transaction rollback or the existing quarantine owner.

### PR-11 — No association cache becomes a second authority

Derived repo/worktree values may be memoized or indexed only as rebuildable
topology projections. Any cache must invalidate on both CWD and topology
generation changes and must be reconstructable from those owners.

Acceptance:

- no new SQLite mapping table or pane UUID facet is introduced;
- cold restore produces the same association as a live topology change; and
- stale cache state cannot affect save validity.

### PR-12 — Observability is actionable and privacy-preserving

The scoped path must emit bounded, scrubbed reason codes for:

- topology normalization repaired / degraded / rejected;
- required-location restore repaired / degraded;
- pane association ambiguity; and
- workspace save failure phase and classified error kind.

OTLP must not include raw paths, pane/repo/worktree UUIDs, prompts, payloads, or
private error strings. High-frequency lookup misses are not emitted per read.

## User journeys

### J-01 — Worktree removal while panes remain

```text
pane CWD is inside worktree A
  → association projects repo R + worktree A
  → worktree A is unregistered
  → pane keeps its CWD and remains usable/saveable
  → association becomes the deepest remaining containing worktree or none
  → later pane/drawer mutations commit
  → restart restores the latest committed layout
```

### J-02 — Pane moves between checkouts

```text
Terminal reports valid CWD under worktree A
  → projection is R/A
Terminal reports valid CWD under worktree B
  → pane CWD changes once
  → projection becomes R/B
  → no generic topology UUID is written with the pane
```

### J-03 — Legacy production database upgrade

```text
existing core.sqlite contains facet UUID columns and stale/null values
  → transactional migration removes facet triggers and UUID columns
  → restore repairs location from trustworthy content facts where needed
  → topology normalization repairs only source-proven main worktrees
  → app starts without deleting panes
  → first post-upgrade save commits the complete current workspace
```

## Proof obligations

| Trace | Observable obligation | Minimum evidence |
| --- | --- | --- |
| Incident → PR-01/PR-06/PR-08 | Topology deletion cannot wedge later pane/drawer saves or roll restart back to an older snapshot. | RED current-source integration reproduction; GREEN save/restart integration with direct and scanned worktree-removal paths. |
| PR-02/PR-03/PR-07 | Required content always receives or repairs a CWD; invalid runtime samples retain the last valid location; unrepairable legacy panes survive degraded. | Exhaustive content-policy unit tests plus restore fixtures and a running-app Terminal/Webview check. |
| PR-04/PR-05/PR-06 | Deepest segment-aware lookup and main-worktree normalization are deterministic across startup and live topology changes. | Pure lookup table tests, topology admission/restore integration tests, and production-shaped degraded fixtures. |
| PR-09 | Every scoped malformed state has a recoverable result rather than a trap or crash. | Negative-path tests plus source inspection forbidding scoped `preconditionFailure`/force unwraps. |
| PR-10 | Production schema migrates transactionally without pane/layout loss. | Migration fixtures from predecessor schemas, row-by-row invariant comparison, `quick_check`, `foreign_key_check`, and restore/save round trip. |
| PR-11 | No second durable authority exists. | Schema/codec/source-structure assertions and cold/live projection equivalence tests. |
| PR-12 | Failure and repair evidence is actionable without leaking identifiers or paths. | Marker-scoped VictoriaLogs proof against the debug app and scrubbed attribute assertions. |

Required manual product proof uses a worktree-isolated debug app and a copied or
synthetic production-shaped database, never the live production database. It
must exercise Terminal, Bridge Files, Bridge Review, Code Viewer, generic
Webview, worktree removal/re-registration, save, clean restart, and pane/drawer
count/order comparison. Production remains read-only.

## Requirements completeness check

- Safety: PR-07 through PR-10 define preservation, failure containment,
  transactionality, and non-crashing recovery.
- Correctness: PR-01 through PR-06 define location ownership, exhaustive pane
  policy, topology invariant, and deterministic association.
- Lifecycle: creation, runtime mutation, topology mutation, migration, restore,
  save, termination flush, and restart are covered.
- Compatibility: one hard cut is required; unsupported pane content is preserved
  without retaining the obsolete generic facet contract.
- Privacy and observability: PR-12 preserves the repository's OTLP scrubbing
  boundary.
- Performance: lookup remains indexable by topology path and must not add
  per-read telemetry or database access.

No implementation is authorized by this requirements document. Structural How
belongs in the paired program design.
