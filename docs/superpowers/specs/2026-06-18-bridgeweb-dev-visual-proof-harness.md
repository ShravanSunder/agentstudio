# BridgeWeb Dev Visual Proof Harness

Date: 2026-06-18

Status: draft spec amendment for `2026-06-16-bridge-viewer-diffshub-polish`

## Purpose

Bridge viewer development needs a fast visual loop that can be inspected in a
normal browser while preserving the stronger proof pyramid for packaged and
native AgentStudio behavior.

The dev server is a new proof lane. It is not a replacement for Browser Mode
tests, packaged asset audits, WKWebView integration, or native visual proof.

## Current Evidence

Current BridgeWeb already has:

- `BridgeWeb/index.html`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/src/app/bridge-app-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts`
- `BridgeWeb/vitest.config.ts`
- `BridgeWeb/vitest.browser.config.ts`
- `BridgeWeb/vitest.benchmark.config.ts`

Current scripts include:

- `test`
- `test:browser`
- `test:browser:integration`
- `test:benchmark:browser`
- `benchmark:viewer`
- `build`
- `check`
- `fmt:check`
- `lint:types`
- `typecheck`

Current test naming mostly follows the requested convention:

- node unit tests use `.unit.test.ts` or `.unit.test.tsx`
- node integration tests use `.integration.test.ts` or `.integration.test.tsx`
- the node config includes `.e2e.test.ts` and `.e2e.test.tsx`
- browser integration tests use `.browser.test.tsx`
- browser performance tests use `.browser.benchmark.tsx`
- node deterministic benchmark tests use `.benchmark.ts`

No separate `.e2e` BridgeWeb file exists in the current proof slice. That is
acceptable until there is a real end-to-end BridgeWeb surface that crosses a
full external boundary beyond the current mocked Bridge backend.

## Proof Pyramid

```text
Unit
  zod schemas, Zustand actions, materialization, sanitizer, worker clients
        |
        v
Node integration
  content loader, projection coordinator, transport seams, mocked backend
        |
        v
Vitest Browser Mode
  Chromium DOM, scroll ownership, workers, Pierre CodeView/FileTree behavior
        |
        v
Dev visual harness
  Vite-served BridgeApp with selectable mocked backend scenarios for fast
  human and Browser-plugin inspection
        |
        v
Packaged BridgeWeb build
  generated JS/CSS/workers/asset manifest and dependency audit
        |
        v
AgentStudio debug WKWebView
  native pane runtime, packaged assets, custom scheme, app chrome
        |
        v
Observability/performance
  Victoria/OTLP and durable benchmark artifacts for runtime behavior
```

## Dev Harness Boundary

The dev visual harness proves:

- visual layout and density
- right-side file rail behavior
- CodeView/FileTree rendering in a browser
- scroll ownership in a browser
- markdown preview rendering in a browser
- mocked Bridge package, delta, content, command, projection, and latency paths
- browser console and runtime errors during interactive development

The dev visual harness does not prove:

- WKWebView behavior
- app pane lifecycle
- `agentstudio://resource/content/...` custom scheme handling
- native Bridge push transport
- packaged worker asset resolution
- generated asset manifest correctness
- native app visual capture
- Victoria/OTLP runtime proof

## Architecture

The harness should reuse `BridgeApp` rather than fork a separate viewer.

```text
Vite dev server
  serves BridgeWeb/index.html
        |
        v
dev harness bootstrap
  parses scenario query params
  creates BridgeViewerMockedBackend
  passes target/fetchContent/workers into BridgeApp
        |
        v
BridgeApp
  same React viewer and same Zustand/runtime paths
        |
        +-------------------------+
        |                         |
        v                         v
mocked Bridge backend        real browser/Pierre UI
  package/delta/content      CodeView/FileTree/markdown
  command/projection ledgers
```

The dev harness may add a small development-only bootstrap module, but it must
not add product-only branches inside `BridgeApp` for test scenarios. The clean
shape is dependency injection at the existing `BridgeAppProps` boundary.

## Scenario Selection

The dev server should support deterministic scenario selection through URL
query params or an equivalent typed dev-only config:

```text
fixture=small-mixed | medium-agentstudio | large-diffshub
latency=zero | small | slowBounded
delivery=full-load | streaming-append
workers=on | off
scenario=default | markdown | stale | failure | scroll
```

Default scenario:

```text
fixture=medium-agentstudio
latency=zero
delivery=full-load
workers=on
scenario=default
```

The dev UI may expose compact non-product controls for scenario switching only
if they are clearly outside the product viewer surface. Product UI screenshots
should be captured with those controls hidden or outside the target frame.

## File And Config Conventions

Preserve the current naming grammar:

