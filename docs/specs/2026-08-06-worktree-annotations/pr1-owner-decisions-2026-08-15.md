# PR1 Owner Decisions — 2026-08-15 pathfinding session

Return owners: deletion (D3), sidebar/finish-warning (D4), session-creation
(D5), and batch-save (D6) amend
[`pr1-user-requirements.md`](./pr1-user-requirements.md) /
[`pr1-specification.md`](./pr1-specification.md) via spec-design. The loss
posture (D1) is an owner tolerance returned to
[`pr1-program-design.md`](./pr1-program-design.md) via program-design.
Session identity (D2) returns to BOTH owners: spec-design amends the
requirements/spec meaning (a session is worktree-owned), and program-design
amends the durable key and discovery scope in
[`pr1-program-design.md`](./pr1-program-design.md) to match.

## D1 — Annotation loss posture on local.sqlite corruption

- decision: Annotation history fails closed and holds data. On local.sqlite
  corruption the annotation feature reports itself unavailable/degraded, the
  reviewer is told, and quarantined bytes are preserved for recovery. UX/cache
  lanes keep today's default-and-continue behavior. No silent empty annotation
  state, ever.
- why: Annotation threads are irreplaceable human work product; a fresh empty
  database indistinguishable from "no annotations yet" is unacceptable loss.
- alternatives: best-effort like UX lanes (rejected — silent-looking loss);
  authoritative core-tier storage (rejected — couples annotation health to the
  boot-critical tier and widens core schema ownership).
- consequences: Program design must reconcile "existing quarantine policy
  remains authoritative" with "never publish an empty replacement" — the local
  recovery contract needs an annotation-lane amendment. The existing
  `PersistenceRecoveryReporter` seam (AppDelegate persistence recovery events)
  is evidence the tolerance is satisfiable; mechanism choice stays with
  program-design. The spec side also needs one reconciliation via spec-design:
  the reliability obligation currently promises both "never publish a
  fabricated empty replacement" and "existing durable recovery/quarantine
  policy remains authoritative" — D1 resolves that pair in favor of
  fail-closed-and-tell-the-reviewer, and the spec clause must say so.
- status: accepted

## D2 — Session identity is worktree-owned

- decision: One living review round is keyed by the worktree (stable
  repo/worktree lineage), not by workspace. The same worktree opened from any
  workspace resumes the same session. Workspace is recorded as provenance at
  most.
- why: P1-U1 already defines the session as one review round in one selected
  worktree; the workspace in the program design's key was storage-convention
  leakage, not product meaning.
- alternatives: `(workspaceId, worktreeId, sessionId)` as currently written
  (rejected — strands or duplicates living rounds across workspaces).
- consequences: Program design's durable key and discovery scope change to
  worktree lineage. Precedent exists: `local_entity_recency` is already an
  application-global table in local.sqlite.
- status: accepted

## D3 — Unresolved comments can be deleted

