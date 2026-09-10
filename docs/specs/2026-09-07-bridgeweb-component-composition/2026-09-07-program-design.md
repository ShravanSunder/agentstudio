# BridgeWeb component language — Program Design

[Requirements](2026-09-07-requirements.md) → [Specification](2026-09-07-specification.md).

## Ownership hierarchy

The library owns how a control looks and behaves as a control. Feature
components own what it means in the product. Both are necessary.

```text
AppStyles — native core conventions
    │ corresponding core values
    ▼
bridge-app.css — canonical values, roles, scales and contexts
    ├─ Tailwind mappings — implementation vocabulary, not another authority
    │    ▼
    │  components/ui — owned shadcn-style source; Base UI interaction beneath
    │    │ controls, frames, content slots and state recipes
    │    ▼
    │  Our composed components
    │    ├─ shared viewer patterns: search, filters, toolbar, context panel
    │    └─ feature components: branch option, comparison form, annotation UI
    │         ▼
    │       Feature screens: layout and connection to domain state/actions
    └─ equality-checked TypeScript mirror → Pierre adapters → real renderers
```

A feature component is not a styling exception. It composes the language.
The mirror is not a separate palette.

## Current evidence and change boundaries

Paths below are relative to BridgeWeb.

| Source | Current ownership and consequence |
| --- | --- |
| src/components/ui/combobox.tsx; dropdown-menu.tsx | Own 28px descriptive rows, zero gap and descendant-wide highlight foreground. Correct library recipes, not only the branch picker. |
| src/app/bridge-review-comparison-branch-selector.tsx | Owns domain formatting/target conversion and virtualization, including a literal 28px estimate. Keep that feature; replace local content paint/geometry with slots. |
| src/app/bridge-viewer-filter-menu.tsx | Genuine shared composition, with local heading, row-content and badge recipes. Preserve filtering semantics while using complete visual patterns. |
| src/components/ui/input-group.tsx | Already owns grouped frame and child treatment. Reuse rather than add a second field system. |
| src/app/bridge-viewer-context-panel.tsx; src/components/ui/drawer.tsx | Host placement and primitive frame are already separate. Preserve them. |
| src/app/bridge-app.css; src/design-tokens/bridge-design-palette.ts | White also supplies annotation blends and renderer foreground. Remap ordinary text roles; do not globally replace white to repair controls. |
| scripts/check-bridgeweb-style-system-classification.ts | Control/frame-root catalog omits description, title and alert slots; root checks cannot establish whole composition conformance. |

## Components and their interfaces

| Owner | Contract | Changes when |
| --- | --- | --- |
| CSS semantic roles | Values become named text, fill, boundary, focus and context roles; preserve independent white/syntax/blend inputs. | Visual meaning changes. |
| Owned primitives | Values, disabled/invalid facts, refs, callbacks and content become Base UI interaction plus complete visual states; no domain fetch/store/command. | Reusable control contract changes. |
| Owned content slots | Label/description/status/indicator content receives internal geometry, truncation and state-safe typography. | Recurring content pattern changes. |
| Shared viewer compositions | Resolved labels/icons, values and callbacks compose recurring viewer arrangements. | Same viewer pattern changes across File/Review. |
| Feature components | Domain records become meaningful content and existing command requests. | Domain meaning changes. |
| Feature screens | Existing query/state results connect to feature components and outer layout. | Journey or host arrangement changes. |
| Pierre adapters | Roles or checked static values cross installed theme/style inputs. | Renderer boundary changes. |

BranchOption is a feature component: it formats name/hash and current/default
facts, composes Combobox item/label/description slots and supplies the value.
It cannot choose gray, selected fill or internal row padding.

The library delta is complete menu/combobox content and indicator slots, a shared
item-content recipe, and explicit variants of existing alert and heading families.
The contracts below define their boundaries; the Specification owns the selected
visual values rather than leaving hidden implementation defaults. There is no
schema-driven universal list, form framework or theme service.

