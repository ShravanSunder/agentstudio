# Bridge Spec + Architecture Coherence Review — 2026-08-10

Status: COMPLETE. Verdict: **needs-revision** (3 blockers, 3 major,
3 moderate, 3 minor). The metadata-purity correction itself is sound and
should not be reopened; the revisions are completeness/authority gaps.

Coverage: parent analysis + read-only code inventory delegate + Base UI
research delegate + fresh-context mode-complete reviewer
(three-artifact-design mode, terminal state complete). All blocker/major
evidence independently re-verified by the parent before acceptance.

## Review targets

- Requirements: `docs/specs/2026-08-10-bridge-review-comparison-target-loading/user-requirements.md`
- Specification: `docs/specs/2026-08-10-bridge-review-comparison-target-loading/specification.md`
- Program Design: `docs/specs/2026-08-10-bridge-review-comparison-target-loading/program-design.md`
- Governing architecture: `bridge_product_transport_architecture.md`,
  `bridge_viewer_architecture.md`, `bridge_native_runtime_architecture.md`,
  `bridge_web_runtime_architecture.md`
- Substrate context: `docs/specs/2026-08-05-bridgeweb-swift-dev-backend/`,
  `docs/specs/2026-08-06-worktree-annotations/pr0-*.md`

## Question 1 — Is the metadata-stream abuse correction in place? YES (docs), NOT YET (code, by design)

Ground truth (all verified file:line):

- Review init enumerates/peels/sorts every branch:
  `BridgePaneController+ReviewContribution.swift:48-104`; the full catalog is
  fetched only to read `defaultTarget` (`:72-82`).
- Catalog rides pushed metadata: `targetCatalog` on the `pane.presentation`
  frame — `BridgeProductStreamFrame.swift:705` (frame kind `:774-782`).
- Worker freezes every row + `JSON.stringify`s the whole comparison payload on
  every frame apply: `bridge-comm-worker-pane-presentation.ts:120-141`.
- React renders every row unvirtualized:
  `bridge-review-comparison-branch-selector.tsx:64`.

`targetCatalog.branches` is the ONLY unbounded array in the entire metadata
surface — every other lane is windowed and capped
(`BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT = 4096`, `.max()`
on every array in `bridge-product-review-metadata-contracts.ts:39-83`). The
abuse is a single anomaly, not a pattern.

Recurrence prevention is real and mechanical: strict-JSON allowed-key corpus
(`BridgeProductStrictJSON.swift:261`) rejects `targetCatalog` once removed;
CT-R2 names every forbidden carrier; three of four architecture docs state
the rule independently; the transport doc's placement test is decision-grade.

## Question 2 — Are on-demand streams used properly? YES, feasible with shipped precedent

- `review.content` is already lease-gated against publication authority, NOT
  subscription-gated (`BridgeReviewPublicationCoordinator.acquireContentLease`,
  `:402-441`) — the query→descriptor→`content.open` composition has an
  in-package precedent. No architectural gap blocks CT-R2.
- Content kinds are closed discriminated unions on both sides with
  compile-checked registry parity
  (`BridgeProductContentContracts.swift:3-13,423-465`;
  `bridge-product-content-contracts.ts:185-357,513-524`). Adding
  `review.comparisonTargets` is mechanical; exhaustiveness finds every site.
- Typed call results already carry structured payloads
  (`bridge-product-call-contracts.ts:16-29`), so a descriptor-bearing result
  has precedent.
- Dev server carrier is a generic one-line passthrough
  (`BridgeDevelopmentProductHost.route`, `:237-239`) — zero dev-server routing
  changes for a new kind. CT-U6 holds structurally.

## Question 3 — Design flaws found

### Blockers

**B1 — The current-comparison "Default" marker loses its only data source.**
`bridge-review-comparison-control.tsx:270-285` computes `isDefault` from
`props.targetCatalog?.defaultTarget` and renders "· Default" in the
CURRENT-STATE block (not the candidate list). After cutover the catalog is
request-scoped and exists only after the Branch surface opens; selection mode
is sticky (`:45`, open handler `:114-117` resets only commitOID), so in
Commit mode no query ever fires. The marker disappears until a branch query
resolves and never appears in Commit mode. This silently subtracts an
accepted PR0 obligation (`pr0-specification.md:145-146`; basis delta
`2026-08-10-pr0-review-comparison-basis.md:13-26`, proof line 57; locked by
`bridge-review-comparison-control-ux.browser.test.tsx:78`).
Smallest correction: add a compact default-target fact to the
`reviewComparison` pane-presentation row and CT-R6, OR record explicit
owner-authorized supersession of the marker obligation.
Route: **spec-design**.

