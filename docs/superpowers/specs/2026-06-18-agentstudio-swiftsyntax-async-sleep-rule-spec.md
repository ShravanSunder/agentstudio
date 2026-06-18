# AgentStudio SwiftSyntax Async Sleep Rule Spec

Status: Accepted for implementation
Date: 2026-06-18

## Goal

Prevent production AgentStudio code from reintroducing the generic Swift
clock-sleep overloads that were implicated in the beta launch crash class.
The guard belongs in the repo-local SwiftPM/SwiftSyntax architecture linter,
not in a string scan test or shell grep.

## Rule

- Rule id: `agentstudio_no_generic_clock_sleep`
- Severity: error
- Tool: `Tools/AgentStudioArchitectureLint`
- Scope: production `Sources/AgentStudio/**` only
- Message: `Production async delays must avoid generic clock sleep overloads; use Task.sleep(nanoseconds:) through Duration.nanosecondsForTaskSleep or AsyncDelay.taskSleep`

## Denied Syntax

The rule reports a diagnostic on production calls to:

- `Task.sleep(for: ...)`
- any member call shaped as `.sleep(for: ...)`, such as `clock.sleep(for:)`
  or `self.clock.sleep(for:)`

The syntax matcher must use `FunctionCallExprSyntax` and argument labels, so it
catches multiline calls that a line-oriented string scan can miss.

## Allowed Syntax

The rule allows:

- `Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)`
- `Task.sleep(nanoseconds: literalOrComputedNanoseconds)`
- production calls to `AsyncDelay.taskSleep.wait(...)`
- test-only injected clocks outside `Sources/AgentStudio/**`
- the single production delay seam in
  `Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift`,
  where `AsyncDelay.clock(_:)` adapts an injected `Clock` for deterministic tests

## Rationale

`Task.sleep(nanoseconds:)` keeps the production delay path on the explicit
nanosecond overload. `Task.sleep(for:)` and generic `.sleep(for:)` use Swift's
generic clock-duration path, which was part of the macOS release startup crash
class we just rescued. Tests may still use injected clocks, but production code
should route deterministic delay behavior through an approved seam rather than
calling generic sleep directly.

## Fixture Strategy

Bad fixtures:

- production `Task.sleep(for: .milliseconds(50))`
- production generic `clock.sleep(for: .milliseconds(50))`
- multiline production `Task.sleep(\n    for: ...\n)` to prove syntax-based
  detection instead of string scanning

Good fixtures:

- production `Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)`
- the approved `AsyncDelay.clock(_:)` seam path using `clock.sleep(for:)`
- non-production test-style paths remain outside this rule's source scope

## Migration

Existing production offenders should be replaced with either:

- `Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)` for direct
  production async delays, or
- `AsyncDelay.taskSleep.wait(duration)` / injected `AsyncDelay` when deterministic
  tests need a delay seam

The existing string-scan test in `AppBootSequenceTests` may remain temporarily
as defense in depth, but the authoritative rule is the SwiftSyntax linter.

## Inventory And Proof

Update `docs/architecture/architecture_lint_inventory.md` with the new rule row.
Proof requires:

- bad fixtures fail with `agentstudio_no_generic_clock_sleep`
- good fixtures pass
- `swift test --package-path Tools/AgentStudioArchitectureLint`
- `mise run lint`

## False Positive Policy

Do not add broad source allowlists. If production code truly needs generic clock
sleep, first introduce or name an explicit delay seam and add only that exact
path to the allowlist with a doc update explaining why the exception is safe.
