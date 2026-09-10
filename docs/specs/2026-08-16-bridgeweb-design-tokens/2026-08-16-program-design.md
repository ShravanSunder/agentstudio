# Program Design: BridgeWeb Style-System Harmonization

Requirements: [2026-08-16-requirements.md](./2026-08-16-requirements.md) (U1–U10)
Specification: [2026-08-16-bridgeweb-design-tokens.md](./2026-08-16-bridgeweb-design-tokens.md) (R1–R14)

## How the system fits together

Agent Studio has two platform styling authorities. `AppStyles.swift` owns native Swift
presentation. `bridge-app.css` owns BridgeWeb presentation. They carry the same product
identity and compact scale by documented convention; neither platform generates or reads the
other platform's values at runtime.

```text
Native Agent Studio                              BridgeWeb

AppStyles.swift                                 bridge-app.css
  native product identity                         canonical primitive values
  native compact scale                            -> semantic roles and scales
  native dark appearance                          -> product contexts and system tokens
        |                                                   |
        v                                                   +--------------------+
  Swift controls                                            |                    |
                                                            v                    v
                                                   components/ui/*       static palette mirror
                                                   control appearance     Pierre theme inputs
                                                            |                    |
                                                            v                    v
                                                   thin shared adapters   effective Pierre inputs
                                                            |                    |
                                                            +----------+---------+
                                                                       v
                                                            feature layout and content

Style-system conformance checker
  reads canonical homes + production consumers + effective renderer bindings
  -> emits sorted rule/location findings
  -> standard BridgeWeb check succeeds or fails as one result
```

The target spends complexity in three places only:

1. a CSS-canonical web vocabulary plus a checked TypeScript mirror for consumers that require
   static color values;
2. owned shadcn primitives that completely define control and floating-surface appearance; and
3. one fail-closed conformance checker that prevents another styling authority from emerging.

Feature code remains responsible for content, layout, placement, accessibility attributes,
interaction state, and callbacks. It does not own control paint or geometry. The half-height
Share panel's vertical placement and inset remain outside this design.

## Current structure and the structural change

The current token foundation is usable: `bridge-app.css` already contains a primitive palette,
semantic roles, system tokens, and an annotation-adjacent context; the palette has an unused
TypeScript mirror. The 34 root `--diffs-*` declarations have no production consumers.
Native `AppStyles` already pins product blue to `#409CFF`, and native app
startup already pins `.darkAqua` while preserving the terminal surface exception.

The current render path nevertheless has three downstream styling authorities:

```text
Current control path

feature control
  -> feature-local state/geometry classes
  -> BridgeViewer class-string recipe
  -> owned shadcn primitive
  -> --bridge-* compatibility alias
  -> semantic role
  -> primitive value
  -> rendered control

Current portal branch

owned primitive with dark:* classes
  -> shell descendant: .dark ancestor exists -> dark branch applies
  -> body portal:       .dark ancestor absent -> dark branch does not apply

Current Pierre path

code/tree adapter
  -> effective --diffs-* / --trees-* hooks and registered Shiki theme
  -> a mixture of --bridge-* aliases, raw theme literals, and canonical values
  -> Pierre render

Current enforcement path

standard BridgeWeb check
  -> general architecture checks
  -> no style-system conformance evaluation
```

Current evidence anchors are `bridge-app.css`, `components/ui/button.tsx`, `toggle.tsx`,
`input.tsx`, `textarea.tsx`, `checkbox.tsx`, the owned floating primitives,
`bridge-viewer-chrome.ts`, `bridge-viewer-button.tsx`, `bridge-viewer-filter-menu.tsx`,
`bridge-viewer-tree-theme.ts`, `bridge-code-view-options.ts`, and
`bridge-code-view-theme.ts`. The context-panel adapter currently owns its frame paint;
`drawer.tsx` owns mechanics but not the frame. The legacy `.bridge-worktree-file-*` and
`.bridge-review-projection-button` CSS selectors have no live class consumers and are deletion
inputs, not live controls needing reconstruction. Installed compatibility baselines are `@pierre/diffs` 1.2.10 and
`@pierre/trees` 1.0.0-beta.4.

The target changes the owner edges, not the product information architecture:

