# Bridge Review Refresh Classification — Specification

Date: 2026-08-21

Governing requirements:
[2026-08-21-requirements.md](./2026-08-21-requirements.md).

Program realization:
[2026-08-21-program-design.md](./2026-08-21-program-design.md).

## Observable model

Bridge has one Review replacement pipeline and two presentation classes for
same-source updates:

```text
source invalidation
      |
      v
compute and validate newest complete Review
      |
      +-- ordinary --> no global bar; normal installation
      |
      `-- promoted --> stable update bar; completed swap may be held
```

Initial load and an explicit comparison-target command are not same-source
classification cases. Initial load uses `Loading review…`. Target replacement
uses the existing comparison control’s loading feedback and no promoted global
bar.

A same-source update stays within the same worktree lineage and preserves the
current comparison-target selection. A changed target selection is an explicit
target replacement even when it resolves within the same worktree.

## Normative requirements

### R-RRC-001 — One replacement pipeline

Ordinary and promoted updates MUST use the same comparison computation,
latest-generation authority, validation, and failure path. Presentation class
MUST NOT create a second Review result or source of truth.

Basis: U-RRC-001, U-RRC-002, U-RRC-003.

### R-RRC-002 — Same-source classification

For a same-source replacement with a last complete displayed Review, Bridge
MUST classify the candidate as ordinary or promoted before that candidate may
change visible Review geometry.

Bridge MUST promote when any incoming-delta fact reaches:

- newly imported commits greater than or equal to 10;
- affected files greater than or equal to 25;
- added plus deleted lines greater than or equal to 1,000.

The facts MUST describe change between the displayed Review source and the
incoming candidate source, not the candidate Review’s total size. A candidate
MUST also promote when direct installation cannot preserve an active editor’s
source anchor. Promotion is monotonic for one candidate generation.

Every successor MUST classify against the Review actually displayed when that
successor is admitted, even when another candidate is already committed,
provisional, or held. If Bridge cannot establish that exact displayed base, it
MUST classify the successor as promoted rather than silently install an
under-measured replacement.

Immediately before visible installation, Bridge MUST admit a candidate only
when the expected displayed publication still matches and that candidate is the
newest native-complete publication at the admission point. Admission is the
installation linearization point: a publication completing afterward is a new
successor and does not retroactively invalidate the admitted installation.

A fresh main product session whose presentation bank is empty MAY use a null
displayed predecessor to bootstrap only the newest native-complete publication
when that product session has not yet established a displayed Review. Native
MUST retain the previously acknowledged displayed publication until the fresh
session applies its bootstrap publication. After that first applied receipt,
every installation in the session MUST use the exact displayed predecessor.
This bootstrap rule MUST NOT apply to an existing main session that retains an
active Review across worker replacement.

If complete impact classification cannot be obtained, Bridge MUST continue the
replacement and conservatively use promoted presentation.

Basis: U-RRC-003, U-RRC-004, U-RRC-008.

### R-RRC-003 — Ordinary presentation

An ordinary same-source update MUST:

- compute in the background;
- show no global update bar;
- install through the normal Review presentation path when complete and
  current;
- preserve active comment editor state and commands across installation.

Ordinary presentation MUST NOT wait merely because a file is selected, a
thread is expanded, or retained content has focus.

If an ordinary successor completes while an older promoted candidate is held,
the ordinary successor MUST release that older candidate and its bar, then
install normally. It MUST NOT inherit the older candidate’s promoted class.

Basis: U-RRC-001, U-RRC-002, U-RRC-004.

### R-RRC-004 — Promoted presentation

While a promoted candidate computes and an affected Review context remains the
reviewer’s semantic focus, Bridge MUST keep the displayed Review fully
interactive and show stable chrome with the text `Updating…`. If the reviewer
leaves every affected context before the candidate is complete, the bar MUST
clear and the candidate MUST install automatically when complete.

When the newest promoted candidate is complete:

- if no affected context remains the reviewer’s semantic focus, Bridge MUST
  install it automatically without showing `Update ready`;
- if an affected context remains focused, Bridge MUST retain the displayed
  Review, stage only that newest complete candidate, and show `Update ready`
  with an `Apply now` action.

The bar MUST remain outside the file tree and diff flow. It MUST NOT insert a
loading row, move the retained Review, or obscure comment controls.

Basis: U-RRC-001, U-RRC-003, U-RRC-006, U-RRC-007.

### R-RRC-005 — Affected context and semantic focus

Affectedness is judged at stable file granularity. A file is affected when its
stable identity participates in the displayed-to-candidate change set; renames
and deletions MUST include the identities needed to match both the displayed and
candidate sides. Annotation threads, editors, ranges, related commands, and
reading position inherit the affectedness of their owning file.

An affected Review context is an affected file or one of those file-owned
contexts that currently owns Review attention through selection, active range
interaction, an open editor, an in-flight related comment command, or the current
Review reading position.

The reading position belongs to the Review item whose content crosses the
leading edge of the scroll viewport immediately below fixed Review chrome. If
the edge falls between items, the nearest following visible Review item owns
the position. If no Review item is visible, reading position contributes no
focused context. Visibility elsewhere in the viewport does not by itself own
the reading position.

Semantic focus remains on that context across ordinary DOM blur, clicks on
Save, Share, or other controls serving the same context, and temporary app or
window deactivation. Semantic focus leaves when the reviewer selects a different
unaffected file, switches File/Review mode, switches pane or tab, or closes the
Review.

Partially visible unrelated files, expanded inactive threads, hover, and
ordinary focus on unrelated chrome MUST NOT hold a promoted candidate.

Affected-context focus holds only promoted presentation installation. It MUST
NOT stop computation, persistence, commands, scrolling, selection, commenting,
replying, editing, resolution, Share, Copy, or Export.

Basis: U-RRC-001, U-RRC-003, U-RRC-004.

### R-RRC-006 — Apply now

`Apply now` MUST request installation of the newest complete promoted candidate
without waiting for semantic focus to leave the affected context. The action
MUST preserve the current editor body, edit identity, durable draft state, and
in-flight command settlement. After installation, ordinary annotation placement
evaluation MUST classify the active anchor as exact, relocated, outdated, or
unavailable.

If editor continuity cannot be preserved, Bridge MUST retain the current Review
and expose the preservation failure; it MUST NOT lose the draft or partially
install the candidate.

Basis: U-RRC-004, U-RRC-005, U-RRC-007.

### R-RRC-007 — Comment continuity and anchor truth

Every Review interaction available before refresh MUST remain available during
ordinary and promoted computation. A new root comment created during refresh
MUST use the source identity and source evidence of the Review actually shown
to the reviewer.

After any replacement installs, Bridge MUST re-evaluate immutable comment
origins against the new current material. A comment MUST NOT silently retain an
old coordinate as current when exact or relocated placement cannot be proven.

Until a replacement installs, annotation projection, placement evaluation, new
root-comment source validation, and Share output fencing MUST continue using
the identity, generation, and material of the Review actually displayed. A
committed but uninstalled candidate MUST NOT advance those annotation surfaces.

Basis: U-RRC-001, U-RRC-004, U-RRC-005.

### R-RRC-008 — Latest complete candidate

At most one non-visible candidate Review may be retained beside the active
Review. That one candidate may be provisional for editor-continuity validation
or held as update-ready, but never both at once. A newer applicable candidate
MUST supersede and release the older candidate. A stale, cancelled, partial,
malformed, or failed candidate MUST NOT install or replace the last complete
Review.

Basis: U-RRC-006, U-RRC-008.

### R-RRC-009 — Completion and failure

Successful installation MUST be atomic from the reviewer’s perspective: Review
source identity, ordered files, visible diff geometry, selection reconciliation,
and refresh chrome MUST describe one current candidate.

If install admission or displayed acknowledgment cannot establish one exact
displayed source, Bridge MUST retain the currently displayed Review and its
annotation authority, discard or retry the incomplete coordination without
partial installation, and conservatively promote successor classification until
the displayed source is re-established.

After main installs an admitted publication, it MUST acknowledge that exact
publication through an idempotent applied receipt. A delayed or lost receipt
MUST NOT roll back the visible Review or make annotation work use another
publication; it may only prolong conservative promotion and source retention.

Replacing the complete browser document MUST NOT strand Review presentation
when native still acknowledges the prior document's displayed publication. The
fresh document MUST bootstrap the newest complete publication through the same
installation and applied-receipt path, while the prior displayed material
remains retained until that receipt.

If a promoted replacement fails, Bridge MUST discard its candidate and retain
the last complete Review. While an affected context remains the reviewer’s
semantic focus, Bridge MUST show `Update unavailable` and expose `Retry` only
when the underlying failure is retryable. Without affected semantic focus, the
global bar MUST remain absent and the failure MUST use the existing non-global
refresh outcome. Safe Review and comment interactions MUST remain available.

Basis: U-RRC-001, U-RRC-008.

### R-RRC-010 — Initial and commanded replacement text

The following messages and locations are authoritative:

- first load with no last complete Review: `Loading review…` in the normal
  loading presentation;
- explicit target replacement: existing comparison-control loading feedback;
- promoted same-source computation while an affected context remains focused:
  global `Updating…` bar;
- promoted candidate held for an affected focused context: global
  `Update ready` bar with `Apply now`;
- promoted replacement failure while an affected context remains focused:
  global `Update unavailable` bar with retry when eligible.

An ordinary background update MUST not show the global bar.

Basis: U-RRC-002, U-RRC-003, U-RRC-007, U-RRC-008.

### R-RRC-011 — Accessibility and motion

Refresh chrome MUST expose its status through an accessible live status without
repeated announcements for unchanged state. `Apply now` and `Retry` MUST be
keyboard reachable and retain visible focus behavior. Installation MUST honor
reduced-motion preferences and MUST NOT force focus into the update bar.

Basis: U-RRC-001, U-RRC-003, U-RRC-007.

### R-RRC-012 — Boundedness and evidence

Impact classification and candidate retention MUST be lineage-fenced and
bounded. The system MUST retain no more than the active Review and one newest
non-visible candidate Review, and MUST release that candidate on installation,
supersession, failure, close, or worker replacement.

Supporting source authority MAY temporarily retain the acknowledged displayed,
one install-admitted, and newest native-current publications when those
identities differ. It MUST release any superseded publication that is neither
displayed, install-admitted, native-current, nor protected by an in-flight source
lease. This source retention MUST NOT create another presentation bank.

Scrubbed operational evidence MUST distinguish ordinary from promoted,
promotion reason, candidate ready, held, apply-now, automatic install,
supersession, failure, and terminal cleanup without exporting paths, comment
bodies, selected text, or source content.

Basis: U-RRC-006, U-RRC-008.

## State relationships

```text
ordinary:
  active(A) -> computing(B) -> admit(A, B) -> active(B) | active(A)+failure