- decision: Deletion is governed by resolution state — unresolved (open)
  comments are deletable. (Owner's words: "unresolved comments can be
  deleted.")
- why: An open comment is still the reviewer's live work and may be retracted;
  resolution marks the record worth keeping.
- alternatives: no deletion ever (rejected — wrong-file threads stay
  output-eligible forever); delete-until-first-output (superseded by the
  resolution-state rule).
- consequences: Requirements gain a deletion need; spec gains delete
  requirements and output-eligibility interaction.
- edges resolved 2026-08-15: deletion operates on whole open threads only —
  individual saved replies are never deleted from a surviving thread. An open
  thread remains deletable even when a prior output batch included its
  messages; the immutable output event/batch history still proves exactly what
  was handed off. Resolved threads are not deletable.
- scope moved 2026-08-15: owner moved deletion out of PR1 into PR2 under the
  keep-it-simple boundary. PR1 ships with no deletion (wrong threads are
  resolved-as-nevermind until PR2). The semantics above stand as the accepted
  PR2 requirement, not a PR1 obligation.
- status: accepted; deferred to PR2

## D4 — Comment sidebar is a follow-up PR

- decision: The thread/comment sidebar (session-wide navigation surface) is
  explicitly a follow-up PR, not PR1 scope.
- why: Owner call this session; consistent with the requirements' existing
  "separate navigation surface may be considered only after the inline
  workflow is proven".
- consequences: PR1 keeps inline-only presentation; spec-design amends the
  requirements/spec presentation and finish-warning language.
- residual resolved 2026-08-15: the PR1 finish warning shows a count only
  ("N threads remain open") with confirm/cancel. Thread navigation arrives
  with the sidebar follow-up PR.
- status: accepted

## D5 — Implicit session creation on first annotation

- decision: When zero applicable sessions exist, the reviewer's first
  annotation creates the session in the same motion — no separate create
  ceremony. An explicit choice is still required when several applicable
  sessions exist, and P1-U13's rule against inferring among existing sessions
  is unchanged.
- why: The cheapest entry to the loop must not have a toll booth; the
  never-infer rule targets choosing among existing sessions, not creation
  from zero.
- consequences: Requirements/spec language for P1-U13 / R-P1-001 gains the
  zero-session implicit-creation path.
- status: accepted

## D6 — No batch save; per-message Save stands

- decision: There is no save-all-drafts affordance in PR1. Save remains an
  explicit per-message action and the only readiness boundary for output
  selection.
- why: Owner keeps PR1 simple; Save-as-intent stays maximally explicit.
- consequences: End-of-round handoff requires saving each draft individually;
  acceptable friction for PR1. Spec-design records this as confirmed negative
  space so it is not re-proposed as a gap.
- status: accepted

## Goal-boundary constraint — keep PR1 simple

- Owner directive (2026-08-15): PR1 already carries a lot; prefer the simple
  shape wherever a decision has a cheaper variant. This is the rationale
  behind D4's count-only warning, D6's no-batch-save, and the sidebar
  deferral. Follow-up PRs (sidebar first) own the deferred affordances.

## Verified observables (2026-08-15, Luna @ 9fd625d9b)

- Pierre 1.2.10 annotation surface: confirmed complete. `LineAnnotation`
  (`types.d.ts:345`), `DiffLineAnnotation` (`types.d.ts:348`),
  `renderAnnotation` (`react/CodeView.d.ts:21`), `updateItem` (`:36`),
  `scrollTo` (`:38`), `setSelectedLines` (`:39`), `onGutterUtilityClick`
  (`managers/InteractionManager.d.ts:40`), `onLineSelectionEnd` (`:54`).
  The program design's Pierre claims hold as written.
- Markdown source map: NOT FOUND in current code. The worker renders via
  `markdown-exit` + Shiki (`bridge-markdown-render-worker-renderer.ts:75-101`)
  and sanitizes via DOMPurify (`bridge-markdown-preview.tsx:32-81`) with no
  span-ID, sourcepos, or source-line mechanism. The design's
  `WorktreeAnnotationMarkdownSourceMap` + sanitizer span-attribute
  preservation + selection mapper is an entirely new subsystem, not an
  extension of existing machinery.

## D7 — Rendered-Markdown selection anchoring deferred

- decision: PR1 anchors located threads through Pierre code/diff line
  selection only. Rendered-Markdown preview selection ("select in the pretty
  preview, resolve to source lines") is deferred to a follow-up PR. Markdown
  files remain annotatable in their source/diff presentation.
- why: Luna verified no source-map foundation exists — the design's
  `WorktreeAnnotationMarkdownSourceMap`, sanitizer span-attribute
  preservation, and selection mapper would be an entirely new subsystem;
  owner's keep-it-simple boundary cuts it from PR1.
- consequences: spec-design narrows P1-U5 / R-P1-002 (rendered-selection
  mapping moves to negative space with the follow-up noted); program-design
  drops the Markdown source-map/mapper components from PR1 scope.
- status: accepted

## Open items

- none — all owner decisions for this session are resolved.
