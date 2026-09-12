# Requirements: BridgeWeb Style-System Harmonization

Owner: Shravan Sunder (sole product owner and decision authority).

This Requirements identity incorporates the owner-confirmed 2026-08-16 design-token
decisions and the accepted 2026-09-04 style-system corrections. The companion
[Specification](./2026-08-16-bridgeweb-design-tokens.md) defines the observable contract;
the separately identified Program Design defines its structural realization.

## Who is affected

| Class | Relationship |
|---|---|
| End user and daily driver | Uses the embedded File and Review surfaces and must experience them as one coherent part of the native app |
| Implementing agents | Build BridgeWeb surfaces and controls without guessing among competing token, component, and feature-local recipes |
| Owner and reviewer | Evaluates deliberate visual changes and needs accidental drift to be mechanically distinguishable |
| Native Agent Studio | Supplies the dark Swift shell and the compact visual scale with which BridgeWeb must harmonize |
| Pierre (`@pierre/diffs`, `@pierre/trees`) | Presents code and files inside BridgeWeb through the installed renderer's effective theme and style inputs |
| Annotation surfaces | Need legible, compact controls and canvas-relative styling without inventing another design vocabulary |

## Authorized needs

### U1 — One canonical styling vocabulary `authorized`

BridgeWeb needs one shadcn-conventional semantic vocabulary, with product extensions only
where a real meaning is missing. Owned primitives must be the only authority for control
paint, typography, geometry, focus, and disabled presentation. Feature consumers may choose
a semantic variant and size and may compose layout, but must not restyle those concerns.

Current evidence (validated 2026-09-04): canonical primitives and roles exist, but 37
transitional `--bridge-*` aliases, BridgeViewer class-string recipes, and feature-local
state recipes still form competing styling authorities. Priority: highest (owner).

### U2 — Normalize inconsistent presentation while preserving the File and Review experience `authorized`

The File and Review surfaces are the foundation. Inconsistent size, color, typography,
alignment, and faded disabled controls must converge rather than be preserved as accidental
differences. Normalization includes the compact type/radius/control scale,
product-versus-syntax blue separation, explicit disabled paint, floating-frame consistency,
explicit Pierre text sizing, and removal of in-tree-versus-portal differences.

The migration must identify its expected visible changes before comparing running states.
Information architecture and product behavior are preserved; a new visual design unrelated
to these inconsistencies is not implied. Priority: highest (owner).

### U3 — One canvas-relative annotation vocabulary `authorized`

Annotation surfaces need a named styling context derived from canonical semantic roles so
they remain legible on Pierre's code canvas and can express surface, text, outline, hover,
active-range linkage, composer, status, and destructive feedback without raw values or a
second control system. Annotation behavior, persistence, transport, and placement remain
outside this style-system boundary. Priority: high (owner).

### U4 — Product identity is `#409CFF`; syntax blue is separate `authorized`

Native Swift and BridgeWeb product actions and active identity must use the pinned product
blue `#409CFF`, regardless of the macOS accent preference. Pierre syntax link/function blue
remains `#89B4FA`; syntax color must not silently become product identity, and product blue
must not recolor syntax. Priority: high (owner, corrected 2026-09-04).

### U5 — Compact density harmonizes with native AppStyles `authorized`

BridgeWeb must use the native compact scale as its default visual grammar:

- type 9/11/12/13/14/16/24 px with explicit line heights;
- control heights 20/24/28/32 px;
- radii 4/6/8/14 px;
- spacing 4/6/8 px;
- fills .04/.06/.08/.10/.12/.15 and strokes .10/.15/.20/.25;
- motion 120/200 ms;
- 12 px icons in standard 24 px toolbar controls;
- 11 px labels in 28 px menu and popover action rows;
- 48 px minimum height for an empty annotation editor; and
- 12 px code and tree text so Pierre harmonizes with the surrounding chrome.

The values are correlated with `AppStyles.General` by convention; no Swift-to-web generator
is desired. The full ramp comes from the established compact design. The later explicit
choices fix toolbar icons at 12 px, menu labels/rows at 11/28 px, and the empty editor at
48 px. Priority: highest (owner).

### U6 — Drift must fail mechanically `authorized`

