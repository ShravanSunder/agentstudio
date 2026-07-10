# Ghostty Action Admission Manifest

Date: 2026-07-10
Status: normative companion contract
Applies to: pinned Ghostty `332b2aef` and candidate
`7e02af87980bfdaad6d393b985d35c917476878e`

This manifest supplies the exhaustive product disposition required by the
[Ghostty Host Boundary and Terminal Interaction Fairness Spec](ghostty-terminal-interaction-fairness.md).
It covers every action tag in the pinned header plus candidate-only
`GHOSTTY_ACTION_SELECTION_CHANGED`. Generated Swift vocabulary, routing, and
tests must be mechanically complete against the selected header; this document
does not authorize a hand-maintained numeric-tag compatibility shim.

## Rules Shared By Every Row

Callback entry first acquires the current app/surface lease, stamps the host
origin scope and generation, and copies every ephemeral payload needed by the
row. A row may then use only its declared policy. An unknown tag, a tag missing
from this manifest, a disallowed origin, an invalid generation, or an invalid
payload returns the row's safe fallback disposition, performs no delayed
product effect, and records only a privacy-safe reason/count. The ordinary safe
fallback is `false`; a source-proven vendor fallback may instead require
`policyConsumedTrue` so denial remains denial. A vendor cutover with a missing
or duplicate row fails before runtime acceptance.

`appTick` and `directMainActorHostCall(callKind)` are host-scoped MainActor
origins. `foreignVendorThread` means no live host origin scope, even if the
callback happens to run on the main thread.

The policy codes below provide the descriptor fields repeated across rows:

| Policy | Allowed origins and synchronous return | Plane, capacity, ordering, replay, and default-host behavior |
| --- | --- | --- |
| `HC` host command | host-scoped only; `hostCompletedTrue` only after the targeted command owner synchronously resolves and performs the action; otherwise `hostDeclinedFalse`; foreign callbacks are rejected and not delivered | one exact `TerminalCommandIntent` to the named owner; no queue, global bus, or replay; ordered in the calling host scope |
| `HS` host suppression | all origins; `hostCompletedTrue` is the complete, deliberate AgentStudio policy effect; no task or later mutation is allowed | no product plane, queue, replay, or consumer work; sampled diagnostic count only |
| `LD` decline | all origins; `hostDeclinedFalse`; no later effect | no product plane, queue, replay, or consumer work; sampled diagnostic count only |
| `LS` local snapshot | host-scoped or foreign; `hostCompletedTrue` only after a copied value commits to the current generation's bounded latest-by-key slot; failure returns `false` | one slot per `(surface generation, tag, subkey)`; current snapshot reads only; no raw global fact or history replay; MainActor publication may observe the committed slot later |
| `MA` MainActor presentation | host-scoped only; `hostCompletedTrue` only after the MainActor presentation owner applies the effect; foreign callbacks return `false` and are not delivered | pane-local current presentation; no queue, global fact, or replay |
| `SA` snapshot plus deduped fact | host-scoped or foreign; `hostCompletedTrue` after the generation-bound current snapshot commits; invalid/oversized input returns `false` | one latest bounded snapshot plus a deduped semantic fact only for the named non-source consumer; snapshot sync, not history replay; equal intermediate values contract |
| `AI` activity input | host-scoped or foreign; `hostCompletedTrue` only after bounded accumulator/latest-state admission; invalid or unavailable generation returns `false` | one pane-local accumulator/window or latest key; no raw global fact/replay; only the activity projector may emit lower-rate semantic edges |
| `EF` exact fact | host-scoped or foreign; `exactRequestAcceptedTrue` only after a generation-bound non-evictable fact request is admitted; saturation/stale/invalid returns `false` | exact per-surface order; fact-specific bounded replay only where named; cannot share capacity with presentation samples |
| `NS` notification request | host-scoped or foreign; `exactRequestAcceptedTrue` only after bounded payload validation, abuse-policy admission, and exact generation-bound request admission; rejection returns `false` | targeted notification/inbox owner; no raw terminal string in routine replay or telemetry; product history is inbox-owned |
| `PR` privileged request | host-scoped only; `hostCompletedTrue` only after the named MainActor owner validates authority/policy and performs the effect; foreign callbacks return `false` and are not delivered | targeted owner only; no global bus/replay; resulting low-rate audit fact is separate and content-free |
| `PC` policy-consumed privileged request | a recognized tag always returns `policyConsumedTrue` after a synchronous allow/deny decision because vendor `false` would invoke a fallback; only a live source-verified user-intent host scope may perform the effect; invalid/stale/foreign/no-intent input is deliberately denied and consumed | targeted MainActor policy owner only; denial schedules no task and suppresses vendor fallback; no global bus/replay or raw-value telemetry |
| `VP` vendor-fallback presentation | host-scoped only; `hostPresentedTrue` only after a current-generation equivalent user-visible presentation commits synchronously; otherwise `hostDeclinedFalse` deliberately selects the source-verified vendor terminal fallback | lifecycle/current-state and exact fact admission are separate from the Boolean; accepting a fact cannot suppress the fallback; foreign/stale/unavailable presentation returns false without delayed host presentation |
| `SR` secure-input request | host-scoped only; return `true` only after `SecureInputOwner` commits requested state, advances the capture fence, and completes the OS transition successfully; failure returns `false` while preserving conservative indeterminate state; foreign callbacks are rejected | app-global security owner; exact per generation; current state plus controlled transition fact, never raw terminal content |

