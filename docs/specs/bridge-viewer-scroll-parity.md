# BridgeViewer Scroll Parity Spec (DiffsHub-quality scrolling)

Status: accepted, ready for implementation
Owner: BridgeWeb review/file viewer (browser integration layer)
Evidence base: `docs/wip/2026-07-02-review-scroll-system-root-cause.md`
(mechanical map §1, causal chains §2, anchor verification §3, fix
derivation §4, upward-reveal mechanism §5).

## 1. Goal

Review-mode and file-view scrolling must match the reference quality of
DiffsHub: no viewport motion the user did not initiate, a scrollbar
thumb that is stable from the first metadata window, and selection
reveals that land the target file header at the viewport top and stay
there — in both directions.

DiffsHub runs the same virtualizer we do (`@pierre/diffs` 1.2.10,
`@pierre/trees` 1.0.0-beta.4, external npm — a fork is out of scope and
unnecessary). Parity is therefore an integration contract: feed the
engine truthful heights, give it sole scroll authority, and keep its
re-targeting semantics alive through the hydration window.

## 2. Non-goals

- No Pierre fork or patch; no vendoring.
- No new app-side scroll anchors (the defect class being removed).
- Native transport changes: none required by this spec. Demand-lane
  streaming, content-addressed caching, prefetch, and the git-refresh
  breaker are landed and orthogonal.
- Comment anchoring UX (consumes this work later; no coupling now).

## 3. System invariants (the contract)

I1 HEIGHT TRUTH. The height Pierre is told for an unhydrated item must
   equal the height the item measures after hydration, within one line
   of rounding error. Violations convert every hydration into a layout
   shift. Sources of truth: metadata `lineCount` (streamed with the
   manifest), real line-height/wrap metrics.

I2 SINGLE SCROLL AUTHORITY. Exactly one system positions the viewport:
   Pierre's internal anchor (first fully-visible item id + pixel
   offset, re-applied after every layout pass). App code never writes
   `scrollTop` outside a Pierre API call. Rationale: any `scrollTo*`
   call clears Pierre's anchor (CodeView.js:494); competing writers
   oscillate.

I3 REVEALS RE-TARGET UNTIL SETTLE. A selection reveal tracks its target
   BY ITEM ID until layout is stable, because an instant one-shot
   resolves the target from estimated layout and abandons it after one
   frame (CodeView.js:1234-1235, :1304-1307); upward reveals land inside
   the region that hydrates next, so the target's true offset moves
   after the jump. Down-direction is insensitive (jumps past its
   above-region); both directions must satisfy the same landing bound.

I4 USER MOTION ONLY. Metadata windows, hydration, invalidation, and
   prefetch never move the viewport. Only user scroll, selection, and
   collapse/expand may.

## 4. Requirements (testable)

R1 Streaming stability: with the cursor idle, streaming N metadata
   windows into an open review causes zero first-visible-line drift
   (≤2px) and zero collapsed-region count flicker.
R2 Thumb constancy: scrollbar thumb length is constant from the first
   window (total height derives from exact counts + true estimates),
   for both the code view and the file tree.
R3 Reveal landing (down): select item 5 then 7 → after bounded settle,
   item 7's header top is within ≤4px of the scroll-owner top.
   (Amended from ≤2px: instrumentation showed a constant 4px offset
   from Pierre's item layout at align:'start', identical for 1-line
   and multi-line targets and independent of height estimates — a
   layout constant, not drift. The invariant is landing AT the header
   with zero post-settle motion; the bound absorbs the constant.)
R4 Reveal landing (up): select item 5 then 1, and 5 then 3 → same ≤4px
   bound (same amendment), and `scrollTop` converges monotonically
   across settle frames (no oscillation beyond ε). RED on HEAD today —
   this is the red→green gate for the reveal work.
R5 Collapse stability: collapsing a file header mid-viewport preserves
   the header's viewport position (the existing red chromium test
   "CodeView file header collapse preserves mid-viewport header
   position" flips green).
R6 Hydration silence: hydrating any visible non-selected item causes no
   viewport motion (≤2px) and no more than one layout pass per batch.
R7 Guided-mode order stability: while metadata is streaming, guided
   review ordering does not re-rank already-rendered items.

## 5. Design contracts (fix set)

Layer 1 — height truth (serves I1, R1, R2, R6):
- F1 `itemMetrics` on `bridgeCodeViewOptions`: real line height and
  wrap-aware metrics. Pierre currently assumes 20px unwrapped lines
  (options default) while rendered lines wrap taller.
