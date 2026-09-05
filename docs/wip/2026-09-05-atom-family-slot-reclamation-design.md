# AtomFamily Slot Reclamation — Program Design Note

Finding F1 from the 2026-09-05 atom audit. **Design only. No code proposed for merge.**
Written for an owner decision before any implementation.

Anchors are at `origin/main` (`234f80529`) and were re-read for this note.

## 1. The contract today

`AtomFamily` (`Sources/AgentStudio/Infrastructure/AtomLib/AtomFamily.swift`) never removes an
entry from `slots` (`:31`). Three paths tombstone instead of removing —
`removeValue` (`:149`), `replaceAll` (`:170`), `removeAll` (`:207`) — each calling
`acceptValue(nil)` on a slot that stays installed. A fourth path *creates* slots:
`slot(for:)` (`:221-228`) installs permanently and is reached from `value(for:)` (`:52`)
and `revision(for:)` (`:65`), so **reading an absent key mints a permanent slot**.

This is deliberate, not an oversight. A slot is the identity that carries the wake promise:
an observer that registered on a key before it existed must still wake when the key is
inserted, and one that registered before a removal must wake on the removal and on a later
re-insert. Five tests in `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomFamilyObservationTests.swift`
pin exactly that, and any reclamation design must keep all five green unchanged:

| Test | What it pins |
| --- | --- |
| `missingSlotsRemainRetainedForFamilyLifetime` | a read of an absent key retains its slot |
| `removingMissingObservedKeyIsSemanticNoOp` | removing an absent key neither bumps nor drops |
| `replaceAllTombstonesRemovedSlots` | `replaceAll` tombstones rather than removes |
| `removeAllTombstonesAllSlots` | `removeAll` tombstones rather than removes |
| `removeAllRetainsSlotsThatOnlyObservedMissingKeys` | never-valued observed slots survive `removeAll` |

The design has a correct lower bound and no upper bound.

## 2. What the retention actually costs — resolved this session

The audit listed as **not determinable read-only** whether a tombstoned slot retains only
bytes or also retains the observer closure. It is determinable, and I determined it. A
standalone probe against Swift's `Observation`:

```
alloc never-fired
-- after registering a tracking that never fires; payload should still be alive --
alloc fired
DEINIT fired            <- one-shot that FIRED released its closure immediately
-- releasing the tombstoned slot itself --
DEINIT never-fired      <- one-shot that NEVER fired released only when the slot died
```

**A one-shot `withObservationTracking` that never fires retains its `onChange` closure for
the lifetime of the observed object.** Since the observed object is the slot, and the slot
is never released, the closure is retained for the lifetime of the family — that is, the
process. Consumers use `[weak self]`
(`Core/State/MainActor/Persistence/EntityRecencyStore.swift:142-152`,
`App/Panes/TabBar/TabBarAdapter.swift:179-186`), so whole controllers are not pinned, but
the closure allocation and its captured context are.

This raises the finding's weight and changes the goal. Reclamation is not a byte-trimming
exercise; **releasing the slot object is the only thing that frees an orphaned observation
closure.**

## 3. The binding constraint

`AtomFamily` keeps **no observer index of its own** — it relies entirely on Swift's
`ObservationRegistrar`, which exposes no "does this key have live observers" query. So the
family cannot distinguish:

- a slot with a registered, never-fired observer that is still waiting, from
- a slot nobody will ever look at again.

Every reclamation design below is a different answer to that one question. None of them can
derive the answer; each has to **import** it from somewhere.

## 4. Growth model

Slot count is the union of every key ever written **or ever read**, per family, for the
process lifetime. It tracks cumulative churn, not live size. The audit's telemetry shows
live counts flat across 8 h (198→200 worktrees, 36→38 panes), which is why this is
churn-driven and not an active runaway.

Families by key domain (30 `AtomFamily` declarations outside AtomLib):

| Key domain | Families | Recurrence of a key after removal |
| --- | --- | --- |
| pane `UUID` | ~11, incl. four in `WorkspacePaneGraphAtom.swift:253,257,261,265` | **Never.** Pane ids are UUIDv7, minted per pane; there is no pane undo stack. |
| worktree / repo `UUID` | ~10 across `RepositoryTopologyAtom`, `RepoCacheAtom`, `InboxNotificationAtom` | **Yes, transiently** — this is what `replaceAll` tombstoning protects. |
| tab `UUID` | ~3 | Never within a session. |

So each closed pane permanently costs about eleven slots, each owning an `AtomRevision` and
therefore an `ObservationRegistrar`, plus any never-fired closures registered against them.

**Churn rate is unmeasured.** No `atom.*` message appears in 12 h of production logs. That
absence is itself part of the finding: the growth is unobservable in production by
construction, since the only slot-count accessors are `internal` and read only by tests
(`RepoCacheAtom.swift:87,91,95`; `AtomFamily.swift:34` is never read in `Sources/`).

## 5. Candidate designs

### Design A — Owner-driven explicit release, `release(key:)`

The owning atom tells the family a key is permanently dead. The owners already do half of
this: they evict *cached values* on pane and worktree removal
(`WorkspacePaneGraphAtom.swift:828-831`, `InboxNotificationAtom.swift:445-446`, `:472`,
`BridgePaneAttendanceAtom.swift:48`). `release(key:)` would additionally drop the slot.

- **Imports the answer from:** the owner's domain knowledge that the entity is gone for good.
- **Keeps the promise** because it is only called for keys that cannot return. Sound for the
  ~11 pane-keyed families today, where ids never recur.
