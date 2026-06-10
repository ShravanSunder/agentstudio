# Bridge Review Foundation Spec

> Status: canonical design source for the pre-Pierre Bridge review foundation.
> Created: 2026-06-10
> Execution plan: [2026-06-08 Bridge Agent Review Foundation](../../plans/2026-06-08-bridge-agent-review-foundation.md)
> Architecture companion: [Swift-React Bridge Architecture](../../architecture/swift_react_bridge_design.md)
> Git data-plane plan: [AgentStudio Git Data-Plane Implementation Plan](../plans/2026-06-08-agentstudio-git-bridge-foundation.md)

This spec defines the Bridge review foundation as it should be understood by
future implementation plans. It replaces the old LUNA-337 foundation model from
the February Bridge diff plan. The February plan is historical only.

## Product Boundary

The Bridge review surface is a read-only source review pane. It helps the user
view files, compare endpoints, review agent-created change sets, filter large
diffs, and attach review metadata. It must not edit source files, apply patches,
approve or reject hunks, or own a Monaco-style editor buffer.

Editable review artifacts are a separate layer. Annotation anchors and review
metadata may be displayed by the foundation, but durable comment bodies,
markdown editing, edit history, and persistence belong to a later annotation
plan.

## Canonical Vocabulary

The review domain uses the query-first `BridgeReview*` model:

- `BridgeReviewQuery`
- `BridgeSourceEndpoint`
- `BridgeReviewCheckpoint`
- `BridgeViewFilter`
- `BridgeChangeGrouping`
- `BridgeProvenanceFilter`
- `BridgeReviewPackage`
- `BridgeReviewDelta`
- `BridgeReviewItemDescriptor`
- `BridgeContentHandle`
- `BridgeReviewGeneration`
- `BridgeReviewSourceProvider`

Do not reintroduce `BridgeDiffPackage`, `BridgeDiffEndpoint`,
`BridgeFileDescriptor`, `BridgeChangeCheckpoint`,
`BridgeChangeCollationPolicy`, or `BridgeChangeGroup` as review-foundation
contracts.

`BridgeReviewGeneration` is the branded monotonic freshness guard for review
packages, review deltas, content handles, and resource fetches. It is encoded
over the wire as `reviewGeneration`.

Transport push envelopes may still use `__epoch` for push-stream staleness.
That is a transport-local concept and is not the review contract freshness
model.

## Source Endpoints And Queries

`BridgeSourceEndpoint` is one side of a review comparison. It is source-neutral:
Git commits and refs are endpoints, but so are the working tree, index/staged
state, prompt checkpoints, session checkpoints, manual checkpoints, and saved
time-window checkpoints.

`BridgeReviewQuery` is the user intent. It covers:

- compare two endpoints
- open one file from one endpoint
- browse a tree or folder
- filter an existing package
- regroup an existing package

"Compare against main", "compare against last checkpoint", "show staged vs
working tree", "open this file", and "filter to this folder" are query modes,
not separate Bridge systems.

## Checkpoints And Collation

Prompt and session checkpoints are the primary automatic checkpoint sources.
Manual checkpoints are user-created canonical review boundaries. A time-window
view, such as "last 30 minutes", is a collation/filter over the event and change
stream until it is explicitly saved as a checkpoint.

The same raw change stream must support grouping and filtering by:

- last prompt
- current session
- last checkpoint
- manual checkpoint range
- time window
- git ref or branch comparison
- folder/path
- file class
- extension/language
- change kind
- review state
- agent/session/prompt provenance

Agent-produced change streams and time-window collations are provenance and
grouping inputs. They are not the canonical source of file truth unless
materialized as checkpoints and backed by endpoint/content identity.

## Package And Delta Model

`BridgeReviewPackage` is a metadata-heavy snapshot. It carries the query, base
and head endpoints, ordered item IDs, item descriptors, groups, summary,
filters, and `reviewGeneration`.

