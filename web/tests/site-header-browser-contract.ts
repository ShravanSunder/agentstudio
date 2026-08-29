export interface SiteHeaderStableState {
  readonly anchorHeight: number;
  readonly headerHeight: number;
  readonly headerTop: number;
  readonly headerWidth: number;
  readonly scrollY: number;
  readonly visualState: "floating" | "resting";
}

export interface SiteHeaderScrollStabilityResult {
  readonly floating: SiteHeaderStableState;
  readonly headerZIndex: number;
  readonly resting: SiteHeaderStableState;
  readonly stateChangeCount: number;
  readonly frostZIndex: number;
  readonly viewport: {
    readonly height: number;
    readonly width: number;
  };
}
