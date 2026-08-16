# BridgeWeb Swift Development Backend — Requirements

> **Status:** Substrate for the focused Vite + Swift carrier boundary. PR0
> Review Comparison supersedes only this document's worktree/base-only and
> no-persistence assumptions: the standalone server now also needs isolated
> durable pane intent through production Core owners. The fast no-full-app
> development requirement remains current. See
> [`../2026-08-06-worktree-annotations/pr0-user-requirements.md`](../2026-08-06-worktree-annotations/pr0-user-requirements.md).

## Developer And Job

The affected user is a BridgeWeb developer working on the React frontend and
the Swift Files/Review product backend. Their job is to exercise real Bridge
product behavior in a browser while retaining Vite's frontend development
loop.

No Agent Studio end-user behavior change is requested.

## Requirements

### U1 — Preserve Vite for frontend development

- **Need:** Continue using Vite to serve BridgeWeb and provide frontend
  hot-module replacement.
- **Why:** Fast React feedback is useful existing behavior; Vite's ownership of
  frontend development is not the duplication being removed.
- **Evidence:** Product-owner direction in the 2026-08-05 design conversation;
  current `BridgeWeb/vite.config.ts` configures Vite and React.
- **Authority:** Authorized
- **Priority:** Must
- **Priority assigner:** Product owner

### U2 — Use one Swift source of truth for product behavior

- **Need:** Files and Review behavior used by the Vite-served frontend must
  execute the same Swift product code used by AgentStudio, through a
  development-only server, rather than a TypeScript reimplementation.
- **Why:** Separate Swift and TypeScript implementations of sessions, Git
  preparation, File/Review products, and content delivery can diverge while
  appearing to exercise the same frontend.
- **Evidence:** Product-owner direction in the 2026-08-05 design conversation;
  current Vite middleware installs a TypeScript product carrier while the
  `AgentStudioBridge` Swift target owns the production product runtime.
- **Authority:** Authorized
- **Priority:** Must
- **Priority assigner:** Product owner

### U3 — Keep backend development independent of the full app loop

- **Need:** The Vite development command should rebuild and restart the
  development backend after relevant Swift source changes without rebuilding
  or relaunching the full AgentStudio application.
- **Why:** The development server should remain practical for focused Bridge
  work.
- **Evidence:** Product-owner direction in the 2026-08-05 design conversation.
- **Authority:** Authorized
- **Priority:** Must
- **Priority assigner:** Product owner
- **Acceptance note:** Backend rebuilding begins only after ten seconds with no
  relevant source change. A failed, timed-out, or stale build must not retire
  the working backend.

## Current Journey And Missing Outcome

```text
Current
  Vite serves React + HMR
    └── TypeScript also implements the development product backend

Required
  Vite serves React + HMR
    └── supervises the development Swift backend
          └── product requests execute AgentStudioBridge Swift behavior
```

The missing outcome is not a new frontend or a faster build system. It is a
browser development path whose Files/Review results come from the Swift product
authority.

## Existing Foundation To Reuse

- Vite already serves the development frontend and React HMR.
- `AgentStudioBridge` is a dedicated Swift package target rooted at
  `Sources/AgentStudio/Features/Bridge`.
- Swift and `agentstudio-git` already own production Files/Review data and
  authorization.
- BridgeWeb already speaks bootstrap, command, metadata-stream, and content
  contracts.

## Boundary

### Required outcome

- Keep Vite as the frontend development server.
- Replace Vite's TypeScript product-backend implementation with a Debug Swift
  server that reuses `AgentStudioBridge` product behavior.
- Keep one frontend/worker product contract across browser development and the
  packaged app.

### Protected

- Files/Review product semantics and user-facing behavior.
- The production Bridge pane/controller lifecycle.
- The React and comm-worker ownership model.
- Test fixtures may emulate inputs and failures, but they must not become a
  second development product backend.

### Out of scope

- Replacing Vite or its frontend hot-reload role.
- Redesigning product sessions, controllers, worktree identity, or Git
  behavior.
- Zero-downtime restart or a numeric end-to-end restart target.
- Production HTTP serving or a remotely reachable service.

### Acceptable complexity

The change may add the smallest development-only Swift serving boundary and
the wiring needed for Vite development to use it. A second product model,
compatibility layer, persistent service, production server, frontend fork, or
watcher inside the Swift executable requires a new owner decision.

## Outcome Evidence

The completed design must make it possible to prove the Must outcomes that:

1. Vite still serves BridgeWeb and React changes hot-reload.
2. Browser Files and Review journeys receive real worktree results produced by
   the Swift product backend.
3. The TypeScript development runtime no longer owns product sessions,
   File/Review Git preparation, metadata publication, or content delivery.
4. Browser development and packaged production use one product protocol rather
   than environment-specific frontend behavior.

It should also make it possible to prove the U3 outcome that Vite observes only
the explicit Swift backend dependency closure, waits for ten seconds of source
quiet, preserves the working backend across failed or stale builds, and reloads
the page once after a successful replacement reports ready.
