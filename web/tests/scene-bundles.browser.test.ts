import { gsap } from "gsap";
import { afterEach, beforeAll, describe, expect, inject, it, vi } from "vitest";
import { commands } from "vitest/browser";

// The registry module also declares `window.AgentStudioScenes`, which scene.js fills.
import type { RegisteredSceneBundle } from "../scripts/scene-bundles/scene-bundle-registry.ts";
import { sceneIds } from "../src/motion-scenes/scene-contract";
import { resolveSceneModule } from "../src/motion-scenes/scene-registry";
import { kitPhoneAttribute } from "../src/recreation-kit/recreation-kit-dom";
import type { BuiltSceneBundleFiles } from "./scene-bundle-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    buildSceneBundlesForBrowserTest(): Promise<readonly BuiltSceneBundleFiles[]>;
  }
}

interface ManifestReading {
  readonly sceneId: string;
  readonly websiteRevision: string;
  readonly durationSeconds: number;
  readonly labels: Readonly<Record<string, number>>;
  readonly stage: { readonly width: number; readonly height: number };
  readonly phoneBreakpoint: { readonly containerName: string; readonly maxWidthPx: number };
  readonly seed: number;
  readonly sha256: Readonly<Record<string, string>>;
}

interface SceneBundleUnderTest {
  readonly sceneJs: string;
  readonly sceneHtml: string;
  readonly sceneCss: string;
  readonly manifest: ManifestReading;
}

// Building runs the production Astro build and headless Chrome; this bounds a
// hang, it is not a speed budget.
const bundleBuildHangBoundMs = 240_000;

let bundlesBySceneId: ReadonlyMap<string, SceneBundleUnderTest>;
let sceneScriptFindingsBySceneId: ReadonlyMap<string, readonly string[]>;
const mountedElements: Element[] = [];

function requireBuiltFindings(sceneId: string): readonly string[] {
  const findings = sceneScriptFindingsBySceneId.get(sceneId);
  if (findings === undefined) {
    throw new Error(`No scene.js audit for ${sceneId}`);
  }
  return findings;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null;
}

function isRecordOf<TValue>(
  value: unknown,
  isEntryValue: (entryValue: unknown) => entryValue is TValue,
): value is Readonly<Record<string, TValue>> {
  return isRecord(value) && Object.values(value).every(isEntryValue);
}

const isNumber = (value: unknown): value is number => typeof value === "number";
const isString = (value: unknown): value is string => typeof value === "string";

function isManifestReading(value: unknown): value is ManifestReading {
  if (!isRecord(value)) {
    return false;
  }
  const { stage, phoneBreakpoint } = value;
  return (
    isString(value["sceneId"]) &&
    isString(value["websiteRevision"]) &&
    isNumber(value["durationSeconds"]) &&
    isNumber(value["seed"]) &&
    isRecordOf(value["labels"], isNumber) &&
    isRecordOf(value["sha256"], isString) &&
    isRecord(stage) &&
    isNumber(stage["width"]) &&
    isNumber(stage["height"]) &&
    isRecord(phoneBreakpoint) &&
    isString(phoneBreakpoint["containerName"]) &&
    isNumber(phoneBreakpoint["maxWidthPx"])
  );
}

function readManifest(manifestText: string): ManifestReading {
  const manifest: unknown = JSON.parse(manifestText);
  if (!isManifestReading(manifest)) {
    throw new Error(`Malformed scene bundle manifest: ${manifestText}`);
  }
  return manifest;
}

const roundToQuarter = (value: number): number => Math.round(value * 4) / 4;

function phoneHiddenWidths(root: HTMLElement): readonly number[] {
  return Array.from(root.querySelectorAll(`[${kitPhoneAttribute}="hidden"]`), (element) =>
    Math.round(element.getBoundingClientRect().width),
  );
}

function requireBundle(sceneId: string): SceneBundleUnderTest {
  const bundle = bundlesBySceneId.get(sceneId);
  if (bundle === undefined) {
    throw new Error(`No scene bundle was emitted for ${sceneId}`);
  }
  return bundle;
}

async function sha256Hex(fileText: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(fileText));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function mountStyle(cssText: string): void {
  const style = document.createElement("style");
  style.textContent = cssText;
  document.head.append(style);
  mountedElements.push(style);
}

function mountStage(markup: string, width: number, height: number): HTMLElement {
  const stage = document.createElement("div");
  stage.style.width = `${String(width)}px`;
  stage.style.height = `${String(height)}px`;
  stage.innerHTML = markup;
  document.body.append(stage);
  mountedElements.push(stage);
  const root = stage.firstElementChild;
  if (!(root instanceof HTMLElement)) {
    throw new Error("scene.html has no root element");
  }
  return root;
}

