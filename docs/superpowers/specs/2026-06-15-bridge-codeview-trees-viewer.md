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

That means `LUNA-338` is not a cosmetic swap of one component. It must add the
viewer ownership layers that sit between the review package and Pierre's
imperative rendering APIs.

## Package Dependency Boundary

BridgeWeb must add Pierre as explicit BridgeWeb dependencies, not as transitive
or vendored assumptions. The researched local Pierre source reports:

- `@pierre/diffs` version `1.2.10`, license `apache-2.0`
- `@pierre/trees` version `1.0.0-beta.4`, license `apache-2.0`

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
- final BridgeWeb bundle size impact
- worker asset output shape after `vite build`
- WKWebView loading from the packaged `agentstudio://app/*` origin

Do not shape Bridge contracts around package-private Pierre internals. Use
documented exports only.

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
    navigation/
    content/
    code-view/
    trees/
    workers/
    markdown/
    shell/
```

Responsibilities:

- `foundation/review-package`: wire contracts, package/delta registry, and
  base package visibility from `filterState`. It must not import Pierre
  packages.
- `review-viewer/navigation`: builds file-tree projections, facets, filtered
  views, and path-to-item maps from the review package registry's
  `visibleItems`. It must not reimplement `filterState` visibility.
- `review-viewer/trees`: owns `@pierre/trees` model creation, prepared input,
  search, selection, focus, and row decoration.
- `review-viewer/content`: owns selected, visible, hover, and neighbor content
  hydration state. It talks to `foundation/content`.
- `review-viewer/code-view`: converts descriptors plus loaded content into
  Pierre `CodeViewItem` records and owns CodeView item updates.
- `review-viewer/workers`: owns Pierre worker-pool creation, render options,
  worker stats sampling, and failure fallback.
- `review-viewer/markdown`: owns read-only markdown file rendering decisions.
  It must not live in `foundation/content`.
- `review-viewer/shell`: composes navigation, toolbar mode controls, Trees,
  CodeView, and markdown/file panels.

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

Add a BridgeWeb-local projection model. This is not a Swift wire contract and
must not be serialized into `BridgeReviewPackage` unless a later plan proves a
backend-owned field is necessary.

```typescript
type BridgeReviewProjectionKind =
  | 'allFiles'
  | 'changedFiles'
  | 'guidedReview'
  | 'currentChangeSet'
  | 'docsAndPlans'
  | 'tests'
  | 'source'
  | 'folder'
  | 'extension'
  | 'fileClass'
  | 'custom';

interface BridgeReviewProjection {
  readonly projectionId: string;
  readonly kind: BridgeReviewProjectionKind;
  readonly label: string;
  readonly orderedItemIds: readonly string[];
  readonly orderedPaths: readonly string[];
  readonly primaryDisplayPathByItemId: Readonly<Record<string, string>>;
  readonly candidatePathsByItemId: Readonly<Record<string, readonly string[]>>;
  readonly itemIdsByDisplayPath: Readonly<Record<string, readonly string[]>>;
  readonly availableContentRolesByItemId: Readonly<
    Record<string, readonly BridgeContentRole[]>
  >;
  readonly facetCounts: BridgeReviewFacetCounts;
}

interface BridgeReviewFacetCounts {
  readonly fileClasses: Readonly<Record<string, number>>;
  readonly extensions: Readonly<Record<string, number>>;
  readonly changeKinds: Readonly<Record<string, number>>;
  readonly reviewStates: Readonly<Record<string, number>>;
  readonly hidden: number;
  readonly binary: number;
  readonly large: number;
}
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
- folder, extension, and file-class projections are local refinements over
  `visibleItems`; they do not mutate the package filter.

The projection layer must tolerate many-to-one and one-to-many path
relationships. A display path can map to multiple review items, and a single
review item can have base and head paths. The default display path remains
`headPath`, falling back to `basePath`, then `itemId`, but the candidate-path
map must retain both sides for renamed files, deleted files, and annotations.

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

## Trees Integration

Use `@pierre/trees` and `@pierre/trees/react` as a stable imperative tree model.
`useFileTree(...)` creates the model once. Later changes should use model
methods such as `resetPaths(...)`, search, focus, and selection methods.

Rules:

- Use prepared input for repo-scale trees.
- Prefer `preparePresortedFileTreeInput(...)` when Swift or the projection
  layer owns final order.
- Give the tree host a real CSS height.
- Use density and overscan intentionally, not custom virtualization.
- Keep path selection and CodeView item selection synchronized through the
  projection maps.
- Do not hand-roll `FileTreePreparedInput`; it is an opaque Pierre type.

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

## CodeView Integration

