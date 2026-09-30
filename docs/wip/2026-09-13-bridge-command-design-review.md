# Bridge command-first design review state

This is process evidence, not a normative design home. Governing artifacts:
[Requirements](../specs/2026-09-12-bridge-navigation/2026-09-12-requirements.md),
[Specification](../specs/2026-09-12-bridge-navigation/2026-09-12-bridge-navigation.md),
[Program Design](../specs/2026-09-12-bridge-navigation/program-design.md).

## Earlier source/specification review (S18–S26)

The owner-expanded scope S18–S26 was reviewed separately from the earlier
Git-only source draft and the dedicated drawer slice. Current source HEAD is
`85ae48f5e`. No implementation or executable proof is claimed.

- Fresh Astra mode-complete specification-only reviewer:
  `2026-09-13-bridge-command-spec-review`, complete, candidate needs-revision.
- Fresh Astra mandatory dispel:
  `2026-09-13-bridge-command-spec-dispel`, complete.
- Both read distinct current Requirements/Specification and checked the latest
  owner sources, known-only worktrees, arbitrary local Files, preparation-only,
  command-first UI deferral and the IPC-v2 integration boundary.

## One bounded correction

**F1, required:** the Requirements agent/miscellaneous-file journeys and
acceptance paragraph still implied immediate agent-driven display. S25 requires
preparation first and separate human/debug activation. Parent corrected all three
passages and verified them against R5/C5. The correction adds no capability,
notification, approval, focus change or new owner choice.

**OD1, required:** acceptance still demanded new worktree-add UI proof despite
S22's command-first delivery. Parent corrected the same acceptance paragraph to
require typed-command/IPC add/select/inspect now, preserving actual rendered
activation/annotation proof and deferring new UI-entry proof to its delivery.

Semantic-change check: corrections stay inside F1/OD1, with one Requirements
correction pass. Subsequent title/wrapping/link changes are non-semantic. Parent
verified the corrected anchors; no confidence-only reviewer rerun was needed.

Coverage retained: U-BN-01–04, U-BN-06 and U-BN-13–16 covered by R1–R7/R14–R16;
U-BN-05 owner-superseded by S23; U-BN-07 covered for this source route while broader
placement is separate; U-BN-08–12 retain their dedicated drawer ownership.

## Earlier Program Design state (before collection reconciliation)

The separate source/navigation Program Design is authored and self-checked for
ownership, source separation, preparation/activation, draft flush, migration,
retention, failure/replay boundaries, call-path deltas and proof seams. It proposes
one Core navigation atom using the existing workspace store/local repository,
one App command handler, explicit File/Review source configurations, an exact
opened-document source, generalized annotation subjects and a draft-preparation
handshake before source replacement. It has not received independent Program
Design or three-artifact review.

Structural-realization confirmation is pending. The governing program-design
workflow requires the owner to confirm the current structure before those
reviews/planning. No source code, atom, table or migration has been added.

IPC coordination also remains unconfirmed. The committed sibling v2 design
reserves file.open/openFile; its presentation fields and typed async result seam
must align with this source design. Router discovery failed, so the
[prepared coordination message](./communications/2026-09-13-ipc-v2-bridge-coordination-draft.md)
has not been submitted. No v1 workaround or sibling-worktree edit was made.

## Owner annotation correction and readable architecture

The owner clarified that exact-file reading must have no worktree-membership
prerequisite, agents may work in related repos for any reason, and known-worktree
selection belongs in the command-first scope. S27–S30 record those annotations.
The main human journey now starts with the exact file; the stale S17 delivery
qualification is superseded explicitly. The fullscreen journey shows one selected
Review worktree/comparison in the same receiver, independent of Files and CWD.

