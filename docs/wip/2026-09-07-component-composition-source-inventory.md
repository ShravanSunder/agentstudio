# Component-composition source inventory

## Current implementation status — 2026-09-07

The sections below preserve the original design-input snapshots, not current
implementation or readiness claims. The governing artifacts are now
[Requirements](../specs/2026-09-07-bridgeweb-component-composition/2026-09-07-requirements.md),
[Specification](../specs/2026-09-07-bridgeweb-component-composition/2026-09-07-specification.md)
and [Program Design](../specs/2026-09-07-bridgeweb-component-composition/2026-09-07-program-design.md).
Their final independent Astra review completed; implementation uses the ready
checkout-local plan `tmp/plan-workflows/2026-09-07-bridgeweb-component-language.md`.

At HEAD015222254 plus dirty shared UI work, owned item slots and descriptive44px
metrics are implemented; list/tree13, metadata/input12 and action11 roles are
bound through CSS and native-correspondence tests. Shared state recipes and the
known comparison/filter/settings consumers are migrated. Current focused checker27,
annotation/contrast browser29 and BridgeWeb check pass; aggregate is not green.
Source diagnosis found an ancestor span-selector enforcement bypass after those
tests. Destination-analysis correction and permanent regression coverage are in
progress; no claim of complete static enforcement or independent implementation
review is made yet.

Chrome5194 real branch selection, settings and filters were exercised with the
Swift backend. Native1owk comparison/annotation disclosure and Share scope/focus
were exercised. Captures exist under `/tmp/bridge-composition-design.OyOR0o/`;
historical before captures have different dimensions and are not pixel-equivalent
before/after proof. Native assets predate the final textual tint-label correction.
UI communication entries071–072 preserve commands, outcomes and limitations.
Transport/domain-state dirty hunks remain separately owned and unstaged.

## Original design-input snapshot

Question: where do current BridgeWeb recipes stop, and where do compositions
reintroduce visual decisions? Mode: design input. Snapshot: HEAD 5a5eaad33 plus
the shared dirty worktree, September 7. No product edits or runtime proof here.

## Coverage

Searched `rg --files BridgeWeb/src/components/ui` and production TSX imports via
`rg -n 'components/ui/|<button|<input|<textarea|<select' BridgeWeb/src --glob '*.tsx' --glob '!**/*test*' --glob '!**/components/ui/**'`.
No raw native control tags appeared outside owned primitives in this bounded
search. This does not exclude aliased factories, render props or indirect controls.

A Node read-only enumeration searched 413 TS/TSX files after excluding paths
containing test/fixture and components/ui, matching literal `components/ui/<family>.`.
It reconfirmed 22 production primitive families. Counts below are direct importing
files, not rendered instances, exports or complete transitive consumer coverage.

| Family | Direct importer count | Primary production composition |
| --- | ---: | --- |
| alert | 5 | Comparison branch/failure/banner; annotation thread/recovery/Share |
| avatar | 1 | Annotation inline surface |
| button | 13 | Comparison, shared button/filter/settings, Markdown, File app, code headers, annotation admission/inline/recovery/Share |
| checkbox | 0 | No direct product import |
| collapsible | 2 | Annotation compact thread/output history |
| combobox | 1 | Comparison branch selector |
| drawer | 3 | Context panel, annotation output controls/Share |
| dropdown-menu | 2 | Shared filter/settings |
| field | 2 | Comparison control/branch selector |
| input-group | 1 | Shared search field; also internally composed by combobox |
| input | 1 | Comparison control; also internally composed |
| label | 0 | Internal Field dependency |
| popover | 2 | Comparison and annotation admission |
| resizable | 1 | Shared rail layout |
| scroll-area | 0 | No direct product import |
| separator | 0 | Internal Field dependency |
| skeleton | 2 | Branch loading and Review fallback |
| sonner | 2 | Product/dev bootstrap |
| textarea | 2 | Annotation composer/message editor |
| toggle-group | 5 | Comparison control/basis, content header, Review projection, Share |
| toggle | 1 | Shared search control; also internally composed |
| tooltip | 2 | Annotation inline/Share |

