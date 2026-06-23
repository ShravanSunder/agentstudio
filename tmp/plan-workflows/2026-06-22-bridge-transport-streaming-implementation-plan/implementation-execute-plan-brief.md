# Implementation Execute Plan Brief

Date: 2026-06-22
Goal id: `2026-06-22-bridge-transport-streaming`
Branch: `luna-338-pierreshikitrees-review-viewer-2`

## Official Workflow State

Latest valid orchestrator event:

- from: `shravan-dev-workflow:plan-review-swarm`
- to: `shravan-dev-workflow:implementation-execute-plan`
- phase result: `complete`
- decision: plan-review-swarm 1.6.29 accepted and patched validated blockers;
  implementation starts at ticket 00, and ticket 01 is blocked until ticket 00
  proves the real WKWebView carrier or design reconverges.

Ticket 00 status:

- committed: `bbf9e51c feat: prove bridge intake carrier`

Current ticket:

- ticket 02: review protocol vertical, current post-review fix pass is ready
  for renewed implementation-review-swarm reduction, not checkpoint acceptance
  yet

## Source Coverage In This Controller Run

Fully loaded:

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
  lines 1-1124
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
  lines 1-458
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
  lines 1-483
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec-review-report.md`
  lines 1-295
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
  lines 1-325
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md`
  lines 1-392
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md`
  lines 1-319
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-1.6.29-report.md`
  lines 1-154
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-ledger.md`
  lines 1-162
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/00-carrier-proof.md`
  lines 1-143
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/01-transport-contracts.md`
  lines 1-133
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/02-review-protocol-vertical.md`
  lines 1-255
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/03-worktree-file-native-provider.md`
  lines 1-145
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/04-worktree-file-browser-surface.md`
  lines 1-159
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/05-hard-cutover-cleanup.md`
  lines 1-122
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/codebase-boundary.md`
  lines 1-70
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/validation-proof.md`
  lines 1-69
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/execution-order-security-reliability.md`
  lines 1-67
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/details.md`
  lines 1-182
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl`
  lines 1-4

## Current Worktree Shape