- pure unit: `*.unit.test.ts` / `*.unit.test.tsx`
- node integration: `*.integration.test.ts` / `*.integration.test.tsx`
- true end-to-end: `*.e2e.test.ts` / `*.e2e.test.tsx`
- browser integration: `*.browser.test.ts` / `*.browser.test.tsx`
- browser performance: `*.browser.benchmark.ts` / `*.browser.benchmark.tsx`
- node deterministic benchmark: `*.benchmark.ts`

Dev harness files should be named by responsibility, for example:

- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app-dev-scenarios.ts`
- `BridgeWeb/src/app/bridge-app-dev-scenarios.unit.test.ts`
- `BridgeWeb/src/app/bridge-app-dev-harness.browser.test.tsx`

Do not introduce untyped `.mjs` or ad hoc JavaScript scripts. Use TypeScript and
the existing Node 24 `--experimental-strip-types` runner where a script is
needed.

## Scripts

Add a dev script only after plan review accepts this spec:

```text
pnpm --dir BridgeWeb run dev
```

Optional scoped scripts may be added if the implementation plan needs them:

```text
pnpm --dir BridgeWeb run dev:bridge
pnpm --dir BridgeWeb run preview:bridge
```

Keep test proof separate from dev server convenience:

- `test:browser` remains automated Chromium behavior proof
- `test:benchmark:browser` remains automated browser performance proof
- `dev` is for fast human/agent inspection

## Security And Trust Boundary

The dev harness touches local HTTP serving, repository fixture content,
markdown rendering, worker loading, and mocked Bridge RPC commands.

Security constraints:

- bind the dev server to loopback only
- do not expose real workspace filesystem content by default
- use deterministic test fixtures unless a future plan explicitly adds local
  fixture import
- keep markdown sanitized exactly as product preview does
- do not allow arbitrary `agentstudio://`, `file:`, `data:`, or remote image
  loading through dev scenario params
- do not weaken the asset audit, worker audit, or content-resource parser
- keep dev-only scenario params out of shipped native app behavior

## Validation Strategy

The implementation plan should add proof for:

- dev script starts Vite on loopback
- dev bootstrap mounts `BridgeApp`
- scenario query params select deterministic mocked backend fixtures
- default scenario renders a nonblank review viewer
- `large-diffshub` scenario renders enough rows for scroll inspection
- markdown scenario renders sanitized preview
- failure scenario renders typed unavailable/error UI
- workers-on scenario exercises worker-backed CodeView where browser supports it
- Browser-plugin or Playwright screenshot can capture the dev server view

Minimum proof commands after implementation:

```bash
pnpm --dir BridgeWeb run typecheck
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run test:browser
pnpm --dir BridgeWeb run test:benchmark:browser
pnpm --dir BridgeWeb run build
pnpm --dir BridgeWeb run check
```

The dev server proof should include a captured browser screenshot or Browser
plugin screenshot of at least:

- default viewer
- filter/search state
- large fixture scrolled CodeView
- right rail scrolled independently
- markdown preview

Native debug visual proof remains required unless the user explicitly approves a
manual screenshot or dev-server screenshot as a temporary substitute for the
blocked Peekaboo capture context.

## Alternatives Considered

### Plan Patch Only

Add `dev` as one more task in the existing plan.

Gain:

- fastest paper change
- less ceremony

Cost:

- too easy for future execution to treat dev server proof as equivalent to
  native proof
- proof-pyramid boundary stays implicit

### Separate Goal

Create a new goal for BridgeWeb dev harness.

Gain:

- clear tracking if this becomes a standalone PR

Cost:

- splits the current Bridge viewer proof story
- likely duplicates the same fixtures and proof matrix

### Spec Amendment Inside Current Goal

Add this spec, review it, then update the implementation plan.

Gain:

- keeps the proof pyramid explicit
- keeps the current Bridge viewer goal intact
- gives plan-create a precise source of truth

Cost:

- one extra review step before code

Decision: use spec amendment inside the current Bridge viewer goal.

## Goal And Workflow Decision

Do not recreate the workflow skill.

The blocked goal state was correct for the previous terminal condition because
native visual proof could not be collected. This spec amendment changes the
proof design by adding a dev visual harness lane; it does not erase the existing
goal history.

Recommended workflow:

```text
spec-design-swarm
  current spec amendment
        |
        v
spec-review-swarm
  adversarially review proof boundaries
        |
        v
plan-create
  update the existing implementation plan and proof matrix
        |
        v
implementation-execute-plan
  add the dev harness and tests
        |
        v
implementation-review-swarm
  review implementation and proof chain
        |
        v
implementation-pr-wrapup
  only after proof gates are satisfied or explicitly substituted
```

If the host goal tracker cannot resume a blocked goal cleanly, create a follow-on
goal with the same `goal_id` context and this spec as required reading. Do not
change the terminal condition silently.

## Open Questions

1. Should a manual human screenshot be accepted as a temporary native visual
   substitute while Peekaboo is blocked by the host capture context?
2. Should the dev harness UI expose visible scenario controls, or should
   scenarios be query-param only so screenshots stay product-clean?