```text
Target control path

feature chooses semantic variant + size and supplies interaction state
  -> optional thin shared adapter supplies attributes/test identity only
  -> owned shadcn primitive resolves complete variant/size/state recipe
  -> semantic role or named product context
  -> canonical primitive value
  -> rendered control
  <- browser exposes one computed result for shell and portal placement

Target Pierre path

code/tree adapter
  -> installed renderer's effective CSS hooks and registered theme
  -> semantic roles or checked static palette mirror
  -> canonical primitive value
  -> Pierre render
  <- compatible name set and computed presentation

Target enforcement path

standard BridgeWeb check
  -> style-system conformance checker
  -> canonical homes + production source + effective renderer bindings
  <- success | sorted rule/file/line/column findings | evaluation failure
```

Removed edges are feature-to-paint, feature-to-control-geometry,
BridgeViewer-adapter-to-control-style, consumer-to-`--bridge-*`, and appearance-to-ancestor.
The feature-to-layout edge, interaction-state-to-primitive edge, and effective Pierre input edges are
intentionally unchanged.

Constraint degree is compatibility-bound by Pierre's public inputs and the approved File/Review
appearance, and migration-bound by current aliases and consumer overrides. There is no runtime
state, data, transport, or persistence change.

## Why this structure is the smallest sufficient one

The main structural choice is whether shared viewer wrappers remain a second style catalog or
become thin adapters over owned primitives.

| Direction | Gain | Cost and failure mode | Decision |
|---|---|---|---|
| Keep viewer-specific recipes | fewer immediate consumer changes | permanently preserves two owners; primitive fixes cannot guarantee cross-surface parity | rejected |
| Put complete recipes in `components/ui`; keep wrappers only where attributes or shared composition earn them | one control authority; equivalent semantics converge | consumers must select the right semantic variant and remove local repairs | selected |
| Remove every wrapper regardless of responsibility | fewest component names | duplicates shared attributes/composition at call sites and confuses style authority with component reuse | rejected |

The static-theme choice remains CSS-canonical plus a checked TypeScript mirror. Runtime
`getComputedStyle` would make worker/theme registration depend on DOM lifecycle. Generating the
mirror would add build machinery expressly excluded by the goal. The accepted debt is a two-home
edit for palette changes; the editing agent pays it, and the checker converts omission into a
local failure. Reconsider generation only if palette-edit frequency makes that repeated edit a
measured maintenance burden.

The conformance owner is a dedicated style-system checker invoked by the standard BridgeWeb
check aggregator. Folding CSS/token policy into the existing TypeScript architecture checker
would merge two unrelated reasons to change and still require a second source scanner. A
dedicated owner preserves one gate result without creating a second product styling authority.

## Owners, consumers, and dependency rules

| Owner | Owns exactly | Consumers | Changes when |
|---|---|---|---|
| `AppStyles.swift` | native product identity, dark appearance contract, compact native values | native Swift chrome | native presentation policy changes |
| `bridge-app.css` canonical blocks | web primitive values, semantic roles/scales, system tokens, product contexts | Tailwind, owned primitives, Pierre adapters | web style meaning or approved value changes |
| TypeScript palette mirror | a derived, value-identical static projection of CSS primitives | tree and code theme adapters | a static consumer needs a canonical primitive value |
| `components/ui` | complete control and floating-surface variants, sizes, and visual state recipes | shared adapters and features | a reusable interaction primitive or semantic visual state changes |
| thin BridgeViewer adapters | cross-File/Review composition, state/accessibility attributes, test identity | File and Review features | shared composition changes, never visual recipes |
| annotation context | canvas-relative annotation surface meanings derived from roles | annotation presentation | annotation presentation meaning changes |
| Pierre adapters | translation from canonical roles/mirror into effective renderer hooks and theme inputs | Pierre diffs and trees | supported Pierre contract or adapter presentation changes |
| style-system conformance checker | strict source-policy evaluation with no migration allowances | local/CI BridgeWeb gate | a structural style rule changes |

Allowed dependency direction:

```text
primitive values -> roles/scales/system tokens -> owned primitives
roles/primitives -> product contexts -> feature surfaces
primitive values -> checked TypeScript mirror -> Pierre static themes
roles/mirror -> Pierre adapters -> Pierre public inputs
owned primitives -> thin shared adapters -> feature composition
source authorities + consumers + effective bindings -> conformance checker -> gate result
```

Forbidden edges are mechanically enforced:

- feature or shared-adapter code defining control paint, type, height, padding, icon scale,
  radius, focus, disabled, invalid, open, active, or selected recipes;
