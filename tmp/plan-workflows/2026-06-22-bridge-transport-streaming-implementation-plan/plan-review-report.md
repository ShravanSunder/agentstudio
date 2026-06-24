# Bridge Transport Streaming Plan Review

Date: 2026-06-22
Verdict: needs revision before implementation

Historical status:

This is the prior plan-review report for the superseded slice graph. Its
findings were folded into the revised plan package. Do not use this file as the
current implementation verdict; use the latest 1.6.29 plan-review report once
the revised package review is complete.

## Reviewed Package

- `implementation-plan.md` lines 1-124
- `plan-ledger.md` lines 1-98
- `slices/00-carrier-proof.md` lines 1-89
- `slices/01-transport-contracts.md` lines 1-82
- `slices/02-browser-demand-runtime.md` lines 1-98
- `slices/03-review-protocol-vertical.md` lines 1-133
- `slices/04-worktree-file-surface.md` lines 1-104
- `slices/05-hard-cutover-cleanup.md` lines 1-91

Spec anchors checked:

- `spec.md` lines 900-1020 plus referenced contract/proof sections
- `review-protocol.md` lines 235-365 and 420-458
- `worktree-file-surface-protocol.md` lines 20-90, 300-330, and 450-485
- `spec-review-report.md` lines 60-115

Subagent lanes completed:

- spec-compliance: needs revision
- testability-validation: needs revision
- adversarial-design: needs revision
- architecture-assumptions: needs revision
- security-reliability: needs revision
- execution-scope: needs revision

Earlier architecture/security lane attempts hit OS `too many open files` before
reading and were discarded. The completed reruns above are the lanes used.

## Accepted Blockers

### B1. Slice 00 can select an intake carrier without proving real WKWebView behavior

Evidence:

- `slices/00-carrier-proof.md:44-76` names TS unit proof and broad Swift proof,
  but no real WKWebView burst/cancel/reset/backpressure gate.
- `spec.md:1008-1013` requires cancellation, chunk ordering, bounded memory,
  backpressure, error propagation, stale close behavior, WKWebView support, and
  parser fixture parity before accepting a carrier implementation.
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+PushTransport.swift:47-50`
  already notes WebKit drops page events under overlapping pushes.

Failure scenario:

The team accepts the existing push/event path as the intake-frame carrier after
envelope/unit tests pass, then discovers during Review or Worktree migration that
real WKWebView delivery cannot support the required stream lifecycle.

Required plan revision:

- Add a real WKWebView/native intake-carrier proof gate to slice 00.
- Make protocol migration blocked until the real intake-carrier proof passes.
- Name exact Swift/WebKit suites or add a dedicated spike fixture for ordered
  bursts, cancel, reset, stale close, and bounded memory.

### B2. Privileged page-world RPC ingress is not owned by any ticket

Evidence:

- `spec.md:420-433` requires content-world-only privileged RPC ingress.
- `BridgeBootstrap.swift:108-155`, `bridge-rpc-client.ts:43-57`, and
  `bridge-page-handshake.ts:49-58` show the current `__bridge_command` /
  `__bridge_ready` path still crosses the page-world event surface.
- `slices/01-transport-contracts.md:46-53` owns descriptors/resource URLs, not
  privileged RPC boundary.
- `slices/02-browser-demand-runtime.md:44-53` tests descriptor-like page events,
  not direct RPC/ready events.

Failure scenario:

New stream/open/refresh/cancel commands inherit the old page-world command path,
so page scripts can trigger privileged actions using DOM-visible nonce state.

Required plan revision:

- Add a blocking transport/security task for content-world-only privileged RPC.
- Add negative browser/integration proof that page-world `__bridge_command` and
  `__bridge_ready` cannot open streams, fetch resources, or reach Swift.

### B3. Slice 02 assumes descriptor-backed demand before Review emits descriptors

Evidence:

- `slices/01-transport-contracts.md:46-55` creates generic descriptors.
- `slices/02-browser-demand-runtime.md:56-64` adapts existing Review selected and
  visible content fetches before the Review protocol vertical emits frames with
  attached descriptors.
- `spec.md:342-352` and `review-protocol.md:281-286` require accepted attached
  descriptors and `BridgeDescriptorRef`s before demand.
- Current Review content still flows through Review package content handles and
  resource URLs in `bridge-app.tsx`, `content-resource-loader.ts`, and
  `visible-review-content-hydration.ts`.

Failure scenario:

Slice 02 either synthesizes descriptors from Review-package handles in the
generic layer, partially migrates Review before slice 03, or supports both old
and new fetch authority despite the hard-cutover rule.

Required plan revision:

- Either merge the generic demand runtime into the Review protocol vertical, or
  add an explicit transition adapter ticket with clear ownership and tests.
- Add architecture proof that generic scheduler/executor modules do not import
  Review package schemas or read `resourceUrl` directly.

### B4. Slice 03 cleanup can break Worktree dev proof before slice 04 replaces it

Evidence:

- `slices/03-review-protocol-vertical.md:73-82` removes old Review package push
  after the Review ticket gates.
- `implementation-plan.md:82-84` says Worktree/File still fabricates a Review
  package until slice 04.
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts:54-80` fetches a Review package
  and dispatches it as `store: 'diff'`.
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts:423-433` still
  mints Review content handles and `agentstudio://resource/content/...` URLs.

