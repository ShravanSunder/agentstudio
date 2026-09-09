# Website campaign-request analytics program design

Date: 2026-08-28

Requirements:
[user-requirements.md](user-requirements.md)

Specification:
[2026-08-28-website-campaign-request-analytics.md](2026-08-28-website-campaign-request-analytics.md)

## The smallest structural change

The existing Astro build remains the page generator and the existing campaign
registry remains the sole owner of creative identity. One website Worker is
inserted only in front of campaign paths. Its job is deliberately narrow:
fetch the already-built asset, decide whether this exact response is eligible
for measurement, write one bounded datapoint, and return the untouched asset
response.

```text
ordinary request
  -> Cloudflare asset router
  -> static asset

campaign request
  -> selective Worker-first router
  -> website Worker
       -> campaign route resolver
       -> ASSETS.fetch(request)
       -> measurement admission
       -> ANALYTICS.writeDataPoint(...)
  <- unchanged static asset response
```

There is no analytics HTTP API, second Worker, service binding, queue, or
database. The Worker is not a dynamic page owner.

## Components and ownership

```text
website build
├── Astro campaign page generation
│     owns: which aggregate and registered HTML files exist
│
├── campaign attribution registry
│     owns: code -> channel/campaign/creative/variant/placement truth
│
├── Cloudflare deployment definition
│     owns: Worker entrypoint, ASSETS binding, Analytics Engine binding,
│           and the six selective Worker-first route patterns
│
└── campaign request Worker
      ├── route resolver
      │     owns: aggregate-vs-creative classification for an exact pathname
      ├── asset fetch
      │     owns: obtaining the authoritative static response
      └── measurement admission
            owns: GET + canonical path + known route + response 200 gate,
                  bounded datapoint construction, and fail-open write boundary

private operator reporting
├── repository-owned query catalog
│     owns: stable field aliases, sampling-aware totals, required report cuts,
│           aggregate interpretation, and measurement language
└── Cloudflare Analytics Engine SQL API
      owns: authenticated read access to the named dataset
```

The registry is imported by both build-time route generation and the Worker.
The Worker may derive a read-only lookup from it; it may not define campaign
identities independently. Aggregate routes derive only from the existing
`campaignChannels` authority.

Forbidden dependencies:

- request data may not create or extend registry values;
- analytics state may not affect route generation or page delivery;
- website components may not call analytics;
- the Worker may not fetch through public HTTP to reach Analytics Engine or
  static assets;
- reporting queries may not become a website runtime dependency.
- reporting credentials may not enter website source, Worker bindings, or
  browser-delivered code.

## Current and target call paths

```text
CURRENT — campaign route

request
  -> Cloudflare static asset router
  -> generated /<channel>/<code>/index.html
  <- direct asset response

TARGET — campaign route

request
  -> [changed] selective Worker-first match
  -> [added] campaign request Worker
       -> [added] resolve exact pathname from campaignChannels/registry
       -> [changed] env.ASSETS.fetch(request)
       <- asset response | asset error
       -> [added] admission gate reads method/path/status
       -> [added, conditional] env.ANALYTICS.writeDataPoint(point)
  <- [intentionally unchanged] asset response bytes/status/headers

TARGET — ordinary route

request
  -> [intentionally unchanged] Cloudflare static asset router
  -> static asset
  <- asset response
```

The asset fetch precedes measurement. This ordering makes HTTP 200 part of the
admission decision and prevents missing assets or future not-found behavior
from becoming successful campaign records.

## Route resolution and admission

The Worker uses a closed route union:

```text
known creative
  exact registry path
  dimensions = registered values

known aggregate
  exact /x, /yt, or /c
  route kind = channel-aggregate
  creative dimensions = reserved non-registry sentinel

unknown
  everything else, including unknown short codes
  measurement = none
```

Canonicality is pathname-based. A trailing slash is not admitted because the
configured static asset handling owns normalization. Query parameters never
participate in lookup, admission, or dimensions. The presence of a query
string does not create an identity; the Worker records only the exact known
pathname for an otherwise admitted request.

The full write predicate is:

```text
method == GET
AND route resolution == known aggregate or known creative
AND request pathname == route canonical pathname
AND asset response status == 200
```

## Analytics Engine record

The named dataset `agent_studio_campaign_requests` stores one fixed-shape
datapoint per admitted response.

```text
index1   exact canonical path

blob1    route kind: creative | channel-aggregate
blob2    channel
blob3    campaign key or reserved aggregate sentinel
blob4    creative key or reserved aggregate sentinel
blob5    variant key or reserved aggregate sentinel
blob6    placement key or reserved aggregate sentinel

double1  1
```

The reserved aggregate sentinel must be impossible under the registry's key
grammar so it cannot collide with a future real identity. Field order is a
schema contract because Analytics Engine datapoints use ordered arrays.

The exact path is the index because it is the bounded high-cardinality key the
owner queries most directly and because it keeps sampling localized by public
route. Reports use `sum(_sample_interval)` for request totals and group by the
fixed blob positions as needed.

Analytics Engine retains the dataset for three months. No export component or
long-term store exists in this design.

## Private owner reporting

The read path is operational rather than part of the public website:

```text
owner
  -> repository-owned campaign request query
  -> authenticated Cloudflare Analytics Engine SQL API
  -> agent_studio_campaign_requests
  <- sampling-aware rows labeled campaign-path requests
```

The query catalog is the stable interpretation of the positional dataset
schema. It exposes these aliases:

```text
path, route_kind, channel, campaign, creative, variant, placement,
campaign_path_requests
```

