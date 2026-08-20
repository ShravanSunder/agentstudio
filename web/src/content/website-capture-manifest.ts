export type WebsiteCaptureId =
  | "parallel-work"
  | "pane-drawer"
  | "quick-find"
  | "review"
  | "git-context"
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
    compositorVersion: "Peekaboo 4.0.0 full-window region capture for Quick Find",
    exportCompositor: "Sharp 0.35.3 sRGB metadata normalization",
    focalPixelPolicy:
      "Native app and sheet pixels remain unchanged; Quick Find uses the matching native window alpha boundary",
    contextualScrim: "Native Agent Studio treatment only",
    focusRail: "None",
    duplicateProductMedia: false,
  },
  captures: [
    {
      id: "parallel-work",
      assetPath: "../assets/captures/parallel-work.png",
      alternativeText:
        "Agent Studio with Codex and Claude Code working in two panes beside repository, branch, Git, activity, and recency context in All Panes.",
      processGeneration: "A",
      sourceSha256: "c5e2e3f1272c2a5ba4f75f303056ed4df60577411329abbddfaa0de2113c5660",
      normalizedMasterSha256: "17cd57e3212be296efd1470ff3e83f8d845b8aecde516ed9921f3e7a9f2455da",
      websiteAssetSha256: "17cd57e3212be296efd1470ff3e83f8d845b8aecde516ed9921f3e7a9f2455da",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 55,
    },
    {
      id: "pane-drawer",
      assetPath: "../assets/captures/pane-drawer.png",
      alternativeText:
        "Agent Studio with one compact Git-status drawer attached to the active Codex task while a second Claude pane remains visible and the global sidebar stays hidden.",
      processGeneration: "A",
      sourceSha256: "bf30f15de6c1c533db3ee9257c2b09e3d8aed9cde721c36681436c7f8ca33860",
      normalizedMasterSha256: "45bc035952b4bcc0d5784612b2fb467fdcf2473550cf10fac901474c0896b879",
      websiteAssetSha256: "45bc035952b4bcc0d5784612b2fb467fdcf2473550cf10fac901474c0896b879",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "quick-find",
      assetPath: "../assets/captures/quick-find.png",
      alternativeText:
        "Agent Studio Quick Find listing agent-studio, y-websocket, and sidebar worktree panes over Codex and Claude sessions with the global sidebar hidden.",
      processGeneration: "A",
      sourceSha256: "5e9a38172895799ae16a2ae436674c99320ebd7b63eeb29cd8cb4e5f0741913d",
      normalizedMasterSha256: "ca1f2ae0bc73a7b17d9373723eda2b419632a3fa395dbf248d728d8fa7239cde",
      websiteAssetSha256: "ca1f2ae0bc73a7b17d9373723eda2b419632a3fa395dbf248d728d8fa7239cde",
      focusRegion: null,
      focusRadiusPixels: 24,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "review",
      assetPath: "../assets/captures/review.png",
      alternativeText:
        "Agent Studio Review showing a readable unified CI workflow diff and Changed Files tree beside Claude Code in the matching worktree for pull request 313, with the global repository sidebar hidden.",
      processGeneration: "A",
      sourceSha256: "9f29a173039e04f1946523e25481f97403ff625a3f77774df4518864677655da",
      normalizedMasterSha256: "fcbb61927148a093b75cdaebae57d6f6cd329338a01e5d5d9bcfc3e21418f9ec",
      websiteAssetSha256: "fcbb61927148a093b75cdaebae57d6f6cd329338a01e5d5d9bcfc3e21418f9ec",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "git-context",
      assetPath: "../assets/captures/git-pull-request-context.png",
      alternativeText:
        "Agent Studio grouped by repository with Codex and Claude panes beside branch, changed-line, and ahead or behind Git status.",
      processGeneration: "A",
      sourceSha256: "8eab0a39bacb1f86a3e6e8f15855ca08a57f736f323ccf1c100b1bb1013b7e74",
      normalizedMasterSha256: "ca8e6f1b85fb722fedadd7020efd77a93fcdbeb0961ffb0489d1611862a753c4",
      websiteAssetSha256: "ca8e6f1b85fb722fedadd7020efd77a93fcdbeb0961ffb0489d1611862a753c4",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "persistent-before",
      assetPath: "../assets/captures/persistent-before.png",
      alternativeText:
        "Agent Studio before closing with five tabs, All Panes, a CI workflow diff in Review, and Claude Code in the matching worktree for pull request 313.",
      processGeneration: "A",
      sourceSha256: "90014a79378bbefe0432401146b57c22103b9bca8f0d05b37b83ff53015e7db5",
      normalizedMasterSha256: "67d4164fd45e4601f5d56a7de14751f7f03e91bc9ac7b6271e48b5384448d627",
      websiteAssetSha256: "67d4164fd45e4601f5d56a7de14751f7f03e91bc9ac7b6271e48b5384448d627",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "persistent-restored",
      assetPath: "../assets/captures/persistent-restored.png",
      alternativeText:
        "Agent Studio after reopening with the same five tabs, All Panes grouping, CI workflow diff, Claude Code worktree, pull request, and terminal session.",
      processGeneration: "B",
      sourceSha256: "ca86b5996a578c1f1422020bb22cbc6c7ed35df4d2dacfc544fe7dc9bd20469a",
      normalizedMasterSha256: "11817756f0e2b8254d5741ac294a7ae3dbbd852c4d14a8435fdaf6dd60f192c1",
      websiteAssetSha256: "11817756f0e2b8254d5741ac294a7ae3dbbd852c4d14a8435fdaf6dd60f192c1",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
  ],
} as const satisfies WebsiteCaptureSuite;
