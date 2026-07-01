import type { BridgeViewerHydrationDiagnostics } from '../bridge-viewer-hydration-diagnostics.ts';

export type BridgeViewerBrowserFixtureClass =
	| 'small-mixed'
	| 'medium-agentstudio'
	| 'large-diffshub';

export interface FixtureTargets {
	readonly addedPath: string;
	readonly addedText: string;
	readonly docsPath: string;
	readonly docsMarkdownHeading: string;
	readonly initialPath: string;
	readonly initialText: string;
}

export interface DevServerVerificationResult {
	readonly codeViewScrollHeight: number;
	readonly codeViewScrollTop: number;
	readonly codeViewVisibleText: string;
	readonly filterBehaviorState: FilterBehaviorState | null;
	readonly gitStatusFilterMenuState: GitStatusFilterMenuState | null;
	readonly hydrationDiagnostics: BridgeViewerHydrationDiagnostics;
	readonly markdownSelectionScrollMotion: ScrollMotionProbe | null;
	readonly selectedHeaderCollapseButtonState: HeaderCollapseButtonState | null;
	readonly selectedScrollMotion: ScrollMotionProbe | null;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly topScopeState: TopScopeState | null;
	readonly workerPoolState: string | null;
}

export interface DirectMarkdownSelectionState {
	readonly initialScrollTop: number;
	readonly selectedDisplayPath: string | null;
	readonly selectedHeaderCollapseButtonState: HeaderCollapseButtonState | null;
	readonly selectedScrollTop: number;
	readonly scrollMotion: ScrollMotionProbe;
}

export interface FilterBehaviorState {
	readonly docsProjectionItemCount: number;
	readonly initialProjectionItemCount: number;
	readonly selectedPathAfterDocsFilter: string | null;
}

export interface ScrollMotionProbe {
	readonly directionChangeCount: number;
	readonly finalSampleScrollTop: number;
	readonly initialScrollTop: number;
	readonly maximumSingleFrameDelta: number;
	readonly sampleCount: number;
	readonly samples: readonly number[];
	readonly scrollClientHeight: number;
	readonly scrollHeight: number;
	readonly totalObservedDelta: number;
	readonly uniqueScrollTopCount: number;
}

export interface HeaderCollapseButtonState {
	readonly ariaExpanded: string | null;
	readonly ariaLabel: string | null;
	readonly hasBridgeHeaderKindIcon: boolean;
	readonly hasBridgeHeaderStatus: boolean;
	readonly height: number;
	readonly text: string;
	readonly topOffsetFromScrollOwner: number | null;
	readonly width: number;
}

export interface GitStatusFilterMenuState {
	readonly ariaExpanded: string | null;
	readonly checkboxItemCount: number;
	readonly hasAllStatusesMenuItem: boolean;
	readonly height: number;
	readonly optionLabels: readonly string[];
	readonly rowHeights: readonly number[];
	readonly width: number;
}

export interface TopScopeState {
	readonly activePressedCount: number;
	readonly backgroundColor: string;
	readonly buttonCount: number;
	readonly buttonFontSizes: readonly string[];
	readonly headerBackgroundColor: string;
	readonly height: number;
	readonly isSegmentedControl: boolean;
	readonly projectionButtonTestIds: readonly string[];
	readonly role: string | null;
}
