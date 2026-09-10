# BridgeWeb component language — Specification

Governing [Requirements](2026-09-07-requirements.md).
Internal realization: [Program Design](2026-09-07-program-design.md).

## Observable difference

```text
Daily user [U3/U4/U5]
  open comparison → search → scan names/metadata → select target
  pain: muted available choices, flattened text, cramped rows
  outcome: readable choices and clear states; unchanged target/commands

Sharing user [U7/U8]
  open Share → choose Pending/All → inspect included comments → Copy/Export
  pain: a count and an empty panel do not reveal what will be shared
  outcome: read-only preview of the selected output set; corrected Pending
  resolution eligibility, with All and output lifecycle preserved
  comparison remains a separate peer drawer, not a nested navigation step

Feature author [U1/U6]
  identify interaction → compose our components → supply domain facts/actions
  pain: shared root leaves visual decisions to each caller
  outcome: standard complete slots; useful feature components stay local
```

```text
Daily user ── pointer/keyboard ──► [BridgeWeb UI]
Feature author ── composition ──► [opaque system]
Reviewer ── rendered evidence ──► [             ]
                                    ├─ File/Review chrome and navigation
                                    ├─ inputs, lists, menus and floating panes
                                    └─ annotation controls and feedback
Outside: transport policy, annotation domain transitions, native shell redesign
```

## Contracts

| ID | Observable obligation | Basis | Proof |
| --- | --- | --- | --- |
| R1 | Equivalent semantics and sizes MUST render with the same typography, internal geometry, paint and state treatment across features and portals. Feature components compose library recipes rather than redefine them. | U1 | V1/V2 |
| R2 | The fixed foundation MUST remain intact. Text-role changes MUST NOT unintentionally alter syntax, annotation fills or native values. | U2 | V1/V2/V5 |
| R3 | Enabled, highlighted, selected, keyboard-focused and disabled states MUST convey distinct facts. Selection retains an accessible state and persistent visual cue beyond hue alone. Opening a menu is not exclusive selection. | U3/U5 | V2/V4 |
| R4 | Primary names and supporting information MUST retain hierarchy across row states without colliding with adjacent rows or indicators. Truncation preserves complete accessible identity. Current/default branch facts remain distinct from selected target. | U3/U4 | V2/V3 |
| R5 | Filtering, keyboard movement, pointer selection, virtual scrolling and focus restoration MUST preserve target identity and existing command behavior. Visible and actionable rows remain aligned after geometry changes. | U4/U5 | V3/V4 |
| R6 | Disabled controls MUST remain inert without whole-control fading. Invalid and focused states retain both error and focus information. Loading, empty and failed states remain truthful; no automatic retry or fallback selection is added. | U3/U5 | V2/V4 |
| R7 | Enabled text MUST reach 4.5:1 contrast and meaningful state/focus indicators 3:1 against the actual composited background. Main/supporting roles MUST remain consistent. Complete compositions, not token names, establish visual coherence. | U3/U6; Requirements inner-control decision | V2/V5 |
| R8 | Mechanical checks MUST cover complete shared visual slots and indirect/nested appearance overrides, while permitting legitimate feature layout and virtual positioning without broad bypasses. | U1/U6 | V1/V3 |
| R9 | Share MUST display every saved comment selected by its current Pending/All output scope, with body and file/range context, and MUST NOT present excluded comments as part of that output set. Pending follows R-ANP-002, including resolved-thread exclusion; All remains unchanged. Preview readiness, counts and output availability MUST remain consistent with the existing revision and eligibility guards. | U7/U5 | V4/V6 |
| R10 | Comparison MUST open in a full-viewer-height floating drawer. Share and Compare MUST be mutually exclusive peers, preserving existing target selection, query cancellation, focus restoration and output-in-progress protection. | U8/U5 | V4/V6 |

Selected plus disabled preserves selected identity without restoring enabled
paint or execution. Keyboard highlight does not commit a value. Focus is an
independent cue. Status colors communicate domain status, not ordinary label
emphasis. Icon-only controls retain accessible labels and action/tooltip identity.

Single-line controls retain the established compact ladder. Descriptive rows
must fit both lines, positive breathing room and indicator clearance. Editors
remain body-text controls. Avatars, status glyphs, drag handles and renderer
metrics are not square action buttons.

## Inner-control treatment

These treatments realize R3/R4/R6/R7 together; they do not change the fixed
surfaces. Another appearance is a shared design revision, not a local override.

| Element | Treatment | Tradeoff |
| --- | --- | --- |
| Inputs | Existing neutral #363636 fill, main entered text and supporting placeholder; one field border. | More explicit field than transparent input; no new hue. |
| Exclusive group track | Transparent over the containing surface, one existing grouping outline. | Removes the gray trough; grouping depends more on outline and alignment. |
| Selected choice | Existing product-blue 15% tint with main-text label; retained check/selected segment boundary. | More readable label than blue-on-blue; blue remains a selection cue, not ordinary text. |
| Hover / keyboard candidate | Existing neutral #454545 highlight, preserving main/supporting text hierarchy. | Clearer highlight than a faint wash. |
| Expanded ghost button, idle | Existing muted #363636 fill; hover remains #454545, with text, focus, disabled and other variant treatments preserved. | A quieter persistent disclosure cue without changing ordinary hover or selected-mode paint. |
| Descriptive row | 44px: 18px primary line + 16px supporting line + 2px gap + 4px top/bottom inset. Plain action rows stay 28px. | Fewer visible two-line rows in exchange for native-role typography and breathing room; existing virtual scrolling remains. |
| Disabled | Explicit faint foreground at opacity 1, neutral inactive paint, selected identity retained. | Distinction relies on deliberate roles/indicators, not fading the whole control. |

