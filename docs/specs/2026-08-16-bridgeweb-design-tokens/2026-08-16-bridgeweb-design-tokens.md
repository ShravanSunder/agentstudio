# Specification: BridgeWeb Style-System Harmonization

Requirements: [2026-08-16-requirements.md](./2026-08-16-requirements.md)
(U1–U10 and its confirmed goal boundary govern this contract).

## Intended observable change

```text
CURRENT                                  REQUIRED
------------------------------------     ------------------------------------
same action changes by surface            same semantics render consistently
disabled outlines wash away               disabled remains legible
web density differs from Swift/Pierre     one compact product rhythm
in-tree appearance differs by portal      one unconditional dark appearance
product blue and syntax blue drift        distinct, stable color meanings
```

Users must experience BridgeWeb, Pierre, and native Swift chrome as one compact dark
application. Implementers must be able to choose a semantic control variant and size without
copying paint, typography, geometry, focus, or disabled recipes into a feature.

## Observable contexts

```text
Implementing agents ── control contract ──► ╭──────────────────────────╮
Native Agent Studio ── identity/density ──► │ BridgeWeb style system   │
Pierre ─────────────── CSS/theme contract ─► │        (opaque)           │
                                            ╰────────────┬─────────────╯
                                                         │ rendered UI
                                                         ▼
                                              End user and owner/reviewer

Outside this boundary: annotation behavior, transport, persistence,
Pierre internals, and Share-drawer vertical-placement decisions.
```

| Consumer | Surface it relies on | Required boundary |
|---|---|---|
| End user | File, Review, annotations, menus, popovers, tooltips, drawers | coherent dark appearance and compact interaction states |
| Implementing agent | owned shadcn primitives and semantic tokens | variant/size selection produces the complete control treatment |
| Native Agent Studio | embedded BridgeWeb presentation | shared product identity and density, without runtime token coupling |
| Pierre diffs and trees | effective CSS hooks and registered theme inputs | compatible rendering, canonical Bridge-owned values, explicit font/canvas contracts |
| Owner/reviewer | running visual proof and gate output | intentional deltas are visible; accidental drift fails |

The system is opaque in this contract. Internal modules, checker organization, migration
sequence, and wrapper retention belong to Program Design.

## Normative requirements

### R1 — One semantic vocabulary (U1)

BridgeWeb MUST expose exactly one shadcn-conventional semantic styling vocabulary. Product
extensions MUST name meanings absent from the standard roles rather than duplicate existing
roles. A style meaning reachable only through a raw value, transitional alias, wrapper recipe,
or feature-local paint rule fails this requirement.

### R2 — Canonical color identities (U1, U4, U8)

Every Bridge-owned color MUST resolve from one canonical primitive palette. Semantic roles MUST
resolve from primitives; product and Pierre contexts MUST resolve from roles or primitives.
Raw color literals MUST NOT appear outside the enumerated primitive homes and test fixtures.

The following identities are fixed:

- app and code canvas: Ghostty grey `#282C34`;
- product primary: `#409CFF`;
- Pierre syntax blue: `#89B4FA`;
- existing neutral, status, syntax, and ANSI values remain the approved palette unless a
  later owner decision explicitly changes them.

Product-primary surfaces MUST NOT use syntax blue, and syntax rendering MUST NOT be recolored
to product primary.

### R3 — Transitional vocabulary reaches zero (U1, U6)

After cutover, production BridgeWeb source MUST contain no `--bridge-*` definition or
reference. Non-color system meanings currently carried by that prefix, including motion,
shadows, and scrollbar behavior, MUST remain available under canonical semantic or system
names. A compatibility alias that keeps the second vocabulary alive is a failure.

### R4 — Existing appearance changes only by an authorized delta (U2, U7)

Equivalent before/after running states for existing File and Review surfaces MUST remain
visually unchanged except for these authorized normalization deltas:

- the compact scale in R5;
- the product/syntax identity correction in R2;
- explicit, legible disabled presentation in R7;
- consistent control state and floating-frame presentation in R6–R8;
- unconditional portal parity in R12; and
- explicit Pierre canvas/font integration in R13.

Any other visible difference MUST be identified and authorized before it is accepted. A test
passing does not convert an unlisted difference into an allowed delta.
Where R5–R8 pin a value or state recipe, those requirements govern. Otherwise the current
shell-contained rendering is the reference appearance and body-portaled instances converge
to it. Base resets MUST NOT override an owned primitive's chosen typography or geometry.

### R5 — One compact density scale (U5)