- production consumers reading palette primitives directly, except checked static theme adapters;
- raw colors outside enumerated primitive homes and test fixtures;
- production `--bridge-*`, `dark:`, or `prefers-color-scheme` usage after cutover;
- TypeScript theme values that restate canonical colors; and
- a second floating-frame or active-control recipe outside `components/ui`.

The conformance checker detects forbidden token/color/geometry/appearance edges. Primitive
behavior and computed-style proof detect incomplete or inconsistent variant recipes.

## Canonical web vocabulary

`bridge-app.css` remains the authoritative web value home. Its layers are marker-delimited and
ordered:

```text
primitive palette
  -> semantic color roles
  -> compact type/radius/control scales
  -> system tokens (motion, elevation, focus, scrollbar)
  -> product contexts (annotation and effective Pierre variables)
```

The primitive palette retains the approved neutral, status, syntax, ANSI, wash, and stroke
values. Load-bearing identities are:

| Meaning | Value/derivation |
|---|---|
| app and code canvas | Ghostty grey `#282C34` |
| product primary | `#409CFF` |
| syntax link/function blue | `#89B4FA` |
| floating surface | `#323641` |
| floating border | `#58585C` |
| focus | lavender role; 2 px ring at 30% |
| invalid | destructive role; 2 px ring at 20% |

The TypeScript mirror exposes only primitive values and is never an independent authority. The
checker compares its complete key/value set with the CSS primitive block after canonical value
normalization. Missing, extra, or unequal entries fail.

The compact scale is owned once by the CSS/Tailwind theme and consumed by primitive variants:

| Scale | Effective values |
|---|---|
| type | 9/12, 11/14, 12/16, 13/18, 14/20, 16/22, 24/30 px |
| controls | `xs` 20, `sm` 24, default 28, `lg` 32 px |
| radius | 4, 6, 8, 14 px |
| spacing | 4, 6, 8 px |
| fills | .04, .06, .08, .10, .12, .15 |
| strokes | .10, .15, .20, .25 |
| motion | 120, 200 ms |

The Tailwind type names are re-anchored to this table with explicit paired line heights. This
lets a primitive use semantic scale utilities without consumer-side `text-[Npx]`, `!text-*`, or
`!leading-*` repairs.
Element resets belong in Tailwind's base layer. In particular, the current unlayered
`button, input, textarea { font: inherit; }` overrides layered typography utilities and
causes 16 px buttons beside controls with important 11 px overrides. Moving that reset into
the base layer restores the intended primitive authority; adding more important utilities
would preserve the competing owner.

## Owned primitive interfaces

Every interactive primitive exposes typed semantic variants and sizes. A caller supplies
content, variant, size, state attributes, and normal DOM behavior. The primitive returns one
complete visual treatment. It performs no product action and owns no product state.

All applicable primitives share these state postconditions:

| State | Primitive-owned result |
|---|---|
| neutral ghost/outline rest | muted foreground; transparent ghost boundary or `input`-strength outline |
| neutral ghost/outline hover and active/open | neutral accent fill and standard foreground, driven by the primitive's supported open/pressed attributes |
| selected toggle | 15% product-primary tint and product-primary foreground |
| focus-visible | ring-colored border plus 2 px ring at 30% ring color |
| disabled | pointer-inert; explicit faint text/current-color icon, explicit variant boundary, and explicit transparent or neutral fill; no whole-control opacity |
| invalid | destructive border plus 2 px ring at 20% destructive color |

Product primary has only solid, 15% tint, and text forms. A feature chooses among those forms;
it cannot manufacture another alpha rung.

The neutral rest/hover rules apply to ghost and outline controls. Primary and tint preserve
their product identity; destructive and success-outline preserve their status identity;
links preserve their text-only identity. Disabled wins over hover/open/selected for every
variant: faint foreground/current-color icons, input-strength border for framed controls,
neutral surface fill for previously filled controls, transparent fill/border for ghost/link.
Opacity remains 1. Compound fields own their single focus ring; their inner field must not
draw a second one. Menu keyboard focus is the owned row highlight.

Open-panel and boolean pressed triggers remain Buttons with neutral active/open paint:
Share while its drawer is open, comparison/menu triggers, and code-file collapse/expand.
They consume `aria-pressed`, `aria-expanded`, or `data-popup-open` as applicable.
Exclusive selection belongs to ToggleGroup: File/Review context, Review mode, and
Pending/All Share scope use product-primary selected tint. Search visibility remains a
Toggle with the same selected treatment. Attribute spelling does not determine semantics.
Primary Button hover retains its solid fill and gains the canonical ring-colored border;
it does not add an 80% product-primary rung.

