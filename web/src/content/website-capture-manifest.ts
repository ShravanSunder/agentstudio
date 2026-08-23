export type WebsiteCaptureId =
  | "parallel-work"
  | "watch-folder"
  | "files"
  | "quick-find"
  | "review"
  | "sidebar-navigation"
  | "task-drawer-tools"
  | "git-context-files"
  | "layout-saved"
  | "layout-pane-zoom";

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
  readonly desktopPixelSize?: readonly [width: number, height: number];
  readonly projectionPolicy?: "full-native-window" | "purpose-crop";
  readonly phoneWebsiteAssetSha256?: string;
  readonly phonePixelSize?: readonly [width: number, height: number];
  readonly phoneFocusRegion?: NormalizedFocusRegion;
  readonly focusRegion: NormalizedFocusRegion | null;
  readonly focusRegions?: readonly NormalizedFocusRegion[];
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
    compositorVersion: "Peekaboo 4.2.2 capture; HyperFrames 0.8.9 focus-isolation export",
    exportCompositor:
      "ColorSync sRGB conversion without resizing; canonical same-geometry native alpha boundary for Parallel agents; frozen phone crops",
    focalPixelPolicy:
      "Native app and sheet RGB pixels remain unchanged after capture except for recorded privacy treatment and color-profile normalization",
    contextualScrim:
      "HyperFrames #1D2026 at 68 percent; task-drawer top-left context segment at 58 percent",
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
      id: "sidebar-navigation",
      assetPath: "../assets/captures/sidebar-navigation.png",
      phoneAssetPath: "../assets/captures/sidebar-navigation-phone.png",
      alternativeText:
        "Agent Studio's sidebar filtered to two matching worktrees, with their branch names and dirty-change badges visible.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-sidebar-navigation-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "1ea9c5625dbced00cd8412dc2df739931ef96d59dd7dcccf138eff0096f9437a",
      normalizedMasterSha256: "21d430ee065191b2b3124c654a6f1ce80dc3153572ee8a095a5c7254044b89d2",
      websiteAssetSha256: "367af61894e6f78dd2caa49c166542fe507d0e5a2c103685f52a5c76baaaa893",
      desktopPixelSize: [1740, 1088],
      projectionPolicy: "purpose-crop",
      phoneWebsiteAssetSha256: "84b793c98eee2643f7c92a16281d969234d2d0ff599ee926a5619ebf4931a506",
      phonePixelSize: [707, 560],
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 6.72,
    },
    {
      id: "task-drawer-tools",
      assetPath: "../assets/captures/task-drawer-tools.png",
      phoneAssetPath: "../assets/captures/task-drawer-tools-phone.png",
      alternativeText:
        "Agent Studio showing a Codex task with a related terminal in its attached drawer.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-task-drawer-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "99694298ec5fd3bc316c28762f4b5d978608a7e21f0411b536e3e0edf970d448",
      normalizedMasterSha256: "8d8107b7a90a45b16c4c4a91f714174d8d93cd4f2dfe545e9ca2f191f4d4d3c9",
      websiteAssetSha256: "95ddc00e1bf851159252cafac9b226708b4a493d54e3e84390f3df764942b4bd",
      desktopPixelSize: [2560, 1400],
      projectionPolicy: "purpose-crop",
      phoneWebsiteAssetSha256: "29516ee6928e4b5433297ec55702aa81c42703a5623a82a757a86fb3dd8b2243",
      phonePixelSize: [2300, 1450],
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 7.72,
    },
    {
      id: "git-context-files",
      assetPath: "../assets/captures/git-context-files.png",
      phoneAssetPath: "../assets/captures/git-context-files-phone.png",
      alternativeText:
        "Agent Studio showing a worktree and branch with PR 201 visible in its terminal.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-git-context-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "c938075251690789315fd5bc37949535a5f031aba8fb5584561b823d2aea51fd",
      normalizedMasterSha256: "c938075251690789315fd5bc37949535a5f031aba8fb5584561b823d2aea51fd",
      websiteAssetSha256: "c938075251690789315fd5bc37949535a5f031aba8fb5584561b823d2aea51fd",
      phoneWebsiteAssetSha256: "29cd68fac9c03c0b8d07164fe0e24dddfac8e3241f45605d8f6f5ab946a2603e",
      phonePixelSize: [810, 570],
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 8.72,
    },
    {
      id: "layout-saved",
      assetPath: "../assets/captures/layout-saved.png",
      phoneAssetPath: "../assets/captures/layout-saved-phone.png",
      alternativeText: "Agent Studio with the named Layout 1 active.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-layout-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "e7a928f3fbdc46514560034cc0f666b87d1dc9cc03472103de6ad7ac2585585b",
      normalizedMasterSha256: "e7a928f3fbdc46514560034cc0f666b87d1dc9cc03472103de6ad7ac2585585b",
      websiteAssetSha256: "e7a928f3fbdc46514560034cc0f666b87d1dc9cc03472103de6ad7ac2585585b",
      phoneWebsiteAssetSha256: "ea76a12ef2736858864212be3db4177814b4593438b19920fb484b615d3f8c11",
      phonePixelSize: [640, 400],
      phoneFocusRegion: { left: 0.3125, top: 0, right: 0.75, bottom: 0.2 },
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 9.72,
    },
    {
      id: "layout-pane-zoom",
      assetPath: "../assets/captures/layout-pane-zoom.png",
      phoneAssetPath: "../assets/captures/layout-pane-zoom-phone.png",
      alternativeText:
        "The same Agent Studio task in Pane Zoom with its terminal, code, and Files context filling the workspace.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-layout-2026-08-22",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "B",
      sourceSha256: "25f194ac2efdf73328b1461a8e4f9169fca9728cd2545251e6e9100b2b99af5e",
      normalizedMasterSha256: "25f194ac2efdf73328b1461a8e4f9169fca9728cd2545251e6e9100b2b99af5e",
      websiteAssetSha256: "25f194ac2efdf73328b1461a8e4f9169fca9728cd2545251e6e9100b2b99af5e",
      phoneWebsiteAssetSha256: "243b23f1fd22dad68f2481a16f945d6b1ad8c49237283c2497a74a92e0f89c92",
      phonePixelSize: [640, 400],
      phoneFocusRegion: { left: 0.3125, top: 0, right: 0.890625, bottom: 0.2 },
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 10.72,
    },
  ],
} as const satisfies WebsiteCaptureSuite;
