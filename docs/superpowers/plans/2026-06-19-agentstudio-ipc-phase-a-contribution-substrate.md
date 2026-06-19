# AgentStudio IPC Phase A Contribution Substrate Plan

Date: 2026-06-19
Status: reviewed implementation plan, ready for implementation execution
Branch: `ipc-phase-a-substrate-fresh`
Base: `origin/main` at `470f72d9851778b45da0b3a4756b7e043fdf1b57`

## Goal

Make AgentStudio app IPC easy to extend safely by future feature owners without
moving socket, authentication, authorization, grant, target-canonicalization,
JSON-RPC, or redaction policy out of `AgentStudioAppIPC`.

The implementation must prove the first supported contributor shape through one
existing generic app method. The Phase A exemplar is `pane.snapshot` because it
already has sanitized public DTOs, exercises pane-handle canonicalization, and
avoids Bridge/diff/review feature semantics. This slice proves authenticated,
handle-based query contributions. Other shapes such as app-scoped UI methods,
streaming/event methods, accepted async commands, and future feature-owned
method families remain later contribution slices unless the implementation
discovers a direct blocker and returns to planning.

Phase A also includes one command-catalog correctness fix: IPC command discovery
must be projected from the app command spec catalog instead of a parallel
hardcoded IPC mini-catalog. This keeps `command.list` useful for programmatic
control while preserving the rule that `command.execute` only runs commands
explicitly marked headless-executable.

## Non-Goals

- No Bridge/diff/review method names, parameters, privileges, proof gates, or
  implementation.
- No public `bridge.*` or `zmx.*` methods.
- No raw terminal output, prompt, cwd, scrollback, buffer, command text, zmx
  session/socket, or raw runtime payload export.
- No durable or automatic restart-resumable app IPC authority.
- No EventBus command routing.
- No direct atom mutation from IPC methods.
- No June 15 lifecycle-closure implementation unless a named issue is proved to
  directly block this substrate.

## Source Coverage

Read end to end before this plan:

- `tmp/spec-workflows/2026-06-19-agentstudio-ipc-phase-a-programmatic-control-design/phase-a-design-synthesis.md`: 299 lines, read lines 1-299.
- `docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md`: 1654 lines, read lines 1-1654.
- `docs/superpowers/specs/2026-06-15-agentstudio-ipc-runtime-lifecycle-followup.md`: 478 lines, read lines 1-478.
- `docs/architecture/agentstudio_ipc_architecture.md`: 535 lines, read lines 1-535.
- `docs/architecture/session_lifecycle.md`: 537 lines, read lines 1-537.
- `docs/architecture/directory_structure.md`: 511 lines, read lines 1-511.
- `tmp/workflow-state/2026-06-19-ipc-phase-a-substrate/details.md`: 204 lines, read lines 1-204.
- `tmp/workflow-state/2026-06-19-ipc-phase-a-substrate/events.jsonl`: 2 lines, read lines 1-2.

Live repo evidence checked on the fresh branch:

- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCQueryAdapter.swift`
- `Sources/AgentStudioProgrammaticControl/IPCContracts.swift`
- `Sources/AgentStudioProgrammaticControl/IPCQueryContracts.swift`
- `Sources/AgentStudioIPCClientCore/AgentStudioIPCClientCore.swift`
- `Sources/AgentStudioIPCClientCore/AgentStudioIPCClientArguments.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioIPCRegistryAuthorizationTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTestSupport.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCQueryAdapterTests.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/IPCBoundaryRules.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/ImportDirectionRule.swift`
- `Package.swift`
- `.mise.toml`
- `scripts/run-debug-observability.sh`
- `scripts/verify-debug-observability.sh`

## Current Model

Current app IPC has the right target split but the extension seam is still
method-name hardcoded:

1. `AppIPCMethodRegistry.phaseOne()` owns one static catalog.
2. `AgentStudioAppIPCServer.authorizationContext(for:)` owns a method switch for
   target extraction and canonical handle rewriting.
3. `AgentStudioAppIPCServer.processAuthenticated(...)` owns another method
   switch for dispatch.
4. `AppDelegate+IPC.swift` builds the registry and all ports centrally.
5. `AgentStudioIPCQueryAdapter.systemCapabilities()` mirrors the registry, so
   contributed methods must be merged before adapter composition.

That means adding a feature method today still requires central edits in the
catalog, auth-context switch, dispatch switch, app port surface, and tests. Phase
A should replace that with a narrow app-composed contribution substrate.

## Requirements / Proof Matrix

| Requirement or claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green required | Sized to pass in scope |
|---|---|---|---|---|---|---|---|
| Registry can merge base plus contributed method definitions. | T1, T2 | implementation executor | `AgentStudioIPCRegistryAuthorizationTests` | Unit | Run after registry constructor changes on current branch. | Yes | Yes |
| Duplicate contributed or base method names fail before capability export. | T1, T2 | implementation executor | registry duplicate test | Unit | Assert thrown error, not silent last-writer-wins. | Yes | Yes |
| Deferred namespaces are rejected before registry merge and capability export. | T1, T2 | implementation executor | namespace-policy tests for `bridge.*`, `diff.*`, `review.*`, `zmx.*`, `mcp.*`, `browser.*`, `webview.*`, `orchestration.*` | Unit | Include contributed rejected namespaces and assert they do not reach capabilities. | Yes | Yes |
| Contributor method metadata includes schema names, target/data scope, and sensitive-data exclusions. | T1, T2, T3 | implementation executor | registry metadata tests plus `pane.snapshot` definition assertions | Unit/lint | Test fails if a contributed method can register with default/empty metadata or without an explicit exclusion list. | Yes | Yes |
| Phase A contributed methods are authenticated-only; pre-auth remains base-owned. | T1, T2 | implementation executor | registry validation test rejecting contributed `.preAuthentication` | Unit | Test fails if a contributed method can bypass the hardcoded pre-auth gate or advertise unreachable pre-auth availability. | Yes | Yes |
| Phase A contributors may register only `pane.*`; base-owned current namespaces are not contributor namespaces. | T1, T2 | implementation executor | registry tests rejecting synthetic `terminal.*`, `workspace.*`, and `drawer.*` contributions | Unit | Test fails if a non-pane contributed prefix can reach the merged registry or capabilities. | Yes | Yes |
| A contributor owns target/auth-context canonicalization for its method shape. | T1, T2, T3 | implementation executor | service test for contributed `pane.snapshot` with friendly handle rewritten to UUID before auth/dispatch | Integration | Test must fail if `pane.snapshot` only works through the old central switch. | Yes | Yes |
| Central server still owns authentication, authorization, grants, JSON-RPC errors, and socket lifecycle. | T1, T2, T3 | implementation executor and implementation review | socket integration negative tests for unauthenticated, unauthorized cross-pane, and unknown method | Integration | Use a real `AgentStudioAppIPCServer` fixture, not direct handler invocation. | Yes | Yes |
| Contributor dispatch receives a narrow post-authorization context, not the full service object or auth internals. | T2, T3 | implementation executor and implementation review | protocol/API review plus service tests proving auth denial occurs before contributor invocation | Unit/integration/review | The exemplar contributor must not receive `AuthorizationService`, principal registry internals, or mutable server state. | Yes | Yes |
| Unsafe debug does not automatically authorize every contributed method. | T1, T2 | implementation executor | unit auth test plus socket integration test with an admitted but non-allowlisted synthetic contributed method | Unit/integration | Test fails if `.unsafeDebug` bypasses central method-name allowlist for all contributed methods. | Yes | Yes |
| The substrate claim is scoped to authenticated handle-based query contributors in this slice. | T1, T2, T3, T6 | parent and implementation review | plan review plus implementation review | Review | Reject implementation claims that Phase A already supports app-scoped, streaming, event, accepted async, or Bridge/diff/review contributor shapes. | No code red/green; review proof | Yes |
| `pane.snapshot` is proven through the contributor path without new feature semantics. | T1, T3 | implementation executor | socket integration test and app query adapter tests | Integration | Remove `pane.snapshot` from base hardcoded dispatch before proof. | Yes | Yes |
| `system.capabilities` includes contributed methods only after namespace admission. | T1, T2, T3 | implementation executor | capabilities tests in AppIPC and app query adapter suites | Unit/integration | Assert sorted capabilities include contributed `pane.snapshot` and exclude rejected namespaces. | Yes | Yes |
| Concrete contributor adapters live in app composition, not feature runtime code. | T4 | implementation executor | architecture lint fixture tests and `mise run lint` | Static/lint | Add fixtures that fail outside `App/IPCComposition`. | Yes | Yes |
| `Sources/AgentStudio/Features/**` does not import `AgentStudioAppIPC`. | T4 | implementation executor | architecture lint rule and bad fixture | Static/lint | Fixture must be under `Sources/AgentStudio/Features/<Feature>/...`. | Yes | Yes |
| IPC public DTOs remain sanitized. | T3, T4 | implementation executor | existing `AgentStudioIPCQueryAdapterTests` plus lint public-surface tests | Unit/lint | Re-run after moving `pane.snapshot` through contribution. | Yes | Yes |
| CLI/debug smoke can prove the contributed exemplar through the real socket path. | T5 | implementation executor and parent verifier | new phase-A smoke script plus debug observability verifier | Smoke | Must launch current debug app and read current runtime metadata, not stale logs. | Yes | Yes |
| `command.list` exposes every app command spec through typed IPC metadata while `command.execute` remains fail-closed for non-headless specs. | T5 addendum | implementation executor | `AgentStudioIPCCommandAdapterTests`, `AgentStudioAppIPCServiceTests`, and `AgentStudioIPCClientCoreTests` | Unit/integration | Remove stale hardcoded IPC command identifier catalog; prove list count matches `AppCommand.allCases` and UI-presentation commands return `requiresPresentation`. | Yes | Yes |
| Scoped Phase A does not absorb Bridge/diff/review or lifecycle closure. | All tasks | parent and implementation review | plan review plus implementation review | Review | Diff must not add public `bridge.*` / `review.*` / `diff.*` methods or child-exit/pane-close lifecycle wiring unless re-planned. | No code red/green; review proof | Yes |
| Goal can proceed toward PR-ready non-merge state. | T6 | parent | PR draft/update, checks, review threads, mergeability state | PR/release gate | Fetch fresh PR state during wrap-up. | No code red/green; PR proof | Yes |

## Design Shape

Add the smallest contribution substrate inside `AgentStudioAppIPC`:

```text
AppIPC base registry
  + app-composed contributors
        |
        v
merged AppIPCMethodRegistry
  - duplicate rejection
  - namespace admission
  - capability export source

request
  -> auth.login / principal
  -> method lookup in merged registry
  -> contributor auth-context provider if method is contributed
  -> central AuthorizationService
  -> contributor dispatch if method is contributed
  -> existing base dispatch otherwise
```

The contribution contract should be explicit and boring. Prefer a per-method
value record over a broad protocol so registry merge, auth lookup, and dispatch
reachability are validated together:

```swift
package struct AppIPCMethodContribution: Sendable {
    let definition: IPCMethodDefinition
    let securityContract: AppIPCContributionSecurityContract

    let authorizationContext: @Sendable (
        _ request: JSONRPCRequest,
        _ principal: IPCPrincipal,
        _ tools: AppIPCContributionAuthorizationTools
    ) async throws -> AppIPCAuthorizedRequestContext

    let dispatch: @Sendable (
        _ request: JSONRPCRequest,
        _ principal: IPCPrincipal,
        _ context: AppIPCContributionDispatchContext
    ) async throws -> JSONValue?
}
```

Implementation may adjust names, but must preserve the split:

- contributor declares method definitions and method-specific target extraction;
- server provides canonicalization/decode helpers as narrow tools;
- server runs auth and grants after target canonicalization;
- server gives dispatch a narrow post-authorization context rather than the
  entire `AgentStudioAppIPCService` or authorization internals;
- contributor dispatch runs only after authorization succeeds;
- base methods keep the current dispatch until later migrations earn their own
  slices.

New contributor-substrate APIs should be `package` or `internal` by default.
Only existing client/programmatic-control DTOs and intentionally exported
transport contracts remain `public`. `AppIPCAuthorizedRequestContext`,
`JSONRPCRequest.replacingHandle(...)`, and the handle string formatter should
move out of private file scope only as far as the package-scoped contributor API
needs. Do not expose app internals or concrete feature owners from
`AgentStudioAppIPC`.

Contributor lookup is keyed by method name. If a method name is in the
contributor dispatch table, its `authorizationContext` hook must return a
concrete canonicalized context or throw a mapped JSON-RPC error. It must not
return `nil`, silently fall back to the base switch, or substitute an app-scope
default.

Registry construction must reject any contributed method that does not have
exactly one method definition, one auth-context hook, and one dispatch hook
before the merged registry can feed `system.capabilities`.

Phase A namespace admission should be explicit in code and tests. Base AppIPC
keeps ownership of existing central control-plane prefixes such as `system.`,
`auth.`, `window.`, `workspace.`, `drawer.`, `terminal.`, `command.`, `ui.`,
`permission.`, and `events.`. The Phase A contributor-allowed prefix is
`pane.` only, for the `pane.snapshot` exemplar. Deferred or future adapter
prefixes such as `bridge.`, `diff.`, `review.`, `zmx.`, `mcp.`, `browser.`,
`webview.`, and `orchestration.` must not appear in contributed method
definitions, the merged registry, or capabilities until a later accepted spec
admits them.

## Task Sequence

### T1. Add failing substrate tests first

Write focused Swift Testing coverage before implementation:

- In `AgentStudioIPCRegistryAuthorizationTests`:
  - contributed methods merge with base definitions;
  - duplicate method names throw;
  - deferred namespaces throw before capability export;
  - deferred namespaces include `bridge.*`, `diff.*`, `review.*`, `zmx.*`,
    `mcp.*`, `browser.*`, `webview.*`, and `orchestration.*`;
  - non-pane current app IPC prefixes such as synthetic `terminal.*`,
    `workspace.*`, and `drawer.*` are rejected for contributed methods in this
    slice;
  - contributors cannot register central base-owned prefixes such as `system.*`,
    `auth.*`, `permission.*`, `events.*`, `command.*`, or `ui.*`;
  - contributors cannot register `.preAuthentication` methods in Phase A;
  - contributed methods must carry explicit schema names, target/data scope, and
    sensitive-data exclusions;
  - a contributed method cannot be exported in capabilities without exactly one
    auth-context hook and one dispatch hook;
  - an admitted but non-allowlisted synthetic contributed method is unauthorized
    for `.unsafeDebug` until the allowlist explicitly names it;
  - `pane.snapshot` can be absent from base and present through contribution.
- In `AgentStudioAppIPCServiceTests`:
  - authenticated socket call to contributed `pane.snapshot` succeeds;
  - friendly `pane:1` is canonicalized before dispatch;
  - spawned pane principal bound to another pane is denied before handler
    invocation;
  - unauthenticated contributed method fails with `-32001`;
  - disallowed contributed namespace is a registry construction failure before
    capability export;
  - unknown unregistered runtime method returns method-not-found.
- In `AgentStudioIPCQueryAdapterTests`:
  - capabilities mirror the merged registry, not only base phase-one methods.

Expected red state:

- The registry has no contributor merge API.
- `pane.snapshot` only works through the central hardcoded query path.
- No namespace-admission policy exists beyond `zmx.*` construction rejection.

### T2. Implement registry and contributor substrate

Likely write surfaces:

- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- new `Sources/AgentStudioAppIPC/AgentStudioIPCMethodContribution.swift`

Implementation requirements:

1. Add a namespace admission policy for Phase A using the explicit contributor
   prefix list in this plan. In this slice, contributors may register `pane.*`
   only; base methods keep existing central prefixes.
2. Make `AppIPCMethodRegistry` validate duplicate method names and disallowed
   namespaces.
3. Add contribution metadata support for the security contract. At minimum,
   contributed methods must expose schema names, target/data scope vocabulary,
   and sensitive-data exclusions for params and results. If this requires a new
   metadata wrapper around `IPCMethodDefinition`, keep it in
   `AgentStudioProgrammaticControl` or `AgentStudioAppIPC` according to the
   existing contract boundary and prove it with registry tests.
4. Reject contributed `.preAuthentication` methods. Pre-auth remains base-owned
   until a later plan moves pre-auth admission onto the merged registry.
5. Add a contribution collection or dispatch table keyed by method name.
   Registry construction must reject duplicate contributed handlers and any
   definition/handler mismatch before capability export.
6. Make server authorization context lookup consult contributors before the base
   switch for contributed methods.
7. Make authenticated dispatch consult contributors before the base switch for
   contributed methods.
8. Keep auth, authorization, grant lookup, JSON-RPC errors, connection tracking,
   and socket lifecycle central in `AgentStudioAppIPCServer`.
9. Give contributors a narrow `AppIPCContributionDispatchContext` that exposes
   only approved post-authorization call surfaces needed for dispatch. Do not
   pass the whole `AgentStudioAppIPCService`, `AuthorizationService`, principal
   registry, grant ledger, or mutable server state to contributors.
10. Keep new contributor-substrate declarations `package` or `internal` unless
    a public client/programmatic-control boundary requires otherwise.
11. Keep unsafe debug allowlist explicit. Contributed methods are not
    automatically debug-authorized unless their method name is intentionally added
    to the debug allowlist. Add a negative test with an admitted namespace method
    that is not on the allowlist so `pane.snapshot`'s existing allowlist entry
    cannot mask a broad debug bypass.

Split trigger:

- If making all existing methods contributor-driven would expand the diff
  materially, stop after the generic substrate plus `pane.snapshot` exemplar.
  Broad migration is a later cleanup.

### T3. Migrate `pane.snapshot` as the exemplar contribution

Likely write surfaces:

- new `Sources/AgentStudio/App/IPCComposition/Panes/PaneSnapshotIPCContribution.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCQueryAdapter.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTestSupport.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCQueryAdapterTests.swift`
- `Tests/AgentStudioTests/App/ApplicationEntrypointArchitectureTests.swift`

Implementation requirements:

1. Remove `pane.snapshot` from all old central hardcoded seams:
   `AppIPCMethodRegistry.phaseOne()`,
   `AgentStudioAppIPCServer.authorizationContext(for:)`, and the base
   authenticated-routing switch in
   `AgentStudioAppIPCServer+AuthenticatedRouting.swift`.
2. Register `pane.snapshot` through an app-composed contributor.
3. Contributor auth context decodes `HandleParams`, canonicalizes pane handles
   through server-provided tools, rewrites params to the canonical pane UUID
   handle, and returns `.pane(<uuid>)` target scope.
4. Contributor dispatch calls the query port exposed by the narrow contribution
   dispatch context with the canonical pane id.
5. Keep `IPCPaneSnapshotResult` unchanged.
6. Keep sanitized snapshot proof unchanged: no titles, cwd, URLs, zmx session ids,
   terminal output, or raw runtime payloads.
7. Update existing app-entrypoint architecture assertions that currently look
   for `AppIPCMethodRegistry.phaseOne()` in `AppDelegate+IPC.swift`, so broad
   `mise run test` does not fail on stale composition-shape assumptions.

Placement note:

`pane.snapshot` is a generic app/pane method, not Bridge or Terminal feature
semantics. The concrete adapter should live under
`Sources/AgentStudio/App/IPCComposition/Panes/`. Reserve
`Sources/AgentStudio/App/IPCComposition/Features/<Feature>/` for later methods
whose semantics are truly feature-owned. The architecture lint still must prove
that `Sources/AgentStudio/Features/**` cannot import `AgentStudioAppIPC`.

### T4. Enforce contribution boundaries

Likely write surfaces:

- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/IPCBoundaryRules.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Core/ArchitectureRule.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleInventoryTests.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- new `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCHumanApprovalPort.swift`
- new/update fixture files under `Tools/AgentStudioArchitectureLint/Tests/.../Fixtures/Bad` and `Good`
- `docs/architecture/architecture_lint_inventory.md` if a new rule id is added

Implementation requirements:

1. Extend the composition-location rule to recognize current AppIPC port
   protocols and the new contributor protocol.
2. Add a blocking lint check that files under
   `Sources/AgentStudio/Features/**` cannot import `AgentStudioAppIPC`.
3. Allow app-composition contributor files under
   `Sources/AgentStudio/App/IPCComposition/**`.
4. Move the existing `AgentStudioIPCHumanApprovalPort` conformance out of
   `AppDelegate+IPC.swift` and into `Sources/AgentStudio/App/IPCComposition/`
   before broadening the composition-location rule. Do not weaken the lint rule
   to preserve a Boot-folder exception.
5. Keep `AgentStudioAppIPC` free of executable app imports and concrete runtime
   owner references.
6. Add good/bad fixtures so the lint rule failure is not review-only.
7. After fixture tests pass, run the architecture linter against the live tree
   so misplaced real files cannot hide behind fixture-only proof.

If adding a new rule id is cleaner than extending an existing one, add it and
update rule inventory tests plus architecture lint inventory docs.

### T5. Add live debug IPC smoke for the contributed exemplar

Likely write surfaces:

- `Sources/AgentStudioIPCClientCore/AgentStudioIPCClientCore.swift`
- `Sources/AgentStudioIPCClientCore/AgentStudioIPCClientArguments.swift`
- `Tests/AgentStudioIPCClientTests/AgentStudioIPCClientCoreTests.swift`
- new/update script contract test under `Tests/AgentStudioTests/Scripts/`
- new `scripts/verify-agentstudio-ipc-phase-a-smoke.sh`
- `.mise.toml` task `verify-agentstudio-ipc-phase-a-smoke`

Implementation requirements:

1. Add a CLI verb for `pane.snapshot`, for example:
   `agentstudio-ipc pane-snapshot pane:1`.
2. The smoke script must use the current debug runtime metadata from the debug
   observability state, not hardcoded socket paths.
3. The smoke must authenticate once over the current Unix-domain socket, call
   `system.capabilities`, and assert `pane.snapshot` is present.
4. The smoke must call `pane.list`, pick a current live pane, then call both
   `pane.snapshot` with `pane:1` and `pane.snapshot` with the current canonical
   handle when a canonical handle is available. The friendly-handle call is
   mandatory because it proves contributor canonicalization rather than only
   canonical UUID invocation.
5. The smoke must fail if capabilities export works but invocation fails.
6. The smoke must not require or inspect terminal output.
7. The smoke must run in one explicit auth mode. For Phase A routing proof,
   prefer escrow-authenticated smoke: enable `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1`,
   do not enable `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH`, read the debug token from the
   debug escrow file, perform one `auth.login`, and reuse that authenticated
   socket session for capabilities, pane discovery, and snapshot calls. Debug
   escrow tokens are single-use, so the live smoke must not rely on repeated
   short-lived CLI invocations with the same token. If an unsafe-no-auth
   diagnostic smoke is added, keep it as a separately named debug bypass proof
   and do not count it as auth-path proof.
8. The smoke must be runnable after:

```bash
mise run observability:up
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```
9. Add repo-native script contract coverage for the new verifier: bash syntax,
   `.mise.toml` task wiring, debug state-file sourcing, IPC metadata path
   derivation, escrow token use, and friendly-plus-canonical handle invocation
   expectations.

### T5 Addendum. Systematize command IPC contract projection

1. Add a failing command-adapter test proving `command.list` projects all
   `AppCommandSpec` rows through typed IPC metadata.
2. Put IPC command exposure on `AppCommandSpec` as a typed value, not a boolean.
   The exposure must carry execution modes, target handle kinds, and required
   privilege classes.
3. Derive the default interactive exposure from `appliesTo` so pane/tab command
   specs get the correct target vocabulary without a second IPC table.
4. Mark command-bar presentation commands as `uiPresentation` so clients can
   discover them without routing them through `command.execute`.
5. Remove the stale public `IPCCommandIdentifier` hardcoded catalog. The public
   identifier remains an open string wrapper; `command.list` is the catalog.
6. Keep `command.execute` fail-closed for every command that is not explicitly
   headless-executable.
7. Prove the socket/service and CLI framing paths still decode open string
   command ids and preserve `unsupported capability`, `requires presentation`,
   and target-handle rejection behavior.

### T6. Documentation, review, and PR-ready wrap-up

Likely write surfaces:

- `docs/architecture/agentstudio_ipc_architecture.md`
- `docs/architecture/directory_structure.md`
- `docs/architecture/architecture_lint_inventory.md` if lint rules change
- PR description and implementation evidence

Implementation requirements:

1. Promote durable contribution-substrate decisions into architecture docs after
   implementation proof is real.
2. Keep Bridge/diff/review as future consumers only.
3. Run implementation review.
4. Address or explicitly reject implementation review findings.
5. Open/update PR.
6. Report fresh PR checks, review-thread state, and mergeability.
7. Do not merge unless explicitly authorized.

## Validation Gates

Focused red/green gates:

```bash
swift test --filter AgentStudioIPCRegistryAuthorizationTests
swift test --filter AgentStudioAppIPCServiceTests
swift test --filter AgentStudioIPCQueryAdapterTests
swift test --filter AgentStudioIPCClientCoreTests
swift test --filter AgentStudioIPCCommandAdapterTests
swift test --filter AgentStudioIPCPhaseASmokeScriptTests
swift test --package-path Tools/AgentStudioArchitectureLint
swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint Sources Tests
bash -n scripts/verify-agentstudio-ipc-phase-a-smoke.sh
```

Repo quality gates:

```bash
mise run lint
mise run test
```

Live smoke gates:

```bash
mise run observability:up
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-agentstudio-ipc-phase-a-smoke
```

If `mise run test` or live smoke fails outside the scoped code path, stop code
edits, report the unrelated blocker with evidence, and ask before changing
tooling, environment, or unrelated app layers.

## Security Assumptions

- Contributors are statically app-composed at launch. There is no plugin, MCP,
  CI, package-script, or runtime-loaded extension registry in Phase A.
- Method namespace admission is allowlist-based for Phase A, with contributed
  methods limited to `pane.*` in this slice.
- Contributed methods are authenticated-only in Phase A; pre-auth methods remain
  base-owned.
- Authenticated dispatch still runs through one central authorization path.
- Contributor DTOs must declare schema names, target/data scope vocabulary, and
  sensitive-data exclusions for params and results.
- Contributors receive no auth internals, principal registry internals, grant
  ledger, or mutable server state during dispatch.
- `pane.snapshot` remains sanitized and cannot expose titles, cwd, URLs, zmx
  ids, raw terminal payloads, prompts, or command text.
- Unsafe debug remains explicit and debug-channel-only.
- App restart requires fresh auth. zmx survival is not app IPC authority
  survival.

## Rollback / Recovery

- If the contributor abstraction gets too broad, keep only the registry merge
  and `pane.snapshot` exemplar path, then defer broader migration.
- If `pane.snapshot` migration creates cyclic app composition, keep
  capabilities merged in app composition and narrow the contribution dispatch
  context further rather than letting contributors own app state or receive the
  full AppIPC service.
- If the CLI smoke is blocked by debug terminal readiness, preserve lower-layer
  unit/integration proof, report the smoke blocker separately, and do not claim
  the smoke gate.
- If architecture lint is too large for the same slice, split T4 into a separate
  proof-bearing task only with explicit plan-review acceptance. The preferred
  plan keeps lint in this slice because the boundary is part of the substrate.

## Open Questions For Plan Review

Resolved by plan review:

1. Use a per-method contribution value/record, not a broad protocol that receives
   the whole AppIPC service.
2. Put the generic `pane.snapshot` exemplar under `App/IPCComposition/Panes/`;
   reserve `App/IPCComposition/Features/<Feature>/` for later true feature-owned
   methods.
3. Limit Phase A contributed namespaces to `pane.*`; keep central control-plane
   prefixes base-owned.

Remaining open question:

1. Should sensitive-data exclusions become fields on `IPCMethodDefinition`, or
   should they live in an AppIPC-only contribution metadata wrapper while the
   public contract stays narrower? The plan allows either, but implementation
   must make the security contract testable before exporting contributed
   capabilities.

## Phase Footer

phase_result: complete
evidence: `docs/superpowers/plans/2026-06-19-agentstudio-ipc-phase-a-contribution-substrate.md`, `tmp/workflow-state/2026-06-19-ipc-phase-a-substrate/plan-review-report.md`
recommended_next_workflow: `shravan-dev-workflow:implementation-execute-plan`
recommended_transition_reason: Plan review accepted after tightening the contributor contract, namespace/auth/debug proof, cutover surfaces, lint/live-smoke gates, and Phase A scope claim; implementation can proceed from this reviewed plan.