## Source-backed findings

### Typography correspondence — current source and selected correction

Native evidence: `Sources/AgentStudio/Infrastructure/AppStyles.swift:60` defines
9/11/12/13/14/16/24, plus the native-only 48px-equivalent display role. The worktree
row uses `.system(size: textBase)` at `RepoExplorerWorktreeRow.swift:84`;
SidebarMetadataLine consumes the 12pt branch role; SidebarSearchField uses the
12pt SearchField text role. Native typography values need no change for this map.

Web evidence: `BridgeWeb/src/app/bridge-app.css:20` requests the system sans-serif
stack; the customized Tailwind 9/11/12/13/14/16/24 scale already corresponds to
AppStyles. Monospace is independently named. The problem is consumer assignment,
not a separate shadcn font or different scale definitions.

| Role | Current web assignment | Selected shared-scale assignment | Affected owners |
| --- | --- | --- | --- |
| Descriptive list title | text-xs, 11/14px | text-base, 13/18px | Combobox and descriptive menu item content |
| Descriptive list supporting text | text-2xs, 9/12px | text-sm, 12/16px | Shared descriptions and metadata |
| Navigation tree | literal 12px | text-base, 13px | Existing tree theme font-size override |
| Search/field value | text-xs, 11/14px | text-sm, 12/16px | Input, grouped input, combobox input |
| Compact action/menu label | text-xs, 11/14px | Preserve | Button, Toggle, plain action rows |
| Tiny auxiliary hints | text-2xs, 9/12px | Preserve only for auxiliary hints | Shortcut/hint slots, not decision-critical descriptions |
| Code / multiline editor | Existing 12px roles | Preserve | Pierre code theme and Textarea |

Descriptive geometry becomes 44px (18 + 16 + 2 + 4 + 4), replacing the earlier
36px trial after the owner requested actual native-role alignment. This does not
change plain 28px action rows or the control height ladder. Current source has
not yet been edited. Whole-system formal design review and a ready implementation
plan remain outstanding; the earlier Astra pass was authoring advice only.

### Semantic consumer map

An AST import/re-export walk (production TS/TSX, excluding test/fixture paths,
resolving relative and `@/` imports) found 81 files in the reverse dependency
closure: 22 primitive files and 59 other files. This is a static import closure,
not a claim that every imported helper renders a control. Code-view helpers that
import panel-support functions belong to preservation coverage, not new UI owners.
Dynamic loading and runtime render props require the explicit paths below.

Prefixes in this map are relative to `BridgeWeb/src/`; names omit `.tsx`.

