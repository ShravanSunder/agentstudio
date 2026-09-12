# Repository and Checkout Lifecycle Specification

[Requirements](requirements.md) → this Specification. Structural realization is a separate downstream artifact.

## What the user experiences

A missing location leaves the normal repository list, but its application record is retained for 30 days. Returning to the same canonical path restores that record. A different location is not assumed to be the old one. No user Repair action is involved.

```text
                        successful validation at the same canonical path
                    +---------------------------------------------------+
                    |                                                   |
                    v                                                   |
                AVAILABLE -- authoritative absence --> HIDDEN, RETAINED -+
                                                        |
                                             30 days since first absence
                                             + current absence confirmed
                                                        |
                                                        v
                                                   COLLECTED

Unproven different path -> independently validated new record
                            (does not alter the old record's deadline)
```

“Hidden” is an internal lifecycle state, not a screen or an extra user task. A hidden old record and a visible new record can coexist without two active rows. If both paths later exist, both may legitimately represent separate checkouts/clones.

```text
User changes watched folders ---> [ Agent Studio ] ---> Repository list/search
Package discovery facts --------> [ opaque system ] ---> Existing panes retained
App restart / elapsed time -----> [               ] ---> Durable lifecycle cleanup

Outside this contract: deleting user folders, changing Git metadata,
manual Repair UI, terminating panes because a repository disappeared.
```

## C1 — Evidence and identity (R1; U2, U3, U6, U7)

**R1.** Same-canonical-path rediscovery before collection MUST reuse the retained application identity and clear hidden state. This is a location identity policy, not a claim that the files could not have been replaced while absent. After collection, discovery creates a new identity.

All Git validation and checkout-family facts MUST come through `agentstudio-git` and its libgit2-backed discovery boundary. Its currently pinned revision is `c8dbd7ef0f344293160b8f7d72d93931328761fd`.

The evidence admitted by this scope is:

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Equal validated canonical checkout path | Same application location; reuse retained record | Historical continuity of file contents |
| Equal validated common Git directory | Current repository-family membership | Which of several checkouts moved |
| Distinct validated checkout paths/registrations within that family | Distinct current checkouts | Cross-path application UUID continuity |
| New common directory after a main-clone move | A valid repository at its new location | Relationship to an absent old clone |
| Rename/root-change notification, timing, same name/remote/branch/content | Reason to refresh or corroborating information only | A unique old-ID to new-path mapping |

There is **no admitted automatic cross-path move proof in the current package-backed discovery contract**. The package derives its repository identity from the common-directory path and returns current paths/registration, not a move receipt. Automatic whole-repository relocation MUST NOT be promised from those facts. A future capability that establishes a unique old-to-new checkout mapping requires a separately validated contract; this scope does not add it.

A newly validated different path MUST be admitted normally as an independent location, without a Repair prompt, blocked candidate state, transfer of the old record's notes/pinning/history, or early deletion of an unrelated hidden record. Names, remote URLs, and checkout registration names alone MUST NOT merge identities. Exact canonical-path aliases MUST not produce duplicate active locations. Equality is equality of the validated canonical path supplied by the package, not a new app-side lowercase or fuzzy comparison. A case-only spelling change that canonicalizes to the same path reuses the record; if the package returns different canonical paths, this scope treats them as independent locations. Preserving identity for differing canonical case spellings is not promised.

When the **same canonical checkout path** validates under a different current repository family, the retained checkout ID and its own location metadata MUST be reused under that validated family. Family membership follows current package evidence; this is not cross-path move detection. The old family keeps its own independent identity/retention. Conflicting simultaneous family claims for one canonical checkout defer membership mutation until a current unambiguous validation is available; no duplicate checkout row is created. Live pane facets must resolve against the current family or clear until recomputed.

## C2 — Absence admission and separate checkouts (R2; U1, U2, U6)

**R2.** A current complete authoritative reconciliation of the authorized watched scope MUST mark previously known locations absent from that scope hidden. It MUST include restored application records within that reconciliation’s scope, so changes made while the app was closed are detected. Records outside the examined authorized scope are not negative evidence. Removing a watched parent or explicitly invoking Remove Repository is outside this automatic absence policy; their existing command behavior is not changed here. Scope removal alone MUST NOT start or accelerate a filesystem-absence clock. If scope is no longer available to validate an already-hidden location, collection is deferred rather than inferred from that loss of coverage.

