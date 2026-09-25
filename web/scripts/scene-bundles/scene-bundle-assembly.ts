// Assembles one scene's bundle: settled markup and scoped CSS from the built
// home page, the module bundled as a classic script, and labels and duration
// measured by running that module against a paused GSAP timeline.

import type { SceneId } from "../../src/motion-scenes/scene-contract.ts";
import type { HeadlessChromePage } from "./headless-chrome-page.ts";
import {
  sha256Hex,
  type SceneBundleFileName,
  type SceneBundleManifest,
} from "./scene-bundle-manifest.ts";
import {
  measureSceneTimelineInPage,
  measureSelectorReachInPage,
  readSceneMarkupInPage,
  type PageStylesheetSource,
  type SceneBuilderSource,
  type SceneTimelineMeasurement,
} from "./scene-bundle-page-functions.ts";
import {
  bundleSceneModule,
  sceneBundleGlobalName,
  sceneModuleExportName,
} from "./scene-module-bundle.ts";
import { findForbiddenSceneScriptSyntax } from "./scene-script-audit.ts";
import type { BuiltHomePage } from "./scene-source-site-build.ts";
import { parseBuiltStylesheet } from "./scene-stylesheet-parser.ts";
import {
  buildScopedSceneStylesheet,
  collectSelectorProbes,
  resolvePhoneBreakpoint,
} from "./scene-stylesheet-scoping.ts";

export type SceneBundleFiles = Readonly<Record<SceneBundleFileName, string>>;

export interface SceneBundle {
  readonly sceneId: SceneId;
  readonly files: SceneBundleFiles;
  readonly manifest: SceneBundleManifest;
}

export interface AssembleSceneBundleProps {
  readonly sceneId: SceneId;
  readonly webRoot: string;
  readonly page: HeadlessChromePage;
  readonly homePage: BuiltHomePage;
  readonly websiteRevision: string;
  readonly websiteTreeClean: boolean;
  readonly gsapVersion: string;
  readonly stage: { readonly width: number; readonly height: number };
  readonly seed: number;
}

function readStylesheetText(source: PageStylesheetSource, homePage: BuiltHomePage): string {
  if (source.kind === "inline") {
    return source.cssText;
  }
  const linkedText = homePage.stylesheetTextByHref[source.href];
  if (linkedText === undefined) {
    throw new Error(
      `The built home page links a stylesheet the build did not emit: ${source.href}`,
    );
  }
  return linkedText;
}

interface ComposeSceneScriptProps {
  readonly sceneId: SceneId;
  readonly bundleCode: string;
  readonly labels: Readonly<Record<string, number>>;
  readonly durationSeconds: number;
  readonly websiteRevision: string;
}

/** Wraps the Vite IIFE so its module name stays local and only the registry is global. */
function composeSceneScript(props: ComposeSceneScriptProps): string {
  return [
    `/* Agent Studio scene bundle ${props.sceneId}, website revision ${props.websiteRevision}. Generated; do not edit. */`,
    "(function () {",
    '"use strict";',
    props.bundleCode.trimEnd(),
    "var sceneRegistry = (window.AgentStudioScenes = window.AgentStudioScenes || {});",
    `sceneRegistry[${JSON.stringify(props.sceneId)}] = Object.freeze({`,
    `  buildScene: ${sceneBundleGlobalName}.${sceneModuleExportName(props.sceneId)}.buildScene,`,
    `  labels: Object.freeze(${JSON.stringify(props.labels)}),`,
    `  durationSeconds: ${JSON.stringify(props.durationSeconds)},`,
    "});",
    "})();",
    "",
  ].join("\n");
}