Bounded mental-model reviewer `2026-09-13-files-review-boundary-check` returned
complete with no repository edits. Parent accepted the worktree-first journey,
stale scope qualification and missing selected-Review-worktree field findings.
The suggested feedback uncertainty was resolved to the existing copy/export
foundation after reading WorktreeAnnotationBatchProjector and the output
coordinator, and checking the owner's supplied annotation batch. Automatic
delivery and source-file editing remain outside scope; output is not a receipt
from an agent.

Requirements, R4/R6/R16/C7 and their proof rows now make those boundaries explicit.
Program Design adds the selected Review worktree and surface-specific transitions,
plus the subject-aware annotation output retrofit. Four rendered, inspected
diagrams show independent Files/Review, current-to-proposed ownership,
preparation/activation with acknowledgement/failure, and fullscreen Review.
The added diagrams use local PNGs with SVG sources; they are design illustrations,
not native runtime evidence.

This is an owner-driven correction after the earlier specification review, not
another completed formal review. That earlier coverage remains historical;
the changed obligations/output details have not received independent design
review. Structural-realization confirmation remains pending for the current
proposal. Drawer artifacts and product code are unchanged.

## Workspace collection reconciliation

Owner sources S31–S34 supersede single-worktree Files/search and seed-only CWD
behavior. Requirements and Specification now require collection-wide file search,
all member trees, location-based individual-file classification, explicit removal
with selected-file clearing and next-member Review fallback, and protection of
the current known CWD member. Known CWD transitions add/protect the new member
without changing display selections. Saved annotations and the existing draft
preservation boundary survive removal. No product code was edited.

At this checkpoint the Program Design and diagrams still contained the prior
either/or Files source and seed-only CWD assumptions. They require structural revision and
are not current evidence of realization for S31–S34. No independent review of the
revised Specification is claimed. Unresolved-CWD and standalone-Bridge protection
semantics are awaiting the owner's pending question; no answer has been inferred.

## Current cleanup and structural proposal

S35 now settles the remaining fallback: only a current known CWD worktree is
protected. It is injected/deduplicated into membership; old members stay listed
and removable. Unresolved CWD and standalone receivers have no protected member.
Last-member removal leaves loose files and empty Review.

Requirements, Specification, Program Design and advisory tradeoffs have been
reconciled. Program Design replaces the single-source choice with one feature
collection adapter over existing worktree sources and exact loose documents,
source-qualified rows/query results and one viewer. Membership/CWD updates do
not replace the viewer. Review binding changes can still recreate it after draft
settlement and restore Files state. Removal rechecks current CWD after any await,
clears affected entries/selection, revokes only the removed source and applies
ordered Review fallback. Protection is derived, not a second saved CWD field.

The tradeoff-writing Delegate edited only its declared proposal path; parent read
it and corrected a leftover worktree-first journey and stale draft-policy wording.
Both changed PNGs were rendered and visually inspected; all four images remain
embedded. Long duplicate ASCII versions were removed while the compact collection
map and lifecycle/ownership flows remain in Markdown. No image-runtime repair or
annotation-save bug fix is claimed. Those issues are separate from design proof.

The owner confirmed product behavior, not yet the complete revised structural
realization. A concrete confirmation question is pending for the navigation atom,
App handler, collection adapter, existing persistence and annotation migration.
No formal review of S31–S35 or this new structure has run. Earlier review findings
and correction limits are preserved; no mode rename is a review-budget reset.
IPC coordination remains unsent because prior Router discovery was unavailable.

## Fable 5.1 high review return

The owner explicitly confirmed the revised structural realization and requested
Fable 5.1 high. The recovered named ACPX session completed its three-artifact
review; receipt is `tmp/design-review/2026-09-13-fable-workspace/fable-result.md`.
Candidate recommendation is needs-revision, not acceptance. A subsequent
scope-defense lane is in progress. No third normal review is authorized.