function runClassicScript(scriptText: string): void {
  const script = document.createElement("script");
  script.textContent = scriptText;
  document.head.append(script);
  script.remove();
}

/** Every style rule in a stylesheet, including those inside grouping rules. */
function collectStyleRules(rules: CSSRuleList): readonly CSSStyleRule[] {
  return Array.from(rules).flatMap((rule): readonly CSSStyleRule[] => {
    if (rule instanceof CSSStyleRule) {
      return [rule];
    }
    return rule instanceof CSSGroupingRule ? collectStyleRules(rule.cssRules) : [];
  });
}

function collectRuleTypeNames(rules: CSSRuleList): readonly string[] {
  const typeNames: string[] = [];
  for (const rule of Array.from(rules)) {
    typeNames.push(rule.constructor.name);
    if (rule instanceof CSSGroupingRule && !(rule instanceof CSSStyleRule)) {
      typeNames.push(...collectRuleTypeNames(rule.cssRules));
    }
  }
  return typeNames;
}

const leakCheckedProperties = [
  "display",
  "position",
  "box-sizing",
  "margin-top",
  "padding-top",
  "border-top-width",
  "color",
  "background-color",
  "font-family",
  "font-size",
  "line-height",
  "opacity",
  "visibility",
] as const;

function snapshotComputedStyles(elements: readonly Element[]): readonly string[] {
  return elements.map((element) => {
    const computedStyle = getComputedStyle(element);
    return leakCheckedProperties
      .map((property) => `${property}=${computedStyle.getPropertyValue(property)}`)
      .join(" ");
  });
}

// Computed values that decide what a frame shows; layout is checked through each
// element's box relative to the scene root.
const renderedProperties = [
  "display",
  "position",
  "box-sizing",
  "margin-top",
  "margin-left",
  "padding-top",
  "padding-left",
  "border-top-width",
  "border-top-color",
  "border-top-left-radius",
  "color",
  "background-color",
  "font-family",
  "font-size",
  "font-weight",
  "line-height",
  "letter-spacing",
  "white-space",
  "opacity",
  "visibility",
  "transform",
  "translate",
  "clip-path",
  "overflow-x",
  "flex-grow",
  "grid-template-rows",
  "container-name",
] as const;

let websiteStylesheets: readonly string[] | undefined;

/** The dev server's `/` styles: the website's own CSS for the same components. */
async function loadWebsiteStylesheets(): Promise<readonly string[]> {
  if (websiteStylesheets !== undefined) {
    return websiteStylesheets;
  }
  const pageUrl = new URL("/", inject("siteHeaderBrowserTestUrl"));
  // Chrome refuses this page's fetch to the 127.0.0.1 spelling of the loopback
  // server; the test page's own host name reaches the same server.
  pageUrl.hostname = location.hostname;
  const response = await fetch(pageUrl);
  if (!response.ok) {
    throw new Error(`Website page answered ${String(response.status)}`);
  }
  const page = new DOMParser().parseFromString(await response.text(), "text/html");
  websiteStylesheets = Array.from(
    page.querySelectorAll("head style"),
    (style) => style.textContent,
  );
  return websiteStylesheets;
}

/** Renders scene markup under only the given CSS, in its own document. */
function renderInFrame(
  stylesheets: readonly string[],
  markup: string,
  width: number,
  height: number,
): readonly string[] {
  const frame = document.createElement("iframe");
  frame.style.width = `${String(width)}px`;
  frame.style.height = `${String(height)}px`;
  frame.style.border = "0";
  document.body.append(frame);
  mountedElements.push(frame);
  const frameDocument = frame.contentDocument;
  if (frameDocument === null) {
    throw new Error("Rendering frame has no document");
  }
  for (const stylesheet of stylesheets) {
    const style = frameDocument.createElement("style");
    style.textContent = stylesheet;
    frameDocument.head.append(style);
  }
  frameDocument.body.style.margin = "0";
  const stage = frameDocument.createElement("div");
  stage.style.width = `${String(width)}px`;
  stage.style.height = `${String(height)}px`;
  stage.innerHTML = markup;
  frameDocument.body.append(stage);
  const root = stage.firstElementChild;
  if (root === null) {
    throw new Error("scene.html has no root element");
  }
  const rootBounds = root.getBoundingClientRect();
  const frameWindow = frameDocument.defaultView ?? window;
  return [root, ...Array.from(root.querySelectorAll("*"))].map((element, index) => {
    const computedStyle = frameWindow.getComputedStyle(element);
    const bounds = element.getBoundingClientRect();
    const box = [
      bounds.left - rootBounds.left,
      bounds.top - rootBounds.top,
      bounds.width,
      bounds.height,
    ].map(roundToQuarter);
    return [
      `${String(index)} <${element.tagName.toLowerCase()} class="${element.getAttribute("class") ?? ""}">`,
      `box=${box.join(",")}`,
      ...renderedProperties.map(
        (property) => `${property}=${computedStyle.getPropertyValue(property)}`,
      ),
    ].join(" ");
  });
}

