# Bridge Review Comparison Target Loading — Program Design

Requirements: [User Requirements](./user-requirements.md)

Specification: [Specification](./specification.md)

## The correction is two complete flows

The existing Bridge transport already separates control, pushed metadata,
requested content, and scheduling. The correction uses those owners as designed:

```text
CURRENT COMPARISON                         SELECTABLE TARGETS

Review initializes                        Comparison picker opens
        │                                         │
        ▼                                         ▼
resolve one default ref                    typed query command
load durable target                               │
publish default identity                          ▼
        │                                  bounded Git capture
        ▼                                         │
compact metadata                                 ▼
active target                             single-use descriptor
basis / attempt / snapshot                        │
repository default identity                      ▼
stale or current                           on-demand content
                                                   │
                                                   ▼
                                          virtualized selector
```

The catalog leaves pane presentation. No cache, database state, service,
watcher, metadata subscription, or fourth physical route is added.

## Current system evidence and constraints

The current branch is compatibility-bound by these shipped paths:

- `BridgePaneController.adoptInitialContributionTargetIfEligible` calls
  `reviewComparisonTargets()`, publishes the complete catalog, and uses the same
  catalog to find the initial `origin/HEAD` target.
- `BridgePaneRefreshAdmissionCoordinator` stores that catalog inside
  `BridgePaneReviewComparisonPresentation`, so it crosses the metadata stream.
- `BridgeDevelopmentProductHost` separately loads the same complete catalog
  during construction and seeds its refresh coordinator with it, so removing
  only the packaged-controller path would leave the development path wrong.
- `BridgeReviewComparisonControl` derives the current `Default` marker from the
  catalog, coupling compact current truth to picker data.
- `LibGit2ReviewComparisonTargetReader` opens one repository, enumerates all
  local and remote-tracking branches, peels every branch, and only then resolves
  `refs/remotes/origin/HEAD`. Its public rows have no commit time and the API has
  no bound.
- Product calls already return typed values through the command route, while
  File and Review bodies already use descriptor-authorized `content.open`.
- Native control dispatch intentionally finishes and replay-caches an exact
  response after provider dispatch begins, even if the originating URL task
  closes. Query cancellation therefore cannot truthfully promise to preempt
  every already-started Git capture.
- `BridgePaneProductContentDemandAuthority` currently derives File/Review body
  priority from metadata subscriptions; request-scoped query content has no
  subscription from which to derive that priority.

Current package authority is `agentstudio-git` revision
`8525ebd88abdd85a0879a3bc20f9949aa606bc14`. Its current target-catalog contract
must change before Agent Studio can implement the bounded capture.

## Structural crux and selected direction

The crux is where a finite, explicitly requested catalog lives between capture
and presentation.

| Direction | Gain | Cost or failure | Decision |
| --- | --- | --- | --- |
| Keep catalog in metadata | no new application call | Review startup and every presentation copy scale with repository history | rejected |
| Return rows directly in the command result | removes metadata abuse | turns the control/replay response into bulk-data transport and bypasses content scheduling | rejected |
| Command returns one content descriptor | reuses command authority, finite content framing, cancellation, bounds, and demand admission | one request-scoped pending body per pane | selected |

The selected cost is paid by the pane-scoped query owner: it may retain one
bounded immutable response between command completion and `content.open`. That
is a descriptor backing, not a reusable cache. A TTL, eviction service,
cross-pane sharing, or catalog persistence would add machinery without serving
an accepted requirement.

## Owners and dependency direction

```text
BridgePaneController / BridgeDevelopmentProductHost
  owns: host-specific Review attempts and default-target lookup initiation
  consumes: the same default resolver through the shared Git data client

BridgePaneRefreshAdmissionCoordinator
  owns: compact current presentation for both production-backed hosts
  consumes: compact default-identity updates from either host

BridgePaneProductSchemeProvider
  owns: pane/session command and content authorization
  contains: one provider-isolated ComparisonTargetQuerySource state owner
            pending → claimed → released descriptor backing
  consumes: live read-only repository/current-target projection

AgentStudioGitBridgeReviewDataClient
  owns: Bridge-to-agentstudio-git mapping and Git scheduler admission
  consumes: agentstudio-git default resolution and bounded capture

Comm worker comparison-query controller
  owns: native call/content sequence, decoding, AbortController, request and
        work-admission identity

React comparison picker
  owns: remembered Branch/Commit mode, focus, search, and visible query state
  consumes: compact current metadata plus request-scoped query results
```