Parent checked current source for F1 (existing showBridge identities have
noArguments/interactive contracts), F2 (search runs in the web query worker and
current IPC requires a mounted page), F3 (Zoom context excludes parentPaneId != nil),
and F5 (pane-source comparison writers still exist). These findings are real
correction candidates. F3 needs an owner choice for drawer-terminal callers before
revising receiver behavior. The pending question contrasts explicit refusal in
this slice with parent-receiver sharing and its additional CWD rules.

F6's demand to reconfirm local persistence is not accepted as a new owner decision:
the exact structural proposal included the existing local workspace persistence
and was explicitly confirmed. F7 must not introduce new command-bar UI contrary
to command-first delivery; the existing debug/IPC testing boundary remains. F4
catalog-unregistration behavior and F8 documentation cleanup await scope reduction.
No normative remediation has been applied while the receiver decision is pending.

Permission audit: although the packet withheld shell execution and ACPX advertised
no terminal, Fable invoked read-only Terminal tools (cat/sed/grep/ls/git status).
That exceeds the packet's execution grant. Its receipt is not permission-compliant
proof, and no executable proof is accepted. Parent treats findings as research
leads requiring independent source verification; inspected source state is unchanged.
Do not hide this gap by calling the full design review accepted.

Scope-defense returned partial after bounded follow-up. F3 owner-choice, F6 no
reconfirmation and F7 no new-UI gate are supported. Its broad suggestions that
new argument/schema mechanisms are unanchored are not accepted: the confirmed
structure explicitly includes typed commands and annotation migration. F1/F2/F5
remain parent-verified obligation gaps, with mechanism choice unresolved. F4,
F8, O1–O4 and the full overdelivery mapping are incomplete. Do not claim review
closure from this receipt; preserve it and finish only after the receiver
boundary is settled. No remediation or additional normal round has started.

## Parent reduction of all Fable candidates

This completes parent classification, not the missing independent scope-defense
coverage or design readiness. Source/authority was rechecked after the partial
scope-defense receipt. No normative artifact was edited in this reduction.

| Candidate | Disposition and failed obligation | Smallest correction / owner |
| --- | --- | --- |
| F1 | Accept contract gap under R7/U-BN-02/06. Existing `showBridgeFiles` and `showBridgeReview` are noArguments/interactive layout commands; proposed typed document activation is not mapped. Reject the stronger assertion that R8 forbids any re-specification: it only preserves placement. | Program Design must choose one explicit command-identity realization and state its interactive/IPC argument and target cutover; no second command catalog. Do not prescribe a reviewer-invented mechanism. |
| F2 | Accept execution-owner gap under R2/U-BN-01. Current query projection is a web worker and current IPC needs a controller. PD says unmounted search but names only existing workers. | Program Design must identify search process/lifetime, mount precondition and one home for matching/ranking. New native engine is not automatically authorized merely because the sentence says headless. |
| F3 | Decision needed under R3/U-BN-02. `zoomCompanionContext` excludes drawer children. Stable receiver semantics do not tell us whether to refuse their calls or share a parent's receiver. | Pending owner question. Preserve associated-Bridge rules for top-level callers; do not select drawer ownership/CWD policy implicitly. Return via spec-design before Program Design. |
| F4 | Accept missing catalog-removal contract under R16/C7/U-BN-15/16. Topology unavailability and worktree unregistration are distinct in current code; unregistration clears pane association. Neither known-only addition nor explicit Bridge removal alone settles existing member treatment. | Owner choice remains: retain identifiable unavailable member until explicit Bridge removal, or automatically apply membership removal/fallback. Specify search/Review/restore outcome before How. No new tombstone service or automatic adoption is justified. |
| F5 | Accept cutover gap under PD sole-source ownership and repo hard-cutover rule. Contribution-target commits and new pane/companion creation currently write `BridgePaneState.source`. | Program Design must name the surviving runtime source contract, legacy payload conversion-only treatment and removal/replacement of every live comparison/source writer. Preserve unrelated supported source variants. |
| F6 | Reject renewed tier approval. Owner explicitly confirmed the concrete structure using existing local workspace persistence; PD already states reset/unavailable local data cannot claim restoration. R15 promises ordinary restart, not corruption-proof recovery. | Keep disclosed consequence. No second approval, new database, stronger recovery or durability contract. This does not reject the already-confirmed new navigation row/annotation migration. |
| F7 | Reject new command-bar UX gate as scope expansion against S22 and confirmed command/debug-first staging. Accept only clarity that existing controls remain and new typed operations have debug/IPC exposure in this slice. | Clarify current staging during the bounded spec correction; do not require new command-bar rows/pickers or treat the settled deferral as an owner decision. |
| F8 | Accept bounded reader/ownership cleanup under S7/S16 and dedicated U-BN-08–12 home. Undefined Track 3/4 names and duplicated drawer journey/proof obscure authority. | Requirements: replace track labels with named capabilities; point to dedicated drawer journey/proof without deleting its U identities or source history. |
| O1 | Already satisfied. PD explicitly says CWD publication can happen while a draft is awaited and protection is reread before synchronous mutation. | No correction or new coordination mechanism. |
| O2 | Reject deletion. User specifically requested visible fullscreen explanation/diagrams; fullscreen topology answers a different reader question from collection membership. | Keep embedded fullscreen diagram and transition table. |
| O3 | Existing obligation, not new requirement. PD retains navigation rows for live/undo-owned pane IDs and forbids pruning merely because an owner leaves active layout. | Confirm actual projection preserves those rows in eventual implementation proof; no new timer/event/undo subsystem. |
| O4 | Accepted integration dependency, not a local implementation success. Dispatcher result is currently narrow/synchronous and reserved sibling file.open fields require agreement. | Keep v2 owner boundary and no-v1 constraint; do not claim planning/execution of this wire edge is ready until current typed async completion contracts are supplied. |

