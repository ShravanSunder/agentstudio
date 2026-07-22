# Proposed File Organization

Date: 2026-06-22

This is the proposed ownership map for the revised plan. Exact filenames can
shift during implementation, but the boundaries should not.

## Browser / BridgeWeb

Current pattern:

- Generic browser bridge transport is under `BridgeWeb/src/bridge`.
- Review data contracts are under `BridgeWeb/src/foundation/review-package`.
- Review UI/runtime is under `BridgeWeb/src/review-viewer`.
- App bootstrapping is under `BridgeWeb/src/app`.

Proposed additions:

```text
BridgeWeb/src/
  core/
    models/                       common schemas/types shared by features
      bridge-descriptor-ref-schema.ts
      bridge-resource-descriptor-schema.ts
      bridge-attached-resource-descriptor-schema.ts
      bridge-integrity-descriptor-schema.ts
      bridge-intake-frame-schema.ts
      bridge-intake-stream-identity-schema.ts
      bridge-demand-intent-schema.ts
      bridge-demand-lane-schema.ts
      bridge-resource-url-schema.ts
      bridge-core-models.unit.test.ts

    intake/
      bridge-intake-carrier.ts
      bridge-intake-carrier.unit.test.ts
      bridge-intake-receiver.ts
      bridge-intake-receiver.unit.test.ts

    resources/
      bridge-resource-registry.ts
      bridge-resource-registry.unit.test.ts
      bridge-resource-url.ts                 # update existing parser
      bridge-resource-url.unit.test.ts       # extend existing tests
      bridge-integrity.ts
      bridge-integrity.unit.test.ts

    demand/
      bridge-demand-stimulus-contract.ts
      bridge-demand-scheduler.ts
      bridge-demand-scheduler.unit.test.ts
      bridge-resource-executor.ts
      bridge-resource-executor.unit.test.ts
      bridge-body-registry.ts
      bridge-body-registry.unit.test.ts

    bridge-host/                  browser host integration / compatibility
      bridge-content-world-rpc.ts
      bridge-content-world-rpc.integration.test.ts
      bridge-rpc-client.ts                   # update existing client
      bridge-rpc-client.unit.test.ts         # extend existing tests
      bridge-page-handshake.ts               # update existing handshake
      bridge-push-receiver.ts                # migrate or delegate to core/intake
      bridge-host-boundary.md                # documents content-world/page-world rule

  features/
    review/
      models/
        review-intake-frame-schema.ts
        review-demand-stimulus-schema.ts
        review-changeset-cluster-schema.ts
        review-protocol-models.unit.test.ts
      materialization/
        review-materializer.ts
        review-materializer.unit.test.ts
      demand/
        review-demand-policy.ts
        review-demand-policy.unit.test.ts
      fixtures/
        review-protocol-fixtures.ts
        review-protocol-fixtures.unit.test.ts

    worktree-file/
      models/
        worktree-file-intake-frame-schema.ts
        worktree-file-descriptor-schema.ts
        worktree-file-demand-stimulus-schema.ts
        worktree-file-source-identity-schema.ts
        worktree-file-protocol-models.unit.test.ts
      materialization/
        worktree-file-materializer.ts
        worktree-file-materializer.unit.test.ts
      demand/
        worktree-file-demand-policy.ts
        worktree-file-demand-policy.unit.test.ts
      state/
        worktree-file-state.ts
        worktree-file-state.unit.test.ts

  review-viewer/
    content/
      review-content-loader.ts               # adapt to demand executor
      visible-review-content-hydration.ts    # adapt to demand executor
    projections/
      use-review-projection-coordinator.ts   # keep Review-specific
    code-view/
      bridge-code-view-*                     # only touch for proven identity issue
    trees/
      bridge-trees-*                         # only touch for proven identity issue

  worktree-file-surface/
    worktree-file-app.tsx
    worktree-file-surface.tsx
    worktree-file-tree-panel.tsx
    worktree-file-content-panel.tsx
    worktree-file-stale-refresh.ts
    worktree-file-surface.integration.test.tsx

  app/
    bridge-app-protocol-router.tsx           # ticket 02 introduces first router
    bridge-app-bootstrap.tsx                 # update to route by app protocol/surface
    bridge-app.tsx                           # shrink Review-specific intake
    bridge-app-dev-worktree.ts               # replace Review-package scaffolding in ticket 04
```

Boundary rules:

- `src/core/**` is generic shared contract/runtime. It mirrors the Swift
  `Models/Transport` and generic transport/runtime split.
- `src/core/models/**` owns common Zod schemas and inferred TypeScript types used
  by more than one protocol.
- `src/core/bridge-host/**` is browser host integration and compatibility glue.
  It can adapt existing browser events/RPC into `src/core/**`, but it should not
  own durable protocol models.
- Existing `src/bridge/**` files are legacy homes during cutover. New files land
  in `src/core/**`; cleanup either moves those files or makes them thin
  compatibility wrappers.
- `src/core/**` must not import `review-viewer`,
  `foundation/review-package`, `features/review`, or
  `features/worktree-file`.
