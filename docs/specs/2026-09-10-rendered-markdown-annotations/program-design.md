# Rendered Markdown source-range integration

Realizes [Specification](specification.md) under [Requirements](requirements.md).

## Ownership

```text
Existing File surface annotation provider — durable client/session/projection
  Existing File viewer shell — chooses source vs rendered presentation
    Markdown worker — parsing/highlighting + NEW typed source-target catalog
    Markdown canvas — stable sanitized article + Mermaid lifecycle
      NEW gutter/layout adapter — geometry, drag, range-to-host placement
      NEW Markdown annotation adapter — exact-source admission and thread projection
        Existing composer/thread — edits, errors, save/reply/resolve/focus
          Existing surface client -> comm worker -> native annotation owner
```

No new provider, transport operation, store or native identity is created. The
new adapters own only renderer-specific behavior. Worker parsing remains off the
main thread; durable truth remains native; UI selection is transient React state.

## Current path and delta

Current source: `BridgeWeb/src/file-viewer/bridge-file-viewer-shell.tsx` selects
`BridgeMarkdownCanvas`; `app/markdown/worker/bridge-markdown-render-worker-renderer.ts`
returns HTML and Mermaid source descriptors. The canvas has no annotation path.
`file-viewer/bridge-file-viewer-code-panel.tsx` already admits Pierre File ranges
against the displayed item's descriptor and renders the existing composer/thread.

```text
UNCHANGED File intent -> async Markdown worker -> identity-checked result
CHANGED  result -> Markdown replacement gate -> installed presentation
CHANGED  worker render -> HTML plus validated targets -> sanitized article
ADDED    pointer gutter -> local range -> + -> exact-current source guard
ADDED    admitted source range -> existing root.create composer operation
UNCHANGED composer -> async surface client/native -> receipt/error/projection
ADDED    projection -> mapped inline host -> existing thread component
UNCHANGED reply/edit/resolve -> existing command and draft lifecycle
```

Selection does not create a record. + captures the exact File descriptor together
with source range, path and source role `file`. Native command results/errors
return through the existing composer; the adapter must not synthesize success.

## Source catalog and safe DOM ownership

The worker response adds a required Zod-validated target catalog. Targets are a
discriminated union: prose (paragraph/list paragraph/heading), code-line,
code-block, table-row, diagram. Each carries an opaque target ID and positive
inclusive source range. Code-line entries identify their fence. Targets are
source-ordered with unique IDs. They derive from Markdown token maps, never from
visible text matching. Fence line ordinals account for the opening fence and the
single trailing newline removed by the Shiki adapter.

The sanitizer admits only the named opaque target attribute in addition to its
existing safe attributes. Catalog validation and DOM matching are separate:
missing or duplicate DOM IDs make the affected target non-interactive. Author
HTML remains disabled and generated styles remain subject to existing policy.

The stable article component owns its HTML only when the replacement gate installs
a new render identity, not immediately when the worker returns a candidate.
Annotation state never rewrites its HTML. A layout effect owns disposable host
nodes and ResizeObserver measurements. List paragraphs are actual paragraph
elements even for tight lists; parent containers receive no overlapping target.
Table hosts are sibling tr/td-colSpan nodes. Code uses valid block containers for
logical-line interleaving, retaining Shiki syntax output rather than introducing
a second highlighter. Cleanup removes only adapter-owned hosts and observers.

An article-level horizontal table wrapper keeps scrolling local. Gutter rows use
the article's vertical geometry; number/control centers use first-line metrics.
Mermaid replacement changes geometry, not target identity. The shared tokens and
existing thread/composer components supply paint; no new color palette.

## Exact-source admission and refresh

`use-bridge-markdown-presentation.ts` deliberately retains old same-path ready
HTML during successor rendering. `bridge-markdown-render-readback.ts` already
checks rendered identity against intent/item. Reuse that exact matching logic
for annotation admission rather than inferring descriptor identity from path.