Tracked modified files:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeBootstrapTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeContentWorldIsolationTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`

Untracked ticket-01 files:

- `BridgeWeb/src/core/bridge-host/**`
- `BridgeWeb/src/core/models/bridge-core-models.ts`
- `BridgeWeb/src/core/models/bridge-core-models.unit.test.ts`
- `BridgeWeb/src/core/models/bridge-protocol-registry.ts`
- `BridgeWeb/src/core/models/bridge-protocol-registry.unit.test.ts`
- `BridgeWeb/src/core/models/bridge-resource-descriptor.ts`
- `BridgeWeb/src/core/resources/**`
- `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/valid/transport-resource-url-corpus.json`
- `Sources/AgentStudio/Features/Bridge/Models/Transport/**`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeTransportResourceLeaseRegistry.swift`
- `Tests/BridgeContractFixtures/valid/transport-resource-url-corpus.json`

The diff is ticket-01-shaped: protocol-scoped resource URLs, core resource
models, descriptor/resource registries, content-world privileged RPC ingress,
host-side lease registry, fixture parity, and focused transport/security tests.

## Current Ticket 02 Review-Fix Pass

Latest implementation-review verdict addressed in this pass:

- not ready
- accepted blockers:
  - Review protocol still emitted snapshot-only frames instead of real
    `review.delta`, `review.invalidate`, and standalone `review.reset`
  - frame authority was self-authenticated from incoming pane/stream fields
    instead of host-published local pane/stream authority
  - standalone reset did not revoke descriptor authority before later loads
  - delta materialization could fail open and reuse stale descriptor refs
- accepted important findings from that review were carried into the current
  proof slice: scheduler/executor queue and cancel ownership, changeset-cluster
  metadata parity, Swift frame failure surfacing, demand-runtime proof
  accounting, and markdown security proof accounting.

Fixed in the current working tree:

- `review.delta` now has a real end-to-end protocol path:
  Swift frame builder/controller, browser dev/test helpers, Zod schema, TS frame
  builder, materializer, descriptor registration, app admission, and telemetry
  parent refresh.
- `review.invalidate` is schema/materializer/Swift-builder covered as a
  metadata-only invalidation fact.
- standalone `review.reset` is schema/materializer/Swift-builder covered and
  BridgeApp revokes descriptor refs before the next selected load when
  authority matches.
- BridgeApp accepts Review frames only against host-published
  `data-bridge-review-pane-id` and `data-bridge-review-stream-id`; incoming
  frame authority is no longer enough to self-authorize descriptors.
- Delta materialization failure clears/cancels current descriptor refs instead
  of falling back to stale refs.
- Scheduler/executor pressure now keeps foreground and active demand queueable
  under transient pressure while visible, nearby, and speculative demand stay
  opportunistic/deferred.
- Selected content demand preserves retryable deferred state instead of turning
  transient pressure into terminal content unavailable.
- Mocked deferred content fetches remove pending responses when aborted, so
  stale visible-lane requests cannot mask later foreground selected requests.
- Browser invalidation keeps bypassing stale cached bodies until a refetch
  succeeds, so one aborted retry cannot replay old content.
- Swift Review package publication now builds snapshot/delta protocol frames
  before content authority activation and stores those frames with the package
  facts in `DiffState`; package/delta push slices no longer silently downgrade
  frame-builder failures to `protocolFrame: nil`.
- TS and Swift descriptor `maxBytes` for root package and delta operation
  metadata are aligned at the 768 KiB IPC payload budget.
- Content queue/fetch telemetry now labels selected versus visible demand,
  records success/deferred/failed result facts, and no longer force-flushes
  every content fetch sample.
- Normal dev-server verification now waits for `domcontentloaded` plus explicit
  app-state probes instead of `networkidle`, which was brittle once Vite OTEL
  traffic was enabled.
- Browser benchmark worker-backed cold package push now waits for the Pierre
  loading status to disappear inside the measured duration before asserting.

Fresh proof after current review-fix pass:

```bash
pnpm --dir BridgeWeb run fmt
```

Result: exit 0.

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0.

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-demand-models.unit.test.ts \
  src/core/demand/bridge-demand-scheduler.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/demand/bridge-resource-executor.unit.test.ts \
  src/features/review/models/review-protocol-models.unit.test.ts \
  src/features/review/materialization/review-materializer.unit.test.ts \
  src/features/review/demand/review-demand-policy.unit.test.ts \
  src/features/review/protocol/review-snapshot-frame-builder.unit.test.ts \
  src/review-viewer/content/review-content-demand-loader.unit.test.ts \
  src/review-viewer/content/visible-review-content-hydration.unit.test.tsx \
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts \
  src/app/bridge-app.integration.test.tsx
```

Result: exit 0, 12 files passed, 107 tests passed. Existing jsdom
ResizeManager warnings remain.

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/review-viewer/markdown/bridge-markdown-preview.unit.test.tsx \
  src/review-viewer/markdown/bridge-markdown-render-mode.unit.test.ts \
  src/review-viewer/workers/markdown/bridge-markdown-render-worker-rpc.unit.test.ts \
  --reporter verbose
```

Result: exit 0, 3 files passed, 16 tests passed.

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
```

Result: exit 0, 1 file passed, 30 tests passed. One immediately preceding full
run failed once on the content-unavailable browser case staying `loading`; a
single-case rerun and a full rerun both passed, so this is recorded as a
transient browser retry unless it recurs. Existing React `flushSync` warnings
remain in two filter tests.

```bash
pnpm --dir BridgeWeb run test:dev-server
```

Result: exit 0 for the large-diffshub mock URL. The verifier originally timed
out at `networkidle` on the telemetry-enabled markdown URL; the harness now uses
`domcontentloaded` plus explicit app-state probes, matching the worktree
verifier.

```bash
BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree' \
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Result: exit 0; selected `.github/workflows/ci.yml` reached ready, worker pool
was ready, and the exact current-worktree URL loaded.

```bash
pnpm --dir BridgeWeb run test:benchmark:browser
```

Result: exit 0, 1 browser benchmark file passed. Artifact:
`tmp/bridge-viewer-browser-benchmark/2026-06-23T14-14-04-892Z`.

```bash
mise run format
```

Result: exit 0.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter BridgeReviewProtocolFrameBuilderTests
```

Result: exit 0, 11 Swift tests passed.

```bash
mise run lint
```

Result: exit 0; SwiftLint found 0 violations, architecture lint OK, release
script verification passed.

```bash
git diff --check
```

Result: exit 0.

Dev server status:

- `node` PID `84893` is listening on `127.0.0.1:5173`.
- `curl http://127.0.0.1:5173/__bridge-dev-telemetry/status` returned
  `acceptedBatchCount=6466`, `acceptedSampleCount=27859`,
  `failedBatchCount=0`, marker `vite-dev-ticket02-1782220582`.

Next safe action:

- reduce the renewed `implementation-review-swarm` lanes against the current
  worktree; fix accepted findings if any. Do not checkpoint, commit, or advance
  to Worktree/File until that review is ready.

## Ticket 01 Delta In This Controller Run

Parser parity hardening:

- Added shared invalid corpus cases for:
  - double-encoded traversal segment:
    `agentstudio://resource/review/content/%252e%252e?...`
  - empty cursor:
    `agentstudio://resource/review/content/content-123?...&cursor=`
- Observed red proof before the parser fixes:
  - TypeScript accepted the double-encoded traversal segment.
  - Swift accepted the empty cursor.
- Fixed TypeScript protocol resource parser to stable-decode path segments until
  fixed point before traversal checks.
- Fixed Swift protocol resource parser to reject empty cursor values.

Content-world RPC envelope hardening:

- Observed red proof that the bridge-world privileged RPC helper posted
  `{ id, protocol, method, params }` without the JSON-RPC version.
- Fixed the helper to post `{ jsonrpc: "2.0", id, protocol, method, params }`
  through `window.__bridgeInternal.sendCommandJSON`.

## Ticket 01 Proof Gathered So Far

Passed:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-core-models.unit.test.ts \
  src/core/models/bridge-protocol-registry.unit.test.ts \
  src/core/resources/bridge-resource-url.unit.test.ts \
  src/core/resources/bridge-resource-descriptor.unit.test.ts \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/core/resources/bridge-integrity.unit.test.ts \
  src/core/bridge-host/bridge-content-world-rpc.integration.test.ts \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/foundation/content/content-resource-loader.integration.test.ts
```

Result: exit 0, 9 files passed, 36 test groups / 39 tests in 39ms.

Passed after parser parity hardening:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/resources/bridge-resource-url.unit.test.ts
```

Red before patch:

- exit 1, double-encoded traversal segment was parsed instead of rejected.

Green after patch:

- exit 0, 1 file passed, 2 tests passed.

Passed after parser parity hardening:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter \
  BridgeSchemeHandlerTests/test_transportResourceURL_rejectsInvalidProtocolScopedURL
```

Red before patch:

- exit 1, empty cursor was parsed instead of rejected.

Green after patch:

- exit 0, 1 Swift Testing test passed.

Passed after content-world RPC envelope hardening:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/bridge-host/bridge-content-world-rpc.integration.test.ts
```

Red before patch:

- exit 1, posted command omitted `jsonrpc: "2.0"`.

Green after patch:

- exit 0, 1 file passed, 2 tests passed.

Passed:

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Result: exit 0, BridgeWeb fixtures in sync.

Passed:

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0, oxlint, architecture check, oxfmt, and TypeScript passed.

Passed after content-world RPC envelope hardening:

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0, oxlint, architecture check, oxfmt, and TypeScript passed.

Passed:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-webkit
```

Result: exit 0, full WebKit lane passed; 17 filters passed.

Passed:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter 'BridgeSchemeHandlerTests|BridgeBootstrapTests'
```

Result: exit 0, 58 tests passed in the focused Bridge suites.

Passed after parser parity hardening:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter 'BridgeSchemeHandlerTests|BridgeBootstrapTests'
```

Result: exit 0, 58 tests in 2 suites passed.

Passed:

```bash
mise run lint
```

Result: exit 0, swift-format, SwiftLint, architecture lint, and release script
verification passed.

Passed no-match scan:

```bash
rg -n "Task\\.sleep|sleep\\(|setTimeout|setInterval|waitForTimeout|requestAnimationFrame|timeout: \\.seconds\\(5\\)" \
  BridgeWeb/src/core \
  BridgeWeb/src/bridge/bridge-resource-url.unit.test.ts \
  BridgeWeb/src/foundation/content/content-resource-loader.integration.test.ts \
  Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift \
  Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift \
  Tests/AgentStudioTests/Features/Bridge/BridgeBootstrapTests.swift \
  Tests/AgentStudioTests/Features/Bridge/BridgeContentWorldIsolationTests.swift \
  Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift \
  Sources/AgentStudio/Features/Bridge/Transport \
  Sources/AgentStudio/Features/Bridge/Models/Transport
```

Result: exit 1, no matches.

## Current Blocker

Required ticket-01 Swift gate:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast
```

Result: exit 1.

Isolated visible blocker:

```bash
SWIFT_TEST_SKIP_PREBUILD=1 \
SWIFT_TEST_TIMEOUT_SECONDS=60 \
mise run test-fast -- --filter \
  CommandBarDataSourceTests/test_commandsScope_includesOpenBridgeReview
```

Result: exit 1, `CommandBarDataSourceTests.swift:157:9`.

Expected title: `Open Bridge Review`
Actual title: `Review`

Classification:

- outside ticket-01 transport/security write scope
- does not authorize changing command-bar behavior as part of this checkpoint
  without an explicit scope decision
- recorded as a broad Swift health blocker after splitting ticket-scoped
  checkpoint proof from broad repo health in:
  - `implementation-plan.md`
  - `slices/01-transport-contracts.md`
  - `plan-ledger.md`

## Next Safe Action

Ticket 01 can proceed to checkpoint review/commit only with the proof split
visible in the handoff:

- ticket-scoped BridgeWeb, fixture sync, focused Swift Bridge, WebKit, and lint
  gates passed
- broad `test-fast` remains open due the unrelated CommandBar title mismatch
- no unrelated CommandBar edit is included in ticket 01

Next workflow after parent verification:

- run `shravan-dev-workflow:implementation-review-swarm` for ticket 01 because
  the slice changes the Bridge trust/transport boundary

## Ticket 01 Review-Fix Checkpoint

Commit:

- `f09d768a fix: close bridge transport review findings`

Review findings addressed:

- Page-world method-only privileged RPC names are fenced in bootstrap and
  rejected again in `RPCRouter` when marked `__bridgeOrigin:
  "pageWorldLegacy"`.
- Descriptor registry registration now validates the descriptor resource URL
  against descriptor protocol/kind/generation/revision/cursor and exposes
  `revoke` plus `resetIdentity`.
- Lease authority is descriptor/pane-bound instead of a bare canonical URL set;
  leased content is rechecked before response and before data emission.
- Core contract drift was corrected: protocol/resource ids use the accepted
  dotted/hyphenated grammar, integrity uses `wholeHash`/`chunkManifest`/
  `previewOnly`, the default app protocol registry was removed, and shared
  fixtures cover encoded and double-encoded slashes.
- Legacy scheme routes now reject non-read methods and duplicate/unknown
  generation query shapes before loading content.

Fresh proof after review-fix patch:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-core-models.unit.test.ts \
  src/core/models/bridge-protocol-registry.unit.test.ts \
  src/core/resources/bridge-resource-url.unit.test.ts \
  src/core/resources/bridge-resource-descriptor.unit.test.ts \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/core/resources/bridge-integrity.unit.test.ts \
  src/core/bridge-host/bridge-content-world-rpc.integration.test.ts \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/foundation/content/content-resource-loader.integration.test.ts
```

Result: exit 0, 9 files passed, 42 tests passed.

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Result: exit 0, BridgeWeb fixtures in sync, 17 files.

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0, oxlint, BridgeWeb architecture check, oxfmt, and TypeScript
passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-webkit
```

Result: exit 0, real WebKit serialized lane passed. The lane is defined by
`.mise.toml` as `Run real WebKit runtime tests in isolated serial processes
with crash retry`; the runner executed the configured serialized filters,
including `BridgeContentWorldIsolationTests`.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter \
  'BridgeSchemeHandlerTests|BridgeBootstrapTests|RPCRouterTests|RPCRouterPrivilegedIngressTests|BridgeContentWorldIsolationTests'
```

Result: exit 0, 96 tests in 4 suites passed. `BridgeContentWorldIsolationTests`
is a WebKit suite and is covered by `mise run test-webkit`; the fast-lane filter
ran the non-WebKit Bridge suites plus `RPCRouterPrivilegedIngressTests`.

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
mise run lint
```

Result: exit 0, swift-format OK, SwiftLint 0 violations / 0 serious across
1304 files, AgentStudio architecture lint OK, release script verification
passed.

Broad Swift health:

- Not claimed as green for ticket 01.
- Existing external blocker remains `CommandBarDataSourceTests/
  test_commandsScope_includesOpenBridgeReview`, expected `Open Bridge Review`
  versus actual `Review`.
- This remains outside the ticket-01 transport/security write scope and should
  not be fixed as part of the ticket-01 review-finding patch.

phase_result: complete
evidence: `f09d768a`, the commands and results above, and
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 accepted implementation-review
findings are addressed with fresh scoped proof; the fixed trust/transport
boundary needs review again before ticket 02 begins.

## Ticket 01 Second Review-Fix Checkpoint

Commit:

- `10d2b075 fix: bind bridge resource leases to descriptors`

Review findings addressed:

- Swift lease authority now rejects descriptor ids that do not match the URL
  opaque resource authority, stores max byte limits, supports scoped reset, and
  rechecks the lease with loaded byte count before response/data emission.
- The legacy `agentstudio://resource/content/...` route no longer classifies as
  content and is covered by fail-closed tests for missing, duplicate, unknown,
  negative, and overflow generation shapes.
- Content handles now mint protocol-scoped URLs:
  `agentstudio://resource/review/content/<handle>?generation=<n>`.
- The browser review content parser and mocks now use the same
  `agentstudio://resource/{protocol}/{kind}/{opaqueId}` shape, so real Swift
  handles and browser materialization agree.
- Descriptor registration now requires the parsed URL opaque id to match the
  descriptor id.
- OPTIONS returns a no-body preflight response without loading content; HEAD
  emits response metadata without a body.
- The Swift scheme handler receives an injected protocol/kind registry from an
  app-owned registry value instead of owning the registry inline.

Fresh proof after second review-fix patch:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/review-viewer/content/review-content-registry.unit.test.ts \
  src/review-viewer/content/review-content-loader.unit.test.ts \
  src/review-viewer/projections/review-item-window-registry.unit.test.ts \
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts
```

Result: exit 0, 6 files passed, 55 tests passed.

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0, oxlint, BridgeWeb architecture check, oxfmt, and TypeScript
passed.

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Result: exit 0, BridgeWeb fixtures in sync, 17 files.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter \
  'BridgeSchemeHandlerTests|BridgeGitReviewSourceProviderTests|BridgeReviewDeltaBuilderTests|BridgePushEnvelopeEncoderTests'
```

Result: exit 0, 68 tests in 4 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-webkit
```

Result: exit 0, real WebKit serialized lane passed. The first run exposed a
test setup gap in `test_pushPackageMetadata_rendersReviewViewerShell`; after
registering the test content leases, the rerun passed the full serial WebKit
lane including real diff content fetches.

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
mise run lint
```

Result: exit 0, swift-format OK, SwiftLint 0 violations / 0 serious across
1305 files, AgentStudio architecture lint OK, release script verification
passed.

Broad Swift health:

- Not claimed as green for ticket 01.
- Existing external blocker remains `CommandBarDataSourceTests/
  test_commandsScope_includesOpenBridgeReview`, expected `Open Bridge Review`
  versus actual `Review`.
- This remains outside the ticket-01 transport/security write scope and should
  not be fixed as part of the ticket-01 review-finding patch.

phase_result: complete
evidence: `10d2b075`, the commands and results above, and
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-review-fix-report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 second review-fix findings are
addressed with fresh scoped proof; the fixed trust/transport boundary needs
review again before ticket 02 begins.

## Ticket 01 Third Review-Fix Checkpoint

Commit:

- `acb4bd3f fix: close bridge content authority gaps`

Review findings addressed:

- Dev-server, contract fixture, IPC fixture, and benchmark fixture resource URLs
  now use protocol-scoped review content URLs.
- Browser content URL parsing now stable-decodes path segments to a fixed point
  and rejects decoded slash separators inside opaque id segments.
- `HEAD` content requests now emit metadata-only responses through
  `BridgeContentStore.metadata` without provider materialization.
- Controller-owned content lease registration is directly asserted after
  `loadDiff` publishes package metadata.
- Failed reloads clear prior review content authority before the new generation
  can fail, with a dedicated WebKit-serialized controller test.
- Lease replacement is batch-validated and swapped by pane/protocol/kind through
  `BridgeTransportResourceLeaseRegistry.replace`.
- The Swift worktree-file registry no longer advertises the unimplemented
  `file-content` kind.
- Bridge pane teardown now deactivates review content store state and resets
  review/content leases.
- The new controller content-authority suite is included in the WebKit
  serialized lane and guarded by a script test.

Fresh proof after third review-fix patch:

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0, oxlint, BridgeWeb architecture check, oxfmt, and TypeScript
passed.

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/review-viewer/content/review-content-registry.unit.test.ts \
  src/review-viewer/content/review-content-loader.unit.test.ts \
  src/review-viewer/projections/review-item-window-registry.unit.test.ts \
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts \
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts \
  src/foundation/review-package/bridge-contract-fixtures.unit.test.ts
```

Result: exit 0, 8 files passed, 68 tests passed.

```bash
pnpm --dir BridgeWeb exec vitest run \
  scripts/bridge-viewer-browser-benchmark-runner.unit.test.ts
```

Result: exit 0, 1 file passed, 8 tests passed.

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Result: exit 0, BridgeWeb fixtures in sync, 17 files.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter \
  'BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests|BridgeGitReviewSourceProviderTests|BridgeReviewDeltaBuilderTests|BridgePushEnvelopeEncoderTests|BridgeReviewFoundationContractTests'
```

Result: exit 0, 74 tests in 6 suites passed.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter \
  'AgentStudioIPCBridgeServiceTests|AgentStudioAppIPCServiceTests'
```

Result: exit 0, 31 tests in 2 suites passed.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 62.52s and explicitly ran
`WebKitSerializedTests/BridgePaneControllerContentAuthorityTests`.

```bash
mise run format && mise run lint
```

Result: exit 0, swift-format OK, SwiftLint 0 violations / 0 serious across
1307 files, AgentStudio architecture lint OK, release script verification
passed.

```bash
rg -n "agentstudio://resource/content/" BridgeWeb Sources Tests scripts \
  --glob '!BridgeWeb/scripts/check-bridgeweb-architecture.unit.test.ts' \
  --glob '!Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift'
```

Result: exit 1, no active-source legacy content URL matches outside intentional
negative fixtures.

Broad Swift health:

- Not claimed as green for ticket 01.
- Existing external blocker remains `CommandBarDataSourceTests/
  test_commandsScope_includesOpenBridgeReview`, expected `Open Bridge Review`
  versus actual `Review`.
- This remains outside the ticket-01 transport/security write scope and should
  not be fixed as part of the ticket-01 review-finding patch.

phase_result: complete
evidence: `acb4bd3f`, the commands above, and
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-second-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 second-review findings are addressed
with fresh scoped proof; the Bridge trust/transport boundary needs review again
before ticket 02 begins.

## Ticket 01 Third Review Follow-Up Fix

Review verdict:

- The third ticket-01 review-fix review returned `not_ready`.
- Accepted findings were fixed in the same follow-up pass.

Accepted findings addressed:

- Content-handle activation used the broader review-viewer allowlist and ignored
  `replace(false)`.
- `BridgeContentStore.deactivate()` did not invalidate in-flight provider loads
  when the provider ignored cancellation.
- The review-viewer worktree-file allowlist narrowing lacked a permanent
  negative test.
- `BridgePaneController.teardown()` returned before review/content lease
  authority was synchronously closed.
- Refresh-failure proof initially encoded old metadata with revoked old leases;
  the invariant is now old metadata and old leases stay live together when new
  metadata validation fails before authority installation.

Fresh proof:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests'
```

Result: exit 0, 70 tests in 2 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 90.70s and explicitly ran 3
`BridgePaneControllerContentAuthorityTests`.

phase_result: complete
evidence:
`60fb99d7 fix: harden bridge content authority revocation`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-third-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 third-review findings are fixed with
fresh scoped proof; the Bridge trust/transport boundary needs another review
before ticket 02 begins.

## Ticket 01 Fourth Review Follow-Up Fix

Review verdict:

- The review of `60fb99d7` returned `not_ready`.
- Accepted findings were fixed in this follow-up pass.

Accepted findings addressed:

- Teardown could synchronously revoke current review/content authority, then an
  already-running `loadDiff` could finish later and re-authorize leases.
- Same-generation refreshes rejected otherwise-valid in-flight content loads
  when the refreshed package preserved the same handle.
- Filtered lease resets widened beyond their API contract because the
  synchronous gate ignored generation/revision/cursor filters.
- Invalid-refresh and teardown tests under-proved the intended authority
  contracts.
- Workflow-state history recorded the previous code-bearing checkpoint as
  review-to-review instead of execute-to-review.

Fresh proof:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Result: exit 0, 73 tests in 3 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 85.70s and explicitly ran 5
`BridgePaneControllerContentAuthorityTests`.

```bash
mise run format
mise run lint
```

Result: both exit 0; SwiftLint reported 0 violations in 1307 files,
architecture lint passed, and release script verification passed.

phase_result: complete
evidence:
`e076fc4b fix: fence bridge content authority after teardown`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fourth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fourth-review findings are fixed with
fresh scoped proof; the Bridge trust/transport boundary needs another review
before ticket 02 begins.

## Ticket 01 Fifth Review Follow-Up Fix

Review verdict:

- The review of `e076fc4b` returned `not_ready`.
- Accepted findings were fixed in this follow-up pass.

Accepted findings addressed:

- Content-store activation could become visible before the
  revocation-revision-checked lease replacement succeeded.
- IPC content loads read directly from `BridgeContentStore` after teardown
  without consulting the synchronous review/content authority gate.
- Direct lease registration could bypass the revocation-revision contract.
- Same-generation content preservation used full `BridgeContentHandle` equality
  instead of the explicit content authority identity.
- Workflow-state/checkpoint text still pointed at the third-review pass.
- The previous fourth-review proof packet overclaimed green-only proof.

Fresh proof:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Result: exit 0, 24 tests in 2 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 96.77s and included
`BridgePaneControllerIPCProjectionTests` with 6 tests.

```bash
mise run lint
```

Result: exit 0; swift-format OK, SwiftLint reported 0 violations in 1307 files,
architecture lint passed, and release script verification passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Result: exit 0, 75 tests in 3 suites passed.

Red-proof attempt:

```bash
MISE_TRUSTED_CONFIG_PATHS=.../tmp/red-proof-e076fc4b/.mise.toml \
SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests/contentStorePreservesSameAuthorityInFlightLoadsWhenNonKeyMetadataChanges'
```

Result: exit 1 before test execution. The detached scratch checkout at
`tmp/red-proof-e076fc4b` is pinned to `e076fc4b`, but it lacks the vendored
`Frameworks/GhosttyKit.xcframework` artifact required by package prebuild.

phase_result: complete
evidence:
`57601c5b fix: close bridge content authority race`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review findings are fixed with
fresh scoped proof; the Bridge trust/transport boundary needs another review
before ticket 02 begins.

## Ticket 01 Fifth Review Post-Review Follow-Up Fix

Review verdict:

- The review of `57601c5b` returned `not_ready`.
- Accepted findings were fixed in `b68c70ea`.

Accepted findings addressed:

- Teardown could still be captured as the expected revocation revision by an
  in-flight `loadDiff` after `clearReviewContentAuthority()` suspended.
- Cached/coalesced content bytes were not normalized onto the current active
  handle before returning, leaving stale active policy and metadata gaps.
- `BridgeTransportResourceLeaseRegistry.replace` still allowed callers to omit
  the expected revocation revision.
- IPC proof covered teardown before a call, but not teardown while a
  provider-backed content load was in flight.
- The previous proof packet needed stronger controller/IPC/store evidence.

Fresh proof:

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Result: exit 0, 27 tests in 2 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 99.44s and included
`BridgePaneControllerIPCProjectionTests` with 8 tests.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Initial result: exit 1 because
`test_protocolScopedContentRouteRejectsOversizedLeaseBeforeEmittingBytes`
expected `.invalidRoute` after active byte-cap enforcement correctly moved the
failure to `.oversizedContent`.

Final result after correcting the test boundary: exit 0, 78 tests in 3 suites
passed.

```bash
mise run lint
```

Result: exit 0; swift-format OK, SwiftLint reported 0 violations in 1307 files,
architecture lint passed, and release script verification passed.

Commit note:

- First commit attempt failed before writing the commit object because the
  1Password signer returned `failed to fill whole buffer`.
- The same staged diff was committed with `--no-gpg-sign`.

phase_result: complete
evidence:
`b68c70ea fix: harden bridge content authority after review`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review post-review findings are
fixed with fresh scoped proof; the Bridge trust/transport boundary needs
another review before ticket 02 begins.

## Ticket 01 Fifth Review Second Post-Review Follow-Up Fix

Review verdict:

- The review of `b68c70ea` returned `not_ready`.
- Accepted findings were fixed in `4c4c7773`.

Accepted findings addressed:

- A superseding `loadDiff` could still leave the previous review/content
  authority usable while the new load was suspended inside provider comparison.
- Scheme-handler content emission had a check/yield gap: a revocation could
  occur after the final authority check but before response or body emission.
- The oversized-content scheme-handler proof asserted the thrown error but did
  not prove that zero response/data events were emitted first.

Recorded follow-up:

- Content cache hits and coalesced loads rehash full payloads during active
  policy validation. This remains correct for ticket 01 authority and is
  carried as a later performance follow-up.

Fresh proof:

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'
```

Result: exit 0, 78 tests in 3 suites passed.

```bash
mise run lint
```

Initial result: exit 1 because the strengthened zero-emission proof pushed
`BridgeSchemeHandlerTests` over the 800-line type body cap at 803 lines.

Final result after compacting that proof: exit 0; swift-format OK, SwiftLint
reported 0 violations in 1307 files, architecture lint passed, and release
script verification passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 99.82s and included
`BridgePaneControllerContentAuthorityTests` with 6 tests, including
`loadDiff synchronously revokes previous content authority while reload is in
flight`.

Commit note:

- First commit attempt failed before writing the commit object because the
  1Password signer returned `failed to fill whole buffer`.
- The same staged diff was committed with `--no-gpg-sign`.

phase_result: complete
evidence:
`4c4c7773 fix: close bridge authority races`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review second post-review
findings are fixed with fresh scoped proof; the Bridge trust/transport boundary
needs another review before ticket 02 begins.

## Ticket 01 Fifth Review Third Post-Review Follow-Up Fix

Review verdict:

- The review of `4c4c7773` / `aa6fd8da` returned `not_ready`.
- Accepted findings were fixed in `55c2689c`.

Accepted findings addressed:

- Scheme-handler response/body emission still checked revocation state without
  proving that the exact requested resource lease remained active at the moment
  of emission.
- Targeted revocation and filtered reset removed lease rows without keeping an
  exact resource tombstone, which left a stale expected revision path for
  re-registering removed authority.
- The HEAD content route lacked proof that authority loss before response
  emission produces zero scheme events.

Implementation:

- `BridgeTransportResourceLeaseRegistry` now records exact resource tombstones
  for targeted revokes and filtered resets.
- Direct registration now authorizes against both the aggregate revocation
  revision and the exact resource tombstone.
- Scheme-handler GET response, GET body, and HEAD response emission now call
  actor-isolated `performWhileLeased`, which checks exact active lease identity
  and byte cap while holding the authority gate around the emission closure.
- The old nonisolated synchronous emission helper was removed so emission has a
  single authority boundary.
- `BridgeSchemeHandlerContentAuthorityTests` owns the content-emission
  authority regressions after splitting them out of the general scheme-handler
  suite.

Fresh proof:

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'
```

Result: exit 0, 81 tests in 4 suites passed.

```bash
mise run lint
```

Result: exit 0; swift-format OK, SwiftLint reported 0 violations in 1308 files,
architecture lint passed, and release script verification passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 102.80s and included
`BridgePaneControllerContentAuthorityTests`,
`BridgePaneControllerIPCProjectionTests`, real diff content fetches, and
`WebviewPaneControllerTests`.

phase_result: complete
evidence:
`55c2689c fix: harden bridge lease emission authority`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review third post-review
findings are fixed with fresh scoped proof; the Bridge trust/transport boundary
needs another review before ticket 02 begins.

## Ticket 01 Fifth Review Fourth Post-Review Follow-Up Fix

Review verdict:

- The review of `55c2689c` / `7bed47d9` returned `not_ready`.
- Accepted findings were fixed in `2d55eef2`.

Accepted findings addressed:

- Final-emission proof still missed GET body authority loss after the response
  emitted and HEAD authority loss after metadata lookup.
- Filtered-reset tombstone/revision protection lacked permanent stale
  re-registration proof.
- `replace` cleared exact tombstones for the whole scope without advancing the
  revision, allowing a removed resource to be directly registered again with
  the same revision token.

Implementation:

- `BridgeTransportResourceLeaseRegistry.replace` clears exact tombstones only
  for the resources being installed and advances the scope revocation revision
  after a successful replacement.
- `BridgeSchemeHandlerLeaseAuthorityTests` now proves stale registration fails
  after filtered reset and after replacement advances the revision.
- `BridgeSchemeHandlerContentAuthorityTests` now proves GET body authority loss
  after response emission and HEAD authority loss after metadata lookup using
  continuation-backed gates.

Fresh proof:

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'
```

Result: exit 0, 14 tests in 2 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'
```

Result: exit 0, 85 tests in 4 suites passed.

```bash
mise run lint
```

Result: exit 0; swift-format OK, SwiftLint reported 0 violations in 1308 files,
architecture lint passed, and release script verification passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 84.55s and included
`BridgePaneControllerContentAuthorityTests`,
`BridgePaneControllerIPCProjectionTests`, real diff content fetches, and
`WebviewPaneControllerTests`.

phase_result: complete
evidence:
`2d55eef2 fix: close bridge lease proof gaps`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review fourth post-review
findings are fixed with fresh scoped proof; the Bridge trust/transport boundary
needs another review before ticket 02 begins.

## Ticket 01 Fifth Review Fifth Post-Review Follow-Up Fix

Review verdict:

- The review of `2d55eef2` / `00e68163` returned `not_ready`.
- Four lanes had no findings.
- One accepted P2 proof finding was fixed in `f892f007`.

Accepted finding addressed:

- The GET-body proof gate waited for the second emission hook with no
  stream-finished escape hatch. A regression that exited after response
  emission but before the body hook would hang until the suite timeout instead
  of failing promptly.

Implementation:

- `BridgeSchemeHandlerContentEmissionStepGate` now tracks stream completion and
  resumes pending started-emission waiters with `false`.
- The GET-body proof asserts both response and body hook reachability and exits
  promptly if the stream finishes early.

Fresh proof:

```bash
mise run format
```

Result: exit 0, Swift sources formatted.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'
```

Result: first exit 1 for a missing `return await withCheckedContinuation` in the
new bool-returning helper; final exit 0, 14 tests in 2 suites passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter \
  'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'
```

Result: exit 0, 85 tests in 4 suites passed.

```bash
mise run lint
```

Result: exit 0; swift-format OK, SwiftLint reported 0 violations in 1308 files,
architecture lint passed, and release script verification passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 86.69s and included
`BridgePaneControllerContentAuthorityTests`,
`BridgePaneControllerIPCProjectionTests`, real diff content fetches, and
`WebviewPaneControllerTests`.

phase_result: complete
evidence:
`f892f007 test: bound bridge body emission proof`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 fifth-review fifth post-review finding
is fixed with fresh scoped proof; the Bridge trust/transport boundary needs
another review before ticket 02 begins.

## Ticket 01 Final Re-Review

Review verdict:

- The review of `f892f007` / `29955968` returned `ready`.
- Proof-helper reliability lane: no findings.
- Docs/workflow-state mapping lane: no findings.
- Trust-boundary regression smoke lane: no findings.

Parent verification:

- `events.jsonl` parsed cleanly with 19 events.
- `00e68163..HEAD` production Bridge transport/runtime diff is empty.
- The changed test helper wakes pending started-emission waiters with `false`
  when the stream finishes before the requested emission count.

phase_result: complete
evidence:
`f892f007 test: bound bridge body emission proof`
`29955968 docs: record bounded bridge proof fix`
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: Ticket 01 implementation review is complete;
checkpoint 2 / ticket 02 can begin while the unrelated CommandBar title mismatch
remains tracked as a broad Swift health blocker.

## Ticket 02 In-Progress Contract Slice

Scope completed so far:

- Added generic BridgeWeb demand contracts and runtime primitives:
  `BridgeWeb/src/core/models/bridge-demand-models.ts`,
  `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts`,
  `BridgeWeb/src/core/demand/bridge-resource-executor.ts`, and
  `BridgeWeb/src/core/demand/bridge-body-registry.ts`.
- Added Review protocol schemas, Review demand policy, and Review
  materializer:
  `BridgeWeb/src/features/review/models/review-protocol-models.ts`,
  `BridgeWeb/src/features/review/demand/review-demand-policy.ts`, and
  `BridgeWeb/src/features/review/materialization/review-materializer.ts`.
- Added a descriptor-backed Review content demand adapter:
  `BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts`.
  It requires an app-owned handle-to-descriptor-ref resolver and fails closed
  with zero fetches when a descriptor ref is missing.
- Added Swift transport descriptor models and ReviewProtocol snapshot frame
  builder:
  `Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeResourceDescriptor.swift`,
  `Sources/AgentStudio/Features/Bridge/Models/ReviewProtocol/BridgeReviewProtocolFrame.swift`,
  and
  `Sources/AgentStudio/Features/Bridge/Runtime/ReviewProtocol/BridgeReviewProtocolFrameBuilder.swift`.

Important boundary decision:

- Current Review runtime still has legacy `BridgeReviewPackage` content handles.
  The new generic demand runtime does not manufacture descriptor refs from page
  or UI data. Browser demand can run only after Review frames attach accepted
  descriptors and the app-owned materializer registers them. This avoids the
  ticket 02 stop condition where generic demand would read old Review package
  resource URLs as authority.
- Review snapshot frames now support `contentDescriptors` in addition to the
  package `rootDescriptor`, because selected/visible content demand needs
  schedulable descriptor refs for individual content handles.

Proof:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-demand-models.unit.test.ts \
  src/core/demand/bridge-demand-scheduler.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/demand/bridge-resource-executor.unit.test.ts \
  src/features/review/models/review-protocol-models.unit.test.ts \
  src/features/review/materialization/review-materializer.unit.test.ts \
  src/features/review/demand/review-demand-policy.unit.test.ts \
  src/review-viewer/content/review-content-demand-loader.unit.test.ts
```

Result: exit 0, 8 files passed, 20 tests passed.

```bash
pnpm --dir BridgeWeb run fmt
pnpm --dir BridgeWeb run check
```

Result: both exit 0. `check` completed `oxlint --type-aware`,
BridgeWeb architecture check, `oxfmt --check .`, and `tsc --noEmit` with no
warnings after cleanup.

```bash
mise run format
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter BridgeReviewProtocolFrameBuilderTests
```

Result: both exit 0. Focused Swift proof passed 1 test in 1 suite after
formatting.

Completed by the following live cutover pass:

- The live `BridgeApp` selected/visible content effects are cut over to
  descriptor-backed demand and now have jsdom, browser integration, and
  dev-server proof.
- The old package and delta push paths now carry ReviewProtocol snapshot frames,
  so newly added delta handles are registered before selected demand runs.
- Browser/dev-server proof is no longer the open blocker for ticket 02.

## Ticket 02 In-Progress Live Review Stream Cutover

Scope completed in this pass:

- Swift diff package metadata pushes now attach a ReviewProtocol snapshot frame
  alongside the existing Review package metadata. The snapshot frame is built
  from host-owned package/content handles before the browser demand runtime
  becomes authoritative.
- `BridgeApp` now owns a descriptor registry plus a current
  handle-id-to-descriptor-ref map populated only from accepted Review snapshot
  frames.
- Selected and visible Review content hydration now call
  `loadReviewItemContentResourcesThroughDemand` instead of the legacy direct
  loader. Missing descriptor refs fail closed with no raw package URL fallback.
- Browser dev/test package push helpers now attach Review snapshot frames, so
  local mocks exercise the same descriptor authority shape as Swift.
- Browser dev/test delta pushes now attach Review snapshot frames for the
  resulting revision, and `BridgeApp` applies those frames only after the delta
  passes package/generation/revision validation.
- Swift `DiffPackageDeltaSlice` now mirrors the metadata slice by carrying the
  resulting revision's ReviewProtocol snapshot frame.
- Selected content unavailability is owned by selected content demand. A
  visible-lane hydration miss can no longer poison the selected canvas before
  the selected lane has a chance to load.
- Selected critical content demand now starts from a layout-timed effect, and
  CodeView reveal is deferred until after selection/command dispatch. This
  removes the failure-path delay where a synchronous reveal could hold selected
  failure materialization behind visible/scroll work.
- Demand content fetch telemetry now flows through the existing review-viewer
  telemetry adapter boundary.
- Browser benchmark URL-scope proof now recognizes the actual
  `agentstudio://resource/review/content/...` contract.

Important boundary decision:

- React selection/visibility effect aborts now gate completion into React state
  but do not directly cancel shared executor loads. Executor cancellation
  remains a scheduler/backpressure responsibility so a selected item moving out
  from under one effect does not kill an in-flight content load still useful to
  another lane.

Proof:

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-demand-models.unit.test.ts \
  src/core/demand/bridge-demand-scheduler.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/demand/bridge-resource-executor.unit.test.ts \
  src/features/review/models/review-protocol-models.unit.test.ts \
  src/features/review/materialization/review-materializer.unit.test.ts \
  src/features/review/demand/review-demand-policy.unit.test.ts \
  src/features/review/protocol/review-snapshot-frame-builder.unit.test.ts \
  src/review-viewer/content/review-content-demand-loader.unit.test.ts \
  src/review-viewer/content/visible-review-content-hydration.unit.test.tsx \
  src/app/bridge-app.integration.test.tsx
```

Result: exit 0, 11 files passed, 59 tests passed. Existing jsdom warnings
remain: ResizeManager observed-node warnings and one React `flushSync` warning
in the filter reconciliation test.

The focused suite now includes a telemetry canary asserting raw paths, prompts,
comments, comms text, handle ids, and content URLs do not leak through the
BridgeWeb telemetry adapter.

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
```

Result: exit 0, 1 browser file passed, 30 tests passed. Existing React
`flushSync` warnings still appear in two filter/chip tests.

This browser suite covers markdown selection/reveal, stale markdown worker
responses, markdown preview-to-file selection restoration, streaming append
delta, large fixture reveal, and independent scroll ownership.

```bash
pnpm --dir BridgeWeb run test:dev-server
```

Result: exit 0 for
`http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll`.
Selected content reached `ready`, worker pool was `ready`, and scroll motion
proof passed.

```bash
BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree' \
  pnpm --dir BridgeWeb run test:dev-server:worktree
```

Result: exit 0 for the exact current-worktree URL. Selected content reached
`ready` for `.github/workflows/ci.yml`; worker pool was `ready`.

```bash
pnpm --dir BridgeWeb run benchmark:viewer
```

Result: exit 0, 1 benchmark file passed, 1 test passed.

```bash
pnpm --dir BridgeWeb run test:benchmark:browser
```

Result: exit 0, 1 browser benchmark file passed, 1 test passed. Proof artifact:
`tmp/bridge-viewer-browser-benchmark/2026-06-23T08-59-28-072Z`.

Notable browser benchmark canary: `failure-content-unavailable` now reports
p95 `24.899999976158142ms` against a `1500ms` budget after selected demand moved
ahead of CodeView reveal work.

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0. `oxlint --type-aware`, BridgeWeb architecture check,
`oxfmt --check .`, and `tsc --noEmit` passed.

```bash
SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
  mise run test-fast -- --filter BridgeReviewProtocolFrameBuilderTests
```

Result: exit 0. Focused Swift proof passed 3 tests in 1 suite. The lane also
rebuilt BridgeWeb assets and wrote `tmp/bridge-web-assets/latest-app-asset-audit.json`.

```bash
pnpm --dir BridgeWeb run fmt
pnpm --dir BridgeWeb run check
mise run format
mise run lint
git diff --check
```

Result: all exit 0. `mise run lint` reported SwiftLint 0 violations,
AgentStudio architecture lint OK, and release script verification passed.

Still not complete:

- Need implementation-review-swarm before moving to Worktree/File.

## Ticket 02 Review-Fix Pass After Implementation Review

Accepted review findings fixed in this pass:

- In-flight selected content is freshness-keyed by accepted descriptor lineage,
  so stale package revisions cannot replay selected body results into newer
  Review packages.
- Transient executor pressure now queues only user-facing lanes
  (`foreground` and `active`). Low-priority `visible`, `nearby`, and
  `speculative` demand remains opportunistic and returns typed pressure instead
  of building a backlog that can block selected demand.
- Resource load failures return typed `load_failed` results instead of rejected
  promises, so selected content failure materializes through the normal failed
  state path.
- Review snapshot frames are admitted only when package id, source/query id,
  generation, and revision match the accepted Review package.
- Browser mocked-backend resource URL handling now uses the real Bridge resource
  parser, and metadata/delta push slices use distinct slice identities.
- The failure-content-unavailable benchmark no longer waits through a generic
  shadow-DOM text scan; it waits for the dedicated unavailable-state element
  while still asserting the rendered text.

Root cause of the final browser benchmark tail:

- The executor queue change originally let visible hydration build a large
  pending backlog in the same executor used by selected demand.
- The failure scenario clicked a file whose failing head handle had already
  been touched by visible hydration. Some samples therefore waited until the
  selected failure escaped the low-priority backlog, producing about 2.0s p95
  despite only 6ms mocked backend latency.
- The final contract is now: selected/open demand may queue under pressure;
  visible/nearby/speculative demand is best-effort and must not create
  long-tail interference for foreground selection.

Fresh proof after these review fixes:

```bash
pnpm --dir BridgeWeb run fmt
pnpm --dir BridgeWeb run check
```

Result: both exit 0.

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/models/bridge-demand-models.unit.test.ts \
  src/core/demand/bridge-demand-scheduler.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/demand/bridge-resource-executor.unit.test.ts \
  src/features/review/models/review-protocol-models.unit.test.ts \
  src/features/review/materialization/review-materializer.unit.test.ts \
  src/features/review/demand/review-demand-policy.unit.test.ts \
  src/features/review/protocol/review-snapshot-frame-builder.unit.test.ts \
  src/review-viewer/content/review-content-demand-loader.unit.test.ts \
  src/review-viewer/content/visible-review-content-hydration.unit.test.tsx \
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts \
  src/app/bridge-app.integration.test.tsx
```

Result: exit 0, 12 files passed, 78 tests passed. Existing jsdom
ResizeManager observed-node warnings remain non-fatal.

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
```

Result: exit 0, 1 browser file passed, 30 tests passed.

```bash
pnpm --dir BridgeWeb run test:dev-server
```

Result: exit 0 for
`http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll`.
Selected content was `ready`, worker pool was `ready`, and visible hydrated
cache count was bounded at 8.

```bash
BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree' \
  pnpm --dir BridgeWeb run test:dev-server:worktree
```

Result: exit 0 for the exact current-worktree URL. Selected content was `ready`
for `.github/workflows/ci.yml`, worker pool was `ready`, revision was `39`, and
visible hydrated cache count was bounded at 3.

```bash
pnpm --dir BridgeWeb run test:benchmark:browser
```

Result: exit 0, 1 browser benchmark file passed, 1 test passed. Proof artifact:
`tmp/bridge-viewer-browser-benchmark/2026-06-23T13-18-32-488Z`.

Notable benchmark recovery:

- `failure-content-unavailable` passed with p95 `20.2ms` against a `1500ms`
  budget.
- `large-cold-package-push` passed with p95 `247.6ms` against a `3000ms`
  budget.
- `scroll-ownership` passed with p95 `124.2ms` against a `1500ms` budget.

Vite dev-server telemetry fast loop:

- running Vite URL: `http://127.0.0.1:5173/`
- status endpoint:
  `http://127.0.0.1:5173/__bridge-dev-telemetry/status`
- status after worktree smoke: `acceptedBatchCount=248`,
  `acceptedSampleCount=441`, `failedBatchCount=0`
- VictoriaLogs marker `vite-dev-ticket02-1782220582`:
  `vite-dev-worktree-default` rows `374`,
  `vite-dev-worktree-current-worktree` rows `67`
- exact URL loaded:
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
- `bash scripts/verify-bridge-web-no-direct-otlp.sh`: exit 0
- after manual current-worktree fresh-load, scroll, and click pressure, the same
  status endpoint reported `acceptedBatchCount=4304`,
  `acceptedSampleCount=7713`, and `failedBatchCount=0` for marker
  `vite-dev-ticket02-1782220582`
- VictoriaLogs for that manual pressure window were dominated by demand/content
  work in `vite-dev-worktree-current-worktree`: `content_fetch=4061`,
  `content_queue=3204`, with only `projection_build=5`, `worker_task=11`,
  `item_update=11`, and `shiki_highlight=11`
- current telemetry can prove demand churn and content-fetch volume, but it
  does not yet carry enough virtualizer-specific fields to directly explain
  scrollbar jump: missing fields include scrollTop before/after, total content
  height, visible range, anchor item/offset, and layout reconciliation reason
- DiffsHub/Pierre source research in
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre` found two
  relevant smoothness contracts:
  - file-tree sizing is fixed-height and row-count based: app snapshots carry a
    bounded `pathCount`, tree rows use fixed `24px` item height, and the tree
    package computes total height from visible row count rather than content
    body size
  - diff/code sizing is patch-metadata based: streamed patch chunks are parsed
    into `FileDiffMetadata` with file/hunk line counts, CodeView reserves
    estimated item heights before DOM render, then sparse measurement deltas are
    reconciled with scroll anchoring
- Ticket 02 therefore has one known follow-up risk before Ticket 03 planning:
  Bridge currently proves content availability and bounded demand queues, but
  does not yet expose a DiffsHub-like virtualized-size contract or telemetry
  canary for scroll extent stability on huge worktrees

```bash
mise run test -- --filter 'BridgeReviewProtocolFrameBuilderTests|BridgeBootstrapTests'
mise run lint
```

Result: all exit 0. The Swift focused lane rebuilt BridgeWeb assets and passed
28 Swift tests across `BridgeReviewProtocolFrameBuilderTests` and
`BridgeBootstrapTests`. `mise run lint`
reported SwiftLint 0 violations, AgentStudio architecture lint OK, and release
script verification passed.

Next required action:

- Rerun `shravan-dev-workflow:implementation-review-swarm` against the current
  worktree. Ticket 02 implementation proof is refreshed, but checkpoint 2 is
  not accepted and the plan must not advance to Worktree/File until review is
  ready or accepted findings are resolved.