Caller layout remains legal: placement, containing grid/flex, width constraints,
margin and virtual translation. Internal padding, type, icon size, radius,
outline, fill and state paint remain owned. Ancestor selectors are not an
escape hatch. Slots retain refs/accessibility; decoration creates no tab stop.

### Rows: one content recipe, separate interaction owners

Combobox and DropdownMenu remain different interaction primitives. They share a
pure `ItemContent` recipe rather than sharing selection, focus or keyboard state.
Their existing item roots keep all Base UI props and emit the same callbacks.

```text
ComboboxItem / DropdownMenuItem / CheckboxItem / RadioItem
  root: value, index, ref, disabled and library interaction attributes
  ├─ leading decoration (optional, noninteractive)
  ├─ ItemContent
  │    ├─ ItemLabel: one truncating primary line
  │    └─ ItemDescription: optional supporting line
  │         └─ ItemMetadata: normal or monospace; regular or emphasized
  └─ indicator region: library-owned, always reserved for selectable rows
```

`ItemContent` owns the shrinking text column, line arrangement and overflow.
`ItemLabel` and `ItemDescription` take content plus ordinary accessibility/data
attributes; they do not accept arbitrary paint or geometry. `ItemMetadata` allows
the two named font forms and emphasis forms above, not an arbitrary class recipe.
It inherits the description's state-aware foreground. Existing exported
ComboboxItemDescription/DropdownMenuItemDescription use this same recipe internally;
their semantic names remain, without parallel implementations.

Each item root owns `presentation: default | descriptive`; this determines its
height and content arrangement. Selectable rows reserve a trailing region even
when the check is absent, so selection does not shift or cover text. The leading
region is optional and cannot take the trailing region's clearance. The trailing
region uses the existing 14px indicator with an 8px separation from content; the root's
8px horizontal inset remains outside that reserved region. Metadata
truncates inside its own column; full branch label and hash remain accessible.
The branch feature continues to format the 12-character visible revision and
full accessible revision, and to label Current/Default independently of selection.

The forwarded ref and virtualizer `measureElement` stay on the actual item root,
not ItemContent or an extra wrapper. `data-index`, `index`, ARIA position/set size,
stable key and value stay there too. The feature owns total-list height and item
translation; internal row height is never passed as caller style.

Canonical CSS owns both row-height values. The existing checked static-mirror
mechanism gains a narrowly typed numeric row-metrics export, equality-checked
against those CSS lengths. The virtualizer consumes that descriptive estimate;
actual mounted measurement still wins. This avoids a second hand-maintained
literal, runtime style observer or measurement state store. The values are 28px
for default and 44px for descriptive, matching the Specification's line/inset sum.

The shared text scale remains in CSS @theme and native AppStyles. ItemLabel uses
text-base/normal and ItemDescription text-sm/normal; ordinary action items keep
text-xs. Input, InputGroup values and ComboboxInput use text-sm. The tree adapter
consumes the text-base CSS role through its existing font-size override rather
than retaining an independent 12px literal. Toolbar/action text remains text-xs.
No native value changes are necessary for the inspected sidebar/search roles;
their current textBase/textSm assignments are the correspondence reference.
Static/native correspondence checks plus rendered web role assertions guard the
mapping, while visual proof compares logical scale and weight in both hosts.

### Fields, headings and feedback

InputGroup remains the frame owner for grouped inputs. Its child Input/Textarea
is borderless and does not paint a second ring. Standalone Input owns its own
frame. ComboboxInput composes InputGroup and keeps Base UI input refs and behavior.
Remove ancestor-sensitive combobox focus suppression: the focused field has one
visible frame regardless of whether its list is inline or portaled. This is a
presentation change; it does not move focus or add event handling.

Use existing FieldTitle/Description/Error for field semantics. Add
DropdownMenuHeader and DropdownMenuDescription as noninteractive presentation
slots for menu introductory content, using the same heading/supporting recipes
as PopoverHeader/Title/Description without invoking Popover's context-dependent
accessibility API inside a Menu. Existing DropdownMenuLabel owns group headings.
Shared viewer filter/settings components compose these; Review's Visibility
heading uses the same group-label slot. Domain copy remains in its current owner.

