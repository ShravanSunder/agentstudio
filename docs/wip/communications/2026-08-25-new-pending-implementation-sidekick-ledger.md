# New/Pending Implementation Sidekick Ledger

## Current relationship

agent name / pattern / assignment / assignment id:
  /root/new_pending_impl_sidekick / Sidekick / implement the reviewed
  New/Pending contract / ANP-IMPLEMENT-2026-08-25

continuity reason:
  Multi-turn cross-layer implementation must preserve Requirements,
  Specification, Program Design, proof state, and file ownership while the
  parent investigates a separate annotation flicker bug.

host / runtime / provider / model lineage / exact model / reasoning effort / budget:
  Codex / native / none / OpenAI Sol / inherited parent model / inherited / unbudgeted

resolved launcher / provider command:
  native spawn_agent with full parent history

working scope / relationship name:
  New/Pending implementation sidekick; exact-revision viewed state, Pending/All
  scope, author-aware projection/output, and focused proof

runtime ids / provider-native id when exposed:
  /root/new_pending_impl_sidekick / none exposed

permission boundary:
  write only clean New/Pending-owned Swift, BridgeWeb, and focused test files;
  never edit current dirty E2E journey files, the shared coordination log,
  PR2 research, debug app databases, or parent-owned flicker/focus files without
  explicit parent reassignment

status / queued work / last prompt / last checked:
  blocked before product edits / route to plan-implementation for one canonical
  pr-ready-unmerged plan / implementation assignment received with the reviewed
  Requirements, Specification, and Program Design but no canonical plan record /
  2026-08-25

receipt expected / receipt level / receipt scope:
  assignment-output receipts per coherent slice, naming exact files, tests,
  commands, results, remaining gaps, and current HEAD/diff identity

parent verification / next follow-up / notes:
  Parent reopens every changed file, validates requirement/design trace, reruns
  scoped gates, and owns commits. Stop on design conflict, overlapping dirty
  ownership, public-contract ambiguity, or a need to widen agent admission.

## 2026-08-25 admission receipt

assignment id:
  ANP-IMPLEMENT-2026-08-25

implementation base:
  branch bridge-review-design-2026-08-14
  HEAD 47cc769a7a4a9ae69f9f7d25c9ae55e7aa91f999

pre-edit verdict:
  blocked

exact discrepancy:
  The assignment supplies a reviewed three-artifact design and direct delivery
  intent, but it does not supply the one canonical implementation-plan record
  required by implement-plan: no plan path, originating planner, planning result
  ready, governing-basis record, requested terminal pr-ready-unmerged, delivery
  grouping, or PR topology. The New/Pending spec folder contains only
  Requirements, Specification, and Program Design. Existing tmp/plan-workflows
  plans are for other deliverables and cannot be reused or silently rewritten.

route / unblock owner:
  plan-implementation must author and return one ready canonical plan for the
  exact New/Pending three-artifact basis with terminal pr-ready-unmerged. The
  implementation sidekick may then validate that immutable record against the
  current HEAD and resume at its smallest ready slice.

pre-existing dirty ownership preserved:
  BridgeWeb Vite product fixture and E2E files, the shared backend/UI coordination
  log, PR2 research artifacts, and this sidekick ledger. No product source,
  tests, database, governing artifact, or existing plan was edited.

proof:
  git status --short --branch identified the existing dirty paths.
  rg --files over the New/Pending spec folder and tmp/plan-workflows confirmed
  that no New/Pending implementation plan exists.

## 2026-08-25 S1 migration RED receipt

canonical plan:
  tmp/plan-workflows/2026-08-25-worktree-annotation-new-pending.md
  ready / pr-ready-unmerged / single:worktree-annotation-new-pending / one-pr

implementation base:
  branch bridge-review-design-2026-08-14
  HEAD baf01aaae7c60c0b2f777851f66c354d9a18a2d8

selected frontier:
  S1 additive nullable positive viewed_saved_revision migration and populated-
  row preservation proof. This frontier is independent of backend repository,
  service, transport, comm-worker coordination, and parent-owned interaction
  files.

failing-first test edit:
  Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/
  WorktreeAnnotationMigrationTests.swift

focused command:
  mise run test:swift -- --filter "WorktreeAnnotationMigrationTests"