Failure scenario:

The Review vertical removes the old package push and `test:dev-server:worktree`
loses its current proof path before Worktree/File owns a replacement protocol.

Required plan revision:

- Move old Review package push cleanup to the Worktree/File cutover or final
  cleanup ticket.
- Require slice 03 handoff to state whether `test:dev-server:worktree` remains
  supported and how.

### B5. Worktree/File slice is not independently mergeable as written

Evidence:

- `worktree-file-surface-protocol.md:29-39` makes provider/source identity,
  watch/status classification, descriptors, invalidations, content handles, and
  reset decisions provider-owned.
- `slices/04-worktree-file-surface.md:31-35` names only dev-server files and
  vague "Current Swift ReviewFoundation browse/open-file paths".
- `slices/04-worktree-file-surface.md:70-91` has BridgeWeb/dev-server proof only.
- `BridgeReviewPipeline.swift:15-79` still owns native browse/open-file behavior
  through Review query kinds.

Failure scenario:

Slice 04 passes as a Vite/dev-provider prototype while native AgentStudio and the
browser root still treat Worktree/File as Review-shaped behavior.

Required plan revision:

- Split slice 04 into:
  - ticket 03 Worktree/File source identity, provider, and native boundary.
  - ticket 04 Worktree/File browser surface, materializer, and stale-refresh UX.
- Add native proof that Worktree/File snapshots/descriptors come from a non-Review
  host surface.
- Add browser proof that the Worktree surface boots without parsing or pushing
  `BridgeReviewPackage`.

## Important Revisions

### I1. Integrity and preview-only semantics need ticket ownership

Evidence:

- `spec-review-report.md:80-86` accepted whole-body validation for authoritative
  resources and preview-only ranged/chunked reads until chunk manifests exist.
- `spec.md:927-928` requires tampered/truncated body rejection and preview range
  non-authority proof.
- `slices/01-transport-contracts.md:46-53`,
  `slices/02-browser-demand-runtime.md:56-63`, and
  `slices/04-worktree-file-surface.md:60-69` do not assign integrity enforcement
  or proof.

Required plan revision:

- Assign integrity verification ownership to slice 01 or 02.
- Add Worktree/File rules that preview/range bodies cannot commit authoritative
  state or anchor comments/review decisions.

### I2. Scheduler/backpressure needs concrete policy, not prose

Evidence:

- `slices/02-browser-demand-runtime.md:40-52` says concurrency, byte caps, aborts,
  and stale drops but does not name queue ceilings, coalescing limits, LRU bounds,
  or drop/degrade policy.
- `spec.md:774-782` and `spec.md:1030-1035` require bounded concurrency and
  byte/work budgets.
- Current visible hydration still fans out per visible item in
  `visible-review-content-hydration.ts:114-183`.

Required plan revision:

- Add named defaults or explicit first-implementation constants for per-lane
  concurrency, max queued intents, max bytes/work, registry/LRU ceilings, and
  overload behavior.
- Add stress proof for invalidation storms, viewport churn, foreground preemption,
  capped queues, and no hydrate-all fallback.

### I3. Telemetry canaries and reserved comments/comms are unowned

Evidence:

- `plan-ledger.md:67-73` acknowledges telemetry redaction needs proof.
- `implementation-plan.md:103-116` final done gate omits telemetry and
  comments/comms fail-closed proof.