| Recipe / slots | Direct composition → indirect surface | Meaning and treatment | Proof witness |
| --- | --- | --- | --- |
| Button / buttonVariants | app/bridge-viewer-button → search-field, refresh-header-chrome, dev-session-notice, annotation output-history/Share | Action, open control or boolean mode according to caller; retain callback, size and guard. Unify ordinary text/state recipes. | Shared state matrix plus real search/refresh/Share |
| Button directly | comparison-control/branch-selector/status-banner; File app; Markdown canvas; code header-renderers; annotation admission/inline/recovery/Share | Submit/retry/open/edit/copy/export; preserve distinct existing intent variants. | Current comparison/annotation/Markdown journeys |
| Toggle | app/bridge-viewer-search-control → File tree-panel and Review shell | Search visibility, not exclusive value. Preserve state/callback; use neutral open-state treatment through an explicit primitive semantic variant. | Search open/close and focus return |
| ToggleGroup/Item | comparison-control, branch-selector → Review mode | Exclusive target kind and basis; preserve value conversions. Standard exclusive-choice recipe. | Branch/commit and Common/Branch Tip selection |
| ToggleGroup/Item | content-header → bridge-app; review projection-menu → Review mode; annotation share-mode → output-controls | Exclusive File/Review, projection mode and Share scope. Preserve unavailable choices/counts/guards; standard exclusive-choice recipe. | Selected+disabled matrix and each actual consumer |
| Input | comparison-control | Commit value entry/validation; standalone frame. | Full valid/invalid OID and focus |
| InputGroup/Addon/Input | search-field → File tree-panel/Review shell; internal ComboboxInput → branch-selector | Search text, mode/clear actions; one grouped frame. Remove contextual visual focus suppression, retain actual focus lifecycle. | Grouped, inline combobox and portaled combobox states |
| Textarea | annotation composer/thread-message → compact-thread/thread → File code panel and Review annotation adapter | Multiline edit, body-text scale; embedded frame remains supplied by annotation presentation. No lifecycle changes. | Existing edit/reply/Escape and embedded-focus proof |
| Combobox root/Input/List/Item/Description/Empty | branch-selector → comparison-control → Review mode | Filtered virtualized target choices; item content and metric change, target/index/ref/state do not. | Real 2,000-row tests plus long metadata/indicator clearance |
| DropdownMenu root/Trigger/Content/Item/CheckboxItem/Description | viewer-filter-menu → File facet and Review facet → tree/shell | Filter activation, exclusive category/status and boolean visibility. Complete plain/descriptive slots; preserve domain mapping. | File/Review filter journey and each row state |
| DropdownMenu RadioGroup/RadioItem | view-settings-menu → File app and Review mode | Exclusive settings choices alongside boolean checkbox rows; no command or selected-value change. | Settings/reset, disabled-open close and focus |
| Popover root/Trigger/Content/Title | comparison-control → Review mode | Target editing surface; preserve anchor/open/Escape behavior. | Comparison popup journey |
| Popover Header/Description plus above | annotation admission → composer → thread | Admission decision; positive complete-composition example. Preserve labels/actions and frame. | Admission choice/dismiss |
| Drawer root/Trigger/Header/Footer/Title/Content | output-controls/share-mode/context-panel → File app/Review mode | Share host and frame; retain container placement/modal policy and action guards. Standard child controls. | Share geometry, scope, copy/export and return focus |
| Tooltip root/Trigger/Content | annotation inline/Share; nested trigger render chains | Explanation only; preserve non-button locked-status trigger and composed button refs. | Pointer/keyboard tooltip and nested trigger parity |
| Alert/Title/Description/Action | branch failure, comparison status; annotation compact-thread/recovery/Share | Inline, banner and card feedback need owned variants; preserve retry/acknowledgement semantics. | Each error/loading recovery surface |
| Field/Title | comparison-control/branch-selector | Labeled value groups; retain layout, use named title/description/error slots. | Comparison label/value alignment |
| Avatar/Fallback | annotation inline-surface → composer/message/thread | Identity badge, not an action; preserve circle and 24px scale. | Annotation identity geometry |
| Collapsible/Content/Trigger | compact-thread/output-history → thread/output-controls | Disclosure; preserve current owners, motion and expansion rules. No token rewrite of domain state. | Existing expansion/history interactions |
| Skeleton | branch-selector/Review fallback | Inert placeholder sized to missing content, not a disabled control. | Loading content remains truthful |
| Resizable components/layout hook | resizable-rail-layout → File shell/loading and Review shell/fallback | Pane geometry and drag/focus affordance; preserve behavior. | Rail resizing/focus |
| Toaster | product and dev bootstraps | Notification presentation; retain Sonner adapter and exceptional unlayered-CSS handling. | Actual toast title/description/frame |

No direct production consumer was found for Checkbox or ScrollArea. Label and
Separator are internally composed by Field. Exports without an external product
use include AvatarImage; ComboboxContent/Group/Label/Collection/Separator/Chips/
Chip/ChipsInput/Value/useComboboxAnchor; DrawerClose/Description;
DropdownMenuPortal/Group/Label/Shortcut/Sub/SubTrigger/SubContent; FieldLabel/
Description/Error/Group/Legend/Separator/Set/Content; InputGroupText/Textarea;
TooltipProvider and inputVariants. Some are called internally (for example
ComboboxTrigger, DrawerOverlay/SwipeHandle) and must not be mislabeled dead code.
Retain these APIs; shared recipe changes need primitive-level coverage even when
no product journey exercises the export. Do not invent a product consumer.