Alert gains `layout: card | banner | inline` and `variant: default | warning |
destructive`. These replace actual branch-inline, comparison-banner and recovery-
warning overrides. Its action area participates in layout rather than a feature
guessing clearance with pr-18/pr-28. Icon, title, description and action columns
are owned; actions still use Button. No recovery or retry behavior moves into Alert.

Status-badge paint belongs to an owned `StatusBadge` presentation component with
`tone: neutral | success | primary | warning | destructive`. Shared viewer rows
compose it; the feature maps domain facts to a tone and supplies the existing
glyph/label. This does not unify annotation Pending/New semantics or change their
status rules. It removes local badge fill/type/size recipes, not domain components.

### Token edges: change controls without recoloring readers

```text
ordinary control/header/panel text → foreground/supporting roles   change
tree ordinary/supporting text → sidebar roles → same text pair    change
static code foreground → existing checked white palette entry      preserve
annotation text → code-foreground / existing faint role            preserve
annotation fills/borders/hover → existing unchanged inputs          preserve
```

Ordinary foreground roles map to the accepted #EAEAEA and supporting roles to
#B8BCC4 through the canonical palette and equality-checked mirror. Preserve the
existing white primitive rather than renaming its meaning. A `code-foreground`
role names its reading-context use; annotation foreground uses that role instead
of following the changed general foreground. Static code theme foreground keeps
its existing mirror input. Syntax token definitions remain untouched.

These current annotation dependencies must retain their resolved output:

| Output | Preserved dependency |
| --- | --- |
| Lane and active lane | background + white 4%; then warning 8% |
| Comment/editor surface | muted 42% + background |
| Comment border/divider | input 70%; border 72% |
| Hover and active thread | accent 64%; existing warning Lab blend |
| Supporting metadata | existing faint role |

Do not redefine muted, accent, input or border globally merely to trial a control
treatment. Choose the component's existing appropriate role or add a narrowly
named role only if the agreed treatment cannot be expressed without changing a
different semantic consumer. Preserve tree canvas, code canvas, selection and
git-decoration inputs except the explicitly selected tree text-role correction.
The before/after proof observes effective outputs, not just declaration equality.

## Peer comparison and Share panels

Specification R10 uses the existing `Drawer` interaction and
`BridgeViewerContextPanel` frame. The frame's full-height variant fills the
existing canvas viewport below the content header/status, with its existing
insets and width. The portal host remains placement-only. Share keeps half height.

```text
Review viewer content — domain/controller connections (existing)
  -> Review header panel composition — owns peer transitions (added)
       | Compare open boolean (moved from Compare control)
       | one output-pending lease (moved from Share header control)
       | reads existing annotation interaction.shareMode (not copied)
       +-> Compare control — controlled Drawer lifecycle/query/input/apply
       |    -> comparison drawer content — pure form/current-state presentation
       |    -> shared context-panel frame [full] -> existing canvas portal
       +-> Share panel control — existing interaction/output/history owners
            -> shared context-panel frame [half] -> same canvas portal

File viewer Share wrapper — no comparison peer
  -> owns its one output-pending lease -> same Share panel control
```

The Review-specific composition is a local UI component, not an atom, store,
coordinator or general panel registry. It accepts the existing comparison inputs
and controller callbacks. Compare receives a required controlled open value,
an open-change request callback returning whether the request was accepted, and
a final-focus policy. There is no uncontrolled fallback inside Compare.
Share's existing standalone header entry wraps a controlled panel with its local
lease; Review instead passes the parent's lease into that same panel. Exactly
one lease instance reaches Share actions, History Repeat and the peer guard.

