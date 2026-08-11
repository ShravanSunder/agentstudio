# Bridge Review Comparison Target Loading — Specification

Authority: [User Requirements](./user-requirements.md).

This Specification replaces the comparison-target discovery, loading, and
catalog-presentation obligations in the older
[PR0 Specification](../2026-08-06-worktree-annotations/pr0-specification.md)
and companion
[Program Design](../2026-08-06-worktree-annotations/pr0-program-design.md).
It does not change the selected-target, comparison-basis, durable SQLite,
comparison calculation, or comparison-origin contracts. The focused
[comparison-basis delta](../2026-08-10-pr0-review-comparison-basis/2026-08-10-pr0-review-comparison-basis.md)
remains authoritative for the current-state popup and basis choices.

## Observable product model

```mermaid
flowchart LR
    Review[Review opens] --> Current[Current comparison appears]
    Current --> Open[Reviewer opens picker]
    Open --> Loading[Recent targets preload]
    Open --> Commit[Remembered Commit mode focuses entry]
    Open --> Branch[Remembered Branch mode focuses search]
    Loading --> Ready[Searchable bounded choices]
    Loading --> Failed[Retryable picker error]
    Ready --> Select[Reviewer selects target]
    Select --> Existing[Existing comparison update flow]
    Failed --> Current
```

Current comparison state and available comparison choices are independent:

| Information | Availability | Failure scope |
| --- | --- | --- |
| Active target, compact repository-default symbolic identity, basis, attempt, displayed snapshot, stale/current state | pushed while Review is active | Review comparison lifecycle |
| Branch choices and repository default candidate | requested while the comparison picker is open | that picker query only |

## CT-R1 — Review does not preload the branch catalog

Opening, restoring, refreshing, or changing the viewport of Review View MUST
NOT enumerate or transfer the selectable branch catalog unless a target query
is currently requested.

Agent Studio MAY resolve the repository-designated default remote-tracking
reference as one constant-scope lookup without enumerating selectable branches.
That lookup has exactly two observable purposes:

1. when no durable target intent exists, initialize the comparison from the
   resolvable repository default target; and
2. publish that currently resolvable default's compact symbolic identity so the
   current-state block can truthfully classify whichever active or displayed
   symbolic target it renders as `Default`.

If the repository default cannot be resolved, Agent Studio MUST NOT mark the
active or displayed target as `Default`. The compact default identity is current
presentation truth, not durable target intent, and contains no branch catalog.

```text
Review initialization
  ├─ resolve designated default only; never enumerate choices
  ├─ durable target exists → use it and publish the compact default identity
  └─ no durable target     → initialize from the resolvable default

No branch catalog is loaded on either path.
```

Traces to: CT-U1, CT-U4.

## CT-R2 — The picker requests choices through the on-demand product path

When the comparison picker opens, BridgeWeb MUST issue the typed product call
`review.comparisonTargets.query` regardless of whether the remembered mode is
Branch or Commit. This preloads Branch choices for an immediate mode switch
without moving the catalog into initialization or pushed metadata. A successful
call MUST return an authorized descriptor for one finite
`review.comparisonTargets` content response. BridgeWeb MUST obtain the catalog
by opening that descriptor through the existing content route.

The catalog MUST NOT appear in `pane.presentation`, File metadata, Review
metadata, or any new metadata subscription. Packaged transport uses
`agentstudio://rpc/command` and `agentstudio://rpc/content`; the development
backend uses their existing HTTP equivalents.

```mermaid
sequenceDiagram
    participant UI as Comparison picker
    participant W as Communication worker
    participant N as Native Bridge
    UI->>W: open comparison picker
    W->>N: review.comparisonTargets.query (command)
    N-->>W: content descriptor
    W->>N: content.open (foreground)
    N-->>W: finite catalog frames + terminal
    W-->>UI: validated catalog
```

Traces to: CT-U2, CT-U4, CT-U6.

## CT-R3 — Candidate production is recent and bounded

The returned catalog MUST include resolvable local and remote-tracking branches
whose tip commit time is at or after the cutoff and no later than query capture.
It MUST also include, when resolvable:

1. the repository-designated default remote-tracking target; and
2. the current selected branch target.

Those two retained targets may be older than the cutoff but count toward the
hard result capacity. Symbolic remote `HEAD` aliases MUST NOT appear as choices.

The response MUST have deterministic ordering, a fixed product row limit, and
a fixed product encoded-byte limit independent of the transport's theoretical
maximum stream size. If eligible rows exceed either product limit, the response
MUST set `isTruncated: true`. The default and current retained targets take
precedence over ordinary recent rows during truncation.

The catalog MUST report its capture time, cutoff time, and truncation state so
the UI can explain that it is a recent bounded list. No network fetch occurs.

```text
all local + remote-tracking refs
        │
        ├─ retain current target if resolvable
        ├─ retain default target if resolvable
        ├─ retain remaining tips from previous 30 days
        ├─ deterministic order
        └─ enforce rows + encoded bytes
```