RED result:
  exit 1; 7 tests executed; 3 issues across 2 failing tests.
  The complete-schema test found no viewed_saved_revision column and then could
  not require its metadata. The populated-row migration test failed with
  SQLite error 1, no such column: viewed_saved_revision. This is the exact
  expected pre-migration failure. The first sandboxed attempt could not compile
  the SwiftPM manifest because sandbox_apply was denied; the unchanged command
  was rerun with authorization to obtain behavioral RED evidence.

preserved ownership:
  No production file has been edited yet. Existing backend E2E and shared-log
  changes remain untouched.

## 2026-08-25 S1 migration GREEN receipt

implementation base and freshness:
  planned-at HEAD baf01aaae7c60c0b2f777851f66c354d9a18a2d8.
  Shared-worktree HEAD advanced independently to
  57c65cb8bd52c3ed8d0f92f06ff2f5005b5879ca during proof. Neither concurrent
  commit overlaps the two migration-slice files; the canonical plan and three-
  artifact basis remain unchanged.

changed files:
  Sources/AgentStudio/Core/State/MainActor/Persistence/
  WorkspaceLocalMigrations.swift
  Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/
  WorktreeAnnotationMigrationTests.swift

implementation:
  Migration 008 adds nullable viewed_saved_revision with the scalar SQLite
  constraint that every non-null value is positive. It preserves populated
  human handled/unhandled, editable/locked, saved-revision, semantic-revision,
  and draft rows. Existing terminology in this focused test now calls an
  unhandled human revision Pending rather than New.

GREEN proof:
  mise run test:swift -- --filter "WorktreeAnnotationMigrationTests"
  exit 0; 7/7 tests passed in one suite. The final run includes nullable
  default, populated-row/draft preservation, zero rejection, and positive-value
  acceptance.

quality proof:
  swift-format format --in-place on both changed files: exit 0.
  mise run lint after the production migration: exit 0; swift-format OK;
  SwiftLint 0 violations/0 serious across 2,192 files; AgentStudio architecture
  lint OK; release script verification passed. A first lint run exposed one
  slice-local 101-line test-body violation; fixture seeding was extracted and
  the full lint rerun passed. After the final assertion/text adjustment,
  swift-format lint --strict and positional swiftlint lint --strict each passed
  on both changed files with zero violations.
  git diff --check on the two files: exit 0.

diff summary:
  2 files changed, 157 insertions, 2 deletions. No backend-owned E2E file,
  shared coordination log, parent interaction file, product repository/service/
  transport file, generated asset, or debug database was changed or staged.

next bounded slice:
  Parent verification and checkpoint decision first. After follow-up, S1 can
  add the closed Swift author/attention domain invariants or the strict
  BridgeWeb author/attention contract matrix without entering backend mutation
  ownership.

## 2026-08-25 S1 Swift domain receipt

implementation base:
  ff012a1bcfceafa652d7115826be1c86125e955a, which contains the parent-verified
  migration checkpoint. Canonical plan and three-artifact basis unchanged.

selected frontier:
  Closed Swift author/attention vocabulary and pure exact-message New/Pending/
  All derivation only. Repository loading, service, transport, comm worker,
  output, migration, BridgeWeb, and interaction files remain outside this
  checkpoint.

changed files:
  Sources/AgentStudio/Features/Bridge/Models/WorktreeAnnotations/
  WorktreeAnnotationDomainModels.swift
  Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/
  WorktreeAnnotationNewPendingDomainTests.swift (new)

RED proof:
  mise run test:swift -- --filter "WorktreeAnnotationNewPendingDomainTests"
  exit 1 at compilation before any test executed. The compiler reported the
  absent author/attention/validation types, absent projectNewPendingState API,
  absent authorKind/viewedSavedRevision initializer parameters, and therefore
  uninferable closed enum members. This was the expected pre-domain failure.