The controlled Share panel continues to read and write `interaction.shareMode`;
its opening callback lets the Review composition close Compare first. It does
not copy scope/open state into parent state. The parent derives peer final-focus
suppression from the incoming panel rather than racing two focus restorations.
Each panel retains its own trigger ref and outside-press reason. Escape or an
ordinary close restores its connected, enabled trigger. Compare Apply immediately
disables that trigger while acknowledgement is pending, so Compare instead uses
the existing context-panel viewport ref as its return target. The shared viewport
is programmatically focusable (`tabIndex=-1`, not another Tab stop), labelled
Viewer content, and remains outside the inert loading code canvas. This is a
host accessibility responsibility, not panel-state ownership. Compare resolves
the target at close time, including Escape during a refresh. If the viewer is
inactive or the target is disconnected/inert, it returns no focus target and
leaves the newly active surface's focus alone. Outside press also leaves the
clicked target alone; a peer switch lets only the incoming panel set initial focus.

```text
Closed + Compare request
  -> parent admits -> Compare open=true
  -> Compare lifecycle clears commit/validation and starts target query
  <- full-height frame; current branch/commit input receives focus

Share idle + Compare request
  -> parent closes shareMode and opens Compare in one React update
  -> closing Share suppresses final focus -> Compare initial focus wins

Compare + Share request
  -> parent closes Compare and opens existing shareMode
  -> Compare lifecycle cancels query once; suppresses final focus
  <- Share initial focus; no annotation/output mutation

Share output-pending + Compare request
  -> existing lease veto -> unchanged Share; no Compare query or cancellation

Compare + dismiss/apply/inactive
  -> controlled close -> lifecycle cancels target query once
  <- enabled trigger, else active viewer viewport; inactive viewer never steals focus
```

Current anchors are `src/app/bridge-review-comparison-control.tsx` (local open,
query/cancel/apply and input focus), `src/app/bridge-app-review-viewer-mode.tsx`
(sibling header controls), `src/worktree-annotations/worktree-annotation-output-controls.tsx`
(shareMode, pending lease and dismissal), and the context-panel/host sources above.
Moving open ownership is the changed edge. Replacing Popover with Drawer and
adding the sibling request guard are added presentation edges. Query/cancel
remain Compare-owned and occur only on accepted lifecycle transitions, not on
same-session rerenders or refused requests. Target application, validation,
native acknowledgement and output commit/revision checks remain unchanged.

The focus proof holds acknowledgement pending until after drawer closure and
asserts the viewport receives focus while the trigger remains disabled. It also
covers Escape during an open-picker refresh and deactivation into another surface.

The large comparison component separates its form/current-state presentation
from lifecycle and command handling. Presentation takes values, refs and
callbacks; it does not query, own pending acknowledgements or coordinate peers.
The shared frame may accept the primitive's existing initial-focus input to
target the current branch/commit field; it acquires no domain knowledge.

This costs a small Review composition and explicit controlled interfaces. Putting
peer state in the portal provider would reduce prop passing but make placement
own product transitions and invite a registry. Retaining private Compare open
state alongside a parent panel enum would require synchronization. Neither is
needed for two known peers. Reconsider only if an authorized third peer introduces
genuinely shared lifecycle semantics; a third surface alone is not a registry mandate.

Browser interaction proof keeps the actual Drawer, CSS, viewport, comparison form
and annotation interaction/lease real. External target/output responses may be
controlled to hold a query or output in flight. Observe one visible panel,
cancel/query counts, canonical applied target, focused element and inset geometry.
Vite/native proof separately exercises the existing runtime and host; a fixture
cannot establish those paths. R10 maps to these peer/lifecycle/geometry seams;
existing R3/R5/R6 and V4/V6 cover focus, disabled and failure preservation.

### Share's read-only output preview