Partial, failed, cancelled, inaccessible, or superseded scans MUST NOT establish absence. Positive validated discoveries from such scans may restore availability, but an unsuccessful scan is not an empty authoritative inventory. A watched parent becoming inaccessible cannot prove all its children deleted. Overlapping watched scopes MUST reconcile shared locations without one source hiding a location still positively observed by another.

A repository family and its individual checkouts are separate. Removing one linked checkout MUST hide that checkout, clear only its invalid pane associations, and preserve the other checkout identities. A family MUST NOT become wholly hidden solely because one checkout is absent while another valid checkout in that family remains discoverable. Availability does not turn an absent main path into a usable launch target. If broken Git registration prevents validating linked checkouts, the scan's failure/negative disposition must be honored; the app must not fabricate successful relocation or repair Git metadata.

No two distinct checkouts may be collapsed merely because the common directory is equal. Independent clones of one remote remain separate families. A moved linked checkout with no proven old-to-new mapping becomes a new checkout in the validated current family; its old location follows retention independently.

## C3 — Retention and return (R3; U2, U5)

**R3.** The first authoritative absence starts a durable 30-day retention interval for the hidden location. Thirty days means 30 × 24 hours. Repeated absence and unrelated persistence saves MUST preserve that original start time. App restart MUST preserve it.

Positive same-path rediscovery clears the absence record and cancels its pending collection. A later, distinct absence starts a new interval. Discovery at an unproven different path neither clears nor resets the old interval.

Previously unavailable records with no historical timestamp MUST receive a new interval at their first authoritative absence under this contract; their age must not be guessed from creation time or file timestamps.

At or after the deadline, collection requires the record to remain hidden and current authoritative reconciliation to confirm absence. If validation is incomplete/unavailable, deletion is deferred; the record remains hidden. On startup or wake after a missed deadline, reconcile before collecting. A successful return before collection commits takes precedence over an obsolete expiry request. A backward wall-clock adjustment MUST NOT make a record older, change its first-absence timestamp, or produce an underflow that admits collection. A detected forward wall-clock adjustment alone MUST NOT count as elapsed retention time; collection waits until 30 days of elapsed duration can be established. After restart, an inconsistent or untrusted clock reading defers collection until a trustworthy retention age can be established. These are deletion-admission guarantees, not a requirement to detect an undetectable clock change while the app was closed.

Individual hidden checkouts follow the same retention/return rule. A wholly hidden family can be collected only when its retained checkout obligations are also eligible; no newly hidden checkout may lose its own retention because the family has an older deadline. Observable active topology excludes hidden locations throughout retention. Collecting a main-checkout location does not collect a family that still owns valid linked checkouts: the family retains its UUID and canonical family/root lookup key without treating the old main path as launchable. A returning main path after its checkout record was collected receives a new checkout ID under that surviving family. “After collection, new identity” applies to the specific record collected, not surviving family records.

## C4 — Pane independence (R4; U4)

**R4.** On accepted unavailability, optional live pane repository/worktree associations that no longer resolve MUST clear, in both live state and durable state. Waiting 30 days to clear live references is not permitted. Cleanup MUST cover affected workspaces, including ones not currently presented.

The pane identity, residency, tab/drawer membership, terminal/session ownership, undo state, and saved review history MUST remain intact. The pane stays present as an unassociated pane. Reconciliation MUST NOT activate another existing terminal or remove a pane as a substitute for clearing its optional context. A pane may acquire a current association later through the existing CWD/topology rules; this does not restore a stale historical reference.

At collection, remaining invalid optional live IDs must be cleared. Immutable launch provenance and historical annotation/undo references may retain inert historical identifiers under their own contracts; they confer no authority to resurrect a collected repository or terminate a pane.

## C5 — Collection and related state (R5; U1, U5)

**R5.** Collection hard-deletes eligible application repository/worktree topology and its absence metadata; it does not leave a permanent deleted-row flag. Its own repository note, pin flag, tags and collected checkout notes are deleted with that record; retention is their recovery window, and this scope adds no separate archive for them. It also removes enrichment, PR facts, obsolete repository/worktree recency, and local activity state belonging solely to the collected identity/location. Separate pane notes, saved review annotations and historical records are not repository metadata and remain protected.

