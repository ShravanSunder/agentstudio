# Bridge Architecture Doc Reconciliation: Retire DiffManifest Vocabulary (Task 0 Debt)

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The master plan's Task 0 promised "Update docs:
`docs/architecture/swift_react_bridge_design.md`" alongside the vocabulary
cutover. The code cutover is complete — zero `DiffManifest` references in
Sources/ (parent-verified) — but the architecture doc still teaches the
retired model in **11 places**, including the foundational State Ownership
table (§3.1), the domain model sections (§8.2/8.3), and the content-delivery
walkthrough (§10.1) with a literal code sample constructing a type that does
not exist. Anyone onboarding LUNA-338 (Pierre viewer) from this doc will build
the wrong mental model; the spec explicitly bans reintroducing this
vocabulary.

The retired-plan pointer chain is otherwise healthy: the February plan is
properly tombstoned, the spec is canonical, and the sibling Git data-plane
plan's ownership boundary language was audited clean (no Bridge contracts
defined there). This is a single-document debt.

## Current Evidence

- `grep -c "DiffManifest" docs/architecture/swift_react_bridge_design.md` →
  11 (parent-verified); `grep -rn "DiffManifest" Sources/` → 0.
- Stale locations (audit lane, line-cited): §3.1 tier table (~line 74:
  "DiffManifest: file metadata as keyed collection"), tier-2 mirror (~line
  91), latency table (~line 142: "DiffManifest (500 files ≈ 25KB)"), §10.1
  (~lines 1848, 1858: prose + `paneState.diff.manifest = DiffManifest(...)`
  code sample).
- Already-current parts (do not churn): §10.2 resource URL shape uses
  `agentstudio://resource/content/{handleId}?generation={reviewGeneration}`
  (~lines 1889, 1898); CLAUDE.md component row is current.
- Authority: `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`
  "Historical Notes" bans `DiffManifest` / `ContentHandle(fileId, epoch)`;
  master plan Task 0 doc-update item
  (`docs/plans/2026-06-08-bridge-agent-review-foundation.md:706-708`).

## Non-Goals

- No spec changes (the spec is the authority being propagated, not edited).
- No code changes.
- No rewrite of doc sections that are accurate (transport §4, protocol §5,
  push infrastructure §6 mechanics, BridgeWeb state layer §7) beyond renaming
  the contract nouns where they appear.
- No restructure of the doc's section numbering (downstream links depend on
  it).

## Scope

Write surfaces:
- `docs/architecture/swift_react_bridge_design.md` — the 11 stale references
  across §3.1, §3 latency table, §8.2, §8.3, §10.1; section titles where they
  name "Manifest".

Read-only context:
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` — canonical
  vocabulary and pipeline.
- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/` — the real
  type shapes any code sample must mirror.

## Task Sequence

1. **§3.1 ownership table.** Tier 1 names `BridgeReviewPackage` +
   `BridgeReviewItemDescriptor` (metadata) with content behind
   `BridgeContentHandle`; tier 2 mirror language updated to "item registry".
2. **Latency table.** Relabel the manifest row to "BridgeReviewPackage
   metadata (500 items ≈ 25KB)" — the size point survives, the noun changes.
3. **§8.2/8.3.** Important distinction (verified): `DiffManifest` is a
   phantom (zero code references), but `FileManifest` and `DiffState` are
   **live** push-state types (`Features/Bridge/State/BridgeDomainState.swift:73`
   and the `diff` state root). Rename "Diff Source and Manifest" → review
   package flow; rewrite prose/samples so phantom types are replaced with the
   actual `BridgeReviewPackage` / descriptor shapes (copy field names from
   the real Swift files, not from memory), while sections describing the live
   `DiffState`/`FileManifest` push state are updated to state their current
   role (push-plane state, distinct from the review-package contracts) rather
   than deleted.
4. **§10.1.** Replace the `DiffManifest(...)` push sample with the real flow:
   query → `BridgeReviewPipeline` → package metadata push → lazy handle
   fetch — consistent with the spec's Delivery Pipeline diagram and the
   lazy-content plan's end state (write it lazy; that is the contract even
   while the implementation gap is open).
5. **Sweep + verify.** `grep -n "DiffManifest\|resource/file/\|fileId.*epoch"
   docs/architecture/swift_react_bridge_design.md` → zero matches; re-read the
   "Current Implementation Reality" header section and refresh its status
   lines to point at the master plan's task state instead of stale claims.

## Proof Gates

- `grep -c "DiffManifest" docs/architecture/swift_react_bridge_design.md`
  returns 0.
- Every code sample edited in §8/§10 names only types that exist in
  `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/` (spot-check
  by grep per type name).
- `mise run lint` passes (doc formatting hooks, if any).
- A reader following §10.1 end-to-end encounters the same pipeline as the
  spec's Delivery Pipeline diagram — reviewer check, stated in the PR.

## Stop Conditions

- Stop if rewriting §8 reveals genuine *design* disagreements between the doc
  and the spec (not just stale nouns) — that is a spec-review question
  (`spec-review-swarm`), not a find-and-replace.
- Stop if the "Current Implementation Reality" section requires claiming
  implementation status this audit contradicts (e.g. lazy content) — describe
  the gap honestly with a pointer to the open plan instead of papering it.

## Risks

- Doc drift recurring: the master plan already requires doc updates in the
  same changeset as boundary changes (CLAUDE.md rule); this plan restores
  compliance, and the grep proof gate is cheap to re-run in future reviews.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridge-architecture-doc-reconciliation.md
Start by validating the plan against current git state before editing files.
Docs-only change; execute tasks in order; the grep gates are the proof.
```