The style system MUST provide these effective values:

| Concern | Required values |
|---|---|
| type | 9/12, 11/14, 12/16, 13/18, 14/20, 16/22, 24/30 px font/line-height pairs |
| control heights | 20, 24, 28, 32 px for `xs`, `sm`, default, and `lg` |
| radius | 4, 6, 8, 14 px |
| spacing | 4, 6, 8 px |
| state fills | .04, .06, .08, .10, .12, .15 |
| strokes | .10, .15, .20, .25 |
| motion | 120 and 200 ms |

The 24 px toolbar control MUST use a 12 px icon. Menu and popover action rows MUST be 28 px
high with 11 px labels. An empty annotation editor MUST have a 48 px minimum height. Pierre
code and tree text MUST render at 12 px. Relative size variants MUST remain coherent, and a
named exception MUST state its distinct semantic need.

### R6 — Owned primitives are the complete control-style authority (U1, U5)

An owned shadcn primitive MUST define the control's height, padding, typography, icon scale,
radius, border, foreground, fill, hover, active/open, selected, focus-visible, disabled, and
invalid presentation for each supported variant and size.

Feature code and shared viewer adapters MAY select a variant and size, arrange controls, add
accessible/state attributes, and provide test identity. They MUST NOT replace or augment the
primitive's paint, typography, geometry, or interaction-state recipe. Controls with equivalent
semantics MUST render equivalently across File, Review, and annotation surfaces.

### R7 — Semantic state contracts are singular (U1, U5)

The owned primitive catalog MUST provide one coherent recipe for each applicable state:

- neutral ghost/outline rest: muted foreground; transparent ghost border or control-strength outline;
- neutral ghost/outline hover and active/open: neutral accent fill with standard foreground;
- selected toggle: 15% product-primary tint with product-primary foreground;
- focus-visible: ring-colored border plus a 2 px ring at 30% ring color;
- disabled: explicit neutral text, icon, border, and fill values; and
- invalid: destructive border plus a 2 px ring at 20% destructive color.

Whole-control opacity MUST NOT define disabled presentation. A disabled outlined control MUST
retain a readable control-strength boundary rather than attenuating a hairline twice. Product
primary has only solid, 15% tint, and text usages; no additional opacity rung may be invented.
Primary, tint, destructive, link, and status variants retain their distinct action hierarchy;
the neutral-control recipe MUST NOT erase their semantic identity. Disabled paint overrides
hover, open, and selected paint. Focus indication belongs to the focusable control or its
owned compound field; keyboard menu items use the owned row highlight.

### R8 — Floating surfaces share one visual family (U1, U2)

Menus, comboboxes, popovers, tooltips, drawers/context panels, and toasts MUST share the
canonical popover surface `#323641`, floating border `#58585C`, and one primitive-owned
radius, typography, and elevation family:

- menu and combobox frames use the 8 px radius, shared popover elevation, and 11 px labels in
  28 px action rows;
- popovers use the 8 px radius, shared popover elevation, 12 px body text, and 14 px titles;
- tooltips use the 8 px radius, shared popover elevation, and 11 px labels;
- toasts use the 8 px radius, shared popover elevation, 11 px titles, and 9 px descriptions;
  and
- drawers/context panels use the 14 px radius and MAY use a named directional variant of the
  shared elevation when their side-attached geometry requires it.

The shared popover elevation is two black-alpha shadows: `0 10px 24px -8px` at 45% and
`0 3px 8px -2px` at 35%. The permitted side-drawer variant preserves the current directional
geometry: `-10px 8px 24px -8px` at 45% and `-3px 2px 8px -2px` at 35%. Feature
code MUST NOT create another frame recipe or substitute a newly invented shared appearance.

This requirement does not choose the half-height Share drawer's vertical placement or inset.

### R9 — Annotation context derives from the canonical system (U3)

The style system MUST expose a named annotation context covering surface, foreground, muted
text, border, divider, hover, range-linked active state, composer background, status, and
destructive feedback. Each value MUST derive from canonical semantic roles. The active-thread
surface preserves its current effective warning-role hue at 14% over transparency; it does
not claim to read a value defined only inside Pierre's shadow root. Renderer-owned selection
remains unchanged. Annotation controls remain governed by R6 and R7.

Drafting, saving, replying, resolving, placement, transport, and selection behavior are not
defined by this specification.

### R10 — Native and web product identity remain pinned (U4)