Numeric capacities for calibrated bounded gates remain implementation
calibration inputs, but the semantic capacities above are fixed: `LS`/`SA` are
one latest slot per declared key, `AI` is one bounded pane-local accumulator,
and `EF`/`NS` cannot evict an accepted exact request.

For the selected vendors, the generic binding-result family uses the callback
Boolean as input-consumption state: `true` means the binding performed and
consumes it; `false` can make a performable binding behave as absent and permit
normal key encoding. The source-verified family is `UNDO`, `REDO`,
`START_SEARCH`, `COPY_TITLE_TO_CLIPBOARD`, `PROMPT_TITLE`, `SET_TITLE`,
`SET_TAB_TITLE`, `NEW_TAB`, `CLOSE_TAB`, `GOTO_TAB`, `MOVE_TAB`, `NEW_SPLIT`,
`GOTO_SPLIT`, `GOTO_WINDOW`, `RESIZE_SPLIT`, `EQUALIZE_SPLITS`,
`TOGGLE_SPLIT_ZOOM`, `RESET_WINDOW_SIZE`, `TOGGLE_MAXIMIZE`,
`TOGGLE_FULLSCREEN`, `TOGGLE_WINDOW_DECORATIONS`, `TOGGLE_TAB_OVERVIEW`,
`FLOAT_WINDOW`, `SECURE_INPUT`, `TOGGLE_COMMAND_PALETTE`,
`TOGGLE_BACKGROUND_OPACITY`, `SHOW_ON_SCREEN_KEYBOARD`, `INSPECTOR`, and
`CLOSE_WINDOW`. Each row's policy deliberately owns that consequence: `HS`
consumes, `LD` permits fallthrough, and another policy returns true only after
its synchronous contract is satisfied.

## Exhaustive Tag Disposition

`P+C` means the tag exists in both selected builds. `C` means candidate-only.
Every tag appears exactly once.

