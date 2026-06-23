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

- ticket 01: core transport contracts and security boundary

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
