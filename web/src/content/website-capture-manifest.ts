export type WebsiteCaptureId =
  | "parallel-work"
  | "watch-folder"
  | "files"
  | "pane-drawer"
  | "quick-find"
  | "review"
  | "git-context"
  | "files-review-tabs"
  | "arrangement-saved"
  | "pane-zoom"
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
  readonly phoneAssetPath?: string;
  readonly alternativeText: string;
  readonly source: {
    readonly productRevision: string;
    readonly fixtureIdentity: string;
    readonly bundleIdentifier: string;
    readonly executableSha256: string;
  };
  readonly processGeneration: "A" | "B";
  readonly sourceSha256: string;
  readonly normalizedMasterSha256: string;
  readonly websiteAssetSha256: string;
  readonly phoneWebsiteAssetSha256?: string;
  readonly focusRegion: NormalizedFocusRegion | null;
  readonly focusRadiusPixels: number | null;
  readonly focusRail: boolean;
  readonly settledAtSeconds: number;
}

export interface WebsiteCaptureSuite {
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
  logicalSizePoints: [1280, 800],
  pixelSize: [2560, 1600],
  scale: 2,
  colorProfile: "sRGB IEC61966-2.1",
  treatment: {
    renderer: "Native macOS",
    compositorVersion: "Peekaboo 4.2.2 exact-window Retina capture",
    exportCompositor:
      "ColorSync sRGB conversion without resizing; canonical same-geometry native alpha boundary for Parallel agents; frozen phone crops",
    focalPixelPolicy:
      "Native app and sheet RGB pixels remain unchanged after capture except for recorded privacy treatment and color-profile normalization",
    contextualScrim: "Native Agent Studio treatment only",
    focusRail: "None",
    duplicateProductMedia: false,
  },
  captures: [
    {
      id: "parallel-work",
      assetPath: "../assets/captures/parallel-agents.png",
      phoneAssetPath: "../assets/captures/parallel-work-phone.png",
      alternativeText:
        "Agent Studio All Panes showing active Codex and Claude Code sessions with repository, worktree, branch, and activity context.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-21",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "c50730423591eb9913f99c68d77c1d385e1b7d8d20054e45266d465f1850e99d",
      normalizedMasterSha256: "380fcc7c600cae71f4fa112b33e4f7143309f26b2980f61c9ca02eeb5c1f42e0",
      websiteAssetSha256: "380fcc7c600cae71f4fa112b33e4f7143309f26b2980f61c9ca02eeb5c1f42e0",
      phoneWebsiteAssetSha256: "19013a7de2becb288fe308770bfc360f65c483495db04d94671f685aed056cf2",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 55,
    },
    {
      id: "watch-folder",
      assetPath: "../assets/captures/watch-folder.png",
      phoneAssetPath: "../assets/captures/watch-folder-phone.png",
      alternativeText:
        "Agent Studio welcome screen explaining Watch Folder discovery beside an example repository and worktree map.",
      source: {
        productRevision: "1ab11ef1d9a28ff6cf3c9673d8ce72d15db5aa7b",
        fixtureIdentity: "website-welcome-20260821",
        bundleIdentifier: "com.agentstudio.app.debug.dnj1k",
        executableSha256: "2824226e702bbb579be3c71069000beba3babaaa7f34950ffaaf2cb4fac25778",
      },
      processGeneration: "B",
      sourceSha256: "98e937b791dcf03b81cb1b0b1aaa14c38332b0714f3f0b8a6ff7044c6dcb7d0b",
      normalizedMasterSha256: "41c3451448cb7ea3470b5aa500530d2c0dff814ac6cd863281364be416aa5bc1",
      websiteAssetSha256: "41c3451448cb7ea3470b5aa500530d2c0dff814ac6cd863281364be416aa5bc1",
      phoneWebsiteAssetSha256: "8fab3ffc081d1a1085ef40b69284fac177c09a11408406eb9b63bfea551c678e",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "files",
      assetPath: "../assets/captures/files.png",
      phoneAssetPath: "../assets/captures/files-phone.png",
      alternativeText:
        "Agent Studio Files showing a source file beside its repository tree, with Review available as the adjacent tab and the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-files-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "816a4ee88c399398b5997517d952e14d42a9d2784b7c05ac2cfccbeb0c020626",
      normalizedMasterSha256: "89def9d7bb825767fadbb2a207da6b141c940a6e1457c958a65bb8ac1a678c8b",
      websiteAssetSha256: "89def9d7bb825767fadbb2a207da6b141c940a6e1457c958a65bb8ac1a678c8b",
      phoneWebsiteAssetSha256: "f6406f4d6adf0fba141612a1456508f27b47cf3eed35c6116bb9df7880f6f7fd",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "pane-drawer",
      assetPath: "../assets/captures/pane-drawer.png",
      phoneAssetPath: "../assets/captures/pane-drawer-phone.png",
      alternativeText:
        "A Git-status drawer attached beneath Antigravity with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "937d5463f85511eccbc2c609fb9106b972f808136a8b75aee415d2a148ab14d4",
      normalizedMasterSha256: "e1bd4bc933ac4517c2d205be8b676689661f96220640d36b40858859d6ea30e5",
      websiteAssetSha256: "e1bd4bc933ac4517c2d205be8b676689661f96220640d36b40858859d6ea30e5",
      phoneWebsiteAssetSha256: "287f9cb1686f76fecbc1966fa7ae1395899edb14910a6ebd74c05c9bf6701152",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "quick-find",
      assetPath: "../assets/captures/command-bar.png",
      phoneAssetPath: "../assets/captures/command-bar-phone.png",
      alternativeText:
        "Agent Studio command bar showing recent repositories and command, pane, and repository scopes with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-21",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "9e82a1640b864b092ed762458ab426a2f47718a4620f256b015bb8fa7acd39c1",
      normalizedMasterSha256: "60f6c7613a4f6f21e0ed96fcdf7e65da2ed7ecba3679dfee7120986b0edc96bc",
      websiteAssetSha256: "60f6c7613a4f6f21e0ed96fcdf7e65da2ed7ecba3679dfee7120986b0edc96bc",
      phoneWebsiteAssetSha256: "0ac22968f4024be0483cf6dac29ea4c6044090ad3841f53bce186d15f69a7344",
      focusRegion: null,
      focusRadiusPixels: 24,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "review",
      assetPath: "../assets/captures/review.png",
      phoneAssetPath: "../assets/captures/review-phone.png",
      alternativeText:
        "Agent Studio Review showing an AGENTS.md diff and its Changed Files tree, with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "d47a107954f01c7caa1934599c1a0484e038835c5b0e6bce1ce36ec022910819",
      normalizedMasterSha256: "f7bc1eac1dfed42332ca1c556592fde6fc492c5cc10dd179c6906e53c03d670c",
      websiteAssetSha256: "f7bc1eac1dfed42332ca1c556592fde6fc492c5cc10dd179c6906e53c03d670c",
      phoneWebsiteAssetSha256: "64394dcaa32e87db5ccdee42c93726f986d7d019025c443fd89d2be9ef129f02",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "git-context",
      assetPath: "../assets/captures/git-pull-request-context.png",
      phoneAssetPath: "../assets/captures/git-pull-request-context-phone.png",
      alternativeText:
        "Agent Studio filtered to workspace-local, with PR 201 and branch status beside the By Repo sidebar.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "ead7e84a074b7e23ba5081e4db33f8658f5d9a8e8761088cf0c289daa635eca5",
      normalizedMasterSha256: "c1fde40d20129e9d7a29da4a458b8f3d5d6db7522ef704c94380e14fc8e7ea67",
      websiteAssetSha256: "c1fde40d20129e9d7a29da4a458b8f3d5d6db7522ef704c94380e14fc8e7ea67",
      phoneWebsiteAssetSha256: "e3ee77a2b8660b49d6ec6f6fd899e7fc4c8cab14a8adb54256a73fd226028ad4",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "files-review-tabs",
      assetPath: "../assets/captures/files-review-tabs.png",
      phoneAssetPath: "../assets/captures/files-review-tabs-phone.png",
      alternativeText:
        "Agent Studio with Files and Review tabs above a changed-files tree and continuous diff, with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-21",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "7023788ecebfdd6efd11f0b72747185dbf4590247686fa0d1300610e6a8fe644",
      normalizedMasterSha256: "7b30828ae58243c819bf485e4669268d71f24392c729428d9102609cc2abe214",
      websiteAssetSha256: "7b30828ae58243c819bf485e4669268d71f24392c729428d9102609cc2abe214",
      phoneWebsiteAssetSha256: "c16e2c745f578d0ad6fb5cd3a60b79600dfebbe3771584273e8d702dd4afe129",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "arrangement-saved",
      assetPath: "../assets/captures/arrangement-saved.png",
      alternativeText:
        "Agent Studio with the Parallel agents arrangement active, showing Codex and Claude Code side by side with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "3b0a01201b1b66cc8dd8205c7eefea38a4fce1ad3c633566386666347cf6f40f",
      normalizedMasterSha256: "839cad625cbf95181715b924075a2dd73615cae6b65ebb5d125c6ea0e42d96d6",
      websiteAssetSha256: "839cad625cbf95181715b924075a2dd73615cae6b65ebb5d125c6ea0e42d96d6",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "pane-zoom",
      assetPath: "../assets/captures/pane-zoom.png",
      alternativeText: "Claude Code filling the Agent Studio workspace in Pane Zoom.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "7b5ed5a79df6adcda772e92a65deb2c5e0b3397360fd8c7244556f07d9446c2f",
      normalizedMasterSha256: "e41ad06b0da16b974611469d48a7d647ab35cbb543d859fdda017398bd2e81db",
      websiteAssetSha256: "e41ad06b0da16b974611469d48a7d647ab35cbb543d859fdda017398bd2e81db",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "persistent-before",
      assetPath: "../assets/captures/persistence-claude-before.png",
      alternativeText:
        "Agent Studio before closing with All Panes, the Parallel agents arrangement, Codex, and Claude Code visible.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "f2c578f3888731018e4652653ac418e8bd70f8c72b6aaa93c5c1bf5a18c81b7b",
      normalizedMasterSha256: "8fe88d440c0ec59d031270b97c46187e7c0fc83d1156f30b98dabfc48a80585c",
      websiteAssetSha256: "8fe88d440c0ec59d031270b97c46187e7c0fc83d1156f30b98dabfc48a80585c",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
    {
      id: "persistent-restored",
      assetPath: "../assets/captures/persistence-claude-restored.png",
      alternativeText:
        "Agent Studio after reopening in the Parallel agents arrangement with All Panes, Codex, and continued Claude Code terminal output visible.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "4c84f5a68a52c7074c5c9fa084bbf589b57c7d2b69e0cacc7b97007d6443bc16",
      normalizedMasterSha256: "dc6ecb25de709cf1b86873edf467e596546437a63ac1ee7ff698b202c8f4a8e3",
      websiteAssetSha256: "dc6ecb25de709cf1b86873edf467e596546437a63ac1ee7ff698b202c8f4a8e3",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 1,
    },
  ],
} as const satisfies WebsiteCaptureSuite;