- F2 Placeholder/hydrated cap parity: the synthesized "Loading…" body
  uses the same line-count window as hydrated content (today 1500 vs
  20000 — large items grow on hydrate by construction).
- F8 Tree reserves height from the exact native path count
  (`exactPathCount` is already on the wire; it currently dies in a
  data attribute — `bridge-file-viewer-pierre-tree-runtime.ts:101-158`
  sizes from received paths instead).

Layer 2 — scroll authority (serves I2, I4, R1, R5, R6):
- F3 `scrollToItem` fires only on a real selection-change key, never
  from metadata-window or hydration effects
  (`bridge-code-view-panel.tsx:567` today re-fires per window).
- F4 Remove the app-side DOM anchor and 30-frame pin loops from
  non-user paths (`bridge-code-view-panel-support.tsx:104-313`,
  `scrollCodeViewHeaderToScrollTopAcrossLayout`); Pierre's anchor is
  identity-stable across reconcile-by-id and needs no help.
- F5 Stable guided projection order during streaming
  (`review-projection.ts:346-395` re-ranks on mutable keys; freeze
  rank keys for rendered items until stream completion).
- F6 Collapse anchors the collapsed item via Pierre and drops the
  restore loop (flips R5's red test).
- F7 Drop the mid-loop `render(true)` in selected-item hydration
  (render() already coalesces via queueRender).

Layer 3 — reveal semantics (serves I3, R3, R4):
- F9 Re-targeting reveal: the selection reveal re-resolves the target
  by item id until `getTopForItem` stabilizes within ε under a bounded
  frame budget — either by issuing the reveal through Pierre's smooth
  path (re-resolves per frame, applies anchor deltas:
  computeTargetScrollTopForFrame CodeView.js:1151-1158,
  advanceScrollAnimation :1184-1207) or by re-issuing
  `scrollToItem(target)` on each layout-dirty until stable. During the
  settle window, Pierre's anchor is pinned to the TARGET so
  above-target growth is absorbed. F4 must land with or before F9 so
  only one authority drives the settle.

## 6. Plan (ordered slices, each red-first)

S1  F3 + F4 (yank removal).            Proof: R1 stream-N-window test
    red on HEAD → green; no regression in existing selection tests.
S2  F9 (re-targeting reveal).          Proof: R4 up-reveal test (red on
    HEAD) → green; R3 down-guard stays green.
S3  F1 + F2 (height truth).            Proof: R2 thumb-constancy test
    red → green; R6 hydration-silence test red → green.
S4  F6 (collapse) + F7 (render loop).  Proof: R5 existing red chromium
    test flips green with no test edits.
S5  F5 (guided order) + F8 (tree count). Proof: R7 test; tree thumb
    assertion from window 1.

Slice hygiene: one commit per slice, red test committed with its green.
The R4 proof fixture needs ≥8 items with line counts chosen so
estimate≠measured under wrap, and content served on demand; assert via
the `data-bridge-code-view-item-id` header being first-fully-visible
after settle and the `selectionScrollDiagnostic` attributes
(`panel-frame.tsx:88-99`).

## 7. Requirements/proof matrix

| Req | Proof | evidence source | freshness guard |
|-----|-------|-----------------|-----------------|
| R1  | stream-N-windows browser test (new) | vitest chromium project | red-first on HEAD |
| R2  | thumb-length constancy assertion from window 1 (new) | vitest chromium | red-first on HEAD |
| R3  | down-reveal landing test (new) | vitest chromium | green guard (works today) |
| R4  | up-reveal landing + monotonic settle test (new) | vitest chromium | RED on HEAD, flips with S2 |
| R5  | existing collapse test | bridge-viewer-browser.integration | red on clean HEAD today |
| R6  | hydration-silence test (new) | vitest chromium | red-first on HEAD |
| R7  | guided-order freeze test (new) | vitest unit | red-first |
| felt result | instrumented interactive session (marker-scoped Victoria analysis) vs session debug-observability-oq4s-1783010753-51205 | before/after comparison | fresh build required |

## 8. Interactions to respect

- Metadata interest streams during scroll (throttled publication); do
  not re-introduce idle-gating for metadata. Heavy content hydration
  remains scroll-idle-gated — with I1 true heights, late hydration is
  positionally invisible, which is what makes that gating safe.
- Content warmth (content-addressed cache + ring prefetch) shortens the
  F9 settle window; no coupling beyond timing.
- The stale auto-refresh coalesce (150ms trailing) may re-render an
  open file's content; under I1/I2 this must not move the viewport —
  covered by R6.