The control catalog provides one coherent size ladder across Button, Toggle, ToggleGroup, Input,
Textarea, Checkbox, and compound controls:

- standard 24 px toolbar controls use 12 px icons;
- menu, combobox, and popover actions are 28 px high with 11 px labels;
- an empty annotation editor has a 48 px minimum height;
- segmented exclusive selection is a ToggleGroup-owned variant rather than a feature-local well;
- equivalent size names produce the same height, label scale, icon scale, and radius semantics.

Labels use 11/14 px for compact controls, including `xs`; menu metadata and shortcut hints
use 9/12 px. A 10 px legacy label maps by role, not by rounding: action label to 11 px,
secondary metadata to 9 px. Standard toolbar controls are 24 px with 12 px icons; segmented
items are 20 px within the 24 px group. Checkbox remains a named 14 px compact indicator,
not a button-height variant. Menus use fixed 28 px action rows unless multiline content
requires a separately named semantic variant. Status/retry actions in distinct layouts may
select different supported sizes; unrelated surfaces are not forced to the same height.

| Button/Toggle size | Height | Label / line-height | Icon | Radius |
|---|---|---|---|---|
| xs / icon-xs | 20 px | 11 / 14 px | 10 px | 4 px |
| sm / icon-sm | 24 px | 11 / 14 px | 12 px | 6 px |
| default / icon | 28 px | 11 / 14 px | 14 px | 6 px |
| lg / icon-lg | 32 px | 11 / 14 px | 16 px | 6 px |

Icon-only buttons use square dimensions matching the height. Input/InputGroup sm and default
use the 24/28 px rows with 11/14 px labels and 6 px radius. Textarea uses 12/16 px body text
and the 48 px minimum; embedded forms inherit the compound frame. Checkbox uses a 14 px
indicator, 10 px check icon, and 4 px radius.

| Primitive | Semantic interface owned by the primitive |
|---|---|
| Button | primary/default, tint, secondary, outline, ghost, destructive, link, and success-outline hierarchy; `xs`, `sm`, default, `lg`, and matching icon-only sizes |
| Toggle | default and outline rest treatments plus the singular selected treatment |
| ToggleGroup | ordinary grouping and the bordered compact segmented variant; items inherit group variant and size |
| Input and compound input | compact/default field geometry plus focus, disabled, and invalid presentation |
| Textarea | default and embedded presentation; the embedded form removes its own frame without replacing the parent field's state contract |
| Checkbox | one compact outline and one product-primary checked treatment |

Selecting a variant is the caller's action-hierarchy decision. Repairing an inappropriate choice
with `className` paint is forbidden.

Floating primitives share one frame family owned by `components/ui`: popover surface and border,
8 px frame radius for menus/comboboxes/popovers/tooltips/toasts and 14 px for side context panels.
The shared elevation is `0 10px 24px -8px` at 45% black plus `0 3px 8px -2px` at 35% black.
A side context panel chooses the current directional form: `-10px 8px 24px -8px` at 45% black
and `-3px 2px 8px -2px` at 35% black. Feature code chooses the surface primitive
and arranges its contents; it does not restyle the frame. This frame contract does not decide
panel placement, height, or inset.

| Floating primitive | Radius and typography |
|---|---|
| menu and combobox | 8 px frame; 11 px labels in 28 px action rows |
| popover | 8 px frame; 12 px body and 14 px title |
| tooltip | 8 px frame; 11 px label |
| toast | 8 px frame; 11 px title and 9 px description |
| drawer/context panel | 14 px frame; contents use the canonical type ramp |

Thin BridgeViewer adapters may translate product-neutral state to supported primitive attributes
and may add shared accessibility/test identity. They must forward semantic variant and size
without appending control appearance classes. If removing an adapter would only move attributes
or shared composition into repeated consumers, it remains; otherwise it is deleted as pass-through.

## Unconditional dark appearance and portal parity

Native app startup is the authority for dark Swift chrome. `AppStyles` is the authority for the
pinned product accent. Terminal content retains its existing per-surface light/dark exception.

