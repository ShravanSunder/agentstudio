# Ticket 03 Implementation Review Packet

Date: 2026-06-23
Mode: implementation
Goal: 2026-06-22-bridge-transport-streaming
Ticket: 03 Worktree/File native provider boundary

## Review Scope

Git range:

- base_sha: aaf42428
- head_sha: 6489c663
- diff_stat_command: `git diff --stat aaf42428..6489c663`
- diff_command: `git diff aaf42428..6489c663`
- shortstat: 22 files changed, 2449 insertions(+), 60 deletions(-)

Current checkpoint commits in scope:

- cd6ff98c Add worktree file surface contracts
- 6489c663 Add worktree file surface RPC entrypoint

Changed files:

- `BridgeWeb/src/bridge/bridge-resource-url.ts`
- `BridgeWeb/src/bridge/bridge-resource-url.unit.test.ts`
- `BridgeWeb/src/core/resources/bridge-resource-registry.unit.test.ts`
- `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/valid/transport-resource-url-corpus.json`
- `Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeResourceProtocolRegistry.swift`
- `Sources/AgentStudio/Features/Bridge/Models/WorktreeFileSurface/BridgeWorktreeFileSurfaceFrame.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgePaneController+WorktreeFileSurface.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgeWorktreeFileSourceProvider.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgeWorktreeFileSurfaceClassifier.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgeWorktreeFileSurfaceFrameBuilder.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/Methods/WorktreeFileSurfaceMethods.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerContentAuthorityTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSourceProviderTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSurfaceNativeTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSurfaceTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSurfaceTransportTests.swift`
- `Tests/BridgeContractFixtures/valid/transport-resource-url-corpus.json`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/03-worktree-file-native-provider.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl`

## Intent

Ticket 03 must create a first-class native Worktree/File application protocol
boundary without building the browser UI. The provider and Swift host mint the
source identity and descriptors. Browser selectors are only requests; they must
not become filesystem authority.

The implementation is supposed to provide:

- provider-issued Worktree/File source identity outside Review package lineage
- `worktree.snapshot`, `worktree.treeWindow`, `worktree.statusPatch`,
  `worktree.fileInvalidated`, and reset/invalidation frame contracts
- tree size facts and file virtualization facts before hydrated content bytes
- descriptor/resource kind admission for Worktree/File resources
- provider-side selector canonicalization and containment checks
- source-scrubbed diagnostics and rejection payloads
- native RPC entrypoint: `worktreeFileSurface.openSourceStream`
- compatibility with old Review-shaped browse/open-file routes until Ticket 04

## Constraints

- Generic Bridge transport must not learn app-specific Review or Worktree/File
  authority.
- Browser code may request a source but may not mint source identity,
  descriptor leases, resource URLs, or filesystem authority.
- Large data must remain out of Zustand and out of generic RPC payloads.
- Resource URLs are opaque capabilities backed by native lease validation.
- Provider and scheme-handler errors crossing to browser-visible surfaces must
  be source-scrubbed.
- Comments/comms flags and resource kinds remain reserved-disabled/fail-closed.
- Do not remove ReviewFoundation browse/open-file transition paths in Ticket 03.
- Do not move Ticket 04 browser surface work into this ticket.

Security context: applicable

- Changed attack surface: native RPC opens a Worktree/File source and registers
  descriptor leases that authorize later `agentstudio://resource/...` fetches.
- Untrusted inputs: browser-supplied source selectors, root/worktree IDs,
  path/cwd scopes, path hints, resource URLs, and stale generations.
- Trust boundary: page/browser request -> content-world bridge/RPC -> Swift host
  provider -> lease registry -> native scheme handler.
- Sensitive data: local filesystem paths and file content. Raw paths, cwd
  scopes, handle IDs, capability URLs, source text, comments, comms, prompts,
  and unsanitized provider error text must not be exported to browser-visible
  errors or telemetry.
- Forbidden broadening: no filesystem, network, subprocess, package-script, CI,
  MCP, plugin, agent, external-model, auth, or secret-boundary broadening beyond
  the reviewed scope.

## Source Of Truth Inputs

- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
  - Requirements/proof matrix and advancement gate for Ticket 03.
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/03-worktree-file-native-provider.md`
  - Ticket output, red tests, proof gates, and handoff requirements.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
  - Worktree/File protocol model and proof expectations.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
  - Transport/security/scheduler/telemetry constraints.
- `git diff aaf42428..6489c663`
  - Actual implementation under review.

## Claimed Implementation Proof

Fresh proof captured during Ticket 03 execution:

- Red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceNativeTests`
  failed before classifier implementation because classifier/status contracts did
  not exist.
- Red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTests`
  failed before tree-window implementation because tree-window contracts did not
  exist.
- Red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTransportTests`
  failed because `worktreeFileSurface.openSourceStream` returned no JSON-RPC
  `result`.
- Green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceNativeTests`
  exited 0 with 4 tests in 1 suite passing.
- Green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTests`
  exited 0 with 10 tests in 1 suite passing.
- Green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTransportTests`
  exited 0 with 1 selected test passing.
- Focused gate:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceNativeTests|BridgeWorktreeFileSurfaceTransportTests|BridgeReviewPipelineTests|BridgeSchemeHandlerTests|BridgeTransportIntegrationTests'`
  exited 0 with 83 selected tests in 6 suites passing.
- Quality:
  `mise run lint` exited 0.
- Browser quality:
  `pnpm --dir BridgeWeb run check` exited 0.
- Fixture sync:
  `bash scripts/bridge-web-sync-fixtures.sh --check` exited 0 with 17 files in
  sync.
- Diff hygiene:
  `git diff --check aaf42428..6489c663` exited 0.

Known split proof caveat:

- The nested WebKit full-suite filter
  `AgentStudioTests.WebKitSerializedTests/BridgeTransportIntegrationTests`
  previously exited with signal 5 after several tests passed. This was carried
  from Ticket 02 and is not claimed as fixed by Ticket 03.

## Review Focus

Default lanes should focus on:

- spec compliance for Ticket 03 vs actual diff
- implementation proof mapping and proof gaps
- security/trust boundary for selector containment, source identity, resource
  URLs, descriptor leases, and scrubbed errors
- reliability/performance for large worktrees, off-main scanning, generations,
  stale completions, cancellation, and lease lifecycle
- contracts/tests for Swift/TS resource grammar parity and early size/extent
  facts
- adversarial design: whether Ticket 03 has a clean enough provider boundary to
  unblock Ticket 04 without carrying Review lineage or browser authority

## Non-Goals

- Do not review all Ticket 02 changes unless they are needed to understand a
  Ticket 03 regression.
- Do not ask for Ticket 04 browser UI implementation in this review.
- Do not require HMAC/encryption for internal app frames; user accepted the
  closed Swift-app boundary for this issue.
- Do not edit files. Parent reducer will verify and route findings.

## Output Contract

Return candidate findings only. Each finding must include:

- severity: blocker | important | follow-up | nit
- title
- evidence: exact file:line, symbol, command output, or plan section
- scenario: concrete failure, exploit, regression, or maintenance path
- smallest_fix
- proof: test, check, or manual reproduction that would prove the fix
- confidence: high | medium | low

If there are no findings, say `No findings.` and still return lane-level
confidence, remaining uncertainty, and completion receipt.