| Action tag | Build | Policy | Named owner / product output | Rate | Payload and sensitivity override |
| --- | --- | --- | --- | --- | --- |
| `GHOSTTY_ACTION_QUIT` | P+C | `HS` | AgentStudio app lifecycle intentionally suppresses Ghostty-owned quit | low | no payload |
| `GHOSTTY_ACTION_NEW_WINDOW` | P+C | `HS` | AgentStudio window lifecycle intentionally owns/suppresses this binding | low | no payload |
| `GHOSTTY_ACTION_NEW_TAB` | P+C | `HC` | pane/workspace command owner | low | no payload |
| `GHOSTTY_ACTION_CLOSE_TAB` | P+C | `HC` | pane/workspace command owner | low | bounded close-mode enum |
| `GHOSTTY_ACTION_NEW_SPLIT` | P+C | `HC` | pane/workspace command owner | low | bounded direction enum |
| `GHOSTTY_ACTION_CLOSE_ALL_WINDOWS` | P+C | `HS` | AgentStudio app/window lifecycle suppression | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_MAXIMIZE` | P+C | `HS` | AgentStudio window lifecycle suppression | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_FULLSCREEN` | P+C | `HS` | AgentStudio window lifecycle suppression | low | bounded mode enum |
| `GHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW` | P+C | `HS` | unsupported host surface intentionally consumed | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS` | P+C | `HS` | AgentStudio window chrome policy | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL` | P+C | `HS` | unsupported host surface intentionally consumed | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE` | P+C | `HS` | AgentStudio command-bar ownership; Ghostty binding suppressed | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_VISIBILITY` | P+C | `HS` | AgentStudio window visibility ownership | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_BACKGROUND_OPACITY` | P+C | `HS` | unsupported host surface intentionally consumed | low | no payload |
| `GHOSTTY_ACTION_MOVE_TAB` | P+C | `HC` | pane/workspace command owner | low | bounded signed delta |
| `GHOSTTY_ACTION_GOTO_TAB` | P+C | `HC` | pane/workspace command owner | low | bounded target enum |
| `GHOSTTY_ACTION_GOTO_SPLIT` | P+C | `HC` | pane/workspace command owner | low | bounded direction enum |
| `GHOSTTY_ACTION_GOTO_WINDOW` | P+C | `HS` | AgentStudio window lifecycle suppression | low | bounded target enum |
| `GHOSTTY_ACTION_RESIZE_SPLIT` | P+C | `HC` | pane/workspace command owner | interactive | bounded direction and amount |
| `GHOSTTY_ACTION_EQUALIZE_SPLITS` | P+C | `HC` | pane/workspace command owner | low | no payload |
| `GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM` | P+C | `HC` | pane/workspace command owner | low | no payload |
| `GHOSTTY_ACTION_PRESENT_TERMINAL` | P+C | `HS` | AgentStudio pane/window presentation ownership | low | no payload |
| `GHOSTTY_ACTION_SIZE_LIMIT` | P+C | `LS` | `SurfaceGeometryCommitOwner` constraint snapshot | burst | bounded numeric geometry only |
| `GHOSTTY_ACTION_RESET_WINDOW_SIZE` | P+C | `HS` | AgentStudio window geometry ownership | low | no payload |
| `GHOSTTY_ACTION_INITIAL_SIZE` | P+C | `LS` | `SurfaceGeometryCommitOwner` initial-size snapshot | burst | bounded numeric geometry only |
| `GHOSTTY_ACTION_CELL_SIZE` | P+C | `LS` | `SurfaceGeometryCommitOwner` cell-size snapshot | burst | bounded numeric geometry only |
| `GHOSTTY_ACTION_SCROLLBAR` | P+C | `AI` | pane-local terminal activity projector plus current scrollbar snapshot | high | bounded numeric rows/offset; no raw bus event |
| `GHOSTTY_ACTION_RENDER` | P+C | `HS` | Ghostty-owned renderer/display-link path; no host draw loop | high | no payload |
| `GHOSTTY_ACTION_INSPECTOR` | P+C | `HS` | unsupported Ghostty inspector UI intentionally consumed | low | bounded inspector enum |
| `GHOSTTY_ACTION_SHOW_GTK_INSPECTOR` | P+C | `HS` | not applicable to macOS embedder | low | no payload |
| `GHOSTTY_ACTION_RENDER_INSPECTOR` | P+C | `HS` | no host inspector renderer | burst | no payload |
| `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` | P+C | `NS` | notification/inbox owner | abuse-limited | bounded terminal-controlled title/body; local product data only |
| `GHOSTTY_ACTION_SET_TITLE` | P+C | `SA` | terminal snapshot plus pane/window-title consumer | medium | bounded terminal-controlled string; value excluded from routine logs/OTLP |
| `GHOSTTY_ACTION_SET_TAB_TITLE` | P+C | `SA` | terminal snapshot plus pane-title consumer | medium | bounded terminal-controlled string; value excluded from routine logs/OTLP |
| `GHOSTTY_ACTION_PROMPT_TITLE` | P+C | `LD` | no accepted AgentStudio prompt-title product owner | low | bounded scope enum; no delayed request |
| `GHOSTTY_ACTION_PWD` | P+C | `SA` | terminal snapshot plus pane/worktree-context consumer | medium | bounded untrusted path string; no authority; value excluded from routine logs/OTLP |
| `GHOSTTY_ACTION_MOUSE_SHAPE` | P+C | `MA` | surface cursor owner | interactive | bounded cursor enum |
| `GHOSTTY_ACTION_MOUSE_VISIBILITY` | P+C | `MA` | surface cursor owner | interactive | bounded visibility enum |
| `GHOSTTY_ACTION_MOUSE_OVER_LINK` | P+C | `LS` | pane-local hover snapshot | high | bounded untrusted URL string; no open authority; no routine value export |
| `GHOSTTY_ACTION_RENDERER_HEALTH` | P+C | `EF` | terminal health snapshot and unhealthy-edge/inbox consumers | low | bounded health enum; transition facts only |
| `GHOSTTY_ACTION_OPEN_CONFIG` | P+C | `HS` | AgentStudio settings/config ownership | low | no payload |
| `GHOSTTY_ACTION_QUIT_TIMER` | P+C | `HS` | AgentStudio app lifecycle suppression | low | bounded timer enum |
| `GHOSTTY_ACTION_FLOAT_WINDOW` | P+C | `HS` | unsupported Ghostty window mode intentionally consumed | low | bounded mode enum |
| `GHOSTTY_ACTION_SECURE_INPUT` | P+C | `SR` | app-global `SecureInputOwner` | low | bounded mode enum; security epoch and surface generation required |
| `GHOSTTY_ACTION_KEY_SEQUENCE` | P+C | `LS` | pane-local key-sequence snapshot | interactive | bounded key/modifier data; no global event |
| `GHOSTTY_ACTION_KEY_TABLE` | P+C | `LS` | pane-local key-table snapshot | interactive | bounded table enum/name; no routine name export |
| `GHOSTTY_ACTION_COLOR_CHANGE` | P+C | `LS` | pane-local terminal color snapshot | burst | bounded kind/RGB values |
| `GHOSTTY_ACTION_RELOAD_CONFIG` | P+C | `LD` | no accepted asynchronous reload owner in this contract | low | bounded soft flag; no delayed request |
| `GHOSTTY_ACTION_CONFIG_CHANGE` | P+C | `LS` | pane-local current config revision/invalidation snapshot | low | no terminal content |
| `GHOSTTY_ACTION_CLOSE_WINDOW` | P+C | `HS` | AgentStudio app/window lifecycle suppression | low | no payload |
| `GHOSTTY_ACTION_RING_BELL` | P+C | `EF` | terminal activity/inbox bell fact | low | no payload; bounded fact replay |
| `GHOSTTY_ACTION_SELECTION_CHANGED` | C | `LS` | pane-local selection epoch/accessibility snapshot only | high | no selection text or ranges in product event/replay/telemetry |
| `GHOSTTY_ACTION_UNDO` | P+C | `LD` | no accepted AgentStudio terminal undo owner | low | no delayed request |
| `GHOSTTY_ACTION_REDO` | P+C | `LD` | no accepted AgentStudio terminal redo owner | low | no delayed request |
| `GHOSTTY_ACTION_CHECK_FOR_UPDATES` | P+C | `HS` | AgentStudio release/update ownership | low | no payload |
| `GHOSTTY_ACTION_OPEN_URL` | P+C | `PC` | validated open-URL policy owner; Ghostty fallback must always be consumed | abuse-limited | bounded untrusted URL/kind; effect requires current source-verified user-intent token; denial/invalid/stale/foreign returns true without opening; no replay |
| `GHOSTTY_ACTION_SHOW_CHILD_EXITED` | P+C | `VP` | terminal lifecycle/health presentation; separate exact lifecycle/inbox fact | low | bounded exit metadata only; true only after equivalent visible host presentation, false intentionally preserves Ghostty's terminal-text fallback |
| `GHOSTTY_ACTION_PROGRESS_REPORT` | P+C | `AI` | pane-local progress snapshot and error-edge projector | burst | bounded state/progress; only error transition may become a fact |
| `GHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD` | P+C | `HS` | not applicable to macOS embedder | low | no payload |
| `GHOSTTY_ACTION_COMMAND_FINISHED` | P+C | `EF` | command lifecycle, activity, and inbox consumers | low | bounded exit/duration; exact ordered fact with bounded fact replay |
| `GHOSTTY_ACTION_START_SEARCH` | P+C | `LS` | pane-local search snapshot | interactive | bounded search string; never global/replayed/exported |
| `GHOSTTY_ACTION_END_SEARCH` | P+C | `LS` | pane-local search snapshot | interactive | no payload |
| `GHOSTTY_ACTION_SEARCH_TOTAL` | P+C | `LS` | pane-local search snapshot | high | bounded count |
| `GHOSTTY_ACTION_SEARCH_SELECTED` | P+C | `LS` | pane-local search snapshot | high | bounded index |
| `GHOSTTY_ACTION_READONLY` | P+C | `LS` | pane-local terminal mode snapshot | low | bounded mode enum |
| `GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD` | P+C | `PR` | clipboard security/presentation owner | low | bounded current title copied only after user action/policy; no bus/replay |

## Mechanical And Behavioral Proof

The selected header's action-tag set must equal the manifest set exactly.
Pinned proof expects 65 rows marked `P+C`; candidate proof expects those rows
plus the one `C` selection row. Swift `GhosttyActionTag.allCases`, the generated
header, router descriptors, and this manifest have no missing or duplicate
tags. Numeric values are compiled from the selected header rather than inferred
from position.

Focused behavior proof exercises at least one row per policy plus every
privileged (`PR`/`PC`/`SR`), fallback (`VP`), exact (`EF`/`NS`), command
(`HC`), and suppression (`HS`) row. It verifies direct/tick/foreign origin,
Boolean return, stale generation, saturation, content/export disposition, and
the absence of a delayed host/product effect after `false`; the row-declared
vendor fallback or normal key encoding remains intentional source behavior.
Generic binding-result proof also verifies the matching consume-versus-key-
encoding outcome for every tag in that source-verified family.

`OPEN_URL` separately proves authorized open and every denial class (invalid
payload, stale generation, disallowed origin, missing user intent, policy
denial) return the fallback-suppressing value while neither Ghostty
`internal_os.open` nor the host opener executes. `SHOW_CHILD_EXITED` proves fact
admission alone returns false, a committed equivalent visible host presentation
returns true, and the false branch leaves Ghostty's terminal-text fallback
intact. Candidate selection floods produce one bounded local latest state, zero
selection-content capture, and zero raw global facts.