R9 composes the existing filtered saved-message projection into a pure
`WorktreeAnnotationSharePreview`. The annotation
[New/Pending design](../2026-08-24-worktree-annotation-new-pending/2026-08-25-program-design.md#pending-and-all-output-scopes)
owns the corrected thread-aware eligibility rule. This preview does not reselect
messages or own another scope, store, revision, lease or command.

```text
existing projection/session selection
  -> shared message-state derivation + canonical thread resolution [changed]
  -> deriveWorktreeAnnotationShareProjection [same owner]
       +-> existing counts and output availability
       +-> filtered inlineThreads + otherThreads
            -> SharePreview [added pure view]
                 path/range + author + complete saved text
  -> ShareModeRow body slot [added composition]
       existing scope control / feedback / History / output footer [preserved]

Copy/Export -> output.scope.commit with displayed revision/session/source fences
  -> native canonical Pending/All selection [resolution correction; same owner]
  -> existing prepare/effect/finalize -> result or error -> existing Share feedback
```

`SharePreview` takes already-filtered thread entries and whether the displayed
projection is current. It renders every participating message from both placement
collections, grouped by thread with effective path/range (or projected original
context when unavailable). It composes owned ItemContent/Label/Description/Metadata
for location/author information and ordinary body-text token roles for complete
pre-wrapped saved text. Body paragraphs are not interactive control slots. No
InlineSurface, editor, Markdown worker, link action, source-navigation callback,
checkbox or new paint recipe is introduced. This avoids creating a second set of
annotation interactions merely to inspect output membership.

The Share row gains an ordinary content slot, not a second domain controller.
The existing surface content supplies the preview from the same `shared` value as
the counts. A known empty scope has an explicit empty state. Unknown membership
shows loading rather than zero; known stale content is labelled unconfirmed and
cannot enable Copy/Export. Existing receipt and viewed-convergence gates remain.
Preview inspection issues no command and never marks New viewed.

Native selection remains authoritative, with canonical resolution available
before message flattening. Existing session/projection/source fences and durable
saved-revision validation reject a stale display without an effect. Resolution
already advances those revisions; no new fence or preview endpoint is needed.
All and exact-byte History Repeat remain unchanged. The JS/Swift cutover must be
proved together and Vite must use a rebuilt matching backend before output proof.

Cost: one pure feature view and a body slot. Reusing the interactive inline
annotation surface would couple preview to editing/focus/selection; a server-side
preview endpoint would duplicate existing data and require a new protocol. Neither
serves the confirmed scope. If a later owner requests navigation or drawer editing,
that is a separate design, not an extension silently added to this view.

Proof observes the exact preview IDs/bodies and actual new-output effect selection
for Pending and All, with open/resolved, author, handled, draft, locked and placement
cases. Resolve/Reopen and stale revision cases prove currentness without changing
handled/viewed history. Browser proof keeps shared controls/CSS/preview real and
may control external responses; real Vite/native output proof keeps the existing
adapter/service/repository/effect path real. Fixtures cannot prove that runtime.

## Why the component-language structure

Root-only lint leaves missing slots and bad primitive recipes intact. A
mega-selector that owns all data and rendering moves domain behavior into the
library. Extending existing recipes and composing them in genuine feature
components avoids both failures.

Cost: explicit content APIs, migration of actual consumers and compound-state
proof. Benefit: feature authors stop making repeated visual decisions. Extract
shared behavior for real recurring semantics, not coincidental visual resemblance.
A one-feature domain component stays local.

## Current-to-proposed paths

```text
Branch search [event]
  input callback → local search write → Base UI filtered collection  unchanged
  → feature virtualizer / measured positioning                      same owner
  → ComboboxItem + locally styled nested spans                       removed recipe
  → feature BranchOption + owned label/description/indicator slots   proposed edge
  ← readable rows with full accessible identity                     preserved

Branch choice [event]
  Base UI onValueChange → comparisonTargetForBranch
  → onSelectTarget → existing command path                          unchanged
  ← existing target update or failure presentation                  unchanged

Filter choice [event]
  shared filter → DropdownMenuCheckboxItem → feature callback       unchanged
  local nested paint → owned content/status presentation            changed

Popup [event]
  existing trigger → Base UI open/portal/focus → owned frame         unchanged
  → our composed content; Escape/dismiss returns focus              preserved
```

Anchors: branch-selector and filter-menu above, plus the owned popup/menu/drawer
sources. No new command, copied selection store or synchronization effect.
The shared descriptive recipe supplies its eventual estimate to the existing
virtualizer; mounted measurements remain authoritative. Keyed row identity,
filtered indexes and highlight-scroll behavior are preserved.

## State and failure ownership

| Facts | Required rendering | Existing owner |
| --- | --- | --- |
| Enabled idle | Main/supporting hierarchy. | Primitive recipe and feature enablement. |
| Hover / keyboard candidate | Highlight without flattening content. | Base UI interaction. |
| Selected + highlighted | Both facts visible; no implicit selection change. | Controlled value and Base UI candidate. |
| Disabled + selected | Selected identity retained; no enabled paint or dispatch. | Existing disabled guard. |
| Invalid + focused | Error and keyboard cue retained. | Validation and focus owners. |
| Loading / empty / failed | Existing truthful state/retry action; no fallback selection. | Query/feature owners. |

Recipes consume existing state attributes, not synchronized React copies.
Async failures keep existing feature propagation. No new persistence,
concurrency, transport or trust boundary; escaped text remains escaped.
Annotation editing, resolution authority and output lifecycle are protected;
the targeted Pending eligibility correction is owned by the linked New/Pending design.

## Enforcement, cutover and proof

Extend the existing checker, not another gate or exception ledger. Replace the
"contains any control" inference with styling-destination analysis:

```text
caller class/style expression
  → resolve local/imported constant, cn/cva, conditional or spread
  → follow that particular prop through the component's returned JSX
  → actual recipient
       ├─ outer layout element: permit its own layout
       ├─ owned control/frame/content slot: reject recipe overrides
       └─ unresolved forwarding: fail with the unsupported source anchor
```

An imported component gets a per-prop destination summary, not a single subtree
classification. A class forwarded only to an outer section containing Button is
layout. The same class forwarded to Button is a control override. If forwarded
to both, the stricter destination wins. Follow render props to their actual
element, including DrawerTrigger → TooltipTrigger → BridgeViewerButton → Button.
Detect cycles and unsupported dynamic forwarding; report them rather than treating
them as safe. The existing parser/resolution owner supplies these summaries;
this is not a general JavaScript interpreter or a runtime component registry.

Inside an owned content slot, native spans/code may provide text/accessibility
markup, but may not introduce paint, type or internal geometry. Named metadata
and status slots express approved variation. Analyze separately defined feature
children in that same rendering context; an imported BranchRevision does not
escape the rule. Independent feature content outside an owned recipe keeps its
own legitimate layout and semantic text use.

For ancestor utilities/CSS, separate styles of the container from selectors that
target descendants. A selector reaching a control/owned slot is checked against
that destination. Unsupported selectors that could reach an owned recipe fail
closed with an actionable anchor. Ordinary container padding remains permitted;
`[&_button]:text-muted-foreground` does not. Keep inherited typography explicit
at owned slots so a general feature text class cannot silently restyle them.

Preserve legal virtual transforms, total-list height and width/positioning inputs.
Never admit a broad file exemption. Negative fixtures cover ancestor styling,
nested native text, imported revision components, explicit descriptions and
forwarded/render-prop overrides; positive fixtures cover outer-section layout,
semantic metadata and real virtual positioning. These define the bounded analysis
contract before a planner chooses implementation slices.

```text
Static fixtures → existing checker → legal composition / rejected override
Real primitives + CSS → state driver → geometry / contrast / focus
Real feature + virtualizer + fixture data → scroll/filter/select identity
Real Vite + Swift backend → complete journey → existing result/error
Packaged native host → same web assets → visual/interaction observation
```

Only external data may be substituted in component scenarios; CSS, primitives
and virtualizer stay real. Those scenarios do not prove transport/native.
R1/R8 map to slot/checker ownership; R2 to role/mirror/renderer isolation;
R3/R6/R7 to compound states; R4/R5 to measured virtualized compositions.

Cut over an agreed recipe with all its consumers, removing the superseded
recipe. No permanent dual path or broad bypass. Exact tasks and commands belong
to planning only after visual choices, complete consumer coverage and concrete
interfaces are settled.