`BridgeReviewDelta` is a package-local metadata update. It carries
`packageId`, `reviewGeneration`, a package-local `revision`, and explicit
operations such as add, update, remove, move, group update, summary update, and
content invalidation.

Deltas update BridgeWeb's item registry. They do not stream raw line or hunk
mutations into Pierre CodeView. If visible content changes, BridgeWeb hydrates a
complete item and updates CodeView with a bumped item version.

## Item Identity And Content Handles

`BridgeReviewItemDescriptor` is the review item identity that maps to future
Pierre `CodeViewItem` records. File identity is not path-only. It is built from
endpoint identity, path, content hash, item ID, item version, and content role.

Descriptors carry per-role handles:

- added files have a head handle only
- deleted files have a base handle only
- modified files may have base and head handles or a diff handle
- open-file queries use a file handle for the selected endpoint

`BridgeContentHandle` is the only lazy pointer React may use to fetch bytes.
Handle identity includes handle ID, review generation, item ID, role, endpoint
identity, cache key, content hash, MIME type, language, size, and binary flag.
Path alone is not a trust boundary.

The resource URL shape is:

```text
agentstudio://resource/content/{handleId}?generation={reviewGeneration}
```

Do not use the historical `agentstudio://resource/file/{fileId}?epoch=...`
shape for review content.

## Delivery Pipeline

The target pipeline is metadata push and lazy content pull:

```text
BridgeReviewQuery
  -> off-main BridgeReviewPipeline
  -> BridgeReviewPackage metadata
  -> BridgeWeb item registry
  -> viewport/selection requests content handles
  -> agentstudio://resource/content/{handleId}?generation=...
  -> complete render item
  -> future Pierre CodeView addItems/updateItem
```

Large file bytes and expensive render preparation must not ride the small state
push stream. The package may register content handles, hashes, summaries, and
small metadata eagerly. It should not require all file bytes to be loaded before
a package can be published.

If current implementation code eagerly preloads handle contents during package
construction, treat that as an implementation gap against this spec, not as the
target architecture.

## MainActor And Runtime Boundary

WebKit, SwiftUI, AppKit, atoms, observable UI state, and pane lifecycle are
MainActor boundaries. Review computation is not.

The following work belongs off the MainActor behind actors/services and
`Sendable` request/result models:

- endpoint resolution
- endpoint comparison
- checkpoint collation
- file classification
- content hashing
- content loading
- review package building
- delta building
- large JSON/data preparation

MainActor Bridge code should collect UI/WebKit/RPC context, await off-main
results, then publish compact metadata or complete WebKit-facing callbacks.

This foundation does not add a new Bridge atom or persistence store. Runtime
indexes and content caches are local runtime infrastructure. Durable Bridge
state requires a separate state-boundary discussion and must follow the feature
state conventions.

## Provider Boundary

Bridge owns review contracts. Git and other backends provide data behind
`BridgeReviewSourceProvider`.

The provider resolves endpoints, compares endpoints, reads trees and single-file
metadata, resolves checkpoint endpoints, and loads content for handles. It must
not decide UI filters, annotation schema, hidden-file policy, BridgeWeb folder
structure, source mutation, or backend selection policy outside the injected
implementation.

Direct calls from Bridge to `AgentStudioGitClient` are allowed only if the
client's public `Sendable` request/result DTOs exactly match Bridge review
contracts. If Git DTOs differ, use a thin Bridge-owned mapper such as
`AgentStudioGitReviewSourceProvider`.

The Git data-plane plan must not define BridgeWeb TypeScript contracts,
Bridge review package shapes, content handle shapes, resource URL shapes,
checkpoint semantics, or review-generation vocabulary.

## WebKit And Resource Trust Boundaries

Bridge panes are an internal, locked-down WebKit surface:

- Bridge code runs in a named `WKContentWorld`.
- Page-world React cannot call scoped WebKit message handlers directly.
- Cross-boundary traffic flows through bridge-world relays.
- Relay traffic uses nonce validation as defense-in-depth.
- `bridge.ready` gates authoritative pushes and package publication.
- Navigation is allowlisted to `agentstudio` and `about`; `http` and `https`
  open externally; other schemes are blocked.