Allowed dependencies follow this order. The query source may read the native
pane repository and current target through one consumer-owned read-only
projection at query admission; the web request does not supply either value.
The provider must not capture an initial target during composition because it
outlives later comparison-target mutations. Pane metadata must not depend on
query state, and target selection continues through `review.comparison.update`
rather than trusting a captured catalog OID.

## Compact current-comparison flow

### Native current truth

Review initialization and comparison refresh perform a constant-scope default
lookup whether the pane has restored target intent or needs automatic
initialization:

```text
Review initialization
        │
        ├─ read target intent from core.sqlite
        │
        ├─ resolve refs/remotes/origin/HEAD and peel only its target
        │
        ├─ no intent + resolvable default
        │      └─ existing pane-intent mutation initializes the target
        │
        └─ publish the resolved remote-tracking symbolic identity
               └─ React compares it with the active or displayed target
                      ├─ same symbolic identity → show Default
                      └─ different or absent    → no marker
```

Before the asynchronous lookup, the host captures repository authority together
with the current Review generation, product admission, and foreground-work
admission. Starting a new lookup clears the prior compact default identity. A
completion may publish only if the repository and all three admissions still
match. This follows the existing `isReviewPackageLoadCurrent` pattern rather
than adding another generation. A stale completion writes nothing. A resolver
failure that is still current leaves the identity absent; it must not preserve a
formerly resolved default after the designation changes or becomes unavailable.

The comparison presentation replaces `targetCatalog` with
`repositoryDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?`.
That transport value contains only `remoteName` and `branchName`; it carries no
catalog rows, target OID, comparison basis, or durable intent.
`BridgePaneRefreshAdmissionCoordinator` remains the owner of the compact
presentation containing:

```text
activeTarget
repositoryDefaultTarget
attempt
displayedSnapshot
native activity / refresh facts
```

The identity is derived current truth and is never persisted. The UI compares
symbolic names rather than target OIDs or basis values, so `origin/main` remains
the same default identity as its commit moves while local `main` remains a
different identity. The same compact fact can classify the active target or the
displayed snapshot target without carrying a targetless boolean across a target
change. If the default ref is missing, malformed, dangling, or points outside
the supported remote-tracking namespace, the identity is absent and automatic
initialization does not fabricate a target.

### Both production-backed hosts use the compact flow

The packaged controller replaces its eager `reviewComparisonTargets()` call in
`adoptInitialContributionTargetIfEligible` with the constant resolver above. It
clears the previous compact identity at lookup admission, revalidates through
`isReviewPackageLoadCurrent`, publishes the resolved symbolic identity, and uses
that same resolved target for automatic initialization only when durable intent
is still absent.

`BridgeDevelopmentProductHost` removes construction-time
`loadReviewComparisonTargetCatalog`. Construction resolves only the designated
default, seeds the shared refresh coordinator with its compact identity, and
retains the supplied pane target intent. Each later comparison attempt clears
and refreshes that identity through the same Git data client while holding the
existing product and foreground admissions. `applyCommittedReviewComparisonUpdate`
and `runReviewComparisonPublication` remain the host's attempt and publication
owners; no packaged-only controller or new shared coordinator is introduced.

### Upstream default resolver

`agentstudio-git` adds a constant-scope operation equivalent to:

```text
resolveReviewDefaultTarget(repositoryPath)
  → GitReviewComparisonBranchTarget?
```

It opens the repository, looks up only `refs/remotes/origin/HEAD`, validates the
symbolic target, opens that one remote-tracking ref, and peels one commit. It
does not create a branch iterator or call a fetch/write API. The host may use
the resolved branch target for automatic initialization, but pane presentation
projects only its remote and branch names into the compact default identity.

