# 2026-07-04 — Bridge scroll-loading handoff (fresh-session debug packet)

Status at handoff (~08:50 EDT): the LIVE symptom **"fast scroll does not load
all revealed files"** has survived FIVE green-tested fixes. Everything else
from the last 24h landed and holds. This packet exists so a fresh session can
attack the survivor with clean eyes, full priors, and the instruments we built.

## The goal (verbatim standards)

> get review view and file view to work stably with great ux and scroll until
> the user is satisfied by their standards: good response time, no jitter, all
> switching and button views working.

North star (user, 2026-07-04): **DiffsHub scrolls a huge diff top-to-bottom
butter-smooth. That is the bar.** Pierre reference checkout (read-only):
`/Users/shravansunder/Documents/dev/open-source/libs-react/pierre`.

## THE SURVIVING BUG

Review view, fast momentum scroll through many files: some revealed files stay
as placeholders. Clicking a file always loads it. Confirmed still present by
the user on build `7ef09009` (which contains all five fixes below).

### CRITICAL: do not trust old paint metrics
A fresh-Fable adversarial analysis proved every pre-`83bcb2d3` "paint ratio"
(17:1, 28:5) measured **click count, not painting** — 13 separate telemetry
signals were all locked to the selected item. Cross-session table in its
report. Honest instruments exist ONLY since `83bcb2d3`:
- `performance.bridge.web.code_view_item_materialize` now fires for ALL items
  (`agentstudio.bridge.selected=false` for visible paints).
- `window.__bridgeVisibleHydrationDiscardProbe` records any ready-result
  discard in the hydration hook. **NOBODY HAS READ THIS PROBE FROM A LIVE
  FAILING SESSION YET.** That is the single highest-value next step.

### The decisive experiment (do this first)
1. Launch: `AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*"
   AGENTSTUDIO_STARTUP_WATCH_FOLDER="$PWD" mise run run-debug-observability -- --detach`
2. Have the user (or Peekaboo with PID targeting) fast-momentum-scroll until a
   file visibly fails to load.