promoted:
  active(A)
    -> updating(A, B)
    -> admit(A, B) -> active(B)          when focus has left affected context
    -> updateReady(A, B)                 while affected context remains focused
         -> admit(A, B) -> active(B)     focus leaves or Apply now
         -> updateReady(A, C)            newer complete C supersedes B
         -> active(C)                    newer ordinary C installs and releases B
         -> active(A)+failure            candidate fails
```

## Boundary examples

- A 24-file, 999-line, 9-commit update with stable active anchors is ordinary.
- Reaching any one numeric limit promotes.
- A small update that removes the file containing an active composer promotes.
- A promoted update affecting the currently focused file stages; selecting an
  unaffected file releases it automatically.
- A successor always measures from the displayed Review. If ordinary C
  supersedes held B while A remains displayed, C installs normally and releases
  B rather than inheriting B’s bar.
- Clicking Save or temporarily switching to another app does not release a
  held update for the same Review context.
- A 1,001-line generated-file update still promotes; the thresholds are
  conservative disruption policy, not proof that every anchor moved.
- A large initial load uses normal loading, because no previous Review exists to
  retain or hold.
- A user-selected target replacement uses comparison-control feedback, not the
  promoted same-source bar.

## Proof obligations

- V-RRC-001 automated behavior: threshold boundaries, conservative fallback,
  monotonic promotion, and ordinary/promoted classification.
- V-RRC-002 automated state/interleaving: affected-context focus before/after
  candidate readiness, semantic focus changes, Apply now, multiple completed
  candidates including completion immediately before and after install
  admission, an ordinary successor to a held candidate, delayed/lost applied
  receipt, stale late arrival, close, worker replacement with a retained main
  bank, and full document replacement with an empty fresh main bank.
- V-RRC-003 automated integration: one real update pipeline feeds both
  presentation classes; ordinary has no bar; promoted presentation holds only
  the display swap.
- V-RRC-004 real persistence and source evaluation: comments authored during
  refresh remain fenced to the displayed generation, survive replacement, and
  become exact, relocated, outdated, or unavailable without body or edit-token
  loss.
- V-RRC-005 browser/manual interaction: typing, replying, scrolling, selecting,
  Share/Copy/Export, Apply now, focus, reduced motion, and stable geometry.
- V-RRC-006 operational evidence: marker-scoped lifecycle shows classification,
  hold, supersession, installation, and cleanup with source-scrubbed attributes.

## Negative space

This contract does not define a second refresh engine, command-cause detection,
cross-pane global interaction state, a durable candidate history, timeout-forced
installation, progressive promoted display, or new annotation placement states.
