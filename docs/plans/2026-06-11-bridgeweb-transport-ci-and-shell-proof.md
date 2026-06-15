# BridgeWeb Transport, CI Lane, Fixture Sync, And Minimal Shell Proof

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The BridgeWeb scaffold is high quality where it exists (strict TS, exact
contract parity with Swift, compliant naming, 9 test files / 10 tests green,
`pnpm run check` exit 0 — verified by parent run on 2026-06-11), but four gaps
keep it an island:

1. **No wire transport.** There is no push receiver, no RPC client, and the
   page handshake does not consume the `pushNonce` Swift sends — BridgeWeb
   cannot yet receive a package envelope or send a command. Master plan Task 9
   (minimal review shell proof) is entirely unchecked and blocked on this.
2. **CI never runs BridgeWeb.** `.github/workflows/ci.yml` has zero
   bridge-web steps (verified), while `.mise.toml` already defines
   `bridge-web-check` / `bridge-web-test` / `bridge-web-build`. TypeScript
   breakage will not fail any build today.
3. **Contract fixtures will drift.** BridgeWeb carries 5 of Swift's 16
   `BridgeContractFixtures` as manual copies with no sync task; Swift is the
   source of truth and nothing enforces parity.
4. **Shell proof undone.** `review-viewer-shell.tsx` renders an item list
   only; no package summary, endpoint labels, filters, or content fetch
   (Task 9 checklist all unchecked).

## Current Evidence

- `grep -n "bridge-web\|BridgeWeb" .github/workflows/ci.yml` → no matches
  (verified by parent). `.mise.toml` defines the three tasks (build outputs to
  `Sources/AgentStudio/Resources/BridgeWeb/app`).
- `BridgeWeb/src/bridge/` contains only `bridge-page-handshake.ts` and
  `bridge-resource-url.ts`; no push-envelope/push-receiver/rpc-client modules
  (audit lane + parent directory listing).
- `bridge-page-handshake.ts` re-emits `__bridge_ready` but does not extract or
  retain the `pushNonce` that Swift's `BridgeBootstrap.generateScript` injects
  into the handshake detail
  (`Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift:109-121`).
- Fixture counts: `Tests/BridgeContractFixtures/` 16 files vs
  `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/` 5 files; shared five
  are content-identical today, formatting aside (audit lane diff).
- Master plan Task 9: `docs/plans/2026-06-08-bridge-agent-review-foundation.md:967-972`
  — all items unchecked.
- Baseline: `pnpm run check` exit 0; `pnpm run test` exit 0 (9 files,
  10 tests) — parent-run 2026-06-11.

## Non-Goals

- No Pierre/Shiki/Trees dependencies (LUNA-338).
- No state-management framework in BridgeWeb; the item registry stays a small
  module per the spec ("This foundation does not add a new Bridge atom").
- No Swift-side method/protocol changes beyond what the production-wiring plan
  already owns; this plan consumes the wire contract documented in
  `docs/architecture/swift_react_bridge_design.md` §5 and §7.
- Annotation, review-state mutation, and editing remain out (read-only pane).

## Scope

Write surfaces:
- `BridgeWeb/src/bridge/` — new `bridge-push-envelope.ts`,
  `bridge-push-receiver.ts`, `bridge-rpc-client.ts`; extend
  `bridge-page-handshake.ts` to retain `pushNonce` and validate it on push
  events (defense-in-depth per spec).
- `BridgeWeb/src/foundation/review-package/` — small item-registry module
  (package + delta application + selection/visibility priority facts).
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` — Task 9 proof:
  summary, endpoint labels, checkpoint/collation label, filtered list,
  selected-file content fetch via handle URL.
- `.github/workflows/ci.yml` — bridge-web check/test/build steps.
- `.mise.toml` — `bridge-web-sync-fixtures` task (copy + verify from
  `Tests/BridgeContractFixtures`), wired into `bridge-web-check`.

Read-only context:
- `docs/architecture/swift_react_bridge_design.md` §5.4 (push format), §5.1
  (JSON-RPC commands), §7.2-7.4 (receiver/sender/RPC client design the doc
  already specifies).
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift` — the
  authoritative event names, nonce fields, and relay shapes.

## Task Sequence

1. **CI lane first (smallest, unblocks everything).** Add pnpm setup +
   `mise run bridge-web-check` + `mise run bridge-web-test` +
   `mise run bridge-web-build` to ci.yml. Ordering: the bridge-web steps run
   after checkout/tool setup and **before** the Swift test lanes, because
   `bridge-web-build` writes the packaged assets to
   `Sources/AgentStudio/Resources/BridgeWeb/app` (per `.mise.toml`) and the
   WebKit serialized Swift tests serve those assets via
   `BridgeAppAssetStore`. Pin the Node/pnpm version (read from
   `BridgeWeb/package.json` `packageManager`/engines or add one). Confirm the
   artifact path matches what `BridgeAppAssetStore` reads with an explicit
   `ls` step in CI.
