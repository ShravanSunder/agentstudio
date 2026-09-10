# PR1 Durable Human Annotations — Implementation Plan

Planning result: `stale — do not execute`

This plan predates the 2026-08-16 inline-comments-only correction. Its
whole-file/session comment UI, session-management chrome, and former component
anatomy are no longer authorized by the current Requirements, Specification,
or Program Design. Replan from those three artifacts before further PR1 UI
implementation.

## Governing planning basis

- Kind: `reviewed-three-artifact-design`
- Requirements:
  [`../pr1-user-requirements.md`](../pr1-user-requirements.md)
- Specification:
  [`../pr1-specification.md`](../pr1-specification.md)
- Program Design:
  [`../pr1-program-design.md`](../pr1-program-design.md)
- Independent review invocation:
  `pr1-three-artifact-review-a5de3efe0-2026-08-15`
- Independent review result:
  `/root/pr1_design_review`, complete, candidate recommendation
  `needs-revision`, parent-reduced at HEAD
  `a5de3efe0c8da4005657448a1bb282fb02908340`
- Parent-verified single remediation:
  - `PR1-MCR-001` corrected by the idempotent cancel-attempt failure/restart
    contract in Program Design, “One batch, two output effects” and “Failure,
    partial success, and recovery”.
  - `PR1-MCR-002` corrected by the bounded 64 KiB complete-message entry and
    maximum-legal singleton-frame contract in Program Design.
  - `PR1-MCR-003` corrected by the annotation-specific safe-link sanitizer and
    existing `BridgeNavigationDecider` boundary in Program Design.
- Design review closure: original complete review plus the parent-verified
  remediation above. The review contract forbids an automatic second review.
- Planned branch: `bridge-review-design-2026-08-14`
- Planned HEAD: `a5de3efe0c8da4005657448a1bb282fb02908340`
- `origin/main` was merged into this branch immediately before design review;
  no main integration remains pending at planning time.

## Delivery context

- Requested terminal: `pr-ready-unmerged`
- Delivery grouping: `single:pr1-durable-human-annotations`
- PR topology: `one-pr`
- Tracking: none; no issue tracker mutation is part of delivery.
- Plan home: this checked-in spec-local plan follows the repository project
  contract for implementation plans. It is the sole canonical plan.

## Goal

Ship one human-only durable review loop across existing File View and Review
View. A reviewer can create source-backed threads, recover drafts, explicitly
save immutable output-eligible message versions, reply in flat threads, resolve
or reopen whole threads, copy selected messages as deterministic Markdown, or
export the same batch as versioned JSON. The loop survives reload/restart and
continues after worktree changes without making Agent Studio an agent-delivery
system.

```text
Pierre source/diff selection
            │
            ▼
BridgeWeb editor + draft scheduler
            │ typed File/Review product call
            ▼
WorktreeAnnotationStore
            │ transaction commits first
            ▼
WorktreeAnnotationSQLiteRepository ──► local.sqlite authority
            │ committed compact delta
            ▼
WorktreeAnnotationProjectionAtom ──► demanded File/Review projections
            │
            ├─► inline thread UI
            └─► selected saved versions
                     │
                     ▼
          exact immutable output batch
              ├─► clipboard Markdown
              └─► versioned JSON file
```

## Scope and protected boundaries

In scope:

- application-global, worktree-lineage annotation sessions in `local.sqlite`;
- first-edit durable drafts, explicit per-message Save/Revert, human flat
  replies, whole-thread resolve/reopen, session finish/reopen and continuity;
- located, whole-file, and session-level threads in the main viewer surface;
- exact/relocated/outdated/unavailable placement;
- safe Markdown messages with H2–H6, no H1/raw HTML, safe HTTP(S) links, and a
  16 KiB UTF-8 body limit per root/reply/draft/version;
- complete-message transport inside 128 KiB frames without splitting or
  rejecting a valid admitted message;
- deterministic clipboard Markdown and strict versioned JSON file output;
- exact prepared batches, output events/history, provisional/permanent message
  locks, partial success, crash-unknown recovery, and explicit repetition;
- fail-closed annotation recovery provenance after local database quarantine;
- owned shadcn primitives and Pierre 1.2.10 annotation APIs;
- Vite + real Swift development backend proof and packaged App proof.

