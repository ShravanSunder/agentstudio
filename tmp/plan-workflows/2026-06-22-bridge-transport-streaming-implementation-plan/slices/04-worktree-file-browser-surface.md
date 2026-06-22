# 04 Worktree/File Browser Surface

## Ticket Output

Build the first browser Worktree/File Surface on the generic Bridge runtime and
the native/provider boundary from ticket 03. The surface is one app protocol
family with tree, file content, and status subcontracts.

Deliverable:

- browser Worktree/File schemas, materializer, demand policy, and state
- tree surface with bounded tree-window demand
- file content panel with open-file session state
- stale marker and manual refresh behavior
- dev-server worktree URL uses Worktree/File protocol instead of fabricated
  Review packages
- Worktree/File replacement path resolves content through registered
  descriptors/lease-backed refs, not raw resource URL text or handle ids as
  authority
- binary/oversized files render metadata-only or bounded preview

## Source References

- `worktree-file-surface-protocol.md` sections 1-14
- `spec.md` state placement and demand/backpressure sections
- `plan-review-report.md` B4, B5, I4

## Write Scope

Browser:

- `BridgeWeb/src/features/worktree-file/**`
- `BridgeWeb/src/worktree-file-surface/**`
- `BridgeWeb/src/app/**` surface routing
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- existing Review worktree dev scaffolding only as transition removal after
  replacement proof passes

Swift:

- Only narrow fixes to Worktree/File method/frame integration discovered during
  browser proof.

## Red Tests First

- Worktree snapshot registers tree/status descriptors before demand.
- Tree viewport stimulus maps demanded refs to `visible`.
- Tree expansion maps visible windows to `visible` and optional nearby windows
  to `nearby`.
- File selected maps content descriptor to `foreground`.
- Open file invalidation marks open session stale and emits no auto-fetch in
  the first implementation.
- Explicit refresh maps latest descriptor to `foreground`.
- Manual refresh commits only if freshness/source identity is still current.
- `sourceReset` drops queued and in-flight tree/file work by
  `WorktreeFileSurfaceSourceIdentity`, and no late stale completion commits.
- Hidden subtree changes mark ancestors stale without hydrating descendants.
- Binary file renders metadata-only/unavailable.
- Oversized text renders bounded non-authoritative preview or metadata-only.
- Forged, stale, cross-source, or cross-pane resource URLs/handles cannot fetch
  Worktree/File content unless they resolve through the accepted descriptor
  registry and host lease.
- Comments/comms flags and resource kinds fail closed.
- Zustand snapshots contain refs/status/facts only.
- Pierre/renderer inputs are prepared items/paths and render deltas only, never
  fetchable Bridge URLs or descriptor authority.
- Worktree/File telemetry canary excludes raw paths, source text, handles,
  capability URLs, comments, and comms while retaining allowlisted audit fields.

## Implementation Notes

1. Add Worktree/File Zod schemas and inferred types in
   `src/features/worktree-file/models/**`.
2. Add Worktree/File materializer and demand policy.
3. Add minimal Worktree/File state surface with open file sessions.
4. Add UI/runtime surface under `src/worktree-file-surface/**`.
5. Update app routing to select Review or Worktree/File by app protocol/surface.
   This extends the router introduced in ticket 02 instead of creating a second
   root app shell.
6. Replace Vite worktree dev provider Review package fabrication with
   Worktree/File protocol frames and descriptors.
7. Keep optional Review handoff as an intent only; do not make Worktree/File a
   diff engine. Full `OpenReviewComparisonIntent` implementation is deferred
   unless the owner explicitly pulls that handoff into this epic.
8. Remove raw URL/handle authority from the Worktree/File replacement path
   before declaring the ticket cut over; raw URL parsing may remain only in
   explicitly named legacy fixtures until ticket 05 deletes or quarantines them.

## Proof Gates

Worktree/File feature unit:

```bash
pnpm --dir BridgeWeb vitest run \
  src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts \
  src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts \
  src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts \
  src/features/worktree-file/state/worktree-file-state.unit.test.ts
```

Surface integration:

```bash
pnpm --dir BridgeWeb vitest run \
  src/worktree-file-surface/worktree-file-surface.integration.test.tsx \
  src/worktree-file-surface/worktree-open-file-session.integration.test.tsx
```

These suites must include source-reset stale-completion/drop behavior and
negative forged/stale/cross-identity descriptor or resource URL cases.

Dev server:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Quality:

```bash
pnpm --dir BridgeWeb run check
```

Browser proof:

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/worktree-file-surface/test-support/worktree-file-surface.browser.integration.browser.test.tsx
```

Add this suite for stale marker, no auto-fetch, explicit refresh, tree viewport,
source-reset stale-drop, raw URL/handle rejection, renderer-boundary checks,
telemetry canary, and large/binary file behavior. Do not label jsdom/unit proof
as browser proof.

## Handoff Output

- Worktree/File source identity and descriptor examples
- stale marker -> no auto-fetch -> manual refresh proof
- dev-server URL and command result
- raw URL/handle rejection and descriptor/lease-backed fetch proof
- source-reset stale-completion drop proof
- renderer-boundary proof
- telemetry canary proof for path-rich Worktree/File interactions
- binary/oversized behavior proof
- confirmation that `BridgeReviewPackage` is not the Worktree/File product
  contract
- confirmation that optional Review handoff remains deferred or proof if the
  owner explicitly adds it to this epic
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if the browser surface can only pass by continuing to parse or push a
Review package as the Worktree/File contract. Stop if stale-open-file behavior
requires silent auto-replacement. Stop if the replacement path still treats raw
resource URL text, handle id, generation, or revision as fetch authority instead
of descriptor/lease-backed identity.
