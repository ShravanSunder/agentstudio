# WebView Auth & Extensions — Options, Prior Art, and Recommendation

**Date:** 2026-06-01
**Status:** Research / decision doc (precursor to an implementation plan)
**Scope:** How AgentStudio's embedded web panes (SwiftUI `WebView`/`WebPage`, same WebKit as `WKWebView`) can support (a) **persistent login / auth** and (b) **extensions like 1Password / ad blockers** — and what matters for the **agent-testing-web-apps** use case ("programs to test programs").

> Engine note: On macOS 26 the SwiftUI `WebView` + `WebPage` API is the same WebKit content process, cookie store, and network stack as AppKit `WKWebView`. Every API below (`WKWebExtensionController`, `WKWebsiteDataStore`, `WKHTTPCookieStore`, custom scheme handlers, `ASWebAuthenticationSession`) applies identically regardless of which surface hosts the page. AgentStudio is already on the SwiftUI surface (`Features/Bridge/Views/BridgePaneContentView.swift`).

---

## 1. Problem statement

Embedded WebKit web panes do **not** share Safari's or Chrome's cookie jar (hard OS sandbox boundary), and WebKit does not natively load Chrome extensions. Concretely, two pains:

1. **Auth:** users (and agents) get logged out / have to re-login in the embedded pane; no SSO with the system browser.
2. **Extensions:** no 1Password autofill, no ad/tracker blocking, no dev extensions (React DevTools, etc.).

Two distinct audiences:

- **Human user** opening a web pane and wanting it to "just work like a browser" (1Password, stays logged in).
- **AI coding agent** that needs to drive a web app for testing and must get past a login wall without a human babysitting every run.

These have different best answers. The doc covers both.

---

## 2. TL;DR — options summary

