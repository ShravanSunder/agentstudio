# Arrangement visibility — bounded design review result

Mode: three-artifact-design, general-domain. Covered capability: U6/U7 only.
The wider sidebar/preview/pinned-keyboard delivery remains open; this result does
not claim its design readiness. The owner authorized independent settled work to
progress while unresolved questions are collected.

Targets read completely:
- Requirements: `docs/wip/2026-09-11-keyboard-navigation/requirements.md`.
- Specification: `docs/specs/2026-09-12-arrangement-visibility/specification.md`.
- Program Design: `docs/specs/2026-09-12-arrangement-visibility/program-design.md`.

Current source: `96e7dbb137412284c0ec6bf5f86e0090632b6ffb`. Parent merged default after
checkpointing docs; relevant arrangement/sidebar/focus owners are unchanged from
the initial review basis `aae07e0a0`. Setup and vendor verification pass. Baseline
focused tests: three suites, 38 tests pass; this is baseline, not implementation proof.

## Independent coverage

`arrangement_design_review`: fresh-context, read-only mode-complete reviewer;
complete. Original candidate result needs-revision, three material findings.

`arrangement_design_dispel`: fresh-context, read-only, complete after mode-complete
receipt. All material mechanisms mapped to U6/U7; none mapped absent. It confirmed
the three corrections and identified dependent synchronous callers as part of the
same focus-sequencing correction. No reviewer changed source/artifacts or executed
proof. No proof-challenge was required: artifacts describe proof seams, not claimed
executable success. No additional focused lane was needed after source verification.

## Parent reduction and bounded correction

| Finding | Disposition / smallest correction | Verified basis and final anchor |
| --- | --- | --- |
| A1 Default drawer eligibility ambiguous | Accepted; distinguish current/custom unminimized visibility from Default canonical membership and later child expansion | U7/R-A4; persisted drawer minimized children are valid; spec R-A4/examples and program Visibility policy interface now agree |
| A2 Main target reveal bypasses validated switch lifecycle | Accepted; use the existing serialized gesture and workspace select/switch actions before focus; preserve dependent callers in the same operation | U7/R-A3–R-A5; direct helper at PaneTabViewController:3683 versus lifecycle switch owner at WorkspaceSurfaceCoordinator+ActionExecution:318; program Committed focus delta and Synchronous callers sections cover target, zoom/viewer, Bridge reuse, note, retained inbox, and IPC await |
| A3 Threading left to planner | Accepted; concurrent pure decision from keyed immutable graph snapshot; existing scalar revision/current identity validation before UI mutation | R-A5 and explicit owner off-main constraint; WorkspaceTabGraphAtom keyed value/revision and cursor keyed active-ID exist; program Threading section specifies capture/derive/revalidate/apply |
| A2 dependent callers race after async conversion | Accepted as part of A2; inner operation never re-enqueues behind its own gesture; private routing admission separated from completion; IPC awaits focused result | Current zoom/viewer, Bridge attendance and note immediately continue after focusTargetedPane; program Synchronous callers table maps each; AppIPCLayoutPort/adapter/server current contracts inspected |
| A3 raw atom capture versus domain policy placement | Accepted clarification; atom reads capture raw values only; separate pure Core policy owns visibility | Existing atom/data and TabLayoutRules boundary preserved in final Threading/interface prose |

No conflicting/rejected/unverified material finding remains for this capability.
The async focus port changes source signatures but retains JSON schema and the
meaning of focused:true; it is not a new external operation or permission boundary.
Removing the correction would allow premature success or out-of-order effects.

Parent verification after correction: complete target reread; current/custom versus
Default examples align; lifecycle action path present; all direct synchronous helper
consumers and dependent zoom/viewer callers accounted for; off-main placement and
keyed revalidation explicit; no preview state/cache/atom/store added. The one bounded
correction set is inside existing authorized U6/U7 meaning. No second review invoked.

## Result

**ready — arrangement visibility capability only**, with the original independent
receipts plus the parent-verified correction above. U6/U7 are fully covered by the
Specification and Program Design and may enter plan-implementation. U1/UI navigation,
U3–U5/U12/U14–U16 are not claimed complete by this result and remain in their own
design/proof work. No full-task, implementation, native-focus, or PR readiness claim.

## Second normal review — creation versus existing placement

Concrete residual: generic insertion also serves existing moves, detach rollback,
reactivation and undo. Parent inspected those production consumers and the terminal
creation composition at HEAD `23e46367e`. U6 applies only to new identities.
The Program Design creation section now names separate creation entries sharing
private placement mechanics; existing-placement callers preserve prior semantics.

`creation_scope_review` completed fresh-context read-only program-only coverage,
with no candidate findings. `creation_scope_dispel` completed the mandatory
post-candidate sweep with no absent mappings or over-delivery. Parent verified the
creation call sites, generic existingPane branch, and unchanged preservation boundary.
Both receipts are accepted for this bounded delta; neither claims executable proof.
No third normal review is authorized or needed. Ready coverage for U6/U7 carries
forward with this second result and the unchanged first-round corrections.
Implementation still requires the explicit creation routing correction; the earlier
Core green tests do not prove production creation-path preservation.

## Subsequent implementation evidence

Creation routing and existing-placement preservation are implemented and have fresh
focused proof. Implementation review at `0e17351e1` then disproved the R-A4 native
reattachment assumption for an already-open drawer changing custom arrangements.
The earlier ready result must not be used as current authority to finish that path.
See [implementation review](arrangement-implementation-review.md) and
[the design gap](drawer-reveal-design-gap.md). Owner reconvergence and permission for
the targeted third design review are pending; no further code correction is applied.