Watched parent configuration, surviving checkout state, shared volume cursors, pane recency, terminal ownership, active undo operations, and user-authored annotations/history MUST be preserved. Pending owned operations must finish or be safely excluded before their state is collected. Data shared with an active location MUST NOT be erased by cleanup of a hidden location.

Core/local cleanup may complete in separate steps, but a failure or crash between steps MUST be recoverable and retryable. It must not expose a partly restored repository, orphan collectible rows permanently, or allow a delayed full snapshot save to resurrect deleted topology. Repeated cleanup has the same observable result as one successful cleanup.

## C6 — Runtime and responsiveness (R6; U1, U4, U7)

**R6.** Hidden or collected locations MUST not remain launchable normal repository/search/activity entries or appear indefinitely “Scanning.” Pane lists remain governed by pane membership, not repository visibility.

Accepted unavailability MUST reconcile checkout watcher and Git/Forge work scopes. Unchanged parent discovery scope remains available to observe returns; user removal of that scope is excluded as specified in C2. Late results captured for unavailable/collected/replaced scope MUST NOT recreate cache or UI state, including after the same UUID is restored into a newer observation lifetime.

Filesystem/Git I/O, reconciliation derivation, SQL, and deadline scheduling remain off MainActor. MainActor applies bounded current outcomes and publishes observable state. Scans and cleanup MUST retain the existing demand/contraction boundaries; no per-repository polling or fleet-wide work on unrelated pane actions. Telemetry exposes bounded counts/outcomes and synchronous MainActor occupancy separately from asynchronous elapsed time, without exporting raw paths or IDs. The pass/fail performance obligations here are placement and work amplification: no scanning/SQL/deadline work on MainActor, no per-repository polling, no full reconciliation caused by an unrelated pane action, and changed/current outcomes rather than raw samples driving UI publication. Occupancy measurements diagnose regressions and must report workload/counts; this Specification makes no numerical latency-improvement claim. Existing mandatory performance gates remain required.

## Coverage and proof

| Need / problem | Outcome | Contract | Required evidence |
|---|---|---|---|
| U1: stale rows and misleading scan label | Only usable locations in normal projections | R2/C2, R6/C6 | V1: filesystem-to-projection integration and visible runtime check, including cold start and overlapping scopes |
| U2: temporary absence loses identity | Same-path return reuses record and cancels retention | R1/C1, R3/C3 | V2: persisted identity/time readback across restart, repeated absence, return and expiry race |
| U3: guessed move or manual repair | New unproven path admitted independently, no Repair flow | R1/C1 | V3: moved main clone, copy, unrelated clone, symlink alias, and missing old path through package-backed discovery |
| U4: pane vanishes or points at stale topology | Pane preserved and optional live references clear | R4/C4 | V4: live/durable multi-workspace pane, terminal, undo and navigation observations |
| U5: abandoned data grows forever | Eligible records collected without collateral deletion | R3/C3, R5/C5 | V5: populated data, 30-day boundary, incomplete scan, clock/restart, crash between databases, retry and stale-save tests |
| U6: shared repository collapses checkouts | One family with distinct available/hidden checkouts | R1/C1, R2/C2 | V6: several linked checkouts, main/linked loss independently, registration failure and staggered absence |
| U7: Git boundary or performance regresses | Package-only semantics and bounded UI work | R1/C1, R6/C6 | V7: source/interface review plus package/runtime proof and marker-scoped performance measurements |

Independent clones with identical remotes/commits MUST be a negative merge case. In-memory-only tests cannot prove durable retention; schema-only tests cannot prove event/scope cleanup; screenshots cannot prove protected SQL rows survive.

## Source anchors

- [Git integration boundary](../../architecture/state/agentstudio_git.md).
- [Pinned package](../../../Package.swift) and [discovery adapter](../../../Sources/AgentStudio/Infrastructure/RepoScannerGitDiscoveryClient.swift).
- Package source at the pin: `Sources/AgentStudioGitLocal/Discovery/LibGit2AgentStudioGitDiscoveryReadClient.swift` constructs `common:<canonicalCommonDirectory.path>` and validates current registration; `Sources/AgentStudioGitContracts/GitDiscoveryReadContracts.swift` defines current-path evidence. Neither supplies an old-to-new move receipt.
- [Existing authoritative-scan reduction](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WatchedFolderInventoryReducer.swift) and [current pane association cleanup](../../../Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceMutationCoordinator.swift).
