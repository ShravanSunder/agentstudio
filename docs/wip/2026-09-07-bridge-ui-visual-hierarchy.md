# Bridge UI visual hierarchy — working contract

Status: source-grounded findings and proposed direction; not an executable ready
plan. Product source edits paused pending agreement on the complete composition.
Inspected at HEAD adaf8167f plus shared working-tree changes.

## Goal and boundaries

Make control panes, lists and viewer chrome readable as one system. Preserve
accepted canvas/navigation colors initially. Change shared recipes rather than
feature-by-feature paint. Preserve command semantics, selection, keyboard focus,
virtualization, portals and output behavior. Transport/dev-tab work is protected.
Annotation state transitions require a separate state-machine contract; this
document does not settle resolution/output eligibility or navigation shortcuts.

## Current rendering relationships

```text
bridge-app.css: palette + semantic roles + scales
  ├─ components/ui: control, floating frame and list-row recipes
  │    ├─ comparison popover: fields, toggles, input, branch list
  │    └─ toolbar: icon actions and segmented choices
  ├─ Bridge headers: explicit muted title/status classes
  └─ checked palette / role overrides: Pierre reading and navigation
```

## Verified findings

| Surface | Current evidence | Consequence / uncertainty |
| --- | --- | --- |
| Descriptive branch rows | `components/ui/combobox.tsx`: h-7, descriptive gap-0/py-px; label 11/14px and description 9/12px. `app/bridge-review-comparison-branch-selector.tsx`: virtual estimate 28px. | Two text lines consume 26 of 28px before other layout effects. Almost no row separation. Changing row geometry must also reconcile virtual sizing. |
| Metadata emphasis | Combobox highlights force descendants to accent foreground; BranchRevision explicitly uses muted foreground. | Hierarchy and inheritance differ by state and descendant. Rendered audit must check both winning colors. |
| Segmented tracks | ToggleGroup segmented uses bg-muted (#363636); toggles use muted labels and primary/15 selected fill. | General muted fill was reused as a track without an explicit contrast contract. Toolbar and dialog contexts must be compared. |
| Comparison fields | Branch/Commit and Common/Branch Tip use outline variant, not segmented variant. | They are not the same recipe as Files/Review despite presenting exclusive choices. Unification must preserve semantics. |
| Header text | Bridge content header explicitly uses muted titles; code content uses syntax foreground; comparison headings/labels use foreground. | Different colors are intentional assignments, but the overall hierarchy was not validated. Making everything white is not a sufficient fix. |
| Documentation | `docs/architecture/bridge/bridgeweb_design_token_architecture.md` still lists old tree/floating values and active annotation fill. | Accepted trial and durable contract have diverged. Reconcile after agreement, not by treating stale docs as current visual authority. |

Screenshots establish poor scanning and confusing emphasis. Exact contrast
failures are not yet measured; do not equate all gray text with inaccessible text.

## Proposed composition

```text
Floating panel — one enclosing border
  ├─ Section heading — compact, semibold; no oversized/all-caps emphasis
  ├─ Field label — readable, regular; subordinate to selected value
  ├─ Exclusive choices — quiet track; one unmistakable selected segment
  ├─ Search input — distinct input boundary; focus ring only when focused
  └─ Descriptive list
       ├─ Name — primary reading line
       ├─ Metadata — smaller supporting line, restrained but readable
       └─ Row state — selected indicator distinct from hover/keyboard highlight
```

Proposals requiring visual agreement:

- Keep established surface palette for the first comparison; change hierarchy,
  density and state recipes together instead of chasing individual hex values.
- Descriptive rows: target 36px (two lines plus actual vertical breathing room),
  label 11/14px, metadata 9/12px, 4px vertical inset and 2px line gap.
  Single-line action rows remain 28px. Long labels truncate without covering the
  selected indicator; full label remains available accessibly.
- Enabled unselected controls use readable ordinary text; selected controls use
  a blue-tinted fill with high-contrast text and a distinct selected indicator.
  Disabled appearance must not be indistinguishable from idle enabled appearance.
- Trial transparent segmented track in toolbar and popover contexts; preserve
  grouping and selected state without a bright gray trough.
- Metadata remains subordinate on highlighted rows; it must not become identical
  in weight/size/color to the primary name. Measure actual colors after cascade.
- Use fewer decorative dividers; keep input boundaries, one outer panel frame,
  and focus indicators where they communicate real interaction.
- Header titles, field labels, metadata and code have different roles. Define
  consistent role use, not uniform brightness across all text.

## Implementation sequence after concurrence

1. Record one agreed state/role matrix: idle, hover, keyboard focus, selected,
   selected+focused, disabled, error; primary text, metadata and icons per state.
2. Add rendered regression scenarios for descriptive row geometry, indicator
   clearance, virtual-scroll reachability, and measured text/background contrast.
3. Correct shared Combobox/Toggle/Button recipes and necessary virtual row metrics;
   consumers only select semantic variants and supply layout/behavior.
4. Inspect comparison popover, toolbar segmented groups, ordinary menus, Share,
   tooltips and annotation actions together at the same scale. No local exceptions
   merely to satisfy a screenshot.
5. Reconcile docs/checker expectations with the accepted system. Keep architecture
   and style gates; do not weaken them to allow ad hoc recipes.
6. Run focused quality/browser checks, real dev browser inspection, then packaged
   native inspection. Coordinate aggregate test slot before repository gate/push.

## Proof contract

- Small text: minimum 4.5:1 against its actual rendered/composited background.
  Meaningful non-text state indicators: 3:1 where applicable. Disabled controls
  must be visibly distinguishable; do not claim an accessibility exemption makes
  a confusing design acceptable.
- Capture same-scale idle, hovered, keyboard-highlighted, selected and disabled
  rows. Include long branch names, metadata, selected indicator and narrow panel.
- Preserve keyboard navigation, focus restoration, search, selection, comparison
  target changes and virtualized scrolling. Source/class assertions supplement,
  not replace, rendered geometry and real interaction proof.
- Commands: focused `mise run test:bridge-web:browser` for comparison/control
  suites; `mise run test:bridge-web:check`; aggregate `mise run test` before push.
- Current audit ran no tests and made no product changes. Prior green results
  do not validate this proposed redesign.

## Open decision

Agree on the composition above before implementation: especially transparent
tracks, white/high-contrast selected labels rather than blue text, and 36px
descriptive rows. These are proposed visible behavior, not silently accepted
mechanical corrections. Route agreed obligations to the visual specification
and structural owners before declaring an implementation plan ready.