- `models/*schema.ts` files colocate Zod schemas and their inferred TypeScript
  types. Do not create parallel manual interfaces for schema-shaped data.
- Zod-derived types use `z.infer<typeof SomeSchema>` and schema transforms use
  `.pick()` / `.omit()` / `.extend()` instead of handwritten duplicate types.
- Runtime modules import model types/schemas from their local vertical slice
  first, then from shared `src/core/models/**` contracts.
- `src/features/review/**` owns Review schemas, materializer, and demand policy.
  It may adapt old Review package fixtures during the transition, but generic
  Bridge must not know those shapes.
- `src/features/worktree-file/**` owns Worktree/File schemas, materializer, and
  demand policy.
- `src/review-viewer/**` and `src/worktree-file-surface/**` are UI/runtime
  surfaces. They consume protocol materialized state and renderer adapters.
- Large bodies, promises, abort controllers, and Pierre instances stay outside
  Zustand. Zustand stores refs/status/facts only.

## Browser Test Placement

```text
BridgeWeb/src/core/models/*unit.test.ts
  shared schema validation and cross-protocol model invariants

BridgeWeb/src/core/intake/*unit.test.ts
  stream frame ordering, duplicate/missing/out-of-order, reset, cancel

BridgeWeb/src/core/resources/*unit.test.ts
  descriptor refs, URL grammar, lease authority, integrity

BridgeWeb/src/core/demand/*unit.test.ts
  lane ordering, dedupe, caps, abort, stale completion drop

BridgeWeb/src/core/bridge-host/*integration.test.ts
  page-world cannot call privileged RPC; content-world path works

BridgeWeb/src/features/review/models/*unit.test.ts
  Review frames, materializer, demand policy, descriptor handoff

BridgeWeb/src/features/worktree-file/models/*unit.test.ts
  Worktree frames, stale-open-file state, manual refresh demand

BridgeWeb/src/review-viewer/test-support/*browser.test.tsx
  Review app/browser proof and CodeView/Tree identity proof

BridgeWeb/src/worktree-file-surface/*integration.test.tsx
  Worktree/File surface boot, stale marker, manual refresh

BridgeWeb/scripts/dev-server/*
  Vite/dev-server providers and smoke verifiers
```

## Swift / AgentStudio

Current pattern:

- Generic transport lives under `Sources/AgentStudio/Features/Bridge/Transport`.
- Generic runtime/controller code lives under `Sources/AgentStudio/Features/Bridge/Runtime`.
- Review host/provider code lives under
  `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation`.
- Review model contracts live under
  `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation`.

Proposed additions:

```text
Sources/AgentStudio/Features/Bridge/
  Models/
    Transport/
      BridgeDescriptorRef.swift
      BridgeResourceDescriptor.swift
      BridgeAttachedResourceDescriptor.swift
      BridgeIntegrityDescriptor.swift
      BridgeIntakeFrame.swift
      BridgeStreamIdentity.swift

    ReviewProtocol/
      BridgeReviewSnapshotFrame.swift
      BridgeReviewDeltaFrame.swift
      BridgeReviewInvalidationFrame.swift
      BridgeReviewResetFrame.swift
      BridgeReviewProtocolFixtures.swift

    WorktreeFileSurface/
      BridgeWorktreeSnapshotFrame.swift
      BridgeWorktreeFileDescriptor.swift
      BridgeWorktreeStatusDescriptor.swift
      BridgeWorktreeSourceIdentity.swift
      BridgeWorktreeInvalidationFrame.swift

  Transport/
    BridgeBootstrap.swift                    # content-world RPC boundary work
    BridgeSchemeHandler.swift                # protocol-scoped resource URLs
    BridgeResourceLeaseValidator.swift
    Methods/
      BridgeProtocolMethodRegistry.swift      # registry glue only; no app semantics

  Runtime/
    BridgePaneController+PushTransport.swift # selected intake-carrier proof
    BridgePushEnvelopeEncoder.swift          # intake-frame metadata until renamed
    BridgeIntakeStreamCoordinator.swift
    BridgeResourceStore.swift                # generic descriptor/resource serving

    ReviewProtocol/
      BridgeReviewProtocolSourceProvider.swift
      BridgeReviewProtocolFrameBuilder.swift
      BridgeReviewProtocolMaterialization.swift
      BridgeReviewProtocolMethods.swift

    WorktreeFileSurface/
      BridgeWorktreeFileSourceProvider.swift
      BridgeWorktreeFileWatcher.swift
      BridgeWorktreeFileFrameBuilder.swift
      BridgeWorktreeFileContentStore.swift
      BridgeWorktreeFileSurfaceMethods.swift
```

Boundary rules:

- `Models/Transport` and `Transport` are generic Bridge. No Review or
  Worktree/File app nouns except registered protocol ids and registry-only
  method glue.
- App-specific method implementation lives under the app runtime folders
  (`Runtime/ReviewProtocol/**` and `Runtime/WorktreeFileSurface/**`), not under
  generic `Transport/**`.
- `Runtime/ReviewProtocol` owns comparison/review provider behavior.
- `Runtime/WorktreeFileSurface` owns live worktree source identity, watchers,
  status classification, file descriptors, invalidations, content handles, and
  source reset decisions.