const forbiddenMarkupPatterns: readonly RegExp[] = [
  /<script\b/i,
  /\bsrcset=/i,
  /\bsrc=/i,
  /\bhref="(?!#)/i,
  /url\(/i,
];

function assertSelfContainedFiles(sceneId: SceneId, files: SceneBundleFiles): void {
  const violations = [
    ...findForbiddenSceneScriptSyntax(files["scene.js"]).map(
      (finding) => `scene.js uses ${finding}`,
    ),
    ...forbiddenMarkupPatterns
      .filter((pattern) => pattern.test(files["scene.html"]))
      .map((pattern) => `scene.html matches ${String(pattern)}`),
    ...(/@import\b|url\(/i.test(files["scene.css"]) ? ["scene.css loads another resource"] : []),
  ];
  if (violations.length > 0) {
    throw new Error(`${sceneId} bundle is not self-contained: ${violations.join("; ")}`);
  }
}

function assertMeasurementMatchesModule(
  sceneId: SceneId,
  measurement: SceneTimelineMeasurement,
  stage: AssembleSceneBundleProps["stage"],
): void {
  const labelNamesInTimeOrder = measurement.labels.map(([labelName]) => labelName);
  if (measurement.declaredModule?.sceneId !== sceneId) {
    throw new Error(`The ${sceneId} bundle holds ${String(measurement.declaredModule?.sceneId)}.`);
  }
  if (
    JSON.stringify(labelNamesInTimeOrder) !==
    JSON.stringify(measurement.declaredModule.timelineLabels)
  ) {
    throw new Error(
      `${sceneId} timeline labels ${labelNamesInTimeOrder.join(", ")} differ from its declared steps.`,
    );
  }
  if (measurement.rootWidth !== stage.width || measurement.rootHeight !== stage.height) {
    throw new Error(
      `${sceneId} root rendered ${String(measurement.rootWidth)}×${String(measurement.rootHeight)} on a ${String(stage.width)}×${String(stage.height)} stage; scene.css did not reach it.`,
    );
  }
}

/** scene.js, loaded as media will load it, must reproduce the measured timeline. */
function assertRegistrationMatches(
  sceneId: SceneId,
  measured: SceneTimelineMeasurement,
  registered: SceneTimelineMeasurement,
): void {
  const expected = JSON.stringify({
    labels: measured.labels,
    registeredLabels: Object.entries(Object.fromEntries(measured.labels)),
    durationSeconds: measured.durationSeconds,
  });
  const actual = JSON.stringify({
    labels: registered.labels,
    registeredLabels: Object.entries(registered.registration?.labels ?? {}),
    durationSeconds: registered.registration?.durationSeconds,
  });
  if (actual !== expected || registered.durationSeconds !== measured.durationSeconds) {
    throw new Error(
      `${sceneId} scene.js registers ${actual}; the measured timeline is ${expected}.`,
    );
  }
}

export async function assembleSceneBundle(props: AssembleSceneBundleProps): Promise<SceneBundle> {
  const { sceneId, page } = props;
  const source = await page.evaluate(readSceneMarkupInPage, {
    homePageHtml: props.homePage.homePageHtml,
    sceneId,
  });
  const rules = source.stylesheetSources.flatMap((stylesheetSource) =>
    parseBuiltStylesheet(readStylesheetText(stylesheetSource, props.homePage)),
  );
  const reachBySelector = await page.evaluate(measureSelectorReachInPage, {
    sceneMarkup: source.sceneMarkup,
    selectorProbes: collectSelectorProbes(rules),
  });
  const stylesheet = buildScopedSceneStylesheet({
    sceneId,
    rules,
    reachBySelector: new Map(Object.entries(reachBySelector)),
    sceneMarkup: source.sceneMarkup,
  });
  const sceneCss = `/* Agent Studio scene styles for ${sceneId}, website revision ${props.websiteRevision}. Generated; do not edit. */\n${stylesheet.cssText}`;
  const sceneMarkup = `${source.sceneMarkup}\n`;
  const measure = async (builderSource: SceneBuilderSource): Promise<SceneTimelineMeasurement> =>
    await page.evaluate(measureSceneTimelineInPage, {
      sceneId,
      sceneMarkup,
      sceneCss,
      stage: props.stage,
      seed: props.seed,
      builderSource,
    });

  const bundleCode = await bundleSceneModule(props.webRoot, sceneId);
  const measurement = await measure({
    kind: "bundle-export",
    bundleCode,
    globalName: sceneBundleGlobalName,
    exportName: sceneModuleExportName(sceneId),
  });
  assertMeasurementMatchesModule(sceneId, measurement, props.stage);
  const labels = Object.fromEntries(measurement.labels);

  const files: SceneBundleFiles = {
    "scene.js": composeSceneScript({
      sceneId,
      bundleCode,
      labels,
      durationSeconds: measurement.durationSeconds,
      websiteRevision: props.websiteRevision,
    }),
    "scene.html": sceneMarkup,
    "scene.css": sceneCss,
  };
  assertSelfContainedFiles(sceneId, files);
  assertRegistrationMatches(
    sceneId,
    measurement,
    await measure({ kind: "registered", sceneScript: files["scene.js"] }),
  );

  return {
    sceneId,
    files,
    manifest: {
      schemaVersion: 1,
      sceneId,
      websiteRevision: props.websiteRevision,
      websiteTreeClean: props.websiteTreeClean,
      gsapVersion: props.gsapVersion,
      durationSeconds: measurement.durationSeconds,
      labels,
      stage: props.stage,
      phoneBreakpoint: resolvePhoneBreakpoint(stylesheet.groupPreludes, measurement.containerName),
      seed: props.seed,
      sha256: {
        "scene.js": sha256Hex(files["scene.js"]),
        "scene.html": sha256Hex(files["scene.html"]),
        "scene.css": sha256Hex(files["scene.css"]),
      },
    },
  };
}