- **Cost:** every owner must call it; a missed call leaks exactly as much as today, so the
  failure mode is the status quo rather than a regression. A *wrong* call — releasing a key
  that does come back — silently drops a pending observer.
- **Tradeoff:** correctness stays exact; coverage becomes a maintenance obligation spread
  across owners, and a new owner that forgets is invisible.
- **Falsifier:** register an observer on key K, `release(K)`, re-insert K. The observer must
  not be expected to wake, and a *fresh* read of K must mint a new slot that wakes correctly
  on the next insert. If any live caller genuinely needs a wake across a release, A is wrong.
- **Blocking question for topology families:** whether a worktree UUID survives a
  disappear/reappear cycle. Identity is inverted from `stableKey`
  (`RepositoryTopologyAtom.swift:294-295`, `Worktree.swift:15` derives `stableKey` from
  path), but preservation depends on the topology *producer*, not the atom. **I did not
  resolve this.** Until it is resolved, A applies only to pane- and tab-keyed families.

### Design B — Tombstone TTL keyed to a legitimate-return window

Retain tombstoned slots for a bounded duration covering the window in which a key can
legitimately return, then sweep. Needs an injected `any Clock<Duration>` per the repo's
concurrency rules and a sweep trigger.

- **Imports the answer from:** an assumption that legitimate re-inserts are prompt.
- **Keeps the promise** inside the window, which is where transient topology churn lives —
  precisely the case `replaceAllTombstonesRemovedSlots` and
  `removalCallbackReRegistersAndWakesAgainForReinsertion` exist to protect.
- **Cost:** a clock, a timer or sweep-on-touch, and a policy constant in `AppPolicies`. Adds
  a time dimension to a type that currently has none, which is a real complexity increase in
  the one primitive every atom depends on.
- **Tradeoff:** no owner changes and it covers the topology families that A cannot yet reach;
  but it converts an exact promise into a time-bounded one for *all* families, including the
  pane families where an exact answer was available.
- **Falsifier:** observer on K, remove K, advance the injected clock past the TTL, re-insert
  K — must not wake. Same sequence inside the TTL — must wake. Then the sharper one: **does
  any real re-insert path exist that exceeds the TTL?** If re-inserts are always same-settle,
  the TTL can be short; if any path is user-paced, B is unsafe at any tuned value.

### Design C — LRU cap on value-less slots only

Cap the count of slots that hold no cached value; evict least-recently-read past the cap.

- **Imports the answer from:** nothing. It guesses, bounded by a constant.
- **Keeps the five pinning tests green** trivially, since they each use one or two slots and
  any sane cap exceeds that. This is the design's main attraction and also its trap: the
  tests would pass while the promise is now cap-dependent rather than absolute.
- **Cost:** lowest implementation cost, no owner changes, no clock, bounded by construction.
- **Tradeoff:** the wake promise silently degrades for the oldest waiting observers once the
  cap is hit, and the failure is invisible — a missed wake looks like a UI that did not
  update, with no signal pointing here.
- **Falsifier:** register observers on cap+1 distinct missing keys, insert the oldest, assert
  its observer does not wake. If that assertion is unacceptable to write down, the design is
  unacceptable to ship.

Note the audit's read-watermark variant of C has a specific defect worth recording: a
one-shot observer reads **once** at registration and then not again until it fires, so its
watermark freezes at registration. A sweep keyed to "not read since the previous membership
bump" would reclaim exactly the slots with the longest-waiting observers. That variant
should not be pursued as stated.

## 6. Recommendation

**Instrument first, then Design A for pane- and tab-keyed families. Do not ship B or C yet.**

Reasoning:

1. **The measurement is the missing piece, and it is now cheap.** Every design above is
   tuned against a churn rate nobody has measured. F4 in the same PR bounds the `atoms` read
   path under a windowed admitter, which is what made a slot-count instrument safe to add at
   all. The next step is a `performance`-tagged per-family slot-count gauge — the
   `performance` tag, not `atoms`, because it must be on in production. Section 4's growth
   model is a formula with an unmeasured coefficient until then.

2. **A is the only design that keeps the promise exact.** B and C both trade a currently
   exact guarantee for a bounded one, and they do it across all families including the ~11
   pane-keyed ones where the exact answer is freely available: pane ids never recur. Paying
   a correctness tax where no tax is owed is the wrong trade.

3. **A's failure mode degrades to today's behavior.** A forgotten `release(key:)` leaks
   exactly what leaks now. B and C fail the other way — they can drop a live observer — and
   that failure is silent and hard to attribute.

4. **The topology families are a separate decision and should not be bundled.** They are the
   ones with genuine transient re-insert, and they are gated on the worktree-identity
   question in §5 that I did not resolve. Splitting them out keeps the first slice provable.

Suggested slicing, smallest provable unit first:

1. `performance`-tagged per-family slot-count gauge; run it and read the real churn rate.
2. `release(key:)` on `AtomFamily` plus owner calls for pane- and tab-keyed families only,
   with the §5 falsifier written as a test and the five pinning tests unchanged.
3. Revisit the topology families with the measured rate and a resolved answer on worktree
   identity across a disappear/reappear cycle. If churn there proves negligible, close F1
   rather than adding a TTL.

**Owner decision needed on:** whether `release(key:)` may change `AtomFamily`'s public
promise from "a key can always come back" to "a key can come back unless the owner released
it", since that is a contract change to the primitive every atom depends on.
