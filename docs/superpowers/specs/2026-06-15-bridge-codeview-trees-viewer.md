# Bridge CodeView And Trees Viewer Spec

> Status: design source for `LUNA-338` before implementation planning.
> Created: 2026-06-15
> Foundation: [Bridge Review Foundation Spec](2026-06-10-bridge-review-foundation.md)
> Architecture companion: [Swift-React Bridge Architecture](../../architecture/swift_react_bridge_design.md)
> Linear: `LUNA-338` Pierre/Shiki/Trees review viewer

This spec defines the next Bridge viewer milestone after `LUNA-337`. It covers
the read-only Pierre CodeView, Shiki worker, and Trees viewer architecture.
It does not replace the review package foundation. It consumes it.

The goal is a real agent-first review pane that can render files, diffs, and
file collections while preserving the Bridge contract: Swift pushes compact
metadata, BridgeWeb pulls bytes only when needed, and expensive UI work stays
off hot React render paths.

## Product Boundary

The viewer is read-only. It helps users inspect and navigate files, diffs,
checkpoint comparisons, worktree changes, and plan/docs files. It must not own
a source editor buffer, apply patches, accept agent changes, or mutate
workspace files.

Annotation anchors may be rendered later through CodeView line/range metadata,
but durable comment bodies, markdown note editing, and review artifact
persistence are not part of this milestone.

## App IPC Control Boundary

The merged AgentStudio IPC foundation is now available to LUNA-338. Bridge
should use it for headless e2e testing and future agent control, but IPC
integrates with Bridge as a product capability, not as BridgeWeb control.

The ownership model is:

```
External client
  -> AgentStudio IPC JSON-RPC method
  -> authentication, authorization, handle/target resolution
  -> Bridge capability port
  -> Bridge app/runtime owner
  -> BridgeWeb transport only if the Bridge owner chooses to update WebKit
```

BridgeWeb remains a pane renderer and page transport. It must not become an IPC
subsystem. IPC must not expose generic methods such as
`webview.evaluateJavaScript`, `bridge.rawPostMessage`, `bridge.rawPush`,
`eventBus.publish`, or `zmx.*`.

Bridge IPC methods should be semantic and typed in
`AgentStudioProgrammaticControl`. Preferred initial methods are:

- `bridge.diff.load`
- `bridge.diff.refresh`
- `bridge.diff.getPackage`
- `bridge.diff.selectFile`
- `bridge.fileView.getContent`
- `bridge.telemetry.flush`

Only methods with real product owners should enter the method catalog. A method
that would need a fake success, a raw WebKit call, command-bar UI automation, or
EventBus command routing is out of scope until a semantic Bridge capability port
exists.

Bridge IPC authorization must be capability-scoped through the repo's closed
`IPCPrivilegeClass`, `IPCDataScope`, and `IPCPermissionScope` model. The design
intent maps to these privileges:

- Bridge review metadata read
- Bridge content-handle read
- Bridge control: open, refresh, select, mark viewed
- Bridge telemetry read
- Bridge telemetry flush

Pane-bound agents should normally have only self-pane Bridge access. Cross-pane
or workspace/global Bridge access requires explicit delegated policy or grants.

Target resolution must land on a live Bridge pane. Existing `pane:<id>` and
friendly pane handles are acceptable for the first slice. If the implementation
needs active/current pane handles or `surface:<id>`, extend the IPC handle model
explicitly and test it. A terminal, webview, or missing pane target must fail
with a typed unsupported-target outcome instead of fallback behavior.

Content access should prefer Bridge content handles over raw paths. A package
read may return item metadata and handles. `bridge.fileView.getContent`
validates the handle, package id, review generation, role, and bounds before
returning content. Raw filesystem paths, arbitrary refs, hashes, prompt text, or
source paths must not become IPC payload shortcuts.

Bridge IPC events are notification-only facts:

- `bridge.review.updated`
- `bridge.file.selected`
- `bridge.content.ready`
- `bridge.telemetry.sampled`

Events must not be used as command routing. Commands go through the IPC method
registry, authorization, target resolution, and Bridge capability ports. Events
are emitted after Bridge owners mutate state.

## Current State

`LUNA-337` established the source-provider-neutral review foundation:

- `BridgeReviewQuery`
- `BridgeReviewPackage`
- `BridgeReviewItemDescriptor`
- `BridgeReviewDelta`
- `BridgeContentHandle`
- `BridgeReviewGeneration`
- lazy `agentstudio://resource/content/{handleId}?generation=...` content
  loading
- BridgeWeb package, content, telemetry, and minimal shell modules

BridgeWeb currently renders a plain shell: package summary, visible file list,
selection, and selected-item content in a text block. It does not yet depend on
`@pierre/diffs`, `@pierre/trees`, or worker-backed Shiki highlighting.

`origin/main` now also includes the phase-one AgentStudio IPC foundation:
typed JSON-RPC contracts, method definitions, permission scopes, event
subscriptions, command/UI separation, and app composition adapters. The current
IPC method catalog does not yet include Bridge semantic methods, so LUNA-338's
implementation plan must add them explicitly if the e2e proof needs Bridge IPC.

That means `LUNA-338` is not a cosmetic swap of one component. It must add the
viewer ownership layers that sit between the review package and Pierre's
imperative rendering APIs.

## Package Dependency Boundary

BridgeWeb must add Pierre as explicit BridgeWeb dependencies, not as transitive
or vendored assumptions. The researched local Pierre source reports:

- `@pierre/diffs` version `1.2.10`, license `apache-2.0`
- `@pierre/trees` version `1.0.0-beta.4`, license `apache-2.0`

BridgeWeb must also add:

- `zustand` for viewer state slices and selector-based React subscriptions.
- `tsdown` for the BridgeWeb packaged build output that is copied into the
  SwiftPM resource bundle.

Dependency strategy:

- BridgeWeb pins published or prebuilt package artifacts in `pnpm-lock.yaml`.
- The local Pierre checkout is reference material for API verification only.
- Do not import source files from `/Users/.../pierre/packages/*` into
  BridgeWeb. The local monorepo uses workspace and catalog dependencies that
  would turn this viewer ticket into cross-repo package tooling work.

The plan must verify:

- package license compatibility
- installed export paths for `@pierre/diffs`, `@pierre/diffs/react`,
  `@pierre/diffs/worker`, `@pierre/trees`, and `@pierre/trees/react`
- `zustand` export paths used by BridgeWeb
- final BridgeWeb bundle size impact
- worker asset output shape after `tsdown` build
- WKWebView loading from the packaged `agentstudio://app/*` origin

Do not shape Bridge contracts around package-private Pierre internals. Use
documented exports only.

BridgeWeb may keep Vite for local dev server and Vitest integration, but the
mergeable packaged-app build should be a `tsdown`-owned artifact path. The plan
must update `mise run bridge-web-build` and the app-asset normalization script
so `tsdown` emits deterministic JS, CSS if applicable, worker assets, and an
asset manifest under `Sources/AgentStudio/Resources/BridgeWeb/app`.

Debug hot reload is a follow-up developer-experience lane, not a substitute for
packaged WKWebView proof. The preferred design is a DEBUG-only Bridge app asset
root override such as `AGENTSTUDIO_BRIDGEWEB_APP_ROOT`, served through the
existing `agentstudio://app/*` scheme handler after the same path-confinement
checks as packaged assets. Pair it with a BridgeWeb watch/build task that emits
into the override directory, then reload the Bridge pane. Do not make the
Bridge pane load a generic `http://localhost` dev server for this proof lane;
that would bypass the real scheme handler, bootstrap, content-resource origin,
and worker-loading constraints this ticket is meant to validate.

Library decisions:

- `@pierre/diffs/react`: CodeView, File, FileDiff, types, refs, and
  scroll/selection APIs. BridgeWeb adapter only; Swift never sees Pierre DTOs.
- `@pierre/diffs/worker`: Shiki worker pool entry and worker stats types.
  Highlighter work only; no Bridge content authority.
- `@pierre/trees/react`: file tree model, search, selection, and virtualization.
  Path navigation only; projections stay Bridge-owned.
- `zustand`: viewer-local store slices and selector subscriptions. IDs, status,
  and queues only; no raw large file bodies.
- `zod` v4: schema-first LUNA-338 viewer-local contracts, worker/RPC
  envelopes, and any shared contract files explicitly touched by the
  implementation. Parse at boundaries and tests; avoid hot-loop reparsing.
- `vitest`: unit, integration, jsdom, and `expectTypeOf` type tests. Required
  for adapter and schema proof.
- `tsdown`: deterministic packaged BridgeWeb build artifacts. Mergeable app
  bundle path; Vite remains dev/test support.

Do not add a general worker-RPC dependency until the implementation plan proves
it improves the local protocol. The default is a tiny Bridge-owned request/result
envelope built from Zod discriminated unions. A `comlink` spike is acceptable
only if it keeps explicit request IDs, cancellation, schema parsing, telemetry,
and source-scrubbed error payloads.

## BridgeWeb TypeScript Stack

Follow the repo's TypeScript stack rather than inventing a parallel one:

- package manager: `pnpm`
- runtime UI: React
- state: Zustand store slices with narrow selectors
- schemas: Zod v4 schemas with `z.infer` for Bridge-owned data types
- tests: Vitest unit, integration, jsdom, and `expectTypeOf` type tests
- lint/format/typecheck: oxlint, oxfmt, TypeScript strict mode
- packaged build: `tsdown` output copied into the SwiftPM resource bundle
- local dev only: Vite may remain as a dev server if it still helps iteration

Rules:

- For Bridge-owned contracts, schemas are source of truth and types derive from
  `z.infer<typeof schema>`.
- Zod model naming is standardized:
  - schema values use lower camel case with a `Schema` suffix, for example
    `bridgeViewerWorkerRequestSchema`
  - derived types use Pascal case without the suffix, for example
    `BridgeViewerWorkerRequest`
  - schema and type names must describe the domain concept, not the transport
    accident that first needed it
- Prefer Zod object composition with `.pick(...)`, `.omit(...)`,
  `.extend(...)`, and discriminated unions over hand-written duplicate types.
