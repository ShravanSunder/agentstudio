// The manifest the media team pins a HyperFrames project to: which website
// revision a scene came from, how long it runs, where its labels fall, and the
// hashes of the three files it ships beside.

import { createHash } from "node:crypto";

import type { PhoneBreakpoint } from "./scene-stylesheet-model.ts";

export const sceneBundleFileNames = ["scene.js", "scene.html", "scene.css"] as const;

export type SceneBundleFileName = (typeof sceneBundleFileNames)[number];

export interface SceneBundleManifest {
  readonly schemaVersion: 1;
  readonly sceneId: string;
  /** `git rev-parse HEAD` of the website checkout that built the bundle. */
  readonly websiteRevision: string;
  /** False when `web/` had uncommitted changes, so the revision alone does not reproduce it. */
  readonly websiteTreeClean: boolean;
  /** The GSAP version the website pins; the host timeline should match it. */
  readonly gsapVersion: string;
  readonly durationSeconds: number;
  /** Timeline label name to time in seconds, in time order. */
  readonly labels: Readonly<Record<string, number>>;
  /** The app window size the recreation kit models; the scene scales to any 16:10 stage. */
  readonly stage: { readonly width: number; readonly height: number };
  /** Stages at or below this container width render the phone crop. */
  readonly phoneBreakpoint: PhoneBreakpoint;
  /** The seed the website passes to buildScene; timings above were measured with it. */
  readonly seed: number;
  readonly sha256: Readonly<Record<SceneBundleFileName, string>>;
}

export function sha256Hex(fileText: string): string {
  return createHash("sha256").update(fileText, "utf8").digest("hex");
}

export function serializeSceneBundleManifest(manifest: SceneBundleManifest): string {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}
