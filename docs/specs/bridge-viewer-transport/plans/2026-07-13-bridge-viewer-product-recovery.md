# Bridge Viewer Product Recovery Implementation Plan

Status: accepted after the one permitted external plan review and one parent
remediation pass. Ready for `implementation-execute-plan`.

Goal id: `2026-07-13-bridge-recovery`

Recovery anchor: `38fe66aefda5df752f7f5c211de74c9d126eec3a`

## 1. Outcome

Restore the actual Bridge File View and Review product while completing the
transport hard cut:

- File View streams and assembles the complete selected text file off-main,
  gives Pierre one complete supported item, keeps tree and content painted
  through sustained deep scrolling, and reaches independently verified final
  source content.
- Review restores its hierarchical `@pierre/trees` navigation and one continuous
  multi-file Pierre CodeView with search, composed facets, projection modes,
  reveal, selection, directory/file/hunk collapse, hunk expansion, sanitized
  markdown, and selected/visible complete-item hydration.
- File and Review trees start fully expanded on every fresh/source-reset source;
  same-source appends preserve a user's manual collapse and open newly streamed
  directories.
- a retained same-identity Pierre `CodeView` is reconciled to the complete
  authoritative ordered manifest even if its live membership was reduced to a
  selected-only subset.
- one pane comm worker owns accepted metadata/projection/selection, protocol,
  freshness, demand, complete-item cache/residency, retry and availability;
  React owns only synchronous UI intent/ephemera and bounded display copies.
- deterministic-fixture Vite, real-worktree Vite, and packaged Swift
  `agentstudio-git` implement one source contract and exercise the same worker,
  restored UI, Pierre adapter and disposition path.
- Pierre remains unmodified. Public complete-item APIs are the dependency floor.
- the final PR is created or updated and proven ready, but not merged.

## 2. Source Coverage And Authority

The parent read and reduced the complete 1,998-line accepted spec:

- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`

Normative supporting product specs remain in force where the accepted spec does
not explicitly supersede them:

- `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md`
- `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`

Creation evidence:

- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/plan-ledger.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/codebase-boundary.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/validation-proof.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/security-reliability.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/vertical-slice-decomposition.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/execution-order.md`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-product-recovery/lanes/scope-and-proof-fit.md`
- `tmp/spec-review-workflows/2026-07-13-bridge-recovery/reduction.md`

The two older plans are broken historical evidence, not execution authority.
They are retired only after this plan completes its capped review:

- `tmp/plan-workflows/2026-07-12-bridge-viewer-contract-recovery/`
- `tmp/plan-workflows/2026-07-13-bridge-viewer-hard-cut-loop/`

## 3. Non-Goals And Hard Boundaries

- no Pierre repository, fork, patch, private API, `patch-package`, local-path
  dependency, or required upstream release;
- no permanent File size/line prefix, cap, fabricated whitespace, fabricated
  extent, or size-based terminal state;
- no old and new product owner for one surface;
- no restored main Zustand product store, projection-worker owner, page/native
  relay, package-first startup, feature worker factory, or mocked viewer bypass;
- no main-side source fetch/decode/diff/cache/retry/residency;
- no automatic `flat -> recovered` fallback or runtime shell retargeting;
- no proof weakening, skipped required layer, or shallow readiness/count claim;
- no broad restore/checkout/reset/cleanup in the dirty worktree;
- no unrelated infrastructure changes without explicit user authority; and
- no merge.

## 4. Current Failure Baseline

The executor records fresh evidence at G0, but these are the known RED facts:

1. Review mounts `bridge-app-review-direct-viewer-shell.tsx`, displays flat
   depth-zero file rows, and renders only one selected item.
2. hierarchical Review store/controller/projection/test pieces were deleted from
   the worktree but remain recoverable at the pinned HEAD.
3. File View disappears after sustained deep tree/content scrolling, and no
   permanent regression currently proves the failure.
4. Vite and Swift File paths still contain prefix/preview semantics, including a
   Vite 10,000-line contract.
5. one dedicated Vite E2E configuration does not yet exercise deterministic
   and disposable live-worktree scenarios through one product path.
6. current browser/native proof can pass on `ready`, counts, or markers without
   correlating source bytes to readable DOM and disposition.
7. Review update/select may publish the same job twice.
8. `selectedReviewPreparationIdentity` is referenced but not defined.
9. TypeScript exits 2, packaged BridgeWeb build exits 1, Swift hard-cut static
   proof is RED, and packaged WKWebView/performance/CI/PR proof is incomplete.

G0 must preserve these failures as permanent RED witnesses before a behavior
owner is changed. A witness that cannot fail for the expected reason is repaired
before implementation proceeds.

## 5. Accepted Architecture And Policy Freeze

```text
Swift provider/source authority
  -> capable, bounded, cancellable product call/metadata/content POST streams
  -> one pane comm worker
       owns accepted metadata, hierarchy/projection, selection, freshness,
       demand, complete bytes/items, cache/residency, retry and availability
  -> bounded keyed display patches + complete ready-item publications
  -> React local UI intent + bounded presentation adapter
  -> public Pierre addItems/updateItem/scrollTo
  -> readable DOM
  -> matching disposition back to the comm worker