BridgeWeb declares dark color-scheme and encodes the approved dark treatment directly in roles
and owned primitive recipes. Neither a `.dark` ancestor nor the macOS appearance participates in
web style selection. Body-portaled and shell-contained instances therefore consume identical
tokens and classes. A portal container remains a placement, clipping, and stacking decision only;
it is not an appearance boundary.
The Specification's reference rule governs branch folding: explicit R5–R8 recipes win;
otherwise preserve the currently active shell-contained branch. Fields retain their existing
dark fill where no new state rule replaces it.

The appearance interface guarantees:

- the shell, default `document.body` portals, and shell-contained context-panel portals resolve
  the same state recipe;
- `dark:` and `prefers-color-scheme` branches are invalid production dependencies;
- removing the current shell `.dark` marker cannot change computed control paint; and
- reduced-motion handling remains independent of color appearance.

## Annotation context

The canonical product context uses annotation terminology and derives each meaning from roles.
The active-thread fill is `color-mix(in lab, transparent 86%, var(--warning))`, preserving
the current effective value. A root-defined custom property cannot read a selection variable
that exists only on Pierre's shadow host; the misleading fallback is removed, and no shared
selection override or runtime synchronization is introduced. It covers surface, foreground, muted text, border, divider,
hover, range-linked active state, composer background, status, and destructive feedback.

Annotation components consume this context for canvas-relative surfaces and consume owned
primitives for controls. They do not redraw Pierre's source-range selection and do not define a
second focus treatment. The current `--comment-*` and mixed `--bridge-*` vocabulary is a migration
input, not a target API; the target context has one annotation-named namespace and no compatibility
alias after hard cutover. Annotation behavior, persistence, transport, placement, and selection
remain unchanged.

## Pierre adapter interfaces

Pierre remains an external rendering dependency; its packages are not modified.

The diffs adapter preserves the existing effective hooks, scoped where Pierre consumes them:
`--diffs-addition-base`, `--diffs-deletion-base`, `--diffs-modified-base`, `--diffs-fg`, and
`--diffs-fg-number` on code headers; `--diffs-computed-selected-line-bg` and `--diffs-line-bg`
for annotation selection; and `--diffs-scrollbar-gutter-override` on the panel boundary.
These are the installed-version integration surface, not a promise about every undocumented
Pierre variable. Selection logic and selector scope remain unchanged.

The root 34-name block is removed: installed Pierre does not consume those names, and no
production BridgeWeb reference gives them meaning. Syntax remains owned by the registered
Catppuccin Shiki theme. The checked mirror supplies only Bridge's theme overrides such as
`editor.background`, `editor.foreground`, and `editorCursor.background`; it does not duplicate
the external theme's syntax table.

The code renderer receives `--diffs-font-size: 12px` and canonical font-family settings on its
host so they inherit into the shadow root. Tree font settings use the corresponding
`--trees-font-size-override` and `--trees-font-family-override` inputs. Outer `pre/code`
selectors are not used to claim control of shadow-root typography. CSS embedded by
`bridge-code-view-options` may set effective Pierre variables and sanctioned DOM metrics,
but cannot reference transitional aliases or invent control styles.

The trees adapter preserves the supported override inputs and dark theme identity. It supplies
12 px tree text, Ghostty-grey canvas/`editor.background`, canonical foreground and chrome roles,
and palette-mirror-derived reachable `gitDecoration.*` values. Bridge's override-first chain
remains the visible chrome authority. Theme fields shadowed by those overrides are removed rather
than treated as independent values; the current effective tree hover and selection stay unchanged.

The code theme preserves Catppuccin syntax scopes while sourcing Bridge-owned canvas and foreground
overrides from the checked static mirror. Product blue does not replace syntax blue.

Any Pierre package-version change reopens the compatibility inventory: public names, effective
fallback order, reachable theme fields, and font hooks must be re-established before accepting the
new version.

## Style-system conformance checker

The checker is a deterministic, read-only build-time component. Its behavioral interface is:

```text
input
  canonical CSS primitive block
  checked TypeScript palette mirror
  production CSS/TS/TSX source
  effective renderer-hook and theme-binding contract

output
  success
  | sorted findings { rule, relative path, line, column, explanation }
  | evaluation failure naming the rule/scope that could not be checked
```

It owns five exhaustive rule classes:

1. raw colors are restricted to enumerated primitive homes and test fixtures;
2. transitional `--bridge-*` definitions and references are rejected without allowances;
3. control paint, typography, geometry, and interaction-state recipes outside owned primitives
   are rejected, except named non-control/Pierre contracts;