- Use `z.record(z.string(), z.unknown())` only when the payload is genuinely an
  opaque extension bag or external JSON object. Narrow it as soon as the
  product owns the shape.
- Use descriptive generic names when generic helpers are required, for example
  `TProjectionResult`, `TBridgeMessage`, or `TPierreItem`. Do not use
  single-letter generics for product-facing helper types.
- For Pierre-owned contracts, import Pierre's exported types and either use
  those types directly or define narrow adapter types that prove assignability
  with Vitest `expectTypeOf`.
- Do not copy Pierre's `CodeViewItem`, `FileContents`,
  `FileDiffMetadata`, worker option, or tree prepared-input shapes into local
  hand-written types.
- Add type tests alongside adapter tests whenever a local Bridge adapter claims
  compatibility with a Pierre type.
- Use `satisfies` for literals where a test fixture or config should be checked
  without widening away useful inference.

## Architecture Discipline

The viewer has hot data-plane paths, so code organization must be enforceable,
not only remembered in review. The implementation plan must choose and wire the
exact BridgeWeb architecture boundary checks.

Expected enforcement layers:

- lint rules for import and call-site boundaries, likely through Oxlint custom
  JS plugin rules if the implementation spike confirms the API is stable enough
  for this repo
- TypeScript strict mode for compile-time contract drift
- Zod v4 schemas for Bridge-owned boundary payloads
- Vitest unit and `expectTypeOf` tests for schema/type/Pierre adapter proof
- selector and performance tests for Zustand write/rerender discipline
- debug-only runtime metrics for large-workload proof

Boundary rules to enforce:

- `review-viewer/state` may define Zustand slices, selectors, and pure actions.
  It must not call Swift, fetch content, post worker messages, mutate Pierre
  models, or emit telemetry directly.
- `review-viewer/content` owns content hydration effects and may call
  `foundation/content`.
- `review-viewer/workers/rpc` owns `Worker` creation, `postMessage`, response
  parsing, cancellation, and Bridge-owned worker measurement context. It does
  not emit telemetry directly.
- `review-viewer/workers/pierre` owns Pierre Shiki worker-pool creation and
  worker stats sampling.
- `review-viewer/trees` is the only BridgeWeb folder that imports
  `@pierre/trees` runtime APIs or mutates the FileTree model.
- `review-viewer/code-view` is the only BridgeWeb folder that imports
  `@pierre/diffs/react` runtime CodeView APIs or calls CodeView imperative
  methods.
- `foundation/telemetry` is the only BridgeWeb folder that emits telemetry.
  Other folders may prepare low-cardinality measurement context.
- Raw file bodies must not be stored in Zustand slices. Loaded bodies live in
  the content cache and are applied to CodeView through the code-view
  controller.

This is not a lint-only contract. Lint catches obvious boundary drift; type
tests and runtime proof catch semantic and performance drift. The implementation
plan owns exact rule names, rule implementation details, fixture placement, and
command wiring.

## DiffsHub Reference Boundary

Pierre's DiffsHub is strong prior art, not an architecture to copy wholesale.

Borrow these patterns:

- one mixed CodeView scroll surface for files and diffs
- imperative CodeView ownership for large or streaming surfaces
- stable item IDs plus `version` bumps for targeted updates
- file tree and CodeView joined by explicit path-to-item maps
- file tree search and Git-status filtering as first-class sidebar controls
- status/stat panels that show file counts, line counts, and worker health
- worker-backed Shiki highlighting with plain text rendered first
- batched publishing so tree/model updates are O(delta), not repeated O(N)
- deterministic scroll benchmarks over the real CodeView scroller

Do not copy these DiffsHub-specific pieces:

- Next.js routing, server components, SSR preload, or public GitHub URL rewriting
- `/api/diff` as the source of truth for content
- browser-side GitHub fetch/auth/network policy
- patch-stream parsing as the only package model
- process-facing console timers as the proof path
- public-web theme persistence and URL hash behavior when Swift should own pane
  lifecycle and workspace context

AgentStudio's equivalent of DiffsHub's patch stream is the Bridge package/delta
stream. Swift owns source access and content handles; BridgeWeb owns projection,
selection, visible-range hydration, and renderer adapters.

DiffsHub is one public URL -> one diff stream -> one file-tree/status view.
AgentStudio is one active review source -> many review projections -> one
renderer surface.

```text
DiffsHub
  GitHub URL
    -> patch stream
    -> append-only accumulator
    -> CodeView items + file tree + Git status filter

AgentStudio Bridge
  BridgeReviewQuery
    -> Swift package/delta metadata
    -> BridgeWeb projection state
    -> Trees view modes + CodeView hydration + future agent-guided queue
```

The important difference is that AgentStudio's sidebar is a review-control
surface, not only a patch file list. Search and Git-status filters are local
filters inside the current projection. Projection buttons can reorder or reduce
the entire package: all files, changed files, guided review, current change set,
docs/plans, tests, source, folder, extension, and file class.

View model comparison:

| Concern | DiffsHub | AgentStudio Bridge |
| --- | --- | --- |
| Source | public GitHub-like URL | Swift-owned `BridgeReviewQuery` |
| Initial data | patch stream | package/delta metadata |
| Sidebar primary action | inspect one diff tree | choose a review projection |
| Local filters | search and Git status | search, Git status, facets, docs/tests/source |
| Ordering | patch order | package order, guided order, future agent score |
| Content authority | fetched web patch/content | Swift-issued handles only |
| Future review flow | comments/demo annotations | agent-guided queue and annotations |

## LUNA-338 Prerequisites

This spec assumes `LUNA-337` has landed and owns the review foundation:

- `BridgeReviewPackage` and `BridgeReviewDelta` JSON contracts.
- `BridgeReviewItemDescriptor.contentRoles` and `BridgeContentHandle`
  resource URLs.
- `BridgeReviewGeneration` freshness checks.
- lazy `agentstudio://resource/content/{handleId}?generation=...` delivery.
- BridgeWeb package registry, content fetch, telemetry batch, and minimal shell.
- packaged BridgeWeb app-asset delivery through `agentstudio://app/*`.

`LUNA-338` owns the viewer layer above that foundation: Pierre dependencies,
projection/navigation state, Trees and CodeView adapters, Shiki worker setup,
viewer-specific observability, and the first packaged WKWebView proof. If a
tree row lacks a usable content handle, `LUNA-338` may add a scoped
handle-resolution RPC as described below; it must not reinterpret top-level
`openFile` as an incremental handle request.

## First Slice Contract

The first implementation slice is package-backed review navigation:

- Use the active `BridgeReviewPackage` as the source of truth for file rows.
- Build Trees input from package item paths and package visibility.
- Render files, diffs, and plan/docs files only after obtaining Swift-issued
  content handles.
- Keep rich markdown preview out of the first slice. Markdown renders as
  source text in CodeView unless a later plan adds a sanitizer and proof gate.
- Keep arbitrary endpoint tree browsing out of the first slice. Existing
  top-level `browseTree` or `openFile` queries may replace the active package,
  but the viewer does not add a general `readTree(...)` browse UI in this
  milestone.
- Use uncontrolled/imperative CodeView ownership in production from day one.
  Controlled CodeView mode is fixture/test-only.

## Primary Design Decision

Introduce a BridgeWeb projection and hydration layer before integrating Pierre
renderers.

The review package is the semantic contract. Trees and CodeView have different
identity and update models:

- Trees is path-first. Selection, focus, search, and row decoration operate on
  path strings.
- CodeView is item-first. Scrolling, line selection, annotations, collapse
  state, and item updates operate on stable item IDs.
- Content loading is handle-first. Bytes are fetched only through
  `BridgeContentHandle.resourceUrl`.

Do not let any one of these models swallow the others. The viewer must preserve
all three identities explicitly.

```text
BridgeReviewPackage
  | metadata only
  v
Review projection layer
  | ordered path/item views, facets, mode state
  +-----------------------------+
  |                             |
  v                             v
Trees adapter              CodeView adapter
path identity              item identity
selection/search/focus     scroll/line/range/update
  |                             |
  +-------------+---------------+
                |
                v
          Hydration layer
          content handles -> fetched bytes -> render item update
```

Detailed runtime flow:

```text
Swift review source
  |
  | BridgeReviewPackage / BridgeReviewDelta
  | metadata only, no file bodies
  v
foundation/review-package registry
  |
  | visibleItems + descriptor indexes
  v
review-viewer/state
  |
  +--> projection action
  |      -> projection worker RPC above the plan-defined threshold
  |      -> ordered item IDs, paths, facets, maps
  |      -> Zustand projection slice
  |
  +--> Trees adapter
  |      -> preparePresortedFileTreeInput outside React render
  |      -> worker-prepared only if public API clone-safety is proved
  |      -> FileTree model reset/batch
  |      -> search, Git-status filters, row selection
  |
  +--> CodeView adapter
  |      -> initial placeholders / hydrated items
  |      -> imperative addItems/updateItem/scrollTo
  |
  +--> content hydration queue
         -> selected/visible/hover/neighbor priorities
         -> foundation/content fetch
         -> agentstudio://resource/content/...
         -> loaded text cache
         -> CodeView item version bump
```

Projection and filtering flow:

```text
Top-level projection buttons
  all | changed | guided | change set | docs/plans | tests | source
          |
          v
Bridge projection result
  orderedItemIds + orderedPaths + facetCounts + display maps
          |
          v
Local tree controls inside that projection
  search text | Git status menu | folder | extension | file class
          |
          v
Trees visible rows
          |
          v
selected path -> itemId -> CodeView scroll/hydration
```

Worker lanes:

```text
Pierre Shiki lane
  CodeView/File/FileDiff
    -> WorkerPoolContextProvider
    -> @pierre/diffs workerFactory
    -> syntax highlight results

Bridge-owned compute lane
  package/projection inputs
    -> typed Zod worker RPC envelope
    -> order/filter/facet/path-map result
    -> Zustand projection slice
    -> Trees/CodeView adapters
```

The Pierre Shiki lane should use Pierre's worker pool directly. The Bridge-owned
compute lane is for heavy package projection, future agent-guided scoring
preparation, and facet/count work. Do not manually post messages into Pierre's
Shiki workers. Benchmark fixture generation is test-harness work and must not
ship in the packaged runtime worker.