Non-goals:

- agent identity, delivery, acknowledgement, agent replies, providers, Codex
  App Server, or App IPC annotation methods;
- thread/message deletion, a comment sidebar, rendered-Markdown selection
  source mapping, batch Save, guided review, or multi-user collaboration;
- a Pierre upgrade, second physical Bridge transport, Atom persistence
  authority, global service locator, or compatibility shim;
- automatic Copy/Export replay or claims that an external agent addressed a
  comment.

## Current evidence and constraints

- `WorkspaceLocalMigrations` owns `local.sqlite` schema changes.
- `WorkspaceSQLiteDatastore` owns local database opening, quarantine, and
  replacement; `SQLiteSidecarQuarantine` already returns quarantine filenames.
- `PersistenceRecoveryReporter` and App notification composition already expose
  recovery events, but no durable recovery witness currently distinguishes a
  replaced database from a database that never held annotations.
- `AtomRegistry` is App-only and explicitly retains Feature atoms. It may retain
  the annotation projection Atom, never the Store or repository as ambient
  state.
- Inbox Notification supplies repository/adapter placement precedent, but its
  Atom-observation snapshot saver is explicitly not the annotation mutation
  pattern.
- Bridge product transport has exhaustive Swift/TypeScript call and subscription
  registries, strict JSON, sequencing, resync, and a 128 KiB metadata-frame
  ceiling. Extend those owners; do not add a parallel transport.
- The Swift development backend uses the production datastore/Core/Bridge and
  isolated `core.sqlite`/`local.sqlite`; it must compose the annotation Store so
  Vite exercises real persistence.
- BridgeWeb owns shadcn-style source under `BridgeWeb/src/components/ui/`.
  Sonner is absent and must be added through the configured shadcn CLI, then
  product tokens/sizing are edited in the owned primitive.
- Pierre stays at `@pierre/diffs` 1.2.10. The required installed APIs are
  `LineAnnotation<T>`, `DiffLineAnnotation<T>`, `renderAnnotation`,
  `setSelectedLines`, `scrollTo`, `onGutterUtilityClick`, and
  `onLineSelectionEnd`.
- The current Markdown worker disables raw HTML and automatic URL linkification;
  the document-preview sanitizer strips `href`. Annotation rendering therefore
  needs its own narrow sanitizer policy while reusing parser/Shiki work.
- `BridgeNavigationDecider` already opens HTTP(S) externally and blocks other
  schemes from navigating the bundled pane.

## Target UI composition

```text
FileViewer / ReviewViewer
  └─ shared WorktreeAnnotationSurface
      ├─ session strip
      │   ├─ Button / DropdownMenu / Alert
      │   └─ session-level thread region
      ├─ whole-file thread region
      ├─ Pierre CodeView 1.2.10
      │   ├─ gutter utility → line/range selection
      │   ├─ LineAnnotation / DiffLineAnnotation
      │   └─ renderAnnotation → WorktreeAnnotationThread
      ├─ degraded-thread region
      │   └─ outdated/unavailable threads in the same main surface
      └─ output interaction
          ├─ Toggle / Checkbox-compatible selection controls
          ├─ Popover + Button: Copy Markdown / Export JSON
          └─ owned Sonner Toaster: “Copied N comments”

WorktreeAnnotationThread
  ├─ safe Markdown rendering
  ├─ flat saved root/replies
  ├─ Textarea composer
  ├─ Button: Save / Revert / Reply
  └─ Button: Resolve thread / Reopen thread

No sidebar and no route-local substitute for a shadcn primitive.
```

## Slice graph

```text
S1 durable domain + migration
       │
       ├──────────────► S2 Store/projection/recovery
       │                         │
       │                         ▼
       └──────────────► S3 product transport + dev-server composition
                                  │
                                  ▼
                         S4 BridgeWeb authoring + Pierre
                                  │
                     ┌────────────┴────────────┐
                     ▼                         ▼
             S5 continuity/placement    S6 output coordinator/projectors
                     │                         │
                     └────────────┬────────────┘
                                  ▼
                      S7 real effects + history UI
                                  │
                                  ▼
                      S8 integrated runtime proof
                                  │
                                  ▼
                      S9 full gates + review + PR
```