With macOS configured to any accent color, native product-accent surfaces and equivalent web
product-accent surfaces MUST remain `#409CFF`. A non-blue system accent MUST NOT alter product
identity. This requirement does not change syntax colors or terminal-content appearance.

### R11 — Mechanical drift prevention (U6)

The standard pull-request gate MUST fail closed and identify each offending file, location,
and rule when production source introduces:

1. a raw color outside an enumerated primitive home;
2. a new transitional `--bridge-*` definition or reference;
3. feature-local control geometry, typography, paint, or state recipes;
4. a mismatch between canonical color values and a required static theme consumer; or
5. an appearance-conditional branch in the dark-only BridgeWeb source.

During migration, an exception MUST identify the specific admitted occurrence. Count-only
allowances are forbidden: swapping or relocating a violation while preserving a total MUST
still fail. Exceptions MUST shrink to zero and MUST NOT remain after cutover. If enforcement
cannot run, the gate MUST fail rather than silently pass.

### R12 — Dark-only appearance is unconditional and portal-safe (U9)

Native Swift chrome, BridgeWeb, and Pierre MUST present one dark appearance regardless of the
macOS appearance setting. An owned web primitive MUST render the same intended state when it
is an ordinary shell descendant and when it or its descendants are portaled outside the shell
ancestry, including default body portals.

Production BridgeWeb styling MUST NOT depend on a `.dark` ancestor, a `dark:` utility branch,
or `prefers-color-scheme`. A portal container choice MUST NOT change colors, focus, disabled
paint, or any other state recipe. Terminal content may retain its separately governed
per-surface appearance behavior.

### R13 — Pierre contracts remain compatible and explicit (U2, U8)

The compatibility baseline is `@pierre/diffs` 1.2.10 and `@pierre/trees`
1.0.0-beta.4. Compatibility applies to inputs consumed by those versions, not to a prefix
or a declaration count. Existing code-header addition/deletion/modified colors, foreground,
line-number foreground, annotation selection treatment, and scrollbar-gutter behavior MUST
remain available through their effective renderer hooks. Renderer-owned selection and syntax
behavior MUST remain intact.

The current 34-name root CSS block is application-defined and unused by production BridgeWeb
and installed Pierre. It MUST NOT be retained as a fictitious public compatibility contract
or used as proof that syntax, focus, or canvas colors are connected.

The Bridge-supplied tree contract preserves the dark theme identity and its `fg`, `bg`,
`editor.background`, `editor.foreground`, and reachable `gitDecoration.*` inputs, plus these
style overrides: background, foreground, muted foreground/background, search
foreground/background, border, selected foreground/background, selected-focused border,
focus ring, level gap, inline padding, and renamed-git color. Shadowed fallback theme fields
are not compatibility obligations.

Each Bridge-owned effective value MUST derive from the canonical system without a transitional alias. The
Pierre code and tree canvases MUST resolve to `#282C34`; code and tree font sizes MUST resolve
to 12 px; syntax colors MUST preserve their approved Catppuccin values through the registered
Shiki theme. Font settings MUST reach Pierre's rendering boundaries; an outer DOM selector
that cannot cross a shadow root is not evidence of compliance.

Tree chrome values shadowed by Bridge overrides MUST NOT be treated as visible palette
authority. Reachable theme values, including git-decoration colors, MUST derive from the
canonical palette. Existing tree hover and selection appearance must remain unchanged unless
separately authorized.

### R14 — Rules are available at the point of use (U10)

Scoped agent instructions, permanent architecture documentation, and the native/web style
authorities MUST state the primitive-to-role-to-context direction, product/syntax identity,
dark-only contract, compact scale, primitive ownership rule, Pierre boundary, curated
exceptions, and gate behavior. A capable implementer MUST be able to select and use an owned
primitive without reading this historical specification.

## Observable failure and compatibility behavior

- If a gate rule cannot evaluate its scope, the gate fails with the responsible rule rather
  than accepting unknown compliance.
- If a legacy value has more than one plausible semantic destination, the migration does not
  silently choose one; the ambiguity returns for a design decision.
- If an in-tree and body-portaled instance of the same primitive differ, R12 fails even if
  only one instance is visible in a normal journey.
- If a selected variant is inappropriate for the action hierarchy, the consumer must select
  the correct existing semantic variant; it must not repair that choice with local classes.
- A hard cutover may require simultaneous call-site changes. No dual styling API is promised.
- Pierre package internals and public variable names remain compatible; undocumented package
  internals are not made part of the product contract.