```text
current ready render + matching source descriptor -> select -> compose -> durable flow
source changes -> retained old render remains readable
               -> new selection/+ disabled; stale pending selection retired
successor exact render installed -> new annotation admission resumes
successor fails -> retain old article/hosts; show Retry; new admission stays disabled
obsolete async result -> existing presentation rejection; no admission
```

Existing durable drafts and command-confirmed threads remain owned by the current
annotation lifecycle. Retain their origin/edit token rather than reconstructing
them from successor line numbers. If a thread has no exact/relocated target in
the painted document, do not fabricate an inline location; preserve its existing
recovery/history path. An uncommitted UI selection is disposable, not a draft.

The alternative is retaining a descriptor-bearing old Markdown binding and
allowing old-source admission. It preserves more interaction during refresh but
adds version-retention ownership. The accepted guard avoids that extra owner;
revisit only if refresh downtime makes annotation work materially unusable.

### Replacing a document with an active editor

The Markdown presentation owner holds at most the displayed result and the latest
same-file completed candidate. It does not cache document histories. The File
composition supplies the existing annotation edit registry's active-token signal
and `prepareActiveEditorsForInstallation` callback; the renderer does not create
another registry. New-message composers, reply composers and message editors all
participate through their existing edit registrations.

A successor result cannot remove hosts while an editor is mounted. The replacement
gate first calls the existing preparation callback (flush, not save). While any
editor remains active it retains the old article, the exact host objects, editor
component and local body/error/admission state—even if preparation succeeded.
This avoids a DOM/editor handoff rather than trying to recreate an editor from an
edit token. Failed preparation retains the old view and permits Retry. Existing
editor Save/Cancel/Escape behavior owns ending the edit; no automatic save is added.

When editing ends, the gate prepares once more and rechecks the current file,
request identity and active tokens after awaiting. Only a current candidate and
successful preparation may replace the article. A superseded candidate never
installs. Command-confirmed threads still belonging to the predecessor source
retain its presentation until compatible authoritative projection arrives, following
the existing File code-panel receipt-retention rule. Existing draft operations
keep their captured origin; the new-range guard never rewrites that origin.

An explicit file switch is a different lifetime: retire the transient range and
use existing editor exit/draft recovery behavior; do not paint the old file under
a new filename. A failed same-file render or unavailable worker retains the last
ready document, with a discriminated refresh-failure state and Retry action.
Initial load failure still shows the existing failure screen. Retried success
passes through the same replacement gate. Tests must delay/fail preparation,
type while a candidate waits, then prove the latest body survives and only the
current candidate installs after the editor exits.

## Interaction states

```text
idle -> selecting(anchor,target) -> selected(range) -> composing(edit token)
  text drag: no transition
  pointer cancel / obsolete source / file switch: retire transient selection
  + while not current: no transition, no command
  composer save/cancel: existing lifecycle owns outcome
  saved-thread activation: existing interaction controller owns attention/editor
```

Pointer capture belongs only to gutter gestures. The existing dismissal predicate
recognizes a named Markdown gutter marker in addition to Pierre markers; it must
not classify article text as a gutter or intercept native selection. Geometry
updates cannot mutate semantic range. No new polling, retry queue or coordinator.

## Proof seams

R1-R4: real worker renderer plus browser canvas exercise exact mapping, nested
paragraph exclusion, table header/body rows, blank code lines, wrapping and
cross-block drag. Real DOM and pointer gestures are necessary; mocked geometry
cannot prove layout. Component tests may substitute only the native command
boundary with its existing contract fixture.

R5-R6: File shell/provider journey exercises real composer and projection, with
native command boundary separately proved through the real Vite+Swift/native
path. A delayed successor render proves retained-source guard and durable draft
safety. Source/rendered switching proves singular annotation identity.

R7-R8: strict catalog/schema and sanitizer tests cover malformed metadata and
active-content rejection. Existing worker cancellation and readback tests guard
obsolete results. Native UI proof exercises the same WebKit renderer and actual
annotation command owner; fixture-only tests are not a smoke.