- Existing `ReviewFoundation` stays as transition source until the Review
  protocol vertical cuts over. Cleanup moves or deletes it only when the
  replacement proof passes.

## Swift Test Placement

```text
Tests/AgentStudioTests/Features/Bridge/
  BridgeBootstrapTests.swift
    content-world RPC boundary and page-world rejection

  BridgeSchemeHandlerTests.swift
    protocol-scoped resource URL, lease rejection, cross-pane rejection

  BridgeTransportIntegrationTests.swift
    intake frame encode/deliver/gap/reset behavior

  BridgeWebKitSpikeTests.swift
    real WKWebView carrier proof under burst/cancel/reset/stale-close

  Runtime/BridgePushEnvelopeEncoderTests.swift
    intake frame metadata redaction and parser parity

  BridgeReviewProtocolTests.swift
    Review frame parity, descriptor attachment, source reset

  BridgeWorktreeFileSurfaceTests.swift
    source identity, invalidation, manual-refresh provider behavior

  BridgeWorktreeFileSourceProviderTests.swift
    provider-issued identity, descriptors, watcher/status classification

  BridgeWorktreeFileSurfaceNativeTests.swift
    source identity, invalidation, manual-refresh provider behavior

  BridgeTelemetryBatchValidatorTests.swift
    telemetry canaries and allowlist behavior
```

## Ticket-To-Folder Map

```text
00 intake carrier proof
  Browser: BridgeWeb/src/core/models
           BridgeWeb/src/core/intake
           BridgeWeb/src/core/bridge-host compatibility adapters
  Swift:   Runtime/BridgePaneController+PushTransport.swift
           Runtime/BridgePushEnvelopeEncoder.swift
           Tests/.../BridgeWebKitSpikeTests.swift

01 transport contracts
  Browser: BridgeWeb/src/core/models
           BridgeWeb/src/core/resources
           BridgeWeb/src/core/bridge-host
  Swift:   Models/Transport
           Transport/BridgeSchemeHandler.swift
           Transport/BridgeBootstrap.swift

02 Review protocol vertical with descriptor-backed demand
  Browser: BridgeWeb/src/core/models
           BridgeWeb/src/core/demand
           BridgeWeb/src/core/resources
           BridgeWeb/src/features/review
           BridgeWeb/src/features/review/models
           BridgeWeb/src/review-viewer adapters
           BridgeWeb/src/app protocol router
  Swift:   Models/ReviewProtocol
           Runtime/ReviewProtocol

03 Worktree/File native provider boundary
  Swift:   Models/WorktreeFileSurface
           Runtime/WorktreeFileSurface
           transition edits to existing ReviewFoundation browse/open-file seams:
           Models/ReviewFoundation/BridgeReviewQuery.swift
           Runtime/ReviewFoundation/BridgeReviewPipeline.swift

04 Worktree/File browser surface
  Browser: BridgeWeb/src/features/worktree-file
           BridgeWeb/src/features/worktree-file/models
           BridgeWeb/src/worktree-file-surface
           BridgeWeb/src/app surface routing
           BridgeWeb/src/app/bridge-app-dev-worktree.ts replacement path

05 hard-cutover cleanup
  Browser: remove old Review package push-only paths and dev scaffolding
  Swift:   retire superseded ReviewFoundation paths after proof
```

Former standalone demand-runtime ticket:

```text
The earlier standalone `02 descriptor-backed demand runtime` ticket is merged
into the Review vertical. Demand runtime may create generic `core/demand`
modules, but it is proven through Review after Review frames attach descriptors.
This prevents generic demand code from learning old Review package/resource URL
authority.
```

App router ownership:

```text
Ticket 02 introduces the first protocol router around the current Review-only
BridgeApp root. Ticket 04 extends that router for Worktree/File instead of
creating a second root shell. This keeps app routing a shared app concern while
keeping protocol materialization under `features/review/**` and
`features/worktree-file/**`.
```

## Resolved Placement Decisions For Execution

- Whether to introduce `BridgeWeb/src/core/**` immediately, or keep common
  shared contracts under `BridgeWeb/src/bridge/**`. Decision: use
  `BridgeWeb/src/core/**` for common models/runtime, matching the Swift
  `Core/Models` mental model. New browser-host wiring goes under
  `BridgeWeb/src/core/bridge-host/**`; existing `BridgeWeb/src/bridge/**` is
  legacy compatibility during cutover, not the target home.
- Whether to introduce `BridgeWeb/src/features/**` immediately, or first place
  Review protocol under `foundation/review-protocol`. Decision:
  `src/features/**`, because these are product/app features, not generic core.
- Whether Swift generic transport models should be `Models/Transport` or
  `Models/BridgeProtocol`. Recommendation: `Models/Transport`, matching the
  existing `Transport` folder and keeping app protocol models separate.
- Whether the existing `BridgePushEnvelopeEncoder` should be renamed in slice 00.
  Recommendation: avoid rename in slice 00 unless the carrier proof changes the
  abstraction; keep mechanical renames for cleanup.