4. the CSS primitive block and static TypeScript mirror have identical normalized key/value sets;
5. `dark:` and `prefers-color-scheme` appearance branches are rejected in production BridgeWeb.

The source-policy rules use syntax-aware classification of CSS declarations and Tailwind class
tokens. They distinguish feature layout from primitive-owned control geometry and paint. Named
non-control and Pierre exceptions are part of the rule definition, not an open-ended bypass.

There is no migration ledger. The checker and consumer cutover enter the accepted bundle
together, with zero admitted violations. Adding, duplicating, moving, or substituting a
violation therefore fails regardless of totals or location; no fingerprint can transfer an
allowance. This removes the occurrence-identity mechanism entirely. The cost is one cohesive
cutover rather than separately acceptable partially migrated bundles. Intermediate working
states may fail the checker and are never presented as passing delivery checkpoints.

Existing TypeScript syntax analysis and CSS parsing distinguish control class recipes from
layout, prose, status glyphs, loading canvases, and version-bound Pierre metrics. Imported
control aliases, shared class constants, and compound composition must be covered. Unknown
dynamic control class construction fails with a diagnostic rather than escaping evaluation.
Tests include representative bypasses, not just raw hex and direct JSX strings.

The standard BridgeWeb check owns aggregation. A checker exception, parse/read error, incomplete
scope, or palette-normalization error is a failing result, never a warning or silent
pass. Findings are sorted deterministically so local and CI output agree.

## Cutover, authority, and consistency

The migration is one cohesive hard cutover:

| State | Styling authority | Permitted compatibility | Transition invariant | Recovery source |
|---|---|---|---|---|
| foundation | canonical values/roles exist, but legacy recipes still participate | current aliases and overrides | capture current effective appearance and enumerate normalization deltas | version control plus current visual baseline |
| hard cutover | canonical roles, owned primitives, and Pierre adapters are sole owners | none | zero aliases, local control recipes, appearance branches, and checker allowances | revert the cohesive cutover only with its corresponding consumers |

Within a bundled BridgeWeb build, consumer changes and removal of the aliases they used must be
atomic. There is no supported mixed bundle where a consumer expects an alias absent from its CSS.
Native and web authorities may change independently because they share no runtime interface, but
the exact convention rows are not accepted as harmonized until both values and running appearance
agree.

Style resolution is immutable after CSS and module load. There is no runtime writer, retry loop,
or cross-process synchronization. Concurrent source edits are resolved by version control;
every remaining violation fails the strict gate. The checker
uses stable source ordering and complete-set comparison, so filesystem enumeration order cannot
change its result.

## Failure containment and recovery

| Failure | Detection | Containment and result | Recovery owner |
|---|---|---|---|
| unknown or ambiguous legacy meaning | no singular role/context mapping can be established | that occurrence remains unmigrated and the change is not accepted; no guessed alias or role | style-system design owner |
| raw value, local recipe, new alias, or appearance branch appears | checker finding | standard check fails with exact location; unaffected source is not rewritten | editing agent removes or properly re-homes it |
| palette mirror differs | complete-set comparison | static themes cannot pass the gate with stale values | editing agent updates canonical value and mirror together |
| checker cannot read, parse, normalize, or cover its scope | evaluation failure | entire style-conformance result fails closed | checker owner repairs evaluation before product change proceeds |
| shell and portal computed styles differ | browser/computed-style seam | appearance migration is rejected even if one normal journey looks correct | primitive owner removes ancestry-dependent styling |
| unlisted File/Review visual delta appears | matched running visual evidence | affected migration is rejected; the allowed-delta list is not expanded after observation | product owner authorizes a new delta or implementation restores the baseline |
| Pierre name/fallback/font contract changes | adapter contract inspection and running render | package/update cutover is blocked; existing supported version remains authoritative | Pierre adapter owner re-establishes compatibility |
| reduced-motion support regresses | accessibility behavior seam | affected motion recipe is rejected | primitive or motion-context owner restores the independent reduced-motion path |

There is no partial gate success: any unadmitted finding or evaluation failure fails the aggregated
result. There is no runtime degraded style fallback; the last accepted bundle remains the recovery
truth.

## Cross-cutting realization