`campaign_path_requests` is always calculated with
`sum(_sample_interval)`. Creative reports group the registered dimensions.
Channel reports group `channel`. Aggregate records remain separate through
`route_kind = channel-aggregate`; the reserved sentinel never appears as a
real campaign or creative in an owner-facing report.

Every query requires an explicit time window within the three-month retention
boundary. The operator authenticates privately with an account-scoped
`Account Analytics: Read` token supplied outside the repository. The website
Worker has write-only dataset access through its binding and receives no read
credential. No dashboard, reporting API, or query execution is added to the
public website.

## Trust and privacy boundary

```text
untrusted public request
        │
        ▼
selective route pattern        broad prefilter only
        │
        ▼
exact checked-in resolver      rejects arbitrary identity values
        │
        ├── unknown ─────────► asset response only
        │
        ▼
GET + canonical + 200 gate
        │
        ▼
private ANALYTICS binding      fixed fields; no browser credential
```

The public can request a real route repeatedly. That can increase request
counts, just as preview bots, scanners, reloads, and prefetchers can. The
system contains the impact by admitting only fixed registered dimensions and
one datapoint per delivered request. It does not claim fraud resistance or
human identity.

No rate-limit component is introduced in the first version. A global limiter
could let one attacker suppress legitimate measurement, while an IP-keyed
limiter would add a privacy-sensitive input and still would not prove human
traffic. Revisit rate limiting only if observed write volume or dataset noise
causes a real capacity or reporting problem. Any future limiter must suppress
analytics writes without blocking the page.

## Failure containment

| Failure | Owner and detection | Containment and recovery |
| --- | --- | --- |
| Unknown or malformed campaign path | Route resolver returns unknown. | Return ordinary asset response; no write. |
| Asset returns non-200 | Measurement admission observes status. | Return response unchanged; no write. |
| Asset fetch throws | Static delivery boundary. | Propagate the existing delivery failure; analytics does not run. |
| Analytics write is unavailable or throws at the call boundary | Worker write boundary. | Contain the analytics error and return the already-resolved asset response; no retry. |
| Worker code/config deployment defect | Cloudflare runtime/deployment boundary. | Roll back the Worker version; prior asset-first deployment is the recovery source. |
| Analytics Engine unavailable or quota-limited | Binding/write boundary and owner report. | Missing datapoints are accepted partial success; page remains available. |
| Duplicate/replayed request | Public request boundary. | Each admitted delivery may record independently; reporting remains request-based. |

The write is deliberately not retried. Retrying creates duplicate uncertainty
and would add queue/state machinery for a best-effort measure.

## Concurrency and consistency

Requests are independent and share no mutable Worker state. Registry data is
immutable module data. Each admitted request performs at most one write.
Analytics Engine is append-only for this use; there is no read-modify-write,
ordering guarantee, deduplication key, or cross-request transaction.

The page response and analytics record are intentionally not atomic. Page
success with a missing datapoint is valid partial success. An analytics record
without a successful asset response is prevented by fetch-before-write and the
HTTP 200 gate.

## Cutover and rollback

Cutover adds the Worker entrypoint, selective route patterns, ASSETS binding,
and Analytics Engine binding in one Cloudflare deployment. There is no dual
writer and no data migration.

Before cutover, static assets and the registry remain authoritative. After
cutover, they remain authoritative; the Worker only observes selected
responses. Rollback restores the preceding Cloudflare version, removing the
Worker-first observation path while leaving all public pages and registry
identity intact. Analytics already written before rollback remains in the
dataset until platform retention expires.

## How each requirement is realized and proved

| Requirement | Structural owner | Proof seam |
| --- | --- | --- |
| R1 selective execution | Cloudflare deployment definition | Generated configuration plus runtime invocation evidence for campaign and ordinary paths |
| R2 exact admission | Route resolver and measurement admission | In-process route/status/method matrix and real unknown-route response |
| R3 bounded dimensions | Registry and datapoint constructor | Exact datapoint inspection for creative and aggregate routes |
| R4 authoritative delivery | ASSETS fetch ordering and fail-open write boundary | Byte/header/status comparison plus injected write failure |
| R5 request reporting | Fixed dataset schema and sampling-aware query | Owner query result using `sum(_sample_interval)` |
| R6 privacy/lifecycle | Closed datapoint constructor and Analytics Engine retention | Schema inspection and live record inspection |
| R7 compatibility | Existing Astro pages, registry, metadata, and asset handling | Existing route/metadata/sitemap suite plus live HTTP evidence |

## Revisit signals

Add more structure only when evidence requires it:

- persistent legitimate traffic exceeds the practical Analytics Engine write
  or query boundary;
- automated request noise makes the request metric unusable;
- the owner needs retention beyond three months;
- more than one website or service must emit the same governed events; or
- product-funnel events receive a separate privacy and telemetry contract.

Those signals could justify rate limiting, export, a queue, or a shared
analytics boundary. None is required to count bounded campaign-path requests
for this website today.

## Platform sources

- [Static asset binding and selective `run_worker_first`](https://developers.cloudflare.com/workers/static-assets/binding/)
- [Run a Worker script before static assets](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/)
- [Analytics Engine get started and `writeDataPoint`](https://developers.cloudflare.com/analytics/analytics-engine/get-started/)
- [Analytics Engine sampling](https://developers.cloudflare.com/analytics/analytics-engine/sampling/)
- [Analytics Engine limits and retention](https://developers.cloudflare.com/analytics/analytics-engine/limits/)