- `agentstudio://app/*` serves immutable packaged BridgeWeb assets and future
  worker chunks.
- `agentstudio://resource/content/*` serves review-package-scoped content bytes
  only.
- Scheme handlers reject unknown hosts, malformed routes, missing or negative
  generations, unknown handles, stale generations, and traversal attempts after
  percent-decoding.

The bridge nonce is not a secret against hostile same-page script execution. It
is a guard against accidental cross-script interference and unsanctioned direct
page-world access to Bridge internals. The primary trust anchors are WebKit
content-world isolation, scoped message handlers, navigation policy, method
allowlisting, typed decoding, and Swift-side URL/handle validation.

BridgeWeb may fetch only Swift-issued content handle URLs. Client-side resource
URL parsing is useful as a defensive assertion and test aid, but Swift remains
the enforcement point for path, generation, and handle validity.

## BridgeWeb Shape

BridgeWeb follows the domain shape and avoids generic folders:

```text
BridgeWeb/
  src/
    app/
    bridge/
    foundation/
      review-query/
      review-package/
      content/
    review-viewer/
```

Test names must use:

- `*.unit.test.ts`
- `*.unit.test.tsx`
- `*.integration.test.ts`
- `*.integration.test.tsx`
- `*.e2e.test.ts`
- `*.e2e.test.tsx`

Do not use generic `types.ts`, `utils.ts`, `store.ts`, `protocol.ts`, or
`helpers.ts` for Bridge domain modules.

## Downstream Architecture Plans

The following are intentionally not part of the pre-Pierre foundation. They
should become separate architecture specs/plans when executed later.

### Pierre/Shiki/Trees Viewer

The next viewer plan should integrate Pierre CodeView, Shiki highlighting,
Pierre worker-pool setup, and Trees-style navigation on top of the foundation
package and content-handle model.

Accepted constraints to preserve:

- CodeView is the high-level mixed file/diff scroll surface.
- CodeView item identity maps from `BridgeReviewItemDescriptor.itemId`.
- Render-significant content changes bump item version and cache key.
- Bridge streams package/delta metadata; BridgeWeb hydrates complete items.
- Shiki/highlighter work must run through Pierre's worker/highlighter path.
- Worker chunks are packaged `agentstudio://app/*` assets.
- Trees navigation is path-first and should consume prepared or presorted input
  outside hot React render paths.

### Annotation And Review Artifacts

Annotation anchors and marker rendering are downstream from this foundation.
The durable annotation/comment schema belongs to a later plan after Pierre and
Hunk-style review workflow research.

The foundation may carry lightweight annotation summary metadata, but it does
not freeze markdown bodies, edit history, persistence, or rich note UX.

### Agent Review Workflow

Agent review workflow is context delivery and timeline/state exchange only. It
may send selected files, ranges, or annotation threads as review context. It
must not add patch application or source mutation to the Bridge review pane.

### Security, Performance, And Lifecycle Hardening

Hardening plans should cover method allowlists, navigation policy, scheme URL
validation, app/worker asset loading, content cancellation, slow consumer
behavior, WebKit crash/resume, stale generation rejection, and large-package
performance.

## Historical Notes

The old February Bridge diff plan preserved useful downstream research about
Pierre CodeView, Shiki, Trees, annotation research, and hardening order. Those
ideas are reflected above as downstream architecture-plan inputs.

Its old LUNA-337 foundation vocabulary is obsolete:

- `DiffManifest(epoch, sourceId, orderedPaths, fileDescriptors)`
- `ContentHandle(fileId, epoch, contentHash, cacheKey, ...)`
- `agentstudio://resource/file/{fileId}?epoch=...`
- split `LUNA-347 -> LUNA-337` foundation ownership

Do not execute those old instructions.
