# Zmx Restore and Sizing

## Goal

Keep session restore reliable while ensuring restored panes get correct terminal geometry (`cols`/`rows`) without requiring manual input.

## Runtime Flow

1. Pane startup launches an interactive shell first (`zsh -i -l`).
2. Zmx attach command is stored as `deferredStartupCommand`.
3. Ghostty surface waits for readiness:
   - surface is in a window,
   - content size is non-zero,
   - process is still alive,
   - deferred attach was not already sent.
4. Once ready, AgentStudio injects zmx attach text and sends a real Return key event.

This prevents early attach against placeholder geometry during startup.

## Why Not Immediate Attach

Immediate attach during startup was tested and produced unstable behavior:

1. restored panes could keep wrong width/column state,
2. startup flicker increased,
3. attach timing was sensitive to view/window ordering.

Deferred attach after readiness is the stable default.

## Test Coverage

### Unit

1. `DeferredStartupReadinessTests`
   - validates readiness policy for scheduling and execution.
   - protects sizing gate semantics (window + non-zero dimensions required).

2. `ZmxBackendTests`
   - validates session ID format, attach command shape, env handling, and kill/discover logic.

### Integration

1. `ZmxBackendIntegrationTests`
   - validates behavior against a real zmx binary with isolated `ZMX_DIR`.

### End-to-End

1. `ZmxE2ETests`
   - full lifecycle: create, health check, orphan discovery, kill.
   - restore semantics: backend recreation can rediscover and kill existing live sessions.

## What Is Not Fully Automated Yet

GUI-level verification of rendered prompt wrapping/visual flicker across pane resize still requires manual validation, because current test targets do not drive AppKit layout + Ghostty rendering end-to-end.

The automated suites cover the attach/sizing gate policy and zmx daemon lifecycle to reduce regression risk in restore behavior.
