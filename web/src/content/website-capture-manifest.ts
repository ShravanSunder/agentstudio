export type WebsiteCaptureId =
  | "parallel-work"
  | "pane-drawer"
  | "quick-find"
  | "review"
  | "persistent-before"
  | "persistent-restored";

export interface NormalizedFocusRegion {
  readonly left: number;
  readonly top: number;
  readonly right: number;
  readonly bottom: number;
}

export interface WebsiteCaptureRecord {
  readonly id: WebsiteCaptureId;
  readonly assetPath: string;
  readonly alternativeText: string;
  readonly processGeneration: "A" | "B";
  readonly sourceSha256: string;
  readonly normalizedMasterSha256: string;
  readonly websiteAssetSha256: string;
  readonly focusRegion: NormalizedFocusRegion | null;
  readonly focusRadiusPixels: number | null;
  readonly focusRail: boolean;
  readonly settledAtSeconds: number;
}

export interface WebsiteCaptureSuite {
  readonly sourceRevision: string;
  readonly fixtureIdentity: string;
  readonly debugBundleIdentifier: string;
  readonly captureExecutableSha256: string;
  readonly logicalSizePoints: readonly [width: number, height: number];
  readonly pixelSize: readonly [width: number, height: number];
  readonly scale: number;
  readonly colorProfile: string;
  readonly treatment: {
    readonly renderer: "Native macOS";
    readonly compositorVersion: string;
    readonly exportCompositor: string;
    readonly focalPixelPolicy: string;
    readonly contextualScrim: string;
    readonly focusRail: string;
    readonly duplicateProductMedia: false;
  };
  readonly captures: readonly WebsiteCaptureRecord[];
}

export const websiteCaptureSuite = {
  sourceRevision: "2b0ff02d47b447ee67393c42b2a02a65894d3a36",
  fixtureIdentity: "h4u3-real-projects-2026-08-20",
  debugBundleIdentifier: "com.agentstudio.app.debug.dh4u3",
  captureExecutableSha256: "6f53124fb6e8575e69cc0b1ce59aa1701855ae892754e72d9495eb67ce704ff4",
  logicalSizePoints: [1280, 800],
  pixelSize: [2560, 1600],
  scale: 2,
  colorProfile: "sRGB IEC61966-2.1",
  treatment: {
    renderer: "Native macOS",
    compositorVersion: "FFmpeg 9.0.1 for the measured Quick Find sheet composite only",
    exportCompositor: "Sharp 0.35.3 sRGB metadata normalization",
    focalPixelPolicy: "Native app pixels remain unchanged apart from color-profile metadata",
    contextualScrim: "Native Agent Studio treatment only",
    focusRail: "None",
    duplicateProductMedia: false,
  },
  captures: [
    {
      id: "parallel-work",
      assetPath: "../assets/captures/parallel-work.png",
      alternativeText:
        "Agent Studio with two terminal panes and the All Panes sidebar showing repository, branch, Git, activity, and recency context.",
      processGeneration: "A",
      sourceSha256: "343afef132da533223a0b0ee5818e9c5bee2bc1c3d5bfb387aae54915a94e83a",
      normalizedMasterSha256: "343afef132da533223a0b0ee5818e9c5bee2bc1c3d5bfb387aae54915a94e83a",
      websiteAssetSha256: "343afef132da533223a0b0ee5818e9c5bee2bc1c3d5bfb387aae54915a94e83a",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 0.72,
    },
    {
      id: "pane-drawer",
      assetPath: "../assets/captures/pane-drawer.png",
      alternativeText:
        "Agent Studio with a Git diff summary in a drawer attached to the right terminal pane.",
      processGeneration: "A",
      sourceSha256: "295ca6f42dfb414986f2925e79563f348f1b89a74725ac4354179e8bdfb8121e",
      normalizedMasterSha256: "295ca6f42dfb414986f2925e79563f348f1b89a74725ac4354179e8bdfb8121e",
      websiteAssetSha256: "295ca6f42dfb414986f2925e79563f348f1b89a74725ac4354179e8bdfb8121e",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1.72,
    },
    {
      id: "quick-find",
      assetPath: "../assets/captures/quick-find.png",
      alternativeText:
        "Agent Studio Quick Find scoped to the agent-studio repository over a two-pane workspace.",
      processGeneration: "A",
      sourceSha256: "ae87b8655804e8f65eaf4ef13c7ab8561f9cd239fc1eac97024e9fa1d574072c",
      normalizedMasterSha256: "ae87b8655804e8f65eaf4ef13c7ab8561f9cd239fc1eac97024e9fa1d574072c",
      websiteAssetSha256: "ae87b8655804e8f65eaf4ef13c7ab8561f9cd239fc1eac97024e9fa1d574072c",
      focusRegion: null,
      focusRadiusPixels: 24,
      focusRail: false,
      settledAtSeconds: 2.72,
    },
    {
      id: "review",
      assetPath: "../assets/captures/review.png",
      alternativeText:
        "Agent Studio with a read-only Swift diff and Changed Files tree beside the matching worktree terminal.",
      processGeneration: "A",
      sourceSha256: "f5795f0e0f6cac3325af9014d29346ed3d386a636d3129e0527f0b398713a79c",
      normalizedMasterSha256: "f5795f0e0f6cac3325af9014d29346ed3d386a636d3129e0527f0b398713a79c",
      websiteAssetSha256: "f5795f0e0f6cac3325af9014d29346ed3d386a636d3129e0527f0b398713a79c",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 3.72,
    },
    {
      id: "persistent-before",
      assetPath: "../assets/captures/persistent-before.png",
      alternativeText:
        "Agent Studio before closing with five tabs, two visible terminal panes, drawer and Review entries, and the All Panes sidebar.",
      processGeneration: "A",
      sourceSha256: "f806f6e696a50def8a67ba049b9b4c505f7bd567b964263e3293ec6fce9a83c3",
      normalizedMasterSha256: "f806f6e696a50def8a67ba049b9b4c505f7bd567b964263e3293ec6fce9a83c3",
      websiteAssetSha256: "f806f6e696a50def8a67ba049b9b4c505f7bd567b964263e3293ec6fce9a83c3",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 4.72,
    },
    {
      id: "persistent-restored",
      assetPath: "../assets/captures/persistent-restored.png",
      alternativeText:
        "Agent Studio after reopening with five restored tabs, the same terminal panes, drawer and Review entries, terminal output, and sidebar grouping.",
      processGeneration: "B",
      sourceSha256: "f8a30d68d749cfc77461cea6ba98bc29e0e1f971dbc956f3b1b51be61610fae5",
      normalizedMasterSha256: "f8a30d68d749cfc77461cea6ba98bc29e0e1f971dbc956f3b1b51be61610fae5",
      websiteAssetSha256: "f8a30d68d749cfc77461cea6ba98bc29e0e1f971dbc956f3b1b51be61610fae5",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 5.72,
    },
  ],
} as const satisfies WebsiteCaptureSuite;