## Request-scoped catalog flow

```text
React picker          Comm worker          Native provider       Git scheduler / libgit2
     │                     │                       │                         │
     │ picker opens        │                       │                         │
     ├────────────────────►│                       │                         │
     │                     │ query command         │                         │
     │                     ├──────────────────────►│ acquire foreground      │
     │                     │                       ├────────────────────────►│
     │                     │                       │ bounded capture          │
     │                     │                       │◄────────────────────────┤
     │                     │                       │ encode + retain pending  │
     │                     │◄──────────────────────┤ descriptor               │
     │                     │ content.open          │                         │
     │                     ├──────────────────────►│ claim once               │
     │                     │◄──────────────────────┤ accepted/data/end        │
     │                     │ validate + decode     │ release                  │
     │ ready result        │                       │                         │
     │◄────────────────────┤                       │                         │
```

### Product call

Add `review.comparisonTargets.query` to the exhaustive Swift and TypeScript
call registries. Its request contains no repository path, ref, cutoff, or
capacity override. Pane composition supplies repository authority, current
symbolic target, and product policy through one live read-only projection. The
projection atomically returns the current repository authority and current
symbolic branch/ref identity at query admission. `localDefaultBranch`,
`originDefaultBranch`, `branch`, and branch-backed `ref` targets map to
`currentBranchReference`; an exact commit maps to `nil` because it is not a
branch-catalog row.

Both hosts inject the same projection contract. In the packaged host it reads
the controller's current `bridgePaneState`; in the development host it reads
the host's current `paneState`, including mutations applied after provider
construction. The projection creates no new state owner and cannot mutate pane
intent.

The successful result is a `review.comparisonTargets` descriptor using the
existing descriptor guarantees:

```text
content kind
descriptor identity
declared byte length and maximum bytes
UTF-8 encoding
expected SHA-256
capture identity
```

The descriptor authorizes one immutable body and can be claimed once. Catalog
rows never appear in the command response.

### Content kind and native demand mapping

Add `review.comparisonTargets` to the exhaustive content registries and strict
JSON contracts. It uses the existing `content.open` request and
accepted/data/end, reset, and error frames.

Because query content is created by an explicit user action rather than a
metadata subscription, demand is mapped directly:

```text
review.comparisonTargets
  → BridgeContentDemandInterest.selected
  → BridgePaneRefreshWorkAdmissionSource.acquire()
  → ordinary foreground content admission
```

It must not fall through `.unspecified` and must not use
`acquireReviewContentContinuation()`, which is for publication-backed Review
body continuation while a pane is loaded but hidden.

The query's Git capture uses the existing `.selectedVisibleContent` Git
operation class while the pane holds foreground work admission. No new Git
scheduler class or queue is introduced.

The worker snapshots `workAdmissionGeneration` when it starts the query and
binds the query abort controller to the current pane `workSignal`. A completion
is applicable only while that signal remains live and the generation still
matches. Native dispatch independently acquires the existing foreground work
admission before Git capture and revalidates that same token immediately before
installing descriptor backing. If foreground admission was lost during the
read, no pending body is installed and the result is query-local cancellation;
the generic command may still finish for replay, but it cannot authorize stale
catalog bytes.

## Bounded agentstudio-git capture

The upstream library replaces its unbounded catalog call with two focused
contracts: the default resolver above and one correlated bounded capture.

```text
GitReviewComparisonTargetCaptureRequest
  repositoryPath
  capturedAt
  cutoff
  maximumRows
  currentBranchReference?   native-derived, never browser-supplied

GitReviewComparisonTargetCapture
  capturedAt
  cutoff
  isTruncated
  defaultReferenceName?       canonical row identity
  currentReferenceName?       canonical row identity
  rows[]
    canonicalReferenceName    unique row identity
    target: local | remoteTracking + exact tip OID
    tipCommittedAt
```

One libgit2 repository scope performs the capture:

```text
resolve default and current refs
        │
        ▼
iterate local + remote-tracking branches once
        │
        ├─ exclude symbolic remote HEAD aliases
        ├─ peel each usable candidate to a commit
        ├─ read tip commit time
        ├─ retain default/current even before cutoff
        └─ retain ordinary candidates where cutoff ≤ tip time ≤ capturedAt
        │
        ▼
deterministic order
  default row first
  distinct current row second
  remaining rows by tip time descending
  then canonical ref name ascending
        │
        ▼
stop at maximumRows and report truncation
```

Canonical ref name is the unique identity of a catalog row. Default resolution,
current-target resolution, and branch iteration may encounter the same ref, but
they collapse to one row before ordering or capacity accounting. The nullable
default/current fields identify roles within that unique row set; they do not
introduce duplicate rows. The row cap counts distinct canonical identities.

The operation is read-only: no fetch, reference write, worktree mutation, or
Git lock is introduced. A branch may move after capture; selection sends its
symbolic identity through the existing correlated comparison-update path,
which resolves current Git truth again.

`agentstudio-git` owns row production and real-Git contract tests. Agent Studio
owns scheduling, Bridge mapping, wire encoding, picker behavior, and integration
proof. The upstream API must be published and the Agent Studio package revision
advanced before the hard cutover can compile; there is no local shadow API.

## Product capacity policy

Concrete initial limits live in `AppPolicies.Bridge`:

```text
reviewComparisonTargetRecencyWindow       30 days
reviewComparisonTargetMaximumRows         2,000
reviewComparisonTargetMaximumEncodedBytes 1 MiB
```

The first two values are passed to the correlated Git capture. Bridge owns the
encoded-byte limit because it owns the exact JSON wire representation. It
encodes the default row first, the distinct current row second, then ordered
ordinary rows until the next unique row would exceed 1 MiB. Final `isTruncated`
is true when either the upstream row cap or Bridge byte cap omitted an eligible
distinct row.

The 1 MiB body limit is a product policy below the generic transport ceiling;
the theoretical `UInt32` stream maximum is not a capacity decision. These
values are calibrated through the specified real-repository and browser proof,
not exposed as compatibility promises.

The selector uses `@tanstack/react-virtual` with a local fixed overscan of eight
rows. The virtualization remains comparison-selector-local until another owned
Combobox needs identical semantics.

## Descriptor backing lifecycle

`ComparisonTargetQuerySource` is pane-session state isolated by the existing
`BridgePaneProductSchemeProvider` actor. It owns only immutable encoded response
bodies awaiting or undergoing one open:

```text
Captured
   │ command returns descriptor
   ▼
Pending ── content.open ──► Claimed ── end/reset/error ──► Released
   │                           │
   ├─ newer query              ├─ content cancellation
   └─ session teardown         └─ session teardown
          │                           │
          └───────────────► Released ◄┘
```

Rules:

1. At most one body is pending per pane session.
2. Installing a newer query result atomically replaces and releases the pending
   body.
3. `content.open` must match the complete descriptor and current pane session,
   then atomically claims it. A descriptor cannot be opened twice.
4. Claimed bytes are released after terminal delivery, reset, error,
   cancellation, producer retirement, or pane-session teardown.
5. A descriptor that is issued but never opened may remain only as the single
   bounded pending body until supersession or session teardown.

There is no timer, TTL task, cache index, release RPC, or background cleanup
service.

## Worker and picker state

The main-thread/worker protocol adds one Review query command, one correlated
result, and one cancellation intent. These are application messages over the
existing worker boundary, not native transports or metadata events.

The comm worker owns the query `AbortController`, invokes the product call,
opens the returned descriptor with `.selected` demand, validates the content
frames and JSON schema, and returns only the newest correlated result. The
picker owns presentation state:

| State | Enter | Exit and invariant |
| --- | --- | --- |
| idle | picker closed | picker open starts a query |
| loading | picker open or failed-state retry | newest result, failure, close, or supersession |
| ready | newest catalog decoded | select or close; no implicit refresh transition |
| empty | newest catalog has no choices | Commit remains available |
| failed | current query fails | explicit retry or close; current comparison unchanged |

