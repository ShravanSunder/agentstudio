# Bridge Resource Data Plane Spec

Date: 2026-06-20

Status: design amendment for `LUNA-338` before implementation planning

Related:

- `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md`
- `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`
- `docs/plans/2026-06-18-bridgeweb-large-diff-fast-loop-remediation.md`

## Purpose

Bridge review needs to load huge worktree diffs without blank panes, slow file
clicks, eager content pushes, or unbounded React/Zustand memory. The viewer must
work in two loops:

- the Vite dev server with realistic large worktree data
- the packaged AgentStudio Bridge pane with the same loading contracts

This spec tightens the data loading architecture before the next implementation
plan. It separates command intent from read payloads, defines a broader
`agentstudio://resource/*` data plane, and makes Zustand a typed index over
feature-owned package/content registries instead of a raw-content store.

## Current State Evidence

The live code currently supports a narrow content-only resource path:

- `BridgeContentHandleIdentity.resourceUrl(...)` mints
  `agentstudio://resource/content/{handleId}?generation=N`.
- `BridgeSchemeHandler.classifyPath(...)` accepts only `app/*` and
  `/resource/content/{handleId}?generation=N`.
- `BridgeContentStore.loadObserved(...)` validates generation, handle, content
  hash, binary status, and cache state, then returns a full payload.
- `BridgeWeb/src/bridge/bridge-resource-url.ts` parses only content URLs.
- `loadBridgeContentResource(...)` validates the URL and reads
  `response.text()`.
- `BridgeApp` currently keeps the selected item's loaded resources in React
  state, while the Zustand store keeps selection, projection status, worker
  status, and hydration status only.

That means the current design is already metadata-push/content-pull, but it is
not yet range-aware, window-aware, or explicit about content/resource registry
ownership.

## Product Requirements

1. The Bridge viewer must support large agent-written diffs where the user can
   select, scroll, collapse, expand, search, filter, and open docs/plans without
   forcing the whole package content into the web page.
2. The Vite dev harness and native AgentStudio pane must use the same schema
   contracts, cache rules, and resource-loading model.
3. Item-window loading is required for the first working large-diff slice.
   Click-to-file reveal, jump-to-file, collapse/expand, and scroll hydration must
   not depend on pushing every item descriptor or every file body up front.
4. Data fetching must be cache-before-fetch. If the requested package window,
   item window, content segment, tree segment, or full body is already available
   and fresh, BridgeWeb must not ask Swift or the dev server for it again.
5. Zustand is the typed review index and UI state store. It must not store raw
   large file bodies, raw diff bodies, Pierre model instances, Worker instances,
   or generic transport managers.
6. Heavy or blocking frontend work must stay off hot React render paths.
   Projection, large filtering, search/facet computation, markdown rendering,
   Shiki highlighting, and diagnostics that scale with package/content size use
   typed worker lanes unless the implementation plan proves a tiny-workload
   synchronous path with the same stale-drop and telemetry semantics.
7. The design must support future repo file browsing and single-file viewing.
   It cannot be a review-diff-only shortcut.
8. The design must leave room for review comments, annotations, and local-agent
   review conversations. Those are future PRs, but they must not force a later
   rewrite of the data plane.

## Plane Ownership

Bridge has three planes. They are deliberately separate.

```text
Command / IPC plane
  owns: semantic intent, authz, target resolution, pane routing
  exposes: bridge.review.load, bridge.review.refresh,
           bridge.review.selectFile, bridge.review.setMode,
           bridge.review.setFacets, bridge.review.revealFile,
           bridge.review.prepareWindow, bridge.telemetry.snapshot
  does not expose: raw WebKit calls, raw postMessage, EventBus command routing,
                   raw file bodies, arbitrary path reads

Push / notification plane
  owns: compact state facts from Swift to BridgeWeb
  exposes: package available, package updated, selected file changed,
           content ready, telemetry sampled
  does not expose: large source bodies or authoritative read permissions

Resource data plane
  owns: read payload transfer through agentstudio://resource/*
  exposes: package summaries/snapshots, review item windows/lists, whole
           content bodies, future content ranges, tree windows/ranges,
           future bounded read-only resource kinds
  does not expose: commands, UI actions, source mutation, broad filesystem
                   browsing outside an issued scope
```