implementation:
  WorktreeAnnotationAuthorKind closes to human | agent.
  WorktreeAnnotationAttentionState closes to not_applicable | new | viewed.
  WorktreeAnnotationMessage gains authorKind and viewedSavedRevision through an
  explicit initializer whose final two parameters default to .human and nil;
  every existing human call site remains source-compatible.
  projectNewPendingState fails closed for a human viewed marker and for agent
  draft, handled, missing/nonpositive current saved revision, nonpositive
  viewed revision, or viewed revision newer than current. Valid human saved/
  draft/handled combinations preserve PR1 behavior. Valid agent nil/older view
  state is New; exact current view state is Viewed; agent is never Pending.
  isNew is computed from attentionState rather than stored redundantly.

GREEN proof:
  mise run test:swift -- --filter "WorktreeAnnotationNewPendingDomainTests"
  final exit 0; 4/4 tests passed in one suite. The final matrix includes human
  default/Pending, human handled/draft independence, agent nil/exact/older
  viewed revision, and every fail-closed combination including current/viewed
  revision 0 and -1.
  mise run test:swift -- --filter "WorktreeAnnotationDomainPolicyTests"
  exit 0; 5 tests passed in one suite, including the existing five-case unsafe
  Markdown parameter matrix. The final invariant addition did not require this
  unchanged suite to rerun.

quality proof:
  swift-format format --in-place on both files: exit 0.
  final swift-format lint --strict on each file: exit 0.
  final swiftlint lint --strict on each file: exit 0, zero violations/serious.
  tracked git diff --check: exit 0. The untracked-file no-index check emitted
  no whitespace diagnostics; its exit 1 is the normal no-index difference
  status for a new file.

diff summary:
  Domain model +115 lines; one 167-line focused test file added. No other
  tracked or untracked owner path changed by this checkpoint. No commit.

next bounded slice:
  Parent diff verification and checkpoint commit first. Then S1 may consume
  these types at the repository/projection boundary under the appropriate
  backend owner, or proceed independently to strict BridgeWeb contract types.

## 2026-08-25 S1 projection contract parity receipt

implementation base:
  7aaa3f9631e75fca7147acd52f86e4737251626e, containing the committed schema
  and Swift domain checkpoints. Canonical plan and governing artifacts remain
  unchanged.

selected frontier:
  Closed Swift finite-projection DTO plus BridgeWeb raw/decoded Zod parity only.
  No repository/loading, service, transport adapter, operation/call contract,
  comm-worker coordination, output, interaction, or ingress behavior changed.

changed production contracts:
  Sources/AgentStudio/Features/Bridge/Models/Transport/
  BridgeProductWorktreeAnnotationProjectionContracts.swift
  Sources/AgentStudio/Features/Bridge/Models/Transport/
  BridgeProductStrictJSON.swift
  BridgeWeb/src/core/comm-worker/
  bridge-product-worktree-annotation-contracts.ts

direct proof/fixture files:
  Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/
  WorktreeAnnotationProjectionAttentionContractTests.swift (new)
  BridgeWeb/src/core/comm-worker/
  bridge-product-worktree-annotation-contracts.unit.test.ts
  BridgeWeb/src/core/comm-worker/
  bridge-comm-worker-annotation-projection-query-controller.unit.test.ts
  BridgeWeb/src/worktree-annotations/worktree-annotation-browser-test-support.ts
  BridgeWeb/src/worktree-annotations/worktree-annotation-edit-ownership.unit.test.ts
  BridgeWeb/src/worktree-annotations/worktree-annotation-surface-client.unit.test.ts

RED proof:
  mise run test:bridge-web:unit --
  src/core/comm-worker/bridge-product-worktree-annotation-contracts.unit.test.ts
  exit 1; 5 tests, 1 failed and 4 passed. Zod rejected attentionState as the
  exact unrecognized new member.
  mise run test:swift -- --filter
  "WorktreeAnnotationProjectionAttentionContractTests"
  exit 1 at compilation before tests. DTO authorKind was still String and the
  attentionState member did not exist. No backend E2E was executed or involved.

implementation:
  Swift message projection now encodes typed authorKind and attentionState,
  deriving both from WorktreeAnnotationMessage.projectNewPendingState().
  Strict decode admits only closed enum values and reconstructs the minimum
  exact domain state needed to reuse that pure domain invariant; the decoded
  attention must equal the derived attention. Strict JSON admits the new member
  name.
  BridgeWeb raw and decoded schemas require closed author/attention values and
  reject human agent-attention states, agent not_applicable, agent drafts,
  agent handled state, and agent missing current saved content. Existing human
  fixtures now carry human + not_applicable.