### Material-element scope map

| Existing proposed element | Exact obligation / permission basis | Parent result |
| --- | --- | --- |
| Stable terminal/standalone receiver | R3/C3, S18, U-BN-02/03 | Anchored; drawer-child case remains F3 |
| One navigation atom with receiver-keyed values | R3/R15/R16/C7 and explicit structural confirmation | Anchored; equality/publication only |
| Existing workspace save/local row, restart/undo retention | R15/C7, explicit structure, ordinary restart and existing owner identity | Anchored; F5 conversion edges incomplete |
| App navigation handler and pure transition rules | R1/R3/R5/R7/R16, source-based command composition | Anchored; no second authoritative state |
| Exact-file admission, canonical locations and descriptor fences | R1/R14/C1, supported local-file scope | Anchored; no directory crawl or web arbitrary-path authority |
| Files collection adapter/member engines/loose entries | R2/R16, S31/S32, explicit structural confirmation | Anchored; one WebView, per-member authority |
| Qualified rows, deduplication, membership/query generations | R1/R2/R16/C1/C2, distinguish paths and stale requests | Anchored; only query process/rule owner is unresolved F2 |
| Current-CWD injection/derived protection | R3/R16, S33–S35 | Anchored; do not create persistent second CWD |
| Removal transition, file clearing, Review fallback | R16, S32–S35 | Anchored; catalog-unregistration case F4 separate |
| Independent per-member Review comparison and controller replacement | R4/C4, preserve current Git engine and stable receiver | Anchored; F5 live writer cutover incomplete |
| Annotation Git/local subject and schema/output conversion | R6/R14/R15, S19/S30, explicit structural confirmation | Anchored; no fake Git IDs or second annotations product |
| Awaited draft.flush and display acknowledgements | R5/R6/C4/C5 | Anchored; preserve unsaved draft vs saved comment semantics |
| Existing copy/export, saved revision and exact-output preservation | R6, S30, existing output foundation | Anchored; no automatic delivery claim |
| Member refresh / on-demand loose-file validation | R1/R6/R14 and existing source-currentness rules | Anchored; no arbitrary-folder watcher |
| Cancellation, partial effects and save revision accounting | R5/R7/C5/C7 | Anchored; existing v2 replay owns correlation, no new journal |
| Typed command/IPC/query contributions | R7, S22, explicit structure | Anchored; F1 and external v2 seam remain |
| Marker-scoped proof and source-scrubbed telemetry | Repo proof/performance constraints and V rows | Anchored; no executable/native proof claimed |
| Four diagrams and capability/call-path tables | S7/S16 and explicit user requests for readable embedded diagrams | Anchored; existing diagrams not a new runtime feature |
| Drawer preservation pointers | U-BN-07 and dedicated U-BN-08–12 authority | Anchored; remove duplication only, F8 |

