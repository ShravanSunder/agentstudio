# AgentStudio Debug App Artifact Containment

Date: 2026-07-22
Status: ready for review
Scope: one stable generated debug app per worktree

Related contracts:

- [Terminal runtime distribution](../2026-07-22-terminal-runtime-distribution/2026-07-22-terminal-runtime-distribution.md)
- [Swift build-slot containment](../2026-07-22-swift-build-slot-containment/2026-07-22-swift-build-slot-containment.md)

## Decision

Replace the timestamp/PID generation layout:

```text
~/.agentstudio-db/<worktree-code>/apps/
  app-<timestamp>-<pid>/
    AgentStudio Debug <worktree-code>.app
```

with one stable published app per worktree:

```text
~/.agentstudio-db/<worktree-code>/apps/
  AgentStudio Debug <worktree-code>.app
```

Bundle construction may use one disposable staging directory while assembling
and signing the replacement. Staging is not a retained app generation: it is
removed after success or failure.

No historical debug app copies are retained. There is no “newest two” policy,
no rollback collection, and no timestamp/PID directory created for every
successful launch.

## Product Intent

Generated debug apps live outside the Documents-based worktree so launching the
app does not itself require reading the runnable bundle from Documents. That
location remains.

The storage defect is the per-launch timestamp/PID parent. Every launch creates
another complete app and nothing removes it. On 2026-07-22, one worktree had
262 generated apps consuming about 23 GB.

The desired steady state is one published debug app per worktree, not a retained
history of launch artifacts.

## Current-State Evidence

At `5cf627ee`, `scripts/run-debug-observability.sh` already establishes the
preconditions needed for stable replacement:

- the worktree has a deterministic four-character debug identity;
- the launcher checks the state-file process, direct executable process, and
  matching debug bundle identity before building;
- it refuses to continue while that worktree's AgentStudio debug app is
  running;
- it creates the complete signed app before launching it;
- it copies bundled zmx to the stable
  `~/.agentstudio-db/<worktree-code>/bin/zmx` path;
- it launches AgentStudio with `AGENTSTUDIO_ZMX_PATH` pointing to that stable
  zmx copy.

The timestamp/PID parent is therefore not the runtime-isolation boundary.
Worktree identity, the data root, the zmx root, and the stable zmx path provide
that isolation.

## Boundary and Separability Map

```text
Swift build product
       |
       v
disposable same-worktree staging
  assemble + sign + verify
       |
       v
stable published app
  ~/.agentstudio-db/<code>/apps/AgentStudio Debug <code>.app
       |
       +--> launch AgentStudio
       `--> copy bundled zmx to ~/.agentstudio-db/<code>/bin/zmx

outside app-artifact ownership
  data, SQLite, zmx sessions/sockets, logs, traces, IPC state
```

The terminal-runtime spec changes the GhosttyKit, resources, and zmx inputs.
The build-slot spec changes which Swift scratch tree supplies the executable.
Neither creates another published debug app path.

## Stable Publication Contract

Before replacing the stable app, the launcher must complete its existing
same-worktree process preflight. If it cannot prove that the matching
AgentStudio debug app is idle, it fails without changing the published app.

The replacement flow is:

1. assemble, embed zmx and resources, sign, and verify in disposable staging;
2. preserve the last complete published app until staging verification passes;
3. atomically replace the stable published app;
4. launch only the stable published path;
5. remove disposable staging on every exit path.

A failed build, copy, signing operation, or verification must not leave a
partially assembled app at the stable path.

`AGENTSTUDIO_DEBUG_ARTIFACT_DIR` remains an explicit caller-owned override for
test or diagnostic use. It does not change the default stable publication
contract.

## Requirements

| ID | Requirement |
| --- | --- |
| DA-01 | Publish exactly one default debug app at `~/.agentstudio-db/<worktree-code>/apps/AgentStudio Debug <worktree-code>.app`. |
| DA-02 | Do not create a retained timestamp/PID app directory for each launch. |
| DA-03 | Preserve the deterministic debug identity, data root, zmx root, and stable `bin/zmx` runtime path. |
| DA-04 | Refuse replacement while the matching AgentStudio debug app is running or process state cannot be classified. |
| DA-05 | Build and verify in disposable staging before atomically replacing the stable app. |
| DA-06 | Remove disposable staging after both successful and failed publication attempts. |
| DA-07 | Default publication retains no prior published debug app copies. |
| DA-08 | Stable publication never changes data, databases, zmx state, sockets, `bin/zmx`, logs, traces, runs, IPC state, or beta/stable apps. |
| DA-09 | Keep caller-owned artifact overrides outside the default stable-publication contract. |

## Tradeoffs

### Gain

- normal disk use is one debug app per worktree;
- the runnable app remains outside Documents;
- replacement cannot expose a partially constructed bundle.

### Cost

- the launcher cannot publish a replacement while that worktree's debug app is
  running;
- safe publication requires disposable staging and an atomic replacement step.

## Explicit Non-Goals

- Retaining two or more recent debug apps.
- Keeping rollback generations.
- Moving the debug app into the worktree.
- Moving or redesigning the debug data root.
- Solving general Documents-folder TCC authorization.
- Cleaning persistent AgentStudio or zmx state.
- Cleaning previously accumulated timestamp/PID app directories.
- Changing Swift build slots or terminal-runtime distribution.

## Proof Expectations

The implementation plan must include:

- repeated default launches proving the published app path remains identical
  and the `apps` root does not grow;
- failure injection before publication proving the previous complete app
  remains intact and staging is removed;
- running-app refusal proof showing the stable app is unchanged;
- app signature and launch proof after atomic replacement;
- proof that the launched process uses the stable app path and stable
  `AGENTSTUDIO_ZMX_PATH`;
- sentinel/hash proof that data, SQLite, `z`, `bin`, sockets, logs, traces,
  runs, IPC state, and unknown entries remain untouched.

## Open Decisions

None.