Use `@pierre/diffs/react` `CodeView` as the main code surface for mixed file
and diff scroll regions.

Pierre `CodeViewItem` records map from Bridge items:

```typescript
type BridgeCodeViewItem =
  | {
      readonly id: string;
      readonly type: 'file';
      readonly file: FileContents;
      readonly version: number;
      readonly collapsed: boolean;
    }
  | {
      readonly id: string;
      readonly type: 'diff';
      readonly fileDiff: FileDiffMetadata;
      readonly version: number;
      readonly collapsed: boolean;
    };
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

Prefer imperative CodeView ownership for large or streaming review surfaces:
seed with `initialItems`, then use the ref APIs (`addItems`, `updateItem`,
`getItem`, `scrollTo`). Controlled `items` mode is acceptable for tests and
small packages, but the production viewer should not route every item update
through a full React item array.

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

If `LUNA-338` needs incremental handle acquisition for package-backed tree
rows, add a source-provider-neutral `review.resolveContentHandle` RPC:

```typescript
interface BridgeContentHandleRequest {
  readonly packageId: string;
  readonly reviewGeneration: BridgeReviewGeneration;
  readonly itemId: string;
  readonly endpointId: string;
  readonly contentRole: BridgeContentRole;
  readonly path: string;
}

interface BridgeContentHandleResponse {
  readonly handle: BridgeContentHandle;
  readonly itemVersion: number;
}
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

## Shiki Worker Boundary

Use Pierre's worker-pool path for Shiki highlighting. In the installed Pierre
source, the React provider is `WorkerPoolContextProvider`, and the pool is
configured through `poolOptions` and `highlighterOptions`.

Rules:

- Create the worker through an explicit factory module owned by
  `review-viewer/workers`.
- Slice 1 uses Pierre's bundled portable worker entry:
  `@pierre/diffs/worker/worker-portable.js`.
- Create the worker URL through Vite worker URL bundling, for example:
  `import WorkerUrl from '@pierre/diffs/worker/worker-portable.js?worker&url'`,
  then `new Worker(WorkerUrl, { type: 'module' })` if the emitted asset is a
  module worker.
- Pass the factory to Pierre's `WorkerPoolContextProvider` through
  `poolOptions.workerFactory`.
- Serve the emitted worker asset and any subordinate assets through
  `agentstudio://app/*` with JavaScript MIME.
- Do not silently switch to `@pierre/diffs/worker/worker.js`. A later plan may
  use that entry only if packaged WKWebView proof shows the chunked module path
  works and has a better asset profile.
- If WKWebView rejects Vite's worker URL, a blob URL fallback is allowed only
  for the vetted packaged `worker-portable.js` asset loaded from
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

Pierre's worker pool is currently a shared singleton with reference-counted
teardown. That improves reuse and cache behavior, but it weakens strict
per-pane isolation. The first implementation can use the documented provider,
but the plan must include proof that one pane unmount does not terminate a pool
still needed by another mounted pane.

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
- Unit: telemetry validator accepts the new low-cardinality viewer event names
  and rejects unknown or high-cardinality event names/attributes.
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
- Integration: CodeView renders a mixed file/diff package with worker-backed
  Shiki highlighting.
- Integration: markdown plan/docs file can be opened read-only from the tree.
- Integration: CodeView adapter materializes diff items from `diff` handles and
  from `base`/`head` handles, including added and deleted files.
- Integration: multiple mounted Bridge panes do not terminate Pierre's shared
  worker pool while another pane still needs it.
- Integration: unmount one of two mounted Bridge panes, then verify the
  remaining pane still completes a worker-backed highlight and survives a
  follow-up CodeView item update.
- WKWebView smoke: packaged app JS, CSS, and worker chunks load from
  `agentstudio://app/*`.
- WKWebView smoke: selected worker factory path creates a worker and completes
  a real highlight task inside the packaged macOS pane.
- Observability proof: viewer metrics appear through the existing debug OTLP
  path with trace correlation across package push, content fetch, and worker
  highlight.
- Size proof: BridgeWeb build output records the bundle and worker asset size
  delta introduced by Pierre dependencies.
- License proof: installed Pierre package licenses are compatible with the app.

Required command-level gates for the implementation plan:

- `mise run bridge-web-check`
- `mise run bridge-web-test`
- `mise run bridge-web-build`
- `mise run test -- --filter Bridge`
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

Performance budgets for the initial proof:

- Build projection and prepared tree input for a 100-item package in under
  100ms.
- Select and fetch one visible text file from the content resource stream in
  under 200ms on the local debug fixture.
- Keep projection mode switches and search/filter for a 500-item prepared tree
  under 100ms after the package is in memory.
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