The command plane may prepare or reveal data, but the payload comes from the
resource data plane. For example, a headless test can call
`bridge.review.selectFile` or `bridge.review.prepareWindow`, then BridgeWeb
fetches the needed resource URLs.

## Resource Data Plane Contract

All read payloads go through `agentstudio://resource/*`. URLs are capability
requests scoped to a Bridge pane/package/generation/revision. The page may pass
or request these URLs, but Swift remains the authority that validates scope.

Initial resource kinds:

```text
agentstudio://resource/review-package/{packageId}?generation=N&revision=R

agentstudio://resource/review-items/{packageId}?generation=N&revision=R
  &cursor=C&rangeKind=itemWindow&start={firstItem}&end={exclusiveEnd}

agentstudio://resource/review-items/{packageId}?generation=N&revision=R
  &rangeKind=list&itemIds=item-a,item-b

agentstudio://resource/content/{handleId}?generation=N
  &rangeKind=whole

agentstudio://resource/tree/{treeId}?generation=N&revision=R
  &cursor=C&depth=2
```

These shapes are illustrative contract targets, not implementation sequence.
The implementation plan owns exact naming once tests pin the parser. Future
content-range extensions may add line and byte ranges, but the first vertical
slice should not implement them unless metrics show whole-content reads are the
actual bottleneck.

### Range Semantics

Ranges are closed at the start and open at the end:

- item windows: `start` inclusive, `end` exclusive, scoped to a Swift-issued
  cursor or explicit item-id list
- future line ranges: `start` inclusive, `end` exclusive
- future byte ranges: `start` inclusive, `end` exclusive

Item windows are required for smooth large-diff review. They hydrate the visible
review slice, jump target, and nearby overscan without moving the whole package
through React. The index range is valid only inside the active package,
generation, revision, and cursor; if any of those change, the window is stale
and must be dropped.

Item-window indexes are presentation coordinates, not authority. First-slice
item windows are legal only when they use a Swift-issued cursor token that binds
the package, generation, revision, ordering, and facet/filter state that created
the window. If filtered/sorted order is BridgeWeb-owned or stale-prone,
BridgeWeb must request an explicit bounded item-id list instead of relying on a
naked index range. A page-owned `projectionId` is never accepted as Swift
authority.

Item IDs are opaque, stable within the package generation/revision, and safe to
use in URLs. They may remain current string handles, or move to compact base64url
hash-like handles if payload-size metrics show the current identifiers materially
hurt push, URL, or parse costs. Either way, Swift maps the id back to the
package item, endpoint, role handles, content hash, and path membership.

Line ranges are text ranges in the requested content role. They are not hunk
ranges unless the resource kind explicitly says so in a future extension. Byte
ranges are raw byte ranges and must not split UTF-8 if the response is declared
as text; otherwise Swift returns a typed range error or binary response.

The list form is for small explicit sets only. Long lists must use a window,
cursor, or another bounded server-issued query shape to avoid query-string
limits and unbounded validation costs.

### Adaptive Range Budget Policy

The spec does not set arbitrary first caps such as "100 items" or "500 lines".
Window sizes are a measured policy, not a design guess.

The implementation plan must define an adaptive budget seeded by current
BridgeWeb and native metrics:

- visible CodeView rows/files
- FileTree visible rows
- overscan needed for smooth wheel/trackpad scroll
- scroll velocity and click-to-reveal distance
- p95 resource fetch, parse, worker projection, markdown/Shiki, and controller
  apply timings
- package descriptor bytes and average item/content size
- memory pressure and cache eviction rate
- stale-drop and duplicate-fetch rate

