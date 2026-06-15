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

- `foundation/review-package`: wire contracts and package/delta registry only.
  It must not import Pierre packages.
- `review-viewer/navigation`: builds file-tree projections, facets, filtered
  views, and path-to-item maps from `BridgeReviewPackage`.
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

Add a BridgeWeb projection model:

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
  readonly itemIdByPath: Readonly<Record<string, string>>;
  readonly pathByItemId: Readonly<Record<string, string>>;
  readonly facetCounts: BridgeReviewFacetCounts;
}
```

Swift can own canonical ordering and review-priority metadata. BridgeWeb owns
projection switching, local filters, and the path/item maps used by Trees and
CodeView. For large packages, BridgeWeb should avoid sorting in React render.
If Swift already provided final order, BridgeWeb should call
`preparePresortedFileTreeInput(orderedPaths)` outside render and pass the
prepared input to the Trees model.

Projection mode switches should reuse existing package data. They should not
trigger content fetches by themselves. Content fetches happen only when a file
or diff becomes selected, visible, hovered, or near-visible according to the
hydration policy.

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
tree row should either use an existing handle or issue an `openFile` query to
obtain a file handle. Do not fetch raw paths from BridgeWeb.

## Shiki Worker Boundary

Use Pierre's worker-pool path for Shiki highlighting. In the installed Pierre
source, the React provider is `WorkerPoolContextProvider`, and the pool is
configured through `poolOptions` and `highlighterOptions`.

Rules:

- Create the worker through Vite's documented worker bundling path.
- Serve built worker chunks through `agentstudio://app/*` with JavaScript MIME.
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

- Markdown files may render as source text through Pierre `File`/CodeView if a
  safe rich renderer is not introduced in this ticket.
- A rich markdown renderer is allowed only if it is read-only, sanitized, and
  does not execute raw HTML, scripts, or remote resource loads by default.
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

## Security Context

This milestone touches untrusted repository content, WebKit, custom URL
schemes, workers, markdown rendering, and syntax highlighting. The trust
boundary is security-sensitive.

Rules:

- BridgeWeb fetches only Swift-issued content handle URLs.
- Swift validates route, host, handle, generation, and resource scope.
- Worker scripts load only from packaged BridgeWeb app assets.
- Markdown rich rendering, if added, must sanitize output and avoid raw HTML.
- No remote URLs from markdown or code tokens should load inside the pane by
  default.
- Token hooks should not expose raw source content to telemetry.
- No source mutation commands belong to this viewer.

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
- Unit: projection builders create path-to-item and item-to-path maps,
  including rename cases.
- Unit: Trees adapter uses prepared or presorted input outside React render.
- Unit: CodeView adapter creates stable file and diff items, preserves
  `itemId`, and bumps `version` for content/collapse/annotation changes.
- Unit: hydration queue prioritizes selected/visible/hover/neighbor requests.
- Unit: stale content results are discarded on generation/package/item/handle
  mismatch.
- Unit: worker-pool setup uses documented Pierre provider/options and reports
  usable debug stats.
- Integration: BridgeWeb package push renders tree mode controls and a
  selectable file tree without content bytes in the push payload.
- Integration: selecting a file fetches content through
  `agentstudio://resource/content/{handleId}?generation=...`.
- Integration: CodeView renders a mixed file/diff package with worker-backed
  Shiki highlighting.
- Integration: markdown plan/docs file can be opened read-only from the tree.
- WKWebView smoke: packaged app JS, CSS, and worker chunks load from
  `agentstudio://app/*`.
- Observability proof: viewer metrics appear through the existing debug OTLP
  path with trace correlation across package push, content fetch, and worker
  highlight.

## Open Decisions Before Plan Creation

1. Should the first implementation use CodeView imperative mode in production
   from the start, or controlled mode for a smaller first slice with a planned
   hard cutover?

   Recommended answer: imperative mode for production, controlled mode only in
   small unit tests. Pierre's own docs recommend imperative ownership for very
   large or streaming surfaces.

2. Should rich markdown preview be in this ticket?

   Recommended answer: only if a safe, sanitized, read-only renderer is small.
   Otherwise render markdown as source text first and keep rich markdown as a
   follow-up.

3. Should working-tree/index tree browsing be required for `LUNA-338`?

   Recommended answer: compare and open-file paths are required. Working-tree
   and index tree browsing should be included only if
   `BridgeReviewSourceProvider.readTree(...)` can support them without making
   BridgeWeb backend-aware.

