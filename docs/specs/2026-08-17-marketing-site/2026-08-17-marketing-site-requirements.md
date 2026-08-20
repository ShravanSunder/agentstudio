# Agent Studio Marketing Site Requirements

## Purpose

Agent Studio needs a public product site that lets a developer understand the product's organizing idea, inspect credible product proof, and reach installation or GitHub without reconstructing the story from repository documentation.

The site presents Agent Studio as a native macOS workspace for staying oriented while multiple coding agents run across repositories and worktrees. It does not replace the repository README as the source of shipped product claims.

## Authority and evidence

The product owner authorized the following direction in the 2026-08-17 website discussion:

- the website lives in a dedicated Agent Studio worktree and under the repository's existing `web/` boundary;
- all authored website code is TypeScript;
- Astro may use React, but React is introduced only when it materially improves an interactive boundary;
- the first deployment uses static output on Cloudflare Pages;
- product proof combines recognizable hero imagery with one clickable,
  product-faithful workspace that contains the complete feature explanation;
- the current Agent Studio theme, icon, screenshots, and README own the product identity and shipped claims;
- every website product image is captured purposefully from one dedicated debug Agent Studio fixture at one approved geometry; existing README screenshots remain reference evidence and are not automatic website assets;
- Herdr is prior art for the clickable product-plate interaction and page discipline, not a visual skin to copy.

Current evidence:

- `README.md` describes the shipped positioning, install path, panes, drawers, repository/worktree navigation, Quick Find, Review, and persistence behavior.
- `web/images/` contains the four current README product images and no existing website application.
- `BridgeWeb/` proves the repository's current TypeScript, React, Tailwind, pnpm, Oxlint, Oxfmt, Vitest, and Playwright conventions.
- `BridgeWeb/src/app/bridge-app.css` and `Sources/AgentStudio/Infrastructure/AppStyles.swift` own the current semantic theme and product primary.
- Herdr's public source and live site prove that a convincing clickable product plate can be pre-authored HTML with a small state controller rather than a live product backend.
- Current Astro and Cloudflare documentation establish that a static Astro build deploys to Cloudflare Pages without a Cloudflare adapter or direct Cloudflare Vite plugin.

External platform and prior-art sources:

- Astro React integration: <https://docs.astro.build/en/guides/integrations-guide/react/>
- Astro islands and client directives: <https://docs.astro.build/en/concepts/islands/>
- Astro Cloudflare integration boundary: <https://docs.astro.build/en/guides/integrations-guide/cloudflare/>
- Cloudflare Pages Astro deployment: <https://developers.cloudflare.com/pages/framework-guides/deploy-an-astro-site/>
- Cloudflare Vite plugin boundary: <https://developers.cloudflare.com/workers/vite-plugin/>
- Tailwind v4 Astro integration and theme variables: <https://tailwindcss.com/docs/installation/framework-guides/astro> and <https://tailwindcss.com/docs/theme>
- WAI-ARIA tabs interaction contract: <https://www.w3.org/WAI/ARIA/apg/patterns/tabs/>
- Herdr product-plate fixture and controller at revision `51b7064ef0a02642393bab1d2eea0f4dbd8414d2`: <https://github.com/herdrdev/herdr/blob/51b7064ef0a02642393bab1d2eea0f4dbd8414d2/website/index.html#L191-L390> and <https://github.com/herdrdev/herdr/blob/51b7064ef0a02642393bab1d2eea0f4dbd8414d2/website/index.html#L698-L781>

## Affected people

### Prospective developer users

Developers running or considering multiple coding agents need to understand why Agent Studio is different from a terminal with tabs and whether its organization model fits their work.

### Existing Agent Studio users

Existing users need a stable place to share the product, revisit installation, and see a concise representation of current product behavior.

### Maintainers

Maintainers need a TypeScript-first website system that follows the repository's frontend conventions, preserves the README's image paths, and does not couple marketing presentation to the native app runtime.

### Release operators

Operators need a deterministic static build, pull-request previews, and a production deployment that does not introduce an unnecessary server runtime.

## Authorized needs