Required edges:

- `S1 -> S2`: Store transactions require the schema/domain invariants.
- `S2 -> S3`: transport publishes only committed Store projections.
- `S3 -> S4`: UI must exercise the real typed product boundary.
- `S3 -> S5` and `S3 -> S6`: placement/output commands require real transport.
- `S4 + S5 + S6 -> S7`: final output/history UI consumes authored sessions and
  native output semantics.
- `S1..S7 -> S8`: runtime proof must use the integrated path.
- `S8 -> S9`: no PR readiness before manual/runtime evidence exists.

No slice is authorized to invent a new owner or widen PR1. Stop and return to
Program Design if any path requires pane-local authority, Atom-triggered saves,
an App IPC method, a second transport, or an unplanned source-map subsystem.

## Proof-bearing slices

### S1 — Establish the durable annotation domain and schema

Write surfaces:

- new Bridge-owned models/policies under
  `Sources/AgentStudio/Features/Bridge/Models/WorktreeAnnotations/`;
- `WorkspaceLocalMigrations.swift` for one additive hard-cut migration;
- new Bridge persistence files under
  `Sources/AgentStudio/Features/Bridge/State/MainActor/Persistence/`;
- focused Swift Testing support under
  `Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/`.

Behavior:

1. Define UUIDv7-backed session, thread, message, saved-version, draft,
   output-attempt, and output-event identities and strict enums for lifecycle,
   relationship, placement, scope, resolution, readiness, output kind/status,
   and source role.
2. Add normalized tables and constraints for sessions, threads, messages,
   immutable saved versions, at-most-one draft, output attempts/membership,
   output events/exact bytes, and application-local recovery provenance.
3. Key discovery by stable worktree lineage only; workspace is nullable
   provenance and never a key or filter.
4. Enforce flat message ordinals, whole-thread resolution, append-only saved
   versions, 16 KiB UTF-8 bodies, immutable output locks, strict JSON/version
   fields, and transaction-level expected revisions.
5. Implement repository transactions for zero/one/several session discovery;
   atomic first-session+root-draft creation; draft flush; Save/Revert; reply;
   resolve/reopen; finish/reopen; continuity; output prepare/cancel/finalize;
   output inspection/repetition; and recovery acknowledgement.

Red-first proof:

- migration schema/constraint tests fail before the migration exists;
- repository tests cover zero/one/several session admission, same-worktree
  cross-workspace discovery, flat ordering, draft/version transitions,
  immutable output locks, stale revisions/edit tokens, message-size UTF-8
  boundaries, whole-thread state, and no delete operation;
- output transaction tests cover exact membership/bytes and idempotent
  cancel/finalize.

Focused gate:

`mise run test:swift -- --filter WorktreeAnnotation`

Stop/replan if current local datastore access cannot expose transaction-scoped
repository work without making the repository or Store ambient.

### S2 — Make the Store the only mutation/query/demand coordinator

Write surfaces:

- `WorktreeAnnotationStore`, `WorktreeAnnotationProjectionAtom`, compact
  projection/delta models, source/output protocols, and datastore adapter in
  the Bridge Feature;
- `AtomRegistry.swift` for explicit projection-Atom retention only;
- App boot composition for one application-scoped Store;
- `WorkspaceSQLiteDatastore` recovery replacement path,
  `PersistenceRecoveryEvent`, and focused recovery tests.

Behavior:

1. Every semantic command runs Store -> authoritative repository transaction ->
   committed delta -> projection Atom. Atom changes never trigger persistence.
2. Demand is keyed by worktree/session. Discovery summaries stay bounded;
   active detail hydrates on first demand and evicts at zero demand without a
   save or delete.
3. Persist quarantine filenames/reason/time into the fresh database before it
   becomes available. Hydrate annotations as recovered-degraded while an
   unacknowledged witness exists; reject mutations until acknowledgement sets
   `acknowledgedAt` without deleting witness/files.
4. Extend the existing recovery event vocabulary and App notification seam;
   malformed annotation rows and hydration failures publish unavailable, never
   an empty fabricated replacement.