Imperative controller flow:

```text
Zustand declarative state
  |
  +--> trees controller
  |      owns FileTree model ref
  |      applies resetPaths / batch / selection / focus
  |
  +--> codeview controller
  |      owns CodeViewHandle ref
  |      applies addItems / updateItem / updateItemId / scrollTo
  |
  +--> hydration controller
         owns content request queue
         writes loaded content cache
         asks codeview controller to materialize item updates
```

React components render controller state and dispatch typed actions; they do
not directly scatter Pierre model mutations.

Effect ownership stays outside the Zustand store:

- Zustand actions update pure state, enqueue intent, and record status. They do
  not call Swift, fetch content, post worker messages, mutate Pierre models, or
  emit telemetry directly.
- `review-viewer/content` owns content effects: visible/selected/hover/neighbor
  hydration queues, `foundation/content` calls, stale result drops, and loaded
  body cache writes.
- `review-viewer/workers/rpc` owns Bridge worker effects: request creation,
  Zod parsing on send and receive, cancellation, queue timing, stale result
  discard, and low-cardinality measurement context. It reports that context to
  `foundation/telemetry`; it does not call telemetry emitters directly.
- `review-viewer/trees` owns Tree effects: prepared input creation, model
  reset/batch operations, focus, selection, expansion, and row decoration.
- `review-viewer/code-view` owns CodeView effects: item materialization,
  `addItems`, `updateItem`, `updateItemId`, selected-line changes, and scroll
  targeting.
- `foundation/telemetry` owns debug-only telemetry effects. Store slices expose
  measurement context and low-cardinality status, not exporter calls.

## BridgeWeb Folder Shape

Keep BridgeWeb domain-oriented and avoid generic folders:

```text
BridgeWeb/src/
  app/
  bridge/
  foundation/
    content/
    review-package/
    review-query/
    telemetry/
  review-viewer/
    state/
    navigation/
    content/
    code-view/
    trees/
    workers/
      pierre/
      rpc/
    markdown/
    shell/
```

Responsibilities:

- `foundation/review-package`: wire contracts, package/delta registry, and
  base package visibility from `filterState`. It must not import Pierre
  packages.
- `review-viewer/state`: owns the Zustand store, typed actions, and selectors
  for viewer-local package, projection, selection, hydration, CodeView, worker,
  and telemetry state. It must not fetch bytes or call Swift directly.
- `review-viewer/navigation`: builds file-tree projections, facets, filtered
  views, and path-to-item maps from the review package registry's
  `visibleItems`. It must not reimplement `filterState` visibility.
- `review-viewer/trees`: owns `@pierre/trees` model creation, prepared input,
  search, selection, focus, and row decoration.
- `review-viewer/content`: owns selected, visible, hover, and neighbor content
  hydration state. It talks to `foundation/content`.
- `review-viewer/code-view`: converts descriptors plus loaded content into
  Pierre `CodeViewItem` records and owns CodeView item updates.
- `review-viewer/workers/pierre`: owns Pierre worker-pool creation, render
  options, worker stats sampling, and failure fallback.
- `review-viewer/workers/rpc`: owns Bridge-owned worker request/result schemas,
  typed client helpers, cancellation, and worker measurement context. It does
  not own Pierre Shiki worker messages and does not emit telemetry directly.
- `review-viewer/markdown`: owns read-only markdown file rendering decisions.
  It must not live in `foundation/content`.
- `review-viewer/shell`: composes navigation, toolbar mode controls, Trees,
  CodeView, and markdown/file panels.

## BridgeWeb State Model

Use Zustand for viewer-local state. React component state is acceptable for
ephemeral UI-only details, and refs are still the right place for imperative
CodeView handles, tree model handles, and worker manager instances. The
Zustand store owns durable viewer state that multiple components and adapters
need to read without prop drilling.

```text
Swift push/RPC
  |
  v
BridgeWeb app ingress
  |
  v
review-viewer/state Zustand store
  | package slice       active package, revision, selected item id
  | projection slice    mode, projection result, facet counts
  | tree slice          search text, Git-status filter, expanded/focused paths
  | hydration slice     queue, inflight requests, cache keys, stale drops
  | code-view slice     mounted item ids, collapsed state, scroll target
  | worker slice        worker-pool status and sampled stats
  | telemetry slice     debug-only viewer measurement context
  |
  +--> selectors --> shell / toolbar / Trees / CodeView
  +--> actions   --> pure state updates / queued intents / status records
  |
  +--> effect coordinators --> content / workers / Trees / CodeView / telemetry
```

State rules:

- Store actions and action payloads are typed and, where they cross a boundary,
  schema-first with Zod v4 and `z.infer`.
- Selectors should be narrow and stable. Components subscribe to the smallest
  state they need; the root shell must not rerender on every content-cache or
  worker-stat update.
- The store holds IDs, descriptors, lightweight status, queue state, and
  derived projection results. It does not store raw large file bodies as a
  general app state blob.
- Loaded text content belongs in the viewer content cache. CodeView receives
  updates imperatively from the code-view adapter when content becomes ready.
- The foundation registry remains the owner of base package visibility from
  `filterState`; Zustand projection state reads from that registry and does
  not duplicate the visibility algorithm.
- Tree search text, Git-status filter state, projection mode, and selected item
  ID are small enough for Zustand. Prepared tree input, CodeView handle, FileTree
  model, worker manager, and loaded file bodies stay outside Zustand.
- On `packageId` or `reviewGeneration` change, the store must clear selected
  item if stale, hydration queues, loaded content cache entries for the old
  package, mounted item IDs, pending scroll target, and current worker RPC
  request IDs. CodeView remounts with a new viewer key for hard package changes.
- Package deltas for the same package/generation may preserve selection and
  expansion when the selected item and paths still exist.

## Navigation Modes And Projections

The user needs fast buttons for different review views:

- all files
- changed files
- guided review order
- current change set
- docs and plans
- tests only
- source only
- folder/path scoped
- extension/language scoped
- file class scoped

These are viewer projections over one package, not separate package types.
They are also broader than DiffsHub's Git-status menu. DiffsHub filters one
patch tree by status. AgentStudio switches between review tasks and then applies
local filters inside the chosen task.

Add a BridgeWeb-local projection model. This is not a Swift wire contract and
must not be serialized into `BridgeReviewPackage` unless a later plan proves a
backend-owned field is necessary.

Use discriminated unions for projection state. Split base projections from
composable refinements. A base projection answers "what review task is the user
doing?" Refinements answer "how is that task narrowed in the local tree?"
Do not model this as one broad interface with optional parameters; that hides
invalid states and cannot express combinations such as changed files narrowed to
tests under one folder.

Define these shapes schema-first with Zod v4, then derive TypeScript types from
the schemas. Runtime parsing is required at Bridge boundaries and tests; hot
internal paths may use the inferred types without reparsing every object.

```typescript
import { z } from 'zod';

import {
  bridgeContentRoleSchema,
  bridgeFileClassSchema,
} from '../../foundation/review-package/bridge-review-package';

export const bridgeCurrentChangeSetScopeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('activePackage') }),
  z.object({
    kind: z.literal('provenance'),
    provenanceKind: z.enum(['prompt', 'session', 'operation']),
    provenanceId: z.string().min(1),
  }),
]);

export type BridgeCurrentChangeSetScope = z.infer<
  typeof bridgeCurrentChangeSetScopeSchema
>;

export const bridgeReviewFacetCountsSchema = z.object({
  fileClasses: z.record(z.string(), z.number().int().nonnegative()),
  extensions: z.record(z.string(), z.number().int().nonnegative()),
  changeKinds: z.record(z.string(), z.number().int().nonnegative()),
  reviewStates: z.record(z.string(), z.number().int().nonnegative()),
  hidden: z.number().int().nonnegative(),
  binary: z.number().int().nonnegative(),
  large: z.number().int().nonnegative(),
});

export type BridgeReviewFacetCounts = z.infer<
  typeof bridgeReviewFacetCountsSchema
>;

export const bridgeReviewProjectionRefinementSchema = z.discriminatedUnion(
  'kind',
  [
    z.object({ kind: z.literal('folder'), folderPath: z.string().min(1) }),
    z.object({ kind: z.literal('extension'), extensions: z.array(z.string().min(1)) }),
    z.object({ kind: z.literal('language'), languages: z.array(z.string().min(1)) }),
    z.object({ kind: z.literal('mime'), mimeTypes: z.array(z.string().min(1)) }),
    z.object({ kind: z.literal('fileClass'), fileClasses: z.array(bridgeFileClassSchema) }),
    z.object({
      kind: z.literal('gitStatus'),
      statuses: z.array(z.enum(['added', 'modified', 'renamed', 'deleted', 'copied'])),
    }),
    z.object({
      kind: z.literal('visibility'),
      includeHidden: z.boolean(),
      includeBinary: z.boolean(),
      includeLarge: z.boolean(),
    }),
  ],
);

export type BridgeReviewProjectionRefinement = z.infer<
  typeof bridgeReviewProjectionRefinementSchema
>;

export const bridgeReviewProjectionResultSchema = z.object({
  projectionId: z.string().min(1),
  label: z.string().min(1),
  orderedItemIds: z.array(z.string().min(1)).readonly(),
  orderedPaths: z.array(z.string()).readonly(),
  primaryDisplayPathByItemId: z.record(z.string(), z.string()),
  primaryItemIdByTreePath: z.record(z.string(), z.string()),
  secondaryItemIdsByTreePath: z.record(z.string(), z.array(z.string()).readonly()),
  candidatePathsByItemId: z.record(z.string(), z.array(z.string()).readonly()),
  itemIdsByDisplayPath: z.record(z.string(), z.array(z.string()).readonly()),
  availableContentRolesByItemId: z.record(
    z.string(),
    z.array(bridgeContentRoleSchema).readonly(),
  ),
  facetCounts: bridgeReviewFacetCountsSchema,
});

export const bridgeReviewProjectionModeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('allFiles') }),
  z.object({ kind: z.literal('changedFiles') }),
  z.object({ kind: z.literal('guidedReview') }),
  z.object({
    kind: z.literal('currentChangeSet'),
    scope: bridgeCurrentChangeSetScopeSchema,
  }),
  z.object({ kind: z.literal('docsAndPlans') }),
  z.object({ kind: z.literal('tests') }),
  z.object({ kind: z.literal('source') }),
  z.object({ kind: z.literal('custom'), customProjectionId: z.string().min(1) }),
]);

export const bridgeReviewProjectionRequestSchema = z.object({
  base: bridgeReviewProjectionModeSchema,
  refinements: z.array(bridgeReviewProjectionRefinementSchema).readonly(),
});

export const bridgeReviewProjectionSchema = bridgeReviewProjectionRequestSchema
  .and(bridgeReviewProjectionResultSchema);

export type BridgeReviewProjection = z.infer<
  typeof bridgeReviewProjectionSchema
>;
```

