# Review-mode scroll system — definitive mental model and root-cause chain

Date: 2026-07-02
Scope: `BridgeWeb` review-mode CodeView (and the sibling file tree) built on Pierre's
virtualizer (`@pierre/diffs@1.2.10`, `@pierre/trees@1.0.0-beta.4`). Read-only investigation.

> **Addendum (2026-07-02) — upward selection-scroll regression: see §5 at the end of this
> document.** Short version: selection reveal uses a one-shot `instant` scroll to the target's
> *estimated* top and then abandons it (Pierre clears `pendingScrollTarget` after one settled
> frame). Upward jumps land in the region that then hydrates and grows, so the target moves
> after the scroll settled and nothing chases it; downward jumps land past their above-region,
> which stays virtualized and stable. Fix = accurate `itemMetrics` **plus** a re-targeting
> reveal (scroll to item id with post-layout correction until stable) instead of one-shot
> instant. Pre-existing on committed branch code; Codex's dirty edits only amplify it.

Pierre is an **external npm dependency** (pnpm-symlinked into
`BridgeWeb/node_modules/@pierre/*`), not vendored source we own. Every fix below is an
**integration fix** — none requires editing or forking Pierre.

---

## TL;DR verdict

1. **Pierre already keeps the viewport visually stable across item mutations.** Its render
   pass captures a scroll anchor (first fully-visible item, by **item id** + pixel
   `viewportOffset`) and re-applies it after re-layout, on **every** render where layout
   went dirty — which `setItems`/`updateItem` always cause. So content jumps are **not**
   Pierre failing to anchor.

2. **The jumps are self-inflicted.** The app runs a *second*, competing anchor system that
   writes `scrollOwner.scrollTop` directly and force-renders in RAF loops, and it calls
   `scrollToItem(selected)` on nearly every metadata window. Both actions **defeat Pierre's
   own anchor** (`scrollTo` explicitly clears it). Two anchor authorities fighting over one
   scroll position is the primary jump source.

3. **The "less smooth than DiffsHub" feel is the scrollbar thumb churning**, caused by
   estimated item heights being wrong up front and re-measuring as content hydrates. Two
   causes: (a) Pierre is given **no `itemMetrics`** so it estimates with defaults while the
   view runs `overflow: 'wrap'` (wrapped lines are taller than the estimate); (b) placeholder
   heights come from a **line count that streams in late** and is **capped at 1500 lines**
   while hydrated content is not. The scroll content height keeps changing → thumb length and
   position keep changing.

4. **Codex was directionally right that the app's duplicate DOM anchor is wrong, but wrong
   about the remedy.** No missing Pierre "batch/deferred-update API" is needed. Batching
   already happens (renders coalesce); the fixes are: stop fighting Pierre's anchor, stop
   redundant `scrollTo`, give Pierre accurate heights, and stop reordering the list mid-stream.

---

## 1. The mechanical map (read this section standalone)

### 1.1 Who owns `scrollTop`

There is exactly one scrollable element, and **both** Pierre and the app write to it.

```
   ┌──────────────────────────────────────────────────────────────────┐
   │  <div class="bridge-code-view-scroll-owner ... overflow-y-auto     │
   │        [overflow-anchor:none]">          ← THE scroll container    │
   │                                                                    │
   │   • This div is passed to Pierre as CodeView.setup(root).          │
   │     (react/CodeView.js:65 → instance.setup(node))                  │
   │   • Pierre reads it:  root.scrollTop         (CodeView.js:1533)    │
   │   • Pierre writes it:  root.scrollTo(...)     (CodeView.js:1513)   │
   │   • The APP also writes it: scrollOwner.scrollTop += delta         │
   │                              (panel-support.tsx:270)               │
   │   • Same element: closest('.bridge-code-view-scroll-owner')        │
   │     resolves to this div (panel-frame.tsx:108).                    │
   └──────────────────────────────────────────────────────────────────┘
```

Pierre keeps a *logical* scrollTop = `root.scrollTop + scrollPageOffset`. `scrollPageOffset`
is 0 for normal-sized reviews and only becomes non-zero for >~1,000,000px lists (the
`SCROLL_REBASE_*` paging scaffold, CodeView.js:109-113). So for ordinary reviews the app's
raw `scrollOwner.scrollTop += delta` is *consistent* with Pierre; for very tall reviews it
silently diverges from Pierre's paged model.

### 1.2 How a row's height is determined (estimate → measure)

An item's reserved height is set in two places:

```
 createItem/appendItemsInternal ──► instance.prepareCodeViewItem(file|fileDiff, top)
   (CodeView.js:583, 1621-1622)        → ESTIMATED height from itemMetricsCache
                                          (lineHeight, diffHeaderHeight, hunkLineCount…)

 …later, once the element is really rendered…
 reconcileRenderedItems ──► instance.reconcileHeights()  (CodeView.js:1372-1374)
                              → MEASURED height replaces the estimate; if it changed,
                                scrollHeight is recomputed and scrollDirty=true.
```

