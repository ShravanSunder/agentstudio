# BridgeWeb style system audit: shadcn, tokens, and the visual contract

Date: 2026-09-04. Branch `bridge-review-design-2026-08-14`, working tree.
Scope: `BridgeWeb/src` excluding test files. Native `AppStyles.swift` read for correlation only.

This document has two jobs. Section A says how BridgeWeb controls should look, as one
contract. Section B is the inventory of where the tree deviates from that contract today,
with exact anchors, and the ordered slices that close the gap.

Evidence: four mechanical censuses (primitives, consumers, tokens, CSS-in-TS and Pierre)
were scraped by operators and then verified by reading the anchored files. Counts below
are from those scrapes re-run against the working tree on 2026-09-04.

---

## 0. Verdict in one screen

```
                 WHAT THE 2026-08-16 PROGRAM SAID            WHAT IS ON THE TREE TODAY
                 ──────────────────────────────────           ──────────────────────────────
S1  foundation   palette + roles + aliases + CHECKER          palette + roles + aliases      ✓
                                                             checker: added in PR #303, then
                                                             deleted in its last commit
                                                             b88c6045e (no reason recorded) ✗
S1b re-anchor    text-xs=11, radius 4/6/8/14                 stock Tailwind (12px, 5.76px)  ✗
S2  file-viewer  .bridge-worktree-file-* → primitives         16 bespoke CSS classes remain  ✗
S3  chrome       delete --bridge-* refs in app/, review/      245 refs across 28 files       ✗
S4  TS themes    tree theme derives from palette              5 dead Catppuccin hexes; code-view
                                                             CSS still derives from --bridge-* ✗
S5  comment ctx  --comment-* consumed by annotations          exists; partially consumed     ~
S6  cutover      aliases deleted, gate strict                 37 aliases live                ✗
docs             accent #89B4FA                              owner chose #409CFF (native)   stale
```

The token layer is structurally right (primitives → roles → contexts, `--palette-*` only
referenced from CSS). What went wrong is everything downstream of it:

1. **No gate.** The five design-token rules the architecture doc describes were built
   inside PR #303 (`90c6a3f68`) and deliberately deleted by its final pre-merge commit
   `b88c6045e` ("remove custom design token checker", no body). The only recorded
   critique is a review flag that its count-only allowlists could be gamed. Nothing on
   `main` stops raw hex, `--bridge-*` growth, bespoke control geometry, or `dark:`
   branches. Drift was free.
2. **Primitives render at the wrong density.** Because S1b never landed, `text-xs` is 12px
   and radius is 5.76px. Every chrome control must therefore force `!text-[11px]
   !leading-none` and its own radius. That forcing became a second design system
   (`bridge-viewer-chrome.ts`, `bridge-viewer-button.tsx`, `bridge-viewer-filter-menu.tsx`
   constants).
3. **Primitives disagree with each other.** Same-named sizes and states produce different
   typography, focus rings, disabled treatment, and icon sizes. Consumers then patch the
   differences locally, six times over for one visual state.
4. **Appearance is conditional in a dark-only app.** `BridgeViewerAppShell` applies
   `.dark` at the root (`bridge-viewer-app-shell.tsx:10`), so the 28 `dark:` utilities
   fire for in-tree controls. But DropdownMenu, Popover, Tooltip, and Combobox portal to
   `document.body` with no container, outside `.dark`, so the same utilities are dead
   there. Only the context-panel drawer portals under the shell. One primitive renders
   two ways depending on whether it is portaled. (Corrected 2026-09-04: an earlier
   revision claimed `.dark` was never applied.)

---

## A. The contract: how BridgeWeb controls look

The rules below are the target. Where the 2026-08-16 program design already decided a
value, that decision is kept. Where it left a gap, the gap is filled here and marked
**decide** for the owner.

### A1. Scale tokens (mirror `AppStyles.General`)