The earlier 36px trial used 11/9px text. Matching native list roles uses 13/12px
text and therefore needs 44px with the same breathing room. Keeping ordinary
rows at 28px avoids increasing every menu to solve a descriptive-list problem.
Browser/native observation tests this treatment against the stated targets; it
does not authorize silently changing values or lowering contrast requirements.

Individual file headers and code-view scroll tracks use #27282B. File headers
remain 40px high, without a bottom divider or its sticky-state duplicate; the
top boundary is retained. Open in Files remains the same 24px action with an
outlined appearance. Scrollbar thumb paint, size and other scrollbar contexts
are unchanged. These treatments do not change code line geometry.

## Share preview and comparison drawers

Share remains an output panel with its current Pending/All scope control and
Copy/Export actions. Its body shows the included saved message text with enough
file and line/range context to identify each comment. It is read-only: no reply,
edit, resolve or jump-to-code actions are added. A preview is not an output
operation and does not mark anything handled or viewed merely by being shown.
An empty selected set is shown explicitly. Unknown or unreconciled selection is
not presented as ready to copy; existing output readiness and failure behavior
remain authoritative. Successful output retains the existing dismissal behavior.

Eligibility is owned by
[R-ANP-002 and R-ANP-008](../2026-08-24-worktree-annotation-new-pending/2026-08-24-specification.md#r-anp-002--exact-pending-membership),
not redefined by the preview. Resolved threads therefore disappear from Pending
counts, badges and new Pending output, without changing handled or viewed state.
All still includes their draft-free saved comments; immutable History Repeat is
not a new-output scope and retains its existing contract.

The preview shows saved message text, not an editor or a second selectable list.
Preserve body text and line breaks, identify author and file/range, and include
eligible outdated/unavailable comments using their projected original context.
The preview is the same selected comment set, not a byte-for-byte display of the
export document's metadata or source excerpts. Last-known content may remain
visible during convergence only as unconfirmed, with output unavailable; unknown
membership does not show a false empty-state claim. No inspection action marks
comments viewed, handled, resolved or edited.

Comparison preserves its branch/commit controls, validation, target identity,
loading/error presentation and apply behavior, but is displayed in the same
floating visual family as Share instead of an anchored popover. Its full height
is relative to the Bridge viewer, retaining an inset frame and access to code
outside it. No height selector, width change, nested stack or Back hierarchy is
introduced. Share retains its existing height.

Opening either peer closes the other. While Share cannot be dismissed because
output is in progress, switching to Compare must not cancel the output or expose
both panels; the existing busy protection wins. Closing or switching a panel
must not strand keyboard focus in its hidden content. Domain comparison and
annotation/output state transitions remain unchanged.

## Typography roles, not per-feature sizes

Both native and web UI request the macOS system sans-serif family. Tailwind's
customized scale corresponds by convention to AppStyles.General.Typography;
stock Tailwind sizes are not the contract. CSS px and Swift points are compared
at equivalent logical scale, not by raw Retina screenshot pixels.

| Role | Native scale name | Web scale name | Web size / line height |
| --- | --- | --- | --- |
| Navigation/list primary label | textBase | text-base | 13 / 18px |
| List metadata / description | textSm | text-sm | 12 / 16px |
| Search and ordinary field value | textSm | text-sm | 12 / 16px |
| Compact action/menu/field label | textXs | text-xs | 11 / 14px |
| Auxiliary tiny hint | textXxs | text-2xs | 9 / 12px |
| Code and editing body | Existing native/renderer role | text-sm or explicit renderer equivalent | 12 / 16px for text editing; preserve renderer line geometry |

List names use regular weight, with medium weight only for an existing semantic
emphasis such as a group or current/default fact. Descriptions are regular.
Compact action labels and headings use the owned medium/semibold role already
appropriate to their semantics. Highlight and selection do not change font size,
line height or weight. Metadata needed to make a choice is not a 9px tiny hint.
Ordinary lists are not monospace; only code/revisions retain monospace formatting.
The Bridge tree uses the 13px navigation role without changing its row metrics.

## Proof obligations

| ID | Required observation |
| --- | --- |
| V1 | Positive/negative static and type cases for canonical values, mirror equality, complete recipe ownership and valid feature composition; existing gates preserved. |
| V2 | Real rendered compound-state matrix on relevant surfaces, in-tree and portaled; bounds, text contrast, indicator clearance and focus. Include selected+highlighted, disabled+selected, invalid+focused. |
| V3 | Real feature and virtualizer with long names, metadata, narrow width, filter/resize/scroll/keyboard changes; visible and actionable identities agree. |
| V4 | Complete affected comparison, search, settings, filter and annotation-control interactions; error/retry/empty/disabled cases and preserved command/focus outcomes. |
| V5 | Equivalent Chrome/Vite and packaged-native before/after views and independent visual inspection. Fixtures cannot prove native integration or transport health. |
| V6 | Preview membership/body/context must match actual Copy/Export selection for both scopes, including excluded, empty, stale and changing-message cases. Exercise peer switching, full-height geometry, keyboard focus and busy-output refusal through real shared controls; demonstrate the resulting output through the existing runtime path. |

Coverage: U1→R1/R8; U2→R2; U3→R3/R4/R6/R7; U4→R4/R5;
U5→R3/R5/R6/R9/R10; U6→R7/R8 and V1–V5; U7→R9; U8→R10;
R9/R10→V4/V6. A blocked runtime layer remains
unverified, never replaced by lower-layer evidence.