describe("scene bundles for HyperFrames", () => {
  beforeAll(async () => {
    const builtBundles = await commands.buildSceneBundlesForBrowserTest();
    sceneScriptFindingsBySceneId = new Map(
      builtBundles.map((builtBundle) => [builtBundle.sceneId, builtBundle.sceneScriptFindings]),
    );
    bundlesBySceneId = new Map(
      builtBundles.map((builtBundle): [string, SceneBundleUnderTest] => [
        builtBundle.sceneId,
        {
          sceneJs: builtBundle.files["scene.js"] ?? "",
          sceneHtml: builtBundle.files["scene.html"] ?? "",
          sceneCss: builtBundle.files["scene.css"] ?? "",
          manifest: readManifest(builtBundle.files["manifest.json"] ?? ""),
        },
      ]),
    );
  }, bundleBuildHangBoundMs);

  afterEach(() => {
    for (const element of mountedElements.splice(0)) {
      element.remove();
    }
    delete window.AgentStudioScenes;
  });

  it("emits exactly one bundle folder per scene", () => {
    // Arrange / Act
    const emittedSceneIds = Array.from(bundlesBySceneId.keys()).toSorted();

    // Assert
    expect(emittedSceneIds).toEqual([...sceneIds].toSorted());
  });

  for (const sceneId of sceneIds) {
    describe(sceneId, () => {
      it("pins its three files by the sha256 recorded in the manifest", async () => {
        // Arrange
        const bundle = requireBundle(sceneId);

        // Act
        const actualHashes = {
          "scene.js": await sha256Hex(bundle.sceneJs),
          "scene.html": await sha256Hex(bundle.sceneHtml),
          "scene.css": await sha256Hex(bundle.sceneCss),
        };

        // Assert
        expect(bundle.manifest.sceneId).toBe(sceneId);
        expect(bundle.manifest.websiteRevision).toMatch(/^[0-9a-f]{40}$/);
        expect(actualHashes).toEqual(bundle.manifest.sha256);
      });

      it("labels its timeline with the scene's declared steps, in order", () => {
        // Arrange
        const bundle = requireBundle(sceneId);

        // Act
        const labelNamesInTimeOrder = Object.entries(bundle.manifest.labels)
          .toSorted(([, firstTime], [, secondTime]) => firstTime - secondTime)
          .map(([labelName]) => labelName);

        // Assert
        expect(labelNamesInTimeOrder).toEqual(
          resolveSceneModule(sceneId)?.steps.map((step) => step.timelineLabel),
        );
      });

      it("registers a scene whose timeline matches the manifest when loaded as a classic script", () => {
        // Arrange
        const bundle = requireBundle(sceneId);
        const { width, height } = bundle.manifest.stage;
        mountStyle(bundle.sceneCss);
        const root = mountStage(bundle.sceneHtml, width, height);

        // Act
        runClassicScript(bundle.sceneJs);
        const registeredScene: RegisteredSceneBundle | undefined =
          window.AgentStudioScenes?.[sceneId];
        const timeline = gsap.timeline({ paused: true });
        registeredScene?.buildScene(root, timeline, { width, height, seed: bundle.manifest.seed });

        // Assert
        expect(root.getAttribute("data-scene-root")).toBe(sceneId);
        expect(registeredScene?.durationSeconds).toBe(bundle.manifest.durationSeconds);
        expect(registeredScene?.labels).toEqual(bundle.manifest.labels);
        expect(timeline.duration()).toBe(bundle.manifest.durationSeconds);
        expect(timeline.labels).toEqual(bundle.manifest.labels);
        timeline.revert();
        timeline.kill();
      });

      it("ships scene.js with no module imports and no network access", () => {
        // Arrange
        // Scene fixtures print source code, so "import" appears inside string
        // literals; the audit reads the syntax tree, not the text.
        const bundle = requireBundle(sceneId);
        const { width, height } = bundle.manifest.stage;
        mountStyle(bundle.sceneCss);
        const root = mountStage(bundle.sceneHtml, width, height);
        const fetchSpy = vi
          .spyOn(window, "fetch")
          .mockRejectedValue(new Error("scene.js must not fetch"));
        const xhrOpenSpy = vi
          .spyOn(XMLHttpRequest.prototype, "open")
          .mockImplementation((): void => undefined);

        // Act
        // oxlint-disable-next-line typescript/no-implied-eval -- parses the classic script without running it.
        const parseAsClassicScript = (): unknown => new Function(bundle.sceneJs);
        try {
          runClassicScript(bundle.sceneJs);
          const timeline = gsap.timeline({ paused: true });
          window.AgentStudioScenes?.[sceneId]?.buildScene(root, timeline, {
            width,
            height,
            seed: bundle.manifest.seed,
          });
          timeline.progress(0.5);
          timeline.progress(1);
          timeline.revert();
          timeline.kill();
        } finally {
          fetchSpy.mockRestore();
          xhrOpenSpy.mockRestore();
        }

        // Assert
        expect(parseAsClassicScript).not.toThrow();
        expect(requireBuiltFindings(sceneId)).toEqual([]);
        expect(fetchSpy).not.toHaveBeenCalled();
        expect(xhrOpenSpy).not.toHaveBeenCalled();
      });

      it("renders every element as the website's own stylesheets do", async () => {
        // Arrange
        const bundle = requireBundle(sceneId);
        const { width, height } = bundle.manifest.stage;

        // Act
        const bundleRendering = renderInFrame([bundle.sceneCss], bundle.sceneHtml, width, height);
        const pageRendering = renderInFrame(
          await loadWebsiteStylesheets(),
          bundle.sceneHtml,
          width,
          height,
        );

        // Assert
        expect(bundleRendering.length).toBeGreaterThan(20);
        expect(pageRendering.length).toBe(bundleRendering.length);
        expect(
          bundleRendering.flatMap((elementRendering, index) =>
            elementRendering === pageRendering[index]
              ? []
              : [`bundle ${elementRendering}\npage   ${pageRendering[index] ?? "missing"}`],
          ),
        ).toEqual([]);
      });

      it("scopes every selector in scene.css under the scene root", () => {
        // Arrange
        const bundle = requireBundle(sceneId);
        const sceneRoot = `[data-scene-root="${sceneId}"]`;
        const stylesheet = new CSSStyleSheet();
        stylesheet.replaceSync(bundle.sceneCss);

        // Act
        const styleRules = collectStyleRules(stylesheet.cssRules);
        const complexSelectors = styleRules.flatMap((rule) =>
          rule.selectorText.split(/,(?![^(]*\))/).map((selector) => selector.trim()),
        );

        // Assert
        expect(styleRules.length).toBeGreaterThan(20);
        expect(complexSelectors.filter((selector) => !selector.startsWith(sceneRoot))).toEqual([]);
        expect(
          collectRuleTypeNames(stylesheet.cssRules).filter(
            (typeName) =>
              ![
                "CSSStyleRule",
                "CSSMediaRule",
                "CSSContainerRule",
                "CSSSupportsRule",
                "CSSLayerBlockRule",
                "CSSLayerStatementRule",
              ].includes(typeName),
          ),
        ).toEqual([]);
      });

      it("leaves a copy of the scene outside its root unstyled", () => {
        // Arrange
        const bundle = requireBundle(sceneId);
        const { width, height } = bundle.manifest.stage;
        mountStage(bundle.sceneHtml, width, height);
        const decoyRoot = mountStage(bundle.sceneHtml, width, height);
        decoyRoot.removeAttribute("data-scene-root");
        const decoyElements = [decoyRoot, ...Array.from(decoyRoot.querySelectorAll("*"))];
        const unstyledDecoy = snapshotComputedStyles(decoyElements);

        // Act
        mountStyle(bundle.sceneCss);
        const decoyWithSceneCss = snapshotComputedStyles(decoyElements);

        // Assert
        expect(decoyElements.length).toBeGreaterThan(20);
        expect(decoyWithSceneCss).toEqual(unstyledDecoy);
      });

      it("fills its stage and switches to the phone crop at the manifest's breakpoint", () => {
        // Arrange
        const bundle = requireBundle(sceneId);
        const { maxWidthPx } = bundle.manifest.phoneBreakpoint;
        mountStyle(bundle.sceneCss);

        // Act
        const nativeRoot = mountStage(
          bundle.sceneHtml,
          bundle.manifest.stage.width,
          bundle.manifest.stage.height,
        );
        const phoneRoot = mountStage(bundle.sceneHtml, maxWidthPx, maxWidthPx * 0.625);
        const widerRoot = mountStage(bundle.sceneHtml, maxWidthPx + 1, (maxWidthPx + 1) * 0.625);

        // Assert
        expect(nativeRoot.clientWidth).toBe(bundle.manifest.stage.width);
        expect(nativeRoot.clientHeight).toBe(bundle.manifest.stage.height);
        expect(phoneHiddenWidths(phoneRoot).length).toBeGreaterThan(0);
        expect(phoneHiddenWidths(phoneRoot).every((elementWidth) => elementWidth === 0)).toBe(true);
        expect(phoneHiddenWidths(widerRoot).some((elementWidth) => elementWidth > 0)).toBe(true);
      });
    });
  }
});
