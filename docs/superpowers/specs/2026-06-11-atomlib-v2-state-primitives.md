# AtomLib v2: Change-Gated Values, Revision-Memoized Derivation, Entity Maps

Status: design direction (pre-plan)
Repo: agent-studio
Companion: `2026-06-11-git-enrichment-refresh-redesign.md` (process/frequency
fixes; consumes this spec's primitives for its granularity/memoization items)

## Problem

The atom layer is push-on-**write**, not push-on-**change**, at every level:

1. **No equality gating.** `@Observable` fires on assignment regardless of
   value; no setter in the codebase checks content before writing
   (`RepoCacheAtom.swift:21-31`, `SessionRuntimeAtom` `markRunning` et al.).
   Every write site is implicitly a "notify everyone" decision.
2. **Fleet-sized single properties.** Six dictionaries scaled by
   repo/worktree/pane (163 worktrees, e.g.
   `worktreeEnrichmentByWorktreeId`) each live in one observable property —
   one key's write invalidates every reader of the collection
   (`RepoCacheAtom.swift:16`, `WorkspacePaneGraphAtom.paneStates`,
   `SessionRuntimeAtom.statuses`, `PaneFilesystemProjectionAtom` × 3).
3. **No derivation layer in practice.** `Derived`/`DerivedSelector` recompute
   on every access (`Derived.swift:9-11`), and `AtomRegistry` exposes derived
   surfaces as computed vars returning **fresh structs per access**
   (`AtomRegistry.swift:250-302`) — memoization is structurally impossible
   today. Rich read models (`WorkspacePaneDerived.panes`) rebuild the world
   per body evaluation.
4. **Canonical values are public read surfaces.** Views subscribe directly to
   raw collections (`TabBarAdapter.swift:108` tracks the whole enrichment
   dict; `RepoExplorerView.swift:131-153` passes whole dicts into row
   builders), so granularity cannot improve without an API boundary.

Jotai-vocabulary diagnosis: we have atoms with no `Object.is` gate, no
`atomFamily`, and no cached derived graph. Measured consequence documented in
the companion spec: one no-op enrichment tick re-renders 14 pane bodies +
tab bar + sidebar.

## Design Direction

**Three small primitives plus one visibility rule — not a generic reactive
runtime.** Adoption is per-atom in a fixed order starting with the measured
hot path. The primitives encode "push on change" structurally so it stops
being a per-setter convention that erodes.

### Primitive 1 — `AtomValue<Value: Equatable>` (change-gated value)

```swift
@MainActor final class AtomValue<Value: Equatable> {
    private let registrar = ObservationRegistrar()
    private var storage: Value
    private(set) var revision: UInt64   // bumps only on accepted change

    var value: Value { registrar.access(...); return storage }
    func set(_ newValue: Value) {
        guard newValue != storage else { return }   // the Jotai Object.is gate
        registrar.withMutation(...) { storage = newValue; revision &+= 1 }
    }
}
```

`ObservationRegistrar` is public API designed for exactly this
(`access(_:keyPath:)` / `withMutation(of:keyPath:_:)`; SE-0395). Skipping
`withMutation` when equal preserves SwiftUI tracking correctness — verified
feasible (prior art: `ra1028/swiftui-atom-properties` `.changes(of:)`).

**Zero external churn.** Adoption is atom-internal: the atom keeps a
same-name computed forwarding var (`var foo: T { _foo.value }`) over a
private `AtomValue`; `.value`/`.set` are internal spelling. Reads through a
non-observable forwarder register on the inner registrar — this pattern is
already load-bearing in-repo (`RepoCacheAtom` facade forwarding,
`RepoCacheAtom.swift:115-210`, tracked through by `TabBarAdapter.swift:108`).
External call sites compile unchanged; writes were already method-mediated
behind `private(set)`.

### Primitive 2 — `AtomEntityMap<Key: Hashable, Entity>` (the atomFamily analog)

Fleet-sized state becomes a map of **per-entity observable boxes** plus an
observable **membership revision**:

- Reading `entity(for: key)` tracks only that entity's box (each box has its
  own registrar — per-key invalidation falls out of object identity).
- List surfaces read `membershipRevision` + key snapshot: rows re-resolve
  only when entities are added/removed, not when one entity's value changes.
- **Lifecycle is owner-managed, not GC'd**: the write-owner atom's mutation
  methods create/destroy boxes (`hydrate`, `removeWorktree`, …). No weak-map
  machinery, no auto-resurrection: reading a removed key returns nil. This is
  deliberate divergence from Jotai (which leans on JS GC) and is what keeps
  the primitive ~150 lines instead of a framework.