```text
command ─► Store ─► repository transaction
                         │ commit
                         ▼
                    compact delta ─► ProjectionAtom ─► viewers

loading / demand eviction ───────────────────────────► ProjectionAtom only
ProjectionAtom ──X──► repository save
```

Red-first proof:

- commit-before-publication and failed-transaction unchanged-projection tests;
- multi-demand acquire/release and eviction/reload tests;
- static/behavioral tests proving loading/display mutations do not persist and
  exact historical bytes never enter Atom state;
- corrupt/incomplete `local.sqlite` integration proving filenames are witnessed
  before hydration, pre-ack mutation fails, acknowledgement persists, restart
  distinguishes recovered-degraded from never-created, and sidecars remain.

Integration gate S1->S2: restart with real `local.sqlite` must restore a draft,
saved versions, thread/session state, and exact output attempt without reading
from Atom state.

### S3 — Extend the existing typed product transport and development host

Write surfaces:

- Swift call/subscription DTOs and exhaustive registries under
  `Features/Bridge/Models/Transport`;
- paired File/Review command adapters and one annotation projection producer;
- `BridgePaneController` dependency injection and App composition;
- TypeScript schemas/registries/client under
  `BridgeWeb/src/core/comm-worker/` and a shared annotation client;
- `AgentStudioBridgeDevelopmentServer` and `BridgeDevelopmentProductHost`
  composition using the same isolated datastore/Store.

Behavior:

1. Register paired File/Review calls for discovery, demand, create/reply, draft
   flush, Save/Revert, resolve/reopen, finish/reopen, continuity choice, output
   preparation/history/repetition, and recovery acknowledgement. Register no
   delete or App IPC method.
2. Carry compact source identity/coordinates from browser to native; validate
   against current File/Review material and capture excerpts natively.
3. Publish demanded projections with the bounded complete-message DTO. Each
   entry is at most 64 KiB; singleton maximum legal context+entry+envelope fits
   128 KiB; packing never splits or rejects an admitted message.
4. Preserve existing sequencing, authentication, correlation, resync,
   backpressure, and physical routes.
5. Make the Swift development server construct the same Store/repository and
   persist through its isolated `local.sqlite`, so server restart is a real
   annotation restart proof.

Red-first proof:

- Swift/TS strict codec and exhaustive-registry tests;
- maximum legal singleton and multi-message packing boundary tests;
- invalid source identity/range, stale revision, wrong surface, oversized body,
  unknown field/version, and resync tests;
- development HTTP integration that creates a draft, shuts down, restarts on
  the same isolated root, and reads the committed draft/session.

Focused gates:

- `mise run test:swift -- --filter WorktreeAnnotation`
- `pnpm --dir BridgeWeb run test:unit`
- `pnpm --dir BridgeWeb run test:integration:node:prepared`

### S4 — Build shared authoring UI and integrate Pierre 1.2.10

Write surfaces:

- `BridgeWeb/src/worktree-annotations/` shared contracts, store bindings,
  scheduler, policies, editor/thread/surface components, and tests;
- File and Review CodeView composition adapters;
- existing shared shadcn primitives only, adding missing owned primitives via
  the configured shadcn CLI before product composition;
- annotation-specific Markdown sanitizer/renderer tests.

Behavior:

1. Use Pierre `onGutterUtilityClick` and `onLineSelectionEnd` to admit located
   selection, `setSelectedLines` to reflect/clear selection, `LineAnnotation`
   and `DiffLineAnnotation` plus `renderAnnotation` to place exact/relocated
   threads, and `scrollTo` for explicit reveal. Do not write scroll position
   outside Pierre or upgrade the dependency.
2. Share File/Review controls and visual scale. Compose `Button`, `Textarea`,
   `Popover`, `Tooltip`, `Separator`, `Alert`, and selection primitives from
   `BridgeWeb/src/components/ui/`; no route-local substitute controls.
3. Persist the first non-empty edit immediately. While focused, coalesce per
   message at one-second debounce with five-second maximum wait using an
   injected scheduler/clock; flush on focus loss and Save. Suppress equal
   acknowledged bodies, never wall-clock sleep in tests.
4. Save only after latest draft commit; Revert restores latest saved version or
   removes never-saved draft. Preserve unsent editor text on rejection/conflict.
