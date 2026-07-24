# Bridge Review Demand Lanes

Status: accepted; sole normative Review demand-lane completion contract for this slice
Goal: make Review content preparation responsive, reusable, and continuous
without replacing the existing scheduling architecture.

Earlier demand-lane drafts and plans are non-authoritative where they conflict
with this contract, including prior per-lane caps, preemption, cancellation,
background limits, and implementation sequencing.

## Product contract

Bridge Review uses five demand roles:

```text
selected > visible > nearby > speculative > background
```

The pane owns twelve active content-preparation opportunities:

```text
3 selected/visible-reserved
9 dynamic, filled in strict role order
```

The required behavior is:

- role changes rerank current work but never abort it;
- background walks the complete Review order lazily;
- exact active work, resident content, and render fulfillment are reused;
- typed transport outcomes remain distinguishable;
- rank reaches real Pierre file and diff tasks; and
- physical response concurrency is a separate measured limit of twelve.

## Non-goals

- A new scheduler framework, worker, cache, transport, or protocol.
- File View demand-policy changes.
- A process-global or cross-pane scheduler.
- Velocity prediction or speculation beyond hover.
- Aborting active work to make a newly selected item start immediately.
- Batching multiple files into one response.
- Persisting traversal or body content across pane lifetime.
- Modifying or forking Pierre.

## Current gap

Current Review production code has only selected, visible, and speculative
membership. Their active work is tracked separately. `maxStartCount` limits one
planner invocation rather than total active work. Nearby and background have no
production owners, completed bodies are not retained for reuse, and known
transport errors/resets are collapsed into generic failures.

The rendered viewport supplies exact visible item IDs, but its numeric indexes
are synthetic. The worker already owns authoritative Review order, so it must
derive real viewport bounds and direction from the visible IDs.

The render job carries demand rank, but the Pierre adapter currently reads rank
from file tasks only. Diff tasks therefore miss the real priority path.

## Data flow

```text
selection / rendered IDs / order / hover
                    │
                    ▼
          one highest-role reducer
                    │
                    ▼
    active / resident / render reuse gates
                    │ miss
                    ▼
     pane-local 3-reserved + 9-dynamic ledger
                    │
                    ▼
 existing fetch → validation → body registry
                    │
                    ▼
       existing render fulfillment → Pierre
```

Trigger membership is decided before capacity. Capacity may delay work; it must
not remove wanted items or change their role.

## Lane triggers

An item is eligible when it belongs to the accepted source and generation,
exists in current Review order, and has current fetchable text descriptors.

For each eligible item, the reducer applies the first matching rule:

| Role | Trigger | When the trigger stops matching |
| --- | --- | --- |
| selected | accepted user, keyboard, programmatic, or initial selection | immediately reclassify through visible, nearby, speculative, then background |
| visible | exact item body/header is currently rendered in CodeView | immediately reclassify through nearby, speculative, then background |
| nearby | item is inside the ordered viewport margin | immediately reclassify through speculative, then background |
| speculative | current hovered item | immediately reclassify as background when its opportunity remains pending |
| background | no higher trigger matches and background state is pending or retry-ready | leave only when promoted, resident, terminal, retry-waiting, or invalidated |

Tree visibility never creates body demand.

Every current-generation eligible opportunity begins with background state
`pending`. Starting work does not remove that membership. Therefore an active
selected, visible, nearby, or speculative record that loses its UI trigger
always has a valid demotion path, normally to background, until it settles.

Retryable failure changes background state from `pending` to `retry-waiting`.
The backoff wake changes it to `retry-ready`, which triggers background again if
no higher role matches. Validated residency or a terminal outcome completes the
background opportunity for that generation. Eviction does not make it pending
again.

### Nearby margin

The worker maps exact rendered IDs through authoritative Review order and
compares the new range with the previous range:

- moving forward: two viewport lengths ahead and one behind;
- moving backward: two behind and one ahead;
- direction not known yet: one viewport before and one after.

No new viewport protocol is required.

## One membership and one active record

Every eligible item has at most one role. If facts overlap, the strict role
order wins.