- A partial migration may carry only specifically identified existing exceptions. It may not
  admit any new occurrence or lose the effective dark appearance of an already-migrated
  surface.

## Cross-cutting obligations

- **Accessibility:** ordinary, muted, disabled, focus, selected, and invalid states must remain
  distinguishable on their supported surfaces. Text contrast must not regress from the
  approved current state. Reduced-motion behavior remains available.
- **Compatibility:** semantic results must match in the Vite development surface and packaged
  WKWebView/Swift host. Body-portaled and shell-contained variants are both required cases.
- **Privacy, security, data lifecycle:** no new data, network, authorization, or persistence
  behavior is introduced.

## Proof obligations

| ID | Requirement | Evidence that distinguishes pass from fail |
|---|---|---|
| V1 | R1–R3 | automated source and resolved-style evidence shows one vocabulary, canonical derivation, and zero aliases after cutover |
| V2 | R4 | matched visual evidence for equivalent running File and Review states, with every visible delta pre-enumerated |
| V3 | R5 | automated geometry/typography assertions plus visual comparison of controls, menus, editor, code, and tree at the specified scale |
| V4 | R6–R7 | automated variant/state behavior plus computed-style and visual evidence for rest, hover, active/open, selected, the exact 2 px/30% focus treatment, explicit disabled paint, and the exact 2 px/20% invalid treatment |
| V5 | R8 | computed-style and visual evidence that menu, combobox, popover, tooltip, drawer/context panel, and toast use the specified surface, border, radius, typography, and shared or permitted directional elevation |
| V6 | R9 | automated derivation inspection plus running annotation-surface evidence; annotation behavior remains proved by its own program |
| V7 | R10 | runtime visual evidence with a non-blue macOS accent shows native and web product identity remains `#409CFF` |
| V8 | R11 | red-first evidence for each violation class, including a same-count substitution that still fails; green evidence after removal |
| V9 | R12 | runtime/computed-style evidence under light and dark macOS settings and for both shell-contained and body-portaled surfaces shows identical dark presentation |
| V10 | R13 | automated inspection of effective versioned diffs/tree hooks and registered theme inputs, including detection of unused claimed bindings, plus visual evidence for code/tree canvas, 12 px text, syntax, tree hover/selection, and git-decoration colors |
| V11 | R14 | documentation inspection from each editing entry point verifies complete, non-conflicting guidance |

Existing BridgeWeb unit, browser, integration, Vite, packaged-build, and native-host suites
remain the regression floor. They do not substitute for running visual evidence where a
requirement is perceptual.

## Requirement coverage

| Need | Problem | Outcome | Requirement | Contract | Proof |
|---|---|---|---|---|---|
| U1 | competing styling authorities | one vocabulary and primitive authority | R1 R2 R3 R6 R7 R8 | token and owned-control surfaces | V1 V4 V5 |
| U2 | approved surfaces drift during cleanup | only authorized visual deltas | R4 R8 R13 | running File/Review/Pierre surfaces | V2 V5 V10 |
| U3 | annotations invent canvas-local styles | canonical annotation context | R9 | annotation styling surface | V6 |
| U4 | product and syntax blue were conflated | stable product identity and syntax | R2 R10 | native/web accent and Pierre syntax | V1 V7 V10 |
| U5 | web density diverges from Swift | one compact scale and state grammar | R5 R6 R7 | owned controls and Pierre text | V3 V4 |
| U6 | drift can enter unnoticed | fail-closed occurrence-specific enforcement | R3 R11 | pull-request gate | V1 V8 |
| U7 | automation cannot judge visual coherence | running owner-visible proof | R4 | visual review surface | V2 |
| U8 | Pierre has independent or implicit values | compatible canonical Pierre presentation | R2 R13 | `--diffs-*`, themes, code/tree UI | V1 V10 |
| U9 | dark styling changes by ancestry or OS | unconditional dark portal parity | R12 | Swift/Bridge/Pierre appearance | V9 |
| U10 | rules are absent at edit sites | durable point-of-use guidance | R14 | docs and authority headers | V11 |

## Negative space

- No second semantic vocabulary, feature-local control skin, or post-cutover alias layer.
- No light-theme scaffolding or macOS-following product appearance.
- No Swift-to-web generation or runtime token synchronization.
- No new palette family or syntax recoloring.
- No Pierre fork, patch, renderer replacement, or new app-side scroll/selection behavior.
- No annotation product, persistence, transport, or data-model behavior.
- No permanent or count-only gate allowance.
- No Share-drawer vertical-placement or inset decision in this specification.