5. Render flat human replies, whole-thread resolve/reopen, saved/draft/locked
   distinctions, session/whole-file/located scopes, and no sidebar.
6. Reuse Markdown worker parsing/Shiki but apply an annotation-specific
   sanitizer that admits only absolute HTTP(S) `href`; rely on
   `BridgeNavigationDecider` for external opening and scheme blocking.

Red-first proof:

- injected-scheduler unit tests for first edit, debounce, max wait, focus loss,
  Save ordering, equality suppression, cancellation, and conflict retention;
- safe Markdown cases for ATX/setext H1, raw HTML, H2-H6, tables/code/lists,
  safe HTTP(S) links, and blocked schemes/attributes;
- Pierre adapter unit/browser tests using the actual installed APIs;
- browser interaction tests for root, reply, Save/Revert, resolution/reopen,
  File/Review shared behavior, and accessibility/focus.

Focused gates:

- `pnpm --dir BridgeWeb run check`
- `pnpm --dir BridgeWeb run test:browser:integration`

Stop/replan if Pierre cannot represent one inline portal per located thread
without introducing another scroll/selection authority. Use the designed
same-surface degraded region for outdated/unavailable threads; do not fabricate
line slots.

### S5 — Realize continuity, placement, and session lifecycle

Write surfaces:

- `WorktreeAnnotationSourceEvaluator` and bounded `agentstudio-git` adapter;
- Store placement/continuity commands and projections;
- shared File/Review session/degraded-region UI and integration tests.

Behavior:

1. File source uses stable repo/worktree source identity; Review adds PR0
   comparison origin. Paths/branch labels alone never prove continuity.
2. Proven same remains applicable; missing/conflicting evidence becomes
   uncertain and pauses new mutation; proven different lineage becomes detached
   without completing.
3. Evaluate immutable origin into exact/relocated/outdated/unavailable. Preserve
   origin forever; unique rename/context relocation is the only relocated path.
4. Show exact/relocated threads in Pierre slots. Show outdated/unavailable in a
   degraded-thread region in the same main surface with original path/range and
   verify-location warning.
5. Expose zero-session implicit creation, one-session continuation,
   several-session explicit choice, count-only finish warning, explicit
   finish/reopen, and independent whole-thread resolution.

Red-first proof:

- controlled real-Git fixtures for exact, unique relocation, ambiguous/outdated,
  unavailable, same/uncertain/different lineage, and source-epoch races;
- Store transition matrix tests;
- File/Review browser journeys for discovery and same-surface degraded threads;
- finish warning proves count only and never auto-resolves.

### S6 — Implement deterministic batch projection and failure-safe output state

Write surfaces:

- `WorktreeAnnotationBatchProjector`, Markdown/JSON DTO validators, and tests;
- `WorktreeAnnotationOutputCoordinator`, output-effect protocol, repository
  output transitions, and focused tests.

Behavior:

1. Snapshot exactly the selected saved message versions once, with deterministic
   session/path/scope/line/identity order; drafts never enter output.
2. Markdown owns exactly one H1, plain labels, `---` separators, path and
   current/original lines, diff side, placement, visibly numbered excerpts,
   adaptive fences, and byte-for-byte authored Markdown.
3. JSON v1 represents the same batch order/membership losslessly and rejects
   unknown versions, fields, discriminants, duplicates, or order mismatch.
4. Prepare transaction persists exact bytes/membership and provisional locks
   before any effect. Known failure runs idempotent cancel. Cancel persistence
   failure reports effect+cleanup separately, retains locks, and retries cleanup
   only while proof is live. Known success/finalization failure is partial
   success. Crash/lost response recovers unknown and never replays.
5. Successful or unknown output locks included messages; correction is a new
   human reply. No output transition changes thread resolution.

```text
select saved versions
       │
       ▼
prepare transaction ──► exact bytes + membership + provisional locks
       │ commit
       ▼
native effect
  ├─ known failure ─► idempotent cancel
  │                    ├─ commit: release eligible locks
  │                    └─ fail: retain + report cleanup failure
  ├─ known success ─► finalize event
  │                    └─ fail: visible partial success, never replay
  └─ lost result/crash ─► unknown on recovery, exact explicit repeat only
```

Red-first proof:

- deterministic permutation/golden-semantic tests without brittle formatting
  snapshots where structured assertions are clearer;
- line-number and adaptive-fence boundary tests;
- JSON round trip and strict rejection matrix;
- injected effect tests for generation failure, panel cancellation, known
  failure, cancel-transaction failure/retry/restart, success, finalization
  failure, crash-unknown, explicit exact-byte repetition, and lock overlap.

### S7 — Wire real clipboard/file effects and output/history UI

Write surfaces:

- App-owned `WorktreeAnnotationOutputEffects` implementation and injection into
  the Store/coordinator;
- BridgeWeb output selection/history components;
- shadcn-generated `BridgeWeb/src/components/ui/sonner.tsx`, dependency lockfile,
  and root `Toaster` composition;
- packaged App effect tests/manual harnesses already admitted by the repo.

Behavior:

1. Use `NSPasteboard` replacement for Copy and `NSSavePanel` followed by atomic
   file write for Export. Destination selection precedes prepare; cancellation
   creates no attempt/file/history.
2. Invoke shadcn from the configured BridgeWeb project to add Sonner; inspect
   generated source/dependency changes, then adapt the owned primitive to Agent
   Studio tokens and sizing. Do not hand-write route-local toast markup.
3. Normal Copy shows `Copied N comments`, closes only the copy interaction, and
   leaves threads open/visible. Export reports the actual selected file result.
4. History lists bounded summaries and fetches exact details/bytes on demand;
   inspect/repeat never rebuilds current content.
5. Partial and unknown states say exactly what is and is not proven.

Red-first proof:

- fake-effect unit/integration tests remain in S6; S7 adds real App boundary
  tests where feasible and packaged manual proof for actual clipboard and file;
- browser tests cover selection, toast, interaction close, open-thread
  preservation, history inspection, and explicit repetition;
- visual screenshots prove shared geometry, focus, status, and toast placement.

### S8 — Prove the real development loop and packaged App journeys

Development-server loop:

1. `mise run build-bridge-development-server`
2. Create an isolated root with `mktemp -d` and start
   `.build-bridge-development-server/agentstudio-bridge-dev-server` seeded to
   this worktree and `HEAD` on a unique port.
3. Start `pnpm --dir BridgeWeb run dev` and use the real Vite worktree fixture
   for File and Review.
4. Exercise create, first-edit persistence, Save/Revert, reply, resolve/reopen,
   selection, placement, session finish/reopen, and output-history UI through
   the real Swift backend.
5. Stop only exact agent-launched PIDs, restart backend on the same isolated
   root, and prove draft/session/history recovery. Never touch another running
   Agent Studio or browser process.

Packaged App proof:

1. Build and launch the worktree-isolated debug App through the repository's
   supported debug launcher with exact identity/PID targeting.
2. Verify File View and Review View annotation creation and Pierre placement.
3. Inspect actual system clipboard Markdown: one H1, repository-relative file,
   current/original line reference, visible numbered excerpt, separators, and
   unchanged H2-H6 authored body.
4. Export JSON through the actual save panel to an isolated temporary path;
   parse and validate format/order/membership, then confirm output history.
5. Capture screenshots for root/reply draft state, exact/relocated/degraded
   placement, output selection, Copy toast, history, resolve/reopen, finish
   warning, and recovery-degraded acknowledgement when feasible.
6. Verify HTTP(S) annotation link opens externally through the existing native
   navigation policy and a blocked scheme does not navigate.

Manual proof is not replaced by jsdom, mocked browser tests, or the Vite backend
for clipboard/save-panel/WKWebView/App lifecycle claims.

### S9 — Complete quality gates, independent implementation review, and PR

Required local gates on the final implementation HEAD:

```text
mise run format
mise run lint
mise run test
git diff --check
```

Also inspect:

- no file over 900 lines; split new files near 600 lines by responsibility;
- no `any`, no wall-clock sleeps, UUIDv7 used for new identities;
- no Atom observation persistence trigger;
- no PR2, sidebar, delete, App IPC, rendered-preview source-map, or Pierre
  upgrade residue;
- no route-local fake shadcn controls and no direct scroll writer outside
  Pierre `scrollTo`;
- exact output bytes absent from Atom state and telemetry.

Then:

1. Run one bounded fresh implementation review against the current plan,
   governing artifacts, exact diff, tests, and manual proof.
2. Apply only accepted implementation-owned remediation within the orchestrator
   limit and rerun affected/full gates.
3. Commit scoped work, push the current branch, open/update one PR, and verify
   checks, review threads/comments, mergeability, and exact head.
4. Stop at PR-ready and unmerged. Merge requires separate authority.

## Obligation-to-proof map

| Obligations | Realization slices | Minimum observable proof |
| --- | --- | --- |
| P1-U1/U13, R-P1-001 | S1-S5 | zero/one/several discovery, cross-workspace same-worktree identity, first-annotation atomic creation, File/Review continuation |
| P1-U2/U3, R-P1-003/004/006 | S1-S4, S8 | injected scheduler, SQLite restart, Save/Revert UI, unsent conflict retention |
| P1-U4, R-P1-005/017 | S1/S3/S4 | UTF-8 boundaries, maximum singleton/frame packing, safe Markdown/link rendering and native navigation |
| P1-U5/U6, R-P1-002/007 | S3-S5 | Pierre source/diff admission, real-Git exact/relocated/outdated/unavailable, same-surface degraded region |
| P1-U7/U8, R-P1-008/009 | S1/S2/S5 | continuity/lifecycle state matrix, count-only finish warning, explicit reopen, whole-thread resolution |
| P1-U9/U10, R-P1-010/011 | S6-S8 | deterministic selected batch, actual clipboard bytes with path/line/numbered excerpt |
| P1-U11, R-P1-012 | S6-S8 | strict JSON validator plus actual save-panel file |
| P1-U12, R-P1-013 | S1/S6/S7/S8 | prepare/effect/finalize failure matrix, restart unknown, exact history/repetition, real effects |
| P1-U14, R-P1-014/016 | S1-S5/S7 | flat replies, immutable output messages, new-reply correction, resolve/reopen across views |
| R-P1-015 and negative space | all, S9 | architecture/static inspection plus absence scans |
| fail-closed recovery | S1/S2/S8 | quarantine witness, pre-ack rejection, acknowledgement retention, restart distinction |

## Integration gates and false-green risks

```text
repository unit green
    does not prove Store commit-before-publication
        └─► require S2 real repository integration

mock transport green
    does not prove Swift/TS exhaustive codec or frame fit
        └─► require S3 real product transport + dev HTTP integration

DOM unit green
    does not prove Pierre geometry, focus, or rendering
        └─► require S4 browser + S8 screenshot proof

fake effect green
    does not prove NSPasteboard/NSSavePanel/atomic write
        └─► require S7/S8 packaged App proof

Vite restart green
    does not prove WKWebView or App lifecycle
        └─► require S8 packaged debug App

full suite green
    does not prove actual copied/exported bytes or PR state
        └─► require manual output inspection + S9 PR wrap-up
```

## Risks and stop/replan conditions

- Stop for a design break if `local.sqlite` cannot provide atomic annotation
  transactions through the existing datastore without moving authority to Core
  or Atom state.
- Stop if worktree lineage identity is not available consistently to both File
  and Review; do not substitute workspace, pane, path, or branch labels.
- Stop if source relocation needs a new Git owner or broad comparison redesign;
  return to Program Design rather than shelling out from production TypeScript.
- Stop if the current static product transport cannot publish demanded
  annotations without a new physical route or content protocol; measured frame
  pressure is the revisit evidence.
- Stop if Pierre 1.2.10 cannot support required inline placement through its
  declared annotation APIs; do not upgrade or write a competing overlay/scroll
  system.
- Stop if safe annotation links require widening document-preview sanitization
  or navigation schemes beyond HTTP(S); keep the annotation policy separate.
- Stop before changing unrelated test/lint/build/CI infrastructure. Report an
  out-of-scope gate failure with scoped evidence and ask for authority.
- Preserve all unrelated dirty/untracked work. Never use destructive Git or
  broad process cleanup.

## Ready result

The plan is `ready` for direct `implement-plan` execution. It carries current
reviewed authority, one parent-verified design remediation, a single-PR
`pr-ready-unmerged` delivery context, proof-bearing vertical slices, and no
generic approval checkpoint.