Opening the picker starts one query regardless of remembered mode, while focus
still follows the remembered Branch or Commit input. Switching modes preserves
that in-modal preload; it does not start or cancel another request. Closing,
pane-session replacement, or a newer query makes the older request identity
inadmissible; late results are discarded. Foreground loss aborts through the
same worker `workSignal` and invalidates the captured
`workAdmissionGeneration`; it does not create a second picker lifecycle.

After native provider dispatch begins, the generic control replay contract may
finish the command even when the UI request has become obsolete. In that case
the worker does not open or apply the descriptor. If native foreground admission
was still valid when backing was installed, that body remains only as the single
bounded pending body described above; if admission was already lost, no body is
installed. This is deliberate: changing generic command replay semantics would
be broader and less reliable than bounded request-scoped retention.

The Branch selector keeps the owned Base UI/shadcn-style Combobox primitives.
Filtering covers the full returned catalog; `Combobox.useFilteredItems()` feeds
the external virtualizer; item indices and highlight scrolling preserve
keyboard and active-descendant behavior. Each virtual row continues to render
the unambiguous branch name, local or remote-tracking kind, abbreviated target
revision, full assistive revision, and query-snapshot `Default` marker. Capture
cutoff and truncation state remain query data, so every ready or empty result
renders only the concise 30-day explanation adjacent to the list. Truncation
remains available for diagnostics and proof but does not add picker copy. None
of that enters pane metadata.

## Call-path delta

```text
CURRENT — PACKAGED
Review initialization
  → provider.reviewComparisonTargets()
  → scheduler(.reviewMetadata)
  → libgit2 enumerates and peels every branch
  ← complete catalog or error
  → refresh coordinator writes targetCatalog
  → pane.presentation metadata
  → worker projection
  → React renders matching rows

CURRENT — DEVELOPMENT
Host construction
  → loadReviewComparisonTargetCatalog()
  → provider.reviewComparisonTargets()
  → scheduler(.reviewMetadata)
  → libgit2 enumerates and peels every branch
  ← complete catalog or error
  → makeRefreshAdmissionCoordinator(targetCatalog:)
  → initial pane.presentation metadata

TARGET — CURRENT COMPARISON, PACKAGED
Review initialization
  → clear compact default identity
  → capture repository + Review/admission identity
  → provider.resolveReviewDefaultTarget()
  → scheduler(.reviewMetadata)
  → libgit2 opens and peels one designated ref
  ← default target or nil/error
  → controller revalidates repository + Review/admission identity
  → current completion publishes default symbolic identity
  → no durable intent: existing mutation initializes from resolved default
  → refresh coordinator writes compact comparison presentation
  → pane.presentation metadata

TARGET — CURRENT COMPARISON, DEVELOPMENT
Host construction or comparison attempt
  → remove construction-time catalog read and clear compact default identity
  → capture repository + product/foreground admission
  → shared Git client resolveReviewDefaultTarget()
  → scheduler(.reviewMetadata)
  → libgit2 opens and peels one designated ref
  ← default target or nil/error
  → development host revalidates repository + admissions
  → refresh coordinator writes compact default symbolic identity
  → existing development presentation publication

TARGET — REQUESTED CATALOG
Comparison picker opens
  → worker captures work generation + binds workSignal
  → worker review.comparisonTargets.query
  → provider reads live repository/target projection
  → provider acquires foreground admission
  → scheduler(.selectedVisibleContent)
  → libgit2 bounded correlated capture
  ← capture or query-local error
  → provider revalidates foreground admission
  → current completion installs pending descriptor backing
  → content.open(.selected)
  ← catalog frames or reset/error
  → worker validation + work-generation/latest-request admission
  → React virtualized rows
```

