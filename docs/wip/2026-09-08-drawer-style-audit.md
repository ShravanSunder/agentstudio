# Drawer style audit

Scope: current UI changes on bridge-review-design-2026-08-14 at1584e3fb7
plus shared dirty source. Parent source audit, not independent implementation
review. Transport and output-capture helpers remain outside this correction.

Authority: user-approved component-language contract, now located in
[architecture](../architecture/bridge/bridgeweb_design_token_architecture.md#component-language-contract).

| Source finding | Disposition |
|---|---|
| Compare used small muted CardTitle; larger target reversed hierarchy. | Removed small title recipe earlier; standard13px section heading,12px summary values;14px panel title. |
| DrawerDescription inherited11px medium header styling. | Explicit12px regular supporting recipe. Permanent rendered regression reproduced11px before correction. |
| DrawerHeader resized all descendant SVGs. | Removed blanket selector; Button owns control icons. Plain panel titles match across Compare and Share. |
| Header divider enabled by default, disabled independently by both callers. | No-divider shared default; explicit opt-in remains for a real boundary. |
| Compare lacked Share's visible close action. | Compose existing DrawerClose/Tooltip/Button; test query cancellation and trigger focus. No new close state/controller. |
| Body inset and scrolling repeated in each drawer. | Shared DrawerBody; document-flow default preserves Share scrolling, Compare requests flex layout. An initial flex default failed the existing scroll test and was corrected. |
| History locally defined footer wrapping/gap. | CardFooter owns wrap and8px gap; caller no longer overrides. |
| History date used11px local caption. | CardDescription supplies12px supporting text; timestamp semantics preserved. |
| History section disclosure used11px toolbar typography. | Shared CollapsibleHeading composes standard Button interaction with13px section-heading typography; no feature override. |
| Compare attempt status used local uppercase/muted heading and description; Share Include used a local muted span. | Existing Alert title/description/action slots and FieldTitle now own these recipes. State, copy and retry callback preserved. |
| Title/description slots absent from checker classification. | Registered CardTitle/CardDescription/DrawerTitle/DrawerDescription and added negative override fixture. |

Legitimate retained feature layout: Compare's field grid and available list height,
Share's message grouping, virtualizer positioning, and History expansion. These
are not button or title recipes. Existing exact-byte code presentation is reading
content, not an interactive control; its separate presentation remains unchanged.
No palette, Pending/All membership, output lease, Repeat eligibility or transport
change in this correction.

Documentation chain: root AGENTS → BridgeWeb AGENTS → existing architecture
contract → owning primitives and proof. Old spec files were not deleted or
rewritten; the architecture explicitly identifies superseded visual trials while
preserving domain authorities.

Proof receipts: tmp/2026-09-08-drawer-contract-red.log,
tmp/2026-09-08-drawer-contract-green-final.log,
tmp/2026-09-08-drawer-contract-check-final.log. Read their actual outcomes before
making completion claims. Current packaged-native and independent visual review
are not established by these scoped browser/check receipts.

Final scoped result:62/62browser tests in6files passed, exit0, at
tmp/2026-09-08-drawer-contract-delivery-verified.log. Checker38/38 passed, exit0;
quality exit0 at tmp/2026-09-08-drawer-contract-delivery-quality.log.98relative
documentation links resolved; git diff --check exit0. Live Chrome5197 confirmed
Share/History grouping and Compare title/close layout; after close motion the
Compare trigger regained focus. No packaged-native or aggregate result claimed.
