# BridgeWeb Design-Token Architecture

BridgeWeb and native Agent Studio have separate styling authorities. The native source of
truth is [`Sources/AgentStudio/Infrastructure/AppStyles.swift`](../../../Sources/AgentStudio/Infrastructure/AppStyles.swift); the web source of truth is
[`BridgeWeb/src/app/bridge-app.css`](../../../BridgeWeb/src/app/bridge-app.css). They are correlated by convention, not generation or a
runtime dependency. An editor changing an exact correlation must update both authorities in
their owning slices; approximate correlations preserve intent rather than identical storage.

## Tri-system correlation map

| Concern | AppStyles.swift (native source) | bridge-app.css (web source) | Pierre / TypeScript consumers | Correlation |
|---|---|---|---|---|
| type ramp | `Typography.textXxs..text2xl` 9/11/12/13/14/16/24 | `--text-2xs..--text-2xl`, same values after S1b | code view font size = 12 | exact |
| state fills | `Fill` .04/.06/.08/.10/.12/.15 | `--palette-wash-*`; existing pinned hover/selection hexes stay roles | row hover/selection via roles | approximate: native composes over material; existing web hex surfaces stay visually fixed |
| strokes | `Stroke` .10/.15/.20/.25 | `--palette-stroke-*` | `--diffs-border-*` via `border` / `input` | exact |
| radius | `CornerRadius` 4/6/8/14 | `--radius-*` effective set after S1b | none | exact |
| spacing | `Spacing` 4/6/8 | Tailwind 4px grid; blessed steps 1/1.5/2 | none | convention |
| motion | `Animation` 120/200ms | `--motion-fast` / `--motion-standard` | none | exact |
| accent | `accentPrimary` `#89B4FA` after native slice SN | `--primary` | Pierre link and function tokens | exact |
| status hues | adopted on native demand | `success`, `warning`, `destructive` | Pierre inserted/changed/deleted and tree git decoration | convention |
| neutrals | system materials plus alpha washes | pinned ramp `n0` through `n5` | Pierre background and derived tree palette | approximate: common rendered-gray intent, different mechanism |
| text tiers | `Foreground` opacities over material | primary/secondary/muted/faint pinned values | Pierre foreground and tree foreground | approximate: common four-tier intent, different mechanism |
| appearance | app-level dark pin after SN | `color-scheme: dark` and one styling branch | dark-only Pierre themes | exact |

## Layer and ownership rules

The dependency direction is strict:

```text
bridge-app.css primitive values
  -> semantic roles registered by @theme inline
    -> product contexts such as --diffs-* and --comment-*
      -> feature consumers and Tailwind utilities

bridge-app.css primitives
  -> checked derived mirror bridge-design-palette.ts
    -> static TypeScript theme consumers
```

Color literals live only between the exact design-primitives markers in
`bridge-app.css`. The palette TypeScript module is a derived mirror for consumers that need
static values; the checker requires the CSS and TypeScript maps to match exactly. Roles
reference primitives. Contexts reference roles or primitives. Feature code references roles
or contexts and never creates another vocabulary.

Pierre owns the public `--diffs-*` names, so those names remain frozen while their values
derive from canonical roles and primitives. Inline comments use the `--comment-*` context.
Translucent system and context colors use `color-mix(in srgb, ...)` over a named primitive or
role at the exact designed alpha.

### Primary tonal ladder

The primary role has exactly three sanctioned rungs: solid (`bg-primary` with
`text-primary-foreground`), tint (`bg-primary/15`), and text (`text-primary`). This maps
Material 3's primary / container / on-container names approximately to solid / tint / text.
React consumers use the opacity modifier, token CSS uses `color-mix` over the role, and Pierre
contract blocks pre-compose the finished value. Do not add a `--primary-tint` token, use raw
`rgba`, or invent another primary alpha.

## Cutover state

S1 establishes the palette and roles while keeping every existing `--bridge-*` definition as
a one-line alias. Existing reference sites are count-bounded in committed burn-down
allowlists. S2 through S5 migrate feature references and shrink those counts. S6 deletes the
aliases and empty allowlists. New raw colors, bridge-token references, bespoke control
geometry, or appearance branches fail immediately; a count may decrease but never increase.

Typography and radius re-anchoring are intentionally not part of S1. They land in S1b with
their own visual-delta review. The S1 foundation changes only the input stroke from 18% to the
20% stroke scale stop.

## Enforcement

[`BridgeWeb/scripts/check-bridgeweb-architecture.ts`](../../../BridgeWeb/scripts/check-bridgeweb-architecture.ts)
runs in `pnpm run check` and fails closed with file, line, and rule ID. Design-token
enforcement in this doc is the intended contract; the live checker is the architecture
script, not a separate `check-bridgeweb-design-tokens.ts`. It enforces:

1. `no-raw-color-literal`: no hex, rgb, hsl, or oklch literal outside primitive and test homes;
   the two S4 theme files have a count-bounded transitional baseline.
2. `no-bridge-token`: aliases plus only the committed existing reference counts are legal.
3. `no-bespoke-control-geometry`: feature CSS/CSS-in-TS pixel declarations and route-local
   control-size utilities cannot grow outside `components/ui`.
4. `palette-mirror`: every CSS primitive and TypeScript mirror entry matches after canonical
   hex and numeric-alpha normalization.
5. `no-appearance-branch`: `dark:` and `prefers-color-scheme` branches cannot grow and burn
   down to zero during cutover.

The app is dark-only. Upstream shadcn `dark:` variants are folded deliberately into the one
owned branch rather than copied as a second appearance path. Native chrome is pinned dark by
the native SN slice. `TerminalSurfaceScrollView` is the named exception: terminal content may
choose a per-surface appearance that matches its own background.

## Adding a token

1. Confirm no existing semantic role already states the meaning.
2. Add a literal primitive inside the marker block only when the value itself is new, and add
   the identical entry to [`bridge-design-palette.ts`](../../../BridgeWeb/src/design-tokens/bridge-design-palette.ts).
3. Define the semantic role in `:root` from a primitive, add a one-line meaning comment, and
   register it in `@theme inline` when Tailwind utilities consume it.
4. Define product-specific contexts from roles or primitives; do not expose primitives to
   feature code merely to avoid naming the meaning.
5. Run the design-token check, focused behavior tests, and the required visual proof.

## Adding a shadcn component

Check [`BridgeWeb/src/components/ui/`](../../../BridgeWeb/src/components/ui) first. If the primitive is missing, add its owned shadcn
source there, replace upstream values with Agent Studio roles and compact geometry, and fold
any upstream light/dark split into the single approved dark branch. Compose it through a
feature-neutral BridgeViewer wrapper when FileViewer and ReviewViewer share the interaction.
Route-local controls must not own interactive height, padding, font size, or radius.