The estimate quality depends entirely on `itemMetrics`. **The app passes none**
(`bridgeCodeViewOptions` has no `itemMetrics`, options.ts:7-80), so Pierre uses
`DEFAULT_CODE_VIEW_FILE_METRICS` = `{ lineHeight: 20, diffHeaderHeight: 44, hunkLineCount: 1,
spacing: 8 }` (constants.js:38-47). The view runs `overflow: 'wrap'` (options.ts:15), so real
lines can wrap to 2-3 rows — always **taller** than the 20px/line estimate. Every measured
item therefore tends to grow relative to its estimate.

**Where line count becomes pixels for an *unhydrated* item:** the placeholder does not carry a
numeric height — it literally synthesizes N lines of `"Loading content..."` text
(`placeholderTextForLineCount`, materialization.ts:584-601) and lets Pierre estimate from that
text. N comes from `item.contentLineCountsByRole` if known, else a package-average estimate,
else **empty** (materialization.ts:717-749, 755-793). Two consequences:

- Before any line-count metadata arrives, N≈0 → placeholder is ~0px tall.
- N is capped at `codeViewContentWindowLineCount = 1500` (materialization.ts:591) while hydrated
  content is only capped at `fullCodeViewMaterializationLineBudget = 20000` (materialization.ts:22).
  A 4000-line file's placeholder is 1500 lines tall but hydrates to 4000 → it **grows ~2.6×**
  on hydration.

So item heights move twice: estimate-from-N (which itself changes as N streams in) and
estimate→measured (wrap correction). Each move changes total `scrollHeight`.

### 1.3 What `setItems` actually does internally

`setItems` is a dispatcher, not a full rebuild (CodeView.js:558-563):

```
 setItems(items):
   items.length === 0            → reset()                       (wipe everything)
   this.items.length === 0       → appendItemsInternal(items)    (first fill)
   tryAppendItems(items) == true → append-only fast path         (prefix unchanged + new tail)
   else                          → reconcileItems(items)         (reconcile by id)
```

- `tryAppendItems` (CodeView.js:860-879) only succeeds if the **entire existing ordered prefix
  matches by id+type** and the new list is strictly longer. It reuses every record in place and
  measures only the appended tail.