| Edge | Status | Result/error behavior |
| --- | --- | --- |
| Review initialization → unbounded `reviewComparisonTargets()` | removed | startup no longer depends on catalog size |
| Packaged Review initialization → repository/admission capture → constant default resolver → revalidation | changed | prior compact identity clears; stale completion writes nothing; current nil/failure leaves identity absent and fabricates no target |
| Development construction/attempt → eager catalog read | removed | the development host never enumerates choices to create current comparison state |
| Development construction/attempt → repository/admission capture → constant default resolver → revalidation | changed | both hosts publish the same compact default-identity contract through the shared coordinator |
| catalog → comparison presentation → metadata stream | removed | strict contracts reject `targetCatalog` |
| resolved default → compact symbolic identity → pane presentation → UI target comparison | added | one pushed fact truthfully classifies active or displayed symbolic targets without catalog data |
| Picker open → worker work generation/signal → query command → typed native call | added | foreground loss or correlated failure affects picker only |
| native live authority projection → bounded Git capture → foreground revalidation | added | current target is read at admission; stale completion installs no body |
| query call result → descriptor → content.open | added | single-use claim, framed terminal, bounded release |
| decoded catalog → virtualized selector | changed | bounded mounted rows; full returned set remains searchable |
| target selection → `review.comparison.update` → `core.sqlite` intent | intentionally unchanged | catalog OID is never mutation authority |
| comparison capture/publication/invalidation/origin flow | intentionally unchanged | PR0 comparison behavior remains authoritative |

Source anchors include
`BridgePaneController+ReviewContribution.swift`,
`BridgePaneRefreshAdmissionCoordinator.swift`,
`BridgeDevelopmentProductHost.swift`,
`BridgeDevelopmentProductHost+ReviewComparison.swift`,
`BridgePaneProductSchemeProvider.swift`,
`BridgeProductSchemeControlDispatcher.swift`,
`BridgePaneProductContentDemandAuthority.swift`,
`bridge-comm-worker-product-controller.ts`,
`bridge-worker-rpc-client.ts`, and the pinned
`LibGit2ReviewComparisonTargetReader.swift`.

## Failure, ordering, and cleanup

```text
default resolver unavailable
  → compact default identity remains absent
  → restored current comparison remains eligible to proceed
  → no branch enumeration fallback

Git capture / admission / command failure
  → correlated picker failure
  → current comparison and durable intent unchanged

descriptor mismatch / second open / oversize / digest / decode failure
  → existing content error or reset
  → body released
  → picker failure; comparison unchanged

close / newer query
  → abort worker content work when possible
  → reject late result by query identity in all cases
  → release claimed body, or retain only one bounded pending body

foreground loss during Git capture
  → abort worker query through pane workSignal
  → invalidate worker workAdmissionGeneration
  → native foreground token fails final revalidation
  → install no new pending body

pane-session replacement or close
  → reject old capability and query identity
  → release pending and claimed query bodies during provider/session drain
```

Product-control sequencing already serializes native query calls per session.
The existing scheme-provider actor provides the pending-to-claimed atomic
boundary. Existing session, worker derivation epoch, product admission, content
request, query identity, pane `workSignal`, and work-admission generations
provide stale-result rejection. The live repository/target projection is a
read-only view of existing host state, not another authority. No new actor,
global generation, mutex, retry scheduler, or cross-pane coordinator is added.

## Cross-cutting realization

- Performance and capacity: `AppPolicies.Bridge` owns the capture window and
  row/byte bounds; the Git scheduler, content admission, byte encoder, and
  virtualizer enforce them at their respective boundaries.
- Reliability: compact comparison metadata is independent from query success;
  product/session identities and the query-source lifecycle contain late,
  cancelled, or malformed results.
- Accessibility: the owned Combobox remains the semantic control; external
  virtualization preserves active-descendant, keyboard highlight, selection,
  scroll-to-highlight, full assistive revisions, and distinguishable local and
  remote-tracking rows rather than replacing them with custom rows.
- Trust and containment: the browser cannot choose a repository path or product
  capacity, strict schemas validate the call, descriptor, and body, and the
  existing pane capability and session authority gate both physical routes. No
  new secret, privilege, or external actor is introduced.