| ID | Need or outcome | Why it matters | Priority | Authority |
| --- | --- | --- | --- | --- |
| U1 | A prospective developer can identify the product, intended user, and core outcome from the first viewport. | The category and value must be understood before feature detail. | Must | Product owner |
| U2 | A prospective developer can inspect product-faithful behavior rather than relying only on marketing copy. | Agent Studio's spatial organization is easier to understand by interaction and real imagery. | Must | Product owner |
| U3 | A prospective developer can evaluate parallel work, pane drawers, navigation, Review, and Git/pull-request context without leaving the page through one visually consistent, purpose-made capture suite, then inspect persistence and other shipped details in a quieter expandable follow-up. | The primary states must each read clearly in one still; sequence-dependent and supporting capabilities need more room without weakening the main spatial story. | Must | Product owner and current README |
| U4 | A visitor can reach the supported Homebrew installation path and GitHub repository without ambiguity. | Interest must convert into an executable next step. | Must | Product owner and current README |
| U5 | Keyboard, assistive-technology, reduced-motion, and narrow-screen users receive an equivalent understandable product story. | Product proof cannot depend on pointer-only or involuntary motion. | Must | Product owner and platform accessibility expectations |
| U6 | Maintainers author website behavior in TypeScript and reuse the repository's established frontend quality standards where they fit. | A second untyped or unrelated frontend culture would raise maintenance cost. | Must | Product owner |
| U7 | The site deploys as static output with preview deployments on Cloudflare Pages. | Static delivery is sufficient for the first release and keeps operations small. | Must | Product owner |
| U8 | Brand and product claims remain traceable to current Agent Studio sources. | Marketing must not drift into obsolete colors, screenshots, or roadmap claims. | Must | Product owner and repository instructions |

## Goal boundary

The first release is one public marketing homepage with two complementary proof modes:

1. a concise hero with positioning, install, GitHub, and recognizable product
   imagery that may become the approved silent website loop when it is ready;
2. a clickable, product-faithful Agent Studio workspace that switches among a bounded set of pre-authored screens;

The clickable workspace owns the primary Parallel work, Pane drawer, Quick
Find, Review, and Git/pull-request context explanation. A restrained expandable
feature list follows it and owns persistence plus any later owner-approved
supporting details. It does not repeat the five primary stories as long-form
sections.

The website may change `web/`, website-specific package/configuration files, website build integration, and website deployment workflow. It may read or copy approved brand values and assets from their current owners. It must not change native application behavior, Bridge protocols, app persistence, or release packaging to serve the website.

## Existing foundation to preserve

- The four `web/images/` files and their repository-relative paths remain valid because `README.md` references them directly. They remain README/reference assets; the website uses a separate approved capture suite.
- `README.md` remains the authority for shipped capability claims and planned-versus-shipped boundaries.
- The canonical icon palette, including blue `#89B4FA`, cyan `#74C7EC`, peach
  `#EF9F76`, and its dark plane surfaces, remains the website brand input.
- BridgeWeb remains the embedded native-app web surface. The marketing site does not become another Bridge runtime consumer.
- The repository continues to use pnpm, strict TypeScript, Oxlint, Oxfmt, Vitest, and Playwright conventions for TypeScript work.

## Non-goals

- No live connection to a visitor's Agent Studio application.
- No simulated shell execution, agent execution, repository access, authentication, account system, analytics backend, database, KV, D1, R2, or other Workers binding in the first release.
- No server-side rendering or on-demand rendering in the first release.
- No full documentation migration or new documentation information architecture.
- No reuse of BridgeWeb's native transport, workers, telemetry, product state, or generated app bundle.
- No copied Herdr colors, terminal fixtures, mascot, wording, or inaccessible pointer-only interaction semantics.
- No roadmap capability represented as shipped product behavior.
- No requirement that React be present when the selected behavior remains clearer without it.

## Acceptable complexity

The first release may add one Astro site, Tailwind's CSS-first Vite integration, a small typed interactive-demo controller, a dedicated debug capture fixture and frozen website image suite, static media handling, website-focused tests, and Cloudflare Pages deployment configuration.

Scope reopens if a confirmed requirement needs a live backend, authenticated state, server rendering, Workers bindings, cross-page client state, or an interactive component whose state and composition are no longer clear as an Astro-rendered DOM plus typed controller.

## Outcome-level evidence

- A production-equivalent static build renders without a server runtime.
- Desktop and narrow-screen visual evidence shows the complete hierarchy and readable proof surfaces.
- Keyboard and assistive-technology evidence demonstrates complete interactive-demo navigation and selection state.
- Reduced-motion evidence shows a poster-first hero and nonessential motion disabled.
- Product-state evidence demonstrates every approved clickable screen, the
  required persistence disclosure, and each matching current claim.
- Capture-manifest evidence shows every website image came from the same approved debug build, fixture, window geometry, scale, theme, and source revision.
- Installation and GitHub actions resolve to the current supported targets.
- A Cloudflare preview deployment serves the generated static site for a pull request.

## Open owner choices

- Final public domain and canonical URL.
- Final marketing copy and narration-derived hero loop.
- Whether the interactive plate remains a typed DOM controller after its static prototype is reviewed or crosses the stated threshold for a React island.
