# Annotation live UX and reliability debugging

Updated: 2026-09-03 07:16 America/Toronto

## Current objective

Make the composed Vite/Swift annotation journey reliable and visually intentional across create, save, reply, edit, cancel, worktree refresh, Share, reload, and restart. Preserve the transport ownership boundary: diagnose through it, but do not redesign or modify main/worker/native transport without an explicit owner decision.

## Current task ledger

- [x] Reproduce and trace the post-Save/post-Cancel focus handoff.
- [x] Add browser REDs proving keyboard ownership without the accidental outer focus rectangle.
- [x] Reproduce saved annotations disappearing from inline Review while remaining durable.
- [x] Identify native placement materialization as the first data-model owner that substitutes `unavailable` for otherwise retained annotations.
- [ ] Add a deterministic browser or composed E2E RED for retained annotations through refresh.
- [ ] Implement only the proven focus and refresh-continuity corrections.
- [ ] Run focused unit/browser/E2E gates and composed Chrome visual proof.
- [ ] Run the applicable BridgeWeb quality gate, commit the coherent checkpoint, and report unrelated blockers separately.

Current evidence notes:

- The root composer explicitly focuses its temporary committed preview after an exact Save receipt (`worktree-annotation-composer.tsx`), and saved-thread activation can then focus the outer thread frame. Both targets are programmatically focusable but expose browser-default focus paint.
- The annotation projection store itself retains threads while marked `refreshing`; therefore the disappearance is not yet attributable to `markRefreshing`. Remaining candidate seams are catalog replacement filtering, Review publication/shell replacement, and Pierre annotation reapplication.
- A same-worktree background refresh must retain the last committed presentation. Source/target replacement remains a separate foreground transformation contract.
- A clean composed runtime saved `Refresh continuity proof annotation` and transferred keyboard ownership to the installed thread with `outline-style: none`; a continuous DOM probe is armed before the next ordinary worktree edit.
- Focus RED: `worktree-annotation-range-selection.browser.test.tsx` received `outline-style: auto` for the exact committed preview; the saved-message focus test exposed the same default-outline family on the retained thread owner. GREEN: both focused files pass, 3/3 tests.
- An unrelated ordinary WIP edit retained the existing inline annotation continuously: minimum thread count 1, body never absent, selected content remained `ready`.
- A later source transition left both saved messages durable (`Share: Pending 2 / All 2`) but inline Review rendered zero threads. Read-only `local.sqlite` inspection proved both messages belong to the same living applicable session.
- The exact stored output snapshot classified both threads as `placement.status = unavailable`, including the unchanged and still-present WIP source.
- Root cause: `WorktreeAnnotationSourceCapture.reviewRefresh` builds one source-material batch for all thread requirements. A retired handle/path may widen relocation search across Review candidates; `reviewMaterial` returns global `.unavailable` when any candidate cannot be loaded. `WorktreeAnnotationSourceEvaluator` then marks every thread unavailable because the material type cannot represent per-thread or per-candidate failure.
- This is a data-model break rather than a safe one-line UI correction. Skipping failed candidates would misclassify an exact-but-unreadable source as outdated; disabling relocation search would prevent valid renamed annotations from becoming relocated.

## Live environment

- Branch: `bridge-review-design-2026-08-14`
- Current checkpoint: `4f51dbc5e`
- Composed server: `pnpm --dir BridgeWeb run dev`
- URL: `http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree`
- Health: HTTP 200
- Chrome: current-worktree Review rendered and retained for manual testing
- Concurrent files not owned by this investigation:
  - `docs/specs/2026-09-03-incremental-review-git-refresh/*`
  - `docs/wip/2026-09-03-bridge-transport-annotation-git-review.md`

## Issue tree

### A. Command settlement — blocker

Symptom:

- Creating a Review annotation opens the composer and focuses the Markdown textbox.
- Entering a body works.
- `Command+Enter` and the Save button fail.
- The editor remains open with the raw alert: `Bridge comm worker failed to forward review.annotations.command.`

Expected:

- Exact command receipt settles the save.
- Saved annotation remains visible.
- Editor closes while the annotation thread remains the keyboard owner.
- No internal transport terminology reaches the reviewer.

Evidence:

- Reproduced manually in real Chrome against the composed Vite/Swift server.
- Browser console contains no surfaced error.
- No HTTP command request was observed after pre-arming Chrome network events, which places the first known divergence at or before worker product-control forwarding.

Next proof:

1. Inspect worker degraded-health event and product-control dispatch failure path.
2. Determine whether Review publication identity is absent/stale, the command sender is uninstalled, or the product call is rejected.
3. If the cause is UI command construction or stale projection identity, fix in this lane.
4. If the cause is main↔worker or worker↔Swift transport, return an exact handoff to the transport owner before edits.

### B. Refresh continuity — blocker

Symptom:

- When the worktree changes, visible annotations disappear and later reappear.
- A related exact-final E2E observation showed a File replacement become ready, then a later invalidation returned it to `loading` with no rendered path/content for 120 seconds.

Expected:

- A background refresh retains the last committed annotation projection.
- The surface may show an updating affordance, but annotations do not blink out.
- The successor projection replaces the old projection atomically when ready.
- Source-unavailable or invalidated annotations use an explicit unavailable/detached presentation rather than disappearing silently.

Known distinction:

- Normal same-worktree refresh is background continuity.
- Source/target changes and promoted large semantic changes may justify a foreground transformation surface.
- Current behavior appears to conflate refresh-in-progress with absence of authoritative annotation state.

Next proof:

1. Reproduce with one saved annotation and one controlled worktree edit.
2. Capture projection-store state, catalog authority, refresh state, rendered annotation count, and Review publication identity before/during/after refresh.
3. Locate the first transition that clears committed annotations.
4. Add a deterministic browser test requiring retained annotations through refresh handoff.

### C. Post-editor focus visualization — important

Symptom:

- After Save or Revert closes an annotation editor, Chrome draws a large purple focus rectangle around the entire message grid, including metadata/avatar space.

Cause:

- `finishThreadEditor` / `exitThreadEditor` restore keyboard focus to the annotation message.
- The message is programmatically focusable with `tabIndex={-1}`.
- The outer message surface has no intentional focus presentation, so the browser default outline is exposed.

Expected:

- Keep annotation/thread keyboard ownership so `R`, `Control+R`, and `Control+E` remain available.
- Pointer Save/Revert must not look like a selected purple box.
- Keyboard-only focus must remain visible, but on the inner message surface with the product's intentional focus token—not around the whole grid.
- Existing active-thread tint remains the primary persistent context signal.

Required proof:

- Browser test for focus owner after Save and Revert.
- Browser test distinguishing pointer versus keyboard focus presentation.
- Visual Chrome screenshot after each transition.

### D. Visual quality notes — important, after blockers

- The composer itself uses the intended inset edit ring and spacing reasonably well.
- Save/Revert icons are low contrast in the empty/disabled and error states.
- The Pierre add-annotation button is exposed as an unnamed button in the accessibility snapshot; confirm whether the host can supply an accessible label without forking Pierre behavior.
- The raw forwarding error is implementation language, not reviewer-facing recovery copy.

## Proof status

- Focused File annotation Vite→Swift→SQLite E2E: passed before the live manual failure.
- Full BridgeWeb gate: one current green run before the second Review-admission remediation.
- Exact Review invalidation admission regression: RED then GREEN.
- Initial Review load suite: 19/19 green before the regression was moved into the refresh-admission suite.
- Moved exact regression: 1/1 green.
- Scoped Swift format, SwiftLint, and architecture lint: green.
- Exact-final BridgeWeb gate: blocked by repeated File refresh/deep-scroll failure.
- Repo-wide SwiftLint: blocked by four unrelated legacy SwiftUI aspect-ratio violations outside this diff.
- Packaged three-launch / 100-attempt latency proof: not run and not claimed.

## Checkpoints

- `4f51dbc5e` — Review startup admission, worker authority retirement, exact annotation output/lifecycle E2E diagnostics, completed-session stress fixture, and File-invalidation initial-Review guard.
- Push of `4f51dbc5e` was not performed because the external-transfer safety gate rejected it.

## Stop and ownership rules

- Do not weaken assertions, increase timeouts, or hide transient states.
- Do not modify transport message schemas or main↔worker↔Swift delivery without explicit authority.
- Do not stage or commit the concurrent incremental-refresh design documents.
- If source evidence shows the live Save failure is transport-owned, produce the exact failing request/identity/outcome handoff and continue UI/retention work independently.