No independent overdelivery verdict is manufactured from this parent map. The
partial dispel did not cover F4/F8/O1–O4 or provide its own complete material map;
that coverage remains incomplete. The broader assertion that typed arguments or
schema additions are unanchored is contradicted by explicit structural approval.

### Continuation boundary

Current result is decision-needed, not ready: F3 and F4 contain genuinely unmade
owner meaning. The current pending question is F3; do not repeatedly ask it or
infer an answer from a wake/stop hook. F4 can be discussed with the owner as the
catalog-removal consequence, without choosing it here. Preserve the bounded
correction set F1/F2/F5/F7 clarity/F8 for one ordered spec-design → program-design
remediation after decisions. No normal review budget is reset, no third review
is authorized, and no code implementation follows from this document.

## Independent scope-check completion

Fresh Fable 5.1/high named session `bridge-workspace-dispel-fable-2026-09-13`
completed `2026-09-13-fable-dispel-completion`. Receipt:
`tmp/design-review/2026-09-13-fable-workspace/dispel-result.md`.
The wrapper restricted tools to Read/Glob/Grep; parent audited the transcript:
only read/search tool kinds, no errors, stopReason=end_turn. It read all three
targets, advisory prose and SVG labels, classified F1–F8/O1–O4 and mapped every
material proposed element. This completes the previously partial scope lane,
not another general review or a review-budget reset.

Parent reduction agrees with necessary F1/F2/F5 contract/owner/cutover gaps,
F3/F4 unresolved owner meaning, redundant F6 reconfirmation, F7 recording deferred
presence rather than adding UI, and F8 removal of duplicated drawer prose. The
user's repeated request for readable diagrams supplies the authority that the
scope receipt omitted for O2; keep fullscreen.png. O1/O3 are already covered and
O4 remains the existing external v2 dependency. A hypothetical missing future v2
seam is not a new permission question or authorization for a local replacement.

Additional scope findings, reduced against the actual obligations:

| Scope finding | Parent disposition | Bounded next correction |
| --- | --- | --- |
| OD-1 new refreshBridgeFiles | Accept removal. No explicit refresh obligation appears in the current Requirements/Specification; exact-file reopening/activation already revalidates content. | Delete the new command and its standalone promises in the Program Design; retain existing refresh/invalidation foundation. No new owner approval requested. |
| OD-2 persisted prepared line/default activation location | Accept removal of the unrequired durable field. The unsent IPC reservation is not owner authority for new persistence semantics. | Retain exact document identity and selection; do not design a prepared-line persistence contract from the sibling draft. Any later required line targeting needs its explicit input/activation contract, not silent durable state. |
| OD-3 converted marker | Reject blanket claim that dropping the field is inherently atomic or that every migration completion marker is forbidden compatibility. The ordinary save owner commits core first, then writes local (`WorkspaceSQLiteDatastoreActor.swift:145–235`); undo saves return before local. | Fold into F5: specify safe one-time import and writer cutover across the two existing database boundaries. Delete an extra marker if redundant, but never discard the legacy source before imported local state is acknowledged. No permanent dual runtime owner. |
| OD-4 optional Files filter | Permitted by R2 MAY, not an absent rail; no defect or new owner decision. | Keep optional narrowing subordinate to default all-member search unless later simplification is separately selected. |