Every current render opportunity has at most one active record. Its identity is
the existing Review preparation identity generalized to every role: current
source, generation, item, render semantics, and required descriptor identities.
Demand role and rank are not part of that immutable identity.

A modified diff remains one logical opportunity even when it needs base and
head bodies. Both descriptors must belong to the same preparation identity;
old and replacement sides may never be combined.

Each validated side may enter body residency independently. Render publication
still requires every required side to match the same captured preparation
identity. A retry opens only missing or retryable sides; any constituent
identity invalidation retires the composite opportunity before publication.

When a role changes:

1. update the active record's role and rank;
2. retain its current logical position;
3. retain its fetch and lifecycle signal; and
4. use the current role when later enqueueing render work.

Role change alone never aborts, duplicates, or settles the record.

Generation replacement, source or pane teardown, descriptor invalidation, and
integrity failure remain valid retirement causes.

### In-flight cancellation boundary

An active current-identity logical record is never retired, and a content
response whose `fetch` has started is never cancelled, because of:

- a new selection;
- viewport entry or exit;
- scroll-direction or nearby-margin change;
- hover entry or exit;
- promotion or demotion between any demand roles;
- the pane becoming hidden; or
- Review becoming temporarily inactive.

Those facts only update membership, rank, and publication authority. The same
active record and logical position continue. A started response retains its
request and response-lifecycle signal.

A logical record waiting at the TypeScript physical-response admission gate
has not started `fetch` and is not yet an in-flight native response. On
foreground exit, withdraw or pause only that physical waiter while retaining
the logical record, logical position, and current identity. On foreground
resume it reacquires physical admission without creating a second logical
opportunity. It must not open native content while hidden.

Cancellation is permitted only when continuing could no longer produce valid
content: source/generation replacement, descriptor/freshness invalidation,
explicit source or pane teardown, or transport/integrity failure. These are
identity or lifecycle invalidations, not demand scheduling decisions.

## Browser-side reuse

Demand passes through three existing browser-side reuse gates:

```text
same preparation identity active
  → promote/demote that record; no new start

all required exact bodies resident
  → reuse BridgeBodyRegistry bytes; no native content open or retransmission

exact render fulfillment already preparing or painted
  → front end reuses it; no duplicate publication, payload, or Pierre task

otherwise
  → admit one opportunity and fetch only missing bodies
```

Use the existing `BridgeBodyRegistry` as the pane-local reusable body owner. Do
not add another cache. Residency requires exact descriptor freshness and all
existing generation, digest, byte-bound, binary, and UTF-8 validation.

The body slot key is package, source, generation, item, content role, and byte
window. Its freshness key is the content digest plus declared/whole length and
UTF-8 contract. Descriptor, handle, and endpoint IDs authorize a fetch but do
not define resident bytes, so a metadata-only reissue with the same body and
freshness keys reuses the body. Any key mismatch is a miss. Retention uses the
accepted 4 MB per-body and 128 MB pane-local total policy.

Demand role and rank are excluded from preparation, body, and render identities.
A role-only promotion or demotion therefore cannot invalidate valid bytes or
cause retransmission. A metadata refresh with the same exact content identity
must reuse the resident body. Only a real freshness change, eviction, or
correctness/lifecycle invalidation may reopen that body.

Front-end reuse is keyed by the existing exact render identity—item, render
kind, content cache key/hash, window, and worker derivation epoch—not by file
path alone. An exact preparing or painted hit sends nothing again; a changed
render identity publishes exactly once.

Cache admission and UI publication are separate. A still-valid body may become
resident after its role changes, even when it is no longer eligible to publish
immediately.

Eviction may cause a later foreground refetch. It never rewinds background
progress.

## Twelve-position ledger

The existing Review scheduling owner replaces its separate role-owned active
collections with one pane-local ledger.

Allocation rules:

- three positions accept selected or visible misses only;
- nine dynamic positions accept all roles in strict priority order;
- selected and visible may also use dynamic positions;
- nearby, speculative, and background never borrow reserved positions;
- there are no separate nearby, speculative, or background caps; and
- active count never exceeds twelve across repeated reconciliations.

Refill rules:

1. Reconcile the complete membership set.
2. Update matching active records in place.
3. Remove active and resident hits from the miss set.
4. Fill free reserved positions with selected, then visible.
5. Fill free dynamic positions in full role order.
6. Within a role, preserve Review order and stable prior queue order.
7. Pull only enough background candidates to fill current vacancies.

A logical position begins when a missed opportunity starts. It ends exactly
once after validated residency, terminal failure/unavailability, retry-wait,
invalidation, or teardown. Pierre queueing and body retention do not continue
holding the position.

Reserved positions guarantee refill priority, not preemption. If all twelve
positions are occupied, a new selected item remains wanted and waits for a
natural release.

## Background traversal

Background walks the complete current-generation Review order. It has no
40-file prefix, percentage-of-cache stopping rule, or separate concurrency cap.

The traversal owner keeps only:

- current generation;
- a cursor used to find the next candidate;
- per-opportunity outcome; and
- retry eligibility using the existing bounded backoff.

The cursor is an optimization, not completion authority. Same-generation
additions become candidates, removals cannot pin progress, and reorder changes
future walking without clearing outcomes.

A retryable error or reset records that the item received an opportunity, then
enters retry-wait. When backoff becomes ready it triggers background again.
The cursor continues to later items instead of getting stuck on that failure.

Background runs only while Review is foreground and dynamic positions remain
after higher roles. Continuous higher-priority work may delay it; lower work
never bypasses a runnable higher role.

## Hidden and inactive Review

On foreground exit, admit no new logical Review opportunity of any role. A
Review content response that already reached native while foreground may
continue into residency under its existing producer lease; native must not
treat the foreground transition alone as retirement for that already-started
Review response. Close, revocation, source or descriptor invalidation, and
transport or integrity failure still retire it.

A logical opportunity still waiting at TypeScript physical admission has not
reached native. Preserve its logical record and position, but pause or withdraw
that waiter so it cannot call `fetch` while hidden. On resume it competes at
physical admission from the same logical record. Do not start hidden render
work. File View admission behavior does not change.

A resident completion that has not been rendered retains exactly one deferred
render continuation. On resume, rederive current facts and publish that exact
resident identity once without reacquiring a logical position or reopening
native content. Waiting misses compete normally from current membership; no
hidden snapshot is replayed.

## Typed outcomes

The Review fetch boundary preserves the transport's existing distinctions:

| Outcome | Result |
| --- | --- |
| validated descriptor complete | insert that exact body; release the position only after every required body is resident |
| non-retryable error | preserve error code and bounded safe message; terminal outcome; release position |
| retryable error | preserve error code and retryable flag; enter retry-wait; release position |
| reset | preserve reset reason; enter retry-wait; release position |
| stale generation/source | discard; release position |
| teardown abort | discard; release position |
| descriptor, digest, byte, binary, or UTF-8 failure | no residency or publication; release position and report bounded health evidence |
| unexpected local failure | preserve a bounded internal-failure result; terminal outcome; release position |

This is a closed Review-domain result over the existing transport terminals.
The original complete/error/reset discriminant and its typed correlation,
code, retryability, or reason survive beside the scheduling disposition. Known
terminals and local validation failures never fall through a generic error.
This does not require a new wire type or error service.

## Pierre rank

Use one numeric rank:

| Role | Rank |
| --- | ---: |
| selected | 0 |
| visible | 1 |
| nearby | 2 |
| speculative | 3 |
| background | 4 |

Read the active record's current rank when materializing the render job. Equal
ranks keep stable Pierre request order. Running Pierre work is not preempted.
If an exact task is still queued when its role is promoted, update that queued
task's rank in place; do not refetch or enqueue a second task.

Project the rank onto both real task shapes:

- CodeView file → Pierre `request.file`;
- CodeView `fileDiff` → Pierre `request.diff`.

Do not modify Pierre.

## Physical response boundary

The pane product transport permits twelve open content responses.

This is an Agent Studio policy, not a WebKit rule. Apple/WebKit exposes no
six-task `WKURLSchemeHandler` limit and no application-facing consumption
backpressure signal. A finite bound remains necessary for native, IPC, and
memory pressure.

Twelve is below Agent Studio's native hard limit of sixteen content-producer
lifecycle residues, leaving four positions for cancellation/terminal residue.
A two-sided diff may still have a secondary body waiting at this boundary; that
is accepted for this slice.