Direct render-prop chains inspected include Share's DrawerTrigger → TooltipTrigger
→ BridgeViewerButton → Button, annotation action TooltipTrigger → Button and
locked status TooltipTrigger → focusable noninteractive status span. Ancestor/
descendant enforcement must preserve these distinct sinks.

Remaining inventory boundary: the static closure includes non-rendering helpers
and protected runtime containers not inspected end-to-end. Their imports do not
authorize behavior edits. A full runtime interaction census is still not claimed;
the table closes the known recipe-to-semantic-composition mapping used by this
design, with rendered proof left explicitly open.

1. Accepted, direct observation: `BridgeWeb/src/components/ui/combobox.tsx`
   and `dropdown-menu.tsx` give descriptive rows h-7, gap-0 and py-px, with
   11/14px labels and 9/12px descriptions. Both also force highlighted/focused
   descendant foreground. This contradicts treating the branch symptom as
   exclusively a feature-local defect.
2. Accepted, direct observation: `BridgeWeb/src/app/bridge-review-comparison-branch-selector.tsx`
   owns a 28px virtual estimate, `measureElement`, filtered collection handling,
   keyed values and command-target conversion. Nested spans/hash own some visual
   treatment. The correct boundary must preserve this legitimate feature owner.
3. Accepted, direct observation: `BridgeWeb/src/app/bridge-viewer-filter-menu.tsx`
   already composes reusable filters, but separately owns heading and status-badge
   recipes. It is not just a pass-through primitive adapter.
4. Accepted, direct observation: `BridgeWeb/scripts/check-bridgeweb-style-system-classification.ts`
   catalogs control/frame roots but omits description/title/alert presentation
   slots. `checkStyledElementOverrides` in the TypeScript analyzer returns when
   a node has no styled-element classification. Root conformance does not prove
   nested content conformance. No claim that the whole checker is absent or useless.
5. Accepted, direct observation: `BridgeWeb/src/app/bridge-app.css` still maps
   ordinary text to white and muted text to #C5C8C6, unlike the owner's settled
   #EAEAEA/#B8BCC4 pair. White also feeds annotation-lane blending. The checked
   mirror supplies code-theme foreground. Replacing white globally would cross
   the protected surface/syntax boundary; ordinary role remapping must be isolated.
6. Accepted, direct observation: current tree adapter uses semantic overrides and
   checked mirror values; the historical Fable concern about five dead Catppuccin
   chrome keys is not a new outstanding implementation task. Current unconditional
   primitive recipes also do not retain the historical dark-ancestor portal bug.

## What is not established

- This is an exhaustive direct-family/import scan, not the requested complete
  transitive component inventory. Full source inspection of every consumer,
  exported variant and compound state remains open.
- No screenshot, actual contrast ratio, browser interaction or native proof was
  produced in this design pass. Prior test counts are not current visual evidence.
- Fable's audit and prior inventories are discovery evidence, not current authority.
  Historical counts and runtime claims are not promoted without revalidation.
- Exact new content APIs, descriptive-row metric and inner-control fills remain
  unselected. The rewritten documents expose these gaps instead of presenting
  earlier assistant proposals as owner decisions.

## Delegation and next owner

### Additional source pass after Astra authorization

Read the complete shared search field/control/button, view-settings menu,
File facet menu, Review facet menu, Review projection menu and annotation admission
popover. These establish useful preserved compositions rather than missing
controls that should be rebuilt:

- `bridge-viewer-search-field.tsx` owns autofocus/select-on-mount, Escape close,
  regex/text action and clear action through InputGroup and shared buttons.
  `bridge-viewer-search-control.tsx` uses Toggle to present search open state.
  Inventory must classify this open-state presentation separately from exclusive
  choice and boolean mode; primitive name alone is not a semantic classification.