```

### 5.1 Complete-item admission and eviction

- demand rank is selected, visible, nearby, speculative, then background;
- selected work preempts lower ranks without starving visible work;
- main publication admission is bounded by pending item count and encoded bytes;
- selected/visible items and publications awaiting a terminal disposition are
  protected from eviction;
- only offscreen, unprotected complete items are LRU-evictable;
- eviction removes residency, never source bytes from an in-flight complete
  assembly and never changes a current semantic item to size-based terminal;
- demand remains re-derivable after reject, supersession, missing receipt or
  eviction; and
- numeric residency/admission ceilings are not invented now. S8b establishes a
  falsifiable baseline; any proposed number must preserve all release gates;
- the nonnumeric policy shape is worker-owned at
  `BridgeWeb/src/core/comm-worker/bridge-worker-complete-item-admission-policy.ts`
  from S4a onward; S8b may bind measured numeric constants in
  `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts`; and
- the legacy Review projection window-budget file is never a live policy owner.

### 5.2 Reset and freshness

- `sourceGeneration` remains Swift-owned; each surface has its own worker
  derivation epoch under one pane worker;
- stale generation/epoch/sequence/instance work is discarded before mutation;
- source or transport churn alone does not mint semantic identity, demote an
  unchanged ready item, or authorize fabricated loading;
- worker replacement raises an instance barrier, cancels prior work, ignores
  late messages/dispositions, rebuilds demand from current FE facts, and proves
  zero native producer residue;
- pane teardown cancels streams/workers and leaves zero residue; and
- one semantic fingerprint has one publication chain after coalescence.

### 5.3 Closed Pierre reconciliation and remount rules

- append-only ordered additions use `addItems`;
- same-id content, name, annotation or collapse changes use `updateItem` with a
  changed content cache key when rendered content/name changes and a changed
  adapter version whenever the final Pierre record changes;
- removal, reorder or projection-layout identity change creates a new layout
  epoch and controlled CodeView instance;
- a stable item id never changes item type; a type change receives a new id;
- source generation, lease, stream, worker restart or metadata retouch alone
  does not trigger a remount when semantic order/type/content is unchanged;
- Pierre `scrollTo` is the only programmatic CodeView viewport writer;
- active momentum vetoes programmatic reveal; hydration never re-arms a settled
  reveal; and
- explicit current reveal intent is keyed to item/layout/intent identity.

### 5.4 Shared trust decisions

- authoritative hostile path/framing corpus:
  `Tests/BridgeContractFixtures/edge/bridge-product-source-path-corpus.json`,
  mirrored by `scripts/bridge-web-sync-fixtures.sh` into BridgeWeb;
- default Swift owner for lexical and symlink-resolved containment:
  `Sources/AgentStudio/Features/Bridge/Runtime/BridgeSourcePathContainment.swift`;
  if repo import rules reject that placement, the sole predefined fallback is
  `Sources/AgentStudio/Features/Bridge/Transport/BridgeSourcePathContainment.swift`;
  if both placements violate the dependency boundary, stop at S6a before any
  byte-read change;
- the missing selected preparation identity becomes a pure exported helper in
  `bridge-comm-worker-review-preparation.ts`, owned by Review worker preparation
  and tested there; and
- capability admission stays before body-stream reading.

## 6. Corrected 43-Path HEAD Recovery Disposition

The spec shorthand is resolved here to three `.ts` controllers rather than
`.tsx`. This table is the machine-reproducible corrected inventory. No directory
restore is allowed.

| HEAD path | Disposition |
| --- | --- |
| `BridgeWeb/src/app/bridge-app-review-controller.ts` | reject as package/main authority; mine behavior into pane-surface/render controller tests |
| `BridgeWeb/src/app/bridge-app-review-navigation-controller.ts` | recover/adapt local navigation and typed intent only |
| `BridgeWeb/src/app/bridge-app-review-selection-controller.ts` | recover/adapt immediate local selection and intent emission only |
| `BridgeWeb/src/app/bridge-app-review-viewer-shell-boundary.tsx` | recover/adapt as the restored presentation boundary |
| `BridgeWeb/src/review-viewer/projections/review-item-window-budget.ts` | reject the legacy projection-budget owner and leave it absent; S4a creates the worker-owned complete-item admission policy |
| `BridgeWeb/src/review-viewer/projections/review-item-window-budget.unit.test.ts` | do not restore; mine no-truncation, pressure and pacing cases into `bridge-worker-complete-item-admission-policy.unit.test.ts` |
| `BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.ts` | reject runtime coordinator; mine lifecycle/currentness cases into worker projection tests |
| `BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.unit.test.ts` | adapt scenarios to comm-worker pure-kernel/currentness proof |
| `BridgeWeb/src/review-viewer/state/review-viewer-store.ts` | reject canonical Zustand owner; mine UI-only state decomposition |
| `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts` | adapt to UI-local state plus worker ownership/static proof |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.ts` | preserve/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.unit.test.ts` | preserve/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser-dom.ts` | preserve/adapt with readable-source oracle |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx` | recover/adapt through pane worker/restored UI |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx` | recover/adapt through pane worker/restored UI |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser-test-support.ts` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.test-support.ts` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.virtualizer.test-support.ts` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-markdown-worker-test-client.ts` | reject HTML-shaped bypass; retain hostile/sanitization cases |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend-retouch-fixtures.ts` | preserve/adapt data only |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend-support.ts` | preserve/adapt common source support only |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.browser.test.ts` | recover/adapt through common Vite source/worker/UI |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts` | reject viewer/runtime bypass; replace with deterministic source provider |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer-render-slices.browser.test.tsx` | recover/adapt keyed display proof |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark-support.tsx` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx` | recover/adapt |
| `BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts` | preserve/adapt canonical nested fixtures |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-sync-client.ts` | reject separate runtime; mine pure-kernel behavior only |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-client.ts` | reject separate product owner |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-client.unit.test.ts` | adapt currentness/teardown cases to comm worker |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-entry.ts` | reject separate worker entry |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-entry.unit.test.ts` | adapt boundary/import cases |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-planner.ts` | reject runtime planner; mine deterministic algorithm if still useful |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-planner.unit.test.ts` | adapt to pure-kernel/comm scheduling proof |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-rpc.ts` | reject RPC authority |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-rpc.unit.test.ts` | adapt closed DTO/currentness cases to worker protocol |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-transport.ts` | reject transport authority |
| `BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-transport.unit.test.ts` | adapt lifecycle cases to pane worker |
| `BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.test-support.ts` | reject duplicate transport support; replace with core worker support |
| `BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.ts` | reject duplicate transport |
| `BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts` | adapt scenarios to core pane-worker transport |

## 7. Execution Tasks And Local Proof

Each behavior-changing task begins by making its named permanent witness fail
for the expected reason, then implements only its manifest, makes that witness
green, and runs the lower proof layers named in the card. If the manifest is
wrong at execution time, stop and update the plan before editing outside it.

### G0 — Safety, Manifests, And Honest RED

Tasks:

1. record `git status --short`, current HEAD, diff stats and the exact 43-path
   recovery inventory;
2. intersect the complete current dirty/untracked path set with every plan
   manifest and classify each in-scope pre-existing path as `red-scaffold`,
   `adapt-in-place:<slice>` or `delete:<slice>`; everything else remains
   user-owned and untouched;
3. record one task-level allowed-write manifest and one join owner for every
   subsequent sub-slice before dispatch;
4. prove the permanent witnesses fail for flat Review, selected-only CodeView,
   missing hierarchy/continuous traversal, duplicate Review publication, File
   prefix/deep-scroll, absent dedicated Vite product E2E, shallow correlation,
   shallow packaged journey, static hard cut, typecheck and build; and
5. preserve unrelated dirty paths; no broad restore/checkout/reset/clean.

Current in-scope untracked classifications are explicit rather than inferred:

- `bridge-app-review-direct-{viewer-shell,code-panel}.tsx` -> `delete:S9a`;
- `bridge-pane-runtime.ts` -> `adapt-in-place:S2b`;
- `BridgeHardCutStaticNegativeTests.swift` and
  `BridgeProductBootstrapHardCutContractTests.swift` -> `red-scaffold:G0`, then
  `adapt-in-place:S9a`;
- `bridge-worktree-dev-provider/{content,metadata,ports}.ts` ->
  `adapt-in-place:S6b`.

G0 installs or restores these exact permanent witnesses and records the exact
expected failure phrase and exit code before production edits:

| Failure class | Permanent witness | G0 command/filter |
| --- | --- | --- |
| flat Review, selected-only CodeView and missing hierarchy | `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx` | `pnpm -C BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser <path>` |
| continuous early/middle/final Review traversal and deep scroll | `bridge-viewer-browser.integration-{large,scroll}.browser.test.tsx` | same Browser command with both exact files |
| duplicate Review update/select publication | `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts` | `pnpm -C BridgeWeb exec vitest run <path> -t "coalesces update and select"` |
| complete File bytes beyond 2 MiB/10,000 lines | `BridgeWeb/src/core/comm-worker/bridge-file-complete-content.unit.test.ts` and `Tests/AgentStudioTests/Features/Bridge/BridgeFileCompleteContentTests.swift` | focused Vitest path plus `mise run test-fast -- --filter BridgeFileCompleteContentTests` |
| File tree/content disappearance after sustained deep scroll | `BridgeWeb/src/file-viewer/bridge-file-viewer-app.deep-scroll.browser.test.tsx` | focused Browser command for that exact file |
| deterministic source-to-readable-DOM/disposition correlation | existing focused Browser integration tests | current `integration-browser` project with deterministic File/Review fixtures |
| absent dedicated Vite product E2E and live-git oracle | future `BridgeWeb/tests/e2e/bridge-viewer-vite-product.e2e.test.tsx` | future `BridgeWeb/vitest.e2e.config.ts`; absence is the intentional RED until the post-Swift E2E slice |
| shallow packaged Swift journey | `Tests/AgentStudioTests/Features/Bridge/BridgeProductRealGitFileAndReviewWebKitTests.swift` | `mise run test-webkit -- --filter WebKitSerializedTests/BridgeProductRealGitFileAndReviewWebKitTests` |
| surviving legacy owners/carriers | TS `bridge-hard-cut-static-negative.source-structure.unit.test.ts` plus Swift `BridgeHardCutStaticNegativeTests.swift` and `BridgeProductBootstrapHardCutContractTests.swift` | focused Vitest paths plus `mise run test-fast -- --filter BridgeHardCutStaticNegativeTests` and `mise run test-fast -- --filter BridgeProductBootstrapHardCutContractTests` |
| TypeScript and packaged BridgeWeb failures | `BridgeWeb/package.json` scripts | `pnpm -C BridgeWeb run check` and `pnpm -C BridgeWeb run build` |

Write manifest: permanent tests and planning ledger only. Production edits are
forbidden at G0.

Gate: the parent inspects each RED failure, exact reason, command and exit code.

### S1a — Recover Pure Review Behavior And Proof, Not Authority

Write manifest:

- the 43 HEAD paths in Section 6, individually;
- `BridgeWeb/src/review-viewer/navigation/review-projection.ts` and its models/
  tests only when pure behavior must be reconciled; and
- a generated recovery-disposition test/manifest under Review test support.

Actions:

- use HEAD blob content as evidence and adapt with normal edits; never checkout
  or restore a directory;
- recover navigation, selection, shell-boundary and permanent browser/benchmark
  behavior into files that compile without old stores/workers/transports;
- keep rejected runtime files absent or convert only their scenarios into new
  owner tests; and
- leave the current flat shell as the only mounted shell.

RED: source-structure tests fail if recovered files import the old Review store,
projection worker/coordinator, duplicate shared RPC or mocked viewer runtime.

Green checkpoint: all 43 dispositions are represented in code/test evidence and
the recovered pure components/tests compile behind typed adapter interfaces.

### S2a — Freeze Closed Product/Worker Contracts And Identity

Primary write manifest:

- `BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-transport-contract.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-session-contracts.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-content-contracts.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-subscription-contracts.ts`
- their adjacent unit/type tests;
- `Tests/BridgeContractFixtures/{valid,invalid,edge}/bridge-product-*.json`
- mirrored `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/**`

Actions:

- align the product v2 and main/worker DTO vocabulary without one generic JSON
  escape hatch;
- prohibit root/store snapshots, main-minted worker epochs/sequences, and
  undeclared binary transfers;
- close pane/surface/worker/publication/disposition identities; and
- add static negative proof for forbidden bootstrap/update payloads.

RED: version/identity mismatch, extra fields, unknown variants, root snapshots
and undeclared buffers fail closed.

Green checkpoint: TypeScript contract/type tests and byte-identical Swift/TS
fixtures pass; Section 5 policies are expressible without a second owner.

Join owner: parent owns `bridge-worker-contracts.ts` and fixture-schema joins.

### S2b — One Real Pane Worker, Minimal Review And File Patches

Primary write manifest:

- `bridge-pane-runtime.ts` and unit tests;
- `bridge-pane-comm-worker-session.ts` and unit/topology tests;
- comm-worker `entry`, `store`, `runtime-protocol`, `command-handler` and tests;
- `bridge-worker-rpc-client.ts`, `bridge-worker-rpc-lifecycle-store.ts` and tests;
- `bridge-main-render-snapshot-store.ts` plus keyed tests;
- `BridgeWeb/src/app/bridge-app-dev-product-session-host.ts`;
- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`;
- Vite `bridge-product-dev-{carrier,session,metadata-writer}.ts` and tests.

Actions:

- make Review and File surface clients of one pane-owned session;
- pass one minimal bounded patch for each surface through one real worker;
- keep UI lifecycle/display copies non-authoritative; and
- prevent feature worker factories and main-seeded product packages.

RED: real-worker test detects a second worker across mode switches, full store
snapshot traffic or a main product fetch.

Green checkpoint: one worker id survives Review/File mounts and switches, both
surface patches paint, and teardown has no worker/port residue.

Join owner: parent owns pane runtime, snapshot store, app bootstrap and Vite
carrier/session joins.

### S1b / J1 — Mount Exactly One Recovered Review Shell

Primary write manifest:

- `bridge-app-review-viewer-shell-boundary.tsx`
- `bridge-app-review-navigation-controller.ts`
- `bridge-app-review-selection-controller.ts`
- `bridge-app-review-render-snapshot-controller.ts`
- `bridge-app-review-viewer-mode.tsx`
- `review-viewer/{shell,trees,navigation,chrome}/**`
- focused source-structure, component and Browser tests.

Actions:

- wire recovered presentation to `BridgePaneSurfaceClient` and keyed display
  selectors;
- keep local selection/disclosure/search/focus synchronous, sending typed intents
  after local paint;
- mount fresh and replacement Review sources fully expanded, preserve manual
  collapse across same-source appends, and prove stale reveal is not replayed
  independently of disclosure state;
- make the temporary composition target a closed build-time/props choice with no
  automatic fallback or runtime retargeting; and
- mount only the recovered target at J1 while keeping the flat source compiled
  but unmounted until S9a.

RED: test proves current flat output and rejects two simultaneous emitters.

J1 Green: one recovered shell/emitter and one worker paint minimal Review and
File data; no obsolete Review authority is imported or running.

### S6a — Canonical Source Contract, Hostile Corpus, Deterministic Vite

Primary write manifest:

- `Tests/BridgeContractFixtures/edge/bridge-product-source-path-corpus.json`
- mirrored BridgeWeb fixture and fixture sync tests;
- `BridgeWeb/scripts/dev-server/bridge-product-dev-{call-handler,content-producer,
  session,subscription-handler,review-adapter,file-adapter}.ts` and tests;
- deterministic source support in `review-viewer/test-support/**` and
  `file-viewer/bridge-file-viewer-browser-test-*.ts*`;
- existing deterministic File/Review Browser fixtures and tests under the
  ordinary `integration-browser` project; and
- parent-owned `BridgeWeb/vitest.browser.config.ts` plus package scripts for
  the ordinary unit/integration/component Browser layer only.

Actions:

- freeze canonical file/directory/path/rename/content/digest facts shared by all
  backends;
- replace mocked viewer bypass with a deterministic Vite source behind the same
  product session; and
- make the deterministic Browser cell use the production pane worker and UI.

RED: deterministic source that emits flat projected rows or prefix fulfillment
fails the common source contract.

Green checkpoint: strict corpus and deterministic Vite source pass lower tests;
the Browser cell exists and cannot mount a test-only viewer.

Join owner: parent owns the corpus, source DTO and Browser entry.

### S3 — Worker-Derived Hierarchical Review

Primary write manifest:

- `bridge-comm-worker-review-{metadata-applicator,metadata-projection,
  display-projection,runtime-source-mapper,runtime}.ts` and tests;
- `bridge-worker-review-display-patch-contracts.ts` and tests;
- pure `review-viewer/navigation/review-projection*.ts` and tests;
- Review keyed selectors/patch application in the main snapshot store;
- restored `review-viewer/{trees,navigation,chrome}/**` and Browser tests.

Actions:

- derive directory hierarchy and stable item order from canonical source facts;
- move accepted projection/currentness to the comm worker;
- implement normal/guided/plans modes, search and composed status/class/path/
  language facets; and
- keep tree disclosure, pending selection and draft query local while worker
  accepts/supersedes intent revisions.
- reset fresh/replacement trees to fully expanded, while same-source streamed
  metadata preserves manual collapse and opens new directory rows.

RED: the 3,420-file nested fixture fails against depth-zero rows, stale
projection overwrite and duplicate update/select publication.

Green checkpoint: hierarchical Trees, reveal, collapse, search/facets/modes and
selection pass with O(selected + visible delta) touched-key/subscriber proof.

### S4a — Complete Review Publication, Fulfillment And Residency

Primary write manifest:

- `bridge-comm-worker-review-preparation.ts` and tests;
- `bridge-worker-review-{content-fetch,content-ready,pierre-job-planner}.ts` and
  tests;
- `bridge-worker-content-preparation-pump.ts` and tests;
- `bridge-worker-complete-item-admission-policy.ts` and tests;
- `bridge-worker-{pierre-render-job,pierre-courier,render-fulfillment}.ts` and
  tests;
- Review publication/disposition contracts and focused snapshot-controller
  tests.

Actions:

- implement `selectedReviewPreparationIdentity` in Review preparation;
- stream all required roles, strictly decode/hash, assemble one complete
  supported item and mint semantic/cache/publication identity;
- apply Section 5 admission/eviction/reset policy;
- coalesce duplicate semantic preparation/publication;
- accept fulfillment only from matching painted residency or terminal
  availability; and
- bound selected/visible preparation and main publication queues.

RED: same update/select produces duplicate jobs; ready/delivered without painted
receipt falsely fulfills demand; stale/rejected receipt cannot re-demand.

Green checkpoint: hostile worker tests cover currentness, retry, coalescence,
eviction, reset and one disposition chain per attempt.

Join owner: parent owns publication/disposition DTO and worker store/runtime
joins.

### S4b — Continuous Review UX And Pierre Reconciliation

Primary write manifest:

- `bridge-app-review-render-snapshot-controller.ts` and Browser/unit tests;
- `review-viewer/shell/review-viewer-shell.tsx`;
- `review-viewer/code-view/{bridge-code-view-controller,
  bridge-code-view-materialization,bridge-code-view-metadata-apply,
  bridge-code-view-panel,bridge-code-view-programmatic-reveal-gate,
  bridge-code-view-worker-prepared-items,use-bridge-code-view-collapse-controller,
  use-bridge-code-view-selection-scroll}.ts*` plus adjacent tests;
- Review markdown component/worker and hostile tests;
- recovered large/scroll/virtualizer/browser benchmark suites.

Actions:

- seed one ordered continuous CodeView and reconcile only through public Pierre
  APIs under Section 5.3;
- validate steady-state live membership with changed-item neighborhoods and
  stable first/final sentinels, keeping public Pierre reads O(selected + visible
  delta); use one exact authoritative replacement for policy adoption or a
  detected mismatch;
- preserve independent tree/CodeView scrolling, selected reveal, file/hunk
  collapse, supported hunk expansion and sanitized markdown;
- keep prior readable content until replacement paints; and
- prove early/middle/final real content and stable anchors under late hydration.

RED: current selected-only shell, fabricated placeholder readability, app-side
viewport writes and hydration retargeting fail permanent Browser tests.

Green checkpoint: deterministic 3,420-file/100,000-line journey reaches final
real content with zero blank/wrong/disappearing/stale items and stable anchors.

### S5 — Complete File Assembly And Deep-Scroll Product Proof

Primary write manifest:

- product content frame/stream codecs and tests;
- `bridge-comm-worker-file-view-{preparation,runtime,runtime-source,
  source-update}.ts` and tests;
- `bridge-worker-file-view-{content-fetch,content-ready}.ts` and tests;
- File metadata/query/display projection and patch contracts/tests;
- `file-viewer/{bridge-file-viewer-app,code-panel,code-view-items,
  render-snapshot-controller,shell,tree-panel}.ts*` and tests;
- deterministic File Browser fixtures/harness and permanent deep-scroll test.

Actions:

- delete prefix/padding/preview-as-complete behavior from the ready path;
- stream, strictly decode and assemble the complete selected text file off-main;
- preserve exact empty/newline/CRLF/multibyte semantics and typed binary/
  unsupported/unavailable/failure states; and
- keep tree/content painted through sustained final-content scrolling.

RED: >2 MiB/>10,000-line and fragmented corpus fails final checksum; permanent
Browser test reproduces disappearance.

Green checkpoint: deterministic source -> worker -> complete item -> Pierre ->
readable final DOM checksum, with both scroll surfaces continuously painted.

Real-worktree and Swift provider work is excluded here and belongs to S6b/S6c.

### J2 — Deterministic Browser Lower Proof

Run lower proof for S1-S6a through the existing focused Browser integration
tests. They must prove hierarchy, search/facets/reveal/collapse, continuous
Review early/middle/final source, complete File final source, worker identity,
readable DOM, dispositions and no test-only viewer. This is fast deterministic
product proof, not a second Vite E2E system.

### S6b — Dedicated Vite Product E2E After Packaged Swift

Execution order: S6b is intentionally deferred until S6c, S7 and J4 have
proven the Swift provider and packaged WKWebView path. Its numbering preserves
the source-contract ownership map; it is not permission to block Swift on test
framework construction.

Primary write manifest:

- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider/{config,ports,
  files,metadata,content,provider}.ts` and tests;
- `bridge-worktree-dev-provider.ts` and provider integration/stability tests;
- Vite product session/carrier/http/adapter modules only where the frozen source
  contract requires them;
- `BridgeWeb/vitest.e2e.config.ts`; and
- `BridgeWeb/tests/e2e/bridge-viewer-vite-product.e2e.test.tsx` plus the smallest
  fixture/helper files justified by the completed packaged journey.

Actions:

- own exactly one Vite E2E system with deterministic and disposable
  live-worktree scenarios; do not create parallel source-cell, reporter, Node
  verifier, or named-project frameworks;
- start the normal Vite product backend and mount the real product UI;
- preserve lexical plus `realpath` containment immediately before every byte
  read;
- emit canonical facts, never projected flat rows;
- mutate a per-run disposable git repository canary and correlate selected item ->
  descriptor -> role -> request -> live bytes -> semantic item -> readable DOM
  -> painted disposition; and
- reject stale route/source reuse;
- observe the actual worker/main painted-disposition receipt rather than writing
  a literal `painted` result in the harness; and
- absorb only useful assertions from the Node development verifier, then retire
  it as an E2E authority so Vite has one permanent E2E owner.

RED: `BridgeWeb/vitest.e2e.config.ts` and the dedicated product E2E are absent;
the diagnostic Node verifier can pass without painted source correctness.

Green checkpoint: one dedicated Vite E2E configuration passes deterministic and
disposable live-worktree File/Review scenarios with an independent live-git
oracle. The Node verifier may support migration but cannot remain a second E2E
authority.

### S6c — Swift Provider, Containment And Packaged Source Correlation

Primary write manifest:

- `Sources/AgentStudio/Features/Bridge/Runtime/BridgeSourcePathContainment.swift`;
- Swift `Models/Transport/BridgeProduct*` contracts/codecs;
- `Transport/BridgeProduct{SchemeRequestAdmission,BoundedRequestBodyReader,
  SchemeAdapter,SchemeFramePump,Session,Session+ProtocolLifecycle,
  Session+Resync}.swift`;
- `BridgePaneProduct{File,Review}{Metadata,Content}Source.swift`;
- `Runtime/WorktreeFileSurface/{BridgeWorktreeFileSourceProvider,
  BridgeWorktreeFileMaterializer}.swift`;
- `Runtime/ReviewFoundation/AgentStudioGitBridgeReviewDataClient*.swift` and
  `BridgeGitReviewSourceProvider.swift`;
- shared corpus/codec/provider tests; and
- `BridgeProductRealGitFileAndReviewWebKitTests.swift` plus packaged support.

Actions:

- preserve capability-before-body and bounded strict framing;
- enforce lexical and resolved containment before every File/Review byte read,
  including fallback paths;
- use `agentstudio-git` for production facts/content;
- reject production CLI `git`/Worktrunk ownership; TypeScript CLI `git` remains
  limited to explicitly scoped Vite development and test-fixture utilities; and
- strengthen packaged proof from readiness/counts to source checksum/readable
  DOM/disposition correlation.

RED: hostile symlink/path corpus reaches inconsistent Swift read guards and the
packaged journey passes on shallow counts.

Green checkpoint: headless Swift corpus/provider tests pass and the packaged
journey is capable of the same correlation oracle; full lifecycle is J4.

Join owner: parent owns shared corpus, product DTO/version and packaged harness.

### J3 — Provider Parity Join

The post-J4 dedicated Vite E2E scenarios are green, Swift headless/provider and
packaged tests consume the same corpus/contract, and source facts are
semantically identical. A provider-owned tree/projection, main fetch,
test-only viewer or second Vite E2E authority fails the join.

### S7 — Reset, Reconnect, Cancellation And Pane Isolation

Primary write manifest:

- TS pane runtime/session, comm-worker protocol/health/store/reconciler/
  fulfillment and lifecycle tests;
- Swift `BridgeProductSession*`, producer registry/revocation barrier,
  metadata coordinator, pane session owner/controller bootstrap/lifecycle;
- real-worker Browser lifecycle tests; and
- packaged two-pane/reset test support.

Actions:

- distinguish surface epoch reset from worker replacement;
- cancel old streams/preparation/publications and ignore late traffic;
- replay current UI facts without crossing product rows/content;
- coalesce duplicate semantic publication after restart;
- prove Review/File mode changes retain one pane worker; and
- prove two panes have distinct workers/sessions/capabilities and zero cross-
  pane leakage.

RED: delayed old-instance mutation, duplicate chain, leaked producer/observation
gate or pane identity reuse fails permanently.

Green checkpoint: hostile TS/Swift lifecycle tests and real-worker Browser reset
matrix pass with zero residue before packaged J4.

### S8a — Telemetry Integrity, Independent Of Performance Results

Primary write manifest:

- `BridgeWeb/src/core/telemetry-worker/**` and tests;
- main/comm compact-sample adapters and tests;
- Swift `Models/Telemetry/**`, `Runtime/Telemetry/**`,
  `BridgePaneController+TelemetrySidecar.swift` and tests;
- telemetry endpoint/admission tests; and
- typed snapshot/drain semantic IPC adapters.

Actions:

- create no worker/ports/network when telemetry is off;
- bind producer identity and credits, scrub before retention, account exact
  required/optional loss, batch/retry/outbox only in telemetry worker, and
  drain/close with terminal acknowledgements;
- keep product behavior identical when telemetry fails; and
- mark any required loss/gap/restart/drain failure proof-ineligible.

RED: telemetry-off traffic, producer buffering after ready, required loss that
remains eligible, or telemetry failure changing product behavior.

Green checkpoint: hostile telemetry unit/integration proves off/on/failure and
drain semantics without claiming product performance.

### J4 — `WK-packaged-current-worktree`

Build current assets and run the serialized packaged WKWebView journey with
current bundle/PID/marker/temp-repo identity. Prove:

- hierarchical Review and continuous early/middle/final readable content;
- complete File final readable content and sustained deep scroll;
- source-to-DOM/disposition correlation through Swift `agentstudio-git`;
- capability and direct worker streams, cancellation/resync and no main relay;
- reset/restart/mode switch/two-pane isolation and zero residue; and
- telemetry off/on/failure product parity.

Browser or headless Swift evidence cannot substitute for this gate.

### S8b — Immutable-Candidate Correctness And Performance Matrix

Primary write manifest:

- Review/File benchmark workloads and Browser runners;
- `bridge-viewer-browser-benchmark-runner.ts` and manifest/report support;
- policy constants only after baseline evidence;
- Swift performance workload/telemetry proof support;
- packaged current-worktree benchmark runner; and
- Victoria query/validator artifacts.

Actions:

- freeze candidate commit/diff, source/cache state, fixture, viewport, machine,
  Pierre version, worker mode and telemetry mode;
- run every required family/state in `controlled_dev_chromium` and
  `packaged_wkwebview`, telemetry off and on;
- use three fresh launches, one excluded warmup and at least 100 attempted
  actions per launch;
- report nearest-rank per-launch and pooled p95/p99, maximum launch percentile,
  publication bytes, clone/apply work, duplicate lifetime, retained heap,
  cancellation reclamation, event-loop gaps, owned slices and correctness;
- prove early/middle/final traversal and anchors under hydration; and
- only after the baseline, set numeric residency/pacing values if all gates
  still pass with headroom.

RED: missing measurement is RED; any wrong/blank/disappearing/stale item,
required telemetry gap/loss, >=50 ms main task, >8 ms owned slice, anchor error
or threshold miss fails the cell.

J5 Green: every individual launch and pooled cohort passes. Any whole-item
correctness/heap/event-loop/anchor/p99 failure stops for user reconvergence; no
cap, sparse fiction, proof weakening or Pierre change.

### S9a — Atomic Compile-Enforced Hard Cut And Local Final Re-Proof

Primary delete/edit manifest:

- delete `bridge-app-review-direct-viewer-shell.tsx` and
  `bridge-app-review-direct-code-panel.tsx`;
- keep the rejected HEAD store/projection-worker/shared-RPC runtime files absent;
- remove File main Zustand/prefix/padding owners and feature body/cache/retry
  paths named by static scans;
- delete product script-message, page/native `callJavaScript`/DOM relay,
  feature resource GET and duplicate telemetry owners named by the spec;
- remove deleted projection-worker references from app asset build/manifest;
- update only required app/bootstrap/IPC/build registration sites; and
- strengthen TS source-structure, Swift hard-cut static negatives, dependency
  audit and built-asset carrier scans.

Actions:

- perform deletion only after J5;
- keep bootstrap/assets/typed native-to-FE controls and bounded diagnostic reads
  that the spec explicitly permits;
- prove exactly one recovered Review shell, one pane worker and one telemetry
  sidecar at most; and
- rebuild packaged assets before any final proof claim.

RED: every named surviving flat import, extra worker, legacy carrier, main
Zustand product owner, prefix contract or Pierre diff fails a static gate.

J6 Green: repeat static, type/lint/unit/integration, focused deterministic
Browser, dedicated Vite E2E, packaged WKWebView, telemetry and required
performance cells on the post-deletion candidate. Pre-deletion proof is
insufficient.

### S9b — Implementation Review, Remediation, CI And PR Readiness

Actions:

- run `shravan-dev-workflow:implementation-review-swarm` on the final diff with
  bounded ownership, security, UX, proof and deletion lanes;
- parent-verify every finding and implement only accepted in-scope remediation;
- repeat affected lower proof and all terminal gates;
- reconcile authoritative docs/handoff and retire broken historical plans;
- intentionally stage/commit only scoped verified files;
- create/update the PR, run/watch CI, inspect checks/comments/unresolved review
  threads/mergeability at final head SHA; and
- report PR ready but leave it unmerged.

External CI/PR state is not a local implementation gate. Any accepted code
finding returns to its owning slice and reopens its proof.

## 8. Execution DAG And Join Ownership

```text
G0 -> S1a -> S2a -> S2b -> S1b/J1 -> S6a
                                      |
                                      +-- S3 -> S4a -> S4b --+
                                      +-- S5 -----------------+-> J2 deterministic lower proof
                                      +-- S8a ----------------+       |
                                                                    +-- S6c -> Swift headless
                                                                    +-- S7 TS/Swift lifecycle
                                                                                 |
                                                                                 +-> J4 packaged Swift
                                                                                           |
                                                                                           +-> S6b dedicated Vite E2E -> J3 parity
                                                                                                                     |
                                                                                           S8b correctness/perf -> J5
                                                                                                                     |
                                                                                           S9a deletion/re-proof -> J6
                                                                                                                     |
                                                                                           S9b review/CI/PR -> PR ready, unmerged
```

S8a intentionally starts after S6a: telemetry semantics are product-disjoint,
but its compact adapters and Browser/package configuration wait for the shared
pane/source identity and hostile source contract to freeze, avoiding concurrent
joins in `bridge-worker-contracts.ts`, package config and verifier support.

Safe parallel work exists only inside the fan-outs above and only after the
shared DTO/fixture/lifecycle contract is frozen. Parent or one designated join
owner has sole write authority over these files/surfaces during a fan-out:

| Shared integration surface | Join owner | Join gate |
| --- | --- | --- |
| `bridge-worker-contracts.ts` and worker wire version | parent | S2a, S4a |
| `bridge-pane-runtime.ts` and pane session | parent | S2b, S7 |
| `bridge-main-render-snapshot-store.ts` | parent | J1, S3/S4/S5 joins |
| `bridge-comm-worker-runtime-protocol.ts` and worker store | parent | S2b, S4a, S7 |
| `bridge-app-review-viewer-mode.tsx` and render controller | parent | J1, S4b, S9a |
| TS/Swift shared fixtures and product DTO version | parent | S6a/J3 |
| package/Vite/Vitest/build configuration | parent | J2, S9a/J6 |
| app bootstrap, packaged assets and semantic IPC registration | parent | J4, S9a/J6 |
| final Browser/native/performance verifiers | parent | J2-J6 |

Subagents receive exact file lists, not directory ownership. A lane completion
is candidate evidence; the parent inspects its diff, reruns the local proof and
performs the join.

## 9. Requirements / Proof Matrix

| Requirement or claim | Source | Owner | Proof modality and layer | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| one pane comm worker; no main protocol/cache/demand owner | R42, R49, R54-R56 | S2a/S2b | type/static unit, hostile integration, real-worker Browser | parent-run contract/topology tests and creation scan | worker/pane id, current DTO version | required |
| all 43 recovery paths handled without obsolete authority | migration recovery set | S1a/S1b | manifest/static/unit/component/Browser | parent diff audit plus recovered tests | HEAD `38fe66a`, execution-start status | required |
| still-present `review-viewer/trees/` is preserved and used rather than replaced | product recovery contract | S1a/S1b/S3 | source-structure, component Browser, final product cells | parent diff audit plus hierarchical tree interaction proof | current tree component identity and final diff | required |
| exactly one recovered Review shell/emitter, no fallback | migration single-shell contract | S1b/S9a | lifecycle unit, component Browser, import scan | parent-run composition proof | pane, HMR/source/restart identity | required |
| hierarchical Review, modes, search/facets, reveal/collapse/selection | product contract, R41-R46, R61 | S3 | projection unit, worker integration, focused deterministic Browser tests | 3,420-file nested fixture and keyed invalidation counters | fixture checksum, source generation, projection/UI revision | required |
| fresh/reset File and Review trees are fully expanded; same-source appends preserve manual collapse | product contract, R41-R46 | J1/S3/S5 | controller unit plus production Browser source-reset and streamed-append witnesses | live Pierre `aria-expanded` rows before/after reset, collapse and append | source identity, generation, tree model identity | required |
| FE selection and viewport invalidation is O(selected + visible delta) | R45 | S3/S4b | keyed-store unit, subscriber/touched-key integration, large Browser fixture | subscriber and invalidated-key counters | fixture checksum, source generation, display revision | required |
| ready-to-visible work uses one AppPolicies-mirrored frame pump with fairness | R46 | S4b | policy unit, frame/yield integration, Browser liveness and long-task proof | symbolic policy references, applied-unit/deferred-progress counters | policy version, viewport, run marker | required |
| continuous multi-file Review with complete items, hunk/markdown/anchors | R44, R52, R57, R60-R63 | S4a/S4b | state unit, hostile worker, Browser large/scroll/virtualizer/markdown | readable early/middle/final DOM and disposition oracle | semantic/render/publication/attempt ids, Pierre version | required |
| retained same-identity Pierre membership reconciles to the complete authoritative order without O(package) steady-state scans | Review contract, R44/R45/R52/R57 | S4b | 3,420-item bounded-lookup metadata unit plus production Browser retained-instance witness | <=12 public item/geometry reads for one healthy delta; actual live Pierre header ids in authoritative order, not React input counts | source/manifest identity, mounted CodeView policy epoch, Pierre version | required |
| markdown is sanitized immediately before HTML insertion and hostile script/network/interactive content is denied | R59 security | S4b | sanitizer unit, hostile markdown integration, Browser insertion proof | hostile corpus plus inspected readable DOM | corpus digest, sanitizer version, run marker | required |
| complete File text; typed terminals; no cap/padding; deep scroll stable | File contract, R44, R47, R57, R61, R65 | S5 | decode/unit, stream integration, deterministic Browser deep-scroll | independent complete source checksum and final readable DOM | selected path/file, source generation, semantic id | required |
| deterministic and disposable live-worktree Vite scenarios share one source contract and one dedicated E2E configuration | backend parity, R48-R50/R62 | S6a/S6b | provider integration plus post-J4 Vite product E2E | `BridgeWeb/vitest.e2e.config.ts` and one product E2E suite | per-run fixture/live-git canary, process/source id | required |
| all product/main-worker schemas are closed and TS/Swift reject the same hostile variants | R50 | S2a/S6c | contract unit/type, byte-identical hostile corpus in both runtimes | parser rejection matrix for unknown/extra/missing/version/bounds/stale cases | corpus digest and current wire version | required |
| transferred buffers and the cloned complete-Pierre-item class have distinct declared ownership modes | R53 | S2a/S4a | contract unit, transfer-list Browser, packaged/benchmark ownership evidence | declared field paths, detachment, clone/transfer duration and duplicate lifetime | wire version, message class, Pierre version | required |
| worker hot actions stay O(delta), <=8 ms per slice and distinct from R60 preparation slices | R58 | S3/S4a/S8a | normalized-store unit, touched-key integration, handler histograms/long-task counters | per-action touched keys, queue wait and handler duration | worker instance, policy version, command class | required |
| Swift `agentstudio-git` is the exclusive production git backend; capable direct worker streams and packaged paint | R48-R50, R59, R64-R65 | S6c/J4 | Swift unit/integration, production subprocess static negative, packaged WKWebView E2E | source bytes -> readable DOM/disposition trace plus zero production CLI-git/Worktrunk owners | bundle/PID/marker/temp repo/source generation | required |
| lexical and symlink-resolved containment before every read; capability before body | R59/R64 security | S6a-S6c | byte-identical hostile TS/Swift corpus and zero-read admission test | parent-run provider/scheme tests | corpus digest and current source paths | required |
| reset/reconnect/restart/HMR/mode and two-pane isolation reach zero residue | R42, R49, R63-R65 | S7 | state unit, hostile integration, Browser, packaged two-pane | barrier/publication/residue trace | worker instance, stream/subscription, pane and bundle id | required |
| telemetry off/on/failure is disjoint, exact and product-fail-open | R43, R62, R66 | S8a/J4 | telemetry unit/hostile, Browser/packaged parity, Victoria | exact credits/loss/gap/drain/proof eligibility | telemetry session/producer/batch, run marker | required |
| whole-item correctness, heap, event loop, anchors and p95/p99 pass | performance contract, R41/R44-R48/R52/R57-R62 | S8b/J5 | benchmark/metrics/traces in Browser and packaged | immutable cell manifest, raw samples and readable DOM | candidate SHA/diff, machine, fixture, Pierre, telemetry mode | required |
| no Pierre modification or private/sparse API | non-goals, R52/R57 | every slice/S9a | dependency/source audit plus public-API application | lockfile/package diff and source-structure test | final diff and bundled `@pierre/diffs@1.2.10` | required |
| legacy owners/carriers compile-dead in source and assets | R51, migration deletion sets | S9a/J6 | TS/Swift static negatives, build/audit, packaged trace | final source and built resource scan | post-deletion assets and candidate SHA | required |
| type/lint/test/build/full pyramid and PR readiness | goal terminal, R48/R62 | S9b | quality, CI, review and PR gates | exit codes/counts, review ledger, checks/threads/mergeability | final PR head SHA | current failures are RED; final green required |

No row is waived. A row whose proof cannot pass inside its owner is split before
implementation; it is not deferred to a generic final test phase.

## 10. Validation Gate Order And Commands

Commands are revalidated against the live repo before execution. Focused tests
use exact file/filter targets recorded in the task receipt; final gates use the
repo-owned commands below.

### Per-slice lower proof

- TypeScript unit/integration:
  `pnpm -C BridgeWeb exec vitest run <owned-test-files>`
- TypeScript focused Browser:
  `pnpm -C BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser <owned-browser-files>`
- Swift focused:
  `swift test --filter <owned-suite-or-test>` or the narrower repo-owned mise
  task when available.
- Shared fixture parity:
  `bash scripts/bridge-web-sync-fixtures.sh --check`

### Deterministic Browser and post-Swift Vite E2E gates

- focused deterministic proof stays under the ordinary
  `vitest.browser.config.ts` `integration-browser` project;
- after S6c/S7/J4, `pnpm -C BridgeWeb exec vitest --config vitest.e2e.config.ts run`
  runs the single dedicated Vite product E2E system;
- that E2E owns deterministic and disposable live-worktree scenarios, binds
  evidence to per-run fixture/live-git canaries and source/worker/process
  identity, and observes the actual painted disposition; and
- the Node development verifier remains diagnostic until useful assertions are
  absorbed, then ceases to be an E2E authority;
- dedicated E2E evidence carries exact test entry, scenario kind/checksum or
  live-git canary, source generation, process/provider identity, pane/worker
  instance, bundled Pierre version, readable-DOM oracle and dispositions;
- J2/J3/J6/S9b reject diagnostic artifacts substituted for focused Browser,
  dedicated Vite E2E, or packaged evidence;
- `pnpm -C BridgeWeb run test:dev-server` and
  `pnpm -C BridgeWeb run test:dev-server:worktree` are support evidence only.

### Packaged and native gates

- `pnpm -C BridgeWeb run build`
- `pnpm -C BridgeWeb run audit:assets`
- `mise run test-fast`
- `mise run test-large`
- `mise run test-webkit`
- `mise run test-e2e`

`WK-packaged-current-worktree` must be reported separately. Headless Swift,
Browser Mode, Node/Playwright or screenshots cannot replace it.

### Performance and observability gates

- `mise run observability:up`
- `mise run observability:status`
- `mise run observability:smoke`
- `pnpm -C BridgeWeb run benchmark:viewer`
- `pnpm -C BridgeWeb run test:benchmark:browser`
- the packaged current-worktree workload/validator introduced by S8b.

The shared observability stack is only started/used, never re-owned by this repo.
Every benchmark reports raw sample counts, launch counts, warmup treatment,
per-launch and pooled percentiles, maximum launch percentile and failure counts.

### Final quality and PR gates

- `pnpm -C BridgeWeb run check`
- `pnpm -C BridgeWeb run test`
- `mise run lint`
- `mise run test`
- repeat focused deterministic Browser proof, the dedicated Vite E2E,
  `WK-packaged-current-worktree`, S8b and all affected lower proof after
  implementation-review remediation;
- run CI and inspect PR checks, comments, unresolved threads and mergeability at
  the exact final head SHA.

Every receipt reports command, pass/fail counts, exit code and any unrun layer
with its blocker. A required unrun layer keeps the goal open.

## 11. Security And Reliability Rules

- parse all worker/native/network input as `unknown` only at the immediate
  parser boundary, then convert to a closed strict union;
- authorize capability and route before reading the request body;
- bound every body, frame, sequence, queue, retry, outbox and diagnostic result;
- perform lexical and symlink-resolved containment immediately before each
  filesystem byte read, including fallback paths;
- never export raw paths, content, prompts, errors or secrets through telemetry;
- sanitize markdown immediately before HTML insertion and test script/network/
  protocol hostile content;
- cancellation/reset must retire native producers and worker work to zero
  residue; late work cannot mutate current state;
- telemetry failure is product-fail-open and proof-fail;
- no proof gate may depend on telemetry as a control acknowledgement; and
- no build or verifier may fetch, modify or patch Pierre.

## 12. Recovery, Rollback And Dirty-Tree Safety

- Before each slice, re-read current status and the exact owned files.
- Apply individual HEAD blobs only as reviewed patches; no directory checkout or
  restore.
- Do not stage, commit, revert or delete unrelated paths.
- In-scope untracked files are governed by the G0 classification and their named
  later slice; they are never silently treated as disposable or as unrelated
  preservation blockers.
- Keep the flat shell as sole mount through S1a/S2 and as unmounted compiled
  fallback-free source through J5. If recovered integration fails before J5,
  revert only the current slice's owned edits and keep the previous single mount.
- Commit verified scoped checkpoints when repo policy permits: accepted plan,
  J1, J2, J4, J6, review remediation and PR-ready state. J3 and J5 are evidence
  joins rather than mandatory commit boundaries; checkpoint them only if scoped
  source changed after the preceding commit.
- Build/generated assets are refreshed only at named gates, then audited from
  the current source candidate.
- If a proof failure is outside Bridge scope, stop code edits, report scoped
  pass/fail evidence and ask before changing infrastructure.

## 13. Stop, Split And Reconvergence Triggers

Stop and return to the user before more code when:

- recovered behavior needs an obsolete owner, runtime fallback, dual shell,
  test-only viewer or main/native product relay;
- a task cannot make its permanent RED witness fail for the expected reason;
- shared DTOs or byte-identical TS/Swift fixtures cannot express the accepted
  contract without expanding outside Bridge;
- containment happens after byte access or capability admission needs body data;
- direct worker custom-scheme streaming cannot pass packaged WebKit;
- reset/restart cannot reach zero residue, duplicate publication survives or
  pane identity leaks;
- telemetry changes product behavior or required telemetry is lossy;
- whole-item correctness, memory, clone/apply, event-loop, anchor or p99 gates
  fail; or
- a required proof layer cannot run without unrelated infrastructure edits.

Whole-item failure is a product/dependency reconvergence point. It does not
authorize a File cap, sparse-window fiction, proof weakening or Pierre change.

## 14. Plan Review, Acceptance And Historical-Plan Retirement

This plan receives exactly:

1. one ACPX Claude Opus xhigh read-only Delegate review against the complete
   plan, accepted spec and current repo evidence; and
2. one parent-verified remediation pass.

No second external review loop is allowed. Every finding is accepted, rejected
or deferred with evidence. Use a strict allowed-tool list that excludes terminal
and mutation tools. After remediation and plan acceptance:

- delete the two broken historical plan workflow directories/files requested by
  the user:
  `tmp/plan-workflows/2026-07-12-bridge-viewer-contract-recovery/` and
  `tmp/plan-workflows/2026-07-13-bridge-viewer-hard-cut-loop/`;
- record the official orchestrator transition to
  `shravan-dev-workflow:implementation-execute-plan`; and
- begin at G0/S1a. Do not skip directly to transport cleanup or flat-shell
  deletion.

## 15. Plan Completion Receipt

Plan creation is complete when this file:

- contains the corrected recovery inventory, policy freeze, executable
  sub-slices, explicit manifests, DAG, join owners and proof matrix;
- passes scoped format/diff checks;
- completes the one capped external review and one remediation; and
- is accepted as the sole implementation plan.

Plan acceptance is not implementation completion. The goal remains open through
implementation, implementation review, CI and PR readiness.