The policy starts with visible item count plus measured overscan, expands when
latency or scroll velocity requires prefetch, and contracts under memory
pressure. Hard safety ceilings still exist in Swift and TypeScript, but they are
derived from benchmark evidence and parser/provider protection needs, not from
placeholder design numbers.

### Zod And Type Contract

BridgeWeb resource contracts are schema-first:

- schema values use lower camel case with `Schema` suffix, for example
  `bridgeResourceRequestSchema`
- derived types use Pascal case without the suffix, for example
  `BridgeResourceRequest`
- variants use Zod discriminated unions
- no raw `unknown` crosses resource, worker, or IPC boundaries after parsing

Core variants:

```typescript
export const bridgeResourceKindSchema = z.enum([
  'reviewPackage',
  'reviewItems',
  'content',
  'tree',
]);

export const bridgeResourceRangeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('whole') }),
  z.object({
    kind: z.literal('itemWindow'),
    cursor: z.string().min(1),
    start: z.number().int().nonnegative(),
    end: z.number().int().nonnegative(),
  }),
  z.object({
    kind: z.literal('list'),
    itemIds: z.array(z.string().min(1)).min(1),
  }),
  z.object({
    kind: z.literal('cursor'),
    cursor: z.string().min(1),
    limit: z.number().int().positive(),
  }),
]);
```

The final schemas should live under Bridge-owned resource/foundation modules,
not inside React components. Tests must prove the Swift route classifier and
TypeScript parser agree on accepted and rejected URLs.

## Zustand And Content Registry Model

Zustand stores the index, not the large data.

```text
Zustand review store
  activePackageRef
  activeGeneration
  activeRevision
  selectedItemId
  activeProjectionId
  projection mode and filter refs
  visible item window refs
  hydration status by itemId
  cache keys and lightweight counters
  worker request IDs and statuses

Closure-owned review-viewer registries
  package snapshots by packageId/generation/revision
  review item windows by packageId/generation/revision/cursor or item-list key
  content segments by handleId/generation/contentHash/range key
  tree segments by treeId/generation/revision/root-or-cursor/depth
  in-flight fetches by canonical resource key
  worker jobs by requestId
  CodeView/FileTree/Worker imperative handles
```

The closure maps may be private variables inside the store creator or explicit
feature-owned registry objects referenced from selectors/actions. Do not name
this layer `runtime`; that name hides ownership. Use folders such as
`review-viewer/content`, `review-viewer/projections`, `review-viewer/commands`,
or `review-viewer/app` according to the reason the code changes. Registries must
be managed like resources, with clear reset and eviction rules.

Reset triggers:

- package id changes
- review generation changes
- package revision changes when descriptors or order are invalidated
- pane unmount
- worker failure requiring a hard registry/controller reset
- resource parser/schema version changes in dev/test harness

Cache keys include the freshness fence:

```text
package key = packageId + generation + revision
items key   = packageId + generation + revision + cursor/list key + range kind + range value
content key = handleId + generation + contentHash + range kind + range value
tree key    = treeId + generation + revision + root/cursor + depth
```

Cache-before-fetch invariant:

```text
request intent
  -> canonical resource key
  -> fresh cache hit? return cached value
  -> in-flight match? await/coalesce
  -> stale/backoff/evicted? fetch resource URL
  -> parse/validate
  -> store in feature-owned registry
  -> update Zustand status/key counters only
  -> notify CodeView/Tree/Markdown controllers
```

Raw body content, markdown HTML, parsed Pierre item payloads, and large tree
prepared inputs do not become broad Zustand state.

## Frontend Loading Flow

```text
Swift push / dev fixture
  -> compact active package identity and descriptor summary
  -> Zustand activePackageRef + revision
  -> worker projection for large package/filter/search/facets
  -> visible item window
  -> content/resource registry checks review item descriptors
  -> resource fetch if missing
  -> content handle discovery
  -> visible/selected/neighbor content requests
  -> content registry checks whole content or future content segments
  -> resource fetch if missing
  -> worker markdown/Shiki/projection as needed
  -> CodeView/FileTree controllers update imperatively
```