`WKURLSchemeHandler` start/stop callbacks run on MainActor. They must perform
only bounded request validation, admission, lifecycle registration, and
delegation. Git reads, body assembly, hashing, decoding, demand scheduling, and
other substantive work must not run inline on MainActor.

The existing per-frame observation protocol remains the backpressure mechanism:
native retains at most the already-defined unobserved frame window per response
and advances only after worker acknowledgement.

The value twelve must pass the packaged WKWebView workload. Acceptance requires:

- an observed per-pane peak of twelve open responses while a thirteenth waits;
- no native capacity rejection or lifecycle residue above sixteen;
- existing frame and queued-byte limits are respected;
- final response, waiter, acknowledgement, and lifecycle residue are zero;
- correct cancellation and terminal settlement;
- no metadata/control wedge or material interaction regression; and
- separately reported selected/visible logical wait and physical wait.

Chromium tests cannot prove this native boundary.

## Ownership

```text
Review controller
  owns selection, rendered IDs, hover, foreground state
        │
        ▼
pure Review reducer
  owns one role per eligible item
        │
        ▼
existing Review scheduling owner
  owns one ledger, 12/3/9 admission, traversal, retry readiness
        │
        ├── existing body registry
        └── existing Review fetch/preparation path
                    │
                    ▼
existing render fulfillment and Pierre adapter

shared product transport
  owns twelve physical responses, framing, capability, cancellation
  does not own Review membership
```

## Proof requirements

| Contract | Required proof |
| --- | --- |
| five-role membership | exhaustive reducer tests for entry, exit, overlap, promotion, and demotion |
| real nearby geometry | authoritative-order tests and real browser forward/backward scrolling |
| 12/3/9 ledger | deterministic repeated-reconciliation and exact-release tests |
| no role-change abort | held-fetch promotion/demotion integration |
| browser-side reuse | one native response identity for an active preparation, including continued first-delivery bytes after promotion; zero second-response bytes; zero native opens for a fresh resident hit; zero duplicate publications/Pierre tasks for an exact in-progress or painted fulfillment; exactly one legitimate reopen after freshness change or eviction |
| background | full-order traversal with add/remove/reorder/retry/eviction |
| hidden behavior | held native response survives foreground exit; a pre-fetch physical waiter produces zero hidden native opens and resumes from the same logical record; resident completion defers render; resume performs zero refetches for resident content and one publication |
| typed outcomes | complete terminal table without generic error collapse |
| Pierre rank | real file and diff task ordering plus queued same-key promotion without duplication |
| physical twelve | packaged WKWebView one-pane and multi-pane peak-twelve/thirteenth-waiting response, final-zero residue, queue-bound, cancellation, and interaction evidence |
| MainActor boundary | source/trace proof that substantive Git/content work executes off MainActor |
| security | stale and forged cache-key rejection; mixed-diff, digest, byte, binary, and UTF-8 rejection |

Proof must assert user-visible or transport-observable behavior, not merely
private map contents or a restatement of reducer output. Focused deterministic
tests cover role transitions, exact open/publication counts, bytes, capacity,
and settlement. Browser integration must exercise the real Review worker and
real descriptor/body route with a large Review fixture containing at least 100
changed files. Packaged debug-app proof must then use this branch's real
worktree Review data and cover selection, sustained scrolling, promotion,
background continuation, and File/Review switching without duplicate body
opens, duplicate publications, a wedge, or a crash.

## Guardrails

- Extend the existing Review scheduling owner; do not add a generic scheduler.
- Reuse the existing reducer, preparation identity, pump, body registry,
  transport, render fulfillment, and Pierre adapter.
- Derive nearby geometry from existing visible IDs and worker order.
- Preserve existing terminal types; do not add a protocol version.
- Keep traversal pane-local and in memory.
- Do not add adaptive concurrency, persistence, batching, a global coordinator,
  or a new proof app.
- Remove old per-role active caps and cancellation behavior instead of retaining
  compatibility branches.
- If native proof rejects twelve, reconverge on the physical boundary; do not
  compensate by truncating membership or aborting role-demoted work.