Swift can own canonical ordering and review-priority metadata. BridgeWeb owns
projection switching, local filters, and the path/item maps used by Trees and
CodeView. For large packages, BridgeWeb should avoid sorting in React render.
If Swift already provided final order, BridgeWeb should call
`preparePresortedFileTreeInput(orderedPaths)` outside render and pass the
prepared input to the Trees model.

Projection semantics for the first slice:

- `allFiles`: all registry `visibleItems` in package order.
- `changedFiles`: visible items whose `changeKind` is `added`, `modified`,
  `deleted`, `renamed`, or `copied`.
- `guidedReview`: visible items in the deterministic order below, derived only
  from existing descriptor fields: `reviewState`, `reviewPriority`,
  `fileClass`, `changeKind`, `extension`, path, and `isHiddenByDefault`.
- `currentChangeSet`: the active package query scope. For compare packages this
  is equivalent to `changedFiles`. For checkpoint, prompt, session, or
  time-window packages it narrows only when the package already carries the
  relevant `provenance` identifiers. It must not call Swift for a new package
  or invent a backend session model.
- `docsAndPlans`: visible items with `fileClass === 'docs'` or markdown-like
  paths under `docs/`, `docs/plans/`, `docs/superpowers/specs/`, or
  `docs/superpowers/plans/`. A markdown-like path has extension `.md` or
  `.mdx`, or a basename containing `plan`, `spec`, `design`, or `handoff`.
- `tests` and `source`: visible items with `fileClass === 'test'` or
  `fileClass === 'source'`.
- folder, extension/language/MIME, file-class, Git-status, and visibility
  filters are refinements over the selected base projection. They do not mutate
  the package filter and can be combined.

The projection layer must tolerate many-to-one and one-to-many path
relationships. A display path can map to multiple review items, and a single
review item can have base and head paths. The default display path remains
`headPath`, falling back to `basePath`, then `itemId`, but the candidate-path
map must retain both sides for renamed files, deleted files, and annotations.

Tree-row identity policy:

- `primaryItemIdByTreePath[path]` is the item selected, hovered, and prefetched
  when a tree row is activated.
- `secondaryItemIdsByTreePath[path]` contains additional review items sharing the
  same display path.
- Primary item selection is deterministic: visible projection order first,
  then available `head` role, then `diff` role, then `base` role, then
  lexicographic `itemId`.
- Row decoration aggregates Git-like state by strongest visible change:
  deleted, renamed, added, modified, copied. Product facets such as docs/plans,
  binary, large, generated, and review priority aggregate as bounded badges or
  counts.
- CodeView and annotation targeting always use `itemId` plus content role/path,
  never only display path.

When the architecture docs say CodeView identity is derived from a content
handle, this spec narrows the implementation rule: `BridgeReviewItemDescriptor`
`itemId` is the CodeView item ID. Content handles, content hashes, and cache
keys participate in item `version` and `cacheKey`, not DOM/item identity.

Projection mode switches should reuse existing package data. They should not
trigger content fetches by themselves. Content fetches happen only when a file
or diff becomes selected, visible, hovered, or near-visible according to the
hydration policy.

Initial guided review order should be deterministic and explainable:

1. unreviewed high-priority source/config changes
2. unreviewed normal-priority source changes
3. tests related to visible source changes
4. docs/plans/config context
5. generated, vendor, large, binary, and hidden items last unless explicitly
   requested

Later backend scoring can replace this projection only if it arrives as
metadata on review items or groups. The viewer should not call source providers
to compute guided order.

### Sidebar Controls

The first viewer shell should expose these control groups:

- projection segmented control: all, changed, guided, change set, docs/plans,
  tests, source
- tree search button/input backed by `useFileTreeSearch(model)`
- Git-status filter menu: added, modified, renamed, deleted, copied if
  represented in Bridge metadata, and clear filter
- secondary facet menu: folder, extension/language, file class, hidden/large
  visibility
- compare selector display: current package query label, such as against main,
  against checkpoint, against worktree, or single file

Control semantics:

- Projection buttons can reorder and reduce the package. They rebuild projection
  maps and usually call `resetPaths(...)` with fresh prepared input.
- Search and Git-status filters are local to the current projection. They do not
  request a new package and should not fetch content.
- The Git-status menu uses Trees built-in `gitStatus` only for Git-like states.
  Product-specific signals such as generated, hidden, large, docs/plans,
  agent-priority, or annotation count must use row decoration/facets, not fake
  Git statuses.
- The future agent-guided review system should arrive as descriptor/group
  metadata or a Bridge-owned projection result. It must not be a hidden side
  channel in the tree component.

## Trees Integration

Use `@pierre/trees` and `@pierre/trees/react` as a stable imperative tree model.
`useFileTree(...)` creates the model once. Later changes should use model
methods such as `resetPaths(...)`, search, focus, and selection methods.

Rules:

- Use prepared input for repo-scale trees.
- Prefer `preparePresortedFileTreeInput(...)` when Swift or the projection
  layer owns final order.
- Keep prepared input creation outside React render. For medium and large
  workloads, projection/search/facet shaping must already be off the UI thread.
  Worker-prepared Pierre `FileTreePreparedInput` is allowed only after explicit
  structured-clone proof against the installed public API.
- Give the tree host a real CSS height.
- Use density and overscan intentionally, not custom virtualization.
- Keep path selection and CodeView item selection synchronized through the
  projection maps.
- Do not hand-roll `FileTreePreparedInput`; it is an opaque Pierre type.
- Do not import package-private Pierre paths such as `packages/trees/dist/...`,
  `@pierre/*/dist/**`, non-exported subpaths, or local checkout paths. This
  includes `import type`. BridgeWeb uses installed public package exports only.

Tree row decoration should derive from item descriptor metadata:

- change kind
- file class
- review priority
- hidden/large/binary state
- annotation summary
- review state

Renames need a visible path policy. The default display path is `headPath`,
falling back to `basePath`, then `itemId`. Rename metadata should still preserve
both base and head paths for CodeView and annotation targeting.

Tree update policy:

- New package or new generation: create a new projection and reset the model.
- Projection switch that filters, removes, or reorders rows: call
  `resetPaths(...)` with a matching prepared input and ancestor-derived
  `initialExpandedPaths`; preserve selection only when the selected item still
  exists. Do not default to `initialExpansion: "open"` for full workspace trees.
- Same-projection append-only package delta: may use `model.batch(...)` with add
  operations when the previous tree source proves append-only growth.
- Git-status-only changes: use installed public Trees status update APIs, not
  full path rebuilds. With the currently installed package this means
  `setGitStatus(...)`; do not call local-repo or private
  `applyGitStatusPatch(...)` unless a pinned published package exposes it as a
  public export.
- Search and local status filter changes: use Trees search/filter APIs and keep
  the prepared input stable.

Controller ownership:

- `review-viewer/trees` exposes a `BridgeTreesController`.
- The controller owns the `FileTree` model reference created by `useFileTree`.
- The controller is the only module that calls `resetPaths(...)`, `batch(...)`,
  `setGitStatus(...)`, tree focus, and tree selection APIs. A narrower status
  patch API can be adopted later only after it is available through public
  `@pierre/trees` exports.
- The controller subscribes to the narrow projection/tree slices it needs and
  applies imperative mutations in effects or controller methods, never during
  React render.
- Components can dispatch actions such as `setProjectionBase`, `setRefinement`,
  `selectTreePath`, and `toggleGitStatusFilter`; they do not call FileTree
  mutation APIs directly.
- Teardown unregisters the model and cancels pending tree-side actions without
  clearing package registry state owned by `foundation/review-package`.

Tree event sequence:

```text
package push
  -> registry visibleItems update
  -> projection action
  -> trees controller resetPaths(preparedInput)
  -> preserve selected path if still present

package delta append
  -> registry applies delta
  -> projection action marks append-only if valid
  -> trees controller batch(add paths) and status patch

projection/refinement switch
  -> projection action rebuilds ordered paths/maps
  -> trees controller resetPaths(preparedInput)
  -> selected item retained only if still in primary/secondary maps

tree row click
  -> primaryItemIdByTreePath[path]
  -> store selected item
  -> hydration controller queues selected item
  -> codeview controller scrollTo item/range
```

## CodeView Integration

Use `@pierre/diffs/react` `CodeView` as the main code surface for mixed file
and diff scroll regions.

Pierre `CodeViewItem` records map from Bridge items. Define the adapter's local
render model schema-first with Zod v4 and derive the TypeScript type from it.
Do not pass optional `file`, `fileDiff`, `placeholder`, and handle fields
through one loose object.

