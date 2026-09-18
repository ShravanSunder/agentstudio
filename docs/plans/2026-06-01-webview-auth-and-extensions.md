# WebView Auth & Extensions — Options, Prior Art, and Recommendation

**Date:** 2026-06-01
**Status:** Research / decision doc (precursor to an implementation plan). Revised 2026-06-01 with primary-source validation pass — see [revision notes](#revision-notes).
**Scope:** How AgentStudio's embedded web panes can support (a) **persistent login / auth** and (b) **extensions like 1Password / ad blockers** — and what matters for the **agent-testing-web-apps** use case ("programs to test programs").

> **Engine note.** AgentStudio's web panes use Apple's WebKit-for-SwiftUI API: `WebKit.WebView` (SwiftUI `View` struct) and `WebKit.WebPage` (`@Observable` class), introduced at WWDC25 for **iOS 26 / iPadOS 26 / macOS 26 / visionOS 3** ([Apple — WebKit for SwiftUI](https://developer.apple.com/documentation/webkit/webkit-for-swiftui), [WebKit blog — News from WWDC25](https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/)). This API is **backed by the same WebKit engine / content process as `WKWebView`** — same cookie store (`WKHTTPCookieStore`), same data store (`WKWebsiteDataStore`), same custom scheme handlers, same script-message handlers. Every API discussed below applies identically. AgentStudio is already on this surface (`Features/Bridge/Views/BridgePaneContentView.swift`).

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
| 1 | **`WKWebExtensionController`** (Apple, macOS 15.4+) | partial¹ | ✅ (MV2/MV3, Safari-parity loader) | ⚠️ allowlist-gated | ~0 | M | **Adopt** — for ad/dev extensions; 1Password unlikely without coordination |
| 2 | **1Password CLI (`op`) fill shim** | ✅ (credentials) | n/a | ✅ (via CLI, not extension) | ~0 | S | **Adopt** — pragmatic 1Password without the allowlist fight |
| 3 | **Per-profile `WKWebsiteDataStore(forIdentifier:)`** | ✅ (stay logged in) | n/a | n/a | ~0 | S | **Adopt** — fits per-pane controller model exactly |
| 4 | **Import system-browser sessions** (cmux/agent-browser pattern) | ✅ (start authenticated) | n/a | n/a | ~0 | M–L | **Strong consider** — this is how the closest peer solves it |
| 5 | **`storageState` save/load** (cookies + localStorage JSON) | ✅ (reuse session) | n/a | n/a | ~0 | S | **Adopt for agents** — the canonical test-login reuse pattern |
| 6 | **CDP attach to user's Chrome** | ⚠️ degraded² | ✅ (Chrome's own) | depends² | ~0 | M | **Reconsider** — Chrome 136+ blocks attach to default profile (see Opt 6) |
| 7 | **Device Authorization Grant (RFC 8628)** | ✅ (headless login) | n/a | n/a | ~0 | S | **Adopt where provider supports** — but watch Entra policy (see Opt 7) |
| 8 | **`ASWebAuthenticationSession`** | ✅ (OAuth/SSO) | n/a | n/a | ~0 | S | **Adopt for app-initiated OAuth** (not in-pane logins) |
| 9 | **Embed CEF / Chromium** | ✅ | ✅ (full Chrome store) | ✅ (allowlisted) | **+100–200 MB** | XL | **Reject** — abandons WebKit, bridge, and "tiny fast app" thesis |

¹ Auth via password-manager extensions only; doesn't change the cookie-jar boundary itself.
² Chrome 136 (May 2025) hardened `--remote-debugging-port` against App-Bound-Encryption cookie theft: attaching CDP now requires `--user-data-dir=<non-default>`, so you can no longer drive the user's signed-in default profile ([Chrome Developers — Changes to remote debugging](https://developer.chrome.com/blog/remote-debugging-port)). See Opt 6 below.

**Headline:** stack options **1–5, 7, 8** (all zero-binary-cost, all stay on WebKit). They cover humans (1, 2, 3) and agents (4, 5, 7) without ever leaving your architecture. **Do not embed Chromium** — the cost is not just the obvious ~150 MB; it throws away your entire bridge/runtime integration and per-pane WebKit model. **Option 6 is significantly degraded by Chrome 136+** and is no longer a "use the user's logged-in Chrome" path; reconsider scope.

---

## 3. How cmux does it (closest prior art — read this first)

cmux ([`manaflow-ai/cmux`](https://github.com/manaflow-ai/cmux), **GPL-3.0-or-later** — dual-licensed with a commercial option) is the nearest peer. Its README's actual tagline: *"A Ghostty-based macOS terminal with vertical tabs and notifications for AI coding agents"* — **notable: cmux is Ghostty-based, like AgentStudio**, so the architectural starting point is essentially identical. Its in-app browser pane is **WKWebView** — not containerized Chromium, not VNC, not headless CDP. Per [`skills/cmux-browser/SKILL.md`](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/SKILL.md): *"These commands currently return `not_supported` because they rely on Chrome/CDP-only APIs not exposed by WKWebView."* Its scriptable browser API is *"ported from agent-browser"* (i.e. [`vercel-labs/agent-browser`](https://github.com/vercel-labs/agent-browser)).

**This is the single most relevant data point in this doc:** a direct competitor solving the identical problem chose the same engine you already have and did not reach for Chromium.

### How cmux solves login

1. **Import sessions from system browsers at startup.** Per the cmux README (verbatim): *"Import cookies, history, and sessions from Chrome, Firefox, Arc, and 20+ browsers so browser panes start authenticated."* This is the primary "get logged in" path.
2. **Playwright-style storage-state save/load** (scriptable, from [`references/authentication.md`](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/references/authentication.md) and [`references/session-management.md`](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/references/session-management.md)):
   - `cmux browser surface:7 state save ./auth-state.json` — *"State includes cookies, localStorage, sessionStorage, and open tab metadata for that surface."*
   - `cmux browser surface:8 state load ./auth-state.json` — restores it into another surface.
   - Manual interactive login: `cmux browser surface:7 snapshot --interactive`, fill credentials, wait for navigation.
3. **Per-surface isolation** (verbatim): *"Each surface has independent: cookies, localStorage/sessionStorage, tab list and active tab, navigation history."*

### What cmux does **not** have

All open feature requests, not shipped:

- **No password-manager integration** (no 1Password) — not documented anywhere.
- **No extensions** — WKWebView doesn't load Chrome extensions; not addressed.
- **No Chromium engine** — [issue #2803](https://github.com/manaflow-ai/cmux/issues/2803) ("Feature Request: Support for Multiple Browser Engines (e.g., Chromium) and Enhanced Browser Control") proposes *"a configuration setting to switch between WebKit and Chromium for the internal view"* plus profile persistence. **Open.**
- **No CDP endpoint for Playwright attach** — [#2842](https://github.com/manaflow-ai/cmux/issues/2842) ("Expose CDP for cmux browser surfaces") and [#3442](https://github.com/manaflow-ai/cmux/issues/3442) ("Expose CDP endpoint for embedded browser (Playwright / Playwright MCP support)"). **Both open.**
- **Explicitly unsupported on the WKWebView backend** (verbatim from SKILL.md): *"viewport emulation, offline emulation, trace/screencast recording, network route interception/mocking, low-level raw input injection."*

### The agent-browser mechanics (directly portable to AgentStudio)

From the [`vercel-labs/agent-browser` README](https://github.com/vercel-labs/agent-browser/blob/main/README.md):

- **`--profile <name>`** (verbatim): *"This copies your Chrome profile to a temp directory (read-only snapshot, no changes to your original profile), so the browser launches with your existing cookies and sessions."*
- **`--session-name`** (verbatim): *"automatically save and restore cookies and localStorage across browser restarts."*
- **`--state ./auth.json`**: *"Load storage state from JSON file (or `AGENT_BROWSER_STATE` env)."* (Combinability with `--session-name` is not documented; treat them as independent.)
- **`cookies set --curl <file>`** (verbatim): *"Import cookies from a Copy-as-cURL dump, JSON array, or bare Cookie header (auto-detected)."*

> Engine note: `agent-browser` itself drives Chrome/Chromium (via Playwright/CDP — its README states *"Uses Chrome (from Chrome for Testing) by default"*). cmux re-exposed that *command surface* on top of WKWebView; CDP-only features fall away. The transferable idea is the **auth model** (profile snapshot + storage-state JSON + cURL cookie import), not the CDP transport.

### Distinguishing cmux from the manaflow cloud product

A separate sibling product ([`manaflow-ai/manaflow`](https://github.com/manaflow-ai/manaflow)) uses *"VS Code editor, Claude Code TUI, and VNC browser preview all in one view"* with *"isolated VS Code workspace either in the cloud or in a local Docker container."* That's the VNC/containerized one — **not** the same as cmux. cmux is the native macOS tool; manaflow is the cloud product.

**Takeaway for AgentStudio:** the "import system-browser sessions" + "storage-state save/load" combo is a proven, shipping answer to your exact auth problem on your exact engine. Options 4 and 5 below are the generalization of this.

---

## 4. Prior art across the field

| Product | Engine | Extensions | Password mgr / auth | Notes |
|---------|--------|-----------|---------------------|-------|
| **cmux** | WebKit (WKWebView) | ❌ | session import + storageState; no 1Password | Closest peer; see §3 |
| **Orion** (Kagi) | WebKit | ✅ ~70% of WebExtensions API, **natively re-implemented** on WebKit | 1Password works **after** Kagi + 1Password jointly whitelisted Orion | Proof a WebKit browser *can* run 1Password — but only via business coordination |
| **Arc / Dia** (Browser Co.) | **Chromium** | ✅ full Chrome store | ✅ native; Arc on 1Password default allowlist | Not WebKit. Arc in maintenance since May 27 2025; Atlassian acquisition closed Oct 21 2025 |
| **Tauri / WRY** | System webview (WKWebView on macOS) | ⚠️ `with_extensions_path` is **Windows + Linux only — not macOS** | cookie getters added v0.47.0; setters not advertised | No first-class extension model on macOS WebKit |
| **Electron** | Chromium | ⚠️ limited `chrome.*` subset (`management`, `storage.local`, `tabs`, `webRequest`); persistent (`persist:`) sessions only | **1Password refuses** — Electron apps not on its allowlist (per 1Password community staff statement) | Full Chromium, but 1Password explicitly won't connect |

**Orion specifics (sources for the table row):** Orion *natively re-implemented* WebExtensions on top of WebKit — per [help.kagi.com/orion/misc/technical.html](https://help.kagi.com/orion/misc/technical.html): *"Early in development, Orion decided to natively support the Web Extensions API, and ended up porting hundreds of APIs, one by one, that were never meant to work with WebKit."* Coverage is around 70% per Kagi's docs. The 1Password fix is documented at [help.kagi.com/orion/browser-extensions/1password.html](https://help.kagi.com/orion/browser-extensions/1password.html): *"1Password is now compatible with Orion thanks to the joint effort between 1Password and Orion teams"*, originally requiring a nightly 1Password desktop build (≥ 81009030) and Orion explicitly added via *"1Password → Settings → Browser → Add Browser, then select Orion."*

**Arc / Dia specifics:** Arc is Chromium-based, written in Swift. Arc entered maintenance mode May 27 2025 (Josh Miller open letter). Atlassian announced acquisition of The Browser Company for $610M on Sept 4 2025 ([TechCrunch](https://techcrunch.com/2025/09/04/atlassian-to-buy-arc-developer-the-browser-company-for-610m/)); the deal closed Oct 21 2025 ([Thurrott](https://www.thurrott.com/cloud/325637/atlassian-acquires-developer-of-the-arc-and-dia-web-browsers)). Dia inherits Spaces (reportedly reimagined), and imports Chrome passwords/history.

**Tauri/WRY specifics:** WRY's [v0.47.0 CHANGELOG](https://github.com/tauri-apps/wry/blob/dev/CHANGELOG.md): *"Add WebViewBuilder::with_extension_path API to Windows and Linux."* v0.48.0 renamed to **`with_extensions_path`** (plural) on `WebViewBuilderExtWindows` and `WebViewBuilderExtUnix`. No macOS extension trait exists. `WebView::cookies` / `cookies_for_url` getters added v0.47.0; setter support is not advertised in the changelog. Linux persistence requires a `data_directory` via `WebViewBuilderExtUnix` (rustdoc).

**Electron specifics:** Per [electronjs.org/docs/latest/api/extensions](https://www.electronjs.org/docs/latest/api/extensions): *"Electron supports a subset of the Chrome Extensions API"* — `chrome.management`, `chrome.storage.local` (not `sync`/`managed`), `chrome.tabs`, `chrome.webRequest`. *"Loading extensions is only supported in persistent sessions. Attempting to load an extension into an in-memory session will throw an error."* Native messaging is not built in (see Electron issues [#7681](https://github.com/electron/electron/issues/7681), [#8692](https://github.com/electron/electron/issues/8692)); third-party `electron-chrome-extensions` extends coverage. 1Password refusal is documented in a [1Password community staff response](https://www.1password.community/discussions/1password/desktop-application-integration/30653/replies/30656) — *"1Password has a strict whitelist that they're not currently adding to"* (forum statement, not formal policy).

**Two lessons:**
1. Everyone who got "full Chrome extensions + 1Password works out of the box" did it by **being Chromium** (Arc / Dia) — which is the option you're rejecting on size and architecture grounds.
2. The one WebKit browser that got 1Password working (Orion) did it through native WebExtensions re-implementation **plus** a direct allowlisting deal with 1Password — not a public API you can just call.

---

## 5. The options in full

### Option 1 — `WKWebExtensionController` (Apple, macOS 15.4+)

**What:** Apple's public API ([`WKWebExtension`](https://developer.apple.com/documentation/webkit/wkwebextension/), [`WKWebExtensionContext`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/), [`WKWebExtensionController`](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller), `WKWebExtensionMatchPattern`) lets a third-party WebKit app load standard cross-browser WebExtension bundles. Availability: **iOS 18.4, iPadOS 18.4, visionOS 2.4, macOS 15.4**. Supports both **MV2 and MV3** (the loader matches Safari's; per `WKWebExtension.manifestVersion` and `unsupportedManifestVersion` error).

**Wiring (corrected from the previous draft of this doc):**
- Create a [`WKWebExtensionContext`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/) for each loaded extension.
- Attach the context to a controller via `WKWebExtensionController.load(_:)` (Obj-C: `loadExtensionContext:error:`).
- For web views that render extension pages, use [`extensionContext.webViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration) as the `WKWebViewConfiguration` (the configuration is **vended by the context**, not constructed and passed in).
- Implement [`WKWebExtensionControllerDelegate`](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate) for tabs/windows (`openWindowsFor:`, `focusedWindowFor:`), permission prompts ([`promptForPermissions:in:for:completionHandler:`](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:promptforpermissions:in:for:completionhandler:))), and **native messaging**: `webExtensionController(_:sendMessage:to:for:replyHandler:)` and `webExtensionController(_:connectUsing:for:completionHandler:)` (the latter passes a `WKWebExtensionMessagePort`).

**Native messaging fallback to NSExtension:** WebKit landed *"Add support for nativeMessaging with NSExtension"* ([webkit-changes commit a4a639](https://www.mail-archive.com/webkit-changes@lists.webkit.org/msg219249.html), [w3c/webextensions #256](https://github.com/w3c/webextensions/issues/256)) — if the host doesn't implement the messaging delegate methods, WebKit routes through an `NSExtension`, matching Safari's behavior.

**Pros:**
- Only sanctioned path to real extensions on WebKit; zero binary cost.
- Covers the high-value, low-friction wins: **uBlock Origin Lite, Dark Reader, Vimium, Stylus, Refined GitHub, React DevTools**.
- Fits your per-pane configuration model — the context vends a per-extension `WKWebViewConfiguration`.

**Cons / unknowns:**
- **1Password is not a given.** Even though the API exposes native-messaging hooks, 1Password's desktop app verifies the **extension ID + native-messaging-host file** against a hardcoded allowlist before connecting ([support.1password.com/1password-browser-connection-security](https://support.1password.com/1password-browser-connection-security/) — *"Before accepting a connection, the 1Password app verifies the extension ID and native messaging hosts file"* + code-signature validation). Your `WKWebExtensionController`-hosted instance won't be on that list. This is the exact gate Orion had to clear via direct coordination with 1Password. **Treat 1Password-via-extension as a business/partnership step, not a technical one.**
- Exact MV2/MV3 parity vs. Safari needs verification in Xcode against your target SDK.
- You must implement the controller delegate (tabs, windows, permission prompts, messaging) — non-trivial surface.

**Verdict:** Adopt for ad-blocking and dev extensions (big perceived-quality win). Do **not** assume it delivers 1Password.

---

### Option 2 — 1Password CLI (`op`) fill shim

**What:** Instead of fighting the extension allowlist, integrate the **1Password CLI**. Bind a key (e.g. ⌘\) in a web pane → resolve the credential for the current host via `op item get` / `op read "op://vault/item/field"` → inject into the page's form via `WebPage.callJavaScript` / `evaluateJavaScript`. Secret-reference syntax is documented at [developer.1password.com/docs/cli/secret-reference-syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/).

**Mechanics:**
- **Touch ID / biometric unlock** through the desktop app integration ([developer.1password.com/docs/cli/biometric-security](https://developer.1password.com/docs/cli/biometric-security/)): *"Authorization establishes a 10-minute session that automatically refreshes on each use… authorization expires after 10 minutes of inactivity in the terminal session, **with a hard limit of 12 hours**, after which you must reauthorize."* Authorization is **limited to a single account at a time** and is per-terminal-session (each terminal needs its own approval).
- [`op inject`](https://developer.1password.com/docs/cli/secrets-scripts/) / `op run` resolve `op://` references into env vars / templates (useful for the agent path too).
- **Service-account tokens** (`OP_SERVICE_ACCOUNT_TOKEN`) for unattended use ([service accounts docs](https://developer.1password.com/docs/service-accounts/use-with-1password-cli/)).
- **Shell Plugins** ([shell-plugins docs](https://developer.1password.com/docs/cli/shell-plugins/)) extend biometric injection to 60+ third-party CLIs.
- **Official SDKs** ([developer.1password.com/docs/sdks](https://developer.1password.com/docs/sdks/)): *"Go, JavaScript, or Python."* **No Swift SDK** — confirmed. For Swift, shell out to `op` or call the [1Password Connect](https://developer.1password.com/docs/connect/get-started/) self-hosted REST API (bearer-token auth).

**Pros:** ~half a day of work; you control the UX; works today regardless of allowlists; Touch ID feels native; doubles as the agent secret-resolution path.

**Cons:** not "automatic" autofill — it's an explicit fill action; requires the 1Password app + CLI installed and biometric integration enabled; one account at a time under biometric session; 12-hour hard reauthorize cap.

**Verdict:** Adopt. This is the pragmatic 1Password answer.

---

### Option 3 — Per-profile `WKWebsiteDataStore(forIdentifier:)`

**What:** [`WKWebsiteDataStore(forIdentifier:)`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) on **macOS 14 / iOS 17+** creates a **separate persistent store** distinct from the default. Identified stores live under `~/Library/WebKit/WebsiteDataStore/<NSUUID>/` (vs. the default store at `~/Library/WebKit/WebsiteData/`) per the [WebKit blog — Building Profiles with new WebKit API](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/).

What's persisted (the relevant `WKWebsiteDataType*` constants): **cookies, disk + memory cache, localStorage, IndexedDB databases, service worker registrations**, etc. Assign one per pane/profile, persist the UUID, recreate with the same identifier on relaunch → "log in once, stay logged in" per profile.

**Pros:**
- Directly fixes the "keeps logging me out" complaint **if** the cause is non-persistent or shared/clobbered stores.
- Enables **work vs. personal vs. preview** sessions in different panes (how Arc/Orion do profiles) — maps perfectly onto your existing per-pane `BridgePaneController` / per-pane `WKUserContentController` design.

**Cons:** doesn't share with Safari/Chrome (still isolated); profile management UX to build; you own UUID lifecycle.

**First check:** confirm you're not using [`WKWebsiteDataStore.nonPersistent()`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()) anywhere and not calling `removeData(ofTypes:)` on launch — [`default()`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/default()) already persists across launches, so a logout bug may simply be a misconfigured store.

**Verdict:** Adopt. Low effort, high fit.

---

### Option 4 — Import system-browser sessions (the cmux/agent-browser pattern)

**What:** At pane creation (or on demand), import cookies/sessions from the user's real Chrome/Firefox/Arc/etc. into the pane's `WKHTTPCookieStore`, so the pane "starts authenticated." Two flavors:
- **Profile snapshot** (agent-browser `--profile`): copy the user's browser profile to a temp dir read-only, never mutating the original.
- **Cookie extraction**: read the source browser's cookie DB and inject relevant cookies into the WebKit store via `WKHTTPCookieStore.setCookie`.

**Pros:** best UX — login carries over with no manual step; this is exactly how cmux ships it.

**Cons / hard parts:**
- **Chromium cookies are encrypted** (per-OS; on macOS the AES key lives in the login Keychain under "Chrome Safe Storage"). Extraction requires Keychain access and is brittle across Chrome updates.
- **Safari's cookie container is sandboxed off-limits** without special entitlements (won't pass App Store review).
- Importing live session cookies is a **secret-handling** responsibility — scope to the site the user is navigating to; don't vacuum everything.
- Cross-browser format churn (20+ browsers = ongoing maintenance, which is why cmux frames it as a feature, not a one-off).

**Verdict:** Strong consider, phase 4. Highest-UX auth answer, but the most maintenance. Start with Chrome-only cookie import for a target site, behind an explicit "Import login from Chrome" action.

---

### Option 5 — `storageState` save/load (cookies + localStorage JSON)

**What:** The Playwright pattern ([playwright.dev/docs/auth](https://playwright.dev/docs/auth)): `browserContext.storageState({ path })` returns *"current cookies, local storage snapshot"*; reload via `browser.newContext({ storageState })`. **IndexedDB is opt-in**, not default — pass `{ path: ..., indexedDB: true }`. cmux exposes this verbatim (`state save` / `state load`).

**Pros:** dead simple; the canonical way agents skip re-login across test runs; portable across panes/runs; no Keychain/crypto.

**Cons:** the file **is** a live session token. Playwright docs frame it as: *"delete the stored state when it expires"* — gitignore it, rotate when it expires, treat as a bearer token. State dies when the session does.

**Verdict:** Adopt, especially for the agent path. Implement `WKHTTPCookieStore` export/import + a localStorage dump via `callJavaScript` (and IndexedDB via JS if you need it). This is the single most useful primitive for "programs testing programs."

---

### Option 6 — CDP attach to user's Chrome — *degraded by Chrome 136+*

**What it used to be:** User launches Chrome with `--remote-debugging-port=9222`; agent reads `localhost:9222/json/version` for the WebSocket URL, then `chromium.connectOverCDP('http://localhost:9222')` drives the **already-authenticated** profile — live cookies, live tabs, live extensions including 1Password.

**What changed (May 2025):** Chrome 136 added App-Bound-Encryption hardening against CDP-based cookie theft. Per [Chrome Developers — Changes to remote debugging](https://developer.chrome.com/blog/remote-debugging-port): *"Chrome debugging protocol exposes all information about the UI to all processes on localhost, and allows any local process to hijack the UI."* From Chrome 136, `--remote-debugging-port` is **ignored** unless paired with `--user-data-dir=<non-default>`. This means the entire premise of "attach to my real signed-in Chrome" is gone — you must launch CDP against a **fresh, separate profile**, which has no cookies / no login / no extensions.

**Pros (what survives):** still useful as an **agent-driven separate Chromium** mode for testing; CDP power (network interception, screencast, viewport emulation) intact; can pair with Option 5's `storageState` to seed login into the fresh profile.

**Cons:**
- **No longer "uses the user's logged-in session"** — the headline value prop is gone.
- Still security-sensitive: the debug port grants full control over the spawned profile; bind localhost only.
- Functionally overlaps with Option 5 (storageState into a fresh Chromium) plus running your own headed Chrome — a heavier path than just driving a WebKit pane.

**Verdict:** **Reconsider.** This was the strongest agent-testing answer pre-Chrome 136; now it's a niche advanced mode. If you ship it, ship it as "agent-driven Chromium with storage-state seeding," not "attach to my Chrome." For most cases, Opt 5 + a `WKWebView`-driven pane covers the use case at lower complexity.

---

### Option 7 — Device Authorization Grant (RFC 8628)

**What:** The pane/agent POSTs to a device-authorization endpoint, gets a `device_code` + short `user_code` + `verification_uri` (+ optional `verification_uri_complete`, `expires_in`, `interval`), shows the user the code, and **polls the token endpoint** while the user authorizes on any device's browser. Spec: [RFC 8628 §3.2](https://datatracker.ietf.org/doc/html/rfc8628#section-3.2). Supported by:
- **GitHub** ([docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow))
- **Google** ([limited-input devices](https://developers.google.com/identity/protocols/oauth2/limited-input-device))
- **Microsoft Entra ID** ([device code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code))
- **Auth0** ([Device Authorization Flow](https://auth0.com/docs/get-started/authentication-and-authorization-flow/device-authorization-flow))
- **Okta** ([Device Authorization Grant](https://developer.okta.com/docs/guides/device-authorization-grant/main/))
- **Keycloak** ([securing apps](https://www.keycloak.org/securing-apps/oidc-layers))

**Pros:** purpose-built for headless/embedded/agent contexts — no in-app redirect handling, no embedded login form, no passkey limitations. The cleanest "agent needs to authenticate to a first-party service" path.

**Cons:**
- Only works where the provider implements it.
- Out-of-band step (user approves elsewhere).
- Yields an **API token**, not a browser session — great for API-backed flows, less so for "drive this arbitrary web UI."
- ⚠️ **Microsoft Entra explicitly recommends disabling device code flow in tenants** ([learn.microsoft.com](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code)): *"Device code flow is a high-risk authentication method… Microsoft recommends blocking device code flow wherever possible."* Works for personal/dev tools; may be blocked in corporate Entra tenants.

**Verdict:** Adopt wherever the target supports it — especially for AgentStudio's own integrations (GitHub PR ops, etc.). Be aware of the Entra caveat for any Microsoft 365 / corporate login.

---

### Option 8 — `ASWebAuthenticationSession`

**What:** Apple's sanctioned OAuth/OIDC flow ([`ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)). Opens the auth URL in a Safari-backed view that runs **in the top-level site context, isolated from your app**, and returns a callback URL via `init(url:callbackURLScheme:completionHandler:)` — completion receives `(URL?, Error?)`. The [`prefersEphemeralWebBrowserSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession) property controls cookie sharing: `false` (default) shares Safari's cookies and shows a consent dialog → frequent one-tap SSO; `true` runs ephemeral with no shared state. Because it's a real Safari/WebKit browser context, **WebAuthn/passkeys work** ([passkeys.dev — iOS](https://passkeys.dev/docs/reference/ios/), [— macOS](https://passkeys.dev/docs/reference/macos/)).

**Pros:** the *only* legitimate Safari-cookie-sharing surface; ideal for **AgentStudio-initiated OAuth** (Linear, GitHub, etc.); passkeys work inside it.

**Cons:** you get only the final callback URL — **no DOM control inside the flow** (so it can't be scripted/inspected); it's for *your app's* auth, not for logging into an arbitrary in-pane site.

**Verdict:** Adopt for app-initiated OAuth. Not a substitute for in-pane login.

---

### Option 9 — Embed CEF / Chromium

**What:** Bundle Chromium (CEF). Gets the full Chrome extension ecosystem and a working 1Password (Chrome IDs are on 1Password's default allowlist).

**Pros:** solves both problems comprehensively in one move.

**Cons (the size is the *least* of them):**
- **+100–200 MB** binary; memory back in Electron territory — kills the "tiny fast Swift app" thesis.
- **Abandons your entire architecture:** you lose `WKWebExtensionController`, the per-pane WebKit model, and the native integration of your Bridge runtime/transport. Your `agentstudio://` scheme, content-world isolation, and push pipeline are all WebKit-shaped.
- CEF on macOS arm64 is a real, ongoing maintenance burden (build, sign, notarize, update cadence).
- Even Electron — full Chromium — **can't get 1Password** without being on the allowlist; CEF inherits the same native-messaging-host allowlist mechanics (see §4 Electron row).

**Verdict:** Reject. The closest peer (cmux) faced this exact choice and stayed on WKWebView. Chromium only makes sense if you're building a *browser*, not a coding tool with web panes.

---

## 6. Sign-in mechanism reference (the auth toolbox)

Quick map of *which mechanism for which situation*:

| Situation | Use | Why |
|-----------|-----|-----|
| AgentStudio authenticating to its own integrations (GitHub, Linear) | **Device code flow** (Opt 7) or **`ASWebAuthenticationSession`** (Opt 8) | Headless-friendly / sanctioned OAuth |
| Human logs into a site in a pane and wants it to stick | **Per-profile data store** (Opt 3) + **session import** (Opt 4) | Persistent, per-profile, carries over |
| Human wants 1Password autofill | **`op` CLI shim** (Opt 2); extensions (Opt 1) only if 1Password allowlists you | Allowlist is the blocker, not the API |
| Agent must get past a login wall to test a web app | **storageState reuse** (Opt 5) → **seeded test session** (§7) → **agent-driven Chromium + storageState** (Opt 6) | Reuse > bypass > spawn, by safety |
| Logging into your *own* service (your RP domain) | **Passkeys/WebAuthn** in the webview | Works for your linked domain only (below) |

**Passkeys / WebAuthn caveat (important for embedded contexts):** A `WKWebView`/`WebPage` *can* invoke the platform authenticator and system passkey UI on modern macOS ([passkeys.dev — macOS](https://passkeys.dev/docs/reference/macos/), iOS 16+ / macOS 13+) — **but** (verbatim from passkeys.dev): *"Embedded WebViews run in the context of the calling app, meaning only passkeys for the linked web domain (RP ID) can be created or used for sign in."* Specifically: only RP IDs declared in the app's `webcredentials` Associated Domains entitlement can invoke WebAuthn from the embedded pane. For arbitrary third-party RPs (verbatim): *"If you need a web view to authenticate to a domain you don't own, you should use ASWebAuthenticationSession."* So passkeys are great for "log into *our* service from our webview," useless for "log into github.com inside a generic pane."

---

## 7. "Programs to test programs" — agent login patterns

When an AI agent needs to drive a web app under test, ranked by safety/maintainability:

1. **`storageState` reuse (Opt 5)** — best default. A human (or a one-time setup job) logs in once and saves state; every agent run loads it. No secrets in code, no re-login, trivial to rotate. cmux and Playwright both standardize on this.
2. **Device code flow (Opt 7)** — when the target is a first-party service with an API; agent prints the code, a human approves once, token is cached/refreshed. Watch Entra tenant policy.
3. **Seeded test sessions / auth-bypass tokens (staging only)** — common team patterns to skip real login:
   - a **test-only login endpoint** gated by `ENV=test` that mints a signed session cookie/JWT directly,
   - injecting a forged-but-valid session into storage,
   - an `x-test-auth` / bypass header honored only in non-prod.
   Keep these **strictly env-fenced** so they can never reach production. Best when AgentStudio's user *owns* the app under test. Patterns documented in community discussion (e.g. [Auth0 community thread on bypassing passwordless](https://community.auth0.com/t/bypass-passwordless-login-for-automated-tests/113332) — community workarounds, not Auth0 product features) and the [Auth.js testing guide](https://authjs.dev/guides/testing).
4. **Agent-driven Chromium with storageState seeding (Opt 6)** — when you specifically need Chromium engine power (network interception, CDP) for the test. Note: post-Chrome-136, this is a *fresh* Chromium with seeded state, not the user's real Chrome.
5. **Magic links / email codes** — short-lived (5–10 min) signed tokens; in tests, read the link server-side rather than checking a mailbox.
6. **Password-manager CLI fill (Opt 2)**:
   - 1Password `op` with Touch ID biometric unlock (10-min session, 12-hour hard cap, per-terminal).
   - Bitwarden `bw` ([cli docs](https://bitwarden.com/help/cli/)): `bw unlock` returns a `BW_SESSION` token; *"Session keys are valid until invalidated using `bw lock` or `bw logout`, however they will not persist if you open a new terminal window."* Users **commonly persist `BW_SESSION` in their shell profile**, which is less secure than 1Password's biometric session (and contrary to the per-session guidance). For Touch ID on Bitwarden CLI, third-party [`bitwarden-cli-bio`](https://github.com/jeanregisser/bitwarden-cli-bio) exists.
   Resolve the credential, then `callJavaScript` to fill the form. Works against real login when you can't seed a session.

**Recommended agent default for AgentStudio:** a per-pane **`storageState`** primitive (export/import) + an **"authenticate this pane"** action that can drive `op` fill or a device-code prompt, plus an opt-in **agent-driven-Chromium-with-seeded-state mode** for advanced CDP-needing tests.

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
- Wire `WKWebExtensionController` (Opt 1) per the corrected wiring above (`context.webViewConfiguration` + `controller.load(context)` + delegate). Ship with **uBlock Origin Lite + Dark Reader** as the headline.
- Explicitly **scope 1Password-via-extension out** of this phase — pursue only if you decide to approach 1Password for allowlisting (Orion precedent).

**Phase 4 — optional, advanced (later, if demand).**
- System-browser session import (Opt 4), Chrome-first, behind an explicit action.
- Opt-in **agent-driven Chromium + storageState** mode (Opt 6 post–Chrome 136) for CDP-needing tests.

**Reject:** embedding CEF/Chromium (Opt 9). It's the only option that throws away your bridge architecture, and your closest peer proved it's unnecessary.

---

## 9. Open questions / verify before building

- **`WKWebExtension` MV2/MV3 parity** vs. Safari on your target SDK — verify in Xcode against the macOS 26 SDK.
- **Does 1Password expose anything consumable** to a third-party `WKWebExtensionController` host, or is it strictly allowlist + Safari App Extension? (Likely the latter — treat as a coordination step.)
- **Chrome cookie decryption on macOS** (Keychain "Chrome Safe Storage" key) — confirm entitlement/UX implications before committing to Opt 4.
- **App Store vs. direct distribution** — Safari-container reads and some entitlements won't pass review; decide distribution model first.
- **Entra tenant policy** for any corporate-target device-code flow integration.

*Resolved by this revision pass:*
- ~~1Password Swift SDK~~: **confirmed none** ([developer.1password.com/docs/sdks](https://developer.1password.com/docs/sdks/) lists Go, JavaScript, Python only). Use `op` or Connect REST from Swift.

---

## Revision notes

Initial draft 2026-06-01; primary-source validation pass same day. Material corrections from validation:

- Engine API name: `WebKit.WebView` / `WebKit.WebPage` (not `SwiftUI.WebView`); availability **macOS 26 / visionOS 3**.
- `WKWebExtensionController` wiring (Opt 1): controller is attached via `load(_:)`; the per-extension `WKWebViewConfiguration` is vended from `context.webViewConfiguration`. Native-messaging delegate methods are `sendMessage:to:for:replyHandler:` and `connectUsing:for:completionHandler:` (the previous draft had a fabricated `connectUsingMessagePort:forExtensionContext:`).
- Chrome 136+ broke Option 6's "attach to user's signed-in Chrome" premise; rewrote that option.
- Playwright `storageState` IndexedDB is opt-in, not default.
- 1Password biometric session has a **12-hour hard cap** plus per-terminal authorization.
- cmux license is **GPL-3.0-or-later**, not AGPL-3.0; tagline corrected; verbatim quote capitalized correctly.
- cmux is **Ghostty-based** — same engine starting point as AgentStudio (a notable point of architectural sympathy).
- Atlassian / Browser Co. acquisition closed **Oct 21 2025** (announced Sept 4 2025).
- WRY API renamed to `with_extensions_path` (plural) in v0.48.0; macOS still has no extension support.
- Microsoft Entra explicitly recommends blocking device code flow in tenants.
- Electron `chrome.*` supported APIs enumerated.
- Orion 1Password initially required nightly 1Password desktop build ≥ 81009030.
- 1Password's default allowlist of browsers is described as "including" — non-exhaustive.
- Electron 1Password refusal is sourced from a 1Password community staff statement, not formal policy.

---

## Sources

Apple WebKit / Auth APIs:
- [WKWebExtensionController — Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller) · [WKWebExtension](https://developer.apple.com/documentation/webkit/wkwebextension/) · [WKWebExtensionContext.webViewConfiguration](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration) · [WKWebExtensionControllerDelegate.promptForPermissions](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:promptforpermissions:in:for:completionhandler:))
- [WKWebExtension.manifestVersion](https://developer.apple.com/documentation/webkit/wkwebextension/manifestversion) · [unsupportedManifestVersion error](https://developer.apple.com/documentation/webkit/wkwebextension/error/unsupportedmanifestversion)
- [WebKit-changes — Add support for nativeMessaging with NSExtension](https://www.mail-archive.com/webkit-changes@lists.webkit.org/msg219249.html) · [w3c/webextensions #256](https://github.com/w3c/webextensions/issues/256)
- [WKWebsiteDataStore — Apple](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) · [.default()](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/default()) · [.nonPersistent()](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()) · [WebKit blog — Building Profiles](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)
- [ASWebAuthenticationSession — Apple](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) · [prefersEphemeralWebBrowserSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession)
- [WebKit for SwiftUI — Apple](https://developer.apple.com/documentation/webkit/webkit-for-swiftui) · [WebView (SwiftUI struct)](https://developer.apple.com/documentation/webkit/webview-swift.struct) · [WebKit blog — News from WWDC25](https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/)
- [passkeys.dev — iOS](https://passkeys.dev/docs/reference/ios/) · [— macOS](https://passkeys.dev/docs/reference/macos/)

cmux / agent-browser (closest prior art):
- [manaflow-ai/cmux README](https://github.com/manaflow-ai/cmux) · [cmux-browser SKILL.md](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/SKILL.md) · [authentication.md](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/references/authentication.md) · [session-management.md](https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-browser/references/session-management.md)
- cmux issues [#2803](https://github.com/manaflow-ai/cmux/issues/2803), [#2842](https://github.com/manaflow-ai/cmux/issues/2842), [#3442](https://github.com/manaflow-ai/cmux/issues/3442)
- [vercel-labs/agent-browser README](https://github.com/vercel-labs/agent-browser)
- [manaflow-ai/manaflow](https://github.com/manaflow-ai/manaflow) (sibling product, distinct)

Other prior art:
- [Orion — macOS Web Extensions Support](https://help.kagi.com/orion/browser-extensions/macos-extensions.html) · [Orion technical FAQ](https://help.kagi.com/orion/misc/technical.html) · [Orion 1Password](https://help.kagi.com/orion/browser-extensions/1password.html)
- [TechCrunch — Atlassian to buy Browser Co.](https://techcrunch.com/2025/09/04/atlassian-to-buy-arc-developer-the-browser-company-for-610m/) · [Thurrott — acquisition closed](https://www.thurrott.com/cloud/325637/atlassian-acquires-developer-of-the-arc-and-dia-web-browsers)
- [WRY README](https://github.com/tauri-apps/wry) · [WRY CHANGELOG](https://github.com/tauri-apps/wry/blob/dev/CHANGELOG.md)
- [Electron Extensions API](https://www.electronjs.org/docs/latest/api/extensions) · [electron-chrome-extensions npm](https://www.npmjs.com/package/electron-chrome-extensions) · [Electron native messaging issue #8692](https://github.com/electron/electron/issues/8692)
- [1Password community — Electron statement](https://www.1password.community/discussions/1password/desktop-application-integration/30653/replies/30656)

1Password:
- [Browser connection security](https://support.1password.com/1password-browser-connection-security/) · [Connect additional browsers](https://support.1password.com/additional-browsers/) · [Connect 1Password browser & app](https://support.1password.com/connect-1password-browser-app/)
- [CLI biometric security](https://developer.1password.com/docs/cli/biometric-security/) · [Secret reference syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/) · [Secrets in scripts (op inject/run)](https://developer.1password.com/docs/cli/secrets-scripts/) · [Service accounts](https://developer.1password.com/docs/service-accounts/use-with-1password-cli/) · [Shell Plugins](https://developer.1password.com/docs/cli/shell-plugins/)
- [Official SDKs (Go, JS, Python)](https://developer.1password.com/docs/sdks/) · [1Password Connect](https://developer.1password.com/docs/connect/get-started/)

Auth patterns:
- [OAuth Device Authorization Grant — RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)
- [GitHub device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow) · [Google limited-input device](https://developers.google.com/identity/protocols/oauth2/limited-input-device) · [Microsoft Entra device code](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code) · [Auth0 Device Authorization Flow](https://auth0.com/docs/get-started/authentication-and-authorization-flow/device-authorization-flow) · [Okta Device Authorization Grant](https://developer.okta.com/docs/guides/device-authorization-grant/main/) · [Keycloak OIDC](https://www.keycloak.org/securing-apps/oidc-layers)
- [Playwright auth](https://playwright.dev/docs/auth) · [Playwright BrowserContext](https://playwright.dev/docs/api/class-browsercontext) · [Playwright BrowserType (connectOverCDP)](https://playwright.dev/docs/api/class-browsertype) · [Chrome — Changes to remote debugging (136+)](https://developer.chrome.com/blog/remote-debugging-port) · [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) · [Playwright #12782](https://github.com/microsoft/playwright/issues/12782)
- [Bitwarden CLI](https://bitwarden.com/help/cli/) · [bitwarden-cli-bio](https://github.com/jeanregisser/bitwarden-cli-bio)
- [Auth.js testing](https://authjs.dev/guides/testing) · [Auth0 community — bypass passwordless](https://community.auth0.com/t/bypass-passwordless-login-for-automated-tests/113332)
