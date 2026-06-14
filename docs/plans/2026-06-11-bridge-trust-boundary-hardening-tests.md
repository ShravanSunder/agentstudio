# Bridge Trust Boundary: Close The Untested Rejection Paths And Scheme-Task Cancellation

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The trust-boundary audit found the security architecture sound — traversal
defense uses stable percent-decoding with segment matching, hosts and schemes
are allowlisted and tested, generation parsing is strict, nonces are
per-controller `UUID().uuidString`, `isBridgeReady` is set-once-per-load with
reset on teardown (all parent-verified). What remains is a set of **untested
rejection paths and one real behavioral gap**:

1. **Scheme-task cancellation is not wired.** `BridgeSchemeHandler.reply(for:)`
   spawns an inner `Task` per request and never installs
   `continuation.onTermination` — when WebKit abandons a load (pane closed,
   rapid navigation), the content load runs to completion into a dead stream.
   Wasted I/O today; once the lazy-content cutover makes loads provider-backed
   and expensive, it becomes a real cost and keeps stale-generation work alive.
2. **Symlink confinement is implicit and untested.** `BridgeAppAssetStore`
   is safe only because `standardizedFileURL` resolves symlinks *before* the
   prefix check — an ordering invariant no test pins and no comment explains.
3. **Untested rejections:** negative generation, overflow generation, unknown
   handle (explicit test), pre-ready RPC rejection, missing-nonce/invalid-nonce
   relay drops (JS-side logic, no Swift-side coverage).
4. **Inverted error fields:** `BridgeContentStore`'s `staleReviewGeneration`
   error reports `expected:` from the stored handle and `actual:` from the
   request — semantically backwards for readers/log triage.

This is the executable start of LUNA-348 (Bridge security hardening) scoped to
what the foundation already ships.

## Current Evidence

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift:26-79`
  — `AsyncThrowingStream { continuation in ... Task { ... } }` with no
  `onTermination` handler (parent-verified read).
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeAppAssetStore.swift:8-34`
  — `appendingPathComponent(relativePath).standardizedFileURL` then prefix
  check; safe ordering, untested, uncommented.
- Audit's untested-rejection matrix: negative generation, overflow generation,
  unknown handle, pre-ready command rejection, symlink escape — no
  corresponding tests in `BridgeSchemeHandlerTests.swift` /
  `BridgeContentStoreTests.swift` / router tests.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift:35-39`
  — `staleReviewGeneration(expected: result.handle.reviewGeneration,
  actual: requestedGeneration)`.
- Verified-fine (do not re-audit): traversal decode loop
  (`BridgeSchemeHandler.swift:100-145`), navigation allowlist + tests,
  method allowlist, nonce generation
  (`BridgePaneController.swift:131-132`), ready-flag lifecycle
  (`BridgePaneController.swift:45,369-400`).

## Non-Goals

- No new security mechanisms (CSP, per-request tokens, batch limits) — that
  is the larger LUNA-348 scope and needs its own spec pass.
- No change to the nonce model (spec: nonce is defense-in-depth, not a
  secret).
- No scheme-handler API reshape beyond cancellation wiring.

## Scope

Write surfaces:
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift` —
  `onTermination` → cancel inner task; cooperative cancellation check before
  yielding response/data.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeAppAssetStore.swift` —
  ordering-invariant comment + (optional) explicit
  `resolvingSymlinksInPath` step so the intent is in code, not luck.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
  — swap the `expected`/`actual` semantics (or rename to
  `storedGeneration`/`requestedGeneration` — clearer; small hard cutover).
- Tests: `BridgeSchemeHandlerTests.swift`, `BridgeContentStoreTests.swift`,
  `RPCRouterTests.swift`, `BridgeAppAssetStore` tests.

Read-only context:
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` — "WebKit
  And Resource Trust Boundaries" (the contract these tests pin).

## Task Sequence

1. **Cancellation wiring.** Grounding (researched): WebKit's async
   `URLSchemeHandler` cancels the *iteration* of the returned sequence when a
   load stops, which propagates automatically only to structured work — the
   handler's inner `Task { }` is **unstructured**, so it keeps running unless
   bridged. The correct idiom, inside the `AsyncThrowingStream` build
   closure: create the inner task, then
   `continuation.onTermination = { _ in task.cancel() }` (the task reference
   is available in the closure scope; no retain cycle — onTermination is
   released on finish). Add `try Task.checkCancellation()` before each yield.
   Test: start a content load against a slow fake store gated on a
   test-controlled continuation (no `Task.sleep`), terminate the stream,
   release the gate, assert the store call observed cancellation and produced
   no completion side effects.
2. **Symlink test + intent.** Test fixture: build programmatically in-test —
   temp app-root, `FileManager.createSymbolicLink` pointing outside the root;
   assert `invalidRoute`/rejection. If symlink creation fails in a sandboxed
   CI environment, record an explicit known-issue note and exit the test
   early (do not silently pass). Add the ordering comment stating the
   standardize-then-prefix-check invariant (symlinks are resolved by
   `standardizedFileURL` *before* the prefix check — that ordering is the
   defense and must not be refactored away).
3. **Rejection-path tests.** `generation=-1`, `generation=99999999999999999999`
   (overflow), unknown handleId (content store + end-to-end scheme),
   pre-ready non-`bridge.ready` RPC rejected with `bridgeNotReady` (router
   test driving `isBridgeReady: false`).
4. **Error-field clarity.** First verify wire-visibility: grep every catch
   site of `staleReviewGeneration` — today the scheme handler finishes the
   URLSchemeTask with the error (not JSON-serialized to BridgeWeb), so the
   rename is expected to be Swift-only; confirm before editing. Then rename
   the fields to `storedGeneration`/`requestedGeneration`. Coordination: the
   lazy-content plan touches the same failure path — whichever plan lands
   second adopts the landed shape (stated in both plans).
5. **Doc note.** One paragraph in the spec's trust-boundary section listing
   the now-tested rejection matrix, so future hardening starts from evidence.

## Proof Gates

- Red/green: each new test fails when its guard is locally disabled
  (spot-verify cancellation and symlink cases).
- Focused validation:
  `mise run test -- --filter "BridgeSchemeHandler"`,
  `mise run test -- --filter "BridgeContentStore"`,
  `mise run test -- --filter "RPCRouter"`.
- Full validation: `mise run test`, `mise run lint` — zero errors. Baseline:
  bridge-filtered Swift tests pass at 578c1084 (parent-run 2026-06-11,
  exit 0).

## Stop Conditions

- Stop if `onTermination` cannot reach the inner task without restructuring
  `reply(for:)`'s stream shape — the WebKit `URLSchemeHandler` protocol
  contract constrains this; propose the restructure before doing it.
- Stop if the stale-generation failure shape is wire-visible to BridgeWeb and
  renaming breaks a fixture — coordinate with the fixture-sync task in the
  BridgeWeb plan instead of forking the shape.

## Risks

- Cancellation checks racing legitimate completions: yield-then-finish
  sequences must tolerate cancellation between yields without partial-response
  corruption — the slow-fake test covers the window.
- Symlink fixtures on CI filesystems (sandbox/temp dirs) can behave
  differently than local — build the fixture programmatically in-test.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridge-trust-boundary-hardening-tests.md
Start by validating the plan against current git state before editing files.
Tasks 1-4 are independent slices; task 5 last. Parent owns integration and
final proof (mise run test, mise run lint).
```