3. Attach Safari Web Inspector (Develop menu → the debug app's WKWebView) and
   read `window.__bridgeVisibleHydrationDiscardProbe`,
   `window.__bridgeFrameJankProbe`, and count DOM placeholders vs items.
4. Cross-read the session in VictoriaLogs (query pattern below): fetches by
   interest vs `code_view_item_materialize` with `selected=false`.
   - Probe non-empty → discard path still leaks (fix #5 incomplete).
   - Probe empty + fetches ≫ selected=false materializes → loss is between
     resource-map and panel apply (controller/props/render loop).
   - Probe empty + fetch count itself low → demand/sweep still under-firing
     (hydration hook not demanding all revealed items).

## Five fixes that did NOT clear the live symptom (all committed, all unit-green)

| # | Commit | Theory | Why it failed live |
|---|--------|--------|--------------------|
| 1 | `26bd1992` | Aborted visible demands never re-arm (W6) | Real bug, fixed; pause path doesn't abort, so the discard class remained |
| 2 | in `77ba12a9` | Settle sweep held one recovery slot | Real bug, fixed; same reason |
| 3 | in `77ba12a9` | Scroll-jump: gate materialization to settled window | Fixed jumps, CAUSED paint starvation (17 fetches:1 paint measured — later shown partially artifact) |
| 4 | `18d2d839` | Viewport-honest gate (live range, strictly-above defer) | Still starved; getRenderedItems() returns [] pre-window → deferred everything |
| 5 | `83bcb2d3` | **Pause-discard cure** (analyst-specified): pause deletes 'loading' state → completed fetches fail contentKey guard → READY results silently discarded during macOS momentum tails (~1-1.5s). Pause now gates only load starts; ready always lands; no empty-map swap; prune keeps ready-unapplied; gates removed; Pierre owns sizing | **USER SAYS STILL BROKEN.** Either another leak below the fixed guard, or the demand side never fires for all revealed items, or delivery/apply loses them. The probe read (above) discriminates. |

Analyst's full report (root-cause ranking, file:line map of every conditional
between fetch-success and applyItemUpdate, refuted cacheKey-collision theory,
Pierre citations): it arrived as a teammate message in the prior session; key
file:line anchors are reproduced in the fix commits' messages. Core files:
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
  (+ `-support.ts`) — demand/pause/prune/sweep + discard probe
- `BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts` —
  resources → panel
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
  (+ `-support.tsx`) — materialization loop, applyItemUpdate, paint telemetry
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.ts`
  — item shapes, placeholder line counts (post-collapse-fix)
- Reference: Pierre `CodeView.ts` (syncItemRecord ~2012, getRenderedItems
  ~1420, anchor capture ~2461-2585), `VirtualizedFile.ts` (~463-499 sizing).

## Everything else that landed today (24h, commits `d7e0a5c0`..`7ef09009`, all pushed)

- Both full-pyramid smoke render proofs PASS (review journey + file-view
  mode-idle). Verifiers rebuilt honest: emitted-vocabulary assertions,
  ×2-role content bounds + quiescence, non-stale drop gates, RAF-liveness
  (`raf_alive`) SKIP-with-label for occluded runs, positive final-generation
  evidence verdict, demand-honest tree coverage. Smoke gotchas memory updated.
- Real telemetry bugs fixed: burst-throttle flush loss; selected_content_dropped
  had no native contract; THREE OTLP projection-allowlist scrubs (recurring
  trap — every new attr needs `AgentStudioOTLPTraceProjection.swift`);
  review-startup contract drift; selected-only paint telemetry.
- Apply path (#50 phase 1): parse-once-at-intake + batched merges —
  5k apply 728→41.8ms, 1k delta 760→7.8ms (bench-pinned red→green).
- DiffsHub parity: worker pool 2→3; Pierre render-cache keys were
  `generation:revision`-embedded → zero cache residency; now content-addressed
  and hitting. Per-instance render cache verified unbroken.
- Priority: browser interest tier rides `?interest=` on content URLs
  (excluded from lease identity); `BridgeContentDemandAdmission` makes
  background fill yield to selected/visible + token-bucket pacing + cool-down.
  NOTE: startup fill still sweeps the whole package (2340+ loads) = #42/#51.
- Scroll-jump: fixed via removing app-side height churn; placeholders were
  rendering minimized because WE sent `collapsed:true` (Pierre never
  auto-collapses) — now expanded skeletons with real line counts; expand fires
  foreground-priority demand (`7ef09009`).
- Crashes: (a) OTLP backpressure class — queue 8192/batch 1024/1s pinned +
  `BridgeTelemetryAdmissionController` caps high-volume web events 32/s.
  STILL DIED once after that under (b): **topology storm — closing 4 bridge
  tabs emitted 32,767+ `performance.topology.repo_and_worktree` events in
  <3min (~180/s)**, exporter C++-exception path fired even while dropping
  gracefully. Storm lane IN FLIGHT at handoff: `task-mr6cod61-yz1gzb`
  (emission idempotency + rate bound + upstream C++ path identification).
  If it landed after this doc: check `git log`, else adopt the lane.
- Tree-click "swallow" was actually selection LATENCY (handler ran, command
  issued, late_match=true) — smoke now measures polls_to_selection_match.
  Post-scroll click→selection latency spikes feed #21.
- RAF starves in occluded windows (unattended runs) — painted/TTFI absence
  overnight was environmental; both instruments proven live in a visible
  session (first honest click_to_paint sample: 561ms cold → #21 target).

## Task board essentials (fresh session: TaskList for full state)

- #56 pause-discard cure — landed but user says symptom persists → REOPEN
  as the surviving-bug investigation (this packet).
- #50 in_progress: phase 1 done; remaining W3 frame-cap parity, worker-offload
  option, FileStream streaming-to-worker protocol idea (user).
- #21 p99 click→paint (<100ms; first sample 561ms cold), #40 ContentIdentity
  authority, #41 mock-fidelity (hostile mocks — FIVE mock-politer-than-live
  failures now), #42 pane-visibility gating, #43 two-phase delivery (serial
  drain still shared), #49 transport lifecycle, #51 production-side demand
  (startup sweep), #16 S2+ remainder, #33 speculation tier.
- Storm lane adoption (above) if unlanded.

## Working with codex (operating manual, hard-won)

- Dispatch: `node ~/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs task --background --fresh --write --model gpt-5.5 --effort high|xhigh "$(cat prompt.txt)"`
  (write prompt to a scratch file; NO backticks in prompts — shell eats them).
- Poll job state yourself (never a relay agent for dispatch):
  `~/.claude/plugins/data/codex-openai-codex/state/agent-studio.bridge-start-7d4f5d4c4c6f7f00/jobs/<task>.json`
  (`status` field) and the final report is the last `Final output` block in
  `<task>.log`. `--resume-last` only when exactly one lane is active.
- Lane discipline: one writer per file family; declare do-NOT-touch lists in
  every prompt; codex CANNOT run git writes here (worktree), launch apps, or
  reach Chromium — orchestrator owns commits/launches/browser runs.
- Every lane: red-first proof with exit codes; swiftlint file caps (1000
  lines / 800 type body / 100 func body) and BridgeWeb source-structure caps
  (1000) are hard gates lanes must self-satisfy; new telemetry attrs MUST be
  added to the OTLP projection allowlist + red-first projection test.
- Gates run UNPIPED (a `| tail` swallowed a red gate exit code once today).
- `cd BridgeWeb` persists across Bash calls — always return to repo root.
- Full-suite vitest: `pnpm --dir BridgeWeb exec vitest run` (118 files/~835).
  Scaling bench is wall-clock sensitive — verify alone if red under load.

## Infra quickrefs

- Launch (safe tags, crash-resistant): see decisive experiment above. Never
  `pkill AgentStudio`; kill the specific PID from
  `tmp/debug-observability/latest-observability.env`.
- VictoriaLogs: `curl -sG http://127.0.0.1:9428/select/logsql/query
  --data-urlencode 'query=agent.proof.marker:="<marker>" _msg:<event> | stats by (field) count() hits'`.
  Marker field is `agent.proof.marker` (exact `:=`). Attr fields are full
  dotted names (`agentstudio.bridge.content.interest` etc.).
- Smokes: launch with `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=
  bridge-review-observability-smoke` (or `bridge-review-to-file-view-…`), then
  `mise run verify-bridge-review-journey-smoke` / `verify-bridge-mode-idle-smoke`.
  Verifier summaries print `raf_alive`; occluded runs SKIP paint assertions.
- Two crash signatures in run logs: `queue was full`/`dropped_count=` then
  `C++ exception handling detected` = telemetry pressure (relaunch safe tags);
  check topology storm counts before blaming new code.
- Untracked leftovers `artifacts/` `plugins/` are SwiftPM build inputs,
  gitignored today — never commit, never delete casually.
- Commits today are `--no-gpg-sign` (1Password signing broken) — re-sign later.

## Memory files worth loading (auto-memory dir)

`project_bridge_fault_lines_content_identity` (F1/F2/F3 + instruments-never-
gate-UX), `project_bridge_file_view_e2e_smoke_gotchas` (verifier drift, RAF
occlusion, marker attribution), `feedback_subagent_model_floor` (codex
contract + tracker-lag hazard), `project_pierre_scroll_anchor_gotchas`,
`feedback_holistic_redesign_over_patches` (five patches on one seam = redesign
signal — arguably where the surviving bug now sits).

## FINAL DIAGNOSIS (user-converged at handoff): there is no queue

Five independent schedulers each own a slice of loading; none owns ordering:

    browser demand scheduler ─┐
    hydration hook            ├─ each has LOCAL priority/pause/limits
    (pause/prune/sweep)       │
    native admission gate     │        NOBODY owns end-to-end order
    native background fill    │
    serial WebView delivery ──┘

Consequences (all observed live): priority inversions between stages; five
green-tested fixes failing live (no single testable seam — behavior emerges
from stage interactions; mocks cannot be faithful to five systems); the
topology storm (emitters with no rate ownership).

## Recommended next-session agenda (design-first, not patch #6)

1. Run the decisive probe experiment (top of this doc) — 30 minutes, tells the
   new session which stage loses the surviving bug.
2. DESIGN: one unified demand pipeline — single queue, single priority order
   (selected > visible > nearby > speculative > background), single owner from
   intent to painted, cancellation/re-arm as first-class transitions.
   Inputs: docs/specs/bridge-viewer-transport/performance-demand-lanes.md
   (R20-R31 already specify most of the contract), tasks #43 (two-phase
   delivery) + #51 (production-side demand) + #40 (ContentIdentity), the cold
   audit (docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md),
   and DiffsHub/Pierre as the working reference implementation.
3. The unified pipeline is what makes DURABLE tests possible: one seam, one
   state machine, scenario tables from the demand-lane spec run against the
   real component, hostile mock rules from #41.
4. Draw it with the user before building (their explicit ask).

## USER DESIGN DIRECTIVE for the unified pipeline (verbatim intent, 2026-07-04)

"What's in screen that has to be loaded is ALWAYS first. An immediate queue
lane that gets inserted ASAP with what can fit in screen for review etc."

Design translation: an IMMEDIATE lane at the head of the single queue —
computed from the visible window the instant it changes (what fits on screen),
inserted ahead of everything, preempting in-flight lower-tier work. Order:
immediate(viewport) > selected(click) > nearby > speculative > background.
Viewport membership is recomputed on every range change; items leaving the
viewport demote, items entering promote — one owner, one ordering, end to end.
This is the organizing principle for next-session agenda item 2.