2. **Fixture sync task.** `bridge-web-sync-fixtures` mechanism: for each
   fixture in the sync list, copy from `Tests/BridgeContractFixtures/` into
   `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/` and fail (non-zero
   exit) if the destination differed before copy — Swift is the source of
   truth, local TS edits are drift. Wire it as the first step of
   `bridge-web-check` so CI catches drift. Sync list now: the 5 existing
   review fixtures (`bridge-review-package`, `bridge-review-delta`,
   `bridge-review-checkpoint`, `bridge-review-query-time-window`,
   `bridge-review-package-missing-generation`). Task 3 extends the list with
   the push-envelope and RPC fixtures it starts consuming (enumerate them in
   the same commit that adds the TS decode they validate).
3. **Wire transport modules.** Precondition: verify the push-envelope field
   names against architecture doc §5.4 AND the live Swift sender in
   `BridgePaneController` (grep the actual `__bridge_push` payload
   construction) — the doc and code must agree before TS mirrors either; if
   they disagree, stop and reconcile (do not invent a third shape). Then:
   envelope decode (`__revision`/`__epoch` handling), push receiver
   subscribing to the bridge push event with `pushNonce` validation
   (extraction added to `bridge-page-handshake.ts`, which currently discards
   the handshake detail — verified), RPC client serializing commands through
   the `__bridge_command` relay with `bridgeNonce`. Runtime-validate inbound
   envelopes with **zod schemas** (repo TS rules prefer zod-derived
   validation/types; one dependency, replaces blind casts and catches
   wire-shape drift at runtime) — typed-decode is a spec trust anchor. Note:
   the vitest `node` environment natively supports
   `EventTarget`/`CustomEvent` (the existing handshake test already uses
   them), so no jsdom/happy-dom dependency is needed for receiver tests.
4. **Item registry.** Package snapshot + `applyBridgeReviewDelta` + selected /
   visible priority facts in one domain-named module; unit tests for
   stale-generation envelope rejection and delta application order.
5. **Shell proof (Task 9).** Render summary/endpoints/checkpoint labels and
   the filtered item list from registry state; fetch selected item content
   through its handle URL via the existing `content-resource-loader`;
   folder/file-class/change-kind filter state in the shell. Integration tests
   per the master plan's named test files.
6. **Packaged smoke.** Build BridgeWeb, copy into app resources, run the
   WebKit serialized bridge lane (`mise run test -- --filter
   WebKitSerializedTests`) and a manual debug-build check that
   `agentstudio://app/index.html` boots the shell and a pushed package
   renders.

## Proof Gates

- Red/green: CI must fail on an injected TS type error (verify once, revert);
  fixture-sync fails on a locally edited fixture (verify once, revert).
- Focused validation: `mise run bridge-web-check`, `mise run bridge-web-test`
  (counts reported), `mise run bridge-web-build` artifact present.
- Swift side: `mise run test -- --filter "BridgeSchemeHandler"` and the WebKit
  serialized lane stay green.
- Manual: debug build renders the shell with a pushed package; selecting a
  file fetches bytes through `agentstudio://resource/content/...` (verify in
  push/scheme logs).

## Stop Conditions

- Stop if the push envelope shape in §5.4 does not match what
  `BridgePaneController` actually sends today — reconcile the doc/code first
  (do not invent a third shape in TS).
- Stop if Task 9 needs the production-wiring plan's package publication to
  exist and it has not landed — the shell can be proven against a test-pushed
  fixture package, but the packaged smoke (task 6) requires real wiring;
  split the gate rather than faking it.
- UX-first rule: the shell is intentionally plain, but if any visual decision
  beyond list+summary arises, ask before designing.

## Risks

- Hand-written TS contract mirrors can drift from Swift; the fixture-sync +
  decode tests are the guard until a schema-generation step is justified
  (record that decision; do not build codegen speculatively).
- Nonce validation in page world is defense-in-depth only — do not let its
  presence weaken the Swift-side enforcement posture (spec is explicit).

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridgeweb-transport-ci-and-shell-proof.md
Start by validating the plan against current git state before editing files.
Tasks 1-2 are independent quick wins; 3-5 are sequential; 6 gates on the
production-wiring plan. Parent owns integration and final proof (bridge-web
check/test/build, WebKit serialized lane, manual packaged smoke).
```