| # | Option | Solves auth | Solves extensions | 1Password works? | Binary cost | Effort | Verdict for AgentStudio |
|---|--------|:-----------:|:-----------------:|:----------------:|:-----------:|:------:|-------------------------|
| 1 | **`WKWebExtensionController`** (Apple, macOS 15.4+) | partial¹ | ✅ (MV2/MV3, ~Safari parity) | ⚠️ allowlist-gated | ~0 | M | **Adopt** — for ad/dev extensions; 1Password unlikely without coordination |
| 2 | **1Password CLI (`op`) fill shim** | ✅ (credentials) | n/a | ✅ (via CLI, not extension) | ~0 | S | **Adopt** — pragmatic 1Password without the allowlist fight |
| 3 | **Per-profile `WKWebsiteDataStore(forIdentifier:)`** | ✅ (stay logged in) | n/a | n/a | ~0 | S | **Adopt** — fits per-pane controller model exactly |
| 4 | **Import system-browser sessions** (cmux/agent-browser pattern) | ✅ (start authenticated) | n/a | n/a | ~0 | M–L | **Strong consider** — this is how the closest peer solves it |
| 5 | **`storageState` save/load** (cookies+localStorage JSON) | ✅ (reuse session) | n/a | n/a | ~0 | S | **Adopt for agents** — the canonical test-login reuse pattern |
| 6 | **CDP attach to user's real Chrome** | ✅ (live session) | ✅ (Chrome's own) | ✅ (it's their Chrome) | ~0² | M | **Consider for agent testing only** — security-sensitive |
| 7 | **Device Authorization Grant (RFC 8628)** | ✅ (headless login) | n/a | n/a | ~0 | S | **Adopt where provider supports** — best for agents |
| 8 | **`ASWebAuthenticationSession`** | ✅ (OAuth/SSO) | n/a | n/a | ~0 | S | **Adopt for app-initiated OAuth** (not in-pane logins) |
| 9 | **Embed CEF / Chromium** | ✅ | ✅ (full Chrome store) | ✅ (allowlisted) | **+100–200 MB** | XL | **Reject** — abandons WebKit, bridge, and "tiny fast app" thesis |

¹ Auth via extensions (password managers) only; doesn't change the cookie-jar boundary itself.
² No binary cost, but requires the user to run their own Chrome with a debug port.

**Headline:** stack options **1–5** (all zero-binary-cost, all stay on WebKit). They cover humans (1,2,3) and agents (4,5,6,7) without ever leaving your architecture. **Do not embed Chromium** — the cost is not just the obvious ~150 MB; it throws away your entire bridge/runtime integration and per-pane WebKit model.

---

## 3. How cmux does it (closest prior art — read this first)

cmux (`manaflow-ai/cmux`, AGPL-3.0) is the nearest peer: a **native macOS terminal for running parallel coding agents**, and its in-app browser pane is **WKWebView — not containerized Chromium, not VNC, not headless CDP**. Its scriptable browser API is ported from **`vercel-labs/agent-browser`**. This is the single most relevant data point in this doc: a direct competitor solving the identical problem chose the same engine you already have, and did **not** reach for Chromium.

How cmux solves login:

1. **Import sessions from system browsers at startup.** Per its README, cmux can *"import cookies, history, and sessions from Chrome, Firefox, Arc, and 20+ browsers so browser panes start authenticated."* This is the primary "get logged in" path.
2. **Playwright-style storage-state save/load** (scriptable):
   - `cmux browser surface:7 state save ./auth-state.json` — captures cookies, localStorage, sessionStorage, open-tab metadata.
   - `cmux browser surface:8 state load ./auth-state.json` — restores it into another surface.
   - Manual interactive login once (`snapshot --interactive`, fill, wait for nav), then save state.
3. **Per-surface isolation:** each surface has independent cookies / localStorage / sessionStorage / history. One task per surface.

What cmux does **not** have (all are open feature requests, not shipped):

- **No password-manager integration** (no 1Password) — not documented anywhere.
- **No extensions** — WKWebView doesn't load Chrome extensions; not addressed.
- **No Chromium engine / no CDP endpoint** — requested in issues #2803 (Chromium engine + profile persistence), #2842 / #3442 (expose CDP for Playwright attach), not implemented.

The underlying `agent-browser` mechanics (the parts cmux's pane is built on, and the parts directly portable to AgentStudio):

- **`--profile <name>`**: copies a Chrome profile to a temp dir (read-only snapshot, never mutates the user's real profile) so the browser launches with existing cookies/sessions.
- **`--session-name`**: auto-saves and restores cookies + localStorage across restarts.
- **`--state ./auth.json`**: load auth at launch; combine with `--session-name` so imported auth auto-persists.
- **`cookies set --curl <file>`**: bulk cookie import, auto-detecting JSON / cURL / `Cookie:`-header formats (e.g. paste from "Copy as cURL" in DevTools).

> Note: `agent-browser` itself drives Chrome/Chromium over CDP. cmux re-exposed that *command surface* on top of WKWebView; commands relying on Chrome-only CDP features (network interception, screencast, viewport emulation, raw input injection) return `not_supported` on the WKWebView backend. The transferable idea is the **auth model** (import + storageState), not the CDP transport.

**Takeaway for AgentStudio:** the "import system-browser sessions" + "storageState save/load" combo is a proven, shipping answer to your exact auth problem on your exact engine. Options 4 and 5 below are the generalization of this.

---

## 4. Prior art across the field

| Product | Engine | Extensions | Password mgr / auth | Notes |
|---------|--------|-----------|---------------------|-------|
| **cmux** | WebKit (WKWebView) | ❌ | session import + storageState; no 1Password | Closest peer; see §3 |
| **Orion** (Kagi) | WebKit | ✅ ~70% of WebExtensions API, **natively re-implemented** on WebKit | 1Password works **after** Kagi+1Password whitelisted Orion | Proof a WebKit browser *can* run 1Password — but only via business coordination |
| **Arc / Dia** (Browser Co.) | **Chromium** | ✅ full Chrome store | ✅ native; Arc on 1Password default allowlist | Not WebKit. Arc discontinued May 2025; company → Atlassian 2025 |
| **Tauri / WRY** | System webview (WKWebView on macOS) | ⚠️ `with_extension_path` is **Windows/Linux only — not macOS** | cookie *getters* added v0.47.0 (http/https), setters limited | No first-class extension model on macOS WebKit |
| **Electron / CEF** | Chromium | ⚠️ limited `chrome.*` subset, persistent sessions only | **1Password refuses** — Electron apps not on its native-messaging allowlist | Full Chromium, but 1Password explicitly won't connect |

**Two lessons:**
1. Everyone who got "full Chrome extensions + 1Password works out of the box" did it by **being Chromium** (Arc/Dia) — which is the option you're rejecting on size/architecture grounds.
2. The one WebKit browser that got 1Password working (Orion) did it through **`WKWebExtension`-style native re-implementation *plus* a direct allowlisting deal with 1Password**, not a public API you can just call.

---

## 5. The options in full

### Option 1 — `WKWebExtensionController` (Apple, macOS 15.4+)

**What:** Apple's public API (`WKWebExtension`, `WKWebExtensionContext`, `WKWebExtensionController`, `WKWebExtensionMatchPattern`) lets a third-party WebKit app load standard cross-browser WebExtensions (the same MV2/MV3 folders Chrome/Firefox consume). You attach a controller to the page configuration and implement a controller delegate for tabs/windows/permissions. **Native messaging is supported** — WebKit landed "native messaging with NSExtension"; the host app handles it via the controller delegate's `connectUsingMessagePort:forExtensionContext:`, and if unimplemented WebKit falls back to routing to an `NSExtension` (matching Safari).

**Pros:**
- Only sanctioned path to real extensions on WebKit; zero binary cost.
- Covers the high-value, low-friction wins: **uBlock Origin Lite, Dark Reader, Vimium, Stylus, Refined GitHub, React DevTools**.
- Fits your per-pane configuration model — controller goes on the per-pane `WKWebExtensionController`.

**Cons / unknowns:**
- **1Password is not a given.** Even though the API exposes native-messaging hooks, 1Password's desktop app verifies the **extension ID + native-messaging host against a hardcoded allowlist** before connecting. Your `WKWebExtensionController`-hosted instance won't be on that list. This is the exact gate Orion had to clear via direct coordination with 1Password. **Treat 1Password-via-extension as a business/partnership step, not a technical one.** (Verify: confidence medium that 1Password ships nothing consumable here.)
- Exact MV2/MV3 parity vs. Safari needs verification in Xcode against your target SDK.
- You must implement the controller delegate (tabs, windows, permission prompts) — non-trivial surface.

**Verdict:** Adopt for ad-blocking and dev extensions (big perceived-quality win). Do **not** assume it delivers 1Password.

---

### Option 2 — 1Password CLI (`op`) fill shim

**What:** Instead of fighting the extension allowlist, integrate the **1Password CLI**. Bind a key (e.g. ⌘\) in a web pane → resolve the credential for the current host via `op item get` / `op read "op://vault/item/field"` → inject into the page's form via `WebPage.callJavaScript` / `evaluateJavaScript`.

**Mechanics:**
- `op` supports **Touch ID / biometric unlock** through the desktop app integration (a biometric session lasts ~10 min, auto-refreshing, one account at a time).
- `op inject` / `op run` resolve `op://` references into env/templates (useful for the agent path too).
- **Service-account tokens** (`OP_SERVICE_ACCOUNT_TOKEN`) and the **Connect server** exist for unattended/CI use.
- Official SDKs: **Go, JS/Node, Python** (auth via service-account tokens). **No Swift SDK listed** (confidence medium — verify). For Swift, shell out to `op` or use Connect's REST.

**Pros:** ~half a day of work; you control the UX; works today regardless of allowlists; Touch ID feels native; doubles as the agent secret-resolution path.

**Cons:** not "automatic" autofill — it's an explicit fill action; requires the 1Password app + CLI installed and `op` integration enabled; one account at a time under biometric session.

**Verdict:** Adopt. This is the pragmatic 1Password answer.

---

### Option 3 — Per-profile `WKWebsiteDataStore(forIdentifier:)`

**What:** macOS 14+ API: `WKWebsiteDataStore(forIdentifier: UUID)` creates a **separate persistent store** (cookies, localStorage, IndexedDB, cache) under `~/Library/WebKit/WebsiteDataStore/<UUID>/`, distinct from the default. Assign one per pane/profile, persist the UUID, recreate with the same identifier on relaunch → "log in once, stay logged in" per profile.

**Pros:**
- Directly fixes the "keeps logging me out" complaint **if** the cause is non-persistent or shared/clobbered stores.
- Enables **work vs. personal vs. preview** sessions in different panes (how Arc/Orion do profiles) — maps perfectly onto your existing per-pane `BridgePaneController` / per-pane `WKUserContentController` design.

**Cons:** doesn't share with Safari/Chrome (still isolated); profile management UX to build; you own UUID lifecycle.

**First check:** confirm you're not using `.nonPersistent()` anywhere and not calling `removeData(ofTypes:)` on launch — default stores already persist across launches, so a logout bug may simply be a misconfigured store.

**Verdict:** Adopt. Low effort, high fit.

---

### Option 4 — Import system-browser sessions (the cmux/agent-browser pattern)

**What:** At pane creation (or on demand), import cookies/sessions from the user's real Chrome/Firefox/Arc/etc. into the pane's `WKHTTPCookieStore`, so the pane "starts authenticated." Two flavors:
- **Profile snapshot** (agent-browser `--profile`): copy the user's browser profile to a temp dir read-only, never mutating the original.
- **Cookie extraction**: read the source browser's cookie DB and inject relevant cookies into the WebKit store via `WKHTTPCookieStore.setCookie`.

**Pros:** best UX — login carries over with no manual step; this is exactly how the closest peer (cmux) ships it.

**Cons / hard parts:**
- **Chromium cookies are encrypted** (per-OS; on macOS the AES key lives in the login Keychain under "Chrome Safe Storage"). Extraction requires Keychain access and is brittle across Chrome updates.
- **Safari's cookie container is sandboxed off-limits** without special entitlements (won't pass App Store review).
- Importing live session cookies is a **secret-handling** responsibility — scope to the site the user is navigating to; don't vacuum everything.
- Cross-browser format churn (20+ browsers = ongoing maintenance, which is why cmux frames it as a feature, not a one-off).

**Verdict:** Strong consider, phase 2. Highest-UX auth answer, but the most maintenance. Start with Chrome-only cookie import for a target site, behind an explicit "Import login from Chrome" action.

---

### Option 5 — `storageState` save/load (cookies + localStorage JSON)

**What:** The Playwright pattern: dump cookies + localStorage (+ IndexedDB) to a JSON file; reload into a fresh context so it starts authenticated. A "setup" step logs in once; all subsequent runs reuse the state. cmux exposes this verbatim (`state save` / `state load`).

**Pros:** dead simple; the canonical way agents skip re-login across test runs; portable across panes/runs; no Keychain/crypto.

**Cons:** the file **is** a live session token — treat as a secret, never commit (Playwright docs and cmux both warn). State expires when the session does.

**Verdict:** Adopt, especially for the agent path. Implement `WKHTTPCookieStore` export/import + a localStorage dump via `callJavaScript`. This is the single most useful primitive for "programs testing programs."

---

### Option 6 — CDP attach to the user's real, signed-in Chrome

**What:** User launches Chrome with `--remote-debugging-port=9222`; the agent connects over CDP (`connectOverCDP`) and drives the **already-authenticated** profile (live cookies, tabs, sessions). For agent web-testing only — not a UI pane.

**Pros:** zero login work — it's the user's real, logged-in Chrome, with their extensions (including a working 1Password); full CDP power (network interception, etc.).

**Cons:** **security-sensitive** — the debug port grants total control (read all cookies/tokens, act as the user); any local process can attach. Must stay bound to localhost; never expose. Requires the user to run Chrome a specific way.

**Verdict:** Consider as an **opt-in agent-testing mode**, clearly fenced and documented. Not a default; not a human-UI feature.

---

### Option 7 — Device Authorization Grant (RFC 8628)

**What:** The pane/agent POSTs to a device-authorization endpoint, gets a `device_code` + short `user_code` + `verification_uri`, shows the user the code, and **polls the token endpoint** while the user authorizes on any device's browser. Supported by **GitHub, Google, Microsoft Entra ID, Auth0, Okta, Keycloak**.

**Pros:** purpose-built for headless/embedded/agent contexts — no in-app redirect handling, no embedded login form, no passkey limitations. The cleanest "agent needs to authenticate to a first-party service" path.

**Cons:** only works where the provider implements it; out-of-band step (user approves elsewhere); yields a token, not a browser session (great for API-backed flows, less so for "drive this arbitrary web UI").

**Verdict:** Adopt wherever the target supports it — especially for AgentStudio's own integrations (GitHub PR ops, etc.).

---

### Option 8 — `ASWebAuthenticationSession`

**What:** Apple's sanctioned OAuth/OIDC flow. Opens the auth URL in a Safari-backed view that runs **in the top-level site context, isolated from your app**, and returns a callback URL. By default it **shares Safari's cookies** → frequent one-tap SSO. Set `prefersEphemeralWebBrowserSession = true` for a clean session. Because it's a real browser context, **WebAuthn/passkeys work**.

**Pros:** the *only* legitimate Safari-cookie-sharing surface; ideal for **AgentStudio-initiated OAuth** (Linear, GitHub, etc.); passkeys work inside it.

**Cons:** you get only the final callback — **no DOM control inside the flow** (so it can't be scripted/inspected); it's for *your app's* auth, not for logging into an arbitrary in-pane site.

**Verdict:** Adopt for app-initiated OAuth. Not a substitute for in-pane login.

---

### Option 9 — Embed CEF / Chromium

**What:** Bundle Chromium (CEF). Gets the full Chrome extension ecosystem and a working 1Password (Chrome IDs are on 1Password's default allowlist).

**Pros:** solves both problems comprehensively in one move.

**Cons (the size is the *least* of them):**
- **+100–200 MB** binary; memory back in Electron territory — kills the "tiny fast Swift app" thesis.
- **Abandons your entire architecture:** you lose `WKWebExtensionController`, the per-pane WebKit model, and the native integration of your Bridge runtime/transport. Your `agentstudio://` scheme, content-world isolation, and push pipeline are all WebKit-shaped.
- CEF on macOS arm64 is a real, ongoing maintenance burden (build, sign, notarize, update cadence).
- Even Electron — full Chromium — **can't get 1Password** without being on the allowlist; CEF inherits the same native-messaging-host allowlist mechanics.

**Verdict:** Reject. The closest peer (cmux) faced this exact choice and stayed on WKWebView. Chromium only makes sense if you're building a *browser*, not a coding tool with web panes.

---

## 6. Sign-in mechanism reference (the auth toolbox)

Quick map of *which mechanism for which situation*:

| Situation | Use | Why |
|-----------|-----|-----|
| AgentStudio authenticating to its own integrations (GitHub, Linear) | **Device code flow** (Opt 7) or **ASWebAuthenticationSession** (Opt 8) | Headless-friendly / sanctioned OAuth |
| Human logs into a site in a pane and wants it to stick | **Per-profile data store** (Opt 3) + **session import** (Opt 4) | Persistent, per-profile, carries over |
| Human wants 1Password autofill | **`op` CLI shim** (Opt 2); extensions (Opt 1) only if 1Password allowlists you | Allowlist is the blocker, not the API |
| Agent must get past a login wall to test a web app | **storageState reuse** (Opt 5) → **CDP attach** (Opt 6) → **seeded test session** (§7) | Reuse > attach > bypass, by safety |
| Logging into your *own* service (your RP domain) | **Passkeys/WebAuthn** in the webview | Works for your linked domain only (below) |

**Passkeys / WebAuthn caveat (important for embedded contexts):** A WKWebView/`WebPage` *can* invoke the platform authenticator and system passkey UI on modern macOS — **but only for passkeys whose RP ID matches the app's linked web domain** (via Associated Domains). It runs in the calling app's context, so an embedded pane **cannot** use passkeys for arbitrary third-party IdPs. For third-party passkey login you must route through `ASWebAuthenticationSession` (top-level site context, any RP). So: passkeys are great for "log into *our* service from our webview," useless for "log into github.com inside a generic pane." (Confidence high; tracks current Apple/passkeys.dev guidance, version-sensitive.)

---

## 7. "Programs to test programs" — agent login patterns

When an AI agent needs to drive a web app under test, ranked by safety/maintainability:

1. **storageState reuse (Opt 5)** — best default. A human (or a one-time setup job) logs in once and saves state; every agent run loads it. No secrets in code, no re-login, trivial to rotate. This is what cmux and Playwright both standardize on.
2. **Device code flow (Opt 7)** — when the target is a first-party service with an API; agent prints the code, a human approves once, token is cached/refreshed.
3. **CDP attach to real Chrome (Opt 6)** — when you genuinely need the user's live, extension-equipped session; gate hard behind opt-in + localhost-only.
4. **Seeded test sessions / auth-bypass tokens (staging only)** — common team patterns so tests skip real login:
   - a **test-only login endpoint** gated by `ENV=test` that mints a signed session cookie/JWT directly,
   - injecting a forged-but-valid session into storage,
   - an `x-test-auth` / bypass header honored only in non-prod.
   Keep these **strictly env-fenced** so they can never reach production. Best when AgentStudio's user *owns* the app under test.
5. **Magic links / email codes** — short-lived (5–10 min) signed tokens; in tests, read the link server-side rather than checking a mailbox.
6. **Password-manager CLI fill (Opt 2)** — `op` (Touch ID biometric unlock) or Bitwarden `bw` (`BW_SESSION` token, or `bitwarden-cli-bio` for Touch ID). Resolve the credential, then `callJavaScript` to fill the form. Works against real login when you can't seed a session.

**Recommended agent default for AgentStudio:** a per-pane **storageState** primitive (export/import) + an **"authenticate this pane"** action that can drive `op` fill or a device-code prompt, plus an opt-in **CDP-attach mode** for advanced testing.

---

## 8. Recommendation for AgentStudio

Phased, all on WebKit, all zero-binary-cost. Each phase is independently shippable.

**Phase 0 — verify the logout bug (1 hour).**
Confirm web panes use a **persistent** `WKWebsiteDataStore` and nothing calls `removeData` on launch. A large share of "keeps logging me out" is just a misconfigured store, fixable before building anything.

**Phase 1 — persistence + 1Password CLI (½–1 day).**
- Per-profile `WKWebsiteDataStore(forIdentifier:)` (Opt 3), one per pane/profile, UUID persisted in the pane's metadata.
- `op` CLI fill shim (Opt 2) bound to a key, host-scoped credential lookup, Touch ID unlock.

**Phase 2 — agent auth primitives (1–2 days).**
- `storageState` save/load on the pane's cookie store + localStorage (Opt 5).
- Device-code helper (Opt 7) for first-party integrations.
- `ASWebAuthenticationSession` for AgentStudio-initiated OAuth (Opt 8).

**Phase 3 — extensions (2–4 days, after Phase 1–2 prove out).**
- Wire `WKWebExtensionController` (Opt 1) into the per-pane configuration; ship with **uBlock Origin Lite + Dark Reader** as the headline. Implement the controller delegate (tabs/windows/permissions).
- Explicitly **scope 1Password-via-extension out** of this phase — pursue only if you decide to approach 1Password for allowlisting (Orion precedent).

**Phase 4 — optional, advanced (later, if demand).**
- System-browser session import (Opt 4), Chrome-first, behind an explicit action.
- Opt-in CDP-attach agent-testing mode (Opt 6), localhost-only, clearly fenced.

**Reject:** embedding CEF/Chromium (Opt 9). It's the only option that throws away your bridge architecture, and your closest peer proved it's unnecessary.

---

## 9. Open questions / verify before building

- **1Password Swift SDK** — none listed publicly (confidence medium). Confirm; if absent, shell out to `op` or use Connect REST.
- **`WKWebExtension` MV2/MV3 parity** vs. Safari on your target SDK — verify in Xcode.
- **Does 1Password expose anything consumable** to a third-party `WKWebExtensionController` host, or is it strictly allowlist + Safari App Extension? (Likely the latter — treat as a coordination step.)
- **Chrome cookie decryption on macOS** (Keychain "Chrome Safe Storage" key) — confirm entitlement/UX implications before committing to Opt 4.
- **App Store vs. direct distribution** — Safari-container reads and some entitlements won't pass review; decide distribution model first.

---

## Sources

Engine / Apple APIs:
- [WKWebExtensionController — Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)
- [WebKit native-messaging commit (mail-archive)](https://www.mail-archive.com/webkit-changes@lists.webkit.org/msg219249.html) · [w3c/webextensions #256](https://github.com/w3c/webextensions/issues/256)
- [WKWebsiteDataStore(forIdentifier:) — Apple](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)) · [WebKit blog: building profiles](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [ASWebAuthenticationSession — Apple](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) · [Okta SSO history](https://developer.okta.com/blog/2022/01/13/mobile-sso)
- [Passkeys on macOS — passkeys.dev](https://passkeys.dev/docs/reference/macos/)

cmux / agent-browser (closest prior art):
- [manaflow-ai/cmux README](https://github.com/manaflow-ai/cmux) · [cmux-browser SKILL.md](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/SKILL.md)
- cmux issues [#2803](https://github.com/manaflow-ai/cmux/issues/2803), [#2842](https://github.com/manaflow-ai/cmux/issues/2842), [#3442](https://github.com/manaflow-ai/cmux/issues/3442)
- [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) · [sessions docs](https://github.com/vercel-labs/agent-browser/blob/HEAD/docs/src/app/sessions/page.mdx)

Other prior art:
- [Orion extensions — Kagi](https://help.kagi.com/orion/browser-extensions/macos-extensions.html) · [Orion 1Password](https://help.kagi.com/orion/browser-extensions/1password.html)
- [Arc (Wikipedia)](https://en.wikipedia.org/wiki/Arc_(web_browser)) · [tauri-apps/wry](https://github.com/tauri-apps/wry) · [WRY cookies discussion](https://github.com/orgs/tauri-apps/discussions/11655)
- [Electron extensions](https://www.electronjs.org/docs/latest/api/extensions) · [1Password + Electron (community)](https://www.1password.community/discussions/1password/desktop-application-integration/30653/replies/30656)

1Password / Bitwarden / auth patterns:
- [1Password browser security](https://support.1password.com/1password-browser-security/) · [connect additional browsers](https://support.1password.com/additional-browsers/)
- [1Password CLI biometric unlock](https://developer.1password.com/docs/cli/use-biometric-unlock/) · [1Password SDKs](https://developer.1password.com/docs/sdks/)
- [bitwarden-cli-bio](https://github.com/jeanregisser/bitwarden-cli-bio)
- [OAuth Device Flow RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628) · [Microsoft device code](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code)
- [Playwright auth / storageState](https://playwright.dev/docs/auth) · [connect to existing browser (CDP)](https://www.browserstack.com/guide/playwright-connect-to-existing-browser)
- [Auth.js testing](https://authjs.dev/guides/testing)