GREEN proof:
  focused BridgeWeb contract unit: exit 0, 5/5.
  focused Swift projection contract: exit 0, 2/2.
  affected BridgeWeb unit set (contract, projection controller, surface client,
  edit ownership): exit 0, 34/34 across four files.
  The broader affected run initially exposed one fixture-size sensitivity:
  the required field changed a synthetic chain from two to three pages. The
  mixed-snapshot test now correctly requires at least two pages because its
  semantic proof does not depend on an exact total; the rerun passed.

quality proof:
  pnpm exec tsc --noEmit: exit 0.
  pnpm run check:product-contract: exit 0.
  scoped oxfmt check on six changed BridgeWeb files: exit 0.
  scoped type-aware oxlint on the same files: exit 0, with one pre-existing
  prefer-add-event-listener warning in the projection-controller test.
  swift-format lint --strict and swiftlint lint --strict on all three Swift
  files: exit 0, zero violations/serious.
  git diff --check: exit 0; the untracked Swift test is separately strict-
  formatted/linted.

aggregate check classification:
  mise run test:bridge-web:check exited 1 only on the existing parent-owned
  worktree-annotation-thread.browser.test.tsx max-file-lines gate (1,121 >
  1,000). It stopped before later stages. This slice did not edit that file;
  standalone TypeScript and product-contract checks above are green.

diff summary:
  Eight tracked files: +119/-12. One 152-line Swift contract test added. No
  backend E2E, shared coordination log, repository/loading/service/transport,
  output, interaction component, or debug database changed. No commit.

next bounded slice:
  Parent diff verification and checkpoint commit. The backend owner can then
  load actual author/viewed persistence into the now-closed DTO; UI work can
  later consume the decoded attention state without inventing durable truth.

## 2026-08-25 Browser thread test architecture prefactor receipt

implementation base:
  534ab9cffd3c9232b381357a8f038f55e5126062. This base contains the committed
  projection-contract parity checkpoint. Canonical New/Pending plan and proof
  obligations remain unchanged.

purpose and scope:
  Clear the BridgeWeb max-file-lines architecture gate before adding S3 proof.
  Behavior-preserving Browser Mode test organization only; no production code,
  assertion deletion/weakening, skip, backend E2E, or shared log change.

characterization:
  mise run test:bridge-web:browser --
  src/worktree-annotations/worktree-annotation-thread.browser.test.tsx
  The first sandboxed launch exited 1 before tests because Chrome aborted and
  Playwright could not kill it (kill EPERM). The unchanged authorized rerun
  exited 0 with 18/18 tests in one file.

responsibility split:
  worktree-annotation-thread.browser.test.tsx
    rendering, collapsed/expanded anatomy, Markdown identity, same-coordinate
    selection, focus fallback, summary states, output-control absence, resumed
    edit, tooltip/focus paint, empty-draft Escape, keyboard two-stage Escape,
    and outside-close behavior.
  worktree-annotation-thread-editor-convergence.browser.test.tsx
    durable reply Revert, delayed durable-detail adoption, Save across portal/
    projection remount, second Reply before first projection convergence, and
    overlapping edit-token registration.
  worktree-annotation-thread.browser.test-support.tsx
    shared production-component renderer, projection publication, message and
    stable-ID fixtures, bounded requestAnimationFrame condition wait, and
    deferred-response helper. This extraction removes more than 150 lines of
    otherwise duplicated harness code.

line counts:
  original before: 1,121.
  original after: 587.
  editor-convergence file: 401.
  shared support file: 180.
  Every file is below 600 lines; the original is below the requested 900-line
  ceiling. All 18 original test names remain present exactly once across the
  two Browser files.

post-split proof:
  mise run test:bridge-web:browser -- <both Browser files>
  authorized exit 0; 2/2 files and 18/18 tests passed.
  mise run test:bridge-web:check
  exit 0; type-aware lint, architecture check, whole-repo formatting,
  TypeScript noEmit, and product-contract TypeScript all passed. Existing
  warning-only diagnostics remain non-blocking.
  standalone pnpm exec tsc --noEmit: exit 0.
  scoped oxfmt check on all three files: exit 0.
  scoped type-aware oxlint on all three files: exit 0, no diagnostics.
  git diff --check: exit 0.