```typescript
import type {
  CodeViewDiffItem,
  CodeViewFileItem,
  CodeViewItem,
  FileContents,
  FileDiffMetadata,
} from '@pierre/diffs/react';
import { z } from 'zod';

const pierreFileContentsSchema = z.custom<FileContents>(
  (value: unknown): value is FileContents => value !== null,
);
const pierreFileDiffMetadataSchema = z.custom<FileDiffMetadata>(
  (value: unknown): value is FileDiffMetadata => value !== null,
);
const pierreCodeViewFileItemSchema = z.custom<CodeViewFileItem>(
  (value: unknown): value is CodeViewFileItem => value !== null,
);
const pierreCodeViewDiffItemSchema = z.custom<CodeViewDiffItem>(
  (value: unknown): value is CodeViewDiffItem => value !== null,
);

export const bridgeCodeViewRenderItemSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('file'),
    itemId: z.string().min(1),
    version: z.number().int().nonnegative(),
    cacheKey: z.string().min(1),
    codeViewItem: pierreCodeViewFileItemSchema,
  }),
  z.object({
    kind: z.literal('diff'),
    itemId: z.string().min(1),
    version: z.number().int().nonnegative(),
    cacheKey: z.string().min(1),
    codeViewItem: pierreCodeViewDiffItemSchema,
  }),
  z.object({
    kind: z.literal('placeholder'),
    itemId: z.string().min(1),
    reason: z.enum(['binary', 'large', 'missingContentRole', 'notLoaded']),
    title: z.string(),
    message: z.string(),
  }),
]);

export type BridgeCodeViewRenderItem = z.infer<
  typeof bridgeCodeViewRenderItemSchema
>;
```

The `z.custom<T>()` schemas above treat Pierre-owned objects as opaque runtime
values while preserving compile-time assignability to Pierre exports. Add
Vitest type tests with `expectTypeOf`:

```typescript
import type { CodeViewItem } from '@pierre/diffs/react';
import { describe, expectTypeOf, test } from 'vitest';

describe('Bridge CodeView adapter types', () => {
  test('file and diff render items carry Pierre-compatible CodeView items', () => {
    expectTypeOf<BridgeCodeViewRenderItem>()
      .extract<{ kind: 'file' }>()
      .toHaveProperty('codeViewItem')
      .toMatchTypeOf<CodeViewItem>();

    expectTypeOf<BridgeCodeViewRenderItem>()
      .extract<{ kind: 'diff' }>()
      .toHaveProperty('codeViewItem')
      .toMatchTypeOf<CodeViewItem>();
  });
});
```

Rules:

- `id` is `BridgeReviewItemDescriptor.itemId`.
- `version` comes from `itemVersion` plus content/render-affecting local
  version state.
- `cacheKey` must use Bridge content identity and change whenever content
  changes.
- `collapsed` changes must bump the CodeView item version.
- Line/range scroll targets use CodeView `scrollTo`, not pixel offsets.
- Use CodeView `layout` and `itemMetrics`; do not fake item spacing in CSS.
- Keep token hooks off by default. Token metadata increases DOM size and should
  be enabled only when a later annotation or hover feature needs it.
- The initial visual slice is dark-only and starts with Bridge's
  AgentStudio-owned `agentstudio-bridge-dark`
  theme. When the Shiki worker pool is enabled, configure the same theme at the
  worker-pool render-options boundary; component-only theme settings are not
  sufficient proof that highlighted tokens use the intended theme.

Prefer imperative CodeView ownership for large or streaming review surfaces:
seed with `initialItems`, then use the ref APIs (`addItems`, `updateItem`,
`getItem`, `scrollTo`). Controlled `items` mode is acceptable for tests and
small packages, but the production viewer should not route every item update
through a full React item array.

Controller ownership:

- `review-viewer/code-view` exposes a `BridgeCodeViewController`.
- The controller owns the `CodeViewHandle` reference and viewer key.
- The controller is the only module that calls `addItems(...)`,
  `updateItem(...)`, `updateItemId(...)`, `setSelectedLines(...)`, and
  `scrollTo(...)`.
- The controller receives materialized `BridgeCodeViewRenderItem` records from
  the content/hydration layer and applies item updates imperatively.
- The controller remounts CodeView on hard package changes:
  `packageId`, `reviewGeneration`, or renderer option changes that require
  clearing the item registry.
- The controller preserves selected lines only when the selected `itemId` and
  range still exist after a delta/projection update.
- Components can dispatch actions such as `selectItem`, `collapseItem`,
  `expandItem`, and `scrollToSelection`; they do not call the CodeView ref
  directly.

### CodeView Content Materialization

Bridge review descriptors are metadata. Pierre CodeView items require complete
`FileContents` or `FileDiffMetadata` values.

The adapter must materialize items by content role:

- `itemKind: 'file'` uses the `file` handle when present, falling back to the
  selected endpoint handle only if the descriptor explicitly provides one.
- `itemKind: 'diff'` with a `diff` handle may parse a patch string through
  Pierre's patch utilities before producing `FileDiffMetadata`.
- `itemKind: 'diff'` with `base` and `head` handles may build old/new
  `FileContents` and use Pierre's file-diff parsing path.
- Added and deleted files must render correctly when only one side exists.
- Binary and large files should produce a non-code placeholder item until the
  user explicitly requests loading, if loading is allowed.

The adapter must not assume every descriptor has a single universal content
handle. It must branch on `BridgeReviewContentRoles`.

The materialization request should also be schema-first and discriminated so
each path has the exact handles and loaded content it needs:

```typescript
export const bridgeDiffSideContentSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('present'),
    handle: bridgeContentHandleSchema,
    content: bridgeLoadedTextContentSchema,
  }),
  z.object({
    kind: z.literal('missing'),
    reason: z.enum(['addedFile', 'deletedFile']),
  }),
]);

export const bridgeCodeViewMaterializationRequestSchema = z.discriminatedUnion(
  'kind',
  [
    z.object({
      kind: z.literal('singleFile'),
      item: bridgeReviewItemDescriptorSchema,
      handle: bridgeContentHandleSchema,
      content: bridgeLoadedTextContentSchema,
    }),
    z.object({
      kind: z.literal('patchDiff'),
      item: bridgeReviewItemDescriptorSchema,
      diffHandle: bridgeContentHandleSchema,
      patchContent: bridgeLoadedTextContentSchema,
    }),
    z.object({
      kind: z.literal('sideBySideDiff'),
      item: bridgeReviewItemDescriptorSchema,
      base: bridgeDiffSideContentSchema,
      head: bridgeDiffSideContentSchema,
    }),
    z.object({
      kind: z.literal('placeholder'),
      item: bridgeReviewItemDescriptorSchema,
      reason: z.enum(['binary', 'large', 'missingContentRole', 'notLoaded']),
    }),
  ],
);

export type BridgeCodeViewMaterializationRequest = z.infer<
  typeof bridgeCodeViewMaterializationRequestSchema
>;
```

This keeps compile-time narrowing aligned with the runtime cases: patch diffs
cannot accidentally read side handles, added files cannot require a base side,
and placeholders cannot be sent to Pierre as if they were real `FileContents`.

### CodeView Visible-Range Signals

The hydration design wants visible-item loading, but the plan must verify the
installed CodeView API before relying on a specific signal.

Known available paths in the researched Pierre source:

- React `onScroll(scrollTop, viewer)`
- `CodeViewHandle.getInstance()`
- vanilla instance methods such as `getRenderedItems()`
- `onPostRender`/render callbacks on file and diff options

The implementation plan must choose a measured visible-item signal from the
installed package. If no stable public signal is suitable, the first slice may
hydrate selected, hovered, and guided-next items first, then add true
viewport-driven hydration after a small Pierre API spike. Do not use brittle DOM
queries as the primary source without a test that proves they survive
virtualization and item recycling.

## Content Hydration

The viewer must keep the `LUNA-337` metadata-push/content-pull model:

```text
package push
  -> projection update
  -> visible/selected item signal
  -> content queue
  -> agentstudio://resource/content/{handleId}?generation=...
  -> loaded content cache
  -> CodeView item update
```

Hydration priorities:

1. selected item
2. visible CodeView items
3. hovered tree item
4. near-visible neighbors
5. explicit prefetch for guided-review next item

The content layer should provide:

- cancellation when selection/generation changes
- stale-result discard by `reviewGeneration`, `packageId`, `itemId`, and
  handle ID
- small LRU cache for loaded text resources
- separate binary/large-file fallback state
- telemetry around queue wait, fetch duration, cache hit/miss, and stale drop

Tree browsing can show metadata without content handles. Opening a file from a
tree row must follow the handle-acquisition contract below. Do not fetch raw
paths from BridgeWeb.

### Handle Acquisition For Tree Rows

Rows that already carry a suitable `BridgeContentHandle` hydrate through the
normal content loader. Rows without a suitable handle need an explicit contract;
they must not overload top-level `BridgeReviewQuery.queryKind === 'openFile'`.
In the current foundation, `openFile` is a replacement query that returns a
single-file `BridgeReviewPackage`.

Slice 1 should first prove the package descriptors' per-role handles are enough
for package-backed review navigation. Do not add this RPC merely because it is
convenient for the UI. If implementation discovers a concrete package-backed
row class that is selectable but lacks a usable handle, add a failing fixture
for that descriptor shape before adding the RPC.

If that fixture proves `LUNA-338` needs incremental handle acquisition for
package-backed tree rows, add a source-provider-neutral
`review.resolveContentHandle` RPC:

```typescript
import { z } from 'zod';

import {
  bridgeContentHandleSchema,
  bridgeContentRoleSchema,
  bridgeReviewGenerationSchema,
} from '../../foundation/review-package';

export const bridgeContentHandleRequestSchema = z.object({
  packageId: z.string().min(1),
  reviewGeneration: bridgeReviewGenerationSchema,
  itemId: z.string().min(1),
  endpointId: z.string().min(1),
  contentRole: bridgeContentRoleSchema,
  path: z.string(),
});

export const bridgeContentHandleResponseSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('success'),
    handle: bridgeContentHandleSchema,
    itemVersion: z.number().int().nonnegative(),
  }),
  z.object({
    kind: z.literal('failure'),
    code: z.enum([
      'staleGeneration',
      'unknownItem',
      'invalidRole',
      'invalidEndpoint',
      'pathOutOfScope',
      'handleUnavailable',
    ]),
    message: z.string(),
  }),
]);

export type BridgeContentHandleRequest = z.infer<
  typeof bridgeContentHandleRequestSchema
>;
export type BridgeContentHandleResponse = z.infer<
  typeof bridgeContentHandleResponseSchema
>;
```

Swift validates every request against the active package:

- `packageId` and `reviewGeneration` match the active package.
- `itemId` exists in `itemsById`.
- `endpointId` is the package base or head endpoint.
- `contentRole` is valid for the descriptor and endpoint.
- `path` is one of the descriptor's candidate paths for that role.