- Data lifecycle and privacy: the catalog is local repository metadata retained
  only in ephemeral picker state and one bounded pane-session descriptor
  backing. It is neither persisted nor exported.
- Platform parity: packaged WKWebView and the Swift development backend compose
  the same native providers and differ only at the existing URL mapping.

## Hard cutover and documentation invariants

The Agent Studio cutover removes `targetCatalog` from native/TypeScript
presentation schemas, strict-key corpora, worker projections, fixtures, and UI
props and adds the compact `repositoryDefaultTarget` identity in the same
revision that adds the query call/content contracts. Existing `core.sqlite`
target intent requires no migration and remains the only durable comparison
selection.

The Swift development backend composes the same default resolver, compact
presentation owner, query source, Git client, admission, command, and content
contracts as the packaged scheme provider; it only maps the physical routes to
HTTP for Vite. Host-specific attempt methods remain separate composition roots,
but neither host owns a different comparison-target contract.

The permanent Bridge architecture must distinguish:

```text
publication-backed descriptors
  File and Review bodies authorized by committed metadata/publication

request-scoped query descriptors
  finite data authorized by an explicit typed query result
```

Accordingly, the native invariant becomes “publication-backed content follows
metadata publication for that generation”; it must not claim that
request-scoped query descriptors require metadata publication. Demand docs
also record the explicit mapping from query content to native `.selected`
interest rather than implying all content priority is subscription-derived.

## How each requirement is realized and proved

| Requirement | Structural owner and realization | Proof seam |
| --- | --- | --- |
| CT-R1 | per-host repository/admission snapshot, constant default resolver, currentness revalidation, compact default symbolic identity, and shared comparison presentation | native/metadata interleavings prove one default lookup, no catalog enumeration in either host, identity clearing, stale completion rejection, current failure → absent, and correct active/displayed marker derivation |
| CT-R2 | call registry, query source, content registry, worker query controller | strict contract parity and production-backed command → descriptor → content transcript |
| CT-R3 | bounded agentstudio-git capture with canonical-ref deduplication plus Bridge byte encoder | real-Git upstream tests and Agent Studio integration cover cutoff and capture-time bounds including a future-dated tip, collapsed default/current roles, ordering, distinct-row capacity, both caps, and no fetch/write |
| CT-R4 | owned Combobox plus external virtualizer and picker state | browser and visual proof cover one query on picker open in either remembered mode, immediate preloaded rows after switching Commit to Branch, focus, row labels/kinds/revisions/accessibility, mounted-row bound, search, keyboard, selection, always-visible concise recency text, and empty state |
| CT-R5 | worker request/work-admission identity and abort plus native foreground revalidation and query-source claim/release lifecycle | interleaving tests cover close, mode switches that preserve the in-modal preload, foreground loss during capture, after descriptor issuance but before open, and during claimed streaming; supersession; late command/content results; no stale backing install; and teardown residue |
| CT-R6 | live current-target projection plus explicit packaged/development compact-current paths and unchanged pane intent, comparison update, publication, and origin owners | both-host initialization and mutation-after-construction coverage, SQLite restart, development-server transcript, and packaged-app regression proof |

The `agentstudio-git` repository owns public-contract and real-libgit2 proof for
its two new reads. Agent Studio must use the published pinned revision in its
production-backed development-server proof; a local fake or TypeScript Git
utility cannot satisfy that boundary.

## Complexity spent and revisit signals

Spent:

- two focused upstream Git reads: constant default resolution and bounded
  catalog capture;
- one application query call and one content kind over existing routes;
- one pane-scoped, single-pending descriptor backing;
- one worker query lifecycle and one standard virtualized selector.

Not spent:

- persistence, caching, cross-pane sharing, pagination, watcher invalidation,
  background warming, network fetch, a new transport, or a generalized Git
  browser.

Revisit only if measured Branch-activation latency remains unacceptable after
bounded capture, or if product requirements expand from recent target
selection to complete branch/history browsing. Those signals may justify
pagination or caching later; they do not justify either in this correction.
