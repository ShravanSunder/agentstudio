# Website campaign-request analytics specification

Date: 2026-08-28

Requirements:
[user-requirements.md](user-requirements.md)

## Observable outcome

Each successful request to a known Agent Studio campaign URL produces one
bounded server-side Analytics Engine datapoint while returning the same static
asset response the route would otherwise return. All non-campaign website
traffic remains on the existing asset-first path.

The new dataset complements, but does not replace, Cloudflare Web Analytics,
Security Analytics, or platform-native X and YouTube reporting.

## Normative requirements

### R1 — Selective execution

Only `/x`, `/x/*`, `/yt`, `/yt/*`, `/c`, and `/c/*` MUST be eligible to invoke
the website Worker before static assets. `/`, framework assets, public media,
and ordinary website routes MUST remain asset-first.

### R2 — Exact attribution admission

A request MUST produce a datapoint only when all of these conditions hold:

1. the HTTP method is `GET`;
2. the normalized pathname is either an exact aggregate channel path or an
   exact route resolved by the checked-in campaign attribution registry;
3. the request uses the canonical pathname form rather than a trailing-slash
   or other normalization variant; and
4. static asset resolution returns HTTP 200.

An unknown code, an unregistered channel, `HEAD`, a non-GET method, or a
non-200 asset response MUST NOT produce a datapoint. Query strings MUST be
ignored for route resolution and MUST NOT be recorded. A known canonical
pathname with a query string remains the same campaign-path request; the query
does not create or alter campaign identity or dimensions.

### R3 — Bounded dimensions

For a registered creative route, the recorded dimensions MUST be the exact
`channel`, `campaign`, `creative`, `variant`, and `placement` values resolved
from the checked-in registry.

For `/x`, `/yt`, or `/c`, the recorded channel MUST be exact and the record MUST
be explicitly classified as a channel aggregate. It MUST NOT inherit or infer
campaign, creative, variant, or placement values.

No request header, query value, cookie, body, referrer, browser value, or
caller-supplied event value may populate an analytics dimension.

### R4 — Page delivery is authoritative

Static asset delivery MUST complete independently of analytics. The Worker
MUST return the resolved asset response without rewriting its body, status,
headers, canonical metadata, or social metadata.

If route resolution does not admit measurement, the Worker MUST still return
the ordinary asset response. If the Analytics Engine binding or write fails,
the asset response MUST remain unchanged.

### R5 — Measurement language

Owner-facing queries and documentation MUST label the measure
`campaign-path requests`. They MUST NOT label it clicks, visitors, unique
visitors, people, or conversions.

Reports MUST support the following bounded cuts within Analytics Engine's
retention window:

- total campaign-path requests over time;
- requests by exact path;
- requests by channel;
- requests by campaign, creative, variant, and placement for registered
  creative routes; and
- channel-aggregate requests kept separate from creative requests.

Sampling-aware totals MUST use Analytics Engine's `_sample_interval` weight.

### R6 — Privacy and data lifecycle

The custom dataset MUST NOT record IP address, User-Agent, referrer, query
string, cookie, request body, session identifier, visitor identifier, or a
fingerprint-derived value. Analytics Engine's platform retention is the data
lifecycle for this version; no copy or export is required.

### R7 — Compatibility

The existing public path family, four-character code derivation, registry
collision behavior, direct static 200 pages, unknown-code 404 behavior,
trailing-slash normalization, canonical `/` metadata, sitemap exclusion, and
approved social preview MUST remain observably unchanged.

## Failure and partial-success contract

| Condition | Page result | Analytics result |
| --- | --- | --- |
| Known canonical GET, asset 200, write succeeds | Existing asset response | One bounded datapoint |
| Known canonical GET, asset 200, write fails | Existing asset response | Missing datapoint; no retry obligation |
| Unknown nested code | Existing 404 | No datapoint |
| Normalization request such as trailing slash | Existing normalization response | No datapoint |
| Known canonical GET with a query string | Existing asset response | One pathname-based datapoint; query ignored |
| HEAD or non-GET | Existing asset behavior | No datapoint |
| Ordinary non-campaign request | Existing asset-first response | Worker not invoked |
| Repeated real campaign requests | Existing asset response for each | May produce repeated request records |

The custom dataset is best-effort request evidence. Missing records and
automated traffic are accepted limitations, not reasons to degrade delivery or
collect visitor identity.

## Proof obligations

| ID | Observable proof |
| --- | --- |
| V1 | Routing evidence shows only the six campaign route patterns invoke Worker-first behavior; `/` and ordinary assets remain asset-first. |
| V2 | Automated behavior evidence admits known canonical GET/200 routes, including when a query string is present; proves the query is ignored for route resolution, identity, dimensions, and storage; and rejects unknown, noncanonical, non-GET, and non-200 cases. |
| V3 | Automated data inspection shows exact registered dimensions, explicit aggregate classification, stable field ordering, one index, and no request-derived personal fields. |
| V4 | Failure-injection evidence shows analytics write failure returns the unchanged asset response. |
| V5 | Production build and Cloudflare packaging evidence contains the Worker entrypoint, selective routing, static assets binding, and Analytics Engine binding together. |
| V6 | Live runtime evidence shows `/`, an ordinary asset, `/x`, `/x/73uz`, and `/x/zzzz` retain their released HTTP behavior. |
| V7 | A controlled live `/x/73uz` GET becomes visible in an owner-accessible sampling-aware Analytics Engine query with the exact registered dimensions. |
| V8 | Cloudflare Web Analytics and Security Analytics remain available as separate complementary views. |
