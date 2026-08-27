# Agent Studio social attribution contract

Date: 2026-08-27

## Outcome

Agent Studio campaign links identify both the distribution channel and the
specific campaign creative without cookies, visitor identifiers, fingerprinting,
advertising pixels, or query-string tracking.

The public URL family is:

```text
/x/<code>   X
/yt/<code>  YouTube
/c/<code>   source-agnostic campaign sharing
```

The aggregate routes `/x`, `/yt`, and `/c` identify only the channel. The
canonical homepage remains `/`.

## Identity contract

Each registered creative owns one stable four-character lowercase code. The
code is deterministically derived from the creative's immutable campaign,
creative, and variant keys. The same creative uses the same code across
channels; the first path segment supplies the channel axis.

The code is not treated as reversible by itself. One checked-in typed registry
is the reverse lookup from code to campaign, creative, variant, and
channel-specific placement. Registry construction fails on a code collision or
duplicate identity.

Unknown nested codes are not classified and remain 404. A missing code is not
an error: the aggregate route records only the known channel.

## Page and discovery contract

Every aggregate and registered campaign route:

- returns a direct static HTTP 200 rather than redirecting;
- renders the exact shared homepage composition;
- uses `/` for `rel=canonical` and `og:url`;
- uses the approved social card and the title
  `Agent Studio: Native macOS IDE for parallel coding agents`;
- remains crawlable for social-card fetchers;
- stays out of the sitemap, internal navigation, and ordinary site information
  architecture.

The homepage is the only sitemap URL.

## Measurement contract

Cloudflare Web Analytics is the primary owner-facing report. It measures page
loads whose privacy-preserving browser beacon succeeds and is filtered by exact
Path. It is not exhaustive traffic and must not be described as people, unique
clicks, or conversions.

Cloudflare Security Analytics is the request-level crosscheck. It measures
campaign-path requests, including social preview fetches, bots, retries,
refreshes, and sampled traffic.

The registry joins each observed path to these bounded marketing dimensions:

```text
channel × campaign × creative × variant × placement
```

Platform-native X and YouTube metrics remain separate. X link clicks and
YouTube video engagement do not become website conversions merely because they
share a campaign code.

Analytics Engine is not part of the initial design. The path plus registry
already supplies the required bounded dimensions, while Web Analytics and
Security Analytics supply the two required observations. Analytics Engine may
be reconsidered only for an approved server-side custom-reporting requirement.

## Failure behavior

- Analytics failure never changes navigation, rendering, installation, or any
  other website behavior.
- An unknown code returns the ordinary static 404 and is not mapped to a known
  campaign.
- A registry collision fails build-time generation rather than silently
  changing or merging campaign identity.
- A blocked Web Analytics beacon remains an acknowledged undercount and is not
  backfilled with a visitor identifier.

## Proof obligations

- focused tests cover deterministic codes, collision rejection, aggregate and
  registered routes, unknown-code 404 behavior, canonical metadata, exact
  social metadata, and sitemap exclusion;
- format, lint, strict typecheck, unit/browser checks, and production build pass;
- Cloudflare build and prebuilt dry run pass;
- the exact deployed routes return direct 200 and the expected metadata;
- delivered HTML contains Cloudflare's injected beacon and a controlled route
  visit successfully sends the RUM request;
- the Cloudflare owner dashboard visibly reports the controlled exact path;
- Security Analytics supplies the bounded request crosscheck;
- the real X composer shows the exact title, approved card, and clean campaign
  path without publishing the proof post.

