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
      "FFmpeg 9.0.1 localized privacy blur and lossless phone folds; Sharp 0.35.3 sRGB conversion and phone crops",
    focalPixelPolicy:
      "Native app and sheet pixels remain unchanged except for a bounded blur over the Antigravity account email in Parallel and Drawer",
    contextualScrim: "Native Agent Studio treatment only",
    focusRail: "None",
    duplicateProductMedia: false,
  },
  captures: [
    {
      id: "parallel-work",
      assetPath: "../assets/captures/parallel-work.png",
      phoneAssetPath: "../assets/captures/parallel-work-phone.png",
      alternativeText:
        "Agent Studio All Panes with Antigravity in agent-studio on main and Codex in agent-vm on master.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "3bb2606b47aac09c038c3a1384b5677f09303968a25b3ec57dc0dd7944001c9a",
      normalizedMasterSha256: "79eae201fb1e4a145f308797aca8729a96df1011aa934bd43f10ed4817fbdec2",
      websiteAssetSha256: "79eae201fb1e4a145f308797aca8729a96df1011aa934bd43f10ed4817fbdec2",
      phoneWebsiteAssetSha256: "10862c04865b7dc686ca36c2eedfac11bc353cf2317ed20892ba5c95a21d8f4c",
      focusRegion: null,
      focusRadiusPixels: null,
      focusRail: false,
      settledAtSeconds: 55,
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
      assetPath: "../assets/captures/quick-find.png",
      phoneAssetPath: "../assets/captures/quick-find-phone.png",
      alternativeText:
        "Agent Studio Quick Find showing recent repositories and command, pane, and repository scopes with the global sidebar hidden.",
      source: {
        productRevision: "0.0.90-beta.30 (151)",
        fixtureIdentity: "owner-prepared-beta-workspace-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.beta",
        executableSha256: "2cd31b67f67ac7f8f4d17788de35c1220d205611cdc63c0da3ff535903b90a7b",
      },
      processGeneration: "A",
      sourceSha256: "f16982cc16a21acefb16a47311f89e505afd427b863af3bc63923cb1ef744cc5",
      normalizedMasterSha256: "3d5eac462f9355f4b97cf11a3892274300185b7be0d5e62f5295bacf7f59de25",
      websiteAssetSha256: "3d5eac462f9355f4b97cf11a3892274300185b7be0d5e62f5295bacf7f59de25",
      phoneWebsiteAssetSha256: "991a51e4ce862f596736451f4a3b25d0ecfb94b5e83c7887abbb95ade9bbd848",
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
        "Agent Studio Review showing a continuous AGENTS.md diff beside its Changed Files tree, with the global sidebar hidden.",
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
      phoneWebsiteAssetSha256: "a062398bb598531768de781442628ab32d2b81ed516fe0c0dc1f4e7e330df512",
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
      id: "persistent-before",
      assetPath: "../assets/captures/persistent-before.png",
      alternativeText:
        "Agent Studio before closing with five tabs, All Panes, a CI workflow diff in Review, and Claude Code in the matching worktree for pull request 313.",
      source: {
        productRevision: "2b0ff02d47b447ee67393c42b2a02a65894d3a36",
        fixtureIdentity: "h4u3-real-projects-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.debug.dh4u3",
        executableSha256: "6f53124fb6e8575e69cc0b1ce59aa1701855ae892754e72d9495eb67ce704ff4",
      },
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
      source: {
        productRevision: "2b0ff02d47b447ee67393c42b2a02a65894d3a36",
        fixtureIdentity: "h4u3-real-projects-2026-08-20",
        bundleIdentifier: "com.agentstudio.app.debug.dh4u3",
        executableSha256: "6f53124fb6e8575e69cc0b1ce59aa1701855ae892754e72d9495eb67ce704ff4",
      },
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