- Entity values are themselves change-gated (`AtomValue` inside the box).

Memory cost: ~0.3-0.5KB per active box → ~50-80KB for the 163-worktree fleet.
Acceptable.

**Tracking contract (the most likely implementation bug, pinned by tests
E2/E7):** `entity(for:)` performs an *untracked* dictionary lookup and tracks
only the returned box's registrar. If the lookup itself were tracked,
membership churn (add/remove worktree C) would invalidate every value reader
of A and B and the primitive would deliver nothing.

**Missing-key reads use per-key optional slots (Codex blocker).** A naive
"nil read tracks nothing" rule silently strands topology-driven rows: a
sidebar row renders before its enrichment exists, reads nil, tracks no box —
when the value later arrives only `membershipRevision` bumps and the row
never wakes. Therefore `entity(for:)` **creates the slot on first read**; the
slot holds `Value?` and its registrar fires on nil→value. "No resurrection"
is reframed: *removal* sets the slot's value to nil (fires readers) and the
slot is pruned only when the key leaves the owning topology (a membership
event list surfaces do track). Slots are bounded by topology size, not
unbounded by arbitrary reads — `entity(for:)` creation is restricted to keys
the owner accepts.

**Equality is compile-forced, with explicit comparator injection for domain
payloads (Codex blocker).** Gating on arbitrary `!=` inherits whatever `==`
means — and `WorktreeEnrichment.==` includes `updatedAt` (never equal) and
excludes `snapshot` (false equal): bare-Equatable gating would either no-op
or freeze sidebar counts. The no-comparator initializer exists only for
types that explicitly conform to `AtomContentEquatable` (usually synthesized
struct/enum equality); all other payloads must pass a construction-time
comparator. Row-1 adoption injects content equivalence (identity + branch +
`isMainWorktree` + `snapshot`, excluding `updatedAt`) — the same equivalence
the companion spec's interim gate encodes, now owned by the primitive call
site. `WorktreeEnrichment` must not conform to `AtomContentEquatable`.

**Compat read surface (churn concentration).** The owning atom/facade keeps
its existing dict-typed property name as a computed var that *materializes by
reading every box through its registrar* — tracking-correct (coarse, same
semantics as today) so all existing keyed reads, iterations, and
`_ = dict`-style tracking registrations (`TabBarAdapter.swift:108`,
`RepoCacheStore.swift:199`) compile unchanged AND keep invalidating. The
granular path is `entity(for:)` + `membershipRevision`; hot surfaces migrate
to it as part of the mandated view restructuring. The compat property name is
the grep marker for unmigrated readers; it is deleted per-surface after that
surface migrates (hard cutover, no permanent dual path).

**Rejected: full `Dictionary` protocol mimicry** (subscript-assignment sugar,
Collection conformance). It converts the `_ = dict` tracking-read sites from
compile errors into silent staleness — writes through subscripts would also
bypass the owner's mutation methods. The compat surface above is read-only.

### Primitive 3 — `DerivedValue<Value: Equatable>` (revision-memoized derivation)

Memoization is **revision-keyed, not observation-tracked**: a derived value
declares its input atoms, caches `(inputRevisionStamp, value)`, recomputes
only when an input revision moved, and bumps its **own** revision only when
the recomputed value differs.

**Two planes, named precisely:** *invalidation* is **conditional push** —
comparator-gated, fired synchronously at write to exactly the touched
slot/value's readers. *Computation* is **lazy pull** — derived work happens
at read, gated by revisions. (Jotai's model: mark-dirty eagerly, compute
lazily.) The rejected alternative was pushing recomputed derived *values* at
write time, which requires a dependency-graph runtime.

**Equality policy — compile-forced, not conventional.** There is no
silent-default path. `AtomValue`/`AtomEntityMap` offer exactly two
initializers:

```swift
init(initial:)                 where Value: AtomContentEquatable
init(initial:, equals: (Value, Value) -> Bool)   // everything else
```

`AtomContentEquatable: Equatable` is an empty marker protocol meaning "`==`
*is* content equivalence." Types with synthesized `==` opt in with a one-line
conformance; a type with a hand-written `==` (e.g. `WorktreeEnrichment`)
either must not conform (forcing the comparator initializer at every
adoption — a compile error otherwise) or conforms only after deliberately
aligning its `==`. The "decide explicitly for custom `==`" rule is thereby
enforced by the type system, not by review. No runtime equality probing, no
reflection deep-compare, and deliberately **no ungated always-fire variant**:
non-`Equatable` payloads gate on an `Equatable` projection.