changed files:
  BridgeWeb/src/worktree-annotations/worktree-annotation-thread.browser.test.tsx
  BridgeWeb/src/worktree-annotations/
  worktree-annotation-thread-editor-convergence.browser.test.tsx (new)
  BridgeWeb/src/worktree-annotations/
  worktree-annotation-thread.browser.test-support.tsx (new)

next bounded slice:
  Parent verification and checkpoint commit, then resume S3 UI/data-model proof
  against the now-green Browser architecture gate.

## 2026-08-25 S3 derived state and presentation receipt

implementation base:
  66f0955376dde9cbe8517818e9086bb7f8234acd, containing the committed Browser
  test architecture checkpoint. Canonical plan and New/Pending artifacts remain
  unchanged.

scope:
  Pure BridgeWeb derived message state plus shared thread/message presentation.
  Viewed commands, overlays, output readiness, Share scope rename, output
  behavior, backend loading/repository/service/transport, comm-worker
  coordination, backend E2E, and shared coordination log remain untouched.

implementation:
  Added worktree-annotation-message-state.ts as the sole browser predicate owner
  for exact current-saved, New, Pending, All eligibility, and thread counts.
  Share projection and thread presentation consume that helper.
  Shared inline surfaces render You/Y or Agent/A from closed authorKind.
  Exact agent New uses primary blue dot plus text; exact human Pending uses
  warning dot plus text. Multi-message summaries order nonzero New, Pending,
  message count, latest activity, and resolution, omitting zero states and
  adjacent separators.
  Agent messages cannot expose Edit, begin body-click editing, render an editor,
  or acquire draft ownership. Existing Reply remains a human thread action and
  remains available.

RED proof:
  pure unit command for worktree-annotation-message-state.unit.test.ts exited 1
  before tests because the pure module did not exist.
  authorized Browser command for worktree-annotation-thread.browser.test.tsx
  exited 1 with 2 failures and 13 passes: agent still rendered You and no New;
  mixed summary lacked `1 new`. Vitest produced exact failure screenshots.

GREEN proof:
  focused pure-state plus Share unit command: exit 0; 2 files, 11/11 tests.
  focused Browser command: exit 0; 1 file, 15/15 tests. It proves human Pending,
  agent author/avatar/New, no Edit control, agent body click produces no editor
  and no draft.edit.acquire, human Reply remains, collapsed summary ordering,
  expansion, and exact message markers. One intermediate run found a new test
  click missing act(); wrapping the stateful click corrected test mechanics
  without changing product behavior.
  mise run test:bridge-web:check: exit 0; type-aware lint, architecture gate,
  whole-repo format, TypeScript noEmit, and product-contract check passed.
  git diff --check: exit 0.

visual proof:
  tmp/bridgeweb-new-pending-thread.png captured from the passing Browser suite
  and inspected. It visibly shows `1 new · 1 pending · 2 messages`, blue New,
  amber Pending, You/Y human metadata, Agent/A agent metadata, and exact expanded
  message rows. Pierre/comment semantic surfaces remain unchanged.

changed files:
  BridgeWeb/src/worktree-annotations/worktree-annotation-message-state.ts (new)
  BridgeWeb/src/worktree-annotations/worktree-annotation-message-state.unit.test.ts (new)
  BridgeWeb/src/worktree-annotations/worktree-annotation-share-projection.ts
  BridgeWeb/src/worktree-annotations/worktree-annotation-share-projection.unit.test.ts
  BridgeWeb/src/worktree-annotations/worktree-annotation-inline-surface.tsx
  BridgeWeb/src/worktree-annotations/worktree-annotation-thread-message.tsx
  BridgeWeb/src/worktree-annotations/worktree-annotation-compact-thread.tsx
  BridgeWeb/src/worktree-annotations/worktree-annotation-thread.browser.test.tsx

diff summary:
  Six tracked files +135/-34 and two new files totaling 128 lines. No commit.

remaining S3 blocker:
  Deliberate-view command dispatch, command-confirmed overlay, convergence
  readiness fence, and passive-versus-explicit mutation proof remain blocked on
  backend S2 and were not approximated in React.