```
TYPE RAMP (re-anchored; Tailwind name → px / line-height)
  text-2xs  9 / 12      dense metadata only (chrome counts, kbd hints)
  text-xs  11 / 14      control labels, chrome titles, menu items, tooltips
  text-sm  12 / 16      body copy in panels, popover text, list rows, code (Pierre)
  text-base 13 / 18     section titles inside panels and popovers
  text-lg  14 / 20      panel headers (Drawer/Popover title)
  text-xl  16 / 22      reserved
  text-2xl 24 / 30      reserved

  Line-heights are pinned explicitly (not ratios), so `text-xs` inside an
  `inline-flex` control never exceeds the 20px xs control box.
  Controls use the bare ramp class. `/relaxed` is prose-only.
  `text-[Npx]`, `!text-*`, `!leading-*` are forbidden outside components/ui.

RADIUS (literal, not formula)
  --radius-sm  4px    xs controls, segmented-group items, kbd, checkbox
  --radius-md  6px    sm/default/lg controls, inputs, menu items
  --radius-lg  8px    menus, popovers, tooltips, cards
  --radius-xl 14px    context panel / drawer, floating panels

CONTROL HEIGHTS (one ladder for Button, Toggle, Input, menu rows)
  xs  20px   h-5   segmented-group items, inline chips, input-group buttons
  sm  24px   h-6   toolbar and header chrome controls (the BridgeViewer default)
  md  28px   h-7   default in panels, popovers, forms, menu rows (min-h-7)
  lg  32px   h-8   reserved for primary panel actions

CHROME BARS
  header / rail toolbar   32px (h-8), px-2 py-1, holds sm controls
  segmented group         24px container, p-px, gap-0.5, holds xs items

ICON SIZES (lucide, sized by the control, never by the icon)
  xs → 12px (size-3)   sm → 14px (size-3.5)   md → 14px   lg → 16px (size-4)
  decide: native toolbar icons are 11–12px; keeping 14px in sm chrome is the
  current look and is recommended.

STROKES (--palette-stroke-*)   .10 hairline · .15 muted · .20 control outline · .25 visible
FILLS   (--palette-wash-*)     .04 · .06 · .08 hover · .10 pressed · .12 active · .15 selected
SPACING                        4 / 6 / 8 (Tailwind 1 / 1.5 / 2)
MOTION                         --motion-fast 120ms · --motion-standard 200ms
```

### A2. Color roles (which role means what)

```
SURFACES                                  TEXT TIERS
  background   n1  canvas, code             foreground         #fff   primary, hover/active labels
  surface      n0  header bars, rails       muted-foreground   #c5c8  default control labels
  card/popover n3  floating surfaces        faint-foreground   #9ba1  metadata, placeholders
  muted/accent n4  de-emphasis / hover wash secondary-fg       #eaea  text on filled secondary only
  selection    n5  selected rows
  input        stroke .20  control outline    border   stroke .10  hairlines
  ring         lavender    focus              popover-border    #58585c  floating frame

PRIMARY (#409cff, owner decision 2026-08-16, native primaryHex agrees)
  solid   bg-primary text-primary-foreground     primary action only
  tint    bg-primary/15 text-primary             selected toggle / segment
  text    text-primary                           links, emphasis
  no other primary alpha. (field.tsx primary/5 and primary/10 are violations.)

STATUS  success (added) · warning (changed/pending) · destructive (deleted/error)
SYNTAX  Pierre --diffs-token-* stay Catppuccin; --palette-blue #89b4fa is a syntax
        hue, not the product accent. decide: --sidebar-primary should become
        var(--primary); today it is #89b4fa.
```