**Propagation contract (lazy pull — claims stated honestly):** the derived is
**not a push node**: it never fires invalidation to wake bodies. Bodies are
woken by the *atom aggregate revision* registrars — because the revision
check inside `derived.value` performs tracked reads of the input revisions
*within the body's tracking scope* (Observation tracking is dynamic, not
lexical), the body's dependency set becomes the input revisions. The
derived's own revision exists solely for chained consumers, bumped lazily
during a read that recomputes to a different value.

**Recursive pull ordering (implementation contract):** a chained derived must
read its input derived's `.value` *before* comparing that input's
`.revision` — reading `.value` forces the input's refresh; comparing first
would stamp against a stale revision and serve stale data. (Pinned by test
D4.)

**Behavior changes vs today's `Derived` (migration breakage audit):**
subscriptions shift from *discovered* (whatever compute touched, via dynamic
tracking) to *declared* (the stamp's inputs). Four consequences each migrated
derived must clear:
1. **Undeclared input = silently stale UI** — made mostly compile-time-safe
   by construction: (a) compute receives declared inputs **as parameters**
   (parameter packs — one `inputs:` declaration drives both the revision
   stamp and the closure signature, so stamp/parameter drift is
   unrepresentable; fleet inputs pass a read-only map view, covered by that
   map's aggregate revision); (b) the compute closure is **`@Sendable`**, so
   capturing a `@MainActor` non-`Sendable` atom from the enclosing scope is
   a compile error; (c) the residual hole — calling the global `atom(\.x)` /
   `AtomScope` accessors inside compute (reachable `@MainActor` statics
   Swift cannot fence) — is closed by a custom swiftlint rule enforced by
   the existing PostToolUse lint hook. The mutate-each-input test and Z1
   staleness guard remain as the semantic backstop.
2. **Mid-mutation reads now see consistent pre-mutation state** (aggregate
   revision bumps at method end) instead of torn-fresh partial state. Audit
   any mutation method that writes an atom then reads a derived *within the
   same method* expecting to observe the write (e.g.
   `WorkspaceMutationCoordinator` reading `paneAtom.panes` between writes).
3. **Constructor wiring, not scope resolution:** `DerivedValue` instances are
   wired to their owning registry's atoms at construction. Today's `Derived`
   resolves via `AtomScope.store` per read; a cached instance must not mix
   registries (a cache on the production registry must never serve a
   `@TaskLocal` test-override read). Per-registry `lazy var` instances + the
   fresh-registry test pattern (`withTestAtomRegistry`) preserve isolation.
4. **Compute closures must be pure** — they now run less often; side effects
   or fresh-identity expectations change frequency. Audit at migration.
Unmigrated `Derived`/`DerivedSelector` keep today's recompute-per-access
dynamic-tracking semantics exactly; exposure is bounded to the deriveds
actually migrated. `DerivedSelector` param-keyed caching is deferred (needs
entity-map-style lifecycle; round-one selectors stay old-semantics).

Consequence: an input revision bump still invalidates bodies reading
`derived.value`. What the primitive
guarantees is (a) **recompute cutoff** — unmoved revisions serve the cache,
killing today's rebuild-the-world-per-access defect, and (b) **chained
cutoff** — an equal recompute leaves the derived's own revision unchanged, so
downstream deriveds and revision-observers don't re-run. It does **not**
provide body-level invalidation cutoff on equal results; that would require
eager push-at-write (a writer→derived link), which is named as a
measurement-gated upgrade path, not built now.

This deliberately avoids the `withObservationTracking` re-arm design
(one-shot `onChange` fires on **willSet** with torn multi-property state, has
re-arm gap races — the codebase already documents this hazard at
`TabBarAdapter.swift:88-90` — and converges on owning a dependency-graph
runtime). Revisions are one `UInt64` compare per input; no graph scheduler,
no diamond-recompute problem at our scale.

Requires: registry exposes derived surfaces as **stored, long-lived
instances** (ends the computed-var-fresh-struct pattern at
`AtomRegistry.swift:250-302`). Mechanical change: computed var → `lazy var`;
in-file precedent exists (`lazy var attendedPane`), and `atom(\.paneDisplay)`
keyPath addressability is unaffected. Write-owner atoms without `AtomValue`
storage gain a `revision` bumped in mutation methods.

**Transaction rule (Codex major — torn revision tuples), enforced by an
owner-typed write token.** Semantic mutations write multiple primitives (`removeWorktree`
touches two maps; `hydrate` five fields — `RepoCacheAtom.swift:39-47,66-71`).
Observation's `onChange` fires synchronously on willSet, so revision
consumers could observe mid-mutation state if each primitive bumped
independently. Rather than a "bump at the end of every mutation method"
convention, the primitives make it structural: **setters require a mutation
token** obtainable only from the owning atom's transaction scope. The token is
strongly owner-scoped (`TransactionToken<Owner>` or an equivalent yielded
mutator object) so a token from Atom A cannot compile against Atom B's
primitive setters —

```swift
func setWorktreeEnrichment(_ e: WorktreeEnrichment) {
    transaction { tx in                       // bumps aggregate revision
        worktreeEnrichments.set(e, for: e.worktreeId, tx: tx)   // ONCE, at
    }                                         // scope exit, iff any write
}                                             // was accepted
```

Forgetting the aggregate bump is now a compile error (no token, no write),
cross-atom token misuse is a compile error (wrong owner type), multi-write
methods bump exactly once by construction, and an all-equal transaction bumps
nothing. `DerivedValue` inputs and store observers key on aggregate revisions
only; per-box registrars exist solely for SwiftUI body granularity. Torn
tuples are unrepresentable for revision consumers.

### Rule — canonical values are private

Write-owner atoms expose: mutation methods, `revision`, and read surfaces
(values / entity lookups / membership). Raw collections become `private`.
Three reader buckets, each with an explicit surface:

| Reader bucket | Surface | Examples |
|---|---|---|
| SwiftUI bodies | `AtomValue.value`, `entity(for:)`, memoized `DerivedValue` | pane chrome, sidebar rows, tab bar |
| Long-lived observers (store persistence) | observe `revision` (one Int) instead of N raw collections — *simpler* than today's 5-property tracking closures (`RepoCacheStore.swift:197-203`, `WorkspaceStore` tracks 16 properties) | debounced saves; row 1 scope is `RepoCacheStore` only |
| Hot UI adapters | row-scoped read models / per-entity handles, not aggregate revision observation | `TabBarAdapter`, repo explorer rows, cmd+P rows |
| Plain sync readers (validators, coordinators, repositories) | explicit snapshot methods — no observation semantics implied | `ActionStateSnapshot`, `WorkspaceMutationCoordinator`, SQLite repos |

### Hard requirement — granularity needs view restructuring

Per-key boxes deliver nothing while hot views read whole collections
(adversarial finding, verified: `RepoExplorerView.swift:131-153,717-725`
unions all keys per render; `TabBarAdapter.swift:108` tracks the whole dict;
`WorkspacePaneAtom.panes` rebuilds the full dict per access with 89 call
sites). Adoption of `AtomEntityMap` for an atom **must** include pushing
reads down to per-row/per-entity subviews on its hot surfaces (sidebar row,
tab item, cmd+P row, pane chrome). The primitive and the view change are one
unit of work per surface; shipping the primitive alone is a non-goal.

## Enforcement Matrix — every rule made structural, or named as a residual

Prose rules erode; this section is the completeness check. **Meta-rule: any
rule added to this spec must add a row here** — naming its mechanism
(compiler / API shape / lint / boundary check / test) and its honest residual
gap. Lint and boundary-check rows are deliverables of the same PR as the
primitive they protect, landing in `.swiftlint.yml` / the existing
boundary-check lane of `mise run lint`.

| Rule | Mechanism | How | Residual gap → backstop |
|---|---|---|---|
| Equality decided per adoption, never silently | **compiler** | two initializers; bare init requires `AtomContentEquatable` conformance | a wrong conformance claim → V3 test pins each adopted type |
| No per-`set()` comparators; no always-fire variant | **API shape** | those overloads/inits don't exist | none |
| Aggregate revision bumped exactly once per mutation | **compiler** | setters require an owner-typed `TransactionToken<Owner>` or yielded owner mutator; bump at scope exit | none (T1 test pins the iff-accepted semantics and compile-negative proof pins cross-atom token misuse) |
| No external writes; writes only via owner methods | **compiler** | canonical primitives are `private`; token not exported | `@testable` can bypass — tests only, acceptable |
| Slot creation bounded to owner-accepted keys | **compiler** | the map is `private`; public reads go through the atom's method | none |
| Derived inputs declared, not discovered | **compiler** | parameter packs: one `inputs:` drives stamp + closure params; `@Sendable` blocks atom capture; no `AtomReader` passed | global `atom(\.x)`/`AtomScope` statics reachable → **swiftlint rule** (D5) banning them inside `DerivedValue` closures |
| Recursive pull ordering (value-before-revision) | **encapsulation** | the ordering lives once, inside `DerivedValue.value`; user code cannot re-implement it | D4 test pins it |
| No new fleet-sized observable collections in atoms | **boundary check** | script flags stored collection properties on `@Observable` classes under `State/MainActor/Atoms/`, with a **shrink-only allowlist** of legacy atoms (ratchet) | regex coarseness → review |
| Compat dict surfaces are scaffolding, not permanent | **boundary check (ratchet)** | per-surface grep counts (`…ByWorktreeId[` in `Features/`, `App/Panes/`) recorded in an allowlist that may only shrink; CI fails on growth | none |
| Registry deriveds are stored, not fresh-per-access | **review + grep** | `lazy var` pattern; computed-var `Derived` constructors greppable | weakest row — acceptable, regression is loud (perf) not silent |
| Privatization only after staleness guard exists | **process gate** | TDD sequencing step 4: Z1 green before the property goes private | enforced by plan checklist, not tooling |

Honest summary of residuals: two rules cannot be fully compiler-proven
(global-accessor reads inside deriveds; new fleet-dict introduction) — both
get mechanized as lint/boundary checks that run in `mise run lint`, which the
PostToolUse hook executes on every edit. Nothing in this spec is enforced by
documentation alone.

## What We Deliberately Do NOT Build

- **No generic dependency-graph runtime** (no AtomKey identity machinery, no
  topological invalidation, no auto-tracked derived graph). Revision tuples
  + explicit input declaration cover our depth-1/2 derivation needs.
- **No GC-style family lifecycle** — owner-managed create/destroy only.
- **No custom macro (`@AtomModel`) / swift-syntax dependency.** Package.swift
  has no macro target today; `@Observable` cannot coexist with a second
  accessor-generating macro on the same stored property (it rewrites
  stored→computed first), so a macro would mean forking Observation's
  expansion and maintaining it as Apple evolves it — for ~25 one-line
  internal edits of payoff. The forwarding pattern concentrates changes
  without it.
- **No property-wrapper route** — compiler-blocked: the `@Observable` macro's
  stored→computed transform rejects wrappers on stored properties (SE-0395
  review thread; same limitation hit by TCA's `@ObservableState`).
- **No `Dictionary` protocol mimicry on `AtomEntityMap`** (see Primitive 2 —
  silent-staleness hazard for tracking-read call sites).
- **No facade rewrite**: `WorkspacePaneAtom`, `RepoCacheAtom`,
  `WorkspaceTabLayoutAtom` keep their contracts and read through the new
  surfaces internally; their 100+ call sites do not change in this program.
- **No wholesale 16-atom migration as one changeset** — adoption order below;
  unmigrated atoms remain valid `@Observable` classes with the equality-gate
  convention from the companion spec.

## Inventory (migration surface, from the swarm audit)

~16 atoms, ~50 observable properties. Fleet-sized collections and their
priority:

| Atom / property | Readers | Write frequency | Adoption |
|---|---|---|---|
| `RepoEnrichmentCacheAtom` (3 dicts) | 50+ incl. store observation | per git tick | **1st** |
| `WorkspacePaneDerived.panes` + display deriveds (uncached) | every pane/tab body | per invalidation | **2nd** (DerivedValue) |
| `SessionRuntimeAtom.statuses` | production reads via `status(for:)`/`runningCount`; **but** the `SessionRuntime` facade exposes a raw `statuses` dict (`SessionRuntime.swift:52-53`) consumed by tests — migrate that surface to a snapshot method with the adoption | 10+/s per pane (terminal events) | **3rd** |
| `PaneFilesystemProjectionAtom` (3 dicts) | **zero external raw-dict readers** (method-mediated: `consume`/`context(for:)`) | high (FS events) | **3rd** |
| `WorkspacePaneGraphAtom.paneStates` | 30+ via facade | per command | later — facade-mediated, command-frequency writes |
| `WorkspaceRepositoryTopologyAtom.repos` | 20+ | rare after boot | later — integrates the companion spec's normalized index |
| `WorkspaceTabGraphAtom.tabStates` | 15+ | per command | later |

Scalars/small values (`ActiveWorkspaceSelectionAtom`, cursors, sidebar
memory, …) adopt `AtomValue` opportunistically when touched.

## Migration Concentration (measured call-site churn)

The grep-grounded census for the row-1 adoption
(`worktreeEnrichmentByWorktreeId`: 47 refs/14 files;
`pullRequestCountByWorktreeId`: 34 refs/9 files — DTO/persistence refs stay
plain dicts and don't count):

| API option | unchanged | mechanical edit | structural | silent-break risk |
|---|---|---|---|---|
| Full Dictionary mimicry | 18 | 4 | 2 | **3 (tracking reads — disqualifying)** |
| Explicit-only API (no compat surface) | 0 | ~23 | 2 | 0 |
| **Hybrid (adopted): compat computed property + granular `entity(for:)`** | **25** | 2 (store `snapshot()` — already planned) | 0 | 0 |

The 2 "structural" sites under any option (`RepoExplorerView.swift:153-154`
whole-dict parameter passing) are exactly the per-row view restructurings
this spec already mandates — intentional work, not churn. A primitive-only
spike may be bounded to `RepoCacheAtom.swift` + `RepoCacheStore.swift`, but
real row-1 adoption must also touch the hot surfaces it proves
(`RepoExplorerView`, `TabBarAdapter`, cmd+P rows) under their ownership
boundaries. A third file changing is not a model break; a whole-dict hot
reader remaining after that surface is declared migrated is the break.
Per-surface completion gate: `worktreeEnrichmentByWorktreeId[` count in
`Features/` and `App/Panes/` trends to zero while DTO/persistence refs stay
constant.

## Contested Position (preserved, with resolution)

The adversarial lane argued: post-companion-fix measurement may show
granularity is unnecessary (frequency gates + cheap walks may suffice);
extract primitives only on rule-of-three; full migration is 60-100 files of
churn with silent-staleness regression risk. The architectural counter
(user's position, adopted): push-on-change and private canonical values are
*correctness-of-design* properties, not just perf — every unguarded setter
and public collection is a future storm; the primitive makes the gate
structural rather than conventional, and the scoped form above is days, not
weeks. **Resolution:** build the three primitives + adopt on rows 1-2 of the
inventory now (hot path, measured); rows 3+ adopt per the busy-workload
re-profile and as code is touched. The full-fleet end state is declared, but
each adoption beyond row 2 must cite either measurement or co-located work.

## Relationship to the Companion Spec / Plan

- The companion spec's frequency invariants (sweep tiering, input filter,
  projector dedup, budget) are **orthogonal and not blocked** — process
  scheduling, not state shape. Its plan
  (`docs/plans/2026-06-11-agent-studio-idle-git-render-performance.md`)
  Task 1's `hasSameCacheContent` atom gate is the **interim** form of
  Primitive 1 at one call site; `RepoEnrichmentCacheAtom`'s adoption here
  **replaces** that hand-rolled gate (same tests carry over).
- The companion spec's Phase-2 items "per-worktree observation granularity"
  and "Derived memoization" are **superseded by this spec** — they are
  inventory rows 1-2 here.
- The normalized topology path index (plan Task 3) lands inside
  `WorkspaceRepositoryTopologyAtom` regardless; its later `AtomEntityMap`
  adoption reuses that index.

## Validation Strategy — Test Pyramid and TDD Structure

TDD is part of this spec: every requirement below is red-first unless marked
as a regression guard. Layer homes follow the existing suite: primitive unit
tests in `Tests/AgentStudioTests/Core/Atoms/AtomLibV2/`, integration in
`Tests/AgentStudioTests/Integration/`, view-host proofs via the existing
`NSHostingView` pattern (`PaneLeafContainerInactiveDimmingTests.swift:40-54`).
Swift Testing only; primitive unit tests are synchronous `@MainActor` —
`@Observable` willSet fires **synchronously on MainActor** (already
load-bearing in `ObservableStoreTests.swift:57,190-204`), so no sleeps or
yields anywhere. Store tests use `TestPushClock`
(`Helpers/TestPushClock.swift`).

### Pyramid shape and budget

| Layer | ~Count | Budget | Scope |
|---|---|---|---|
| Unit | 20-24 | p95 <25ms, synchronous | AtomValue (5), AtomEntityMap (8), DerivedValue (6), row-1 atom migration (4) |
| Integration | 6-8 | p95 <250ms | store revision-observation w/ real persistor + TestPushClock, facade regression carryover, hosted per-row probe |
| Smoke (real-view integration) | 2 | hosted real `RepoExplorerView` tree; e2e staleness guard | silent-staleness, real-surface wiring |

Explicitly NOT tested: SwiftUI diffing internals, `ObservationRegistrar`
internals, the KB/box memory estimate, production render p95 (manual
Instruments, see honesty note).

### Test helpers (promoted to `Tests/AgentStudioTests/Helpers/`)

- `ObservationFlag`: promote the existing duplicated private class
  (`ObservableStoreTests.swift:8-11`, `DerivedSelectorObservationTests.swift:6-8`).
- `expectInvalidationIsolation(tracking:unrelatedWrite:relatedWrite:)`: one
  `withObservationTracking` registration; assert the unrelated write does NOT
  fire and the related write DOES. **Every negative assertion ships with its
  positive control in the same registration** — an unwired registrar must not
  pass vacuously.
- Spy compute closure for `DerivedValue` recompute counting (injected — no
  production seam).
- `AtomEntityMap.boxCount` (internal, one named seam) + weak-box deallocation
  probe for leak proof.

### Requirement / proof matrix

| ID | Requirement | Layer | Red-first |
|----|------------|-------|-----------|
| V1 | Equal write → no observation fired, revision unchanged | unit | yes (fails on plain `@Observable` baseline) |
| V2 | Unequal write → fired exactly once, revision +1 | unit | yes |
| V3 | Injected comparator gates correctly: `updatedAt`-only delta → no fire; `snapshot`-only delta → fires (pins both directions of the `WorktreeEnrichment.==` trap) | unit | yes |
| T1 | Multi-field mutation (`hydrate`, `removeWorktree`) bumps aggregate revision exactly once; no observer sees a partial tuple | unit | yes |
| E1 | Write key A's value → value-reader of key B NOT invalidated (+ positive control on B) | unit | yes (fails on single-dict baseline) |
| E7 | Read missing key (slot created) → value arrives later → reader IS invalidated (the stranded-row guard) | unit | yes |
| E2 | Membership add/remove C → value-reader of B NOT invalidated (pins untracked `entity(for:)` lookup) | unit | yes — most likely implementation bug |
| E3 | Value write → membership readers NOT invalidated; add/remove → invalidated | unit | yes |
| E4 | Remove → nil, membership revision +1, no resurrection on re-read, boxCount stable | unit | yes |
| E5 | Hydrate/clear cycles: boxCount exact, weak box ref deallocates | unit | yes |
| E6 | Compat dict property: `_ = compatDict` inside tracking still invalidates on single-entity change (guards `TabBarAdapter.swift:108`-class readers until they migrate) | unit | yes |
| D1 | Unmoved input revisions → zero recompute (spy count) | unit | yes (fails on today's `Derived`) |
| D2 | Input moved, different result → recompute once, own revision +1 | unit | yes |
| D3 | Input moved, equal result → recompute once, own revision unchanged (chained cutoff) | unit | yes |
| D4 | Chained derived reading `derived.revision` does not recompute on equal-result upstream | unit | yes |
| D5 | `DerivedValue` safety boundary: constructor inputs drive both revision stamp and compute parameters; compute closures receive no `AtomReader`; lint rejects `atom(\...)` / `AtomScope` inside `DerivedValue` compute closures | unit + lint | yes |
| A1 | Row-1 atom per-worktree isolation (E1/E2 against the real atom, 3 hydrated worktrees) | unit | yes |
| A2 | `RepoCacheAtom` facade observation regression (`WorkspaceRepoCacheTests.swift:150-193` carryover) | unit | guard |
| S1 | Revision observation → exactly one debounced save per accepted-change burst; equal-write burst → zero saves | integration | yes (equal-write case fails today) |
| S2 | Restore does not trigger save (`isRestoringState`, `RepoCacheStore.swift:208` preserved) | integration | guard |
| R1 | Hosted probe rows reading `entity(for: id)`: write X → only X's probe increments | integration | yes |
| R2 | Structural pin: migrated row views take per-entity handles, not whole dicts | unit | accompanies view restructuring |
| Z1 | Per-surface silent-staleness guard: fact in → atom → UI read model reflects it (written BEFORE that surface's raw property goes private; one per surface: sidebar row, tab bar, cmd+P row) | smoke | guard-first |
| Z2 | Real `RepoExplorerView` hosted: one worktree write → row content updates | smoke | guard |

### Render-proof honesty note

CI proves observation-graph isolation (R1) + the structural pin (R2) — not
literal production `body` evaluation counts (SwiftUI exposes no public
counter; the repo forbids `#if DEBUG` production hooks). The body-count claim
is verified manually with Instruments / `Self._printChanges` once per
adoption and recorded in the plan's evidence log as a non-CI gate.

### TDD sequencing

1. **AtomValue**: V1-V2 red against a plain `@Observable` stand-in → implement → green.
2. **AtomEntityMap**: E1-E6 red (E1/E2 demonstrate the single-dict baseline failure) → implement → green.
3. **DerivedValue**: D1-D4 red against current `Derived` → implement → green.
4. **Row-1 adoption**: Z1 guards written FIRST (green against current code) →
   migrate atom internals → A1 red→green, A2/Z1 stay green → S1/S2 (store
   rewrite) → R1/R2 with per-row view restructuring → only then privatize raw
   collections, per surface.
5. **Companion-plan absorption (hard cutover)**: the interim
   `hasSameCacheContent` gate and its tests are deleted-and-absorbed by V1/V2
   in the same changeset — no dual gates.

Repo gates per step: `mise run test`, `mise run lint` — zero errors.

## Security Context

Not security-sensitive: in-memory state plumbing only; no new inputs,
subprocesses, network, or persistence format changes. The relevant risk is
correctness (silent staleness), addressed in validation.

## Resolved Decisions (from review)

- **Propagation contract: lazy pull.** Bodies track input revisions;
  guarantees are recompute-cutoff + chained cutoff, not body-level
  invalidation cutoff. Eager push-at-write is a measurement-gated upgrade
  path only.
- **Missing-key reads: per-key optional slots** created on first read for
  owner-accepted keys; removal = nil-write (fires) + prune on topology exit.
- **Equality: compile-forced content equivalence.** The no-comparator
  initializer is available only for `AtomContentEquatable` payloads, where
  `==` has been explicitly declared to mean content equivalence. Everything
  else must pass one construction-time comparator; per-`set()` comparators
  and ungated always-fire variants are forbidden. Row-1 injects content
  equivalence — bare `Equatable` is insufficient for enrichment.
- **Derived input safety: declared by construction.** `DerivedValue` inputs
  drive both the revision stamp and the compute closure parameters; compute
  receives no `AtomReader`. `@Sendable` blocks ordinary captured MainActor
  atom objects, and the remaining global `atom(\...)` / `AtomScope` escape
  hatch is banned by swiftlint.
- **Transactions: mutation-token-enforced.** Setters require an owner-typed
  token (`TransactionToken<Owner>`) or yielded owner mutator obtainable only
  from the atom's `transaction { }` scope, which bumps the aggregate revision
  exactly once at exit (iff a write was accepted). Forgetting the bump and
  using a token from the wrong atom are compile errors, not forgotten
  conventions. Deriveds and store observers key on aggregates only.
- **Smoke fixture scale**: the Z2 hosted-view smoke runs against a
  118-repo / 163-worktree / 14-pane fixture (the measured production shape),
  not toy counts.
- **Churn strategy: hybrid compat surface** (same-name materializing computed
  property + granular `entity(for:)`), not Dictionary mimicry, not a macro.
- **Map naming**: compat dict property name is the unmigrated-reader grep
  marker; deleted per-surface after migration. `DerivedValue` gets a new name
  so unmigrated `Derived` call sites stay greppable; collapse names after
  migration completes.
- **`boxCount` seam lives on `AtomEntityMap` (internal)** — one named seam
  beats `@testable` storage spelunking.
- **Z1 staleness guards are per surface** (sidebar row, tab bar, cmd+P row),
  each written before that surface's privatization.
- **Interim `hasSameCacheContent` gate is deleted-and-absorbed** by V1/V2
  when row-1 adoption lands (hard cutover, no dual gates).

## Open Questions

1. `AtomEntityMap` box type: generic `AtomValue<Entity>` boxes vs per-domain
   observable classes (e.g. `WorktreeEnrichmentBox`)? Recommend per-domain
   classes for the first two adoptions (clearer, no generic variance pain),
   extract the generic only if a third instance wants it.
2. Should `revision` observation replace **both** store observation closures
   (`RepoCacheStore`, `WorkspaceStore`) in the first adoption, or only
   `RepoCacheStore` (whose atom is migrating anyway)? Recommend
   `RepoCacheStore` only; `WorkspaceStore` follows with pane-graph adoption.
