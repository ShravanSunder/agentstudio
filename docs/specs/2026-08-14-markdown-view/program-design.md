# Markdown View Program Design

Date: 2026-08-14

Requirements: [Markdown View User Requirements](./user-requirements.md)

Specification: [Markdown View Specification](./specification.md)

## Structural realization

File View owns semantic Markdown. Review stays a Pierre `CodeView` and gives every
reviewed file a two-state `Diff` / `Open` toggle immediately after its change
counts. `Open` replaces only that Review item's Pierre diff item with Pierre's
complete current-file item. Review, its Changed files rail, and its selection stay
mounted.

```text
Bridge pane
  ├─ File View
  │    ├─ selected complete current file
  │    ├─ Markdown worker: Markdown Exit + Shiki
  │    ├─ semantic Markdown canvas
  │    └─ bounded lazy Mermaid rendering
  │
  └─ Review View
       ├─ Changed files rail and selected item
       ├─ Pierre CodeView
       │    ├─ Diff state: exact base/head diff item
       │    └─ Open state: complete current-file item
       └─ header metadata: counts + Diff/Open icon toggle
```

This is not a Markdown-specific Review renderer, a navigation to File View, a new
viewer mode, or a Current/Previous selector. Review changes only the selected
item's Pierre presentation. Semantic Markdown remains File View-only.

## Current system evidence

- `BridgeCodeViewPanelFrame` passes Agent Studio's `renderHeaderMetadata` callback
  to Pierre for every item.
- `createBridgeCodeViewHeaderRenderers` already maps Pierre items to Review
  descriptors and owns the pending label plus deletion/addition counts.
- Review selection already crosses the main/worker boundary through the typed
  `select` command and drives selected-content demand and Pierre materialization.
- Review's materialized item type can be `diff` or `file`; Pierre already renders
  both without a second canvas owner.
- File View already has the complete selected-current-content identity required by
  the Markdown worker. Review's earlier Markdown canvas and changed-line
  reconstruction duplicated that job and are removed.

## Structural crux and selected direction

The crux is keeping the toggle in Review without making the header acquire content
or mounting a parallel renderer over Pierre.

| Direction | Gain | Cost and risk | Decision |
| --- | --- | --- | --- |
| Review-local presentation on the existing selected-item path | preserves Review chrome and Pierre ownership; reuses demand/materialization | one optional `diff \| file` field on Review selection | selected |
| switch the pane to File View | reuses File selection and semantic Markdown | changes the sidebar and leaves Review, contrary to the interaction | rejected |
| mount a rendered Markdown canvas inside Review | rich Markdown in Review | duplicates content/render state and produced a visually confused diff projection | rejected |

The selected cost is a narrow extension of the existing Review selection command.
It is not a native command, durable preference, or new transport lane.

## Ownership and interfaces

### Review header toggle

The existing header metadata owner appends `BridgeCodeViewFilePresentationToggle`
after the counts. It uses the shared shadcn-style `ToggleGroup` primitive and the
requested `FileDiff` and `FileSpreadsheet` icons. The buttons are named `Diff` and
`Open` through `aria-label` and `title`; their icons are decorative.

```text
input:  mapped Review descriptor, selected presentation, callback(itemId, state)
output: one controlled Diff/Open icon toggle after counts
event:  stop Pierre header propagation, then emit the chosen state
error:  unmapped non-Bridge items receive no Agent Studio metadata
```

### Review-local presentation state

`BridgeReviewViewerMode` owns `openedReviewItemId`.

- `Open` on the selected item records that item as opened.
- `Open` on another item selects it and records it as opened.
- `Diff` clears the opened identity for that item.
- Selecting a different file clears the prior Open state.
- A transient null selection for the same item does not erase an explicit Open
  request while the worker republishes the item.

The selected presentation passed to Pierre is `{ kind: 'file', version: 'current' }`
only when the selected item is the opened item. Otherwise Pierre receives the
normal diff presentation.

### Existing Review selection protocol

The Review controller sends the existing `select` command with an optional
`reviewPresentation: 'diff' | 'file'`. Validation rejects that field on File View
selection commands.

The worker's selected Review demand owner keeps the presentation with the selected
item and derives the required content roles:

```text
Diff → base and head content → Pierre diff item
File → current/head content → Pierre file item
```

The response remains the existing Review render publication. No Markdown HTML,
SVG, file bytes, native authority, or separate presentation command is added.

### Pierre item replacement

The selected item keeps its Review item identity while its Pierre item type changes
between `diff` and `file`. Metadata reconciliation treats a type transition as an
authoritative replacement. This avoids retaining a diff-shaped live item when the
worker publishes a file-shaped item, and the inverse transition returns to the
exact diff.

The Review shell and Changed files rail never unmount for this transition.

### File Markdown render controller