The normal pull-request gate must reject new raw colors outside canonical primitive homes,
new transitional aliases or uses, feature-local control geometry or state paint, a mismatch
between canonical web colors and static theme consumers, and appearance-conditional
styling in this dark-only product.

Temporary migration exceptions may identify specific existing occurrences, but count-only
allowances are unacceptable because replacing one violation with another can preserve a
count while moving the defect. The fully migrated state has no permanent exception list.
Priority: highest (owner).

### U7 — Deliberate visual change is reviewed in a running product `authorized`

The owner needs before/after evidence from equivalent running File, Review, annotation,
menu, popover, tooltip, drawer, and Pierre states for changes that can affect appearance.
Source scans and automated tests are necessary but cannot prove visual coherence by
themselves. Priority: high (owner).

### U8 — Pierre must consume the canonical system without being forked `authorized`

Pierre's effective theme and style inputs must remain compatible while Bridge-owned values
derive from the canonical color authority. Compatibility preserves working rendering,
not unused application-defined variables merely carrying a `--diffs-` prefix.
Code and tree canvases use Ghostty
grey `#282C34`; code and tree text use the explicit 12 px scale; syntax colors remain the
current Catppuccin set.

Current source evidence: Bridge overrides determine the tree's chrome colors; shadowed
theme values are cleanup rather than visible recoloring. Code syntax comes from the
registered Catppuccin Shiki theme. The 34-name root CSS block has no production consumer
in BridgeWeb or installed Pierre, and the palette mirror has no imports yet. Reachable
git-decoration and code-theme values require canonical derivation. Priority: high (owner).

### U9 — Swift, BridgeWeb, and Pierre are dark-only `authorized`

The product supports one appearance: dark. Native Swift chrome, BridgeWeb content, and
Pierre must render the same intended dark styling regardless of macOS appearance and
regardless of whether a web surface is in the shell tree or portaled to `document.body`.
No light compatibility branch is required.

Validated current evidence: `.dark` is applied to the live BridgeViewer shell, while several
owned floating primitives portal outside that ancestry. Conditional dark utilities can
therefore produce different results for the same primitive by location. Priority: highest
(owner, clarified 2026-09-04).

### U10 — Rules live where agents work `authorized`

The native and web styling authorities, their correlation, semantic layering, primitive
ownership rule, Pierre boundary, curated exceptions, and mechanical enforcement must be
documented in scoped agent instructions, permanent architecture documentation, and concise
guidance at the source-of-truth files. A capable agent must be able to add or use a control
without consulting a historical migration document. Priority: high (owner).

## Goal boundary

- **Goal:** one coherent, dark-only, shadcn-conventional BridgeWeb style system that looks
  native inside Agent Studio, uses Ghostty grey `#282C34` for the app and code canvas,
  distinguishes product blue `#409CFF` from syntax blue `#89B4FA`, centralizes control
  styling in owned primitives, preserves Pierre contracts, and blocks renewed drift.
- **May change in the later implementation:** BridgeWeb token, primitive, shared chrome,
  feature-consumer, Pierre-adapter, test, lint/check, and scoped documentation surfaces;
  bounded native styling surfaces required to pin product accent and dark appearance.
- **Protected:** Pierre package internals and effective renderer contracts, Ghostty vendor, Swift
  bridge protocol and transport, annotation product behavior, persistence, and data models.
- **Acceptance boundary:** automated contract and behavior evidence plus visual proof in the
  Vite loop and packaged Swift-hosted product where the affected surface exists.

## Non-goals

- No light theme or macOS-following appearance branch.
- No redesign of the File/Review information architecture or annotation behavior.
- No new neutral or syntax palette family; formalize the approved values.
- No Swift-to-web token generation or runtime coupling.
- No shadcn upstream-version migration merely to perform this harmonization.
- No Pierre fork, patch, replacement renderer, or app-side scroll/selection mechanism.
- No feature-local compatibility shim preserving a second styling vocabulary.
- No decision about the half-height Share drawer's vertical placement or panel inset; that is
  a separate open UI design task and must not be guessed inside this program.

## Authority and open gaps

The owner decisions above close the product meaning needed by the Specification. The exact
internal checker shape, migration ordering, wrapper retention, and file decomposition remain
Program Design or planning concerns. The separate Share-drawer vertical-placement task remains
open but does not block style-system harmonization.