- `reconcileItems` (CodeView.js:886-925) matches new items to old **records by id**, reuses the
  record+instance when the type matches, releases removed records, and marks layout dirty from
  the first index where order/membership/**version** changed. `syncItemRecord` only marks an
  item dirty when its **`version` changes** (CodeView.js:932-939) — same version = record kept
  untouched. If nothing changed, `firstDirtyIndex` stays null and reconcile **returns without
  rendering** (CodeView.js:916). So a no-op `setItems` is genuinely free.

Neither `setItems`, `reconcileItems`, `tryAppendItems`, nor `updateItem` calls
`capturePendingLayoutAnchor`. That method is invoked **only from `setOptions`**
(CodeView.js:599). This matters for the anchor claim below.

### 1.4 Pierre's scroll anchor — the load-bearing mechanism

Anchoring lives in the render pass `computeRenderRangeAndEmit` (CodeView.js:1208-1313):

```
 render pass:
   scrollAnchor = getScrollAnchor(scrollTop)          # BEFORE relayout, uses old tops (:1214)
   if layoutDirtyIndex != null:                       # setItems/updateItem set this
       recomputeLayout(dirtyIndex)                     # remeasure tops/heights (:1216)
       computeScrollCorrection = true
   if computeScrollCorrection and scrollAnchor:
       newTop = resolveAnchoredScrollTop(scrollAnchor) # keep anchor at same viewportOffset (:1222)
       scrollTopAfterLayout = newTop                   # → viewport stays pinned to that item
   … render window … reconcileRenderedItems …          # measured heights may move scrollHeight
   anchoredAfterRender = resolveAnchoredScrollTop(scrollAnchor)   # second correction (:1288)
```

`getScrollAnchor` (CodeView.js:1443-1473): scans the currently-rendered items and returns the
**first item whose top is at/below scrollTop** (a fully-visible item) as
`{ type:'item', id, viewportOffset: absoluteItemTop - scrollTop }`. If the top item only
straddles the viewport, it asks that item for a **line-level** anchor
(`getNumericScrollAnchor`). `resolveAnchoredScrollTop` (CodeView.js:1481-1493) looks the anchor
up **by id**, recomputes the item's new absolute top, and returns
`newTop - viewportOffset` — i.e. it keeps that specific item at the same pixel offset from the
top of the viewport, even if items above it grew, shrank, or were inserted.

**This is exactly the correct behavior** and it is identity-stable across reconcile (records
are reused by id). Growth above the viewport, hydration below, height re-measurement — all are
absorbed. The same logic also runs on `handleResize` (CodeView.js:1405-1428).

**When the anchor does NOT run / is defeated:**

| Condition | Where | Effect |
|---|---|---|
| `pendingScrollTarget` is set (any `scrollTo`) | anchor path gated by `computeScrollCorrection`; `scrollTo` sets `pendingLayoutAnchor = void 0` | CodeView.js:494 | app `scrollTo` **clears** Pierre's anchor for that cycle |
| user wheel/touch/key/pointer down | `clearPendingScroll` clears `pendingLayoutAnchor` | CodeView.js:1400-1404 | fine (user is driving) |
| `renderState.firstIndex === -1` or `stickyTop === -1` | `getScrollAnchor` returns undefined | CodeView.js:1446-1448 | transient (first render, or after `resetRenderState` when the list shrank) |
| big programmatic jump w/o correction | `fitPerfectly` path discards anchor | CodeView.js:1234-1235 | intended for large jumps |

Takeaway: **Pierre anchors automatically on item mutation; the only routine way to lose it is
to call `scrollTo`.** The app calls `scrollTo` a lot.

### 1.5 The app's *second* anchor system (the redundant one)

`bridge-code-view-panel-support.tsx` implements a parallel DOM-measurement anchor:

- `captureCodeViewHeaderAnchor` (:104-133) records a header element's pixel offset from the
  scroll owner.
- `restoreCodeViewHeaderAnchor` / `restoreCodeViewHeaderAnchorAcrossLayout` (:168-190, 295-313)
  re-measure after layout and correct by mutating scroll.
- `scrollCodeViewHeaderToScrollTopAcrossLayout` (:201-221) pins a header to offset 0.
- All corrections go through `scrollCodeViewByLogicalDelta` (:257-272):
  `scrollOwner.scrollTop += delta; instance.render(true)`.
- Each runs a **RAF retry loop up to 30 frames** (`codeViewHeaderAnchorRestoreFrameBudget = 30`,
  and the pin/selection budgets are all 30, panel-types.ts:50-52).

This system pins a **specific header** (the collapsed one, or the selected one), whereas
Pierre pins the **first fully-visible item**. When those aren't the same element, the two
systems disagree and push scroll in different directions across many frames.

### 1.6 The metadata streaming loop (why `setItems` re-fires)

```
 CodeView scroll ──(120ms idle only)──► publishVisibleHydrationItemIds
     handleCodeViewScroll debounce = codeViewVisibleHydrationScrollIdleMilliseconds=120
     (panel.tsx:150-171)                                        │
                                                                ▼
                          onVisibleItemIdsChange → metadata-interest runtime
                          → bridge.metadata_interest.update RPC (interest-runtime.ts:219-231)
                                                                │  native returns metadata
                                                                ▼
        review-viewer store updates reviewPackage (new revision/generation)
                                                                │
                                                                ▼
        projection coordinator rebuilds projection (coordinator.ts:261-387; 32/96ms coalesce)
                                                                │  new projection + package
                                                                ▼
        initialItems = createBridgeCodeViewInitialItems(...) recomputes  (panel.tsx:505-517)
                                                                │
                                                                ▼
        EFFECT panel.tsx:540-578 fires:  instance.setItems(reconciled)
                                          + if selected: scrollToItem(selected,'instant')
                                          + header-pin RAF loop
```

Two important properties of this loop:

- Hydration and interest are **suppressed during active scroll** (`shouldApplyBridgeCodeView-
  Materialization` returns false for non-selected items while scrolling, panel-support.tsx:281-287;
  interest only publishes at 120ms idle). So updates arrive in a **burst the moment you stop**.
- `reconcileBridgeCodeViewMetadataItems` (panel-support.tsx:764-796) preserves already-hydrated
  items, so re-applying the array does **not** clobber content — but it still calls `setItems`
  with the whole array every window, and the effect's `scrollToItem(selected)` fires
  unconditionally whenever selected content is present.

---

## 2. Causal chains per symptom (ranked by user-perceived severity)

### S1 — Viewport yanks back to the selected file during metadata streaming (worst; selected/guided review)
```
 metadata window → reviewPackage changes → initialItems changes
   → EFFECT panel.tsx:546  instance.setItems(reconciled)        # Pierre would anchor here…
   → panel.tsx:567         controller.scrollToItem(selected,'instant')
        → engine scrollTo (CodeView.js:480) sets pendingScrollTarget
        → CodeView.js:494  this.pendingLayoutAnchor = void 0    # …but anchor is CLEARED
        → viewport is forced back to the selected item's top
   → panel.tsx:569         scrollCodeViewHeaderToScrollTopAcrossLayout (30-frame pin loop)
```
Every window while a file is selected re-pins scroll to that file. If you scrolled away to read
context, you are pulled back. Maps to **RC1 + RC2** (the reapply has no general first-visible
anchor; it only re-scrolls the selected item).

### S2 — Scrollbar thumb length/position churns constantly (all modes; the DiffsHub-parity gap)
```
 item hydrates or its line-count N updates
   → placeholder/measured height changes
       • estimate uses default 20px/line, no itemMetrics (options.ts has none)
       • overflow:'wrap' makes real lines taller than estimate
       • placeholder N capped at 1500 lines; hydrated up to 20000  (materialization.ts:22,591)
   → reconcileRenderedItems recomputes scrollHeight (CodeView.js:1381-1384)
   → container height set to new scrollHeight (CodeView.js:1320)
   → native scrollbar thumb = viewport / scrollHeight changes length AND position
```
Pierre keeps *content* visually anchored, but the *thumb* is a function of total height, which
keeps moving. This is the "less smooth than DiffsHub" feel. Maps to a **new finding** (height
estimate error), adjacent to RC3's spirit (missing exact counts) but for the code view, not the
tree.

### S3 — Content lurches when you stop scrolling (all modes)
```
 during scroll: hydration + interest suppressed (panel-support.tsx:281-287; 120ms idle)
 scroll stops → 120ms later burst:
   → visible items hydrate: N× controller.applyItemUpdate (panel.tsx:732,776)
   → heights re-measure → scrollHeight jumps → thumb jumps
   → if selected item is in the batch: render(true) mid-loop + scrollToItem (panel.tsx:778-813)
```
Maps to **RC6** (per-item updates; the selected branch forces a synchronous `render(true)`
mid-loop) and the metadata-idle finding.

### S4 — List reshuffles under you in guided review (guided mode only)
```
 metadata updates a sort key (reviewState / reviewPriority / fileClass)
   → guidedReview compareForMode does a full multi-key sort (review-projection.ts:346-395)
   → orderedItemIds change → new initialItems with DIFFERENT ORDER
   → setItems → tryAppendItems fails (prefix reordered) → reconcileItems marks dirty
   → items visually reorder around the anchored first-visible item
```
Pierre pins the first-visible item by id, so *it* stays, but everything else moves around it —
reads as the list shuffling. `normalReview` returns `compareForMode = 0` (stable), so this is
**guided-only**. Maps to **RC5**.

### S5 — Header position drifts on collapse (reproduced by a failing test)
```
 setItemCollapsed (panel.tsx:224-295):
   → captureCodeViewHeaderAnchor(collapsed header)      # app anchor = THIS header
   → controller.applyItemUpdate(nextItem)               # Pierre marks dirty…
   → codeViewHandle.getInstance().render(true)          # …Pierre anchors FIRST-VISIBLE item
   → restoreCodeViewHeaderAnchorAcrossLayout (30-frame loop mutating scrollTop)
```
Pierre pins the top-of-viewport item; the app pins the collapsed header. For a mid-viewport
collapse these are different elements, so the two corrections fight across 30 frames while
async measurement settles. Reproduced by
`src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
("CodeView file header collapse preserves mid-viewport header position"), which fails on clean
HEAD. Maps to **RC2 (collapse anchor)**.

### S6 — Tree panel thumb churns as paths stream (file tree, separate virtualizer)
```
 paths append → model.batch(add ops) (pierre-tree-runtime.ts:137); itemHeight fixed 24px
   → tree total height = current path count × 24; grows every batch
   → no exact total path count reserved up front → thumb resizes each batch
   → app also runs its own row-anchor restore loop (pierre-tree-runtime.ts:131-156)
```
Maps to **RC3**: the native exact path count never reaches the tree virtualizer as a height
reservation; the tree sizes purely from streamed `paths`.

Severity order (perceived): **S1 > S2 > S3 > S4 > S5 > S6**. S1/S2 are the ones a user feels as
"jumps and not smooth."

---

## 3. Verify / refute Codex's claim

Codex claimed: *"Pierre already anchors internally inside setItems, so a duplicate DOM anchor
is wrong; hydration shimmer and thumb quantization need a Pierre batch/deferred-update API that
doesn't exist."*

- **"Pierre anchors internally" — CONFIRMED in substance, corrected in mechanism.** Pierre does
  not anchor *inside* `setItems`; `setItems` only marks layout dirty. The anchoring happens in
  the next render pass, which captures `getScrollAnchor` (first fully-visible item, keyed by
  **item id** + pixel `viewportOffset`) before `recomputeLayout` and re-applies it after,
  whenever `layoutDirtyIndex` was set (CodeView.js:1213-1228, 1288-1290). `setItems`/`updateItem`
  always set `layoutDirtyIndex`, so item mutations *are* anchored automatically.

- **"A duplicate DOM anchor is wrong" — CORRECT.** The app's
  `captureCodeViewHeaderAnchor`/`restore*`/`scrollCodeViewHeaderToScrollTopAcrossLayout` system
  (panel-support.tsx:104-313) is redundant with Pierre's anchor and pins a *different* element
  (a specific header) than Pierre's (first-visible item), so it actively fights it.

- **The caveat Codex missed (the actual root cause):** Pierre's anchor is **cleared by
  `scrollTo`** (`this.pendingLayoutAnchor = void 0`, CodeView.js:494) and its correction is
  skipped whenever a `pendingScrollTarget` is active. The app calls `scrollToItem` on nearly
  every metadata window (panel.tsx:567), during hydration (panel.tsx:790, 804), and from the
  selection hook (use-bridge-code-view-selection-scroll.ts:139) — each call defeats the anchor.
  So the failure is not "Pierre doesn't anchor," it is "the app keeps telling Pierre to scroll,
  which throws the anchor away."

- **"Needs a batch/deferred-update API that doesn't exist" — REFUTED.**
  - *Batching already exists.* `updateItem` calls `render()` which **queues** via
    `queueRender` (CodeView.js:519, 635). Multiple `updateItem` calls in one synchronous loop
    coalesce into a single render pass with one anchor correction. The only place that breaks
    coalescing is the app's own `render(true)` immediate calls (panel.tsx:277, 334, 779; and
    every `scrollCodeViewByLogicalDelta`).
  - *Thumb churn is a height-estimate problem, not a deferral problem.* It is fixed by giving
    Pierre accurate `itemMetrics` (a real option, `CodeViewOptions.itemMetrics`, honored at
    CodeView.js:183/605) and by making placeholder heights match hydrated heights (don't cap
    placeholder line count below the hydrated cap). No new Pierre API required.

Net: Codex's instinct to delete the duplicate anchor is right; its conclusion that we're
blocked on a missing Pierre API is wrong. All fixes are integration-level.

---

## 4. Fix plan (Codex-executable, ordered smallest-first)

Each fix names the mechanism, the exact symbol/file, and a browser-test proof expectation. The
canonical proof pattern (the "work order"): **stream N metadata windows with the scroll cursor
idle → the first visible line must not drift; the thumb length must be constant from window 1;
collapse must preserve the header position.** All fixes are **pure integration**; none needs a
Pierre API that doesn't exist, and Pierre is external so we do not fork it.

### Fix 1 — Give Pierre accurate `itemMetrics` (fixes S2 thumb churn; pure integration)
- **Mechanism:** eliminate estimate-vs-measured height drift so `scrollHeight` is stable.
- **Change:** add an `itemMetrics` block to `bridgeCodeViewOptions`
  (`BridgeWeb/src/review-viewer/code-view/bridge-code-view-options.ts:7`) with `lineHeight`,
  `diffHeaderHeight`, `spacing` matching the actual rendered CSS (measure the real
  `[data-diffs-header]` min-height = 32px set in the same file's `unsafeCSS`, and the real line
  box height for the review font). Pierre reads it at CodeView.js:183/605.
- **Proof:** browser test — render a fixed fixture, assert `scrollHeight` (container height) is
  within a small tolerance of the post-hydration height *before* hydration, and that the thumb
  ratio does not change across N idle metadata windows.

### Fix 2 — Make placeholder height match hydrated height (fixes S2/S3 growth-on-hydrate)
- **Mechanism:** stop the "placeholder capped at 1500 lines, hydrated up to 20000" mismatch and
  the "N≈0 before metadata" collapse.
- **Change:** in `bridge-code-view-materialization.ts`, cap the placeholder line count with the
  **same** window the hydrated item will use (align `codeViewContentWindowLineCount` usage in
  `placeholderTextForLineCount`:591 with the hydrated `shouldUseBoundedCodeViewWindow` decision,
  materialization.ts:642-653), and require line-count metadata to be present before rendering a
  non-empty placeholder for a visible item (or reserve a metrics-based height instead of empty).
- **Proof:** browser test — for a fixture item with known line count, assert the placeholder's
  reserved height equals the hydrated height within tolerance (no growth step on hydrate).

### Fix 3 — Stop re-scrolling to the selected item on every metadata window (fixes S1; largest UX win)
- **Mechanism:** let Pierre's anchor hold the viewport; only scroll on genuine selection change.
- **Change:** in `bridge-code-view-panel.tsx`, the metadata-reapply effect (:540-578) must **not**
  call `controller.scrollToItem(selectedItemId,'instant')` + `scrollCodeViewHeaderToScrollTop…`
  on every `initialItems` change. Gate that block on a *new selection key* (reuse
  `lastSelectionScrollKeyRef`/`completedSelectionScrollKeyRef` already in the file) so it runs
  once per selection, not once per window. `setItems` alone is enough — Pierre anchors.
- **Proof:** browser test — select a file, scroll 500px away, stream N metadata windows idle;
  assert the first visible line's DOM top does not move (no yank-back).

### Fix 4 — Remove the app's duplicate DOM anchor for hydration/reapply (fixes S1/S3/S5 fights)
- **Mechanism:** eliminate the second anchor authority that fights Pierre.
- **Change:** stop calling `scrollCodeViewHeaderToScrollTopAcrossLayout` /
  `restoreCodeViewHeaderAnchorAcrossLayout` from the non-user paths — the metadata reapply
  (panel.tsx:569), the non-selected hydration path, and reduce the collapse path (see Fix 6).
  Keep app-driven scroll **only** for true user intent (initial selection reveal via the
  selection hook). Rely on Pierre's `getScrollAnchor`/`resolveAnchoredScrollTop` for stability.
  The helpers in `panel-support.tsx:104-313` become used only by the explicit reveal path.
- **Proof:** browser test — hydrate a batch of visible items with cursor idle; assert first
  visible line top is unchanged frame-to-frame (no RAF-loop jitter).

### Fix 5 — Freeze projection order during streaming for guided review (fixes S4 reshuffle)
- **Mechanism:** stop reorder-driven reconcile mid-stream.
- **Change:** in the projection path (`review-projection.ts:346-395` guided sort, consumed by
  `use-review-projection-coordinator.ts`), snapshot the guided rank once per review generation
  (or debounce re-rank so it only re-sorts on explicit user action / generation bump), so
  streaming metadata that changes `reviewState`/`priority`/`fileClass` does not re-order the
  live list. `normalReview` is already stable and needs no change.
- **Proof:** browser test in guided mode — stream metadata that flips a sort key on an
  off-screen item; assert `orderedItemIds` for the visible window is unchanged during streaming.

### Fix 6 — Collapse should anchor the collapsed header, not fight Pierre (fixes S5 failing test)
- **Mechanism:** on collapse the user's intent is "keep *this* header put." Let Pierre do it by
  anchoring to that item instead of running a competing DOM loop.
- **Change:** in `setItemCollapsed` (panel.tsx:224-295), after `applyItemUpdate`, do a single
  `controller.scrollToItem(itemId, 'instant')`-style pin to the collapsed item (which becomes
  Pierre's anchor for that render) or rely on Pierre's first-visible anchor when the collapsed
  header is at/above the top; drop the 30-frame `restoreCodeViewHeaderAnchorAcrossLayout` loop.
  Avoid the extra `render(true)`.
- **Proof:** the existing failing browser test
  `bridge-viewer-browser.integration.browser.test.tsx` ("CodeView file header collapse preserves
  mid-viewport header position") flips red→green.

### Fix 7 — Batch selected-item hydration without mid-loop `render(true)` (fixes S3 hitch)
- **Mechanism:** keep the render coalescing Pierre already provides.
- **Change:** in the materialization effect (panel.tsx:676-859), remove the per-item synchronous
  `codeViewHandle.getInstance()?.render(true)` inside the loop for the selected item (:779);
  apply all `applyItemUpdate`s, then do at most one settle/reveal after the loop. `updateItem`'s
  queued `render()` already coalesces.
- **Proof:** browser test — hydrate a batch including the selected item; assert a single render
  pass (one layout recompute) via the existing `materializationDiagnostic`/telemetry counters.

### Fix 8 — Tree: reserve height from an exact path count (fixes S6 tree thumb churn; RC3)
- **Mechanism:** give the tree virtualizer the final row count so its scroll height is stable.
- **Change:** thread the native exact path count (currently landing only in a data attribute)
  into `useBridgeFileViewerPierreTreeRuntime` (`bridge-file-viewer-pierre-tree-runtime.ts:60-158`)
  so the tree reserves `exactPathCount × itemHeight` up front (spacer/estimated total) instead of
  growing purely from streamed `paths`. Verify `@pierre/trees` exposes a total-count / estimated-
  size input on `useFileTree`/`prepareFileTreeInput`; if it does not, reserve height with a
  sibling spacer element rather than forking the package.
- **Proof:** browser test — stream tree paths in K batches; assert the tree scroll height equals
  the final height from batch 1 (thumb length constant).

**Sequencing note:** Fixes 1-2 (heights) and 3-4 (stop fighting the anchor) are independent and
together resolve S1/S2/S3. Do 3-4 first for the biggest felt improvement, 1-2 next for thumb
stability, then 5/6/7/8. None depends on a Pierre code change.

---

## Evidence index (file:line)

- Engine scroll ownership / read+write scrollTop: `@pierre/diffs/dist/components/CodeView.js`
  :1533, :1513, :646-648; react mount `@pierre/diffs/dist/react/CodeView.js`:65.
- `setItems` dispatch: CodeView.js:558-563; `tryAppendItems`:860-879; `reconcileItems`:886-925;
  `syncItemRecord`:932-939.
- Anchor: `capturePendingLayoutAnchor`:626-629 (only caller `setOptions`:599); render-pass
  anchor:1208-1313 (:1214, :1221-1228, :1288-1290); `getScrollAnchor`:1443-1473;
  `resolveAnchoredScrollTop`:1481-1493; `scrollTo` clears anchor:494; `clearPendingScroll`:1400-1404;
  resize anchor:1405-1428.
- Height estimate/measure: `appendItemsInternal`:570-590; `recomputeLayout`:1605-1628;
  `reconcileRenderedItems`:1356-1385; defaults `@pierre/diffs/dist/constants.js`:38-47.
- App reapply + scroll fights: `bridge-code-view-panel.tsx`:505-517 (initialItems), :540-578
  (reapply + scrollToItem), :676-859 (materialization, :779 render(true), :790/:804 scrollToItem).
- App DOM anchor: `bridge-code-view-panel-support.tsx`:104-313 (:270 scrollTop mutation,
  :764-796 reconcile), budgets `bridge-code-view-panel-types.ts`:50-53.
- Options (no itemMetrics; wrap): `bridge-code-view-options.ts`:7-80.
- Materialization heights: `bridge-code-view-materialization.ts`:22, :584-601, :591, :642-653,
  :717-793.
- Guided sort (RC5): `review-projection.ts`:346-395; coalescing coordinator
  `use-review-projection-coordinator.ts`:61-62, :261-387.
- Selection hook (3rd scroll authority): `use-bridge-code-view-selection-scroll.ts`:63-198.
- Metadata interest (120ms idle → RPC): `bridge-code-view-panel.tsx`:150-171, :44;
  `bridge-app-review-metadata-interest-runtime.ts`:133-149, :219-231.
- Tree (RC3): `bridge-file-viewer-pierre-tree-runtime.ts`:54-158.
- Failing collapse test: `src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`.
```

---

## 5. Addendum — upward selection-scroll regression (5→1 fails, 5→7 works)

Reported: clicking file 5 in the tree then file 1 does **not** scroll up to file 1 (it bounces
/ lands wrong); down works (5→7). This section gives the exact mechanism, corrects the prime
hypothesis, attributes clean-HEAD vs dirty, and states the fix.

### 5.1 Call path (tree click → code-view scroll)
`tree click` → item selected → `use-bridge-code-view-selection-scroll.ts:63-198` fires →
`scrollToItem(selected, { behavior: 'instant' })` (:138-139) → `bridge-code-view-panel.tsx`
`scrollToItem` (:296-391) → `controller.scrollToItem(id, 'instant')`
(`bridge-code-view-controller.ts:56-66`, `align: 'start'`) → Pierre
`scrollTo({ type:'item', id, align:'start', behavior:'instant' })` (CodeView.js:480).

### 5.2 What Pierre does with an INSTANT item scroll (verified in source)
- `scrollTo` (CodeView.js:480-497): resolves `resolveScrollTargetTop` → `item.top` (the **current
  estimate**), sets `scrollAnimation = undefined`, **clears `pendingLayoutAnchor`** (:494), sets
  `pendingScrollTarget`, renders.
- Render pass: a big jump makes `fitPerfectly = true` (CodeView.js:1234) which **discards the
  scroll anchor** (:1235) and jumps straight to `item.top`.
- `isPendingTargetSettled` is immediately true (scrollTop == resolved top), so
  **`pendingScrollTarget` is cleared after ONE frame** (:1304-1307). Pierre stops tracking the
  target item.
- `resolveScrollTargetTop` for `type:'item'` = `item.top` = running sum of the **estimated
  heights of every item above it** (`resolveAlignedScrollPosition`:1105-1111; tops built in
  `recomputeLayout`:1605-1628). For **instant** this is evaluated once and abandoned.

**Contrast — SMOOTH is self-correcting.** For `behavior:'smooth'`/`'smooth-auto'`,
`pendingScrollTarget` persists and `computeTargetScrollTopForFrame` **re-resolves `item.top`
every frame** (CodeView.js:1151-1158), and `advanceScrollAnimation` applies `anchorDelta`
corrections (:1184-1207). This is exactly the "scroll-to-item-with-settling" behavior we bypass
by using instant.

### 5.3 Why UP is unstable and DOWN is stable (the real asymmetry)
After the jump, visible-content hydration replaces estimated heights with **measured** heights
in the **new render window**. With **no `itemMetrics`** (`options.ts` sets none) and
`overflow:'wrap'` (options.ts:15), measured > estimate → hydrating items **grow**.

- **DOWN (5→7):** landing window is around file 7. Items above file 7 stay virtualized and are
  **not** hydrated. Hydration marks `layoutDirtyIndex` at file 7 or later, so
  `recomputeLayout` rebuilds tops **from file 7 forward** (earlier items keep their tops,
  CodeView.js:1612-1616). File 7's top does not move → it stays at viewport top → **lands
  correctly.**
- **UP (5→1 / 5→3):** landing window includes the early items (file 1, 2, 3…). They hydrate and
  grow; any early item hydrating sets `layoutDirtyIndex` to a **small index**, so
  `recomputeLayout` rebuilds **every** top including the target's. The target's absolute top
  keeps **increasing across frames**. Because `pendingScrollTarget` was already cleared, Pierre
  no longer chases the target and falls back to `getScrollAnchor` = **first fully-visible item**
  (CodeView.js:1443-1473) — which, after an imperfect estimate landing, can latch onto a
  **different** item than the target. The target drifts off the top → **lands wrong.** The app's
  competing pin loops (`scrollCodeViewHeaderToScrollTopAcrossLayout`, 30-frame RAF,
  panel.tsx:665-673, and the selected-item re-scroll :778-813) fight the moving layout →
  **bounce.**

So the asymmetry is **which region hydrates after the jump**, not "which estimates the target
formula reads." Upward lands *in* the growing region; downward jumps *past* it.

### 5.4 Prime-hypothesis correction
The orchestrator's hypothesis ("upward needs accurate heights ABOVE the target; downward is
insensitive to below estimates") is **half right**. Correct: hydration growth shifts the target
and the estimate error is the magnitude. Wrong: the instant scroll's target *is* computed from
above-heights, but that value is **abandoned** after one frame — the failure is that upward
**lands in the region that then hydrates**, moving the target after settle with nothing to chase
it. The "file 1 = index 0, top=0, should be immune" objection is resolved by: (a) guided review
re-ranks order so the tree's "file 1" is usually **not** code-view index 0
(review-projection.ts:346-395); (b) even at index 0, file 1's own growth + the app pin loops +
the on-hydrate smooth reveal (panel.tsx:791) reintroduce a moving target the one-shot instant
landing mishandles.

### 5.5 Attribution: clean HEAD vs Codex dirty tree
The code-view scroll-path files (`bridge-code-view-panel.tsx`, `use-bridge-code-view-selection-
scroll.ts`, `bridge-code-view-panel-support.tsx`, `bridge-code-view-options.ts`,
`bridge-code-view-controller.ts`, `bridge-code-view-materialization.ts`) are **unmodified** in
the working tree (`git status`). The regression is therefore **pre-existing on the committed
branch** — the one-shot instant selection reveal + missing `itemMetrics`. Codex's dirty edits
are entirely content-hydration plumbing (`review-content-demand-loader.ts`,
`review-content-registry.ts`, a `visibleItemIds` passthrough in
`bridge-app-review-visible-content-controller.ts`, single-file-viewer loading gate in
`bridge-file-viewer-code-panel.tsx`) plus the ring-order prefetch pump
(`bridge-app-review-content-prefetch-controller.ts`, warms outward from the cursor). Those can
**amplify** the instability (they hydrate more items around the cursor, including above it) but
did **not** create the asymmetry. (Read-only: no build A/B; the unmodified scroll path is the
proof.)

### 5.6 Fix directive
1. **Accurate `itemMetrics` (report Fix 1 / Codex Fix 1).** Set `itemMetrics` on
   `bridgeCodeViewOptions` (`lineHeight`, `diffHeaderHeight`≈header min-height, `spacing`) to
   match rendered CSS. Shrinks estimate error → less growth → smaller target shift. **Necessary,
   not sufficient** (wrap keeps exact estimation impossible).
2. **Re-targeting reveal (NEW — not covered by Codex's current plan).** Replace the one-shot
   `instant` selection scroll with a scroll that keeps resolving the target **by item id** until
   layout is stable and the target header sits at viewport top within epsilon. Options, both
   integration-level (Pierre already supports the primitive):
   - Use Pierre's persistent re-targeting: issue the reveal as `smooth-auto`, or re-issue
     `controller.scrollToItem(target,'instant')` on each hydration/layout-dirty event, until
     `getTopForItem(target)` stabilizes and the target header offset < epsilon, bounded by a
     frame budget. During this window, set Pierre's anchor to the **target** so growth above it is
     absorbed by keeping the target pinned.
   - Remove the competing app pin loops from the reveal path (report Fix 4) so a **single**
     authority drives scroll.
3. **Coverage vs Codex's plan:** Fix 1 (itemMetrics) reduces magnitude; Fix 4 (remove duplicate
   DOM anchor) removes the bounce. **Missing from Codex's plan:** the explicit re-targeting
   reveal — Fixes 3 (gate `scrollToItem` to selection-change) and 6 (collapse anchor) do not
   address the post-settle target drift. Add it as Fix 9.

### 5.7 Browser-test proof spec
- Fixture: ≥8 items with varied, known line counts (some large enough that estimate ≠ measured
  under wrap), content loadable on demand.
- **DOWN guard:** select item 5, settle, select item 7; after a bounded stable-scroll wait,
  assert item 7's header top is within ε (≤2px) of the scroll-owner top.
- **UP target:** select item 5, settle, select item 1 (and, separately, item 3); after settle,
  assert the target header top is within ε of the scroll-owner top, **and** sample scrollTop
  across settle frames to assert it converges monotonically (no oscillation beyond ε) — this
  catches the bounce.
- Assert the target's `data-bridge-code-view-item-id` header is the first fully-visible item
  after settle; assert `selectionScrollDiagnostic` reason resolves to `hydrated` / `didScroll`
  true (data attrs at `bridge-code-view-panel-frame.tsx:88-99`).
- Expected: red on current HEAD (UP bounces/lands wrong), green after itemMetrics + re-targeting
  reveal.

### 5.8 Evidence index (addendum)
- Instant one-shot + settle-clear: CodeView.js:480-497 (:494 anchor clear), :1234-1235
  (fitPerfectly discards anchor), :1304-1307 (settle clears pendingScrollTarget),
  `isPendingTargetSettled`:1525-1528.
- Item-top from above estimates: `resolveScrollTargetTop`:1074-1084;
  `resolveAlignedScrollPosition`:1105-1111; `recomputeLayout`:1605-1628.
- Smooth re-targets each frame: `computeTargetScrollTopForFrame`:1151-1158;
  `advanceScrollAnimation`:1184-1207.
- Anchor = first fully-visible: `getScrollAnchor`:1443-1473.
- Selection reveal uses instant: `use-bridge-code-view-selection-scroll.ts`:138-139;
  `bridge-code-view-controller.ts`:56-66 (`align:'start'`).
- App pin loops on reveal: `bridge-code-view-panel.tsx`:665-673, :778-813;
  `bridge-code-view-panel-support.tsx`:201-272.
- Ring-order prefetch (amplifier): `review-content-prefetch-policy.ts`:49-80;
  `bridge-app-review-content-prefetch-controller.ts`.
- Scroll path unmodified (attribution): `git status` clean for
  `BridgeWeb/src/review-viewer/code-view/`.