Traces to: CT-U3.

## CT-R4 — The selector renders a bounded DOM window

The Branch selector MUST preserve the existing owned Combobox input, item, and
list primitives and their Agent Studio theme tokens. It MUST use Base UI's
external-virtualization contract so only the visible rows plus a bounded
overscan are mounted.

Each row MUST preserve its unambiguous displayed branch name, local or
remote-tracking kind, current abbreviated target revision, full revision for
assistive technology, and `Default` marker when its symbolic identity matches
the catalog's designated default. Same-short-name local and remote-tracking rows
MUST remain distinguishable.

Filtering MUST operate over the complete returned catalog. Keyboard highlight,
selection, active-descendant semantics, and scrolling to the highlighted item
MUST continue to work across rows that are not currently mounted. Opening the
picker MUST focus the remembered mode's input; switching to Branch or Commit
MUST focus the newly active mode's input.

An empty eligible set MUST be distinguishable from query failure. Every ready or
empty result MUST show the concise adjacent footer `Showing branches from the
last 30 days.` The footer MUST NOT add date ranges, retention exceptions,
capacity details, or exact-commit guidance. The catalog contract still reports
`isTruncated` for diagnostics and proof; the picker MUST NOT present itself as a
complete branch browser.

Traces to: CT-U2, CT-U3.

## CT-R5 — Queries are cancellable and latest-request-wins

Closing the picker, replacing the pane session, losing foreground work
admission, or starting a newer query MUST cancel or supersede the older request.
Switching between Branch and Commit while the picker remains open MUST preserve
the in-modal preload.

A cancelled or late result MUST NOT update picker state. Query failure MUST
leave the current comparison and durable target intent unchanged and MUST offer
a retry when the picker remains open. Selecting a returned target continues
through the existing `review.comparison.update` mutation; querying choices has
no mutation side effect.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: picker opens
    Loading --> Ready: newest query completes
    Loading --> Empty: newest query has no choices
    Loading --> Failed: newest query fails
    Loading --> Idle: close
    Loading --> Loading: newer query supersedes old
    Empty --> Idle: close
    Failed --> Loading: retry
    Ready --> Idle: close
```

Traces to: CT-U5.

## CT-R6 — Existing comparison behavior remains unchanged

Removing the catalog from metadata MUST NOT change:

- durable selected target and basis in `core.sqlite`;
- automatic default-target initialization;
- the `Default` marker on an active or displayed symbolic target whose identity
  matches the compact currently resolvable repository default;
- common-commit, branch-tip, or exact-commit comparison semantics;
- displayed target/attempt/snapshot status;
- comparison invalidation and stale-result behavior;
- File or Review metadata subscription behavior; or
- target selection through `review.comparison.update`.

Traces to: CT-U4, CT-U5, CT-U6.

## Catalog contract

One successful content response contains:

```text
capture time
cutoff time
isTruncated
default target, nullable
current branch target, nullable
ordered branch rows:
  kind: local | remoteTracking
  display/ref identity
  exact tip commit OID
  tip commit time
```

The catalog is request-scoped application data. It is not durable state, a
metadata snapshot, or authority for the comparison selected after the query.
The existing comparison-update operation resolves the selected symbolic target
again before producing a Review result.

## Failure and compatibility

- Invalid, oversized, stale-session, or unauthorized responses fail through the
  existing product transport error/reset contract.
- An unavailable repository/default/current branch may reduce the returned
  choices but must not silently fabricate a target.
- Existing saved pane data requires no migration because catalog data was never
  durable intent.
- The protocol changes as one hard cutover; no legacy catalog-in-metadata path
  remains.

## Proof obligations

| Obligation | Required evidence |
| --- | --- |
| CT-R1, CT-R6 | Native/integration evidence that Review initialization resolves at most the single default target, publishes only its compact symbolic identity, and renders the correct `Default` marker for restored, initial, pending, and displayed symbolic targets without a catalog |
| CT-R2 | Contract and production-backed integration evidence for command descriptor followed by content frames; metadata corpus rejects `targetCatalog` |
| CT-R3 | Real-Git behavior evidence for cutoff, mandatory exceptions, deterministic truncation, row/byte bounds, and no fetch |
| CT-R4 | Browser interaction and manual visual evidence with one query on picker open in either remembered mode, immediate preloaded rows after switching Commit to Branch, preserved row content and accessibility, a production-scale catalog, bounded mounted rows, search, focus, keyboard navigation, selection, and the concise always-visible recency explanation |
| CT-R5 | Automated cancellation/latest-request evidence showing no comparison mutation or late-result application |
| CT-R6 | Durable SQLite restart evidence plus existing comparison behavior regression coverage in the Swift development backend and packaged app |

## Negative space

This change adds no cache, pagination protocol, background prefetch, metadata
subscription, database table, event history, transport route, service, watcher,
network fetch, or generalized Git browser.