The scope receipt calls F5 field removal the only answer. Parent accepts only the
single-source/writer gap: BridgePaneSource also contains commit/branchDiff/
agentSnapshot variants, so the scoped cutover must preserve any unrelated
supported variants. A reviewer cannot expand the change by deleting them.

The scope lane inspected SVG labels, not PNG rendering, and explicitly excluded
independent reopening of some architecture/sibling/drawer sources. Parent had
already inspected those owning boundaries and visually inspected the images;
this receipt is scope evidence, not fresh visual/runtime proof. The earlier
whole-mode Fable no-shell-grant violation remains recorded; completing this
compliant scope lane does not retroactively validate that run's execution grant.
No claim of full permission-compliant review closure or design readiness is made.

Result after reduction: decision-needed for F3/F4, with a bounded semantic
correction set preserved for spec-design then program-design after owner meaning
is supplied. No product choice, normative edit, code change, test or implementation
has been made in this check. No third normal review was started.

## S36 drawer decision and bounded correction pass

Owner chose drawer-owner routing: owner pane CWD matters, drawer caller path can
resolve to a member-worktree file or loose file, and worktree files are not loose
merely because they came from a drawer. Requirements S36 and Specification R3/V2
record owner receiver routing, caller-relative path base and owner-only CWD
protection. This resolves F3; it does not decide F4 catalog-unregistration.

One ordered Requirements/Specification then Program Design correction pass applied
the settled portion of the accepted set:

- F1: new activateBridgeFile/activateBridgeReview typed identities; existing
  showBridgeFiles/showBridgeReview preserve tab-opening presentation identity.
- F2: mounted Bridge JS worker/query projection is the sole collection search
  owner, sharing the existing matcher. Unmounted/unready queries fail explicitly;
  preparation remains mount-independent. No native search subsystem added.
- F3: App resolves drawer owner via existing pane graph, revalidates ownership
  before publish, and uses one owner record; no drawer-CWD membership injection.
- F5/OD-3: one-time conversion uses existing datastore ownership: acknowledge
  local import before removing legacy core payload field; failed stages retain
  recoverable data. Explicit writer/read replacement table removes competing
  live source authority. No extra converted boolean; unrelated supported source
  variants retain exact import values.
- F7: new typed commands have no new interactive row/picker in this slice;
  existing controls preserved and debug inputs explicit.
- F8: replace undefined track numbers, remove duplicate drawer journey/proof
  while retaining U-BN IDs and the dedicated Requirements link.
- OD-1/OD-2: remove new refresh command and durable prepared-line state; exact
  reopening/activation retains content revalidation.

Parent checked corrected passages against original findings and source anchors.
The capability, caller, data-lifetime and search-owner changes have matching
Specification/proof wording. Existing diagrams retain preparation vs activation
and source-ownership meaning; drawer routing has an inline flow. No new normal
review round or reviewer was dispatched. The F4 remainder is explicitly pending;
no full design-ready or permission-compliant whole-mode proof claim is made.
No product code or runtime tests changed.

## Catalog unregistration settlement

Owner S37 confirms that catalog unregistration uses the already-settled removal
rule; it was not a request for another independent policy. Requirements,
Specification R16/V15 and Program Design now distinguish explicit unregistration
from temporary unavailability. Existing catalog mutation propagates removal to
affected receivers, clears stale protection, clears affected files and applies
Review fallback while preserving annotations/drafts. Committed catalog mutation
is not rolled back merely because an editor is awaiting draft settlement.

F4's owner-meaning gap is resolved. No further product decision is requested.
This completes the pending F4 portion of the bounded correction set; no new
normal review, implementation or runtime proof is claimed. Earlier review
method limitation and external IPC v2 integration dependency remain recorded.