Hydration priorities:

1. selected item
2. currently rendered CodeView items
3. visible file tree rows near selection
4. hovered item
5. neighbor/prefetch items for guided review

Visible-range signals come from public Pierre APIs or measured controller
state. If a stable public CodeView range signal is unavailable, the first plan
must use selected/hover/guided-neighbor hydration and keep true viewport
hydration behind a measured API spike. Brittle DOM queries are not the primary
authority unless protected by browser tests against virtualization recycling.

Package metadata remains metadata-first, content-pull. Small and medium packages
may still arrive as compact push-delivered snapshots. Large packages may use a
tiny push notification plus resource-backed item windows when the measured
snapshot payload crosses the implementation plan's cutoff. The product model is
unchanged: the page gets metadata, then fetches only the item/body data it needs.

## Swift Resource Resolution

Swift owns resource authority:

```text
BridgeSchemeHandler
  -> parse resource kind and query
  -> reject malformed, traversal, unknown kind, negative or over-budget ranges
  -> resolve pane/package/generation/revision scope
  -> resolve opaque handle/item/tree scope to provider request
  -> use BridgeContentStore or package/tree resolver
  -> return typed payload or typed error
```

The page must not gain authority by constructing a path-like URL. For content,
`handleId` remains opaque. Swift maps handle id to endpoint, item, role, and
content hash through the registered content store. For tree resources, `treeId`
or cursor must be scoped to an active package/query and validated before any
provider read.

Every resource route validates:

- scheme and host
- path kind
- package id, generation, revision, or handle id
- range kind and numeric bounds
- adaptive list/window/range budget and hard safety ceilings
- active pane scope
- active package/query scope
- item id, endpoint id, role, and path membership when applicable

Parser and canonicalization rules:

- each resource kind has an exact allowlist of query keys
- unknown keys fail closed
- duplicate singleton keys fail closed, including duplicate `generation`,
  `revision`, `rangeKind`, `cursor`, `depth`, `start`, or `end`
- selector families are mutually exclusive; a request cannot mix `cursor`,
  explicit `itemIds`, and future line/byte range selectors
- explicit `itemIds` are comma-separated opaque ids, preserve caller order, and
  are rejected when they exceed the implementation plan's measured budget
- canonical serialization sorts query keys, percent-encodes with one shared
  Swift/TypeScript rule, and is the only cache/in-flight key source
- Swift route classification and TypeScript parsing share fixtures for accepted
  URLs, rejected duplicate keys, mixed selectors, traversal/path injection, and
  unknown extras

## Command And IPC Correction

IPC remains semantic and command-like. It does not return hot file/diff bodies
as the default loading path.

Recommended command/control methods:

- `bridge.review.load`
- `bridge.review.refresh`
- `bridge.review.getPackage`
- `bridge.review.setMode`
- `bridge.review.setFacets`
- `bridge.review.selectFile`
- `bridge.review.revealFile`
- `bridge.review.scrollToFile`
- `bridge.review.prepareWindow`
- `bridge.review.expandFile`
- `bridge.review.collapseFile`
- `bridge.fileTree.search`
- `bridge.fileTree.setFacets`
- `bridge.fileTree.revealPath`
- `bridge.fileView.setRenderMode`
- `bridge.telemetry.snapshot`
- `bridge.telemetry.flush`

`bridge.review.prepareWindow` may ask Bridge to mint/refresh bounded resource
URLs, validate scope, issue server-owned item-window cursors, or warm
Swift-side caches. The actual item/content/tree data is then fetched through
`agentstudio://resource/*`.

If a test or automation needs content, it should use the same resource URL path
that the viewer uses, after target resolution and permission checks have made
the relevant resource handle available.

## Future Comments And Agent Review

Review comments and agent question loops are future work, not part of the first
loading fix. The resource data plane should still anticipate them.

Expected future shape:

```text
user reviews code
  -> command plane records intent
     comment.create | comment.update | comment.resolve | agent.ask
  -> annotation/comment metadata is pushed as compact state
  -> comment bodies, quoted ranges, context bundles, and agent attachments
     are fetched through bounded resource URLs when large
  -> local agent receives a scoped review context, not unrestricted repo reads
  -> agent responses return as comments/events plus optional resource handles
```

Comments introduce two new payload classes:

- small metadata that belongs in push/update state: ids, anchors, status,
  author kind, timestamps, range refs, and summary labels
- large or sensitive payloads that belong behind resource handles: quoted
  source context, markdown comment bodies if large, agent prompt context,
  attachments, generated review bundles, and response transcripts

Do not design comment and agent review around raw paths or whole-repo dumps.
The same scope rules apply: pane, package, generation, revision, item id, line
range, and content handle authority stay explicit. A future local-agent review
loop may receive a deliberately assembled context bundle, but that bundle is a
Bridge-owned resource with bounds, telemetry, redaction, and permission checks.

## Worker Rules

Worker lanes are typed and explicit:

- Pierre Shiki worker pool owns syntax highlighting.
- Bridge projection worker owns large package projection, search, filter, facet
  counting, and future guided-review scoring preparation.
- Markdown worker owns rich markdown rendering if enabled.
- Diagnostics or benchmarking workers may exist in test/dev support only.

Worker code lives under the feature that owns the product behavior. For the
review viewer, production workers belong under `BridgeWeb/src/review-viewer/workers/*`
with lane subfolders such as `projection`, `markdown`, `pierre`, and
`shared-rpc`. Do not create app-wide worker folders or generic worker managers
unless a second feature proves the same worker contract is reusable. A shared
worker contract must move to `foundation` only after its feature-independent
boundary is explicit.

Workers receive parsed DTOs and return parsed DTOs. They do not receive open
manager instances, Zustand store objects, raw telemetry emitters, or authority
to fetch Swift resources unless a dedicated WKWebView proof test verifies direct
worker `agentstudio://resource/*` fetches. The first implementation should keep
main-thread resource authority and transfer bytes/DTOs to workers for expensive
decode, parse, markdown, projection, and Shiki work. Main thread owns
cancellation, stale-result discard, and application to CodeView/FileTree
controllers.

## Dev Server Contract

The Vite dev server must not bypass the architecture:

- it provides a mock resource scheme/server that follows the same resource
  schemas as the native pane
- it supports real worktree-backed packages for this branch and synthetic large
  fixtures
- it exercises cache hits, in-flight coalescing, stale drops, item windows,
  whole-content reads, markdown, and worker lanes
- it records debug metrics compatible with the Victoria/OTLP naming model when
  enabled

Dev-only shortcuts may generate data, but they must enter the viewer through the
  same package/resource/registry interfaces as native AgentStudio.

## Observability

Debug telemetry must answer these questions without raw paths or content:

- how many package/item/content/tree resource requests happened
- how many were cache hits, in-flight coalesces, stale drops, or provider loads
- what range classes were requested
- how long fetch, parse, worker execution, and controller application took
- whether the CodeView visible range and selected item were hydrated
- whether dev server and native pane follow the same request pattern

Suggested metric names:

- `performance.bridge.resource.fetch`
- `performance.bridge.resource.cache`
- `performance.bridge.resource.range`
- `performance.bridge.viewer.visible_window`
- `performance.bridge.worker.task`
- `performance.bridge.controller.apply`

Allowed attributes are low-cardinality: resource kind, range kind, cache result,
phase, workload bucket, status, lane, generation relation, and fixture class.
Raw paths, source text, patch text, raw handle values, prompts, and errors with
source content are not exported.

## Security Context

This design is security-sensitive. It touches local repository content, WebKit,
custom URL schemes, typed IPC, workers, markdown, and telemetry.

Rules:

- resource URLs are read-only capabilities, not filesystem paths
- Swift validates every resource request against active pane/package scope
- BridgeWeb treats package metadata and URL strings as display/input data, not
  read authority