| Obligation | Structural owner and mechanism | Degradation/failure behavior | Proof seam |
|---|---|---|---|
| accessibility | primitive state recipes own focus, disabled, invalid, selected, and ordinary contrast; reduced motion remains independent | indistinguishable state or lost reduced-motion behavior rejects the primitive change | state-level computed style plus running keyboard/motion inspection |
| platform compatibility | native startup pins dark; web recipes are unconditional; packaged web bundle consumes static CSS/TS | macOS appearance or portal location changing presentation is a failure | Vite and packaged Swift-hosted running surfaces under both macOS appearances |
| Pierre compatibility | adapter preserves versioned public names/fallbacks and canonical derivation | unsupported name/fallback/version blocks cutover | contract inspection plus real diffs/tree rendering |
| reliability/operability | fail-closed deterministic checker is part of the ordinary gate | unknown coverage cannot pass | deliberate violation and evaluation-failure seams |
| performance | static CSS/module resolution; no runtime token synchronization or new render effect | not applicable beyond existing CSS/render cost | bundle/runtime regression floor |
| privacy, security, data lifecycle, compliance | no data, network, secrets, authorization, or persistence introduced | not applicable | scope inspection |

## How each requirement works and how it is proved

| Requirement | Structural realization | Observable/proof seam |
|---|---|---|
| R1 | canonical CSS vocabulary and forbidden dependency edges | V1 vocabulary/derivation inspection |
| R2 | CSS primitive block, roles, checked mirror, product/syntax separation | V1 complete-set and resolved-value evidence; V7/V10 identity rendering |
| R3 | cohesive consumer/alias removal with zero allowances | V1 zero-alias production scan |
| R4 | migration state preserves baseline except enumerated Specification deltas | V2 matched running File/Review evidence |
| R5 | re-anchored theme scale consumed by coherent primitive sizes | V3 geometry/type assertions and running density comparison |
| R6 | `components/ui` is the only complete control-style owner | V4 variant/state behavior and consumer-boundary inspection |
| R7 | singular primitive state table, explicit disabled paint, exact focus/invalid recipes | V4 computed and visual state evidence |
| R8 | one primitive-owned floating-frame family with named directional panel elevation | V5 computed and running surface evidence |
| R9 | one annotation-named context derived from roles; controls still use primitives | V6 derivation inspection and running annotation surface |
| R10 | `AppStyles` product identity plus native dark startup boundary | V7 running native/web identity under non-blue system accent |
| R11 | deterministic fail-closed checker with no admitted occurrences | V8 red-first rule/evaluation failures and green cutover result |
| R12 | unconditional primitive recipes independent of ancestry and macOS appearance | V9 shell/body-portal and light/dark macOS computed/running evidence |
| R13 | versioned diffs/tree adapter contracts, explicit canvas/font, checked theme derivation | V10 contract inspection and real code/tree presentation |
| R14 | scoped instructions, permanent architecture contract, and authority-header guidance | V11 point-of-use documentation inspection |

The existing unit, browser, integration, Vite, packaged-build, and native-host suites remain the
regression floor. They do not replace running visual evidence for perceptual obligations.

Accepted-requirement coverage is complete:

| Need | Structural home | Disposition |
|---|---|---|
| U1 | canonical vocabulary, primitive authority, forbidden edges | covered |
| U2 | baseline-preserving cutover and File/Review visual failure boundary | covered |
| U3 | annotation-named canvas-relative context | covered |
| U4 | separate product-primary and syntax-blue identities in native/web/Pierre owners | covered |
| U5 | compact theme scale and coherent primitive size/state contracts | covered |
| U6 | fail-closed checker with no migration allowances | covered |
| U7 | matched running visual proof seam for every affected surface family | covered |
| U8 | versioned Pierre adapters and checked static theme mirror | covered |
| U9 | native dark pin and ancestry-independent BridgeWeb recipes | covered |
| U10 | authority comments, scoped instructions, and permanent architecture contract | covered |

## Structural negative space

- no light theme or macOS-following BridgeWeb branch;
- no Swift-to-web generation or runtime token synchronization;
- no permanent compatibility aliases or migration exception ledger;
- no feature-local control skin or floating-frame recipe;
- no Pierre fork, package patch, replacement renderer, or changed public variable names;
- no annotation behavior, transport, persistence, placement, selection, or data-model change;
- no new runtime state, event, coordinator, store, network, or trust boundary; and
- no decision about Share panel vertical placement, height behavior, or inset.
