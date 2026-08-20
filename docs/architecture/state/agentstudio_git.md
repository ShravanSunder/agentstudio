# agentstudio-git

<a id="agentstudio-git"></a>

[`agentstudio-git`](https://github.com/ShravanSunder/agentstudio-git) is the
**Git operations package** for AgentStudio. This app does not own Git
semantics. It pins that package and calls it.

**Why it exists:** one abstraction for repository work (status, worktrees,
discovery, diffs, ignore, pathspecs). Agents must not shell out to `git` or
`wt`, and must not reimplement that policy in Swift or TypeScript. GitHub/`gh`
work may move into the same package later; until it does, do not grow a second
Git CLI data plane in this repo.

## What to open

1. **The package itself** — clone or browse
   [`ShravanSunder/agentstudio-git`](https://github.com/ShravanSunder/agentstudio-git)
   at the revision this app pins. Types, tests, and Git behavior live there.
   Do not invent APIs from this file.
2. **The pin** — [`Package.swift`](../../../Package.swift) (`.package(url:…,
   revision:…)` for `agentstudio-git`, product `AgentStudioGit`). Change Git
   behavior by bumping that revision, not by adding `Process`/`git` here.

This is not a Ghostty/zmx vendor and not a submodule.
`mise run setup --use-local-vendors` does not apply.

TypeScript may use `git` only in marked Vite dev-server or test-fixture
utilities.

Demand, EventBus facts, and Bridge mapping stay in this app. Those hop:
[Workspace Data Architecture](workspace_data_architecture.md),
[Bridge Native Runtime](../bridge/bridge_native_runtime_architecture.md).
