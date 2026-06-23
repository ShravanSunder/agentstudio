# 05 Hard-Cutover Cleanup Ticket

## Ticket Output

Remove old mixed transport and Review-only authority paths after tickets 00-04
have proven replacements. This ticket is valid only after the prior gates pass.

Deliverable:

- no generic Bridge module imports Review or Worktree/File app modules
- no app protocol fetches by raw descriptor string or raw resource URL authority
- legacy Review-package Worktree/File scaffolding removed or explicitly kept as
  a named test fixture outside the product path
- comments/comms disabled/fail-closed behavior remains proven
- telemetry canaries and full regression gates pass

## Source References

- `spec.md` R1-R8
- `spec.md` state placement
- `spec.md` security and telemetry invariants
- `plan-review-report.md` I3 and final checklist

## Write Scope

Browser:

- stale compatibility files under `BridgeWeb/src/bridge/**`
- old Review package adapters under `BridgeWeb/src/foundation/review-package/**`
  only when no longer used by product paths
- `BridgeWeb/src/app/**` legacy dev scaffolding
- architecture checks and docs/handoff artifacts

Swift:

- superseded `ReviewFoundation` paths only after Review and Worktree/File
  replacements prove equivalent or better coverage
- architecture tests and focused cleanup tests

Do not delete proof scaffolding that is still required by a final gate.

## Red Tests First

- Generic `src/core/**` cannot import `features/review`,
  `features/worktree-file`, `review-viewer`, or `foundation/review-package`.
- Generic Swift transport models/runtime cannot import app protocol runtime.
- No app protocol can fetch by raw descriptor string.
- No Zustand snapshot contains body text, promises, controllers, worker handles,
  or Pierre instances.
- Comments/comms resource kinds and flags stay rejected/disabled.
- Telemetry canary rejects raw paths, source text, prompts, capability URLs,
  comments, comms, and handles.
- Worktree dev route no longer depends on Review package fabrication.

## Implementation Notes

1. Remove dead compatibility adapters after their replacements pass.
2. Tighten architecture checks for browser import boundaries.
3. Retire superseded ReviewFoundation code only when both Review and
   Worktree/File product paths no longer use it.
4. Update handoff docs with the final boundary and remaining follow-ups.
5. Preserve fixture-only code under explicit fixture names if a test still needs
   legacy data shape.

## Proof Gates

Quality:

```bash
pnpm --dir BridgeWeb run check
mise run lint
```

Unit/integration:

```bash
pnpm --dir BridgeWeb run test
mise run test
```

Browser/dev-server:

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/worktree-file-surface/test-support/worktree-file-surface.browser.integration.browser.test.tsx
pnpm --dir BridgeWeb run test:dev-server
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Benchmark/browser pressure:

```bash
pnpm --dir BridgeWeb run benchmark:viewer
pnpm --dir BridgeWeb run test:benchmark:browser
```

Telemetry/canary:

- run the focused Bridge telemetry validator/canary suite added by tickets 02
  and 05
- record seed strings and exported safe fields in the handoff

Fixture sync:

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Benchmark/pressure:

- rerun targeted browser or push benchmark scenarios if tickets 00, 02, or 04
  changed carrier pressure, queue ceilings, viewport churn, invalidation storms,
  foreground preemption, tree extent reservation, or open-file extent
  reconciliation.

## Handoff Output

- removed compatibility paths
- architecture/import proof
- full final gate results with exit codes
- telemetry canary proof
- remaining risks and explicit follow-up tickets
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if cleanup requires keeping old and new fetch authority paths alive inside
the same app protocol. That is a design contradiction, not a cleanup task.