- unknown resource kinds and unknown query parameters fail closed unless the
  parser explicitly supports them
- range bounds are capped and normalized before provider calls
- list/window requests are budgeted, capped, and de-duplicated
- path traversal and double-encoded traversal are rejected
- binary and oversized content returns typed fallback states
- markdown rendering sanitizes through the worker path or returns a typed
  unavailable state; source text is fallback UI, not acceptance proof
- no source mutation is exposed by the resource plane
- service workers are not allowed in the Bridge pane

## Alternatives

### Put all data through IPC

Rejected for the hot loading path. It mixes command/authz intent with bulk data,
adds per-call command routing overhead, and risks a second body-returning API
that diverges from what the viewer uses.

### Keep only content URLs and push all package/items

Insufficient for huge diffs. It keeps the first package push too large and does
not allow item-window hydration, tree browsing, or future file explorer reads.

### Store full packages and bodies in Zustand

Rejected. It increases rerender pressure, makes eviction harder, and puts
large mutable payloads in the wrong abstraction. Zustand remains the typed
index and status store.

### Make item-window indexes the authority

Rejected. Indexes drift across projection/filter/revision changes. Item-window
indexes may be a presentation request, but authority must remain package,
generation, revision, projection id, item IDs, opaque handles, or Swift-issued
cursors.

## Proof Expectations

The implementation plan must turn these into concrete gates:

- Unit: Swift resource classifier accepts/rejects every resource kind and range
  shape, including traversal, malformed query, stale generation, negative
  ranges, over-budget ranges, and unknown kind.
- Unit: TypeScript resource parser uses Zod discriminated unions and agrees with
  Swift fixture cases.
- Unit: cache-before-fetch returns fresh registry/cache values and coalesces
  in-flight resource requests.
- Unit: Zustand boundary checks reject raw bodies, fetch calls, worker posts,
  Pierre mutations, and telemetry emits from `review-viewer/state`.
- Unit: architecture boundary checks reject generic `runtime/` ownership for
  review-viewer code that can be named by responsibility, and reject
  feature-owned workers outside `review-viewer/workers/*`.
- Unit: worker request/response schemas reject malformed or stale results.
- Integration: dev server large fixture loads package identity without eager
  file bodies.
- Unit: item-window cache keys include cursor or item-list identity and
  stale-drop when package, generation, revision, cursor, or item-list selection
  changes.
- Integration: selecting an item fetches only missing required content bodies
  and does not refetch fresh data.
- Integration: item-window/list resource requests hydrate the visible slice and
  the clicked/revealed item without blank rows or offscreen header jumps.
- Integration: markdown docs/plans render through the sanitized read-only
  markdown worker path without remote-resource loading. Source text is a typed
  unavailable/fallback state only; it is not a passing functional-review
  acceptance path.
- Browser: Vitest Browser Mode with Playwright proves click-to-file scroll,
  collapse/expand stability, search/filter, visible hydration, worker activity,
  and no blank surface for a large fixture.
- Native: AgentStudio debug Bridge pane opens this branch's huge worktree diff,
  hydrates selected and visible content, and emits Victoria metrics for resource
  fetch/cache/worker/controller timings.

## Open Decisions For Review

1. What measured package-snapshot cutoff flips from full compact metadata push
   to tiny notification plus resource-backed item windows?
2. Should first-slice item IDs remain current opaque strings, or should we move
   to compact base64url hash-like ids only if payload/parse metrics justify it?
3. What adaptive item-window budget formula should the implementation plan seed
   from current dev-server, native Bridge pane, and DiffsHub-scale benchmark
   metrics?
4. Confirm line/byte content ranges are a second slice unless metrics prove
   whole-content reads are the current bottleneck.

## Next Step

Review this spec, then use `plan-creation-swarm` to produce the loading-system
implementation plan. That plan should make one vertical slice pass in both the
dev server and the real AgentStudio Bridge pane before broadening the resource
surface.