- File and Review facet components pass domain filter facts through the shared
  filter composition. Review's local Visibility heading repeats the shared group
  heading recipe; moving domain filtering into a generic row would be wrong.
- `bridge-viewer-view-settings-menu.tsx` already shares File/Review settings,
  including closing an open disabled menu. It composes checkbox and radio rows;
  preserve callbacks/default comparison and focus behavior.
- `bridge-review-projection-menu.tsx` retains disabled future-mode choices and
  one active normal-review choice. The selected-disabled presentation must be
  checked without enabling unavailable modes.
- Annotation admission already uses PopoverHeader/Title/Description and owned
  Button variants. This is a concrete positive composition example.

Opened proof seams: `style-system.browser.test.tsx:127–292` covers neutral-open
versus selected paint, explicit disabled paint and focus/invalid primitives;
`bridge-review-comparison-control.browser.test.tsx:417–541` exercises real
virtualizer keyboard traversal and deep mouse selection with 2,000 fixture rows.
These are reusable component/integration seams, not proof that the proposed
design works. No tests were executed in this pass.

The owner explicitly selected Astra medium. The advisor runtime banner confirms
OpenAI `gpt-6-astra`, medium reasoning, sandbox read-only, fresh session
`01a07c4e-090a-7de1-a834-c8f94fcf8c09`. It is inspecting the three drafts and
relevant source against the full rubric as pre-review authoring advice.
Private packet/receipt files remain outside the repository. Final independent
design acceptance is not claimed by this consultation.

### Astra result and parent verification

Astra medium completed the authoring critique (exit0), with four important
candidate findings. Parent accepted all four after reopening current source:

1. Checker classification must follow styling to its actual rendered owner,
   not classify any composition containing a Button as a Button. Parent ran the
   real analyzer on in-memory cases: ancestor button styling, a nested styled span
   and an overridden ComboboxItemDescription each returned zero findings; `py-2`
   forwarded only to an outer section containing a Button was rejected. Command:
   `node --experimental-strip-types --input-type=module` importing the real analyzer;
   exit0. This reproduces a design constraint, not a passing product test.
   Route: program-design; validate prohibited cases fail and valid outer layout passes.
2. The inventory needs recipe/slot → direct/indirect consumer → semantic use →
   retained/changed treatment → proof. Search visibility and exclusive projection
   selection demonstrate why family names alone are insufficient.
   Route: program-design; disputed observable meaning routes to spec-design.
3. Slot nesting, indicator reservation, measurement/ref attachment, accessible
   identity, metric delivery and grouped-input state precedence remain incomplete.
   Route: spec-design for the open visual choices, then program-design for exact
   contracts. Preserve the existing real virtualizer proof seam.
4. Annotation isolation requires more than preserving white: CSS also derives
   annotation surface from muted, border from input, divider from border and hover
   from accent. A role-edge map must distinguish deliberate control change from
   preserved annotation/Pierre output. Route: program-design; verify resolved
   outputs at those boundaries, not mirror equality alone.

All three target document SHA256 values matched before and after the advisory
run. No product source was edited in this pass. The final independent design
review has not run; exact visual choices, full semantic consumer coverage and
structural-realization confirmation remain open. These findings support the
current hierarchy, not a new component framework or new state ownership.

### Earlier blocked attempt

The fresh-context Sol read-only inventory invocation failed before any receipt.
An escalated retry was denied because sending private repository context to that
agent needs explicit payload/destination permission. No alternate route was used.
No independent design review has run; the review allowance remains unused.

Parent reduction: findings above accepted from opened current source; exhaustive
consumer and rendered claims remain unresolved. Next owner: spec-design to settle
the explicit inner-control choices, then program-design to finish interfaces and
structural-realization confirmation. Full independent review also requires the
agent-transfer permission. No implementation or planning readiness is claimed.
