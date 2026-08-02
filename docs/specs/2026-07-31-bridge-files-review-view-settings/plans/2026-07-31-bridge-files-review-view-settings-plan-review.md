# Bridge Files and Review View Settings Plan Review

Date: 2026-07-31

Target: `2026-07-31-bridge-files-review-view-settings-implementation.md`

## Verdict

Ready for implementation validation and execution.

The current plan covers UR-01–UR-25 through six vertical slices, preserves the
accepted native/web ownership boundaries, requires slice-local red/green proof,
and separates native integration from packaged WKWebView proof where the
packaged harness cannot directly drive CWD retargeting.

No blocker, unresolved important finding, or implementation-changing question
remains. Platform feasibility for the empty WebKit context menu, stable target
binding, and mounted Pierre option updates remains intentionally guarded by
explicit design-break proof gates.

## Coverage

- Entire implementation plan read and reviewed.
- Entire current requirements and program design used as accepted authority.
- Current source re-anchored for topology, controller, product-session,
  metadata/source/publication, BridgeWeb surface owners, typed commands, test
  owners, and packaged journey behavior.
- Review lanes:
  - whole-plan-cohesion — Codex subagent, high reasoning;
  - architecture-assumptions and security-reliability — Codex subagent, high
    reasoning;
  - validation/proof — planning lane plus parent verification of current
    commands and harness limits.
- No external model lane was requested.

## Accepted findings and remediation

1. Hidden target authorities were under-enumerated.
   - Added a target-sensitive call-site cutover ledger covering invalidation,
     initial/retry loading, IPC refresh, repo/endpoint/baseline selection.
   - Added a negative scan forbidding post-installation target decisions from
     `runtime.metadata` or `bridgePaneState.source`.

2. Close-wins interleavings were incomplete.
   - Added close before acknowledgement, between acknowledgement/open, during
     W→X→Y drains, and apply-after-close cases.
   - Made close terminal at the same controller ordering boundary as target
     application, with a zero-residue gate.

3. Proposed parallel lanes shared current write owners.
   - Serialized Files/Review surface integration.
   - Reserved surface shells and semantic listeners for the parent.
   - Reserved binding/controller/session internals for one native owner.
   - Split host/command-catalog Reload work from post-4D controller routing.
   - Required a pre-dispatch path-level write ownership ledger.

4. Lifecycle proof omitted material user-visible transitions.
   - Added same-worktree logical selection identity, different-worktree
     matching-path clearing, inactive-surface reset, authority-loss transient
     closure/focus fallback, post-edge edit retention, cancellation, bounded
     reasons, and a complete visible-state truth table.

5. The visible indicator vocabulary used the renderer token `classic`.
   - Corrected visible product copy to Bars, Symbols, None while retaining the
     internal `bars | classic | none` mapping.

6. Keyboard, accessibility, focus, and pane-isolation proof was too generic.
   - Added keyboard-only menu operation/dismissal, accessible names/states,
     filter-exclusion focus fallback, invalid/oversized announcements,
     authority-loss focus restoration, and two-pane View Settings isolation.

7. UR-23/UR-24 lacked two regression gates.
   - Added command-description proof that Reload does not imply native source
     refresh.
   - Added typed Management Layer `⌘R` executes-once/no-navigation proof.

8. The first plan draft overstated the packaged journey's retarget reach.
   - Native integration now owns A→B→null and stable controller/`WebPage`
     identity.
   - The packaged journey owns real initial registered-source and WKWebView
     behavior. No test-only CWD mutation API is planned.

## Rejected or deferred feedback

- Digest and pair-review bookkeeping was intentionally not reopened, per the
  user's explicit instruction.
- Prior stale specification-review findings were not used to redesign accepted
  product meaning.
- No fixture-only substitute, browser-side source authority, host replacement,
  custom Reload lifecycle, or compatibility path was accepted.

## Final recheck

The architecture/reliability reviewer confirmed the target-authority cutover,
close-wins races, and path ownership were resolved. The whole-plan reviewer
confirmed lifecycle, parallel ownership, visible Symbols mapping,
keyboard/accessibility/pane-isolation proof, and Reload regressions were
resolved; its final narrow authority-loss focus gap was then added to Slice 4C
and packaged proof.

Implementation has not started as part of this review.