**B2 — Cross-repo `agentstudio-git` work is unaccounted; CT-R3 is currently
unimplementable upstream.** The pinned upstream contract (revision
`8525ebd8`, `Package.swift:27-29`) exposes only `reviewComparisonTargets(for:)`
whose branch rows carry `branchName`/`remoteName`/`oid` — **no tip commit
time**, which CT-R3's 30-day cutoff and the catalog contract require. Both new
Git operations (constant-scope default read; bounded capture) are upstream API
additions + publish + revision bump. The Hard Cutover list has no such step;
the PD anchor `LibGit2ReviewComparisonTargetReader.swift` is not a repo path
(it resolves only in a tmp proof checkout); CT-R3's real-Git fixture proof has
no stated execution home (this repo's `mise run test` cannot exercise an
upstream reader).
Smallest correction: Hard Cutover names the upstream contract delta
(bounded operation, default-only operation, commit-time field) and bump
ordering; anchors marked as upstream references; proof table states where
CT-R3 evidence executes.
Route: **program-design** (proof-home line: spec-design).

**B3 — Conflicting live authority on the catalog path.**
`pr0-program-design.md:646-682` still prescribes the abuse as the design
("Use the existing pane-presentation path for transient catalog data …
publishes it through `pane.presentation.reviewComparison.targetCatalog`").
No forward supersession pointer exists to the target-loading spec (PR0's
header points only at the comparison-basis delta). Two live program designs
disagree; PR0 is labeled the current persistence design, so a planner reading
it re-implements the abuse. The bounded-picker consequence (branches older
than 30 days become unselectable by name; only escape is Commit mode with a
full OID) is owner-authorized via CT-U3 but should be recorded in the same
supersession note.
Smallest correction: supersession status notes in `pr0-program-design.md`
(and `pr0-specification.md` for the picker rows) scoping replaced sections to
`2026-08-10-bridge-review-comparison-target-loading`.
Route: **spec-design** (authority maintenance).

### Major

**M1 — "Hard capacity bounds" are not determinable.** The byte bound
"no greater than the existing content-stream ceiling" resolves to
`maximumContentStreamBytes = Int(UInt32.max)` ≈ 4 GiB
(`BridgeProductSessionContract.swift:36`) — vacuous for CT-U3's
"pathological repositories cannot overwhelm Bridge". The row budget is
deferred to an unnamed "product policy owner"; no policy file is named (repo
convention: `AppPolicies`).
Correction: Spec states concrete row/byte budgets (or names the constant);
PD names the owning policy file. Route: spec-design (values) +
program-design (placement).

**M2 — No release rule for a never-opened query descriptor.** The web abort
path only cancels an opened stream (`bridge-product-transport.ts:267-291`);
a call result never followed by `content.open` produces no native signal.
Existing bodies avoid this via publication leases, which this kind lacks by
construction. The PD claims "descriptor lifetime" ownership but states no
trigger (single-use? TTL? session-drain?) for close-before-open.
Correction: state the release rule and its enforcement point.
Route: program-design.

**M3 — Governing architecture doc contradicts itself.**
`bridge_native_runtime_architecture.md:122-124` ("content handles are served
only through a committed or retiring publication lease") and invariant `:248`
("Metadata publication precedes content demand for that generation") read as
absolute, while `:182-185` in the same doc permits request-scoped query
descriptors with neither. An implementer following Invariants either rejects
the design or routes the catalog back through a publication.
Correction: qualify both statements to File/Review body content; name the
query-descriptor authorization family (capability + request identity +
descriptor lifetime). Route: docs-maintain.

### Moderate

**Mo1 — CT-U2 vs CT-R2 trigger mismatch.** CT-U2: "opening the comparison
picker must load choices and focus search." CT-R2 fires on "Branch selection
surface opens"; mode is sticky, so reopening in Commit mode satisfies the
spec while failing a literal read of the requirement — and compounds B1.
Correction: reword CT-U2 to name the Branch surface, or reset to Branch mode
on open and say so. Route: spec-design.

**Mo2 — Truncation/recency messaging has no realization owner.** CT-R3/CT-R4
require reporting capture/cutoff/truncation "so the UI can explain"; the
PD's picker state table (idle/loading/ready/failed) has no slot for it and
CT-R4's realization row names only the combobox + virtualizer.
Correction: name the component and state slot. Route: program-design.

**Mo3 — Admission/demand classification for the new content kind is
unassigned.** Two facets: (a) `BridgePaneProductContentDemandAuthority`
derives priority from committed subscription interest — a kind with no
subscription falls to `.unspecified` (`:89,92-116`) and is paced as
background-ish work, quietly violating CT-U2 responsiveness under load;
(b) `BridgePaneProductSchemeProvider.swift:883-895` switches content kinds to
distinct refresh-work admissions, and CT-R5 makes "losing foreground work
admission" a normative cancellation trigger — so which admission the new
producer acquires is behavior, not detail.
Correction: PD names the demand classification and admission source for
`review.comparisonTargets`. Route: program-design.

### Minor

- **Mi1** — `@tanstack/react-virtual` is not a BridgeWeb dependency; add the
  dependency addition to the Hard Cutover list. (All `@base-ui/react@1.6.0`
  API claims verified against shipped `.d.ts`: `virtualized`,
  `useFilteredItems`, `onItemHighlighted`, list render-prop, virtual
  active-descendant.) Route: program-design.
- **Mi2** — Demand-lane vocabulary drift: transport doc says
  `foreground/selected … idle`; web runtime doc says `selected … background`;
  the spec's "foreground" maps to neither unambiguously. One canonical
  vocabulary. Route: docs-maintain.
- **Mi3** — `bridge_product_transport_architecture.md:157` routes the
  discrepancy reader only to the program design; add the Specification link.
  Route: docs-maintain.

## Requirement-subtraction ledger (PR0 picker obligations)

| PR0 obligation | Disposition |
| --- | --- |
| Choose any local/remote branch or exact commit | Owner-authorized supersession (CT-U3); record in B3 note |
| Branch mode provides searchable local+remote candidates | Covered (CT-R2, CT-R4) |
| Candidate shows display name + abbreviated revision | Covered (catalog contract + CT-R4) |
| Initial branch marked Default without replacing name | **GAP — B1** |
| Same-short-name local/remote distinguishable | Covered (kind + ref identity) |
| No remote fetch on open/search | Covered (CT-R3) |
| Commit mode accepts exact OID | Covered (CT-R6) |

## What held (inspected, no findings)

- Metadata purity + recurrence prevention (risk predicate a) — strong.
- Transport feasibility (risk predicate b) — holds with shipped precedent.
- PD current-system claims — accurate everywhere checkable (one anchor
  mislabeled, covered by B2).
- Cancellation/ordering — per-surface worker derivation epoch invalidates
  in-flight picker queries without new machinery, as the PD claims.
- Trust boundaries — no client-supplied repository path; pane session
  authority supplies repo/worktree.
- Durable state — genuinely untouched; no migration needed.
- 2026-08-05 dev-backend spec set — internally coherent; carrier-not-backend
  boundary matches code; supersession headers correct.
- Three-artifact identity separation, traceability tables, negative-space
  sections, changed-edges delta — all satisfy the review bar.

## Coverage-bound result

- Verdict: **needs-revision**.
- First required revision: B1 → spec-design (subtracted accepted obligation);
  B2 and B3 can proceed in parallel (B2 → program-design, B3 → spec-design
  authority note).
- Recommended next step: **spec-design**, carrying B1 + B3 + M1(values) +
  Mo1, then program-design for B2 + M2 + Mo2 + Mo3 + Mi1 once observable
  contract deltas settle.
- Coverage gaps: upstream `agentstudio-git` verified only at pinned revision
  `8525ebd8` (proof checkout), not live upstream HEAD; no build/test executed
  (read-only review).
- Owner decisions needed: none beyond recording the CT-U3 supersession
  consequence explicitly (B3).