Out-of-scope paths, arbitrary refs, raw filesystem paths, stale generations,
and endpoint IDs not present in the package are rejected. The response registers
a normal `BridgeContentHandle`; it does not replace the active package. The
replacement `openFile` query remains available for a separate single-file view.

Client behavior by failure code:

- `staleGeneration`: discard result, clear inflight entry, and wait for the next
  package/generation.
- `unknownItem`, `invalidEndpoint`, `invalidRole`, `pathOutOfScope`: show a
  source-unavailable placeholder for that item and emit a debug-only failure
  sample with closed reason values.
- `handleUnavailable`: keep the row selectable but render a not-loadable
  placeholder; do not retry unless the package changes or the user explicitly
  retries.

## Shiki Worker Boundary

Use Pierre's worker-pool path for Shiki highlighting. In the installed Pierre
source, the React provider is `WorkerPoolContextProvider`, and the pool is
configured through `poolOptions` and `highlighterOptions`.

Rules:

- Create the worker through an explicit factory module owned by
  `review-viewer/workers`.
- Slice 1 uses Pierre's bundled portable worker entry:
  `@pierre/diffs/worker/worker-portable.js`.
- The mergeable packaged build emits the Pierre portable worker as a static
  asset through `tsdown` and records it in the BridgeWeb app asset manifest.
- The packaged worker factory resolves that manifest entry to an
  `agentstudio://app/*` URL and constructs the worker from that URL. A dev-server
  Vite factory may exist only behind the local dev build path.
- Pass the factory to Pierre's `WorkerPoolContextProvider` through
  `poolOptions.workerFactory`.
- Serve the emitted worker asset and any subordinate assets through
  `agentstudio://app/*` with JavaScript MIME.
- Do not silently switch to `@pierre/diffs/worker/worker.js`. A later plan may
  use that entry only if packaged WKWebView proof shows the chunked module path
  works and has a better asset profile.
- If WKWebView rejects direct worker construction from `agentstudio://app/*`, a
  blob URL fallback is allowed only for the vetted packaged `worker-portable.js`
  asset loaded from
  `agentstudio://app/*`. The fallback must be documented and tested.
- Verify worker loading in WKWebView, not only in Vite dev server.
- Configure worker-owned render options once at the pool level:
  - theme
  - line diff type
  - tokenization limits
  - language preloads
  - `preferredHighlighter`
  - `useTokenTransformer` only when needed
- Do not create Shiki highlighters in React render paths.
- Sample worker stats in debug telemetry without making telemetry a hot-path
  dependency.

Packaged worker contract:

- `tsdown` must emit a deterministic app asset manifest that names the main JS,
  CSS if present, Pierre portable worker asset, and Bridge-owned worker asset if
  used.
- The manifest distinguishes `moduleWorker` and `classicWorker`. The first
  implementation may choose either, but the chosen type must match the emitted
  file and WKWebView proof.
- `BridgeSchemeHandler` serves worker assets with JavaScript MIME and no
  repository-controlled content.
- The WKWebView smoke asserts the manifest worker URL is loaded from
  `agentstudio://app/*`, the worker starts, and a real highlight completes.
- The dev-server worker path is not sufficient proof for merge.

Pierre's worker pool is owned by the React page lifecycle. In AgentStudio that
means page-local per Bridge pane because each pane has its own WKWebView and
content-world setup. The plan must prove pane isolation: tearing down one Bridge
pane must not break highlighting or follow-up item updates in another pane. Do
not add cross-pane worker-pool singletons in Swift or BridgeWeb for this slice.

## Bridge-Owned Worker RPC

Use Bridge-owned workers for expensive viewer computation that is not Shiki:
projection building, large-package filtering, facet counting, future
agent-guided scoring preparation, and other production viewer computation.
This worker lane is part of LUNA-338 because large projections are a first-slice
requirement. The implementation may keep tiny packages on the main thread only
when the same schemas, cancellation semantics, stale-result behavior, and
telemetry context are preserved. Medium and large review workloads must exercise
the worker path. The implementation plan owns the exact cutover threshold and
must test both sides of it. Benchmark fixture generation belongs in a test-only
harness or test worker excluded from the app bundle.

Worker RPC rules:

- Define request and response envelopes as Zod v4 discriminated unions.
- Derive TypeScript types with `z.infer`.
- Every request carries `requestId`, `packageId`, `reviewGeneration`, `method`,
  `createdAtMilliseconds`, a projection request, visible item IDs, and an
  optional `abortKey`.
- Every success response carries `method` and a method-specific result schema.
  Do not use `z.unknown()` at the worker boundary.
- Every failure response carries `method`, `requestId`, `code`, and `message`.
- Error payloads are source-scrubbed; no raw path, file body, prompt, or patch
  text leaves the worker through telemetry or generic error messages.
- Parse requests before posting to the worker. Parse responses before applying
  them to Zustand/controller state. Parse again at the worker entrypoint before
  executing a request so tests can catch both caller and callee drift.
- The main thread owns cancellation and stale-result discard. Worker completion
  is not authority if the package or generation changed.
- Worker results should be plain structured-clone-safe data: ordered item IDs,
  ordered paths, facet counts, and maps. The UI thread may call Pierre
  `preparePresortedFileTreeInput(...)` after receiving ordered paths unless the
  implementation plan proves `FileTreePreparedInput` can be safely transferred
  without relying on package internals.
- Pierre's current `PathStore` internals appear clone-tolerant for structurally
  valid prepared input, but that is not an explicit public API guarantee. Treat
  worker-prepared `FileTreePreparedInput` as an optimization that requires
  AgentStudio regression proof, not the default architecture.
- Worker request queue wait, execution time, result size class, cancellation,
  and stale drops are debug telemetry samples.

Illustrative schema shape:

```typescript
import { z } from 'zod';

import { bridgeReviewGenerationSchema } from '../../foundation/review-package';
import {
  bridgeReviewProjectionRequestSchema,
  bridgeReviewProjectionResultSchema,
} from '../navigation/projection-schema';

export const bridgeProjectionWorkerResultSchema = z.object({
  request: bridgeReviewProjectionRequestSchema,
  projection: bridgeReviewProjectionResultSchema.pick({
    projectionId: true,
    label: true,
    orderedItemIds: true,
    orderedPaths: true,
    primaryItemIdByTreePath: true,
    secondaryItemIdsByTreePath: true,
    facetCounts: true,
  }),
});

export const bridgeViewerWorkerRequestSchema = z.discriminatedUnion('method', [
  z.object({
    method: z.literal('buildProjection'),
    requestId: z.string().min(1),
    packageId: z.string().min(1),
    reviewGeneration: bridgeReviewGenerationSchema,
    createdAtMilliseconds: z.number().nonnegative(),
    abortKey: z.string().min(1).optional(),
    request: bridgeReviewProjectionRequestSchema,
    visibleItemIds: z.array(z.string().min(1)).readonly(),
  }),
]);

export const bridgeViewerWorkerSuccessResponseSchema = z.object({
  kind: z.literal('success'),
  method: z.literal('buildProjection'),
  requestId: z.string().min(1),
  result: bridgeProjectionWorkerResultSchema,
});

export const bridgeViewerWorkerFailureResponseSchema = z.object({
  kind: z.literal('failure'),
  method: z.enum(['buildProjection']),
  requestId: z.string().min(1),
  code: z.enum(['cancelled', 'stale', 'invalidRequest', 'internal']),
  message: z.string(),
});

export const bridgeViewerWorkerResponseSchema = z.discriminatedUnion('kind', [
  bridgeViewerWorkerSuccessResponseSchema,
  bridgeViewerWorkerFailureResponseSchema,
]);

export type BridgeProjectionWorkerResult = z.infer<
  typeof bridgeProjectionWorkerResultSchema
>;
export type BridgeViewerWorkerRequest = z.infer<
  typeof bridgeViewerWorkerRequestSchema
>;
export type BridgeViewerWorkerResponse = z.infer<
  typeof bridgeViewerWorkerResponseSchema
>;
```

Test-only fixture builders may reuse the request/result schemas, but they are
not production worker methods. Keep them under BridgeWeb test support or Swift
test support and prove the packaged app manifest does not include those entries.

Do not use this looser shape:

```typescript
z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('success'),
    requestId: z.string().min(1),
    result: z.unknown(),
  }),
]);
```

## Markdown And Plan Files

Opening docs and plan files is a first-class viewer use case. The current
milestone must support selecting markdown files from the tree and rendering
their contents read-only.

Initial policy:

- Slice 1 renders markdown as source text through Pierre `File`/CodeView.
- Rich markdown preview is a follow-up unless the implementation plan names a
  sanitizer/renderer, URL policy, and negative security proof before coding.
- A future rich renderer must be read-only, strip raw HTML, block scripts,
  disable inline images unless allowlisted, and treat `http`/`https` links as
  external click-outs only.
- Rich rendering must reject `file:`, `data:`, `blob:`, `javascript:`, and
  custom-scheme subresources from markdown content.
- Markdown rendering belongs in `review-viewer/markdown`, not in content
  loading or source-provider contracts.
- Plan/docs-focused projections should be available even before annotations
  are implemented.

## Swift Boundary

Swift should stay renderer-agnostic. It owns source access, endpoint
resolution, package building, content handles, and WebKit delivery. It does not
own Trees prepared-input shapes or Pierre `CodeViewItem` objects.

Swift changes should be limited to metadata that BridgeWeb cannot derive
without duplicating source-provider knowledge:

- stable ordering
- file class
- review priority
- language/MIME hints
- content hashes
- endpoint identity
- content handle registration

If the viewer needs working-tree or index tree browsing, that belongs behind
`BridgeReviewSourceProvider.readTree(...)`. The viewer must not call the Git
client directly or branch on backend implementation details.

## Observability

Extend the debug-only Bridge telemetry taxonomy for real viewer work. Do not
emit placeholder spans for features that are not mounted.

Browser-side viewer measurements originate in BridgeWeb with the `.web` scope,
then flow through the existing Swift telemetry batch/RPC path into the debug
OTLP exporter. BridgeWeb must not add a direct OTLP exporter or send telemetry
to Victoria itself.

Required slices:

- `performance.bridge.trees.projection_build`
- `performance.bridge.trees.prepare_input`
- `performance.bridge.trees.mode_switch`
- `performance.bridge.trees.search_filter`
- `performance.bridge.viewer.content_queue`
- `performance.bridge.viewer.content_cache`
- `performance.bridge.pierre.item_update`
- `performance.bridge.pierre.scroll_target`
- `performance.bridge.pierre.virtualized_range`
- `performance.bridge.shiki.highlight`
- `performance.bridge.worker.task`

Each sample must remain low-cardinality and source-scrubbed. No raw paths,
content, prompts, errors, or file bodies may be exported through OTLP.

The Swift telemetry validator is an allowlist. Any new BridgeWeb event names,
attribute keys, or attribute values must be added to the validator in the same
implementation slice as the emitter. The plan must include unit tests for
accepted events and rejected high-cardinality variants.

Viewer telemetry is debug-only. It must be fail-open and must not block package
application, content fetches, worker tasks, scroll handling, or CodeView item
updates.

Metrics must carry scale attributes, never raw identifiers:

- `fixture_class`: `tiny`, `small_real_tree`, `medium_review`, `large_tree`,
  `large_diff`, `ceiling_parse`
- `item_count_bucket`: bounded buckets such as `0_100`, `101_500`,
  `501_1000`, `1001_10000`, `10001_plus`
- `tree_path_count_bucket`
- `diff_row_count_bucket`
- `content_bytes_bucket`
- `projection_kind`
- `worker_lane`: `pierre_shiki` or `bridge_projection`
- `result`: `success`, `cancelled`, `stale`, `failure`

Required measured values include:

- package apply duration
- first viewer render duration
- projection build duration
- tree prepared-input duration
- projection mode switch duration
- search/filter duration
- content queue wait duration
- content fetch duration
- content cache hit/miss count
- CodeView item update duration
- worker queue wait and execution duration
- rendered item/window count when a public signal exists
- deterministic scroll proof fields for benchmark runs: `scrollTop`,
  `targetScrollTop`, `steps`, and `positionChecksum`

## Security Context

This milestone touches untrusted repository content, WebKit, custom URL
schemes, workers, markdown rendering, and syntax highlighting. The trust
boundary is security-sensitive.

Assets and privileges:

- source file content and diffs from a local repository
- review package metadata, endpoint identities, content hashes, and handles
- WebKit page-world and bridge-world JavaScript
- packaged BridgeWeb assets and worker scripts
- debug-only telemetry emitted to the local OTLP/Victoria stack

Entry points:

- Swift package and delta pushes into BridgeWeb
- BridgeWeb RPC commands into Swift
- `agentstudio://resource/content/*` content fetches
- `agentstudio://app/*` app and worker asset loads
- markdown rendering
- token, line, tree selection, search, and hover handlers
- worker messages between BridgeWeb and Pierre workers

Untrusted inputs:

- repository paths, file names, extensions, languages, MIME hints, and content
- patch text and generated diff metadata
- markdown contents and links
- user-visible labels from source-provider metadata
- browser-originated telemetry samples

Trust boundaries:

- Swift validates handles, generations, routes, and resource scope.
- BridgeWeb treats package metadata as display data, not authority.
- Workers receive only the file/diff text needed for highlighting.
- Telemetry exports summaries only, never content or raw paths.
- Markdown rich rendering, if introduced, must use a sanitizer and a blocked
  remote-resource policy.
- A compromised page-world script is not trusted to authorize source reads.
  Swift-side package, generation, endpoint, item, role, path, and handle
  validation remains mandatory for every privileged request.

Rules:

- BridgeWeb fetches only Swift-issued content handle URLs.
- Swift validates route, host, handle, generation, and resource scope.
- BridgeWeb handle-resolution RPCs, if added, can resolve only active-package
  items, active-package endpoints, and descriptor candidate paths.
- Swift rejects out-of-scope `openFile`, `readTree`, or handle-resolution
  requests that name raw filesystem paths, arbitrary refs, stale generations,
  unknown endpoint IDs, or paths not present in the active package descriptor.
- Worker scripts load only from packaged BridgeWeb app assets.
- Service workers are not allowed in the BridgeWeb pane.
- `blob:` URLs are allowed only for a vetted packaged worker fallback. They are
  not allowed for repository markdown, user content, or telemetry payloads.
- Markdown rich rendering, if added, must sanitize output, strip raw HTML, and
  reject blocked URL schemes and remote subresources.
- No remote URLs from markdown or code tokens load inside the pane by default.
- Token hooks should not expose raw source content to telemetry.
- Browser-originated viewer telemetry must use closed event names, closed
  attribute keys, and bounded value vocabularies accepted by the Swift
  validator. There is no generic telemetry pass-through.
- No source mutation commands belong to this viewer.

Security non-goals:

- This viewer does not sandbox hostile repository code execution because it
  never executes repository code.
- This viewer does not protect against a compromised app binary.
- This viewer does not make the bridge nonce a secret against arbitrary
  same-page script execution; the trust model remains WebKit content-world
  isolation plus Swift-side validation.

## Non-Goals

- Monaco or any source editor buffer.
- Patch apply, approve/reject, or accept-agent-change UI.
- Durable annotation/comment body schema.
- Markdown editing.
- Backend selection between Git implementations.
- Replacing the Bridge review package contracts with Pierre-specific DTOs.
- Sending full file contents in package pushes or deltas.

## Fixture And Performance Strategy

Use a fixture ladder instead of one heroic mega-diff. Correctness fixtures run
in CI; noisy browser trace benchmarks are explicit performance gates and should
not be confused with deterministic unit proof.

Fixture classes:

- `tiny`: 8-12 files and one selected content fetch. Smoke existing Bridge path
  in CI.
- `small_real_tree`: Pierre snapshot scale, about 600 paths. Proves normal repo
  navigation in CI.
- `medium_review`: 250-1,000 changed files with source, test, docs, generated,
  large, and binary mix. Proves projections, filters, selection, and no eager
  bytes in CI.
- `large_tree`: Linux 1x/5x-style path breadth, about 90k/450k paths. Proves
  tree prep and virtualized navigation in benchmark or targeted CI if fast.
- `large_diff`: 100k-row generated diff package with an 8k-line materialization
  sample in the deterministic Node benchmark. Proves deep CodeView projection,
  sampled materialization, and scroll-trace geometry without claiming full
  100k-line body hydration.
- `ceiling_parse`: AOSP-style 1M+ paths. Manual upper-bound stress only.

Real reference cases:

- DiffsHub demo class: `ghostty-org/ghostty#12291` is roughly 25 files and
  97k changed lines in the screenshot evidence. Use this scale as a user-facing
  sanity target.
- DiffsHub large route class: `nodejs/node#59805` and `oven-sh/bun#30412` are
  useful public examples for large sidebar search/status behavior.
- Linux compare class: useful for path/tree breadth and scroll ceiling, not a
  default CI gate.

These public examples are scale and interaction references only. Canonical
proof uses repo-local deterministic fixtures and generated workloads, not live
GitHub responses or checked-in public patch snapshots.

Local worktree rehearsal:

- BridgeWeb may provide a dev-only Vite data provider that points at an
  allowlisted local repo/worktree for high-realism iteration.
- This lane exists to reproduce real AgentStudio branch scale quickly without
  rebuilding Swift or launching the native app for every CSS/interaction
  change.
- It must not become a production data path and must not weaken deterministic
  fixture proof. CI correctness still uses generated repo-local fixtures and
  typed mocked Bridge backends.
- The provider returns Bridge-shaped metadata packages, deltas, ordering,
  statuses, file classes, tree paths, content handles, and bounded diagnostics.
  It must not put full source/diff/markdown bodies in package pushes.
- Content is fetched lazily through content handles from a Vite/Node endpoint
  that enforces the allowlisted worktree root and bounded response sizes.
- Browser URLs should select a named source or scenario; raw local paths belong
  in local configuration or environment variables, not shareable app URLs.
- The same zod schemas, discriminated unions, Zustand reference discipline,
  worker lanes, and telemetry fields used by the mocked backend and packaged
  app path apply to this provider.
- Required dev proof includes one large real-worktree scenario that can select
  files, scroll CodeView, show added-file full content, render docs/plans
  markdown, collapse/expand file headers, switch filters, and report worker
  readiness.

Fixture construction rules:

- Store compact deterministic builders and small JSON fixtures in the repo.
- Do not check in public GitHub patch snapshots unless size, license, and
  freshness are explicitly approved.
- Prefer generated BridgeReviewPackage fixtures with deterministic paths,
  classes, change kinds, line counts, handles, and content byte sizes.
- Content bodies are fetched through the same content-resource loader as product
  code; the package fixture itself remains metadata-only.
- Large fixture builders should live under BridgeWeb test support or Swift test
  support, not in product runtime modules.
- Keep a small visual-debug fixture with a balanced file/diff mix and only a few
  added-only files. It exists for manual WebKit review of the shell and should
  not be confused with the large benchmark workloads.
- Added/deleted/new-file materialization requires a focused follow-up after the
  visual shell is usable: content visibility may use a single-file fallback
  temporarily, but diff review semantics must be proven with Pierre-compatible
  diff items before claiming full CodeView materialization coverage.

Required workload variants:

- append-only package delta: proves same-projection `model.batch(...)` path and
  CodeView `addItems(...)` behavior.
- reorder/filter projection switch: proves `resetPaths(...)` with prepared input
  and selection retention/drop rules.
- rename and duplicate-display-path package: proves primary/secondary tree path
  maps, row aggregation, and annotation/content-role targeting.
- partial patch plus full-content mixed package: proves `diff`, `base/head`, and
  `file` materialization paths.
- binary and large placeholders: proves no eager content fetch and correct
  placeholder UI.
- cold worker startup and warm worker pool: separates first highlight cost from
  steady-state scroll/filter behavior.
- repo-scale case above 500 items: proves the 100/500-item unit targets are not
  the only evidence for large packages.

Initial canonical benchmark workloads:

- `bridge_viewer_medium_review_v1`: required CI/integration workload once the
  projection store exists. It contains 1,000 changed items with deterministic
  source, test, docs, generated, binary, large, renamed, deleted, and duplicate
  display-path cases. It proves metadata-only package ingest, all/changed/docs/
  tests/source/guided projections, Git-status and file-class refinements,
  search, selection retention/drop rules, no eager body fetch, and bounded
  Zustand subscriptions.
- `bridge_viewer_large_tree_v1`: targeted benchmark workload once Trees is
  mounted. It contains about 90k paths, deterministic folder breadth/depth, Git
  status distribution, docs/plan density, and generated/vendor regions. It
  proves `preparePresortedFileTreeInput(...)`, search/filter response, row
  mounting bounds, status decoration, and projection reset behavior.
- `bridge_viewer_large_diff_scroll_v1`: targeted benchmark workload once
  packaged CodeView is mounted. It represents 100k virtualized diff rows across
  a fixed mixed file set, materializes an 8k-line selected-content sample, uses
  a 1440x1000 viewport, performs one warmup plus three kept scroll traces, and
  records a deterministic scroll checksum.

The first implementation plan may keep the large tree and large diff workloads
as benchmark/manual gates until the corresponding UI surface exists. It may not
claim viewer performance proof without either running the relevant workload or
stating that the surface is not wired yet.

Benchmark proof should borrow Pierre's DiffsHub runbook shape:

- fixed workload route or debug WebKit scenario
- fixed viewport
- stable-page checks before tracing
- one warmup and at least three kept runs
- deterministic real scroll writes against the CodeView scroller
- matching `scrollTop`, `targetScrollTop`, `steps`, and `positionChecksum`
- trace buckets for style/layout/paint/composite/task/frame costs
- raw per-run metrics plus averages/medians
- normalized `metric_ms_per_million_px` when scroll distances differ
- explicit dropped-trace and machine-state notes

CI-safe proof should assert bounded behavior rather than fragile wall-clock
microbenchmarks where possible:

- metadata package push does not include file bodies
- first selected item fetches content exactly once
- projection switching does not fetch content by itself
- search/status/facet changes do not request a new package
- visible/selected/hover/neighbor hydration priority is stable
- stale worker/content results are dropped after package or generation change
- mounted tree rows stay bounded to visible slice plus overscan
- CodeView item updates bump item `version`
- worker stats and viewer metrics appear only in debug telemetry paths

## Proof Expectations

Implementation planning must include at least these gates:

- Unit: projection builders produce all/changed/guided/docs/tests/source views
  from the same package.
- Unit: projection builders create display-path, candidate-path, item-id, and
  available-role maps, including rename and duplicate-display-path cases.
- Unit: Trees adapter uses prepared or presorted input outside React render.
- Unit: CodeView adapter creates stable file and diff items, preserves
  `itemId`, and bumps `version` for content/collapse/annotation changes.
- Unit: hydration queue prioritizes selected/visible/hover/neighbor requests.
- Unit: stale content results are discarded on generation/package/item/handle
  mismatch.
- Unit: worker-pool setup uses documented Pierre provider/options and reports
  usable debug stats.
- Unit: Bridge-owned worker RPC schemas accept valid projection requests and
  reject malformed/stale/failure envelopes.
- Unit: Bridge-owned Zod schemas follow the `xxxSchema` value and `Xxx` type
  naming rule, and no hand-written duplicate type shadows an owned schema.
- Unit: architecture boundary checks reject Swift calls, worker posts, Pierre
  model mutations, telemetry emits, and raw body storage from
  `review-viewer/state`.
- Unit: architecture boundary checks reject `@pierre/trees` runtime imports
  outside `review-viewer/trees` and CodeView runtime imports outside
  `review-viewer/code-view` or `review-viewer/workers/pierre`.
- Unit: Zustand selectors stay narrow enough that worker-stat, content-cache,
  and hydration-queue updates do not rerender the root shell.
- Unit: tree controls apply projection/search/Git-status/facet state without
  requesting a new package or fetching content.
- Unit: telemetry validator accepts the new low-cardinality viewer event names
  and rejects unknown or high-cardinality event names/attributes.
- Unit: Bridge IPC method definitions and DTOs expose only semantic `bridge.*`
  methods with typed params/results and closed privilege/data scopes.
- Unit: Bridge IPC target resolution accepts Bridge panes and rejects terminal,
  webview, missing, or unsupported targets with typed errors.
- Unit: Bridge IPC registry/routing tests prove generic WebKit/raw-post,
  EventBus command, and `zmx.*` methods are absent.
- Unit: dependency/export smoke imports the installed Pierre package entry
  points used by BridgeWeb.
- Unit: out-of-scope handle-resolution, `openFile`, and `readTree` requests
  are rejected when they name stale generations, unknown endpoints, arbitrary
  refs, or paths outside the active package descriptor.
- Unit: markdown rich-preview sanitizer policy rejects raw HTML and blocked URL
  schemes, if rich preview is included. If slice 1 keeps source-text markdown,
  this proof is explicitly deferred with the feature.
- Integration: BridgeWeb package push renders tree mode controls and a
  selectable file tree without content bytes in the push payload.
- Integration: selecting a file fetches content through
  `agentstudio://resource/content/{handleId}?generation=...`.
- Integration: medium review fixture supports all/changed/guided/docs/tests/
  source projection switches, tree search, Git-status menu, and file-class or
  extension facets with no eager content fetch.
- Integration: CodeView renders a mixed file/diff package with worker-backed
  Shiki highlighting.
- Integration: markdown plan/docs file can be opened read-only from the tree.
- Integration: CodeView adapter materializes diff items from `diff` handles and
  from `base`/`head` handles, including added and deleted files.
- Integration: large-tree fixture builds projection and Trees model without
  storing raw file bodies in Zustand.
- Integration: large-diff fixture can select, scroll to, collapse, expand, and
  update a deep diff item without losing selection or using pixel offsets.
- Integration: multiple mounted Bridge panes keep their page-local Pierre worker
  pools isolated; tearing down one pane does not affect another pane.
- Integration: unmount one of two mounted Bridge panes, then verify the
  remaining pane still completes a worker-backed highlight and survives a
  follow-up CodeView item update.
- Integration: Bridge IPC can resolve a Bridge pane, read package metadata,
  select a file, and fetch selected content through a Bridge content handle
  without raw paths.
- Integration: pane-bound IPC principals can access their own Bridge pane but
  cannot read another pane's Bridge content without an explicit grant.
- Integration: Bridge IPC events are emitted after Bridge-owned state changes
  and are not used as command routing.
- WKWebView smoke: packaged app JS, CSS, and worker chunks load from
  `agentstudio://app/*`.
- WKWebView smoke: selected worker factory path creates a worker and completes
  a real highlight task inside the packaged macOS pane.
- IPC e2e smoke: a debug IPC client can create or target a Bridge pane,
  refresh/load a review package, list files, select a file, fetch selected
  content, observe Bridge events, and prove command-bar UI was not opened.
- Observability proof: viewer metrics appear through the existing debug OTLP
  path with trace correlation across package push, content fetch, and worker
  highlight.
- Benchmark proof: optional/manual trace workload follows the fixed viewport,
  warmup, three-kept-run, scroll-checksum, and raw-metric reporting policy.
- Size proof: BridgeWeb build output records the bundle and worker asset size
  delta introduced by Pierre dependencies.
- License proof: installed Pierre package licenses are compatible with the app.

Required command-level gates for the implementation plan:

- `mise run bridge-web-check`
- architecture boundary check through BridgeWeb's lint/check command, with the
  implementation plan owning whether this is custom Oxlint, a local AST checker,
  or a combination
- `mise run bridge-web-test`
- `mise run bridge-web-build`
- `mise run test -- --filter Bridge`
- a named Bridge viewer benchmark command added by the implementation plan,
  such as `mise run bridge-viewer-benchmark`; it must emit large-tree and
  large-diff benchmark artifacts before the implementation goal closes
- `mise run test-webkit`
- `mise run lint`
- `mise run observability:up`
- `mise run run-debug-observability -- --detach`
- `mise run verify-bridge-observability`

The Bridge observability verifier must be extended in the same slice to require
viewer-specific debug signals. A passing viewer proof includes at least:

- `performance.bridge.trees.projection_build`
- `performance.bridge.viewer.content_queue`
- `performance.bridge.shiki.highlight`
- `performance.bridge.worker.task`

Initial performance targets:

These numbers are benchmark targets on a named local/debug harness, not fragile
CI pass/fail gates until the benchmark route, machine-state capture, and
variance policy are standardized. CI gates should assert structural behavior:
bounded rows, no eager content, stale drops, deterministic ordering, and correct
queue priority. Benchmark artifacts record whether these targets were met.

- Build projection and prepared tree input for a 100-item package in under
  100ms.
- Build projection and local filters for a medium-review fixture in under 100ms
  after the package is in memory.
- Select and fetch one visible text file from the content resource stream in
  under 200ms on the local debug fixture.
- Keep projection mode switches and search/filter for a 500-item prepared tree
  under 100ms after the package is in memory.
- Large-tree and large-diff benchmark targets must be reported as measured
  baselines in the first implementation PR. Do not invent hard pass/fail numbers
  before the packaged WKWebView route exists.
- Content queue orders selected, visible, hover, and neighbor requests in that
  priority order.
- Content queue cancels requests when a file leaves the active viewport or the
  review generation changes.
- Loaded content cache has an explicit LRU capacity and clears package-scoped
  entries when `packageId` or `reviewGeneration` changes.

## Closed Decisions For Plan Creation

- Dependency source: use published or prebuilt Pierre package artifacts pinned
  in BridgeWeb lockfiles. The local Pierre repo is reference-only.
- CodeView ownership: production uses uncontrolled/imperative CodeView from
  the first slice. Controlled mode is test-only.
- Markdown: source-text rendering only in slice 1. Rich preview is a follow-up
  unless separately approved with sanitizer and security proof.
- Tree browse: package-backed Trees only in slice 1. General endpoint tree
  browse through `BridgeReviewSourceProvider.readTree(...)` is a follow-up UI
  surface.
- Worker entrypoint: use `@pierre/diffs/worker/worker-portable.js` first, with
  packaged WKWebView proof for the emitted worker asset.