- `spec.md:906-915` and `spec.md:936` require telemetry canaries.
- `spec-review-report.md:95-100` requires comments/comms flags and resource kinds
  to fail closed or stay disabled until a later schema/permission/redaction slice.

Required plan revision:

- Add telemetry canary proof to slice 02, 03, or 05 with seeded raw path, content,
  prompt, capability URL, comment, and comms strings.
- Add a cross-slice rule and parser/registry tests that comments/comms resource
  kinds and flags stay unregistered/rejected in this epic.

### I4. Stale-open-file refresh proof is too implicit

Evidence:

- `worktree-file-surface-protocol.md:320-324` says `openFileInvalidated` marks
  stale and emits no content demand; refresh requires `explicitRefresh`.
- `worktree-file-surface-protocol.md:458-462` locks first implementation to
  manual refresh after stale marker.
- `slices/04-worktree-file-surface.md:44-58` names this behavior, but
  `slices/04-worktree-file-surface.md:70-91` does not name exact test files or
  a browser/app UX proof.

Required plan revision:

- Add explicit automated proof for: open file invalidated -> stale marker shown
  -> no auto-fetch -> manual refresh fetches latest.

### I5. Shared fixtures and proof gates are under-scoped

Evidence:

- `slices/01-transport-contracts.md:9-13` promises a shared accept/reject corpus,
  but `slices/01-transport-contracts.md:56-70` does not include the repo fixture
  sync gate.
- `BridgeWeb/package.json:10` exposes `check`.
- `.mise.toml:239-263` exposes `test`, `test-fast`, `test-large`, and
  `test-webkit`.
- `scripts/bridge-web-sync-fixtures.sh` exists for fixture parity.

Required plan revision:

- Add `bash scripts/bridge-web-sync-fixtures.sh` or the relevant `mise` task to
  slice 01 and any later slice that changes shared fixtures.
- Add `pnpm --dir BridgeWeb run check` to relevant BridgeWeb tickets.
- Use focused Bridge Swift suites first; keep repo-wide `mise run test` and
  `mise run lint` as milestone/final gates.

## Rejected Or Downgraded Findings

- Pierre/CodeView is not a separate pre-slice blocker. Slice 03 already has a
  renderer identity stop/reconverge gate. Keep it as a targeted risk, not a new
  foundation ticket.
- "Intake carrier proof is unnecessary" is rejected. Current push transport is
  isolated enough to test, and the spec explicitly requires a carrier proof gate
  before protocol migration.
- "Telemetry allowlisting does not exist today" is rejected. Existing Swift
  telemetry validator tests and allowlists cover taxonomy; the gap is seeded
  canary proof for the new bridge fields.
- "Current stale-drop is only generation-based everywhere" is too broad. Current
  Review browser content has stale revision protections; the real gap is
  cross-protocol consistency and source-reset behavior.

## Recommended Revised Ticket Order

1. `00` Intake carrier proof with real WKWebView/native streaming proof.
2. `01` Transport contracts plus content-world privileged RPC boundary, shared
   fixture sync, descriptor/lease/integrity ownership.
3. `02` Review vertical, including descriptor-backed demand runtime after Review
   frames attach descriptors, while preserving Worktree dev proof until
   Worktree/File replaces Review-package scaffolding.
4. `03` Worktree/File source identity, provider, and native boundary.
5. `04` Worktree/File browser feature surface, stale manual refresh, and
   dev-server UX.
6. `05` Hard-cutover cleanup and final regression/canary gates.

## Plan Revision Checklist

- [ ] Add real WKWebView carrier proof to slice 00.
- [ ] Add content-world-only privileged RPC boundary work and negative page-world
      tests.
- [ ] Resolve descriptor-backed demand sequencing by merging the standalone
      demand ticket into the Review vertical.
- [ ] Move old Review package push cleanup out of slice 03 unless Worktree dev
      proof is preserved.
- [ ] Split Worktree/File into provider/native and browser/UX tickets.
- [ ] Assign integrity, preview-only, telemetry canary, and comments/comms
      fail-closed proof.
- [ ] Add exact new test-file names for scheduler policy, scheduler/executor,
      source reset, stale refresh, and page-world security fixtures.
- [ ] Add focused proof commands and fixture-sync gates per ticket.

## Parent Review Decision

Do not execute this plan yet. Route back to plan revision. The current plan has
the right broad intent and useful vertical-ticket shape, but several tickets are
not actually independently mergeable/provable against the accepted spec and live
code boundaries.
