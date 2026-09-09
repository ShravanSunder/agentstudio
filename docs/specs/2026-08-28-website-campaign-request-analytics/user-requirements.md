# Website campaign-request analytics — user requirements

Date: 2026-08-28

## Goal boundary

Give Agent Studio an owner-accessible, first-party count of requests to its
clean social campaign URLs even when browser analytics is blocked, without
turning the static marketing site into a general analytics application.

The accepted public URL system remains:

```text
/x/<code>   X campaign creative
/yt/<code>  YouTube campaign creative
/c/<code>   source-agnostic campaign creative

/x          X channel aggregate
/yt         YouTube channel aggregate
/c          source-agnostic channel aggregate
```

The homepage `/` remains canonical. Campaign routes continue to render the
same approved homepage experience and social preview.

## Affected people

- The campaign owner needs request-level evidence by channel and registered
  creative so distribution choices can be compared without visible UTM
  parameters.
- Website visitors need the same fast, reliable, private page whether or not
  analytics succeeds.
- Website maintainers need one bounded campaign registry rather than a second
  analytics vocabulary that can drift from public links.

## Authorized needs

| ID | Need or outcome | Priority | Authority |
| --- | --- | --- | --- |
| U1 | Count successful canonical GET requests to each known campaign path on the server side. | Must | Owner decision in the 2026-08-28 campaign analytics discussion. |
| U2 | Derive channel, campaign, creative, variant, and placement only from checked-in website-owned definitions. | Must | Owner-approved exact-registry topology. |
| U3 | Preserve asset-first delivery for `/`, framework assets, media, and every ordinary website route. | Must | Owner requirement that the main website remain fast and static. |
| U4 | Keep analytics failure, unavailability, or write suppression from changing page delivery. | Must | Existing social-attribution failure contract plus current owner decision. |
| U5 | Collect no IP address, User-Agent, referrer, query string, cookies, visitor/session identifiers, fingerprint, or client-supplied analytics dimensions. | Must | Owner privacy boundary. |
| U6 | Report the measurement as campaign-path requests, not people, unique clicks, or conversions. | Must | Existing attribution evidence and owner-approved abuse model. |
| U7 | Make aggregate channel routes measurable without pretending they identify a campaign creative. | Should | Existing public URL identity contract. |
| U8 | Keep the dataset and reporting surface small enough to operate directly through Cloudflare without a public events endpoint or a second Worker. | Must | Owner decision to use one website-specific Worker and avoid an abstraction. |
| U9 | Retain the existing Web Analytics and Security Analytics views as complementary evidence rather than replacing or reimplementing them. | Should | Existing released attribution contract. |

## Limits and non-goals

- No public `/events` endpoint, browser event beacon, generic event platform,
  service binding, private second Worker, queue, database, Durable Object, or
  visitor profile.
- No custom product-funnel events, install completion, app telemetry, unique
  visitor estimation, bot classification, or conversion claims.
- No changes to homepage copy, layout, media, interaction, install behavior,
  canonical metadata, social assets, or campaign-code identity.
- No attempt to make public request counts fraud-proof. A requester may reload
  or automate a real public URL. Bounded input prevents schema poisoning; it
  does not turn requests into verified humans.
- Analytics Engine's current three-month retention is accepted for the first
  version. Long-term export or historical warehousing is outside this scope.