File View alone derives Markdown render intent from a complete selected current
file. The intent includes source generation, file identity/version, content cache
key, content hash, source path, and exact contents.

```text
idle
  │ complete Markdown selected
  ▼
loading ── matching success ──► ready
  │                              │
  ├─ matching failure ─────────► failed
  └─ identity changes ─────────► abort and restart

late or mismatched completion → discard
```

The shared runtime owns one lazy Markdown worker client and one lazy Mermaid
renderer per mounted Bridge pane. It owns no File or Review selection state.

## Markdown source and render pipeline

File View renders only complete current content. Windowed, truncated, oversized,
binary, or otherwise incomplete content never masquerades as the whole document.

```text
complete File Markdown
  → Markdown Exit async parse/render
       ├─ semantic HTML
       ├─ Shiki highlighting for registered languages, including Swift
       └─ Mermaid fences become inert placeholders plus typed descriptors
  → sanitize document HTML
  → admit and render visible Mermaid descriptors on demand
  → sanitize each SVG
  → semantic File View article
```

Raw HTML and link navigation remain disabled. Unsupported fenced languages render
as inert text. The worker returns no Review ranges, executable callbacks, or SVG.

## Mermaid trust and demand boundary

Mermaid stays lazy and main-thread because its supported browser renderer requires
DOM access. The renderer uses strict configuration, no `bindFunctions`, bounded
source/edge admission, conservative rejection of URL/image/icon/interaction
directives, and a separate SVG sanitizer.

Each diagram is independent: a valid diagram becomes a labeled sanitized SVG; an
invalid diagram becomes a local retryable error while the rest of the document
remains readable. Results are ignored after the document identity changes or the
placeholder detaches.

## Failure and recovery

| Failure | Owner | Visible result | Recovery |
| --- | --- | --- | --- |
| Open requests a deleted/no-current-content item | Review demand/presentation | explicit unavailable selected item; no unrelated file substitution | choose Diff or another item |
| Review file content is pending | Review demand/presentation | selected file loading state | matching Review publication |
| Markdown worker unavailable | File Markdown controller | bounded document failure | retry recreates lazy worker |
| one invalid Mermaid diagram | Markdown canvas | local diagram error | diagram retry or source change |
| stale worker or Mermaid result | controller/canvas | no visible state change | current request continues |

No timer, debounce, persisted preference, cache, native command, Git adapter, or
cross-pane navigation subsystem is introduced.

## Styling and accessibility

The Review toggle uses the shared Bridge compact segmented-control classes and
focus tokens. The Diff/Open buttons are icon-only to fit Pierre's header; their
accessible names and tooltips are exactly `Diff` and `Open`.

The File Markdown article retains scoped descendant styles for headings,
paragraphs, lists, block quotes, inert link text, tables, thematic breaks, inline
code, `pre`, and Shiki tokens. Long code uses bounded horizontal overflow and
Mermaid SVGs receive accessible names.

## Requirement, design, and proof trace

| Requirement | Structural realization | Proof seam |
| --- | --- | --- |
| R1 | File owner supplies complete Markdown to the shared canvas | File intent/controller and browser semantics |
| R2 | Review defaults to Pierre diff; no Review Markdown canvas survives | Review browser regression and residue scan |
| R3 | controlled Diff/Open toggle emits selected-item presentation | header unit/browser interaction and Vite runtime |
| R4 | worker derives current-file presentation or explicit unavailable state | protocol, demand, materialization, and browser proof |
| R5 | async Markdown Exit + Shiki worker registers Swift | worker and browser token proof |
| R6 | bounded strict Mermaid renderer plus two sanitizers | renderer misuse tests and visual proof |
| R7 | echoed File identity, abort key, and DOM insertion fencing | supersession, mismatch, retry, and disposal proof |
| R8 | shared ToggleGroup and scoped semantic article | browser accessibility and screenshot inspection |

## Explicit non-ownership

This design creates no ownership for automatic rendered Markdown inside Review,
comments or source ranges, Current/Previous revision browsing, direct editing, MDX,
raw HTML, active widgets, remote resources, a native product call, persistence, a
new transport lane, Git access, or a new viewer mode.

## Source anchors

- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-protocol.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-file-presentation-toggle.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel-support.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-metadata-apply.ts`
- `BridgeWeb/src/app/markdown/`
- `BridgeWeb/src/file-viewer/`
- `BridgeWeb/node_modules/@pierre/diffs/dist/react/CodeView.d.ts`
- `tmp/research-workflows/2026-08-14-mermaid-main-thread-boundary/research-ledger.md`

## Structural decision

File View owns semantic Markdown. Review owns selected-item Diff/Open state and
reuses its existing worker demand plus Pierre materialization path for both
projections. Only the selected content presentation changes; Review chrome and
selection remain stable. The superseded Review Markdown canvas and changed-block
projection are deleted.