Naming trap to remove: `--bridge-text-secondary` resolves to `muted-foreground`
(#c5c8c6), not `secondary-foreground` (#eaeaea). It is the most-referenced alias in the
tree (38 refs). The cutover renames it by meaning, not by string replace.

### A3. One recipe per state, shared by every control

| State | Recipe | Applies to |
|---|---|---|
| rest (ghost/outline) | `text-muted-foreground`, border transparent (ghost) or `border-input` (outline) | Button, Toggle, menu trigger |
| hover | `hover:bg-accent hover:text-foreground` | Button ghost/outline, Toggle, menu trigger |
| active / open / pressed (non-toggle) | `bg-accent text-foreground` via `aria-pressed:` and `data-popup-open:` | BridgeViewer chrome buttons, menu/popover triggers |
| selected (toggle) | `data-pressed:bg-primary/15 data-pressed:text-primary` | Toggle, ToggleGroupItem, segmented items |
| focus-visible | `focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/30` | every control; menus use `focus:bg-accent` row highlight instead |
| disabled | `disabled:opacity-50 disabled:pointer-events-none` on the control; outline border stays `border-input` so the disabled stroke reads as a hairline (.10), not .05 | every control |
| invalid | `aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20` | Input, Textarea, InputGroup |

These live once, in `components/ui`. A consumer that writes `hover:bg-[var(...)]`,
`data-pressed:bg-[...]`, or `focus-visible:border-[...]` is re-implementing the primitive
and is a defect.

### A4. Primitive catalog (what each owned component must render)

```
Button      variants: default | tint | outline | secondary | ghost | destructive | link | success-outline
            sizes:    xs 20 · sm 24 · default 28 · lg 32 · icon / icon-xs / icon-sm / icon-lg
            label:    text-xs (11) for xs/sm; text-xs for default; icon per A1
            radius:   sm→4 for xs/icon-xs, md→6 otherwise
Toggle      same sizes, same label rule, same radius rule, selected = tint rung
ToggleGroup variants: default (spacing 2) | segmented (spacing 0, 24px bordered container,
            bg-surface, p-px, items xs 20px radius-sm)  ← replaces
            bridgeViewerChromeSegmentedControlClassName + SegmentButtonClassName
Input       sm 24 (chrome search) | default 28; text-xs; bg-input/20; outline border-input
Textarea    default min-h-16 → decide compact (min-h-12 at md scale); embedded appearance stays
Checkbox    14px, radius-sm, border-input, bg-surface, checked = primary solid
DropdownMenu content: rounded-lg, bg-popover, border popover-border, shadow-popover, p-1
            item:    min-h-7, px-2, text-xs, rounded-md, focus:bg-accent, disabled opacity-50
Popover     content: rounded-lg, border popover-border, shadow-popover, p-2.5, text-sm
            title text-lg medium
Tooltip     rounded-lg, bg-popover, border popover-border, shadow-popover, text-xs medium
Drawer/     rounded-xl, border popover-border, shadow-context-panel
ContextPanel
Sonner      surface popover, border input, title text-xs, description text-2xs
```

Floating surfaces (menu, popover, tooltip, context panel, toast) share **one** frame recipe:
`border-[var(--popover-border)] bg-popover shadow-[var(--shadow-popover)]`. Today there are
three (stock `shadow-md ring-foreground/10`, popover tokens, and the filter menu's
`--menu-*` tokens with a 10px radius).

### A5. What `bridge-viewer-chrome.ts` may still own

Layout and surface only: header bar and toolbar bar classes (height, border-b, background,
divider shadow), and the `BridgeViewerButton` / `BridgeViewerIcon` wrappers as thin
adapters that add `data-bridge-viewer-*` attributes, `aria-pressed`, and `testId`. Zero
typography, zero color, zero radius, zero focus rules. Anything else in that file is a
primitive variant that has not been promoted yet.

### A6. Curated one-offs (sanctioned, named, and bounded)

| One-off | Why it is legitimate | Boundary |
|---|---|---|
| Segmented control | Distinct interaction: exclusive group in a bordered 24px well | becomes `ToggleGroup variant="segmented"`; no route-local copies |
| Inline-comment context `--comment-*` | Sits on the code canvas, needs canvas-relative surfaces | consumed by `worktree-annotations/` only; no `--bridge-*` there |
| Pierre `--diffs-*` contract | Frozen public names | values derive from roles; Bridge sets `--diffs-font-size` explicitly (A1: 12px) |
| Pierre trees theme + style object | Library theme shape | every hex derives from `bridge-design-palette.ts`; hover/selection/description all overridden |
| Code-view sticky header `[data-diffs-header]` | Pierre-owned DOM | 40px header height is a Pierre metric, stays in `bridge-code-view-options.ts` |
| Markdown document prose | Prose, not controls | `.bridge-markdown-document` block stays in `bridge-app.css` |
| Status dots (`size-1.5 rounded-full bg-primary/warning`) | Semantic status glyph | fine inline |
| Comparison status region keyframes | Motion for one region | stays in CSS |

Everything not in this table that sets height, font size, radius, or color on a control
outside `components/ui` is a defect (Section B).

### A7. Forbidden

- `!text-*`, `!leading-*`, `text-[Npx]`, `h-[Npx]`, `rounded-[Npx]` outside `components/ui`
- `var(--bridge-*)` in new code; `var(--palette-*)` anywhere outside `bridge-app.css`
- `dark:` anything (the app is dark-only; the variant is dead code)
- a second copy of any A3 state recipe
- raw hex / rgb / oklch outside the primitives block and `bridge-design-palette.ts`
- primary at any alpha other than 15%

---

## B. Inventory: where the tree deviates

### B1. Token layer (`bridge-app.css`, 684 lines)

| Finding | Anchor | Contract |
|---|---|---|
| No `--text-*` ramp; Tailwind stock 12/14px | `bridge-app.css:18` `@theme inline` has no text tokens | A1 re-anchor (S1b) |
| Radius is a formula off `--radius: 0.45rem` → 4.32 / 5.76 / 7.2 / 10.08px | `bridge-app.css:22-28`, `:80` | A1 literal 4/6/8/14 |
| 37 `--bridge-*` aliases still defined; 2 never referenced (`--bridge-accent-soft`, `--bridge-worktree-file-layout-proof`) | `bridge-app.css:232-269` | S6 delete |
| 245 `--bridge-*` references across 28 files | census C | S2/S3/S5 migrate |
| `--bridge-text-secondary` → `muted-foreground` (documented trap) | `bridge-app.css:246` | rename by meaning |
| `--sidebar-primary` = `#89b4fa` while `--primary` = `#409cff` | `bridge-app.css:200` | decide |
| `--primary-foreground` = ansi-black; disabled primary buttons render black-on-washed-blue | `bridge-app.css:158`; screenshot 2 "Copy" | keep, but stop using solid primary for disabled-by-default actions |
| `@custom-variant dark` keyed on an ancestor class; applied by the shell, absent for body portals | `bridge-app.css:16`; `bridge-viewer-app-shell.tsx:10`; `popover.tsx:43`, `dropdown-menu.tsx:60`, `tooltip.tsx:32`, `combobox.tsx:96` | fold intended dark paint into unconditional recipes, then delete variant and all 28 `dark:` utilities |
| 16 bespoke `.bridge-worktree-file-*` control classes with px heights/fonts | `bridge-app.css:454-583` | S2 |
| `.bridge-review-projection-button { font-size: 11px }` | `bridge-app.css:437` | delete after S1b |
| `--diffs-font-size` never set; Pierre renders code at its 13px default | census D §5 | set from ramp (A1: text-sm 12) |
| Architecture doc claims checker enforces 5 rules; checker was deleted before merge and no rule exists | `docs/architecture/bridge/bridgeweb_design_token_architecture.md:72-92` vs `BridgeWeb/scripts/check-bridgeweb-architecture.ts:8-24`; PR #303 `b88c6045e` | D0 then S0 |
| Spec/design/doc say accent `#89B4FA`; owner chose `#409CFF` | `AppStyles.swift:11-13` | docs update |

### B2. Owned primitives (`components/ui`, 22 files) disagree with each other

```
                  Button sm        Toggle sm                 Input          Textarea       Checkbox
height            h-6 24           h-6 24                    h-7 28         min-h-16 64    14
font              text-xs/relaxed  !text-[11px] !leading-none text-sm 14    text-sm 14     —
                  12 / 19.5
radius            rounded-md 5.76  rounded-[min(md,8px)]     rounded-md     rounded-md     rounded-[3px]
icon              size-3 12        size-3 12                 —              —              size-2.5
focus ring        ring-2 /30       ring-[3px] /50            ring-2 /30     ring-2 /30     --bridge-focus-* ring-2
disabled          opacity-50       opacity-50                opacity-50     opacity-50     opacity-50
                  pointer-none     pointer-none              pointer-none   (no pointer-none) (no pointer-none)
                                                             cursor-not-allowed
outline border    border-border .10  border-input .20        border-input   border-input   --bridge-border-opaque
```

Additional primitive defects:

| Finding | Anchor |
|---|---|
| Button `outline` uses `border-border` (.10); shadcn stock and Toggle use `border-input` (.20). Disabled outline = 5% stroke | `button.tsx:21` |
| Button `outline` fill `dark:bg-input/30` and ghost `dark:hover:bg-muted/50` render in-tree but not inside body portals (menu, popover, tooltip content) | `button.tsx:21,25` |
| Toggle is the only primitive with `!important` typography | `toggle.tsx:18` |
| Toggle focus ring 3px/50% vs everyone else 2px/30% | `toggle.tsx:8` |
| Checkbox and Sonner import `--bridge-*` aliases into generic primitives | `checkbox.tsx:12`, `sonner.tsx:12-40` |
| `field.tsx` introduces `primary/5` and `dark:primary/10` rungs | `field.tsx:100` |
| Three floating-frame recipes: DropdownMenu/Tooltip `shadow-md ring-foreground/10`; Popover `--popover-border --shadow-popover`; Drawer `--shadow-context-panel` | `dropdown-menu.tsx:71`, `tooltip.tsx:43`, `popover.tsx:57`, `bridge-viewer-context-panel.tsx:18` |
| DropdownMenuItem `text-xs/relaxed` vs CheckboxItem/RadioItem/SubTrigger bare `text-xs` | `dropdown-menu.tsx:117,142,191,227` |
| InputGroupButton `sm` forwards nothing (renders Button default 28px inside a 28px group) | `input-group.tsx:72` |
| InputGroupButton xs radius `calc(var(--radius-sm)-2px)` ≈ 3.76px | `input-group.tsx:71` |
| 28 `dark:` utilities in 9 files (button 7, combobox 4, textarea 4, input-group 4, input 3, search-field 3, dropdown 1, field 1, toggle 1) | census A appendix, grep |
| Seven disabled recipes across the directory (census A "Disabled recipes") | `label.tsx:10` carries two on one element |

### B3. The second catalog: BridgeViewer chrome constants

`bridge-viewer-chrome.ts` (26 lines) and `bridge-viewer-button.tsx` (70 lines) plus the four
exported constants in `bridge-viewer-filter-menu.tsx:45-70` form a parallel control
system layered on top of the primitives.

```
Button variant=ghost size=sm (12px/19.5, 5.76px radius, hover bg-muted, ring-2/30)
  └─ + bridgeViewerChromeButtonClassName   h-6 min-h-6 rounded-md border !text-[11px] !leading-none
       └─ + bridgeViewerButtonClassName    text-[var(--bridge-text-secondary)]
                                           hover:border-[opaque] hover:bg-[list-hover] hover:text-[primary]
                                           focus-visible:border-[focus-border] focus-visible:outline-none
            └─ + ariaPressed branch        bg-[header-control-active-bg] text-[text-primary]
                 └─ + consumer className   (12 BridgeViewerButton call sites, 5 with more paint)
```

What the chrome layer overrides that the primitive already owns: height, radius, border,
font size, line height, foreground, hover, focus, pressed. Every one of those is an A3/A4
concern. The layer exists because the primitive defaults are wrong for this app (B2), not
because chrome needs a different design.

| Constant | Overrides | Consumers |
|---|---|---|
| `bridgeViewerChromeButtonClassName` | h-6, radius, `!text-[11px] !leading-none` | wrapper |
| `bridgeViewerChromeIconButtonClassName` | h-6 w-6 rounded-md px-0 | 6 sites |
| `bridgeViewerChromeSegmentedControlClassName` | 24px bordered well, `--bridge-*` bg/border | 4 sites |
| `bridgeViewerChromeSegmentButtonClassName` | h-5 `rounded-[5px]` `!text-[11px] !leading-none` | 5 sites |
| `bridgeViewerChromeSegmentIconButtonClassName` | h-5 w-5 `rounded-[5px]` | 1 site |
| `bridgeViewerChromeIconClassName` | `size-3 text-[10px] leading-none` span wrapper | BridgeViewerIcon |
| `bridgeViewerFilterMenuSurfaceClassName` | `rounded-[10px]`, `--bridge-menu-*` border/shadow/ring, p-2 | 3 sites |
| `bridgeViewerFilterOptionClassName` | `rounded-[7px] text-[13px]`, `--bridge-*` focus paint | 5 sites |
| `bridgeViewerFilterClearClassName` | h-8 `rounded-[7px] text-[13px]` `data-disabled:opacity-55` | 2 sites |
| `bridgeViewerMenuTriggerClassName` | `text-[12px]`, full hover/focus/open paint | 2 sites |

Radius families in play on controls today: 3px, 3.76px, 4.32px, 5px, 5.76px, 6px, 7px,
7.2px, 10px, 10.08px. The contract has four.

### B4. Feature-local recipes (the snowflakes)

The "active chrome surface" pair (`--bridge-header-control-active-bg` +
`--bridge-text-primary`) is hand-written six times, keyed off four different attributes:

| Site | Attribute | Anchor |
|---|---|---|
| BridgeViewerButton `ariaPressed` | `aria-pressed` prop branch | `bridge-viewer-button.tsx:43-44` |
| Share scope toggles | `data-pressed:` and `aria-pressed:` | `worktree-annotation-share-mode.tsx:18` |
| Menu trigger | `data-popup-open:` | `bridge-viewer-filter-menu.tsx:69` |
| Comparison trigger | `data-popup-open:` | `bridge-review-comparison-control.tsx:37` |
| Code-view collapse button | `aria-expanded:` (cancels hover) | `bridge-code-view-header-renderers.tsx:61` |
| Comment action button | `aria-expanded:` with `--comment-*` | `worktree-annotation-inline-surface.tsx:206` |

Other feature-local geometry/paint on primitives (census B §3b, 32 files, 163 usages):

| Site | What it re-styles | Severity |
|---|---|---|
| `bridge-review-comparison-control.tsx:33-38` | `buttonVariants(outline)` + `bridgeViewerButtonClassName` + local border/bg + open paint. Three authorities on one trigger | high |
| `worktree-annotation-share-mode.tsx:18,122,129-140` | ToggleGroup gets segmented well + `grid w-full grid-cols-2` + local pressed paint; items `!text-[11px]` | high |
| `bridge-viewer-search-field.tsx:42-66` | Input shell: local border/bg/focus-within ring, inner Input `h-6 !text-[11px] !leading-none focus-visible:ring-0`, `disabled:opacity-35` | high |
| `bridge-viewer-filter-menu.tsx` + `bridge-viewer-view-settings-menu.tsx` | Menu at 13px / h-8 / 7px+10px radii; separators re-painted 6× with `bg-[var(--bridge-border-subtle)]` | medium |
| `bridge-code-view-header-renderers.tsx:55-63` | icon-sm ghost Button + full hover/focus/expanded paint | medium |
| `bridge-review-comparison-branch-selector.tsx:116-128` | Combobox shell `rounded-md border-input bg-input/20 focus-within:border-ring` rebuilt by hand; ComboboxInput `rounded-none border-x-0 border-t-0` | medium |
| `bridge-viewer-context-panel.tsx:18` | rounded-xl (10.08px) + popover tokens: correct intent, wrong radius until S1b | low |
| `review-viewer-fallback-shells.tsx:242-276` | 8 Skeletons painted `bg-[var(--bridge-surface-raised-bg)]` | low |
| `worktree-annotation-composer.tsx:450`, `thread-message.tsx:420` | Textarea `min-h-16` re-asserted | low |

Typography classes on controls outside `components/ui`: `text-[11px]` 18 sites,
`!text-[11px]` 4, `text-[13px]` 3, `text-[10px]` 4, `text-[12px]` 1. After A1 every one of
these becomes `text-xs` / `text-2xs` / `text-base` or is deleted.

### B5. Pierre and trees integration

| Finding | Anchor |
|---|---|
| Tree hover resolves `--trees-bg-muted` → Bridge's `--trees-bg-muted-override` (= `--muted`, n4). The Catppuccin `#313244` in the theme object is shadowed, not leaking. (Corrected 2026-09-04.) | `bridge-viewer-tree-theme.ts:60`; Pierre `style.js` chain |
| Every chrome-colour key in the tree theme object is shadowed by a Bridge `--trees-*-override` (bg, bg-muted, border, fg, fg-muted, focus-ring, search-bg/fg, selected-bg/fg, selected-focused-border). Only `gitDecoration.*` (green/red/blue = palette primitives) and `fg`/`bg` still reach the DOM. The five non-palette hexes `#6C7086 #181825 #45475A #CDD6F4 #313244` are dead code, not drift | `bridge-viewer-tree-theme.ts:9-24,50-71` |
| Tree font 13px (Pierre default), code 13px (Pierre default), chrome 11px, panels 12px | census D §5; no `--trees-font-size-override` / `--diffs-font-size` |
| Code-view `unsafeCSS` uses `--bridge-*` for five `--diffs-*` derivations and header paint | `bridge-code-view-options.ts:81-142` |
| Code-view header height 40px is a Pierre metric, matched in `itemMetrics.diffHeaderHeight` | sanctioned (A6) |
| `--comment-*` context is defined; annotation surfaces still mix it with `--bridge-*` and `--comment-*` hover pairs | `worktree-annotation-inline-surface.tsx:203-215` |

### B6. Why the three screenshots look wrong

```
Screenshot 1 / 3  (review toolbar: Choose target · segmented group · gear)
  "Choose target"  = Button outline sm (12px/19.5 relaxed, border .10)
                     + BridgeViewerButton (11px !important, ghost hover)
                     + local border-subtle + header bg + open paint
  segment items    = ToggleGroupItem sm (11px !important, ring 3px/50)
                     in a bridgeViewerChrome well (5px radius items in a 5.76px well)
  gear             = DropdownMenuTrigger with a FOURTH recipe (12px, h-6)
  Three adjacent controls, three label sizes (11 forced / 11 forced / 12),
  two radii, two focus rings, hover from two token sets.

Screenshot 2  (Share annotations drawer)
  title            text-sm 14px medium
  "Include" label  text-[11px]
  Pending / All    Toggle sm → 11px !important, leading-none
  Copy / Export    Button outline sm → 12px / 19.5px relaxed
                   disabled → opacity 50% over a .10 border → ~5% stroke,
                   icon and label wash to ~50% grey
  Four sizes in one 384px panel: 14 / 11 / 11 / 12. That is the
  "text at the top is not correct" symptom. (The blue "Dictation
  Engineering" pill is the macOS Dictation indicator, not BridgeWeb.)
```

---

## C. Remediation slices (ordered) and owner decisions

Each slice is one PR, one worktree, with the proof gate named. Order matters: the gate
first so nothing regresses while the rest lands; the ramp second so the chrome layer can
be deleted rather than migrated.

| Slice | Scope | Proof gate | Depends on |
|---|---|---|---|
| **D0 → S0 gate** | Decide whether the `b88c6045e` deletion is superseded. Then either recover `check-bridgeweb-design-tokens.ts` from `origin/toggle-primary-selection` (`90c6a3f68`) with occurrence-specific allowlists (the review objection to count-only lists), or write the rules into `check-bridgeweb-architecture.ts`; wire into `pnpm run check`; any growth fails | red-first: one deliberate violation fails with file:line, then passes | owner D0 |
| **S1b ramp + radius** | Pin `--text-2xs..2xl` and line-heights per A1; radius literal table; delete `.bridge-review-projection-button`; set `--diffs-font-size` and `--trees-font-size-override`; delete every `!text-[11px] !leading-none` and `text-[11px]` on controls in the same PR | owner screenshot review of toolbar, share drawer, menus, code view, tree (named deltas: text-xs 12→11, text-sm 14→12, radii) | S0 |
| **S1c primitive harmonization** | `components/ui` only: one focus, one disabled, one hover, one active recipe (A3); outline → `border-input`; Toggle drops `!important`; fold the intended dark paint into unconditional base recipes, verify in-tree and body-portal surfaces, then delete all `dark:` and `@custom-variant dark` and the `.dark` class on the shell; Checkbox/Sonner drop `--bridge-*`; `field.tsx` primary rungs removed; one floating-frame recipe; `ToggleGroup variant="segmented"`; Button/Toggle `sm` label = `text-xs`, icon 14px | unit: variant snapshot strings; browser: focus/disabled/pressed states per primitive | S1b |
| **S3 chrome cutover** | Delete paint/typography/radius from `bridge-viewer-chrome.ts`, `bridge-viewer-button.tsx`, filter-menu constants; consumers use primitive variants; six active-state copies → `aria-pressed:` / `data-popup-open:` in the primitive; search field → InputGroup; comparison trigger → one Button; branch selector → Combobox defaults | screenshot pairs on the 8 chrome surfaces; allowlist counts for `--bridge-*` in `app/` and `review-viewer/` reach 0 | S1c |
| **S2 file viewer** | `.bridge-worktree-file-*` → primitives | as planned 2026-08-16 | S1c |
| **S4 TS themes** | Delete the shadowed Catppuccin chrome keys from the tree theme object; keep `gitDecoration.*` and `fg`/`bg` sourced from the palette mirror; `bridge-code-view-options.ts` `--diffs-*` derivations → roles instead of `--bridge-*`; bind `editor.background` to the canvas role via the mirror | screenshot of tree hover/selection unchanged (pure deletion) | S1b |
| **S5 comment context** | annotation surfaces consume `--comment-*` only | allowlist for `--bridge-*` in `worktree-annotations/` → 0 | S3 |
| **S6 cutover** | delete 37 aliases; allowlists empty and removed; docs updated (accent, checker, code font) | `mise run test` green; `rg 'var\(--bridge-'` = 0 | S2–S5 |

Owner decisions before S1b starts:

| # | Decision | Recommendation |
|---|---|---|
| D1 | Re-anchor Tailwind names (`text-xs`=11) vs keep stock and bless `text-[11px]` | re-anchor; the program design already selected it and the chrome layer only exists because it did not ship |
| D2 | sm chrome icon 14px (current) vs 12px (native toolbar) | keep 14 |
| D3 | Menu rows 13px / 32px (current filter menu) vs 11px / 28px (primitive after S1b) | 11 / 28; menus then match toolbar and popovers |
| D4 | `--sidebar-primary` → `--primary`; Pierre modified/link stay `#89b4fa` | yes |
| D5 | Disabled: keep `opacity-50` with `border-input` outline (hairline result) vs explicit disabled paint | keep opacity, fix outline border |
| D6 | Dissolve `BridgeViewerButton` into `Button variant="ghost" size="sm"` plus a data-attribute adapter | yes; wrapper keeps attributes only |
| D7 | Textarea default `min-h-16` → compact | `min-h-12` |

---

## D. Census numbers (working tree, non-test, 2026-09-04)

| Measure | Count |
|---|---|
| `components/ui` primitives | 22 |
| product files importing `components/ui` (excl. `components/ui` internals; incl. 2 Toaster-only bootstraps) | 26; 163 primitive usages across 33 files when wrapper and primitive-internal files are included |
| usages that re-style geometry / typography / paint | 32 files (census B §3b) |
| `var(--bridge-*)` references / distinct referenced / defined / files | 245 / 35 / 37 / 28 (no undefined refs) |
| `var(--palette-*)` outside `bridge-app.css` | 0 (correct) |
| `dark:` utilities / files | 28 / 9; `.dark` class applied: never |
| `!text-[11px]` / `!leading-none` | 4 / 4 (9 occurrences incl. one browser suite) |
| Tailwind arbitrary values (color var / size / other) | 263 total: 167 / 72 / 24 |
| raw color literals outside primitives block | palette mirror, tree theme (13), code-view theme (3), CSS comments only |
| `text-[11px]` / `text-[13px]` / `text-[10px]` / `text-[12px]` | 18 / 3 / 4 / 1 |
| `text-xs/relaxed` / `text-xs` / `text-sm` | 42 / 22 / 17 |
| control radius literals on the tree | 3, 3.76, 4.32, 5, 5.76, 6, 7, 7.2, 10, 10.08 px |
| bespoke `.bridge-worktree-file-*` classes | 16 |
| CSS-in-TS stylesheets | 3 (tree, code-view, file-viewer code-view) |
| `--diffs-*` names Bridge defines / Pierre exposes | 34 / 101 |
| `--trees-*` names Bridge sets / Pierre exposes | 16 / 197 |
| tree theme hexes with no palette primitive (all shadowed by overrides) | 5 |
| design-token checker rules on `main` | 0 of 5 documented |

Operator receipts (session scratchpad, not committed): `A-primitive-census.md`,
`B-consumer-census.md`, `C-token-census.md`, `D-css-in-ts-census.md`.
