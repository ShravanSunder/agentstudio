import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, realpath, unlink, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { chromium, type Page, type Route } from 'playwright';
import { z } from 'zod';

import { parseBridgeCoreResourceUrl } from '../src/core/resources/bridge-resource-url.ts';
import { countFlattenedWorktreeFileTreeRows } from '../src/features/worktree-file/models/worktree-file-tree-size.ts';
import { bridgeReviewPackageSchema } from '../src/foundation/review-package/bridge-review-package-schema.ts';
import {
	bridgeWorktreeDevFileContentRouteMatchesHandle,
	bridgeWorktreeDevFileContentRouteUsesOrigin,
	parseBridgeWorktreeDevReloadIntegerList,
	parseBridgeWorktreeDevReloadIntegerToken,
	parseBridgeWorktreeDevReloadStringList,
} from './bridge-worktree-dev-reload-diagnostics.ts';
import { resolveBridgeWorktreeVerifierWritePath } from './verify-bridge-viewer-worktree-dev-server-paths.ts';
import {
	buildReviewContentRouteDeltaProof,
	normalizeReviewTreeSearchQuery,
	reviewCollapseControlSatisfied,
	reviewContentRouteDeltaSatisfied,
	reviewRenderedSelectionSatisfied,
	reviewRouteCollapseControlArtifactSatisfied,
	selectVisibleReviewCollapseControlProof,
	type ReviewContentRouteDeltaProof,
	type ReviewCollapseControlProof,
	type ReviewCollapseControlCandidate,
	type ReviewRenderedSelectionSnapshot,
} from './verify-bridge-viewer-worktree-review-proof.ts';

const defaultWorktreeDevServerUrl =
	'http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree';
const repoRootPath = fileURLToPath(new URL('../..', import.meta.url));
const proofRootPath =
	process.env['AGENTSTUDIO_BRIDGE_WORKTREE_DEV_SERVER_PROOF_ROOT'] ??
	join(repoRootPath, 'tmp/bridge-viewer-worktree-dev-server');
const proofRunCreatedAtUnixMilliseconds = Date.now();
const proofRunDirectoryPath = join(
	proofRootPath,
	timestampForPath(new Date(proofRunCreatedAtUnixMilliseconds)),
);
const worktreeDevServerUrl = fileModeUrlFromWorktreeDevServerUrl(
	process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] ?? defaultWorktreeDevServerUrl,
);
const worktreeReviewDevServerUrl = reviewModeUrlFromWorktreeDevServerUrl(worktreeDevServerUrl);
const worktreeDevServerOrigin = new URL(worktreeDevServerUrl).origin;
const targetPathOverride = process.env['BRIDGE_VIEWER_WORKTREE_TARGET_PATH'] ?? null;
const execFileAsync = promisify(execFile);
const unavailableFilterFixtureRelativePath = '.github/workflows/ci.yml';
const fileToReviewHandoffFixtureRelativePath =
	'BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts';
const reviewSelectionFixtureRelativePath = 'Sources/AgentStudio/AtomRegistry.swift';
const reviewSelectionFixtureMarker = `bridge_worktree_devserver_review_selection_${proofRunCreatedAtUnixMilliseconds}`;

const bridgeWorktreeSurfaceResponseSchema = z
	.object({
		frames: z.array(z.unknown()),
		provenance: z
			.object({
				baseRef: z.string().min(1),
				scenarioName: z.literal('current-worktree'),
				worktreeRootToken: z.string().min(1),
			})
			.strict(),
		source: z
			.object({
				sourceId: z.string().min(1),
				sourceCursor: z.string().min(1),
			})
			.passthrough(),
		treeSizeFacts: z
			.object({
				pathCount: z.number().int().nonnegative().optional(),
				estimatedTotalHeightPixels: z.number().nonnegative().optional(),
				rowHeightPixels: z.number().positive(),
			})
			.passthrough(),
	})
	.strict();

const worktreeFileDescriptorFrameSchema = z
	.object({
		frameKind: z.literal('worktree.fileDescriptor'),
		descriptor: z
			.object({
				path: z.string().min(1),
				contentHandle: z.string().min(1),
				contentHash: z.string().min(1).optional(),
				contentDescriptor: z
					.object({
						descriptor: z
							.object({
								resourceUrl: z.string().min(1),
							})
							.passthrough(),
					})
					.passthrough(),
			})
			.passthrough(),
	})
	.passthrough();

const worktreeReviewPackageRouteResponseSchema = z
	.object({
		reviewPackage: bridgeReviewPackageSchema,
	})
	.strict();

type WorktreeFileDescriptor = z.infer<typeof worktreeFileDescriptorFrameSchema>['descriptor'];
type WorktreeFileTreeExtentSource = 'localProjection' | 'providerFacts';

interface WorktreeDevServerVerificationResult {
	readonly browserProof: WorktreeDevServerBrowserProof;
	readonly descriptorCount: number;
	readonly frameCount: number;
	readonly firstLoadContentState: string | null;
	readonly firstLoadDisplayPath: string | null;
	readonly firstLoadLineCount: number;
	readonly observedLocationHref: string;
	readonly observedPageUrl: string;
	readonly packageForbiddenTextAbsent: boolean;
	readonly proofArtifactPath: string;
	readonly scenarioName: string;
	readonly scrollExtentCanary: WorktreeFileScrollExtentCanary;
	readonly selectedCharacterCount: number;
	readonly selectedContentSemanticProof: WorktreeFileSelectedContentSemanticProof;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly screenshotPaths: WorktreeDevServerScreenshotPaths;
	readonly sourceBaseRef: string;
	readonly sourceCursor: string;
	readonly sourceId: string;
	readonly sourceScenarioName: string;
	readonly worktreeRootToken: string;
	readonly splitResetReplacementProof: WorktreeFileSplitResetReplacementProof;
	readonly staleRefreshProof: WorktreeFileStaleRefreshProof;
	readonly targetPath: string;
	readonly treePathCount: number | null;
	readonly treeTotalSizePixels: number | null;
	readonly treeTotalSizeSource: WorktreeFileTreeExtentSource | null;
	readonly positiveAssertions: readonly string[];
	readonly negativeAssertions: readonly string[];
	readonly productControlsProof: WorktreeFileProductControlsProof;
	readonly fileToReviewHandoffProof: WorktreeFileToReviewHandoffProof;
	readonly reviewFileTargetRouteProof: WorktreeReviewFileTargetRouteProof;
	readonly reviewRouteProof: WorktreeReviewRouteProof;
	readonly sharedShellProof: WorktreeFileSharedShellProof;
	readonly selectedContentRouteProof: WorktreeFileSelectedContentRouteProof;
	readonly substituteGuardProof: WorktreeFileSubstituteGuardProof;
	readonly visibleAppProof: WorktreeFileVisibleAppProof;
}

interface WorktreeDevServerBrowserProof {
	readonly browserName: string;
	readonly browserVersion: string;
	readonly headless: boolean;
	readonly viewportHeight: number;
	readonly viewportWidth: number;
}

interface WorktreeDevServerScreenshotPaths {
	readonly ready: string;
	readonly review: string;
	readonly reviewFileTarget: string;
	readonly search: string;
	readonly stale: string;
}

interface WorktreeFileStaleRefreshProof {
	readonly failedRefreshReturnedStale: boolean;
	readonly foreignContentRouteHitCount: number;
	readonly foreignContentRouteHitUrls: readonly string[];
	readonly initialContentStillVisibleWhileStale: boolean;
	readonly proofPath: string;
	readonly refreshFetchHitsAfterFirstClick: number;
	readonly refreshFetchHitsAfterSecondClick: number;
	readonly refreshFetchHitsBeforeClick: number;
	readonly refreshEnteredRefreshing: boolean;
	readonly refreshReturnedReady: boolean;
	readonly refreshedContentVisible: boolean;
	readonly staleContentState: string | null;
	readonly staleMessageRect: WorktreeFileVisibleBox;
	readonly staleMessageVisible: boolean;
	readonly staleScreenshotPath: string;
}

interface WorktreeFileSplitResetReplacementProof {
	readonly devReloadFrameCount: number;
	readonly devReloadFrameGenerations: readonly number[];
	readonly devReloadFrameKinds: readonly string[];
	readonly devReloadFrameSequences: readonly number[];
	readonly devReloadFrameStreamIds: readonly string[];
	readonly devReloadRequest: string | null;
	readonly devReloadSourceCursor: string | null;
	readonly devReloadStatus: string | null;
	readonly foreignContentRouteHitCount: number;
	readonly foreignContentRouteHitUrls: readonly string[];
	readonly initialContentStillVisibleWhileStale: boolean;
	readonly oldContentHandle: string;
	readonly postRefreshContentRouteHitCount: number;
	readonly postReplacementContentRouteHitCount: number;
	readonly preDispatchContentRouteHitCount: number;
	readonly proofPath: string;
	readonly refreshDisabledAtFirstStale: boolean;
	readonly refreshEnabledAfterReplacement: boolean;
	readonly refreshedContentVisible: boolean;
	readonly replacementContentHandle: string;
	readonly replacementContentHash: string | null;
	readonly replacementContentRouteHitCount: number;
	readonly replacementSourceCursor: string;
	readonly selectedContentStateAfterReset: string | null;
	readonly staleMessageVisible: boolean;
}

interface WorktreeFileContentRouteProbe {
	readonly dispose: () => Promise<void>;
	readonly foreignHitCount: () => number;
	readonly foreignHitUrls: () => readonly string[];
	readonly hitCount: () => number;
	readonly hitUrls: () => readonly string[];
}

interface WorktreeDevReloadProof {
	readonly frameCount: number;
	readonly frameGenerations: readonly number[];
	readonly frameKinds: readonly string[];
	readonly frameSequences: readonly number[];
	readonly frameStreamIds: readonly string[];
	readonly request: string | null;
	readonly sourceCursor: string | null;
	readonly status: string | null;
}

interface WorktreeFileSelectedContentRouteProof {
	readonly expectedContentHandle: string;
	readonly foreignHitCount: number;
	readonly foreignHitUrls: readonly string[];
	readonly hitCount: number;
	readonly hitUrls: readonly string[];
	readonly selectedResourceUrlContainsHandle: boolean;
	readonly selectedResourceUrlUsesDevServerFrontDoor: boolean;
}

interface WorktreeFileSelectedContentSemanticProof {
	readonly expectedContentHash: string;
	readonly expectedContentHandle: string;
	readonly expectedDisplayPath: string;
	readonly observedDisplayPath: string | null;
	readonly observedLineCount: number;
	readonly renderedTextHash: string;
	readonly renderedTextIncludesExpectedContent: boolean;
}

interface WorktreeFileControlsStateSnapshot {
	readonly filterMenuText: string | null;
	readonly filterStatusText: string | null;
	readonly regexPressed: string | null;
	readonly searchValue: string | null;
}

interface WorktreeFileUnavailableOpenProof {
	readonly contentRouteHitCount: number;
	readonly expectedContentHandle: string;
	readonly foreignContentRouteHitCount: number;
	readonly foreignContentRouteHitUrls: readonly string[];
	readonly openedPath: string;
	readonly selectedContentState: string | null;
	readonly selectedLineCount: number;
}

interface WorktreeFileSearchChromeProof {
	readonly regexToggleFontSize: string;
	readonly regexToggleHeight: number;
	readonly searchInputClassName: string;
	readonly searchInputContainedInRail: boolean;
	readonly searchInputFontSize: string;
	readonly searchInputHeight: number;
	readonly searchInputLeft: number;
	readonly searchInputRight: number;
	readonly searchRailLeft: number;
	readonly searchRailRight: number;
	readonly searchToggleFontSize: string;
	readonly searchToggleHeight: number;
}

interface WorktreeFileProductControlsProof {
	readonly allFilterVisibleCount: number;
	readonly allRenderedPathSample: readonly string[];
	readonly allTreeSizePixels: number | null;
	readonly allTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly expectedFetchableTreeSizePixels: number | null;
	readonly expectedInvalidRegexTreeSizePixels: number;
	readonly expectedRegexTreeSizePixels: number;
	readonly expectedSearchTreeSizePixels: number;
	readonly expectedUnavailableTreeSizePixels: number;
	readonly fetchableFilterActive: boolean;
	readonly fetchableFilterVisibleCount: number;
	readonly fetchableRenderedPathSample: readonly string[];
	readonly fetchableTreeSizePixels: number | null;
	readonly fetchableTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly expectedFetchableFilterCount: number;
	readonly expectedUnavailableFilterCount: number;
	readonly expectedUnavailablePath: string;
	readonly initialVisibleCount: number;
	readonly initialRenderedPathSample: readonly string[];
	readonly initialTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly invalidRegexModeActive: boolean;
	readonly invalidRegexRenderedPathSample: readonly string[];
	readonly invalidRegexStatusText: string;
	readonly invalidRegexTreeSizePixels: number | null;
	readonly invalidRegexTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly regexModeActive: boolean;
	readonly regexVisibleCount: number;
	readonly regexRenderedPathSample: readonly string[];
	readonly regexTreeSizePixels: number | null;
	readonly regexTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly searchScreenshotPath: string;
	readonly searchChromeProof: WorktreeFileSearchChromeProof;
	readonly searchResultIncludesTarget: boolean;
	readonly searchRenderedPathSample: readonly string[];
	readonly searchStatusText: string;
	readonly searchTreeSizePixels: number | null;
	readonly searchTreeSizeSource: WorktreeFileTreeExtentSource | null;
	readonly searchVisibleCount: number;
	readonly targetPath: string;
	readonly totalDescriptorCount: number;
	readonly unavailableFilterActive: boolean;
	readonly unavailableFilterVisibleCount: number;
	readonly unavailableOpenProof: WorktreeFileUnavailableOpenProof;
	readonly unavailableRenderedPathSample: readonly string[];
	readonly unavailableTreeSizePixels: number | null;
	readonly unavailableTreeSizeSource: WorktreeFileTreeExtentSource | null;
}

interface WorktreeFileSharedShellProof {
	readonly appOwner: string | null;
	readonly appRootCount: number;
	readonly appRootOwnsCenterPoint: boolean;
	readonly codeCanvasCount: number;
	readonly codeCanvasOwnsCenterPoint: boolean;
	readonly codeOwner: string | null;
	readonly codeViewOverflow: string | null;
	readonly contentPaneStartsBelowTopbar: boolean;
	readonly contentHeaderAndRailToolbarTopAligned: boolean;
	readonly contentHeaderBackground: string;
	readonly contentHeaderMatchesRailToolbarBackground: boolean;
	readonly contentHeaderHeight: number;
	readonly contentHeaderMatchesRailToolbarHeight: boolean;
	readonly contentTopbarCount: number;
	readonly contentTopbarOwnsCenterPoint: boolean;
	readonly contentTopbarStopsBeforeSidebar: boolean;
	readonly contentTopbarVisible: boolean;
	readonly contextFileButtonHeight: number;
	readonly contextReviewButtonHeight: number;
	readonly contextSegmentMatchesRailButtonHeight: boolean;
	readonly contextSwitcherHeight: number;
	readonly contentTitleText: string;
	readonly contextSwitcherInsideContentTopbar: boolean;
	readonly fileContextButtonSelected: string | null;
	readonly hasPierreTreeShadowRoot: boolean;
	readonly modeHostActive: string | null;
	readonly modeHostCount: number;
	readonly modeHostParentIsSharedRoot: boolean;
	readonly rootVisible: boolean;
	readonly railButtonHeightsMatch: boolean;
	readonly railFilterButtonHeight: number;
	readonly railOpenReviewButtonHeight: number;
	readonly railSearchButtonHeight: number;
	readonly railToolbarBackground: string;
	readonly railToolbarBackgroundIsOpaque: boolean;
	readonly railToolbarHeight: number;
	readonly reviewContextButtonSelected: string | null;
	readonly sharedShellMode: string | null;
	readonly sharedShellOwner: string | null;
	readonly shellCount: number;
	readonly shellOwnsCenterPoint: boolean;
	readonly shellParentIsModeHost: boolean;
	readonly shellOwner: string | null;
	readonly sidebarCount: number;
	readonly sidebarIsRight: boolean;
	readonly sidebarOwnsCenterPoint: boolean;
	readonly sidebarPosition: string | null;
	readonly sidebarStartsAtContentTopbar: boolean;
	readonly shikiRendering: string | null;
	readonly treeOwner: string | null;
	readonly workerRequestedState: string | null;
	readonly workerDiagnosticFileSuccessCount: number;
	readonly workerDiagnosticFileSuccessCountBeforeTargetSelection: number;
	readonly workerDiagnosticLastFileSuccessCacheKey: string | null;
	readonly workerDiagnosticLastSuccessRequestType: string | null;
	readonly workerPoolFileCacheSize: number;
	readonly workerPoolManagerState: string | null;
	readonly workerPoolState: string | null;
	readonly codeViewThemeState: string | null;
}

interface WorktreeFileSubstituteGuardProof {
	readonly reviewEmptyShellCount: number;
	readonly standaloneWorktreeFileAppCount: number;
}

interface WorktreeReviewRouteProof {
	readonly appOwner: string | null;
	readonly appRootCount: number;
	readonly appRootVisible: boolean;
	readonly fileContextButtonSelected: string | null;
	readonly fileViewerCodeCanvasCount: number;
	readonly fileViewerShellCount: number;
	readonly fileViewerSidebarCount: number;
	readonly locationHref: string;
	readonly pageUrl: string;
	readonly reviewContentHeaderHeight: number;
	readonly reviewCanvasCount: number;
	readonly reviewCodeScrollCount: number;
	readonly reviewContextButtonSelected: string | null;
	readonly reviewCollapseControlProof: ReviewCollapseControlProof;
	readonly reviewContentRouteHitCount: number;
	readonly reviewContentRouteHitUrls: readonly string[];
	readonly reviewEmptyShellCount: number;
	readonly reviewHeaderMatchesRailToolbarHeight: boolean;
	readonly reviewPackageRouteHitCount: number;
	readonly reviewPackageRouteHitUrls: readonly string[];
	readonly reviewPackageShellCount: number;
	readonly reviewRailToolbarHeight: number;
	readonly reviewRailToolbarUsesSharedAttr: boolean;
	readonly reviewRenderedSelectionProof: ReviewRenderedSelectionSnapshot;
	readonly reviewSelectionContentRouteHitCount: number;
	readonly reviewSelectionPostClickContentRouteProof: ReviewContentRouteDeltaProof;
	readonly reviewSelectionProof: ReviewTreeSearchClickProof;
	readonly reviewSelectionSelectedContentState: string | null;
	readonly reviewSelectionSelectedDisplayPath: string | null;
	readonly reviewSelectedContentState: string | null;
	readonly reviewSelectedDisplayPath: string | null;
	readonly screenshotPath: string;
	readonly sharedShellMode: string | null;
	readonly sharedShellOwner: string | null;
	readonly standaloneWorktreeFileAppCount: number;
}

interface ReviewTreeSearchClickProof {
	readonly clickedRowItemPath: string | null;
	readonly clickedRowItemType: string | null;
	readonly clickedRowVisible: boolean;
	readonly searchInputValue: string | null;
	readonly searchOpened: boolean;
	readonly selectionMethod: 'playwright-review-tree-search-click';
	readonly targetPath: string;
}

interface WorktreeReviewFileTargetRouteProof {
	readonly appOwner: string | null;
	readonly expectedDisplayPath: string;
	readonly expectedReviewItemId: string;
	readonly expectedVersion: 'base' | 'current' | 'head';
	readonly locationHref: string;
	readonly pageUrl: string;
	readonly reviewContentHeaderHeight: number;
	readonly reviewContentRouteHitCount: number;
	readonly reviewContentRouteHitUrls: readonly string[];
	readonly reviewHeaderMatchesRailToolbarHeight: boolean;
	readonly reviewPackageRouteHitCount: number;
	readonly reviewRailToolbarHeight: number;
	readonly reviewRailToolbarUsesSharedAttr: boolean;
	readonly screenshotPath: string;
	readonly selectedCodeViewOverflow: string | null;
	readonly selectedContentRoleCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedItemId: string | null;
	readonly selectedMaterializedFileLineCount: number;
	readonly selectedMaterializedItemType: string | null;
	readonly sharedShellMode: string | null;
	readonly sharedShellOwner: string | null;
	readonly standaloneWorktreeFileAppCount: number;
}

interface WorktreeFileToReviewHandoffProof {
	readonly appRootCount: number;
	readonly appOwner: string | null;
	readonly beforeLocationHref: string;
	readonly afterLocationHref: string;
	readonly expectedDisplayPath: string;
	readonly expectedReviewItemId: string;
	readonly fileContextButtonSelectedAfterSwitch: string | null;
	readonly fileModeHostHiddenAfterSwitch: boolean;
	readonly fileModeHostHiddenAfterReturnToFile: boolean;
	readonly fileModeHostHiddenAfterReturnToReview: boolean;
	readonly fileModeHostActiveAfterReturnToFile: string | null;
	readonly fileModeHostActiveAfterReturnToReview: string | null;
	readonly fileViewerShellCountAfterSwitch: number;
	readonly fileViewerShellHiddenAfterSwitch: boolean;
	readonly fileViewerOpenLoadTelemetry: WorktreeFileOpenLoadTelemetryProof;
	readonly fileViewerSelectedPathAfterReturnToFile: string | null;
	readonly fileViewerSelectedPathAfterSwitch: string | null;
	readonly reviewContentRouteHitCount: number;
	readonly reviewContentRouteHitUrls: readonly string[];
	readonly reviewContextButtonSelectedAfterSwitch: string | null;
	readonly reviewContextButtonSelectedAfterReturnToReview: string | null;
	readonly reviewModeAfterReturnToFile: string | null;
	readonly reviewModeAfterReturnToReview: string | null;
	readonly reviewPackageRouteHitCount: number;
	readonly reviewSelectedDisplayPathAfterReturnToReview: string | null;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedItemId: string | null;
	readonly selectedMaterializedFileLineCount: number;
	readonly selectedMaterializedItemType: string | null;
	readonly sharedShellMode: string | null;
	readonly sharedShellOwner: string | null;
	readonly standaloneWorktreeFileAppCount: number;
}

interface WorktreeFileOpenLoadTelemetryProof {
	readonly disposition: string | null;
	readonly durationMilliseconds: number | null;
	readonly estimatedBytes: number | null;
	readonly executorInFlightCountAfter: number | null;
	readonly executorInFlightCountBefore: number | null;
	readonly executorQueuedLoadCountAfter: number | null;
	readonly executorQueuedLoadCountBefore: number | null;
	readonly lane: string | null;
	readonly schedulerQueuedIntentCountAfter: number | null;
	readonly schedulerQueuedIntentCountBefore: number | null;
}

interface ReviewRouteProbe {
	readonly contentHitCount: () => number;
	readonly contentHitUrls: () => readonly string[];
	readonly dispose: () => Promise<void>;
	readonly packageHitCount: () => number;
	readonly packageHitUrls: () => readonly string[];
}

interface WorktreeFileVisibleAppProof {
	readonly appRootRect: WorktreeFileVisibleRect;
	readonly contentPaneRect: WorktreeFileVisibleRect;
	readonly contentVisibleLineCount: number;
	readonly cssLayoutApplied: boolean;
	readonly filterMenuCount: number;
	readonly filterCountMeaningfullyVisible: boolean;
	readonly filterCountText: string;
	readonly forbiddenTextAbsentOutsideIntentionalUi: boolean;
	readonly regexToggleCount: number;
	readonly sourceProvenanceMeaningfullyVisible: boolean;
	readonly sourceProvenanceText: string;
	readonly sampledTreeRowCount: number;
	readonly sampledTreeRowsHaveDistinctVerticalPositions: boolean;
	readonly searchControlCount: number;
	readonly searchInputCount: number;
	readonly sharedRailToolbarCount: number;
	readonly sharedRailToolbarUsesSharedAttr: boolean;
	readonly sourceBaseRef: string | null;
	readonly sourceCursor: string | null;
	readonly sourceId: string | null;
	readonly sourceScenarioName: string | null;
	readonly sourceState: string | null;
	readonly treePaneRect: WorktreeFileVisibleRect;
	readonly worktreeRootToken: string | null;
}

interface WorktreeFileVisibleRect {
	readonly height: number;
	readonly width: number;
}

interface WorktreeFileVisibleBox extends WorktreeFileVisibleRect {
	readonly x: number;
	readonly y: number;
}

interface WorktreeRenderedContentState {
	readonly selectedCharacterCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly selectedText: string;
	readonly treeTotalSizePixels: number | null;
	readonly treeTotalSizeSource: WorktreeFileTreeExtentSource | null;
}

interface WorktreeVerifierBrowserHelpers {
	readonly getBridgeFileViewerRenderedCodeLineCount: () => number;
	readonly getBridgeFileViewerRenderedCodeText: () => string;
	readonly getBridgeFileViewerScrollableContent: () => HTMLElement | null;
	readonly getPierreFileTreeItem: (path: string) => HTMLElement | null;
	readonly getPierreFileTreeItems: () => HTMLElement[];
	readonly getPierreFileTreeScrollElement: () => HTMLElement | null;
}

declare global {
	interface Window {
		readonly bridgeWorktreeVerifier: WorktreeVerifierBrowserHelpers;
		bridgeWorktreeVerifierLastTreeAnchorSignature?: string;
		bridgeWorktreeVerifierStableTreeAnchorFrames?: number;
	}
}

interface WorktreeFileScrollExtentCanary {
	readonly contentDeclaredTotalSizePixelsAfterReady: number | null;
	readonly contentDeclaredTotalSizePixelsAfterSelection: number | null;
	readonly contentHeightDeltaPixels: number;
	readonly contentScrollClientHeightAfterReady: number;
	readonly contentScrollClientHeightAfterSelection: number;
	readonly contentScrollHeightAfterReady: number;
	readonly contentScrollHeightAfterSelection: number;
	readonly contentScrollTopAfterReady: number;
	readonly contentScrollTopAfterSelection: number;
	readonly contentScrollTopDeltaPixels: number;
	readonly exactSizeTolerancePass: boolean;
	readonly stableAnchorPass: boolean;
	readonly stableAnchorReadout: WorktreeFileScrollExtentReadout;
	readonly selectedAnchorPath: string;
	readonly treeAnchorReadout: WorktreeFileTreeAnchorReadout;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeDeclaredTotalSizeSource: WorktreeFileTreeExtentSource | null;
	readonly treeHeightDeltaPixels: number;
	readonly treeScrollClientHeightAfterReady: number;
	readonly treeScrollHeightAfterReady: number;
	readonly treeScrollHeightBeforeSelection: number;
	readonly treeScrollTopAfterReady: number;
	readonly treeScrollTopBeforeSelection: number;
}

interface WorktreeFileTreeAnchorReadout {
	readonly anchorItemId: string;
	readonly anchorOffsetAfterReady: number;
	readonly anchorOffsetBeforeSelection: number;
	readonly measuredItemIdsAfterReady: readonly string[];
	readonly measuredItemIdsBeforeSelection: readonly string[];
	readonly scrollTopAfterReady: number;
	readonly scrollTopBeforeSelection: number;
	readonly visibleRangeAfterReady: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
	readonly visibleRangeBeforeSelection: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileTreeAnchorSnapshot {
	readonly anchorItemId: string;
	readonly anchorOffset: number;
	readonly measuredItemIds: readonly string[];
	readonly scrollTop: number;
	readonly visibleRange: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileScrollExtentReadout {
	readonly anchorItemId: string;
	readonly anchorOffset: number;
	readonly measuredItemIds: readonly string[];
	readonly reconciliationReason: 'exactLineCount';
	readonly scrollHeightAfter: number;
	readonly scrollHeightBefore: number;
	readonly scrollTopAfter: number;
	readonly scrollTopBefore: number;
	readonly scrollTopDeltaPixels: number;
	readonly totalContentHeightAfter: number | null;
	readonly totalContentHeightBefore: number | null;
	readonly virtualizerTotalSizeAfter: number | null;
	readonly virtualizerTotalSizeBefore: number | null;
	readonly visibleRange: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileScrollExtentSnapshot {
	readonly contentDeclaredTotalSizePixels: number | null;
	readonly contentScrollClientHeight: number;
	readonly contentScrollHeight: number;
	readonly contentScrollTop: number;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeDeclaredTotalSizeSource: WorktreeFileTreeExtentSource | null;
	readonly treeScrollClientHeight: number;
	readonly treeScrollHeight: number;
	readonly treeScrollTop: number;
}

const defaultFileLineHeightPixels = 20;
const bridgeFileViewerTreeRowHeightPixels = 24;

const browser = await chromium.launch({ headless: true });

try {
	const result = await verifyWorktreeDevServer();
	const proofArtifactPath = await writeWorktreeDevServerProofArtifact(result);
	console.log(JSON.stringify(worktreeDevServerConsoleProof(result, proofArtifactPath), null, 2));
} finally {
	await browser.close();
}

async function verifyWorktreeDevServer(): Promise<WorktreeDevServerVerificationResult> {
	const page = await makeVerificationPage();
	let fileToReviewHandoffFixture: WorktreeFileModifiedFixture | null = null;
	let unavailableFilterFixture: WorktreeFileDeletedUnavailableFixture | null = null;
	let reviewSelectionFixture: WorktreeFileModifiedFixture | null = null;
	let staleRefreshFixture: WorktreeFileStaleRefreshFixture | null = null;
	let splitResetFixture: WorktreeFileStaleRefreshFixture | null = null;
	try {
		unavailableFilterFixture = await worktreeFileDeletedUnavailableFixture();
		fileToReviewHandoffFixture = await worktreeFileModifiedFixture({
			relativePath: fileToReviewHandoffFixtureRelativePath,
			tag: 'file_to_review_handoff',
		});
		reviewSelectionFixture = await worktreeFileModifiedFixture({
			relativePath: reviewSelectionFixtureRelativePath,
			tag: 'review_selection',
		});
		const surface = await fetchWorktreeSurface();
		const expectedWorktreeRootToken = await bridgeWorktreeDevRootTokenForPath(repoRootPath);
		if (surface.provenance.worktreeRootToken !== expectedWorktreeRootToken) {
			throw new Error(
				`Expected current checkout worktree token ${expectedWorktreeRootToken}, got ${surface.provenance.worktreeRootToken}`,
			);
		}
		const descriptors = worktreeFileDescriptors(surface.frames);
		const initialDescriptor = firstFetchableDescriptor(descriptors);
		const targetDescriptor = resolveTargetDescriptor(descriptors);
		const initialContent = await fetchWorktreeFileContent(initialDescriptor);
		const content = await fetchWorktreeFileContent(targetDescriptor);
		const staleRefreshDescriptor = resolveStaleRefreshDescriptor({
			descriptors,
			excludedPaths: new Set([initialDescriptor.path, targetDescriptor.path]),
		});
		const splitResetDescriptor = resolveStaleRefreshDescriptor({
			descriptors,
			excludedPaths: new Set([
				initialDescriptor.path,
				targetDescriptor.path,
				staleRefreshDescriptor.path,
			]),
		});
		const staleRefreshInitialContent = await fetchWorktreeFileContent(staleRefreshDescriptor);
		const splitResetInitialContent = await fetchWorktreeFileContent(splitResetDescriptor);
		staleRefreshFixture = await worktreeFileStaleRefreshFixture({
			descriptor: staleRefreshDescriptor,
			initialContent: staleRefreshInitialContent,
		});
		splitResetFixture = await worktreeFileStaleRefreshFixture({
			descriptor: splitResetDescriptor,
			initialContent: splitResetInitialContent,
		});
		const surfaceText = JSON.stringify(surface);
		if (
			content.length > 0 &&
			surfaceText.includes(content.slice(0, Math.min(80, content.length)))
		) {
			throw new Error('Expected Worktree/File surface metadata to omit file body content');
		}
		const reviewRouteProof = await verifyWorktreeReviewRoute();
		const reviewFileTargetRouteProof = await verifyWorktreeReviewFileTargetRoute();
		const fileToReviewHandoffProof = await verifyWorktreeFileToReviewHandoff();
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', { timeout: 30_000 });
		const observedRoute = await assertObservedWorktreeDevServerUrl(page);
		const substituteGuardProof = await assertNoStandaloneWorktreeFileApp(page);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			initialDescriptor.path,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		const firstLoadRendered = await readWorktreeRenderedContentState(page);
		assertRenderedWorktreeContent({
			content: initialContent,
			label: 'first-load Worktree/File content',
			rendered: firstLoadRendered,
			targetPath: initialDescriptor.path,
		});
		const contentRouteGate = makeDeferred<void>();
		const contentRouteProbe = await installFileContentRouteGate({ gate: contentRouteGate, page });
		await scrollTreeToFilePath(page, targetDescriptor.path);
		await waitForPierreFileTreeAnchorSettled(page, targetDescriptor.path);
		const scrollExtentBeforeSelection = await readWorktreeFileScrollExtentSnapshot(page);
		const treeAnchorBeforeSelection = await readWorktreeFileTreeAnchorSnapshot(
			page,
			targetDescriptor.path,
		);
		await clickWorktreeFilePath(page, targetDescriptor.path);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			targetDescriptor.path,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'loading',
			{ timeout: 10_000 },
		);
		await scrollContentPaneToNonzeroOffset(page);
		const scrollExtentAfterSelection = await readWorktreeFileScrollExtentSnapshot(page);
		const workerFileSuccessCountBeforeTargetSelection =
			await readBridgePierreWorkerFileSuccessCount(page);
		contentRouteGate.resolve();
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		await waitForBridgePierreWorkerFileSuccessCountAbove({
			page,
			previousFileSuccessCount: workerFileSuccessCountBeforeTargetSelection,
		});
		const selectedContentRouteProof = assertSelectedContentRouteProof({
			expectedContentHandle: targetDescriptor.contentHandle,
			probe: contentRouteProbe,
		});
		await contentRouteProbe.dispose();
		const scrollExtentAfterReady = await readWorktreeFileScrollExtentSnapshot(page);
		await waitForPierreFileTreeAnchorSettled(page, targetDescriptor.path);
		const treeAnchorAfterReady = await readWorktreeFileTreeAnchorSnapshot(
			page,
			targetDescriptor.path,
		);
		const rendered = await readWorktreeRenderedContentState(page);
		assertRenderedWorktreeContent({
			content,
			label: 'selected Worktree/File content',
			rendered,
			targetPath: targetDescriptor.path,
		});
		const selectedContentSemanticProof: WorktreeFileSelectedContentSemanticProof = {
			expectedContentHandle: targetDescriptor.contentHandle,
			expectedContentHash: hashText(content),
			expectedDisplayPath: targetDescriptor.path,
			observedDisplayPath: rendered.selectedDisplayPath,
			observedLineCount: rendered.selectedLineCount,
			renderedTextHash: hashText(rendered.selectedText),
			renderedTextIncludesExpectedContent: renderedTextIncludesContent(
				rendered.selectedText,
				content,
			),
		};
		const { selectedText: _selectedText, ...renderedResult }: WorktreeRenderedContentState =
			rendered;
		if (rendered.treeTotalSizePixels === null || rendered.treeTotalSizePixels <= 0) {
			throw new Error('Expected Worktree/File tree extent to be reserved from provider facts');
		}
		if (rendered.treeTotalSizeSource !== 'providerFacts') {
			throw new Error(
				`Expected Worktree/File tree extent source to be providerFacts, got ${rendered.treeTotalSizeSource ?? 'none'}`,
			);
		}
		assertWorktreeTreeExtentMatchesSurfaceFacts({
			renderedTreeTotalSizePixels: rendered.treeTotalSizePixels,
			surfaceTreeSizeFacts: surface.treeSizeFacts,
		});
		const sharedShellProof = await assertSharedBridgeFileViewerShell({
			page,
			targetDescriptor,
			workerFileSuccessCountBeforeTargetSelection,
		});
		const visibleAppProof = await readWorktreeFileVisibleAppProof(page);
		assertWorktreeFileVisibleAppProof({
			expectedSourceBaseRef: surface.provenance.baseRef,
			expectedSourceCursor: surface.source.sourceCursor,
			expectedSourceId: surface.source.sourceId,
			expectedSourceScenarioName: surface.provenance.scenarioName,
			expectedWorktreeRootToken,
			proof: visibleAppProof,
		});
		const readyScreenshotPath = await captureWorktreeDevServerScreenshot({
			name: 'worktree-file-ready.png',
			page,
		});
		const productControlsProof = await verifyWorktreeFileProductControls({
			descriptors,
			page,
			targetPath: targetDescriptor.path,
		});
		const splitResetReplacementProof = await verifyWorktreeFileSplitResetReplacement({
			descriptor: splitResetDescriptor,
			fixture: splitResetFixture,
			page,
		});
		await reloadWorktreeDevServerPage(page);
		const staleRefreshProof = await verifyWorktreeFileStaleRefresh({
			descriptor: staleRefreshDescriptor,
			fixture: staleRefreshFixture,
			page,
		});
		const scrollExtentCanary = makeScrollExtentCanary({
			afterReady: scrollExtentAfterReady,
			afterSelection: scrollExtentAfterSelection,
			beforeSelection: scrollExtentBeforeSelection,
			selectedAnchorPath: targetDescriptor.path,
			treeAnchorAfterReady,
			treeAnchorBeforeSelection,
		});
		assertWorktreeScrollExtentCanary(scrollExtentCanary);
		return {
			...renderedResult,
			browserProof: await readBrowserProof(page),
			descriptorCount: descriptors.length,
			firstLoadContentState: firstLoadRendered.selectedContentState,
			firstLoadDisplayPath: firstLoadRendered.selectedDisplayPath,
			firstLoadLineCount: firstLoadRendered.selectedLineCount,
			frameCount: surface.frames.length,
			observedLocationHref: observedRoute.locationHref,
			observedPageUrl: observedRoute.pageUrl,
			packageForbiddenTextAbsent: visibleAppProof.forbiddenTextAbsentOutsideIntentionalUi,
			positiveAssertions: [
				'shared BridgeViewer FileViewer shell rendered',
				'FileViewer opens selected file target in ReviewViewer without page navigation',
				'Pierre FileTree rendered in right rail',
				'Pierre CodeView file canvas rendered on left',
				'Shiki/Pierre worker-backed path requested and ready for workers=on',
				'provider tree extent facts reached DOM',
				'search, regex, and filters changed rendered Pierre rows',
				'source-less split reset preserved stale body and fetched replacement only on refresh',
			],
			proofArtifactPath: '',
			negativeAssertions: [
				'standalone WorktreeFileApp test id absent',
				'review empty shell absent for worktree-file protocol',
				'raw worktree payload text absent outside intended UI',
			],
			scrollExtentCanary,
			selectedContentSemanticProof,
			selectedContentRouteProof,
			scenarioName: scenarioNameFromDevServerUrl(worktreeDevServerUrl),
			screenshotPaths: {
				ready: readyScreenshotPath,
				review: reviewRouteProof.screenshotPath,
				reviewFileTarget: reviewFileTargetRouteProof.screenshotPath,
				search: productControlsProof.searchScreenshotPath,
				stale: staleRefreshProof.staleScreenshotPath,
			},
			sourceCursor: surface.source.sourceCursor,
			sourceId: surface.source.sourceId,
			sourceBaseRef: surface.provenance.baseRef,
			sourceScenarioName: surface.provenance.scenarioName,
			worktreeRootToken: surface.provenance.worktreeRootToken,
			splitResetReplacementProof,
			staleRefreshProof,
			targetPath: targetDescriptor.path,
			treePathCount: surface.treeSizeFacts.pathCount ?? null,
			treeTotalSizeSource: rendered.treeTotalSizeSource,
			sharedShellProof,
			substituteGuardProof,
			visibleAppProof,
			fileToReviewHandoffProof,
			productControlsProof,
			reviewFileTargetRouteProof,
			reviewRouteProof,
		};
	} finally {
		await page.close();
		if (splitResetFixture !== null) {
			await restoreWorktreeFileStaleRefreshFixture(splitResetFixture);
		}
		if (staleRefreshFixture !== null) {
			await restoreWorktreeFileStaleRefreshFixture(staleRefreshFixture);
		}
		if (unavailableFilterFixture !== null) {
			await restoreWorktreeFileDeletedUnavailableFixture(unavailableFilterFixture);
		}
		if (fileToReviewHandoffFixture !== null) {
			await restoreWorktreeFileModifiedFixture(fileToReviewHandoffFixture);
		}
		if (reviewSelectionFixture !== null) {
			await restoreWorktreeFileModifiedFixture(reviewSelectionFixture);
		}
	}
}

async function verifyWorktreeReviewRoute(): Promise<WorktreeReviewRouteProof> {
	const page = await makeVerificationPage();
	const routeProbe = await installReviewRouteProbe(page);
	try {
		const selectionItemId = await fetchWorktreeReviewItemIdForDisplayPath(
			reviewSelectionFixtureRelativePath,
		);
		await page.goto(worktreeReviewDevServerUrl, {
			waitUntil: 'domcontentloaded',
			timeout: 30_000,
		});
		await page.waitForSelector('[data-testid="bridge-app-root"]', { timeout: 30_000 });
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		await waitForAnyReviewSelectedContentState({ page, state: 'ready' });
		const reviewContentHitCountBeforeClick = routeProbe.contentHitCount();
		const reviewSelectionProof = await clickReviewTreeFilePathViaSearch({
			page,
			path: reviewSelectionFixtureRelativePath,
		});
		await waitForReviewSelectedContentState({
			displayPath: reviewSelectionFixtureRelativePath,
			page,
			state: 'ready',
		});
		await waitForReviewRenderedSelection({
			expectedItemId: selectionItemId,
			expectedVisibleText: reviewSelectionFixtureMarker,
			page,
		});
		const reviewSelectionPostClickContentRouteProof = await waitForReviewContentRouteHitAfterIndex({
			beforeHitCount: reviewContentHitCountBeforeClick,
			expectedItemId: selectionItemId,
			routeProbe,
		});
		const reviewRenderedSelectionProof = await readReviewRenderedSelectionSnapshot(page);
		const reviewCollapseControlProof = await readReviewCollapseControlProof({
			expectedItemId: selectionItemId,
			page,
		});
		if (
			!reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: selectionItemId,
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: reviewSelectionFixtureMarker,
				},
				snapshot: reviewRenderedSelectionProof,
			})
		) {
			throw new Error(
				`Expected Review tree click to render ${selectionItemId} in the left CodeView canvas: ${JSON.stringify(reviewRenderedSelectionProof)}`,
			);
		}
		if (
			!reviewCollapseControlSatisfied({
				expectedItemId: selectionItemId,
				proof: reviewCollapseControlProof,
			})
		) {
			throw new Error(
				`Expected Review CodeView collapse control to use compact Button primitive chrome for ${selectionItemId}: ${JSON.stringify(reviewCollapseControlProof)}`,
			);
		}
		if (!reviewContentRouteDeltaSatisfied(reviewSelectionPostClickContentRouteProof)) {
			throw new Error(
				`Expected Review tree click to trigger a post-click content route for ${selectionItemId}: ${JSON.stringify(reviewSelectionPostClickContentRouteProof)}`,
			);
		}
		await waitForReviewContentRouteHitContaining({
			needle: selectionItemId,
			routeProbe,
		});
		const proof = await page.evaluate(() => {
			const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
			const appRoot = appRoots[0];
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const reviewContentHeader = document.querySelector(
				'[data-testid="bridge-viewer-content-topbar"]',
			);
			const reviewRailToolbar = document.querySelector(
				'[data-testid="bridge-review-rail-toolbar"]',
			);
			const reviewContentHeaderRect =
				reviewContentHeader instanceof HTMLElement
					? reviewContentHeader.getBoundingClientRect()
					: null;
			const reviewRailToolbarRect =
				reviewRailToolbar instanceof HTMLElement ? reviewRailToolbar.getBoundingClientRect() : null;
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			return {
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				appRootCount: appRoots.length,
				appRootVisible: appRoot instanceof HTMLElement && appRoot.getBoundingClientRect().width > 0,
				fileViewerCodeCanvasCount: document.querySelectorAll(
					'[data-testid="bridge-file-viewer-code-canvas"]',
				).length,
				fileContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-file'),
				fileViewerShellCount: document.querySelectorAll('[data-testid="bridge-file-viewer-shell"]')
					.length,
				fileViewerSidebarCount: document.querySelectorAll(
					'[data-testid="bridge-file-viewer-sidebar"]',
				).length,
				reviewEmptyShellCount: document.querySelectorAll(
					'[data-testid="bridge-review-empty-shell"]',
				).length,
				reviewCanvasCount: document.querySelectorAll('[data-testid="bridge-review-canvas"]').length,
				reviewCodeScrollCount: document.querySelectorAll(
					'[data-testid="bridge-review-code-scroll"]',
				).length,
				reviewContentHeaderHeight: reviewContentHeaderRect?.height ?? 0,
				reviewContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-review'),
				reviewHeaderMatchesRailToolbarHeight:
					reviewContentHeaderRect !== null &&
					reviewRailToolbarRect !== null &&
					Math.abs(reviewContentHeaderRect.height - reviewRailToolbarRect.height) <= 1,
				reviewPackageShellCount: document.querySelectorAll('[data-testid="review-viewer-shell"]')
					.length,
				reviewRailToolbarHeight: reviewRailToolbarRect?.height ?? 0,
				reviewRailToolbarUsesSharedAttr:
					reviewRailToolbar instanceof HTMLElement &&
					reviewRailToolbar.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
				reviewSelectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				reviewSelectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
				sharedShellMode:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				sharedShellOwner:
					appRoot instanceof HTMLElement
						? appRoot.getAttribute('data-bridge-viewer-shell-owner')
						: null,
				standaloneWorktreeFileAppCount: document.querySelectorAll(
					'[data-testid="worktree-file-app"]',
				).length,
			};
		});
		const selectionState = await page.evaluate(() => {
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			return {
				selectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				selectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
			};
		});
		const routeProof = {
			...proof,
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewCollapseControlProof,
			reviewSelectionContentRouteHitCount: routeProbe
				.contentHitUrls()
				.filter((url) => url.includes(selectionItemId)).length,
			reviewPackageRouteHitCount: routeProbe.packageHitCount(),
			reviewPackageRouteHitUrls: routeProbe.packageHitUrls(),
			reviewRenderedSelectionProof,
			reviewSelectionPostClickContentRouteProof,
			reviewSelectionProof,
			reviewSelectionSelectedContentState: selectionState.selectedContentState,
			reviewSelectionSelectedDisplayPath: selectionState.selectedDisplayPath,
			screenshotPath: await captureWorktreeDevServerScreenshot({
				name: 'worktree-review-ready.png',
				page,
			}),
			locationHref: await page.evaluate(() => window.location.href),
			pageUrl: page.url(),
		} satisfies WorktreeReviewRouteProof;
		const expectedReviewUrl = new URL(worktreeReviewDevServerUrl).href;
		if (
			routeProof.appOwner !== 'BridgeApp' ||
			routeProof.appRootCount !== 1 ||
			!routeProof.appRootVisible ||
			routeProof.locationHref !== expectedReviewUrl ||
			routeProof.pageUrl !== expectedReviewUrl ||
			routeProof.sharedShellMode !== 'review' ||
			routeProof.sharedShellOwner !== 'BridgeViewerAppShell' ||
			routeProof.fileContextButtonSelected !== 'false' ||
			routeProof.reviewContextButtonSelected !== 'true' ||
			routeProof.fileViewerShellCount !== 0 ||
			routeProof.fileViewerSidebarCount !== 0 ||
			routeProof.fileViewerCodeCanvasCount !== 0 ||
			routeProof.standaloneWorktreeFileAppCount !== 0 ||
			routeProof.reviewEmptyShellCount !== 0 ||
			routeProof.reviewPackageShellCount !== 1 ||
			routeProof.reviewCanvasCount !== 1 ||
			routeProof.reviewCodeScrollCount !== 1 ||
			routeProof.reviewSelectedContentState !== 'ready' ||
			routeProof.reviewSelectedDisplayPath === null ||
			routeProof.reviewContentHeaderHeight <= 0 ||
			routeProof.reviewRailToolbarHeight <= 0 ||
			!routeProof.reviewHeaderMatchesRailToolbarHeight ||
			!routeProof.reviewRailToolbarUsesSharedAttr ||
			routeProof.reviewPackageRouteHitCount !== 1 ||
			routeProof.reviewContentRouteHitCount <= 0 ||
			routeProof.reviewSelectionContentRouteHitCount <= 0 ||
			!reviewContentRouteDeltaSatisfied(routeProof.reviewSelectionPostClickContentRouteProof) ||
			!reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: selectionItemId,
				routeProof,
			}) ||
			routeProof.reviewSelectionSelectedContentState !== 'ready' ||
			routeProof.reviewSelectionSelectedDisplayPath !== reviewSelectionFixtureRelativePath ||
			!reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: selectionItemId,
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: reviewSelectionFixtureMarker,
				},
				snapshot: routeProof.reviewRenderedSelectionProof,
			}) ||
			!routeProof.reviewSelectionProof.searchOpened ||
			routeProof.reviewSelectionProof.searchInputValue !==
				normalizeReviewTreeSearchQuery(reviewSelectionFixtureRelativePath) ||
			routeProof.reviewSelectionProof.targetPath !== reviewSelectionFixtureRelativePath ||
			routeProof.reviewSelectionProof.clickedRowItemPath !== reviewSelectionFixtureRelativePath ||
			routeProof.reviewSelectionProof.clickedRowItemType !== 'file' ||
			!routeProof.reviewSelectionProof.clickedRowVisible
		) {
			throw new Error(
				`Expected worktree Review URL to load a real shared review package without FileViewer substitute: ${JSON.stringify(routeProof)}`,
			);
		}
		return routeProof;
	} finally {
		await routeProbe.dispose();
		await page.close();
	}
}

async function verifyWorktreeReviewFileTargetRoute(): Promise<WorktreeReviewFileTargetRouteProof> {
	const page = await makeVerificationPage();
	const routeProbe = await installReviewRouteProbe(page);
	try {
		const expectedDisplayPath = reviewSelectionFixtureRelativePath;
		const expectedReviewItemId = await fetchWorktreeReviewItemIdForDisplayPath(expectedDisplayPath);
		const expectedVersion = 'current';
		const reviewFileTargetUrl = reviewFileTargetUrlFromWorktreeDevServerUrl({
			path: expectedDisplayPath,
			url: worktreeDevServerUrl,
			version: expectedVersion,
		});
		await page.goto(reviewFileTargetUrl, {
			waitUntil: 'domcontentloaded',
			timeout: 30_000,
		});
		await page.waitForSelector('[data-testid="bridge-app-root"]', { timeout: 30_000 });
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
		try {
			await page.waitForFunction(
				(expected: { readonly itemId: string }): boolean => {
					const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
					return (
						codePanel?.getAttribute('data-selected-item-id') === expected.itemId &&
						codePanel?.getAttribute('data-selected-materialized-item-type') === 'file'
					);
				},
				{ itemId: expectedReviewItemId },
				{ timeout: 30_000 },
			);
		} catch (error) {
			const debugState = await page.evaluate(() => {
				const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				const attributes =
					codePanel instanceof HTMLElement
						? Object.fromEntries(
								[...codePanel.attributes].map((attribute) => [attribute.name, attribute.value]),
							)
						: {};
				return {
					codePanelAttributes: attributes,
					reviewSelectedContentState:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-content-state')
							: null,
					reviewSelectedDisplayPath:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-display-path')
							: null,
				};
			});
			throw new Error(
				`Timed out waiting for Review file-target route to materialize a file item: ${JSON.stringify(debugState)}`,
				{ cause: error },
			);
		}
		const proof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			const reviewContentHeader = document.querySelector(
				'[data-testid="bridge-viewer-content-topbar"]',
			);
			const reviewRailToolbar = document.querySelector(
				'[data-testid="bridge-review-rail-toolbar"]',
			);
			const reviewContentHeaderRect =
				reviewContentHeader instanceof HTMLElement
					? reviewContentHeader.getBoundingClientRect()
					: null;
			const reviewRailToolbarRect =
				reviewRailToolbar instanceof HTMLElement ? reviewRailToolbar.getBoundingClientRect() : null;
			return {
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				reviewContentHeaderHeight: reviewContentHeaderRect?.height ?? 0,
				reviewHeaderMatchesRailToolbarHeight:
					reviewContentHeaderRect !== null &&
					reviewRailToolbarRect !== null &&
					Math.abs(reviewContentHeaderRect.height - reviewRailToolbarRect.height) <= 1,
				reviewRailToolbarHeight: reviewRailToolbarRect?.height ?? 0,
				reviewRailToolbarUsesSharedAttr:
					reviewRailToolbar instanceof HTMLElement &&
					reviewRailToolbar.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
				selectedContentRoleCount:
					codePanel instanceof HTMLElement
						? Number(codePanel.getAttribute('data-selected-content-role-count') ?? '0')
						: 0,
				selectedCodeViewOverflow:
					codePanel instanceof HTMLElement
						? codePanel.getAttribute('data-bridge-code-view-overflow')
						: null,
				selectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				selectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
				selectedItemId:
					codePanel instanceof HTMLElement ? codePanel.getAttribute('data-selected-item-id') : null,
				selectedMaterializedFileLineCount:
					codePanel instanceof HTMLElement
						? Number(codePanel.getAttribute('data-selected-materialized-file-line-count') ?? '0')
						: 0,
				selectedMaterializedItemType:
					codePanel instanceof HTMLElement
						? codePanel.getAttribute('data-selected-materialized-item-type')
						: null,
				sharedShellMode:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				sharedShellOwner:
					appRoot instanceof HTMLElement
						? appRoot.getAttribute('data-bridge-viewer-shell-owner')
						: null,
				standaloneWorktreeFileAppCount: document.querySelectorAll(
					'[data-testid="worktree-file-app"]',
				).length,
			};
		});
		const routeProof = {
			...proof,
			expectedDisplayPath,
			expectedReviewItemId,
			expectedVersion,
			locationHref: await page.evaluate(() => window.location.href),
			pageUrl: page.url(),
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewPackageRouteHitCount: routeProbe.packageHitCount(),
			screenshotPath: await captureWorktreeDevServerScreenshot({
				name: 'worktree-review-file-target-ready.png',
				page,
			}),
		} satisfies WorktreeReviewFileTargetRouteProof;
		if (
			routeProof.appOwner !== 'BridgeApp' ||
			routeProof.locationHref !== reviewFileTargetUrl ||
			routeProof.pageUrl !== reviewFileTargetUrl ||
			routeProof.sharedShellMode !== 'review' ||
			routeProof.sharedShellOwner !== 'BridgeViewerAppShell' ||
			routeProof.selectedContentState !== 'ready' ||
			routeProof.selectedCodeViewOverflow !== 'wrap' ||
			routeProof.selectedDisplayPath !== expectedDisplayPath ||
			routeProof.selectedItemId !== expectedReviewItemId ||
			routeProof.selectedMaterializedItemType !== 'file' ||
			routeProof.selectedMaterializedFileLineCount <= 0 ||
			routeProof.reviewContentHeaderHeight <= 0 ||
			routeProof.reviewRailToolbarHeight <= 0 ||
			!routeProof.reviewHeaderMatchesRailToolbarHeight ||
			!routeProof.reviewRailToolbarUsesSharedAttr ||
			routeProof.standaloneWorktreeFileAppCount !== 0 ||
			routeProof.reviewPackageRouteHitCount !== 1 ||
			routeProof.reviewContentRouteHitCount <= 0
		) {
			throw new Error(
				`Expected worktree Review file-target URL to render a typed Pierre file target in Review context: ${JSON.stringify(routeProof)}`,
			);
		}
		return routeProof;
	} finally {
		await routeProbe.dispose();
		await page.close();
	}
}

async function assertNoStandaloneWorktreeFileApp(
	page: Page,
): Promise<WorktreeFileSubstituteGuardProof> {
	const standaloneWorktreeFileAppCount = await page
		.locator('[data-testid="worktree-file-app"]')
		.count();
	const reviewEmptyShellCount = await page
		.locator('[data-testid="bridge-review-empty-shell"]')
		.count();
	if (standaloneWorktreeFileAppCount > 0) {
		throw new Error(
			'Gate 0.a forbids standalone WorktreeFileApp; expected shared BridgeViewer FileViewer shell',
		);
	}
	if (reviewEmptyShellCount > 0) {
		throw new Error('Expected Worktree/File route to avoid the Review empty shell');
	}
	return {
		reviewEmptyShellCount,
		standaloneWorktreeFileAppCount,
	};
}

async function assertObservedWorktreeDevServerUrl(page: Page): Promise<{
	readonly locationHref: string;
	readonly pageUrl: string;
}> {
	const pageUrl = page.url();
	const locationHref = await page.evaluate(() => window.location.href);
	const expectedUrl = new URL(worktreeDevServerUrl).href;
	if (pageUrl !== expectedUrl || locationHref !== expectedUrl) {
		throw new Error(
			`Expected exact Worktree/File dev-server URL ${expectedUrl}, got page=${pageUrl} location=${locationHref}`,
		);
	}
	return { locationHref, pageUrl };
}

async function reloadWorktreeDevServerPage(page: Page): Promise<void> {
	await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
	await page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', { timeout: 30_000 });
	await assertObservedWorktreeDevServerUrl(page);
}

async function readBridgePierreWorkerFileSuccessCount(page: Page): Promise<number> {
	return await page.evaluate(() =>
		Number(document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0'),
	);
}

async function waitForBridgePierreWorkerFileSuccessCountAbove(props: {
	readonly page: Page;
	readonly previousFileSuccessCount: number;
}): Promise<void> {
	await props.page.waitForFunction(
		(previousFileSuccessCount: number): boolean => {
			const fileSuccessCount = Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			);
			return Number.isInteger(fileSuccessCount) && fileSuccessCount > previousFileSuccessCount;
		},
		props.previousFileSuccessCount,
		{ timeout: 20_000 },
	);
}

async function assertSharedBridgeFileViewerShell(props: {
	readonly page: Page;
	readonly targetDescriptor: WorktreeFileDescriptor;
	readonly workerFileSuccessCountBeforeTargetSelection: number;
}): Promise<WorktreeFileSharedShellProof> {
	await props.page.waitForFunction(
		(): boolean => {
			const fileSuccessCount = Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			);
			return Number.isInteger(fileSuccessCount) && fileSuccessCount > 0;
		},
		{ timeout: 20_000 },
	);
	const proof = await props.page.evaluate(() => {
		const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
		const shells = [...document.querySelectorAll('[data-testid="bridge-file-viewer-shell"]')];
		const codeCanvases = [
			...document.querySelectorAll('[data-testid="bridge-file-viewer-code-canvas"]'),
		];
		const sidebars = [...document.querySelectorAll('[data-testid="bridge-file-viewer-sidebar"]')];
		const appRoot = appRoots[0];
		const modeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
		const shell = shells[0];
		const codeCanvas = codeCanvases[0];
		const sidebar = sidebars[0];
		const contentTopbars = [
			...document.querySelectorAll('[data-testid="bridge-viewer-content-topbar"]'),
		];
		const contentTopbar = contentTopbars[0];
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const contextFileButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const contextReviewButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		const contentTitle = document.querySelector('[data-testid="bridge-viewer-content-title"]');
		const pierreTree = document.querySelector(
			'[data-testid="bridge-file-viewer-pierre-file-tree"]',
		);
		const railToolbar = document.querySelector('[data-testid="bridge-file-viewer-rail-toolbar"]');
		const railFilterButton = document.querySelector('[data-testid="worktree-file-filter-menu"]');
		const railSearchButton = document.querySelector('[data-testid="bridge-review-search-toggle"]');
		const railOpenReviewButton = document.querySelector(
			'[data-testid="worktree-file-open-review-comparison"]',
		);
		if (
			!(appRoot instanceof HTMLElement) ||
			!(modeHost instanceof HTMLElement) ||
			!(shell instanceof HTMLElement) ||
			!(codeCanvas instanceof HTMLElement) ||
			!(sidebar instanceof HTMLElement) ||
			!(contentTopbar instanceof HTMLElement) ||
			!(contextSwitcher instanceof HTMLElement) ||
			!(contextFileButton instanceof HTMLElement) ||
			!(contextReviewButton instanceof HTMLElement) ||
			!(contentTitle instanceof HTMLElement) ||
			!(pierreTree instanceof HTMLElement) ||
			!(railToolbar instanceof HTMLElement) ||
			!(railFilterButton instanceof HTMLElement) ||
			!(railSearchButton instanceof HTMLElement) ||
			!(railOpenReviewButton instanceof HTMLElement)
		) {
			return null;
		}
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- this helper must execute inside the browser context.
		const elementOwnsCenterPoint = (element: HTMLElement): boolean => {
			const rect = element.getBoundingClientRect();
			const centerX = rect.left + rect.width / 2;
			const centerY = rect.top + rect.height / 2;
			const topElement = document.elementFromPoint(centerX, centerY);
			return topElement !== null && (topElement === element || element.contains(topElement));
		};
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- this helper must execute inside the browser context.
		const visibleContextButtonSelection = (testId: string): string | null => {
			const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
			const visibleButton = buttons.find(
				(button): button is HTMLElement =>
					button instanceof HTMLElement && button.getClientRects().length > 0,
			);
			return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
		};
		const codeRect = codeCanvas.getBoundingClientRect();
		const sidebarRect = sidebar.getBoundingClientRect();
		const contentTopbarRect = contentTopbar.getBoundingClientRect();
		const contextSwitcherRect = contextSwitcher.getBoundingClientRect();
		const contextFileButtonRect = contextFileButton.getBoundingClientRect();
		const contextReviewButtonRect = contextReviewButton.getBoundingClientRect();
		const railToolbarRect = railToolbar.getBoundingClientRect();
		const railFilterButtonRect = railFilterButton.getBoundingClientRect();
		const railSearchButtonRect = railSearchButton.getBoundingClientRect();
		const railOpenReviewButtonRect = railOpenReviewButton.getBoundingClientRect();
		const sameHeight = (left: number, right: number): boolean => Math.abs(left - right) <= 1;
		const contentHeaderBackground = getComputedStyle(contentTopbar).backgroundColor;
		const railToolbarBackground = getComputedStyle(railToolbar).backgroundColor;
		return {
			appOwner: appRoot.getAttribute('data-bridge-app-owner'),
			appRootCount: appRoots.length,
			appRootOwnsCenterPoint: elementOwnsCenterPoint(appRoot),
			codeCanvasCount: codeCanvases.length,
			codeCanvasOwnsCenterPoint: elementOwnsCenterPoint(codeCanvas),
			codeOwner: codeCanvas.getAttribute('data-pierre-code-view-owner'),
			codeViewOverflow: codeCanvas.getAttribute('data-bridge-code-view-overflow'),
			contentPaneStartsBelowTopbar: codeRect.top >= contentTopbarRect.bottom - 1,
			contentHeaderAndRailToolbarTopAligned:
				Math.abs(contentTopbarRect.top - railToolbarRect.top) <= 1,
			contentHeaderBackground,
			contentHeaderMatchesRailToolbarBackground: contentHeaderBackground === railToolbarBackground,
			contentHeaderHeight: contentTopbarRect.height,
			contentHeaderMatchesRailToolbarHeight: sameHeight(
				contentTopbarRect.height,
				railToolbarRect.height,
			),
			contentTopbarCount: contentTopbars.length,
			contentTopbarOwnsCenterPoint: elementOwnsCenterPoint(contentTopbar),
			contentTopbarStopsBeforeSidebar: contentTopbarRect.right <= sidebarRect.left + 1,
			contentTopbarVisible: contentTopbarRect.width > 0 && contentTopbarRect.height > 0,
			contextFileButtonHeight: contextFileButtonRect.height,
			contextReviewButtonHeight: contextReviewButtonRect.height,
			contextSegmentMatchesRailButtonHeight:
				sameHeight(contextSwitcherRect.height, railFilterButtonRect.height) &&
				sameHeight(contextSwitcherRect.height, railSearchButtonRect.height) &&
				sameHeight(contextSwitcherRect.height, railOpenReviewButtonRect.height),
			contextSwitcherHeight: contextSwitcherRect.height,
			contentTitleText: contentTitle.textContent ?? '',
			contextSwitcherInsideContentTopbar: contentTopbar.contains(contextSwitcher),
			fileContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-file'),
			hasPierreTreeShadowRoot: pierreTree.querySelector('file-tree-container')?.shadowRoot !== null,
			modeHostActive: modeHost.getAttribute('data-bridge-viewer-mode-active'),
			modeHostCount: document.querySelectorAll('[data-testid="bridge-viewer-mode-host-file"]')
				.length,
			modeHostParentIsSharedRoot: modeHost.parentElement === appRoot,
			rootVisible: appRoot.getBoundingClientRect().width > 0,
			railButtonHeightsMatch:
				sameHeight(railFilterButtonRect.height, railSearchButtonRect.height) &&
				sameHeight(railFilterButtonRect.height, railOpenReviewButtonRect.height),
			railFilterButtonHeight: railFilterButtonRect.height,
			railOpenReviewButtonHeight: railOpenReviewButtonRect.height,
			railSearchButtonHeight: railSearchButtonRect.height,
			railToolbarBackground,
			railToolbarBackgroundIsOpaque: !railToolbarBackground.startsWith('rgba(0, 0, 0, 0'),
			railToolbarHeight: railToolbarRect.height,
			reviewContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-review'),
			sharedShellMode: appRoot.getAttribute('data-bridge-viewer-mode'),
			sharedShellOwner: appRoot.getAttribute('data-bridge-viewer-shell-owner'),
			shellCount: shells.length,
			shellOwnsCenterPoint: elementOwnsCenterPoint(shell),
			shellParentIsModeHost: shell.parentElement === modeHost,
			shellOwner: shell.getAttribute('data-file-viewer-owner'),
			sidebarCount: sidebars.length,
			sidebarIsRight: sidebarRect.left > codeRect.left,
			sidebarOwnsCenterPoint: elementOwnsCenterPoint(sidebar),
			sidebarPosition: shell.getAttribute('data-sidebar-position'),
			sidebarStartsAtContentTopbar: Math.abs(sidebarRect.top - contentTopbarRect.top) <= 1,
			shikiRendering: codeCanvas.getAttribute('data-shiki-rendering'),
			treeOwner: sidebar.getAttribute('data-pierre-file-tree-owner'),
			workerRequestedState: codeCanvas.getAttribute('data-worker-backed-highlighting'),
			workerDiagnosticFileSuccessCount: Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			),
			workerDiagnosticLastSuccessRequestType:
				document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessRequestType'] ??
				null,
			workerDiagnosticLastFileSuccessCacheKey:
				document.documentElement.dataset['bridgePierreWorkerDiagnosticLastFileSuccessCacheKey'] ??
				null,
			workerPoolFileCacheSize: Number(
				document.documentElement.dataset['bridgePierreWorkerPoolFileCacheSize'] ?? '0',
			),
			workerPoolManagerState:
				document.documentElement.dataset['bridgePierreWorkerPoolManagerState'] ?? null,
			workerPoolState: document.documentElement.dataset['bridgePierreWorkerPoolState'] ?? null,
			codeViewThemeState:
				document.documentElement.dataset['bridgePierreCodeViewThemeState'] ?? null,
		};
	});
	if (proof === null) {
		throw new Error('Expected shared BridgeViewer FileViewer shell with code canvas and sidebar');
	}
	const proofWithWorkerBaseline = {
		...proof,
		workerDiagnosticFileSuccessCountBeforeTargetSelection:
			props.workerFileSuccessCountBeforeTargetSelection,
	} satisfies WorktreeFileSharedShellProof;
	const expectedTargetWorkerCacheKey = worktreeFilePierreCacheKey(props.targetDescriptor);
	if (
		proofWithWorkerBaseline.sharedShellOwner !== 'BridgeViewerAppShell' ||
		proofWithWorkerBaseline.appOwner !== 'BridgeApp' ||
		proofWithWorkerBaseline.sharedShellMode !== 'file' ||
		proofWithWorkerBaseline.appRootCount !== 1 ||
		!proofWithWorkerBaseline.appRootOwnsCenterPoint ||
		proofWithWorkerBaseline.modeHostCount !== 1 ||
		proofWithWorkerBaseline.modeHostActive !== 'true' ||
		!proofWithWorkerBaseline.modeHostParentIsSharedRoot ||
		proofWithWorkerBaseline.fileContextButtonSelected !== 'true' ||
		proofWithWorkerBaseline.reviewContextButtonSelected !== 'false' ||
		proofWithWorkerBaseline.shellCount !== 1 ||
		!proofWithWorkerBaseline.shellOwnsCenterPoint ||
		proofWithWorkerBaseline.codeCanvasCount !== 1 ||
		!proofWithWorkerBaseline.codeCanvasOwnsCenterPoint ||
		proofWithWorkerBaseline.contentTopbarCount !== 1 ||
		!proofWithWorkerBaseline.contentTopbarVisible ||
		!proofWithWorkerBaseline.contentTopbarOwnsCenterPoint ||
		!proofWithWorkerBaseline.contentHeaderAndRailToolbarTopAligned ||
		!proofWithWorkerBaseline.contentHeaderMatchesRailToolbarBackground ||
		!proofWithWorkerBaseline.contentHeaderMatchesRailToolbarHeight ||
		!proofWithWorkerBaseline.contextSwitcherInsideContentTopbar ||
		!proofWithWorkerBaseline.contextSegmentMatchesRailButtonHeight ||
		!proofWithWorkerBaseline.contentTopbarStopsBeforeSidebar ||
		!proofWithWorkerBaseline.contentPaneStartsBelowTopbar ||
		!proofWithWorkerBaseline.contentTitleText.includes(' / ') ||
		!proofWithWorkerBaseline.railButtonHeightsMatch ||
		!proofWithWorkerBaseline.railToolbarBackgroundIsOpaque ||
		proofWithWorkerBaseline.sidebarCount !== 1 ||
		!proofWithWorkerBaseline.sidebarOwnsCenterPoint ||
		!proofWithWorkerBaseline.sidebarStartsAtContentTopbar ||
		!proofWithWorkerBaseline.shellParentIsModeHost ||
		proofWithWorkerBaseline.shellOwner !== 'BridgeViewerApp.FileViewer' ||
		proofWithWorkerBaseline.sidebarPosition !== 'right' ||
		!proofWithWorkerBaseline.sidebarIsRight ||
		proofWithWorkerBaseline.codeOwner !== 'CodeView.file' ||
		proofWithWorkerBaseline.codeViewOverflow !== 'wrap' ||
		proofWithWorkerBaseline.shikiRendering !== 'pierre' ||
		proofWithWorkerBaseline.treeOwner !== 'FileTree' ||
		!proofWithWorkerBaseline.hasPierreTreeShadowRoot ||
		!proofWithWorkerBaseline.rootVisible ||
		proofWithWorkerBaseline.workerRequestedState !== 'requested' ||
		proofWithWorkerBaseline.workerDiagnosticFileSuccessCount <=
			props.workerFileSuccessCountBeforeTargetSelection ||
		proofWithWorkerBaseline.workerDiagnosticLastSuccessRequestType !== 'file' ||
		proofWithWorkerBaseline.workerDiagnosticLastFileSuccessCacheKey !==
			expectedTargetWorkerCacheKey ||
		proofWithWorkerBaseline.workerPoolFileCacheSize <= 0 ||
		proofWithWorkerBaseline.workerPoolManagerState !== 'initialized' ||
		proofWithWorkerBaseline.workerPoolState !== 'ready' ||
		proofWithWorkerBaseline.codeViewThemeState !== 'ready'
	) {
		throw new Error(
			`Expected shared BridgeViewer/Pierre FileViewer proof: ${JSON.stringify(proofWithWorkerBaseline)}`,
		);
	}
	return proofWithWorkerBaseline;
}

function worktreeFilePierreCacheKey(descriptor: WorktreeFileDescriptor): string {
	return `${descriptor.contentHandle}:${descriptor['contentHash'] ?? 'unknown'}`;
}

async function fetchWorktreeSurface(): Promise<
	z.infer<typeof bridgeWorktreeSurfaceResponseSchema>
> {
	const surfaceUrl = new URL('/__bridge-worktree/surface', worktreeDevServerUrl);
	copyScenarioSearchParam(surfaceUrl);
	const response = await fetch(surfaceUrl);
	if (!response.ok) {
		throw new Error(`Worktree/File surface request failed: ${response.status}`);
	}
	return bridgeWorktreeSurfaceResponseSchema.parse(await response.json());
}

async function readBrowserProof(page: Page): Promise<WorktreeDevServerBrowserProof> {
	const viewport = page.viewportSize();
	return {
		browserName: browser.browserType().name(),
		browserVersion: browser.version(),
		headless: true,
		viewportHeight: viewport?.height ?? 0,
		viewportWidth: viewport?.width ?? 0,
	};
}

function assertWorktreeTreeExtentMatchesSurfaceFacts(props: {
	readonly renderedTreeTotalSizePixels: number;
	readonly surfaceTreeSizeFacts: z.infer<
		typeof bridgeWorktreeSurfaceResponseSchema
	>['treeSizeFacts'];
}): void {
	const expectedHeight = props.surfaceTreeSizeFacts.estimatedTotalHeightPixels ?? null;
	if (expectedHeight === null) {
		throw new Error(
			`Expected provider Worktree/File estimated tree extent facts: ${JSON.stringify(props.surfaceTreeSizeFacts)}`,
		);
	}
	if (Math.abs(props.renderedTreeTotalSizePixels - expectedHeight) > 1) {
		throw new Error(
			`Expected rendered tree extent to match provider facts: ${JSON.stringify({
				expectedHeight,
				renderedTreeTotalSizePixels: props.renderedTreeTotalSizePixels,
				surfaceTreeSizeFacts: props.surfaceTreeSizeFacts,
			})}`,
		);
	}
}

async function bridgeWorktreeDevRootTokenForPath(path: string): Promise<string> {
	return `root-${hashText(await realpath(path)).slice(0, 32)}`;
}

function hashText(value: string): string {
	return createHash('sha256').update(value).digest('hex');
}

function worktreeFileDescriptors(frames: readonly unknown[]): readonly WorktreeFileDescriptor[] {
	const descriptors: WorktreeFileDescriptor[] = [];
	for (const frame of frames) {
		const parsedFrame = worktreeFileDescriptorFrameSchema.safeParse(frame);
		if (parsedFrame.success) {
			descriptors.push(parsedFrame.data.descriptor);
		}
	}
	return descriptors;
}

function resolveTargetDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor {
	const descriptor =
		targetPathOverride === null
			? deepFetchableDescriptor(descriptors)
			: (descriptors.find((candidate) => candidate.path === targetPathOverride) ?? null);
	if (descriptor === null) {
		throw new Error(
			targetPathOverride === null
				? 'Expected at least one Worktree/File descriptor'
				: `Expected Worktree/File descriptor for ${targetPathOverride}`,
		);
	}
	return descriptor;
}

function firstFetchableDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor {
	const descriptor = descriptors.find(
		(candidate) =>
			!candidate['isBinary'] && candidate['virtualizedExtentKind'] === 'exactLineCount',
	);
	if (descriptor === undefined) {
		throw new Error('Expected at least one fetchable Worktree/File descriptor');
	}
	return descriptor;
}

function deepFetchableDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor | null {
	const fetchableDescriptors = descriptors.filter(
		(descriptor) =>
			!descriptor['isBinary'] && descriptor['virtualizedExtentKind'] === 'exactLineCount',
	);
	if (fetchableDescriptors.length === 0) {
		return null;
	}
	return (
		fetchableDescriptors.toSorted(
			(leftDescriptor, rightDescriptor) =>
				Number(rightDescriptor['lineCount'] ?? 0) - Number(leftDescriptor['lineCount'] ?? 0),
		)[0] ?? null
	);
}

interface WorktreeFileModifiedFixture {
	readonly absolutePath: string;
	readonly initialContent: string;
	readonly initialContentHash: string;
	readonly relativePath: string;
	readonly updatedContent: string;
	readonly updatedContentHash: string;
}

interface WorktreeFileStaleRefreshFixture extends WorktreeFileModifiedFixture {}

interface WorktreeFileDeletedUnavailableFixture {
	readonly absolutePath: string;
	readonly initialContent: string;
	readonly initialContentHash: string;
	readonly relativePath: string;
}

async function worktreeFileDeletedUnavailableFixture(): Promise<WorktreeFileDeletedUnavailableFixture> {
	const absolutePath = await resolveBridgeWorktreeVerifierWritePath({
		descriptorPath: unavailableFilterFixtureRelativePath,
		rootPath: repoRootPath,
	});
	await assertGitTrackedWorktreeVerifierPath(unavailableFilterFixtureRelativePath);
	const initialContent = await readFile(absolutePath, 'utf8');
	const fixture: WorktreeFileDeletedUnavailableFixture = {
		absolutePath,
		initialContent,
		initialContentHash: hashText(initialContent),
		relativePath: unavailableFilterFixtureRelativePath,
	};
	await unlink(absolutePath);
	return fixture;
}

async function worktreeFileModifiedFixture(props: {
	readonly relativePath: string;
	readonly tag: string;
}): Promise<WorktreeFileModifiedFixture> {
	const absolutePath = await resolveBridgeWorktreeVerifierWritePath({
		descriptorPath: props.relativePath,
		rootPath: repoRootPath,
	});
	await assertGitTrackedWorktreeVerifierPath(props.relativePath);
	const initialContent = await readFile(absolutePath, 'utf8');
	const marker = `bridge_worktree_devserver_${props.tag}_${proofRunCreatedAtUnixMilliseconds}`;
	const updatedContent = initialContent.endsWith('\n')
		? `${initialContent}${marker}\n`
		: `${initialContent}\n${marker}\n`;
	const fixture = {
		absolutePath,
		initialContent,
		initialContentHash: hashText(initialContent),
		relativePath: props.relativePath,
		updatedContent,
		updatedContentHash: hashText(updatedContent),
	};
	await writeFile(absolutePath, updatedContent);
	return fixture;
}

function resolveStaleRefreshDescriptor(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly excludedPaths: ReadonlySet<string>;
}): WorktreeFileDescriptor {
	const descriptor = props.descriptors.find(
		(candidate) =>
			!props.excludedPaths.has(candidate.path) &&
			!candidate['isBinary'] &&
			candidate['virtualizedExtentKind'] === 'exactLineCount',
	);
	if (descriptor === undefined) {
		throw new Error('Expected an existing fetchable Worktree/File descriptor for stale proof');
	}
	return descriptor;
}

async function worktreeFileStaleRefreshFixture(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly initialContent: string;
}): Promise<WorktreeFileStaleRefreshFixture> {
	const marker = `bridge_worktree_devserver_proof_${proofRunCreatedAtUnixMilliseconds}`;
	const absolutePath = await resolveBridgeWorktreeVerifierWritePath({
		descriptorPath: props.descriptor.path,
		rootPath: repoRootPath,
	});
	await assertGitTrackedWorktreeVerifierPath(props.descriptor.path);
	const initialContent = await readFile(absolutePath, 'utf8');
	const updatedContent = `${initialContent}\n// ${marker}: updated content\n`;
	return {
		absolutePath,
		initialContent,
		initialContentHash: hashText(initialContent),
		relativePath: props.descriptor.path,
		updatedContent,
		updatedContentHash: hashText(updatedContent),
	};
}

async function assertGitTrackedWorktreeVerifierPath(relativePath: string): Promise<void> {
	try {
		await execFileAsync('git', [
			'-C',
			repoRootPath,
			'ls-files',
			'--error-unmatch',
			'--',
			relativePath,
		]);
	} catch (error) {
		throw new Error(`Bridge worktree verifier path must be git-tracked: ${relativePath}`, {
			cause: error,
		});
	}
}

async function restoreWorktreeFileStaleRefreshFixture(
	fixture: WorktreeFileStaleRefreshFixture,
): Promise<void> {
	await restoreWorktreeFileModifiedFixture(fixture);
}

async function restoreWorktreeFileModifiedFixture(
	fixture: WorktreeFileModifiedFixture,
): Promise<void> {
	const currentHash = await readTextFileHashOrNull(fixture.absolutePath);
	if (currentHash !== fixture.initialContentHash && currentHash !== fixture.updatedContentHash) {
		throw new Error(
			`Refusing to restore modified proof file after external edit: ${fixture.relativePath}`,
		);
	}
	if (currentHash === fixture.updatedContentHash) {
		await writeFile(fixture.absolutePath, fixture.initialContent);
	}
	const restoredContent = await readFile(fixture.absolutePath, 'utf8');
	if (hashText(restoredContent) !== fixture.initialContentHash) {
		throw new Error(`Failed to restore modified proof file: ${fixture.relativePath}`);
	}
}

async function restoreWorktreeFileDeletedUnavailableFixture(
	fixture: WorktreeFileDeletedUnavailableFixture,
): Promise<void> {
	const currentHash = await readTextFileHashOrNull(fixture.absolutePath);
	if (currentHash !== null && currentHash !== fixture.initialContentHash) {
		throw new Error(
			`Refusing to restore deleted unavailable-filter proof file after external edit: ${fixture.relativePath}`,
		);
	}
	if (currentHash === null) {
		await writeFile(fixture.absolutePath, fixture.initialContent);
	}
	const restoredContent = await readFile(fixture.absolutePath, 'utf8');
	if (hashText(restoredContent) !== fixture.initialContentHash) {
		throw new Error(
			`Failed to restore deleted unavailable-filter proof file: ${fixture.relativePath}`,
		);
	}
}

async function readTextFileHashOrNull(absolutePath: string): Promise<string | null> {
	try {
		return hashText(await readFile(absolutePath, 'utf8'));
	} catch (error) {
		if (isNodeErrorWithCode(error, 'ENOENT')) {
			return null;
		}
		throw error;
	}
}

function isNodeErrorWithCode(
	error: unknown,
	code: string,
): error is Error & { readonly code: string } {
	return error instanceof Error && 'code' in error && error.code === code;
}

async function fetchWorktreeFileContent(descriptor: WorktreeFileDescriptor): Promise<string> {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(
		descriptor.contentDescriptor.descriptor.resourceUrl,
		{
			allowedResourceKindsByProtocol: {
				'worktree-file': new Set(['worktree.fileContent']),
			},
		},
	);
	if (parsedResourceUrl === null) {
		throw new Error(`Invalid Worktree/File resource URL for ${descriptor.path}`);
	}
	const contentUrl = new URL(
		`/__bridge-worktree/file-content/${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
		worktreeDevServerUrl,
	);
	copyScenarioSearchParam(contentUrl);
	if (parsedResourceUrl.generation !== undefined) {
		contentUrl.searchParams.set('generation', String(parsedResourceUrl.generation));
	}
	if (parsedResourceUrl.cursor !== undefined) {
		contentUrl.searchParams.set('cursor', parsedResourceUrl.cursor);
	}
	const response = await fetch(contentUrl);
	if (!response.ok) {
		throw new Error(`Worktree/File content request failed: ${response.status}`);
	}
	return await response.text();
}

function copyScenarioSearchParam(url: URL): void {
	const scenario = new URL(worktreeDevServerUrl).searchParams.get('scenario');
	if (scenario !== null) {
		url.searchParams.set('scenario', scenario);
	}
}

async function makeVerificationPage(): Promise<Page> {
	const page = await browser.newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
	await page.addInitScript((): void => {
		const verifierHelpers: WorktreeVerifierBrowserHelpers = {
			getBridgeFileViewerRenderedCodeLineCount(): number {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return 0;
				}
				return Array.from(canvas.querySelectorAll('diffs-container')).reduce(
					(lineCount, container) =>
						lineCount +
						(container.shadowRoot?.querySelectorAll('[data-content] [data-line-index]').length ??
							0),
					0,
				);
			},
			getBridgeFileViewerRenderedCodeText(): string {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return '';
				}
				const renderedContentBlocks = Array.from(
					canvas.querySelectorAll('diffs-container'),
				).flatMap((container) =>
					Array.from(container.shadowRoot?.querySelectorAll('[data-content]') ?? []),
				);
				const renderedText = renderedContentBlocks
					.map((contentBlock) => contentBlock.textContent ?? '')
					.join('\n');
				return renderedText.length > 0 ? renderedText : (canvas.textContent ?? '');
			},
			getBridgeFileViewerScrollableContent(): HTMLElement | null {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return null;
				}
				const candidates = [
					canvas,
					...Array.from(canvas.querySelectorAll('*')).filter(
						(candidate): candidate is HTMLElement => candidate instanceof HTMLElement,
					),
				];
				return (
					candidates.find((candidate) => candidate.scrollHeight > candidate.clientHeight) ?? canvas
				);
			},
			getPierreFileTreeItem(path: string): HTMLElement | null {
				const escapedPath = CSS.escape(path);
				return (
					this.getPierreFileTreeItems().find(
						(candidate) => candidate.dataset['itemPath'] === path,
					) ??
					this.getPierreFileTreeScrollElement()?.querySelector(
						`[data-item-path="${escapedPath}"]`,
					) ??
					null
				);
			},
			getPierreFileTreeItems(): HTMLElement[] {
				const scrollElement = this.getPierreFileTreeScrollElement();
				if (!(scrollElement instanceof HTMLElement)) {
					return [];
				}
				return Array.from(scrollElement.querySelectorAll('[data-item-path]')).filter(
					(candidate): candidate is HTMLElement =>
						candidate instanceof HTMLElement &&
						candidate.dataset['fileTreeStickyRow'] !== 'true' &&
						candidate.dataset['itemParked'] !== 'true',
				);
			},
			getPierreFileTreeScrollElement(): HTMLElement | null {
				const treeHost = document.querySelector(
					'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
				);
				const scrollElement = treeHost?.shadowRoot?.querySelector(
					'[data-file-tree-virtualized-scroll="true"]',
				);
				return scrollElement instanceof HTMLElement ? scrollElement : null;
			},
		};
		Object.defineProperty(window, 'bridgeWorktreeVerifier', {
			configurable: true,
			value: verifierHelpers,
		});
	});
	return page;
}

async function installFileContentRouteGate(props: {
	readonly gate: Deferred<void>;
	readonly failFirstHit?: boolean;
	readonly failFirstHitContentHandle?: string;
	readonly page: Page;
	readonly pathPattern?: string;
}): Promise<WorktreeFileContentRouteProbe> {
	const hitUrls: string[] = [];
	const foreignHitUrls: string[] = [];
	const pathPattern = props.pathPattern ?? '**/__bridge-worktree/file-content/**';
	let failedFirstHit = false;
	const routeHandler = async (route: Route): Promise<void> => {
		const requestUrl = route.request().url();
		if (
			!bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin: worktreeDevServerOrigin,
				url: requestUrl,
			})
		) {
			foreignHitUrls.push(requestUrl);
			await route.fulfill({
				status: 599,
				contentType: 'text/plain',
				body: `foreign Worktree/File content route origin rejected: ${requestUrl}`,
			});
			return;
		}
		hitUrls.push(requestUrl);
		const failFirstHitMatchesRequest =
			props.failFirstHitContentHandle === undefined ||
			bridgeWorktreeDevFileContentRouteMatchesHandle({
				expectedContentHandle: props.failFirstHitContentHandle,
				expectedOrigin: worktreeDevServerOrigin,
				url: requestUrl,
			});
		if (props.failFirstHit === true && !failedFirstHit && failFirstHitMatchesRequest) {
			failedFirstHit = true;
			await route.fulfill({
				status: 503,
				contentType: 'text/plain',
				body: 'forced refresh failure for Gate 0.a retry proof',
			});
			return;
		}
		await props.gate.promise;
		await route.continue();
	};
	await props.page.route(pathPattern, routeHandler);
	return {
		dispose: async (): Promise<void> => {
			await props.page.unroute(pathPattern, routeHandler);
		},
		foreignHitCount: (): number => foreignHitUrls.length,
		foreignHitUrls: (): readonly string[] => foreignHitUrls,
		hitCount: (): number => hitUrls.length,
		hitUrls: (): readonly string[] => hitUrls,
	};
}

async function installReviewRouteProbe(page: Page): Promise<ReviewRouteProbe> {
	const packageHitUrls: string[] = [];
	const contentHitUrls: string[] = [];
	const packageRoutePattern = '**/__bridge-worktree/review-package**';
	const contentRoutePattern = '**/__bridge-worktree/review-content/**';
	const assertReviewRouteOrigin = async (route: Route): Promise<boolean> => {
		const requestUrl = route.request().url();
		if (bridgeWorktreeDevReviewRouteUsesOrigin(requestUrl)) {
			return true;
		}
		await route.fulfill({
			status: 599,
			contentType: 'text/plain',
			body: `foreign Worktree/Review route origin rejected: ${requestUrl}`,
		});
		return false;
	};
	const packageRouteHandler = async (route: Route): Promise<void> => {
		if (!(await assertReviewRouteOrigin(route))) {
			return;
		}
		packageHitUrls.push(route.request().url());
		await route.continue();
	};
	const contentRouteHandler = async (route: Route): Promise<void> => {
		if (!(await assertReviewRouteOrigin(route))) {
			return;
		}
		contentHitUrls.push(route.request().url());
		await route.continue();
	};
	await page.route(packageRoutePattern, packageRouteHandler);
	await page.route(contentRoutePattern, contentRouteHandler);
	return {
		contentHitCount: (): number => contentHitUrls.length,
		contentHitUrls: (): readonly string[] => contentHitUrls,
		dispose: async (): Promise<void> => {
			await page.unroute(packageRoutePattern, packageRouteHandler);
			await page.unroute(contentRoutePattern, contentRouteHandler);
		},
		packageHitCount: (): number => packageHitUrls.length,
		packageHitUrls: (): readonly string[] => packageHitUrls,
	};
}

async function fetchWorktreeReviewItemIdForDisplayPath(displayPath: string): Promise<string> {
	const packageUrl = new URL('/__bridge-worktree/review-package', worktreeReviewDevServerUrl);
	packageUrl.searchParams.set('scenario', scenarioNameFromDevServerUrl(worktreeReviewDevServerUrl));
	const response = await fetch(packageUrl);
	if (!response.ok) {
		throw new Error(
			`Expected Worktree/Review package route for ${displayPath}, got ${response.status}`,
		);
	}
	const { reviewPackage } = worktreeReviewPackageRouteResponseSchema.parse(await response.json());
	const item = Object.values(reviewPackage.itemsById).find(
		(candidate): boolean =>
			candidate.basePath === displayPath || candidate.headPath === displayPath,
	);
	if (item === undefined) {
		throw new Error(
			`Expected Worktree/Review package to include ${displayPath}; got ${reviewPackage.orderedItemIds.length} items`,
		);
	}
	return item.itemId;
}

function bridgeWorktreeDevReviewRouteUsesOrigin(url: string): boolean {
	let parsedUrl: URL;
	try {
		parsedUrl = new URL(url);
	} catch {
		return false;
	}
	return (
		parsedUrl.origin === worktreeDevServerOrigin &&
		(parsedUrl.pathname === '/__bridge-worktree/review-package' ||
			parsedUrl.pathname.startsWith('/__bridge-worktree/review-content/'))
	);
}

async function waitForRouteProbeHitCountAbove(props: {
	readonly minHitCount: number;
	readonly probe: WorktreeFileContentRouteProbe;
	readonly remainingAttempts?: number;
}): Promise<void> {
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (props.probe.hitCount() >= props.minHitCount) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for Worktree/File content route hit count ${props.minHitCount}; observed ${props.probe.hitCount()}: ${JSON.stringify(props.probe.hitUrls())}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	await waitForRouteProbeHitCountAbove({
		minHitCount: props.minHitCount,
		probe: props.probe,
		remainingAttempts: remainingAttempts - 1,
	});
}

async function waitForReviewContentRouteHitContaining(props: {
	readonly needle: string;
	readonly remainingAttempts?: number;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<void> {
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (props.routeProbe.contentHitUrls().some((url) => url.includes(props.needle))) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for Worktree/Review content route hit containing ${props.needle}: ${JSON.stringify(props.routeProbe.contentHitUrls())}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	await waitForReviewContentRouteHitContaining({
		needle: props.needle,
		remainingAttempts: remainingAttempts - 1,
		routeProbe: props.routeProbe,
	});
}

async function waitForReviewContentRouteHitAfterIndex(props: {
	readonly beforeHitCount: number;
	readonly expectedItemId: string;
	readonly remainingAttempts?: number;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<ReviewContentRouteDeltaProof> {
	const routeProof = buildReviewContentRouteDeltaProof({
		allHitUrls: props.routeProbe.contentHitUrls(),
		beforeHitCount: props.beforeHitCount,
		expectedItemId: props.expectedItemId,
	});
	if (reviewContentRouteDeltaSatisfied(routeProof)) {
		return routeProof;
	}
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for post-click Worktree/Review content route hit for ${props.expectedItemId}: ${JSON.stringify(routeProof)}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	return waitForReviewContentRouteHitAfterIndex({
		beforeHitCount: props.beforeHitCount,
		expectedItemId: props.expectedItemId,
		remainingAttempts: remainingAttempts - 1,
		routeProbe: props.routeProbe,
	});
}

function assertSelectedContentRouteProof(props: {
	readonly expectedContentHandle: string;
	readonly probe: WorktreeFileContentRouteProbe;
}): WorktreeFileSelectedContentRouteProof {
	const hitUrls = props.probe.hitUrls();
	const foreignHitUrls = props.probe.foreignHitUrls();
	const selectedHitUrl = hitUrls[0];
	const selectedResourceUrlContainsHandle =
		hitUrls.length === 1 &&
		selectedHitUrl !== undefined &&
		bridgeWorktreeDevFileContentRouteMatchesHandle({
			expectedContentHandle: props.expectedContentHandle,
			expectedOrigin: worktreeDevServerOrigin,
			url: selectedHitUrl,
		});
	const selectedResourceUrlUsesDevServerFrontDoor =
		hitUrls.length === 1 &&
		selectedHitUrl !== undefined &&
		bridgeWorktreeDevFileContentRouteUsesOrigin({
			expectedOrigin: worktreeDevServerOrigin,
			url: selectedHitUrl,
		});
	const proof: WorktreeFileSelectedContentRouteProof = {
		expectedContentHandle: props.expectedContentHandle,
		foreignHitCount: props.probe.foreignHitCount(),
		foreignHitUrls,
		hitCount: props.probe.hitCount(),
		hitUrls,
		selectedResourceUrlContainsHandle,
		selectedResourceUrlUsesDevServerFrontDoor,
	};
	if (
		proof.foreignHitCount !== 0 ||
		proof.hitCount !== 1 ||
		!proof.selectedResourceUrlContainsHandle ||
		!proof.selectedResourceUrlUsesDevServerFrontDoor
	) {
		throw new Error(
			`Expected selected Worktree/File content to request dev-server content route: ${JSON.stringify(proof)}`,
		);
	}
	return proof;
}

async function readWorktreeRenderedContentState(page: Page): Promise<WorktreeRenderedContentState> {
	return await page.evaluate((): WorktreeRenderedContentState => {
		const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const text =
			typeof window.bridgeWorktreeVerifier === 'undefined'
				? (contentPanel?.textContent ?? '')
				: window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText();
		const selectedDisplayPath = contentPanel?.getAttribute('data-worktree-open-file-path') ?? null;
		const renderedText = text.endsWith('\n') ? text.slice(0, -1) : text;
		const treeTotalSizeSourceRaw =
			treePanel?.getAttribute('data-worktree-tree-total-size-source') ?? null;
		return {
			selectedCharacterCount: text.length,
			selectedContentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
			selectedDisplayPath,
			selectedLineCount:
				typeof window.bridgeWorktreeVerifier === 'undefined'
					? text.length === 0
						? 0
						: renderedText.split('\n').length
					: window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeLineCount(),
			selectedText: text,
			treeTotalSizePixels: Number(treePanel?.getAttribute('data-worktree-tree-total-size') ?? '0'),
			treeTotalSizeSource:
				treeTotalSizeSourceRaw === 'providerFacts' || treeTotalSizeSourceRaw === 'localProjection'
					? treeTotalSizeSourceRaw
					: null,
		};
	});
}

function assertRenderedWorktreeContent(props: {
	readonly content: string;
	readonly label: string;
	readonly rendered: WorktreeRenderedContentState;
	readonly targetPath: string;
}): void {
	if (props.rendered.selectedDisplayPath !== props.targetPath) {
		throw new Error(`Expected ${props.label} path ${props.targetPath}`);
	}
	if (props.rendered.selectedContentState !== 'ready') {
		throw new Error(`Expected ${props.label} to be ready for ${props.targetPath}`);
	}
	if (!renderedTextIncludesContent(props.rendered.selectedText, props.content)) {
		throw new Error(`Expected ${props.label} content for ${props.targetPath}`);
	}
	const expectedLineCount = countTextLines(props.content);
	if (props.rendered.selectedLineCount < Math.min(expectedLineCount, 2)) {
		throw new Error(
			`Expected ${props.label} visible line structure for ${props.targetPath}, got ${props.rendered.selectedLineCount}`,
		);
	}
}

function renderedTextIncludesContent(renderedText: string, expectedContent: string): boolean {
	const trimmedExpectedContent = expectedContent.trim();
	if (trimmedExpectedContent.length === 0) {
		return true;
	}
	if (renderedText.includes(trimmedExpectedContent)) {
		return true;
	}
	const normalizedRenderedText = normalizeRenderedTextForProof(renderedText);
	const expectedLines = trimmedExpectedContent
		.split('\n')
		.map(normalizeRenderedTextForProof)
		.filter((line) => line.length > 0 && line.length <= 240);
	const sampleLines = expectedLines.slice(0, Math.min(expectedLines.length, 20));
	const matchingLineCount = sampleLines.filter((line) =>
		normalizedRenderedText.includes(line),
	).length;
	return matchingLineCount >= Math.min(5, sampleLines.length);
}

function normalizeRenderedTextForProof(text: string): string {
	return text.replace(/\s+/gu, ' ').trim();
}

async function scrollTreeToFilePath(page: Page, path: string): Promise<void> {
	await scrollPierreFileTreeUntilPathVisible(page, path);
	await page.evaluate((targetPath: string): void => {
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const helpers = window.bridgeWorktreeVerifier;
		const scrollElement = helpers.getPierreFileTreeScrollElement();
		const button = helpers.getPierreFileTreeItem(targetPath);
		if (
			!(button instanceof HTMLElement) ||
			!(treePanel instanceof HTMLElement) ||
			!(scrollElement instanceof HTMLElement)
		) {
			throw new Error(`Expected Worktree/File tree row for ${targetPath}`);
		}
		button.scrollIntoView({ block: 'center' });
		if (scrollElement.scrollTop <= 0) {
			scrollElement.scrollTop = Math.min(
				scrollElement.scrollHeight - scrollElement.clientHeight,
				160,
			);
		}
	}, path);
}

async function waitForPierreFileTreeAnchorSettled(page: Page, path: string): Promise<void> {
	await page.waitForFunction(
		(targetPath: string): boolean => {
			const helpers = window.bridgeWorktreeVerifier;
			const scrollElement = helpers.getPierreFileTreeScrollElement();
			const anchor = helpers.getPierreFileTreeItem(targetPath);
			if (!(scrollElement instanceof HTMLElement) || !(anchor instanceof HTMLElement)) {
				delete window.bridgeWorktreeVerifierLastTreeAnchorSignature;
				window.bridgeWorktreeVerifierStableTreeAnchorFrames = 0;
				return false;
			}
			const treeRect = scrollElement.getBoundingClientRect();
			const anchorRect = anchor.getBoundingClientRect();
			const visiblePaths = helpers
				.getPierreFileTreeItems()
				.map((candidate) => candidate.dataset['itemPath'] ?? '')
				.join('\u0000');
			const signature = [
				Math.round(scrollElement.scrollTop),
				Math.round(anchorRect.top - treeRect.top),
				visiblePaths,
			].join('|');
			if (window.bridgeWorktreeVerifierLastTreeAnchorSignature === signature) {
				window.bridgeWorktreeVerifierStableTreeAnchorFrames =
					(window.bridgeWorktreeVerifierStableTreeAnchorFrames ?? 0) + 1;
			} else {
				window.bridgeWorktreeVerifierLastTreeAnchorSignature = signature;
				window.bridgeWorktreeVerifierStableTreeAnchorFrames = 1;
			}
			return (window.bridgeWorktreeVerifierStableTreeAnchorFrames ?? 0) >= 2;
		},
		path,
		{ timeout: 10_000 },
	);
}

async function clickWorktreeFilePath(page: Page, path: string): Promise<void> {
	const treeItemLocator = page
		.locator(
			`[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container button[data-item-path=${cssStringLiteral(
				path,
			)}]`,
		)
		.first();
	for (let attempt = 0; attempt < 3; attempt += 1) {
		await dismissOpenBridgeMenus(page);
		await scrollPierreFileTreeUntilPathVisible(page, path);
		await page.evaluate((targetPath: string): void => {
			const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
			const scrollElement = window.bridgeWorktreeVerifier.getPierreFileTreeScrollElement();
			if (button instanceof HTMLElement && scrollElement instanceof HTMLElement) {
				const buttonRect = button.getBoundingClientRect();
				const scrollRect = scrollElement.getBoundingClientRect();
				const isFullyVisible =
					buttonRect.top >= scrollRect.top && buttonRect.bottom <= scrollRect.bottom;
				if (isFullyVisible) {
					return;
				}
				button.scrollIntoView({ block: 'center', inline: 'nearest' });
			}
		}, path);
		await page.waitForTimeout(50);
		const targetBox = await page.evaluate((targetPath: string): WorktreeFileVisibleRect | null => {
			const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
			if (!(button instanceof HTMLElement)) {
				return null;
			}
			const rect = button.getBoundingClientRect();
			return {
				height: rect.height,
				width: rect.width,
			};
		}, path);
		const targetCenter = await page.evaluate(
			(targetPath: string): { readonly x: number; readonly y: number } | null => {
				const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
				if (!(button instanceof HTMLElement)) {
					return null;
				}
				const rect = button.getBoundingClientRect();
				return {
					x: rect.left + rect.width / 2,
					y: rect.top + rect.height / 2,
				};
			},
			path,
		);
		if (
			targetBox === null ||
			targetBox.width <= 0 ||
			targetBox.height <= 0 ||
			targetCenter === null
		) {
			throw new Error(`Expected Worktree/File row for ${path}`);
		}
		const viewportSize = page.viewportSize();
		if (
			viewportSize !== null &&
			(targetCenter.y < 0 ||
				targetCenter.y > viewportSize.height ||
				targetCenter.x < 0 ||
				targetCenter.x > viewportSize.width)
		) {
			throw new Error(`Expected visible Worktree/File row for ${path}`);
		}
		await treeItemLocator.click({ timeout: 2_000 });
		const selected = await page
			.waitForFunction(
				(targetPath: string): boolean =>
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-selected-display-path') === targetPath,
				path,
				{ timeout: 1_000 },
			)
			.then(
				() => true,
				() => false,
			);
		if (selected) {
			return;
		}
	}
	const selectedPath = await page.evaluate(
		(): string | null =>
			document
				.querySelector('[data-testid="bridge-file-viewer-shell"]')
				?.getAttribute('data-selected-display-path') ?? null,
	);
	throw new Error(`Expected Worktree/File click to select ${path}, got ${selectedPath ?? 'none'}`);
}

async function dismissOpenBridgeMenus(page: Page): Promise<void> {
	if (!(await hasVisibleBridgeMenuPortal(page))) {
		return;
	}
	const controlsStateBeforeDismiss = await readWorktreeFileControlsStateSnapshot(page);
	await page.evaluate((): void => {
		if (document.activeElement instanceof HTMLElement) {
			document.activeElement.blur();
		}
	});
	await page.keyboard.press('Escape');
	await waitForNoVisibleBridgeMenuPortal(page);
	const controlsStateAfterDismiss = await readWorktreeFileControlsStateSnapshot(page);
	if (
		!worktreeFileControlsStateSnapshotsEqual(controlsStateBeforeDismiss, controlsStateAfterDismiss)
	) {
		throw new Error(
			`Expected Worktree/File menu dismissal to preserve controls state, before ${JSON.stringify(
				controlsStateBeforeDismiss,
			)}, after ${JSON.stringify(controlsStateAfterDismiss)}`,
		);
	}
}

async function waitForNoVisibleBridgeMenuPortal(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean =>
			![...document.querySelectorAll('[data-base-ui-portal], [data-base-ui-portal] *')].some(
				(portalElement) => {
					if (!(portalElement instanceof HTMLElement)) {
						return false;
					}
					const rect = portalElement.getBoundingClientRect();
					const style = getComputedStyle(portalElement);
					return (
						rect.width > 0 &&
						rect.height > 0 &&
						style.visibility !== 'hidden' &&
						style.display !== 'none' &&
						style.pointerEvents !== 'none'
					);
				},
			),
		undefined,
		{ timeout: 2_000 },
	);
}

async function hasVisibleBridgeMenuPortal(page: Page): Promise<boolean> {
	return await page.evaluate((): boolean =>
		[...document.querySelectorAll('[data-base-ui-portal], [data-base-ui-portal] *')].some(
			(portalElement) => {
				if (!(portalElement instanceof HTMLElement)) {
					return false;
				}
				const rect = portalElement.getBoundingClientRect();
				const style = getComputedStyle(portalElement);
				return (
					rect.width > 0 &&
					rect.height > 0 &&
					style.visibility !== 'hidden' &&
					style.display !== 'none' &&
					style.pointerEvents !== 'none'
				);
			},
		),
	);
}

async function readWorktreeFileControlsStateSnapshot(
	page: Page,
): Promise<WorktreeFileControlsStateSnapshot> {
	return await page.evaluate(
		(): WorktreeFileControlsStateSnapshot => ({
			filterMenuText:
				document.querySelector('[data-testid="worktree-file-filter-menu"]')?.textContent ?? null,
			filterStatusText:
				document.querySelector('[data-testid="worktree-file-filter-status"]')?.textContent ?? null,
			regexPressed:
				document
					.querySelector('[data-testid="bridge-review-regex-toggle"]')
					?.getAttribute('aria-pressed') ?? null,
			searchValue:
				document.querySelector<HTMLInputElement>('[data-testid="worktree-file-search-input"]')
					?.value ?? null,
		}),
	);
}

function worktreeFileControlsStateSnapshotsEqual(
	left: WorktreeFileControlsStateSnapshot,
	right: WorktreeFileControlsStateSnapshot,
): boolean {
	return (
		left.filterMenuText === right.filterMenuText &&
		left.filterStatusText === right.filterStatusText &&
		left.regexPressed === right.regexPressed &&
		left.searchValue === right.searchValue
	);
}

async function scrollContentPaneToNonzeroOffset(page: Page): Promise<void> {
	await page.evaluate((): void => {
		const contentPanel = window.bridgeWorktreeVerifier.getBridgeFileViewerScrollableContent();
		if (!(contentPanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File content pane before content scroll canary');
		}
		const targetScrollTop = Math.min(
			Math.max(contentPanel.scrollHeight - contentPanel.clientHeight, 0),
			480,
		);
		if (targetScrollTop <= 0) {
			throw new Error(
				`Expected Worktree/File content pane to reserve enough height to scroll, got ${contentPanel.scrollHeight}`,
			);
		}
		contentPanel.scrollTop = targetScrollTop;
	});
	await page.waitForFunction(
		(): boolean => {
			const contentPanel = window.bridgeWorktreeVerifier.getBridgeFileViewerScrollableContent();
			return contentPanel instanceof HTMLElement && contentPanel.scrollTop > 0;
		},
		{ timeout: 10_000 },
	);
}

async function readWorktreeFileTreeAnchorSnapshot(
	page: Page,
	path: string,
): Promise<WorktreeFileTreeAnchorSnapshot> {
	return await page.evaluate((targetPath: string): WorktreeFileTreeAnchorSnapshot => {
		const helpers = window.bridgeWorktreeVerifier;
		const scrollElement = helpers.getPierreFileTreeScrollElement();
		const anchor = helpers.getPierreFileTreeItem(targetPath);
		if (!(scrollElement instanceof HTMLElement) || !(anchor instanceof HTMLElement)) {
			throw new Error(`Expected Worktree/File anchor row for ${targetPath}`);
		}
		const treeRect = scrollElement.getBoundingClientRect();
		const anchorRect = anchor.getBoundingClientRect();
		const allButtons = helpers.getPierreFileTreeItems();
		const visibleButtons = allButtons.filter((candidate): candidate is HTMLElement => {
			const candidateRect = candidate.getBoundingClientRect();
			return candidateRect.bottom >= treeRect.top && candidateRect.top <= treeRect.bottom;
		});
		const visibleIndexes = visibleButtons.map((button) => allButtons.indexOf(button));
		return {
			anchorItemId: targetPath,
			anchorOffset: anchorRect.top - treeRect.top,
			measuredItemIds: visibleButtons.map((button) => button.dataset['itemPath'] ?? ''),
			scrollTop: scrollElement.scrollTop,
			visibleRange: {
				startIndex: Math.min(...visibleIndexes),
				endIndex: Math.max(...visibleIndexes),
			},
		};
	}, path);
}

async function readWorktreeFileScrollExtentSnapshot(
	page: Page,
): Promise<WorktreeFileScrollExtentSnapshot> {
	return await page.evaluate((): WorktreeFileScrollExtentSnapshot => {
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const helpers = window.bridgeWorktreeVerifier;
		const treeScrollElement = helpers.getPierreFileTreeScrollElement();
		const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const contentScrollElement = helpers.getBridgeFileViewerScrollableContent();
		if (!(treePanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File tree panel for extent canary');
		}
		if (!(treeScrollElement instanceof HTMLElement)) {
			throw new Error('Expected Pierre FileTree scroll element for extent canary');
		}
		if (!(contentPanel instanceof HTMLElement) || !(contentScrollElement instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File content panel for extent canary');
		}
		const contentDeclaredTotalSizeRaw = contentPanel.getAttribute(
			'data-worktree-open-file-total-size',
		);
		const contentDeclaredTotalSize =
			contentDeclaredTotalSizeRaw === null ? null : Number(contentDeclaredTotalSizeRaw);
		const treeDeclaredTotalSizeRaw = treePanel.getAttribute('data-worktree-tree-total-size');
		const treeDeclaredTotalSize =
			treeDeclaredTotalSizeRaw === null ? null : Number(treeDeclaredTotalSizeRaw);
		const treeDeclaredTotalSizeSourceRaw = treePanel.getAttribute(
			'data-worktree-tree-total-size-source',
		);
		const treeDeclaredTotalSizeSource =
			treeDeclaredTotalSizeSourceRaw === 'providerFacts' ||
			treeDeclaredTotalSizeSourceRaw === 'localProjection'
				? treeDeclaredTotalSizeSourceRaw
				: null;
		return {
			contentDeclaredTotalSizePixels:
				contentDeclaredTotalSize === null || Number.isFinite(contentDeclaredTotalSize)
					? contentDeclaredTotalSize
					: null,
			contentScrollClientHeight: contentScrollElement.clientHeight,
			contentScrollHeight: contentScrollElement.scrollHeight,
			contentScrollTop: contentScrollElement.scrollTop,
			treeDeclaredTotalSizePixels:
				treeDeclaredTotalSize === null || Number.isFinite(treeDeclaredTotalSize)
					? treeDeclaredTotalSize
					: null,
			treeDeclaredTotalSizeSource,
			treeScrollClientHeight: treeScrollElement.clientHeight,
			treeScrollHeight: treeScrollElement.scrollHeight,
			treeScrollTop: treeScrollElement.scrollTop,
		};
	});
}

function makeScrollExtentCanary(props: {
	readonly afterReady: WorktreeFileScrollExtentSnapshot;
	readonly afterSelection: WorktreeFileScrollExtentSnapshot;
	readonly beforeSelection: WorktreeFileScrollExtentSnapshot;
	readonly selectedAnchorPath: string;
	readonly treeAnchorAfterReady: WorktreeFileTreeAnchorSnapshot;
	readonly treeAnchorBeforeSelection: WorktreeFileTreeAnchorSnapshot;
}): WorktreeFileScrollExtentCanary {
	const treeAnchorOffsetDelta =
		props.treeAnchorAfterReady.anchorOffset - props.treeAnchorBeforeSelection.anchorOffset;
	const contentScrollTopDelta = Math.abs(
		props.afterReady.contentScrollTop - props.afterSelection.contentScrollTop,
	);
	const contentScrollTopDriftTolerancePixels = defaultFileLineHeightPixels * 4;
	return {
		contentDeclaredTotalSizePixelsAfterReady: props.afterReady.contentDeclaredTotalSizePixels,
		contentDeclaredTotalSizePixelsAfterSelection:
			props.afterSelection.contentDeclaredTotalSizePixels,
		contentHeightDeltaPixels:
			props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight,
		contentScrollClientHeightAfterReady: props.afterReady.contentScrollClientHeight,
		contentScrollClientHeightAfterSelection: props.afterSelection.contentScrollClientHeight,
		contentScrollHeightAfterReady: props.afterReady.contentScrollHeight,
		contentScrollHeightAfterSelection: props.afterSelection.contentScrollHeight,
		contentScrollTopAfterReady: props.afterReady.contentScrollTop,
		contentScrollTopAfterSelection: props.afterSelection.contentScrollTop,
		contentScrollTopDeltaPixels: contentScrollTopDelta,
		exactSizeTolerancePass:
			Math.abs(props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight) <=
			1,
		stableAnchorPass:
			Math.abs(treeAnchorOffsetDelta) <= 1 &&
			Math.abs(props.treeAnchorAfterReady.scrollTop - props.treeAnchorBeforeSelection.scrollTop) <=
				1 &&
			contentScrollTopDelta <= contentScrollTopDriftTolerancePixels,
		stableAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffset: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIds: props.treeAnchorBeforeSelection.measuredItemIds,
			reconciliationReason: 'exactLineCount',
			scrollHeightAfter: props.afterReady.contentScrollHeight,
			scrollHeightBefore: props.afterSelection.contentScrollHeight,
			scrollTopAfter: props.afterReady.contentScrollTop,
			scrollTopBefore: props.afterSelection.contentScrollTop,
			scrollTopDeltaPixels: contentScrollTopDelta,
			totalContentHeightAfter: props.afterReady.contentDeclaredTotalSizePixels,
			totalContentHeightBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeAfter: props.afterReady.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			visibleRange: {
				endIndex: Math.ceil(
					(props.afterReady.contentScrollTop + props.afterReady.contentScrollClientHeight) /
						defaultFileLineHeightPixels,
				),
				startIndex: Math.floor(props.afterReady.contentScrollTop / defaultFileLineHeightPixels),
			},
		},
		selectedAnchorPath: props.selectedAnchorPath,
		treeAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffsetAfterReady: props.treeAnchorAfterReady.anchorOffset,
			anchorOffsetBeforeSelection: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIdsAfterReady: props.treeAnchorAfterReady.measuredItemIds,
			measuredItemIdsBeforeSelection: props.treeAnchorBeforeSelection.measuredItemIds,
			scrollTopAfterReady: props.treeAnchorAfterReady.scrollTop,
			scrollTopBeforeSelection: props.treeAnchorBeforeSelection.scrollTop,
			visibleRangeAfterReady: props.treeAnchorAfterReady.visibleRange,
			visibleRangeBeforeSelection: props.treeAnchorBeforeSelection.visibleRange,
		},
		treeDeclaredTotalSizePixels: props.afterReady.treeDeclaredTotalSizePixels,
		treeDeclaredTotalSizeSource: props.afterReady.treeDeclaredTotalSizeSource,
		treeHeightDeltaPixels:
			props.afterReady.treeScrollHeight - props.beforeSelection.treeScrollHeight,
		treeScrollClientHeightAfterReady: props.afterReady.treeScrollClientHeight,
		treeScrollHeightAfterReady: props.afterReady.treeScrollHeight,
		treeScrollHeightBeforeSelection: props.beforeSelection.treeScrollHeight,
		treeScrollTopAfterReady: props.afterReady.treeScrollTop,
		treeScrollTopBeforeSelection: props.beforeSelection.treeScrollTop,
	};
}

function assertWorktreeScrollExtentCanary(canary: WorktreeFileScrollExtentCanary): void {
	if (canary.treeDeclaredTotalSizePixels === null || canary.treeDeclaredTotalSizePixels <= 0) {
		throw new Error('Expected Worktree/File tree declared extent in scroll canary');
	}
	if (canary.treeDeclaredTotalSizeSource !== 'providerFacts') {
		throw new Error(
			`Expected Worktree/File tree declared extent source to be providerFacts: ${JSON.stringify(canary)}`,
		);
	}
	if (Math.abs(canary.treeScrollHeightAfterReady - canary.treeDeclaredTotalSizePixels) > 1) {
		throw new Error(
			`Expected Worktree/File tree scroll extent near declared size: ${JSON.stringify(canary)}`,
		);
	}
	if (
		canary.contentDeclaredTotalSizePixelsAfterSelection === null ||
		canary.contentDeclaredTotalSizePixelsAfterReady === null
	) {
		throw new Error('Expected Worktree/File content declared extent in scroll canary');
	}
	if (
		canary.contentDeclaredTotalSizePixelsAfterSelection !==
		canary.contentDeclaredTotalSizePixelsAfterReady
	) {
		throw new Error(
			`Expected Worktree/File declared content extent to stay stable: ${JSON.stringify(canary)}`,
		);
	}
	if (Math.abs(canary.treeHeightDeltaPixels) > 1) {
		throw new Error(
			`Expected Worktree/File tree hydration to keep scroll extent bounded: ${JSON.stringify(canary)}`,
		);
	}
	if (canary.treeScrollTopBeforeSelection <= 0 || canary.treeScrollTopAfterReady <= 0) {
		throw new Error(
			`Expected Worktree/File tree canary to exercise non-zero scroll: ${JSON.stringify(canary)}`,
		);
	}
	if (Math.abs(canary.contentHeightDeltaPixels) > 1) {
		throw new Error(
			`Expected Worktree/File content hydration to keep scroll extent bounded: ${JSON.stringify(canary)}`,
		);
	}
	if (canary.contentScrollTopAfterSelection <= 0 || canary.contentScrollTopAfterReady <= 0) {
		throw new Error(
			`Expected Worktree/File content canary to exercise non-zero scroll: ${JSON.stringify(canary)}`,
		);
	}
	if (!canary.stableAnchorPass || !canary.exactSizeTolerancePass) {
		throw new Error(`Expected Worktree/File scroll extent pass readout: ${JSON.stringify(canary)}`);
	}
}

async function readWorktreeFileVisibleAppProof(page: Page): Promise<WorktreeFileVisibleAppProof> {
	return await page.evaluate((): WorktreeFileVisibleAppProof => {
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Runs inside the Playwright page context.
		const visibleRectForPageElement = (element: HTMLElement): WorktreeFileVisibleRect => {
			const rect = element.getBoundingClientRect();
			return {
				height: rect.height,
				width: rect.width,
			};
		};
		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const treePane = document.querySelector('[data-testid="bridge-file-viewer-sidebar"]');
		const contentPane = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const filterCount = document.querySelector('[data-testid="worktree-file-filter-count"]');
		const sourceProvenance = document.querySelector('[data-testid="worktree-file-provenance"]');
		if (!(appRoot instanceof HTMLElement)) {
			throw new Error('Expected visible shared Bridge app root');
		}
		if (!(shell instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer shell');
		}
		if (!(treePane instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer tree pane');
		}
		if (!(contentPane instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer content pane');
		}
		if (!(filterCount instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File filter count element');
		}
		if (!(sourceProvenance instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File provenance element');
		}
		const helpers = window.bridgeWorktreeVerifier;
		const sampledRows = helpers.getPierreFileTreeItems().slice(0, 24);
		const sampledRowTops = sampledRows.map((row) => Math.round(row.getBoundingClientRect().top));
		const distinctSampledRowTops = new Set(sampledRowTops);
		const outsideIntentionalUi = document.body.cloneNode(true);
		if (!(outsideIntentionalUi instanceof HTMLElement)) {
			throw new Error('Expected cloneable page body');
		}
		outsideIntentionalUi
			.querySelectorAll(
				'[data-testid="bridge-file-viewer-sidebar"], [data-testid="bridge-file-viewer-code-canvas"]',
			)
			.forEach((node) => {
				node.remove();
			});
		const outsideText = outsideIntentionalUi.textContent ?? '';
		const shellStyle = window.getComputedStyle(shell);
		const contentRect = contentPane.getBoundingClientRect();
		const treeRect = treePane.getBoundingClientRect();
		const isMeaningfullyVisible = (element: HTMLElement): boolean => {
			const rect = element.getBoundingClientRect();
			const style = window.getComputedStyle(element);
			return (
				style.display !== 'none' &&
				style.visibility !== 'hidden' &&
				rect.width > 2 &&
				rect.height > 2 &&
				element.getClientRects().length > 0
			);
		};
		return {
			appRootRect: visibleRectForPageElement(appRoot),
			contentPaneRect: visibleRectForPageElement(contentPane),
			contentVisibleLineCount: helpers.getBridgeFileViewerRenderedCodeLineCount(),
			cssLayoutApplied:
				shellStyle.display === 'flex' &&
				shell.getAttribute('data-sidebar-position') === 'right' &&
				contentRect.left < treeRect.left,
			filterMenuCount: shell.querySelectorAll('[data-testid="worktree-file-filter-menu"]').length,
			filterCountMeaningfullyVisible: isMeaningfullyVisible(filterCount),
			filterCountText: filterCount.textContent ?? '',
			forbiddenTextAbsentOutsideIntentionalUi:
				!outsideText.includes('"frames"') &&
				!outsideText.includes('frameKind') &&
				!outsideText.includes('resourceUrl') &&
				!outsideText.includes('agentstudio://resource/') &&
				!outsideText.includes('BridgeWeb/src/'),
			regexToggleCount: shell.querySelectorAll('[data-testid="bridge-review-regex-toggle"]').length,
			sourceProvenanceMeaningfullyVisible: isMeaningfullyVisible(sourceProvenance),
			sourceProvenanceText: sourceProvenance.textContent ?? '',
			sampledTreeRowCount: sampledRows.length,
			sampledTreeRowsHaveDistinctVerticalPositions:
				sampledRows.length >= 8 && distinctSampledRowTops.size === sampledRows.length,
			searchControlCount: shell.querySelectorAll('[data-testid="bridge-review-search-control"]')
				.length,
			searchInputCount: shell.querySelectorAll('[data-testid="worktree-file-search-input"]').length,
			sharedRailToolbarCount: shell.querySelectorAll(
				'[data-testid="bridge-file-viewer-rail-toolbar"]',
			).length,
			sharedRailToolbarUsesSharedAttr:
				shell
					.querySelector('[data-testid="bridge-file-viewer-rail-toolbar"]')
					?.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
			sourceBaseRef: shell.getAttribute('data-worktree-base-ref'),
			sourceCursor: shell.getAttribute('data-worktree-source-cursor'),
			sourceId: shell.getAttribute('data-worktree-source-id'),
			sourceScenarioName: shell.getAttribute('data-worktree-scenario'),
			sourceState: shell.getAttribute('data-worktree-source-state'),
			treePaneRect: visibleRectForPageElement(treePane),
			worktreeRootToken: shell.getAttribute('data-worktree-root-token'),
		};
	});
}

function assertWorktreeFileVisibleAppProof(props: {
	readonly expectedSourceBaseRef: string;
	readonly expectedSourceCursor: string;
	readonly expectedSourceId: string;
	readonly expectedSourceScenarioName: string;
	readonly expectedWorktreeRootToken: string;
	readonly proof: WorktreeFileVisibleAppProof;
}): void {
	const proof = props.proof;
	assertVisibleRect('Worktree/File app root', proof.appRootRect);
	assertVisibleRect('Worktree/File tree pane', proof.treePaneRect);
	assertVisibleRect('Worktree/File content pane', proof.contentPaneRect);
	if (!proof.cssLayoutApplied) {
		throw new Error(`Expected Worktree/File packaged CSS layout proof: ${JSON.stringify(proof)}`);
	}
	if (proof.sharedRailToolbarCount !== 1 || !proof.sharedRailToolbarUsesSharedAttr) {
		throw new Error(`Expected Worktree/File shared rail toolbar: ${JSON.stringify(proof)}`);
	}
	if (proof.searchControlCount !== 1) {
		throw new Error(`Expected Worktree/File shared search control: ${JSON.stringify(proof)}`);
	}
	if (proof.searchInputCount !== 0) {
		throw new Error(
			`Expected Worktree/File search input to start closed: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.regexToggleCount !== 1) {
		throw new Error(`Expected Worktree/File shared regex toggle: ${JSON.stringify(proof)}`);
	}
	if (proof.filterMenuCount !== 1) {
		throw new Error(`Expected Worktree/File shadcn filter menu: ${JSON.stringify(proof)}`);
	}
	if (proof.filterCountMeaningfullyVisible || proof.sourceProvenanceMeaningfullyVisible) {
		throw new Error(
			`Expected Worktree/File rail metadata to stay non-visible: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.sampledTreeRowsHaveDistinctVerticalPositions) {
		throw new Error(
			`Expected Worktree/File tree rows to occupy distinct rows: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.contentVisibleLineCount <= 1) {
		throw new Error(
			`Expected Worktree/File selected content to preserve line structure: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.forbiddenTextAbsentOutsideIntentionalUi) {
		throw new Error(
			`Expected no raw Worktree/File payload text outside intended UI: ${JSON.stringify(proof)}`,
		);
	}
	if (
		proof.sourceBaseRef !== props.expectedSourceBaseRef ||
		proof.sourceCursor !== props.expectedSourceCursor ||
		proof.sourceId !== props.expectedSourceId ||
		!proof.filterCountText.includes('/') ||
		proof.sourceProvenanceText !== props.expectedSourceId ||
		proof.sourceScenarioName !== props.expectedSourceScenarioName ||
		proof.sourceState !== 'live' ||
		proof.worktreeRootToken !== props.expectedWorktreeRootToken
	) {
		throw new Error(
			`Expected page-visible Worktree/File source provenance: ${JSON.stringify(proof)}`,
		);
	}
}

function assertVisibleRect(label: string, rect: WorktreeFileVisibleRect): void {
	if (rect.width <= 0 || rect.height <= 0) {
		throw new Error(`Expected visible ${label} rect: ${JSON.stringify(rect)}`);
	}
}

async function verifyWorktreeFileProductControls(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly page: Page;
	readonly targetPath: string;
}): Promise<WorktreeFileProductControlsProof> {
	const expectedFetchableFilterCount = props.descriptors.filter((descriptor) =>
		isFetchableWorktreeFileDescriptor(descriptor),
	).length;
	const expectedUnavailableFilterCount = props.descriptors.filter((descriptor) =>
		isUnavailableWorktreeFileDescriptor(descriptor),
	).length;
	const fetchablePathSet = new Set(
		props.descriptors
			.filter((descriptor) => isFetchableWorktreeFileDescriptor(descriptor))
			.map((descriptor) => descriptor.path),
	);
	const fetchablePaths = [...fetchablePathSet];
	const unavailablePathSet = new Set(
		props.descriptors
			.filter((descriptor) => isUnavailableWorktreeFileDescriptor(descriptor))
			.map((descriptor) => descriptor.path),
	);
	const unavailablePaths = [...unavailablePathSet];
	const expectedUnavailableDescriptor = props.descriptors.find(
		(descriptor) => descriptor.path === unavailableFilterFixtureRelativePath,
	);
	if (expectedUnavailableDescriptor === undefined) {
		throw new Error(
			`Expected unavailable filter fixture descriptor ${unavailableFilterFixtureRelativePath}`,
		);
	}
	const expectedSearchTreeSizePixels = projectedTreeSizePixels([props.targetPath]);
	const expectedRegexTreeSizePixels = projectedTreeSizePixels([props.targetPath]);
	const expectedInvalidRegexTreeSizePixels = projectedTreeSizePixels([]);
	const expectedFetchableTreeSizePixels =
		fetchablePaths.length === props.descriptors.length
			? null
			: projectedTreeSizePixels(fetchablePaths);
	const expectedUnavailableTreeSizePixels = projectedTreeSizePixels(unavailablePaths);
	const initialVisibleCount = await visibleWorktreeFileRowCount(props.page);
	const initialRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const initialTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, props.targetPath);
	await waitForWorktreeFileFilterStatus(props.page, 1, props.descriptors.length);
	await waitForWorktreeRenderedFilePathSample(props.page, [props.targetPath]);
	const searchStatusText = await worktreeFileFilterStatusText(props.page);
	const searchResultIncludesTarget = await worktreeFileRowExists(props.page, props.targetPath);
	const searchRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const searchTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const searchTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const searchChromeProof = await readWorktreeFileSearchChromeProof(props.page);
	const searchScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-search-result.png',
		page: props.page,
	});
	await clickWorktreeFileControl(props.page, 'bridge-review-regex-toggle');
	await fillWorktreeFileSearch(props.page, `^${escapeRegExp(props.targetPath)}$`);
	await waitForWorktreeFileFilterStatus(props.page, 1, props.descriptors.length);
	const regexModeActive = await worktreeFileControlPressed(
		props.page,
		'bridge-review-regex-toggle',
	);
	const regexVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	await waitForWorktreeRenderedFilePathSample(props.page, [props.targetPath]);
	const regexRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const regexTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const regexTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, '(');
	await waitForWorktreeFileInvalidRegexStatus(props.page);
	const invalidRegexModeActive = await worktreeFileControlPressed(
		props.page,
		'bridge-review-regex-toggle',
	);
	const invalidRegexStatusText = await worktreeFileFilterStatusText(props.page);
	const invalidRegexRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const invalidRegexTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const invalidRegexTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, '');
	await waitForWorktreeFileFilterStatus(
		props.page,
		props.descriptors.length,
		props.descriptors.length,
	);
	await selectWorktreeFileFilter(props.page, 'Text files');
	await waitForWorktreeFileFilterStatus(
		props.page,
		expectedFetchableFilterCount,
		props.descriptors.length,
	);
	const fetchableFilterActive = await worktreeFileFilterMenuContains(props.page, 'Text');
	const fetchableFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	const fetchableRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const fetchableTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const fetchableTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await selectWorktreeFileFilter(props.page, 'Unavailable files');
	await waitForWorktreeFileFilterStatus(
		props.page,
		expectedUnavailableFilterCount,
		props.descriptors.length,
	);
	const unavailableFilterActive = await worktreeFileFilterMenuContains(props.page, 'Unavailable');
	const unavailableFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	await scrollTreeToFilePath(props.page, unavailableFilterFixtureRelativePath);
	await waitForPierreFileTreeAnchorSettled(props.page, unavailableFilterFixtureRelativePath);
	const unavailableRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const unavailableTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const unavailableTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const unavailableOpenProof = await verifyUnavailableWorktreeFileOpen({
		descriptor: expectedUnavailableDescriptor,
		page: props.page,
	});
	await selectWorktreeFileFilter(props.page, 'All files');
	await fillWorktreeFileSearch(props.page, '');
	await waitForWorktreeFileFilterStatus(
		props.page,
		props.descriptors.length,
		props.descriptors.length,
	);
	const allFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	const allRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const allTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const allTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const proof: WorktreeFileProductControlsProof = {
		allFilterVisibleCount,
		allRenderedPathSample,
		allTreeSizePixels,
		allTreeSizeSource,
		expectedFetchableFilterCount,
		expectedFetchableTreeSizePixels,
		expectedInvalidRegexTreeSizePixels,
		expectedRegexTreeSizePixels,
		expectedSearchTreeSizePixels,
		expectedUnavailableTreeSizePixels,
		expectedUnavailableFilterCount,
		expectedUnavailablePath: unavailableFilterFixtureRelativePath,
		fetchableFilterActive,
		fetchableFilterVisibleCount,
		fetchableRenderedPathSample,
		fetchableTreeSizePixels,
		fetchableTreeSizeSource,
		initialVisibleCount,
		initialRenderedPathSample,
		initialTreeSizeSource,
		invalidRegexModeActive,
		invalidRegexRenderedPathSample,
		invalidRegexStatusText,
		invalidRegexTreeSizePixels,
		invalidRegexTreeSizeSource,
		regexModeActive,
		regexVisibleCount,
		regexRenderedPathSample,
		regexTreeSizePixels,
		regexTreeSizeSource,
		searchScreenshotPath,
		searchChromeProof,
		searchResultIncludesTarget,
		searchRenderedPathSample,
		searchStatusText,
		searchTreeSizePixels,
		searchTreeSizeSource,
		searchVisibleCount: searchRenderedPathSample.length,
		targetPath: props.targetPath,
		totalDescriptorCount: props.descriptors.length,
		unavailableFilterActive,
		unavailableFilterVisibleCount,
		unavailableOpenProof,
		unavailableRenderedPathSample,
		unavailableTreeSizePixels,
		unavailableTreeSizeSource,
	};
	assertWorktreeFileProductControlsProof({
		fetchablePathSet,
		proof,
		unavailablePathSet,
	});
	return proof;
}

function isFetchableWorktreeFileDescriptor(descriptor: WorktreeFileDescriptor): boolean {
	return descriptor['isBinary'] !== true && descriptor['virtualizedExtentKind'] !== 'unavailable';
}

function isUnavailableWorktreeFileDescriptor(descriptor: WorktreeFileDescriptor): boolean {
	return descriptor['isBinary'] === true || descriptor['virtualizedExtentKind'] === 'unavailable';
}

async function verifyUnavailableWorktreeFileOpen(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly page: Page;
}): Promise<WorktreeFileUnavailableOpenProof> {
	const unavailableGate = makeDeferred<void>();
	unavailableGate.resolve();
	const unavailableRouteProbe = await installFileContentRouteGate({
		gate: unavailableGate,
		page: props.page,
	});
	let renderedState: WorktreeRenderedContentState;
	try {
		await clickWorktreeFilePath(props.page, props.descriptor.path);
		await waitForWorktreeOpenFileState({
			page: props.page,
			path: props.descriptor.path,
			state: 'unavailable',
		});
		renderedState = await readWorktreeRenderedContentState(props.page);
	} finally {
		await unavailableRouteProbe.dispose();
	}
	const proof: WorktreeFileUnavailableOpenProof = {
		contentRouteHitCount: unavailableRouteProbe.hitCount(),
		expectedContentHandle: props.descriptor.contentHandle,
		foreignContentRouteHitCount: unavailableRouteProbe.foreignHitCount(),
		foreignContentRouteHitUrls: unavailableRouteProbe.foreignHitUrls(),
		openedPath: props.descriptor.path,
		selectedContentState: renderedState.selectedContentState,
		selectedLineCount: renderedState.selectedLineCount,
	};
	if (
		proof.contentRouteHitCount !== 0 ||
		proof.foreignContentRouteHitCount !== 0 ||
		proof.selectedContentState !== 'unavailable' ||
		proof.selectedLineCount !== 0
	) {
		throw new Error(
			`Expected unavailable Worktree/File descriptor to open metadata-only without fetching body: ${JSON.stringify(proof)}`,
		);
	}
	return proof;
}

async function verifyWorktreeFileStaleRefresh(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly fixture: WorktreeFileStaleRefreshFixture;
	readonly page: Page;
}): Promise<WorktreeFileStaleRefreshProof> {
	await fillWorktreeFileSearch(props.page, props.fixture.relativePath);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	await clickWorktreeFilePath(props.page, props.fixture.relativePath);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	await assertWorktreeVisibleContentText({
		expectedText: props.fixture.initialContent,
		label: 'initial stale-refresh proof content',
		page: props.page,
	});
	await writeFile(props.fixture.absolutePath, props.fixture.updatedContent);
	const replacementSurface = await fetchWorktreeSurface();
	const replacementDescriptor = worktreeFileDescriptors(replacementSurface.frames).find(
		(candidate) => candidate.path === props.fixture.relativePath,
	);
	if (replacementDescriptor === undefined) {
		throw new Error(
			`Expected replacement descriptor for stale-refresh proof path ${props.fixture.relativePath}`,
		);
	}
	if (replacementDescriptor.contentHandle === props.descriptor.contentHandle) {
		throw new Error(
			`Expected stale-refresh proof to use replacement content handle for ${props.fixture.relativePath}`,
		);
	}
	await dispatchWorktreeDevReload(props.page);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'stale',
	});
	await waitForWorktreeSourceCursor({
		page: props.page,
		sourceCursor: replacementSurface.source.sourceCursor,
	});
	const staleNotice = props.page.locator('[data-testid="worktree-file-content-stale"]');
	await staleNotice.getByText('Content changed').waitFor({ state: 'visible', timeout: 10_000 });
	const staleMessageRect = await staleNotice.boundingBox();
	if (staleMessageRect === null) {
		throw new Error('Expected visible Worktree/File stale notice bounding box');
	}
	const staleText = await worktreeVisibleContentText(props.page);
	const staleScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-stale-refresh.png',
		page: props.page,
	});
	const staleMessageVisible = await staleNotice.isVisible();
	const refreshGate = makeDeferred<void>();
	const refreshRouteProbe = await installFileContentRouteGate({
		failFirstHit: true,
		failFirstHitContentHandle: replacementDescriptor.contentHandle,
		gate: refreshGate,
		page: props.page,
	});
	refreshGate.resolve();
	const refreshFetchHitsBeforeClick = refreshRouteProbe.hitCount();
	await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
	await waitForRouteProbeHitCountAbove({
		minHitCount: refreshFetchHitsBeforeClick + 1,
		probe: refreshRouteProbe,
	});
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'stale',
	});
	const refreshFetchHitsAfterFirstClick = refreshRouteProbe.hitCount();
	await staleNotice.getByText('Content changed').waitFor({ state: 'visible', timeout: 10_000 });
	await waitForWorktreeRefreshButtonEnabled(props.page);
	await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
	await waitForRouteProbeHitCountAbove({
		minHitCount: refreshFetchHitsAfterFirstClick + 1,
		probe: refreshRouteProbe,
	});
	try {
		await waitForWorktreeOpenFileState({
			page: props.page,
			path: props.fixture.relativePath,
			state: 'ready',
		});
	} catch (error) {
		throw new Error(
			`Expected retry refresh to become ready after second click: ${JSON.stringify({
				hitCount: refreshRouteProbe.hitCount(),
				hitUrls: refreshRouteProbe.hitUrls(),
				replacementContentHandle: replacementDescriptor.contentHandle,
				replacementContentHash: replacementDescriptor.contentHash ?? null,
				replacementSourceCursor: replacementSurface.source.sourceCursor,
				proofPath: props.fixture.relativePath,
			})}`,
			{ cause: error },
		);
	}
	const refreshFetchHitsAfterSecondClick = refreshRouteProbe.hitCount();
	await refreshRouteProbe.dispose();
	const refreshedText = await waitForWorktreeVisibleContentText({
		expectedText: props.fixture.updatedContent,
		label: 'refreshed stale-refresh proof content',
		page: props.page,
	});
	const proof: WorktreeFileStaleRefreshProof = {
		failedRefreshReturnedStale: true,
		foreignContentRouteHitCount: refreshRouteProbe.foreignHitCount(),
		foreignContentRouteHitUrls: refreshRouteProbe.foreignHitUrls(),
		initialContentStillVisibleWhileStale: renderedTextIncludesContent(
			staleText,
			props.fixture.initialContent,
		),
		proofPath: props.descriptor.path,
		refreshFetchHitsAfterFirstClick,
		refreshFetchHitsAfterSecondClick,
		refreshFetchHitsBeforeClick,
		refreshEnteredRefreshing: true,
		refreshReturnedReady: true,
		refreshedContentVisible: renderedTextIncludesContent(
			refreshedText,
			props.fixture.updatedContent,
		),
		staleContentState: 'stale',
		staleMessageRect,
		staleMessageVisible,
		staleScreenshotPath,
	};
	assertWorktreeFileStaleRefreshProof(proof);
	return proof;
}

async function verifyWorktreeFileSplitResetReplacement(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly fixture: WorktreeFileStaleRefreshFixture;
	readonly page: Page;
}): Promise<WorktreeFileSplitResetReplacementProof> {
	await fillWorktreeFileSearch(props.page, props.fixture.relativePath);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	await clickWorktreeFilePath(props.page, props.fixture.relativePath);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	await assertWorktreeVisibleContentText({
		expectedText: props.fixture.initialContent,
		label: 'initial split-reset proof content',
		page: props.page,
	});
	await setWorktreeDevPollingEnabled({ enabled: false, page: props.page });
	try {
		await writeFile(props.fixture.absolutePath, props.fixture.updatedContent);
		const replacementSurface = await fetchWorktreeSurface();
		const replacementDescriptor = worktreeFileDescriptors(replacementSurface.frames).find(
			(candidate) => candidate.path === props.fixture.relativePath,
		);
		if (replacementDescriptor === undefined) {
			throw new Error(
				`Expected replacement descriptor for split-reset proof path ${props.fixture.relativePath}`,
			);
		}
		if (replacementDescriptor.contentHandle === props.descriptor.contentHandle) {
			throw new Error(
				`Expected split-reset proof to create a replacement content handle for ${props.fixture.relativePath}`,
			);
		}
		const refreshGate = makeDeferred<void>();
		refreshGate.resolve();
		const refreshRouteProbe = await installFileContentRouteGate({
			gate: refreshGate,
			page: props.page,
		});
		let staleText = '';
		let staleMessageVisible = false;
		try {
			const preDispatchContentRouteHitCount = refreshRouteProbe.hitCount();
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'ready',
			});
			await setWorktreeDevSplitResetReplacementDelay({
				delayMilliseconds: 250,
				page: props.page,
			});
			await dispatchWorktreeDevForceSplitResetReload(props.page);
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'stale',
			});
			const staleNotice = props.page.locator('[data-testid="worktree-file-content-stale"]');
			await staleNotice.getByText('Content changed').waitFor({ state: 'visible', timeout: 10_000 });
			const refreshDisabledAtFirstStale = await readWorktreeRefreshButtonDisabled(props.page);
			await waitForWorktreeDevForceSplitReloadDelivered({
				page: props.page,
				sourceCursor: replacementSurface.source.sourceCursor,
			});
			const devReloadProof = await readWorktreeDevReloadProof(props.page);
			await waitForWorktreeRefreshButtonEnabled(props.page);
			const refreshEnabledAfterReplacement = !(await readWorktreeRefreshButtonDisabled(props.page));
			staleMessageVisible = await staleNotice.isVisible();
			staleText = await worktreeVisibleContentText(props.page);
			const postReplacementContentRouteHitCount = refreshRouteProbe.hitCount();
			await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'refreshing',
			});
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'ready',
			});
			const postRefreshContentRouteHitCount = refreshRouteProbe.hitCount();
			const refreshedText = await waitForWorktreeVisibleContentText({
				expectedText: props.fixture.updatedContent,
				label: 'split-reset replacement proof content',
				page: props.page,
			});
			const hitUrls = refreshRouteProbe.hitUrls();
			const replacementContentRouteHitCount = hitUrls.filter((hitUrl) =>
				hitUrl.includes(encodeURIComponent(replacementDescriptor.contentHandle)),
			).length;
			const proof: WorktreeFileSplitResetReplacementProof = {
				devReloadFrameCount: devReloadProof.frameCount,
				devReloadFrameGenerations: devReloadProof.frameGenerations,
				devReloadFrameKinds: devReloadProof.frameKinds,
				devReloadFrameSequences: devReloadProof.frameSequences,
				devReloadFrameStreamIds: devReloadProof.frameStreamIds,
				devReloadRequest: devReloadProof.request,
				devReloadSourceCursor: devReloadProof.sourceCursor,
				devReloadStatus: devReloadProof.status,
				foreignContentRouteHitCount: refreshRouteProbe.foreignHitCount(),
				foreignContentRouteHitUrls: refreshRouteProbe.foreignHitUrls(),
				initialContentStillVisibleWhileStale: renderedTextIncludesContent(
					staleText,
					props.fixture.initialContent,
				),
				oldContentHandle: props.descriptor.contentHandle,
				postRefreshContentRouteHitCount,
				postReplacementContentRouteHitCount,
				preDispatchContentRouteHitCount,
				proofPath: props.fixture.relativePath,
				refreshDisabledAtFirstStale,
				refreshEnabledAfterReplacement,
				refreshedContentVisible: renderedTextIncludesContent(
					refreshedText,
					props.fixture.updatedContent,
				),
				replacementContentHandle: replacementDescriptor.contentHandle,
				replacementContentHash: replacementDescriptor.contentHash ?? null,
				replacementContentRouteHitCount,
				replacementSourceCursor: replacementSurface.source.sourceCursor,
				selectedContentStateAfterReset: 'stale',
				staleMessageVisible,
			};
			assertWorktreeFileSplitResetReplacementProof(proof);
			return proof;
		} finally {
			await setWorktreeDevSplitResetReplacementDelay({
				delayMilliseconds: null,
				page: props.page,
			});
			await refreshRouteProbe.dispose();
		}
	} finally {
		await setWorktreeDevPollingEnabled({ enabled: true, page: props.page });
	}
}

function assertWorktreeFileSplitResetReplacementProof(
	proof: WorktreeFileSplitResetReplacementProof,
): void {
	if (proof.proofPath.length === 0) {
		throw new Error(`Expected Worktree/File split-reset proof path: ${JSON.stringify(proof)}`);
	}
	if (
		proof.oldContentHandle === proof.replacementContentHandle ||
		proof.replacementContentHash === null ||
		proof.replacementSourceCursor.length === 0
	) {
		throw new Error(
			`Expected Worktree/File split reset to expose replacement metadata: ${JSON.stringify(proof)}`,
		);
	}
	if (
		!proof.initialContentStillVisibleWhileStale ||
		!proof.staleMessageVisible ||
		proof.selectedContentStateAfterReset !== 'stale' ||
		!proof.refreshDisabledAtFirstStale ||
		!proof.refreshEnabledAfterReplacement
	) {
		throw new Error(
			`Expected Worktree/File split reset to preserve stale body and disable refresh until replacement readiness: ${JSON.stringify(proof)}`,
		);
	}
	if (
		proof.foreignContentRouteHitCount !== 0 ||
		proof.preDispatchContentRouteHitCount !== 0 ||
		proof.postReplacementContentRouteHitCount !== 0 ||
		proof.postRefreshContentRouteHitCount !== 1 ||
		proof.replacementContentRouteHitCount !== 1 ||
		!proof.refreshedContentVisible
	) {
		throw new Error(
			`Expected Worktree/File split reset to fetch only the replacement content handle on explicit refresh: ${JSON.stringify(proof)}`,
		);
	}
	if (
		proof.devReloadRequest !== 'force-split-reset' ||
		proof.devReloadStatus !== 'delivered' ||
		proof.devReloadSourceCursor !== proof.replacementSourceCursor ||
		proof.devReloadFrameCount !== proof.devReloadFrameKinds.length ||
		proof.devReloadFrameCount !== proof.devReloadFrameSequences.length ||
		proof.devReloadFrameCount !== proof.devReloadFrameGenerations.length ||
		proof.devReloadFrameCount !== proof.devReloadFrameStreamIds.length ||
		proof.devReloadFrameKinds[0] !== 'worktree.reset' ||
		proof.devReloadFrameKinds[1] !== 'worktree.snapshot'
	) {
		throw new Error(
			`Expected Worktree/File split reset proof to use forced reset/snapshot lineage: ${JSON.stringify(proof)}`,
		);
	}
	if (!numberListIsStrictlyIncreasing(proof.devReloadFrameSequences)) {
		throw new Error(
			`Expected Worktree/File split reset frames to use increasing sequence lineage: ${JSON.stringify(proof)}`,
		);
	}
	if (!numberListUsesOneSafeInteger(proof.devReloadFrameGenerations)) {
		throw new Error(
			`Expected Worktree/File split reset frames to use one generation lineage: ${JSON.stringify(proof)}`,
		);
	}
	if (!stringListUsesOneValue(proof.devReloadFrameStreamIds)) {
		throw new Error(
			`Expected Worktree/File split reset frames to use one stream lineage: ${JSON.stringify(proof)}`,
		);
	}
}

function numberListIsStrictlyIncreasing(values: readonly number[]): boolean {
	for (let index = 1; index < values.length; index += 1) {
		const currentValue = values[index];
		const previousValue = values[index - 1];
		if (
			currentValue === undefined ||
			previousValue === undefined ||
			!Number.isSafeInteger(currentValue) ||
			!Number.isSafeInteger(previousValue) ||
			currentValue <= previousValue
		) {
			return false;
		}
	}
	return true;
}

function numberListUsesOneSafeInteger(values: readonly number[]): boolean {
	const firstValue = values[0];
	if (firstValue === undefined || !Number.isSafeInteger(firstValue)) {
		return false;
	}
	return values.every((value) => value === firstValue && Number.isSafeInteger(value));
}

function stringListUsesOneValue(values: readonly string[]): boolean {
	const firstValue = values[0];
	if (firstValue === undefined || firstValue.length === 0) {
		return false;
	}
	return values.every((value) => value === firstValue);
}

function assertWorktreeFileStaleRefreshProof(proof: WorktreeFileStaleRefreshProof): void {
	if (proof.proofPath.length === 0) {
		throw new Error(`Expected Worktree/File stale-refresh proof path: ${JSON.stringify(proof)}`);
	}
	if (
		!proof.initialContentStillVisibleWhileStale ||
		!proof.staleMessageVisible ||
		proof.staleContentState !== 'stale'
	) {
		throw new Error(`Expected Worktree/File stale state before refresh: ${JSON.stringify(proof)}`);
	}
	if (
		!proof.refreshEnteredRefreshing ||
		!proof.refreshReturnedReady ||
		!proof.refreshedContentVisible ||
		!proof.failedRefreshReturnedStale ||
		proof.foreignContentRouteHitCount !== 0 ||
		proof.refreshFetchHitsBeforeClick !== 0 ||
		proof.refreshFetchHitsAfterFirstClick !== 1 ||
		proof.refreshFetchHitsAfterSecondClick !== 2
	) {
		throw new Error(
			`Expected Worktree/File explicit refresh to render update: ${JSON.stringify(proof)}`,
		);
	}
}

async function captureWorktreeDevServerScreenshot(props: {
	readonly name: string;
	readonly page: Page;
}): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const screenshotPath = join(proofRunDirectoryPath, props.name);
	await props.page.screenshot({ fullPage: true, path: screenshotPath });
	return relative(repoRootPath, screenshotPath);
}

function assertWorktreeFileProductControlsProof(props: {
	readonly fetchablePathSet: ReadonlySet<string>;
	readonly proof: WorktreeFileProductControlsProof;
	readonly unavailablePathSet: ReadonlySet<string>;
}): void {
	const { proof } = props;
	if (proof.initialVisibleCount <= 1 || proof.initialRenderedPathSample.length <= 1) {
		throw new Error(
			`Expected Worktree/File initial tree to have multiple rows: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.initialTreeSizeSource !== 'providerFacts') {
		throw new Error(
			`Expected Worktree/File initial tree extent source to be providerFacts: ${JSON.stringify(proof)}`,
		);
	}
	if (
		!proof.searchResultIncludesTarget ||
		proof.searchVisibleCount !== 1 ||
		proof.searchRenderedPathSample.length !== 1 ||
		proof.searchRenderedPathSample[0] !== proof.targetPath
	) {
		throw new Error(
			`Expected Worktree/File search to isolate target path: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.searchStatusText !== `1/${proof.totalDescriptorCount}`) {
		throw new Error(
			`Expected Worktree/File search status to show result delta: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.searchTreeSizeSource !== 'localProjection') {
		throw new Error(
			`Expected Worktree/File search projection extent source to be localProjection: ${JSON.stringify(proof)}`,
		);
	}
	if (
		proof.searchChromeProof.searchInputHeight !== 24 ||
		!proof.searchChromeProof.searchInputContainedInRail ||
		proof.searchChromeProof.searchInputFontSize !== '11px' ||
		!proof.searchChromeProof.searchInputClassName.includes('h-6') ||
		!proof.searchChromeProof.searchInputClassName.includes('w-[calc(100%-1rem)]') ||
		!proof.searchChromeProof.searchInputClassName.includes('!text-[11px]') ||
		proof.searchChromeProof.searchToggleHeight !== 24 ||
		proof.searchChromeProof.searchToggleFontSize !== '11px' ||
		proof.searchChromeProof.regexToggleHeight !== 24 ||
		proof.searchChromeProof.regexToggleFontSize !== '11px'
	) {
		throw new Error(
			`Expected Worktree/File search chrome to match compact shared controls: ${JSON.stringify(proof)}`,
		);
	}
	assertWorktreeProjectedTreeSize({
		actualSizePixels: proof.searchTreeSizePixels,
		expectedSizePixels: proof.expectedSearchTreeSizePixels,
		label: 'search',
		proof,
	});
	if (
		!proof.regexModeActive ||
		proof.regexVisibleCount !== 1 ||
		proof.regexRenderedPathSample.length !== 1 ||
		proof.regexRenderedPathSample[0] !== proof.targetPath
	) {
		throw new Error(
			`Expected Worktree/File regex search to isolate target path: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.regexTreeSizeSource !== 'localProjection') {
		throw new Error(
			`Expected Worktree/File regex projection extent source to be localProjection: ${JSON.stringify(proof)}`,
		);
	}
	assertWorktreeProjectedTreeSize({
		actualSizePixels: proof.regexTreeSizePixels,
		expectedSizePixels: proof.expectedRegexTreeSizePixels,
		label: 'regex',
		proof,
	});
	if (
		!proof.invalidRegexModeActive ||
		proof.invalidRegexStatusText !== 'Invalid regex' ||
		proof.invalidRegexRenderedPathSample.length !== 0 ||
		proof.invalidRegexTreeSizeSource !== 'localProjection'
	) {
		throw new Error(
			`Expected Worktree/File invalid regex state to be visible and locally projected: ${JSON.stringify(proof)}`,
		);
	}
	assertWorktreeProjectedTreeSize({
		actualSizePixels: proof.invalidRegexTreeSizePixels,
		expectedSizePixels: proof.expectedInvalidRegexTreeSizePixels,
		label: 'invalid regex',
		proof,
	});
	if (
		!proof.fetchableFilterActive ||
		proof.fetchableFilterVisibleCount !== proof.expectedFetchableFilterCount ||
		proof.expectedFetchableTreeSizePixels === null ||
		proof.expectedFetchableFilterCount >= proof.totalDescriptorCount ||
		(proof.expectedFetchableFilterCount > 0 &&
			(proof.fetchableRenderedPathSample.length === 0 ||
				!proof.fetchableRenderedPathSample.every((path) => props.fetchablePathSet.has(path))))
	) {
		throw new Error(
			`Expected nontrivial Worktree/File fetchable filter count: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.fetchableTreeSizeSource !== 'localProjection') {
		throw new Error(
			`Expected Worktree/File fetchable projection extent source to be localProjection: ${JSON.stringify(proof)}`,
		);
	} else {
		assertWorktreeProjectedTreeSize({
			actualSizePixels: proof.fetchableTreeSizePixels,
			expectedSizePixels: proof.expectedFetchableTreeSizePixels,
			label: 'fetchable',
			proof,
		});
	}
	if (
		!proof.unavailableFilterActive ||
		proof.expectedUnavailableFilterCount <= 0 ||
		proof.unavailableFilterVisibleCount !== proof.expectedUnavailableFilterCount ||
		proof.unavailableRenderedPathSample.length === 0 ||
		!proof.unavailableRenderedPathSample.every((path) => props.unavailablePathSet.has(path)) ||
		!proof.unavailableRenderedPathSample.includes(proof.expectedUnavailablePath)
	) {
		throw new Error(
			`Expected nontrivial Worktree/File unavailable filter count: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.unavailableTreeSizeSource !== 'localProjection') {
		throw new Error(
			`Expected Worktree/File unavailable projection extent source to be localProjection: ${JSON.stringify(proof)}`,
		);
	}
	assertWorktreeProjectedTreeSize({
		actualSizePixels: proof.unavailableTreeSizePixels,
		expectedSizePixels: proof.expectedUnavailableTreeSizePixels,
		label: 'unavailable',
		proof,
	});
	if (
		proof.allFilterVisibleCount !== proof.totalDescriptorCount ||
		proof.allRenderedPathSample.length <= proof.searchRenderedPathSample.length
	) {
		throw new Error(
			`Expected Worktree/File all filter reset to restore visible rows: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.allTreeSizeSource !== 'providerFacts') {
		throw new Error(
			`Expected Worktree/File all reset extent source to be providerFacts: ${JSON.stringify(proof)}`,
		);
	}
}

function assertWorktreeProjectedTreeSize(props: {
	readonly actualSizePixels: number | null;
	readonly expectedSizePixels: number;
	readonly label: string;
	readonly proof: WorktreeFileProductControlsProof;
}): void {
	if (
		props.actualSizePixels === null ||
		Math.abs(props.actualSizePixels - props.expectedSizePixels) > 1
	) {
		throw new Error(
			`Expected Worktree/File ${props.label} tree extent to match flattened rendered rows: ${JSON.stringify(props.proof)}`,
		);
	}
}

async function fillWorktreeFileSearch(page: Page, value: string): Promise<void> {
	if ((await page.locator('[data-testid="worktree-file-search-input"]').count()) === 0) {
		await page.locator('[data-testid="bridge-review-search-toggle"]').click();
	}
	await page.locator('[data-testid="worktree-file-search-input"]').fill(value);
}

async function readWorktreeFileSearchChromeProof(
	page: Page,
): Promise<WorktreeFileSearchChromeProof> {
	return await page.evaluate((): WorktreeFileSearchChromeProof => {
		const searchInput = document.querySelector<HTMLInputElement>(
			'[data-testid="worktree-file-search-input"]',
		);
		const searchToggle = document.querySelector<HTMLElement>(
			'[data-testid="bridge-review-search-toggle"]',
		);
		const regexToggle = document.querySelector<HTMLElement>(
			'[data-testid="bridge-review-regex-toggle"]',
		);
		if (searchInput === null || searchToggle === null || regexToggle === null) {
			throw new Error('Expected Worktree/File search chrome to be mounted');
		}
		const searchInputStyle = getComputedStyle(searchInput);
		const searchToggleStyle = getComputedStyle(searchToggle);
		const regexToggleStyle = getComputedStyle(regexToggle);
		const searchInputRect = searchInput.getBoundingClientRect();
		const searchRailRect =
			document
				.querySelector<HTMLElement>('[data-testid="bridge-file-viewer-rail-toolbar"]')
				?.getBoundingClientRect() ?? searchInputRect;
		return {
			regexToggleFontSize: regexToggleStyle.fontSize,
			regexToggleHeight: Math.round(regexToggle.getBoundingClientRect().height),
			searchInputClassName: searchInput.className,
			searchInputContainedInRail:
				searchInputRect.left >= searchRailRect.left &&
				searchInputRect.right <= searchRailRect.right,
			searchInputFontSize: searchInputStyle.fontSize,
			searchInputHeight: Math.round(searchInputRect.height),
			searchInputLeft: Math.round(searchInputRect.left),
			searchInputRight: Math.round(searchInputRect.right),
			searchRailLeft: Math.round(searchRailRect.left),
			searchRailRight: Math.round(searchRailRect.right),
			searchToggleFontSize: searchToggleStyle.fontSize,
			searchToggleHeight: Math.round(searchToggle.getBoundingClientRect().height),
		};
	});
}

async function clickWorktreeFileControl(page: Page, testId: string): Promise<void> {
	await page.locator(`[data-testid="${testId}"]`).click();
}

async function selectWorktreeFileFilter(page: Page, label: string): Promise<void> {
	await page.locator('[data-testid="worktree-file-filter-menu"]').click();
	await page.waitForSelector('[data-testid="bridge-review-filter-option-label"]');
	const optionLocator = page
		.locator('[data-testid="bridge-review-filter-option"]')
		.filter({ hasText: label })
		.first();
	if ((await optionLocator.count()) === 0) {
		const availableLabels = await page
			.locator('[data-testid="bridge-review-filter-option-label"]')
			.allTextContents();
		throw new Error(
			`Expected Worktree/File filter option ${label}; available options: ${availableLabels.join(', ')}`,
		);
	}
	await optionLocator.click({ timeout: 2_000 });
	await dismissOpenBridgeMenus(page);
}

async function worktreeFileFilterMenuContains(page: Page, label: string): Promise<boolean> {
	return await page.evaluate((expectedLabel: string): boolean => {
		const trigger = document.querySelector('[data-testid="worktree-file-filter-menu"]');
		return trigger?.textContent?.includes(expectedLabel) ?? false;
	}, label);
}

async function visibleWorktreeFileRowCount(page: Page): Promise<number> {
	return await page.evaluate(
		(): number =>
			window.bridgeWorktreeVerifier
				.getPierreFileTreeItems()
				.filter((candidate) => candidate.dataset['itemType'] === 'file').length,
	);
}

async function visibleWorktreeFilePathSample(page: Page): Promise<readonly string[]> {
	return await page.evaluate((): readonly string[] =>
		window.bridgeWorktreeVerifier
			.getPierreFileTreeItems()
			.filter((candidate) => candidate.dataset['itemType'] === 'file')
			.map((candidate) => candidate.dataset['itemPath'] ?? '')
			.filter((path) => path.length > 0),
	);
}

async function waitForWorktreeRenderedFilePathSample(
	page: Page,
	expectedPaths: readonly string[],
): Promise<void> {
	await page.waitForFunction(
		(expected: readonly string[]): boolean => {
			const visiblePaths = window.bridgeWorktreeVerifier
				.getPierreFileTreeItems()
				.filter((candidate) => candidate.dataset['itemType'] === 'file')
				.map((candidate) => candidate.dataset['itemPath'] ?? '')
				.filter((path) => path.length > 0);
			return (
				visiblePaths.length === expected.length &&
				visiblePaths.every((path, index) => path === expected[index])
			);
		},
		expectedPaths,
		{ timeout: 10_000 },
	);
}

async function worktreeFileRowExists(page: Page, path: string): Promise<boolean> {
	return await page.evaluate(
		(targetPath: string): boolean =>
			window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath) !== null,
		path,
	);
}

async function worktreeFileControlPressed(page: Page, testId: string): Promise<boolean> {
	return await page.evaluate((targetTestId: string): boolean => {
		const control = document.querySelector(`[data-testid="${CSS.escape(targetTestId)}"]`);
		return control?.getAttribute('aria-pressed') === 'true';
	}, testId);
}

async function worktreeFileFilterStatusText(page: Page): Promise<string> {
	return await page.evaluate(
		(): string =>
			document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ?? '',
	);
}

async function waitForWorktreeFileInvalidRegexStatus(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean =>
			document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ===
			'Invalid regex',
		{ timeout: 10_000 },
	);
}

async function worktreeFileTreeTotalSizeSource(
	page: Page,
): Promise<WorktreeFileTreeExtentSource | null> {
	return await page.evaluate((): WorktreeFileTreeExtentSource | null => {
		const rawSource = document
			.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]')
			?.getAttribute('data-worktree-tree-total-size-source');
		return rawSource === 'providerFacts' || rawSource === 'localProjection' ? rawSource : null;
	});
}

async function worktreeFileTreeTotalSizePixels(page: Page): Promise<number | null> {
	return await page.evaluate((): number | null => {
		const rawSize = document
			.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]')
			?.getAttribute('data-worktree-tree-total-size');
		if (rawSize === undefined || rawSize === null) {
			return null;
		}
		const parsedSize = Number(rawSize);
		return Number.isFinite(parsedSize) ? parsedSize : null;
	});
}

function projectedTreeSizePixels(paths: readonly string[]): number {
	return (
		Math.max(1, countFlattenedWorktreeFileTreeRows(paths)) * bridgeFileViewerTreeRowHeightPixels
	);
}

async function waitForWorktreeFileFilterStatus(
	page: Page,
	visibleCount: number,
	totalCount: number | undefined,
): Promise<void> {
	await page.waitForFunction(
		(expected: { readonly totalCount?: number; readonly visibleCount: number }): boolean => {
			const statusText =
				document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ?? '';
			return expected.totalCount === undefined
				? statusText.startsWith(`${expected.visibleCount}/`)
				: statusText === `${expected.visibleCount}/${expected.totalCount}`;
		},
		totalCount === undefined ? { visibleCount } : { totalCount, visibleCount },
		{ timeout: 10_000 },
	);
}

async function worktreeFileFilterStatusVisibleCount(page: Page): Promise<number> {
	const statusText = await worktreeFileFilterStatusText(page);
	const visibleCountText = statusText.split('/')[0] ?? '';
	const visibleCount = Number(visibleCountText);
	if (!Number.isInteger(visibleCount) || visibleCount < 0) {
		throw new Error(`Expected Worktree/File status count, got ${statusText}`);
	}
	return visibleCount;
}

async function scrollPierreFileTreeUntilPathVisible(page: Page, path: string): Promise<void> {
	const foundWithoutScroll = await worktreeFileRowExists(page, path);
	if (foundWithoutScroll) {
		return;
	}
	for (let attempt = 0; attempt < 80; attempt += 1) {
		const didFind = await page.evaluate(
			(input: { readonly attempt: number; readonly path: string }): boolean => {
				const helpers = window.bridgeWorktreeVerifier;
				const scrollElement = helpers.getPierreFileTreeScrollElement();
				if (!(scrollElement instanceof HTMLElement)) {
					return false;
				}
				const maxScrollTop = Math.max(0, scrollElement.scrollHeight - scrollElement.clientHeight);
				const nextScrollTop =
					maxScrollTop === 0 ? 0 : Math.floor((maxScrollTop * input.attempt) / 79);
				scrollElement.scrollTop = nextScrollTop;
				return helpers.getPierreFileTreeItem(input.path) !== null;
			},
			{ attempt, path },
		);
		if (didFind) {
			return;
		}
		await page.waitForTimeout(25);
	}
	throw new Error(`Expected Pierre FileTree row for ${path}`);
}

async function waitForWorktreeOpenFileState(props: {
	readonly page: Page;
	readonly path: string;
	readonly state: 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(expected: { readonly path: string; readonly state: string }): boolean => {
				const contentPanel = document.querySelector(
					'[data-testid="bridge-file-viewer-code-canvas"]',
				);
				return (
					contentPanel?.getAttribute('data-worktree-open-file-path') === expected.path &&
					contentPanel?.getAttribute('data-worktree-open-file-state') === expected.state
				);
			},
			{ path: props.path, state: props.state },
			{ timeout: 20_000 },
		);
	} catch (error) {
		const debugState = await props.page.evaluate((targetPath: string) => {
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			return {
				currentPath: contentPanel?.getAttribute('data-worktree-open-file-path') ?? null,
				currentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
				filterStatus:
					document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ?? null,
				searchValue:
					document.querySelector<HTMLInputElement>('[data-testid="worktree-file-search-input"]')
						?.value ?? null,
				sourceCursor:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-worktree-source-cursor') ?? null,
				lastRefreshCommitState:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-last-refresh-commit-state') ?? null,
				lastRefreshCurrentRequestId:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-last-refresh-current-request-id') ?? null,
				lastRefreshDescriptorId:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-last-refresh-descriptor-id') ?? null,
				lastRefreshRequestId:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-last-refresh-request-id') ?? null,
				lastRefreshResult:
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-last-refresh-result') ?? null,
				devReloadFrameCount:
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameCount'] ?? null,
				devReloadFrameKinds:
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameKinds'] ?? null,
				devReloadRequest:
					document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] ?? null,
				devReloadSourceCursor:
					document.documentElement.dataset['bridgeWorktreeDevLastReloadSourceCursor'] ?? null,
				devReloadStatus:
					document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] ?? null,
				forceSplitReloadFrameCount:
					document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameCount'] ??
					null,
				forceSplitReloadFrameKinds:
					document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'] ??
					null,
				forceSplitReloadSourceCursor:
					document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] ??
					null,
				forceSplitReloadStatus:
					document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] ?? null,
				targetPath,
				targetTreeRowExists:
					window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath) !== null,
				visiblePathSample: window.bridgeWorktreeVerifier
					.getPierreFileTreeItems()
					.slice(0, 8)
					.map((candidate) => candidate.dataset['itemPath'] ?? ''),
			};
		}, props.path);
		throw new Error(
			`Timed out waiting for Worktree/File open state ${props.state} for ${props.path}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

async function verifyWorktreeFileToReviewHandoff(): Promise<WorktreeFileToReviewHandoffProof> {
	const page = await makeVerificationPage();
	const routeProbe = await installReviewRouteProbe(page);
	try {
		const expectedDisplayPath = fileToReviewHandoffFixtureRelativePath;
		const expectedReviewItemId = await fetchWorktreeReviewItemIdForDisplayPath(expectedDisplayPath);
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', { timeout: 30_000 });
		await clickWorktreeFilePathViaSearch({ page, path: expectedDisplayPath });
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			expectedDisplayPath,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		const beforeLocationHref = await page.evaluate(() => window.location.href);
		await clickWorktreeFileControl(page, 'worktree-file-open-review-comparison');
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
		await page.waitForFunction(
			(expected: { readonly itemId: string }): boolean => {
				const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				return (
					codePanel?.getAttribute('data-selected-item-id') === expected.itemId &&
					codePanel?.getAttribute('data-selected-materialized-item-type') === 'file'
				);
			},
			{ itemId: expectedReviewItemId },
			{ timeout: 30_000 },
		);
		const proof = await page.evaluate(() => {
			const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
			const appRoot = appRoots[0];
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const fileViewerShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			const optionalNumberAttribute = (
				element: Element | null,
				attributeName: string,
			): number | null => {
				if (!(element instanceof HTMLElement)) {
					return null;
				}
				const attributeValue = element.getAttribute(attributeName);
				if (attributeValue === null) {
					return null;
				}
				const parsedValue = Number(attributeValue);
				return Number.isFinite(parsedValue) ? parsedValue : null;
			};
			const fileViewerOpenLoadTelemetry: WorktreeFileOpenLoadTelemetryProof = {
				disposition:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-last-open-load-disposition')
						: null,
				durationMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-duration-ms',
				),
				estimatedBytes: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-estimated-bytes',
				),
				executorInFlightCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-after',
				),
				executorInFlightCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-before',
				),
				executorQueuedLoadCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-after',
				),
				executorQueuedLoadCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-before',
				),
				lane:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-last-open-load-lane')
						: null,
				schedulerQueuedIntentCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-after',
				),
				schedulerQueuedIntentCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-before',
				),
			};
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			return {
				afterLocationHref: window.location.href,
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				appRootCount: appRoots.length,
				fileContextButtonSelectedAfterSwitch: visibleContextButtonSelection(
					'bridge-viewer-context-file',
				),
				fileModeHostHiddenAfterSwitch:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				fileViewerShellCountAfterSwitch: document.querySelectorAll(
					'[data-testid="bridge-file-viewer-shell"]',
				).length,
				fileViewerShellHiddenAfterSwitch:
					fileViewerShell instanceof HTMLElement && fileViewerShell.closest('[hidden]') !== null,
				fileViewerOpenLoadTelemetry,
				fileViewerSelectedPathAfterSwitch:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-selected-display-path')
						: null,
				reviewContextButtonSelectedAfterSwitch: visibleContextButtonSelection(
					'bridge-viewer-context-review',
				),
				selectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				selectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
				selectedItemId:
					codePanel instanceof HTMLElement ? codePanel.getAttribute('data-selected-item-id') : null,
				selectedMaterializedFileLineCount:
					codePanel instanceof HTMLElement
						? Number(codePanel.getAttribute('data-selected-materialized-file-line-count') ?? '0')
						: 0,
				selectedMaterializedItemType:
					codePanel instanceof HTMLElement
						? codePanel.getAttribute('data-selected-materialized-item-type')
						: null,
				sharedShellMode:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				sharedShellOwner:
					appRoot instanceof HTMLElement
						? appRoot.getAttribute('data-bridge-viewer-shell-owner')
						: null,
				standaloneWorktreeFileAppCount: document.querySelectorAll(
					'[data-testid="worktree-file-app"]',
				).length,
			};
		});
		await page.click('[data-testid="bridge-viewer-context-file"]:visible');
		await page.waitForFunction(
			(expected: { readonly displayPath: string }): boolean => {
				const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
				const contentPanel = document.querySelector('[data-worktree-open-file-path]');
				return (
					appRoot?.getAttribute('data-bridge-viewer-mode') === 'file' &&
					contentPanel?.getAttribute('data-worktree-open-file-path') === expected.displayPath
				);
			},
			{ displayPath: expectedDisplayPath },
			{ timeout: 20_000 },
		);
		const returnToFileProof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const fileViewerShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			return {
				fileModeHostActiveAfterReturnToFile:
					fileModeHost instanceof HTMLElement
						? fileModeHost.getAttribute('data-bridge-viewer-mode-active')
						: null,
				fileModeHostHiddenAfterReturnToFile:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				fileViewerSelectedPathAfterReturnToFile:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-selected-display-path')
						: null,
				reviewModeAfterReturnToFile:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
			};
		});
		await page.click('[data-testid="bridge-viewer-context-review"]:visible');
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
		const returnToReviewProof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			return {
				fileModeHostActiveAfterReturnToReview:
					fileModeHost instanceof HTMLElement
						? fileModeHost.getAttribute('data-bridge-viewer-mode-active')
						: null,
				fileModeHostHiddenAfterReturnToReview:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				reviewContextButtonSelectedAfterReturnToReview: visibleContextButtonSelection(
					'bridge-viewer-context-review',
				),
				reviewModeAfterReturnToReview:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				reviewSelectedDisplayPathAfterReturnToReview:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
			};
		});
		const handoffProof = {
			...proof,
			...returnToFileProof,
			...returnToReviewProof,
			beforeLocationHref,
			expectedDisplayPath,
			expectedReviewItemId,
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewPackageRouteHitCount: routeProbe.packageHitCount(),
		} satisfies WorktreeFileToReviewHandoffProof;
		if (
			handoffProof.appRootCount !== 1 ||
			handoffProof.appOwner !== 'BridgeApp' ||
			handoffProof.beforeLocationHref !== worktreeDevServerUrl ||
			handoffProof.afterLocationHref !== worktreeDevServerUrl ||
			handoffProof.sharedShellMode !== 'review' ||
			handoffProof.sharedShellOwner !== 'BridgeViewerAppShell' ||
			handoffProof.fileContextButtonSelectedAfterSwitch !== 'false' ||
			handoffProof.reviewContextButtonSelectedAfterSwitch !== 'true' ||
			handoffProof.fileViewerShellCountAfterSwitch !== 1 ||
			!handoffProof.fileModeHostHiddenAfterSwitch ||
			!handoffProof.fileViewerShellHiddenAfterSwitch ||
			handoffProof.fileViewerOpenLoadTelemetry.disposition !== 'cold-loaded' ||
			handoffProof.fileViewerOpenLoadTelemetry.lane !== 'foreground' ||
			handoffProof.fileViewerOpenLoadTelemetry.durationMilliseconds === null ||
			handoffProof.fileViewerOpenLoadTelemetry.durationMilliseconds < 0 ||
			handoffProof.fileViewerOpenLoadTelemetry.estimatedBytes === null ||
			handoffProof.fileViewerOpenLoadTelemetry.estimatedBytes <= 0 ||
			handoffProof.fileViewerOpenLoadTelemetry.schedulerQueuedIntentCountAfter !== 0 ||
			handoffProof.fileViewerOpenLoadTelemetry.executorInFlightCountAfter !== 0 ||
			handoffProof.fileViewerOpenLoadTelemetry.executorQueuedLoadCountAfter !== 0 ||
			handoffProof.fileViewerSelectedPathAfterSwitch !== expectedDisplayPath ||
			handoffProof.reviewModeAfterReturnToFile !== 'file' ||
			handoffProof.fileModeHostActiveAfterReturnToFile !== 'true' ||
			handoffProof.fileModeHostHiddenAfterReturnToFile ||
			handoffProof.fileViewerSelectedPathAfterReturnToFile !== expectedDisplayPath ||
			handoffProof.reviewModeAfterReturnToReview !== 'review' ||
			handoffProof.fileModeHostActiveAfterReturnToReview !== 'false' ||
			!handoffProof.fileModeHostHiddenAfterReturnToReview ||
			handoffProof.reviewContextButtonSelectedAfterReturnToReview !== 'true' ||
			handoffProof.reviewSelectedDisplayPathAfterReturnToReview !== expectedDisplayPath ||
			handoffProof.selectedContentState !== 'ready' ||
			handoffProof.selectedDisplayPath !== expectedDisplayPath ||
			handoffProof.selectedItemId !== expectedReviewItemId ||
			handoffProof.selectedMaterializedItemType !== 'file' ||
			handoffProof.selectedMaterializedFileLineCount <= 0 ||
			handoffProof.standaloneWorktreeFileAppCount !== 0 ||
			handoffProof.reviewPackageRouteHitCount !== 1 ||
			handoffProof.reviewContentRouteHitCount <= 0
		) {
			throw new Error(
				`Expected FileViewer to hand off selected file to ReviewViewer inside one shared app: ${JSON.stringify(handoffProof)}`,
			);
		}
		return handoffProof;
	} finally {
		await routeProbe.dispose();
		await page.close();
	}
}

async function clickWorktreeFilePathViaSearch(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await dismissOpenBridgeMenus(props.page);
	const searchInputLocator = props.page
		.locator('[data-testid="worktree-file-search-input"]')
		.first();
	if (!(await searchInputLocator.isVisible())) {
		await clickWorktreeFileControl(props.page, 'bridge-review-search-toggle');
	}
	await searchInputLocator.waitFor({ state: 'visible', timeout: 10_000 });
	await searchInputLocator.fill(props.path);
	await props.page.waitForFunction(
		(path: string): boolean => window.bridgeWorktreeVerifier.getPierreFileTreeItem(path) !== null,
		props.path,
		{ timeout: 10_000 },
	);
	await clickWorktreeFilePath(props.page, props.path);
}

async function clickReviewTreeFilePathViaSearch(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<ReviewTreeSearchClickProof> {
	const reviewTreeContainerSelector =
		'[data-testid="bridge-review-trees-panel"] file-tree-container';
	const searchInputLocator = props.page
		.locator(`${reviewTreeContainerSelector} input[data-file-tree-search-input]`)
		.first();
	const searchContainerLocator = props.page
		.locator(`${reviewTreeContainerSelector} [data-file-tree-search-container][data-open="true"]`)
		.first();
	const targetRowLocator = props.page
		.locator(
			`${reviewTreeContainerSelector} button[data-item-path=${cssStringLiteral(
				props.path,
			)}][data-item-type="file"]:not([data-file-tree-sticky-row]):not([data-item-parked])`,
		)
		.first();

	await dismissOpenBridgeMenus(props.page);
	if (!(await searchInputLocator.isVisible())) {
		await props.page.locator('button[data-testid="bridge-review-search-toggle"]:visible').click();
	}
	await searchInputLocator.waitFor({ state: 'visible', timeout: 10_000 });
	await searchInputLocator.fill(props.path);
	await searchContainerLocator.waitFor({ state: 'visible', timeout: 10_000 });
	await targetRowLocator.waitFor({ state: 'attached', timeout: 10_000 });
	await targetRowLocator.scrollIntoViewIfNeeded({ timeout: 10_000 });
	await targetRowLocator.waitFor({ state: 'visible', timeout: 10_000 });

	const clickProof = await targetRowLocator.evaluate(
		(row: Element, targetPath: string): ReviewTreeSearchClickProof => {
			const rowRect = row.getBoundingClientRect();
			const rootNode = row.getRootNode();
			const queryRoot =
				rootNode instanceof Document || rootNode instanceof ShadowRoot ? rootNode : document;
			const searchInput = queryRoot.querySelector('input[data-file-tree-search-input]');
			const searchContainer = queryRoot.querySelector(
				'[data-file-tree-search-container][data-open="true"]',
			);
			return {
				clickedRowItemPath: row instanceof HTMLElement ? row.getAttribute('data-item-path') : null,
				clickedRowItemType: row instanceof HTMLElement ? row.getAttribute('data-item-type') : null,
				clickedRowVisible: rowRect.width > 0 && rowRect.height > 0,
				searchInputValue: searchInput instanceof HTMLInputElement ? searchInput.value : null,
				searchOpened: searchContainer instanceof HTMLElement,
				selectionMethod: 'playwright-review-tree-search-click',
				targetPath,
			};
		},
		props.path,
	);
	await targetRowLocator.click({ timeout: 10_000 });
	return clickProof;
}

async function waitForReviewSelectedContentState(props: {
	readonly displayPath: string;
	readonly page: Page;
	readonly state: 'failed' | 'loading' | 'ready';
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(expected: { readonly displayPath: string; readonly state: string }): boolean => {
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				return (
					reviewShell?.getAttribute('data-selected-display-path') === expected.displayPath &&
					reviewShell?.getAttribute('data-selected-content-state') === expected.state
				);
			},
			{ displayPath: props.displayPath, state: props.state },
			{ timeout: 30_000 },
		);
	} catch (error) {
		const debugState = await props.page.evaluate((targetPath: string) => {
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			return {
				currentDisplayPath: reviewShell?.getAttribute('data-selected-display-path') ?? null,
				currentState: reviewShell?.getAttribute('data-selected-content-state') ?? null,
				selectedItemId: codePanel?.getAttribute('data-selected-item-id') ?? null,
				targetPath,
			};
		}, props.displayPath);
		throw new Error(
			`Timed out waiting for Worktree/Review selected content ${props.state} for ${props.displayPath}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

async function waitForAnyReviewSelectedContentState(props: {
	readonly page: Page;
	readonly state: 'failed' | 'loading' | 'ready';
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(expectedState: string): boolean => {
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				const selectedDisplayPath = reviewShell?.getAttribute('data-selected-display-path') ?? null;
				return (
					selectedDisplayPath !== null &&
					reviewShell?.getAttribute('data-selected-content-state') === expectedState
				);
			},
			props.state,
			{ timeout: 30_000 },
		);
	} catch (error) {
		const debugState = await props.page.evaluate(() => {
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			return {
				currentDisplayPath: reviewShell?.getAttribute('data-selected-display-path') ?? null,
				currentState: reviewShell?.getAttribute('data-selected-content-state') ?? null,
				selectedItemId: codePanel?.getAttribute('data-selected-item-id') ?? null,
			};
		});
		throw new Error(
			`Timed out waiting for any Worktree/Review selected content ${props.state}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

async function waitForReviewRenderedSelection(props: {
	readonly expectedItemId: string;
	readonly expectedVisibleText: string;
	readonly page: Page;
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(expected: {
				readonly expectedItemId: string;
				readonly expectedVisibleText: string;
			}): boolean => {
				const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				const codeViewOverflow = codePanel?.getAttribute('data-bridge-code-view-overflow') ?? null;
				const selectedItemId = codePanel?.getAttribute('data-selected-item-id') ?? null;
				const selectedMaterializedItemType =
					codePanel?.getAttribute('data-selected-materialized-item-type') ?? null;
				const lightDomHeaders = [
					...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
				].filter(
					(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
				);
				const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
					(element: Element): readonly HTMLButtonElement[] =>
						[
							...(element.shadowRoot?.querySelectorAll(
								'[data-testid="bridge-code-view-header-collapse-button"]',
							) ?? []),
						].filter(
							(headerElement: Element): headerElement is HTMLButtonElement =>
								headerElement instanceof HTMLButtonElement,
						),
				);
				const selectedHeaderPresent = [...lightDomHeaders, ...shadowDomHeaders].some(
					(selectedHeader: HTMLButtonElement): boolean =>
						selectedHeader.dataset['bridgeCodeViewItemId'] === expected.expectedItemId,
				);
				const shadowText = [...document.querySelectorAll('diffs-container')]
					.map((element: Element): string => element.shadowRoot?.textContent ?? '')
					.join(' ');
				const visibleText = [
					codePanel instanceof HTMLElement ? (codePanel.textContent ?? '') : '',
					shadowText,
				].join(' ');
				return (
					codeViewOverflow === 'wrap' &&
					selectedItemId === expected.expectedItemId &&
					selectedHeaderPresent &&
					selectedMaterializedItemType === 'diff' &&
					visibleText.includes(expected.expectedVisibleText)
				);
			},
			{
				expectedItemId: props.expectedItemId,
				expectedVisibleText: props.expectedVisibleText,
			},
			{ timeout: 30_000 },
		);
	} catch (error) {
		const debugState = await readReviewRenderedSelectionSnapshot(props.page);
		throw new Error(
			`Timed out waiting for Review CodeView to render ${props.expectedItemId}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

async function readReviewRenderedSelectionSnapshot(
	page: Page,
): Promise<ReviewRenderedSelectionSnapshot> {
	return page.evaluate((): ReviewRenderedSelectionSnapshot => {
		const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		const codeViewOverflow = codePanel?.getAttribute('data-bridge-code-view-overflow') ?? null;
		const selectedItemId = codePanel?.getAttribute('data-selected-item-id') ?? null;
		const lightDomHeaders = [
			...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
		].filter(
			(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
		);
		const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
			(element: Element): readonly HTMLButtonElement[] =>
				[
					...(element.shadowRoot?.querySelectorAll(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					) ?? []),
				].filter(
					(headerElement: Element): headerElement is HTMLButtonElement =>
						headerElement instanceof HTMLButtonElement,
				),
		);
		const selectedHeaderPresent = [...lightDomHeaders, ...shadowDomHeaders].some(
			(selectedHeader: HTMLButtonElement): boolean =>
				selectedHeader.dataset['bridgeCodeViewItemId'] === selectedItemId,
		);
		const shadowText = [...document.querySelectorAll('diffs-container')]
			.map((element: Element): string => element.shadowRoot?.textContent ?? '')
			.join(' ');
		const visibleText = [
			codePanel instanceof HTMLElement ? (codePanel.textContent ?? '') : '',
			shadowText,
		].join(' ');
		return {
			codeViewOverflow,
			selectedHeaderPresent,
			selectedItemId,
			selectedMaterializedFileLineCount:
				codePanel instanceof HTMLElement
					? Number(codePanel.getAttribute('data-selected-materialized-file-line-count') ?? '0')
					: 0,
			selectedMaterializedItemType:
				codePanel?.getAttribute('data-selected-materialized-item-type') ?? null,
			visibleText,
		};
	});
}

async function readReviewCollapseControlProof(props: {
	readonly expectedItemId: string;
	readonly page: Page;
}): Promise<ReviewCollapseControlProof> {
	const candidates = await props.page.evaluate((): ReviewCollapseControlCandidate[] => {
		const lightDomHeaders = [
			...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
		].filter(
			(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
		);
		const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
			(element: Element): readonly HTMLButtonElement[] =>
				[
					...(element.shadowRoot?.querySelectorAll(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					) ?? []),
				].filter(
					(headerElement: Element): headerElement is HTMLButtonElement =>
						headerElement instanceof HTMLButtonElement,
				),
		);
		return [...lightDomHeaders, ...shadowDomHeaders].map(
			(selectedHeader: HTMLButtonElement): ReviewCollapseControlCandidate => {
				const selectedHeaderRect = selectedHeader.getBoundingClientRect();
				const selectedHeaderStyle = getComputedStyle(selectedHeader);
				return {
					proof: {
						ariaExpanded: selectedHeader.getAttribute('aria-expanded'),
						fontSize: selectedHeaderStyle.fontSize,
						height: selectedHeaderRect.height,
						itemId: selectedHeader.dataset['bridgeCodeViewItemId'] ?? null,
						present: true,
						primitiveSlot: selectedHeader.getAttribute('data-slot'),
					},
					visible: selectedHeader.getClientRects().length > 0,
				};
			},
		);
	});
	return selectVisibleReviewCollapseControlProof({
		candidates,
		expectedItemId: props.expectedItemId,
	});
}

async function waitForWorktreeSourceCursor(props: {
	readonly page: Page;
	readonly sourceCursor: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(expectedSourceCursor: string): boolean =>
			document
				.querySelector('[data-testid="bridge-file-viewer-shell"]')
				?.getAttribute('data-worktree-source-cursor') === expectedSourceCursor,
		props.sourceCursor,
		{ timeout: 20_000 },
	);
}

async function waitForWorktreeDevForceSplitReloadDelivered(props: {
	readonly page: Page;
	readonly sourceCursor: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(expectedSourceCursor: string): boolean =>
			document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] ===
				'force-split-reset' &&
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] ===
				'delivered' &&
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] ===
				expectedSourceCursor,
		props.sourceCursor,
		{ timeout: 20_000 },
	);
}

async function setWorktreeDevPollingEnabled(props: {
	readonly enabled: boolean;
	readonly page: Page;
}): Promise<void> {
	const eventType = props.enabled
		? 'bridge-worktree-dev-resume-polling'
		: 'bridge-worktree-dev-pause-polling';
	const expectedState = props.enabled ? 'running' : 'paused';
	await props.page.evaluate((nextEventType: string): void => {
		window.dispatchEvent(new Event(nextEventType));
	}, eventType);
	await props.page.waitForFunction(
		(nextState: string): boolean =>
			document.documentElement.dataset['bridgeWorktreeDevPollingState'] === nextState,
		expectedState,
		{ timeout: 5_000 },
	);
}

async function setWorktreeDevSplitResetReplacementDelay(props: {
	readonly delayMilliseconds: number | null;
	readonly page: Page;
}): Promise<void> {
	await props.page.evaluate((delayMilliseconds: number | null): void => {
		if (delayMilliseconds === null) {
			delete document.documentElement.dataset['bridgeWorktreeDevSplitResetReplacementDelayMs'];
			return;
		}
		document.documentElement.dataset['bridgeWorktreeDevSplitResetReplacementDelayMs'] =
			String(delayMilliseconds);
	}, props.delayMilliseconds);
}

async function waitForWorktreeRefreshButtonEnabled(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const refreshButton = document.querySelector<HTMLButtonElement>(
				'[data-testid="worktree-file-refresh"]',
			);
			return refreshButton !== null && !refreshButton.disabled;
		},
		{ timeout: 10_000 },
	);
}

async function readWorktreeRefreshButtonDisabled(page: Page): Promise<boolean> {
	return await page.evaluate((): boolean => {
		const refreshButton = document.querySelector<HTMLButtonElement>(
			'[data-testid="worktree-file-refresh"]',
		);
		if (refreshButton === null) {
			throw new Error('Expected Worktree/File refresh button to be present');
		}
		return refreshButton.disabled;
	});
}

async function readWorktreeDevReloadProof(page: Page): Promise<WorktreeDevReloadProof> {
	const rawProof = await page.evaluate(() => {
		const frameGenerationsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameGenerations'] ??
			'';
		const frameKindsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'] ?? '';
		const frameSequencesText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameSequences'] ?? '';
		const frameStreamIdsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameStreamIds'] ?? '';
		const frameCountText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameCount'] ?? null;
		return {
			frameCountText,
			frameGenerationsText,
			frameKindsText,
			frameSequencesText,
			frameStreamIdsText,
			request: document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] ?? null,
			sourceCursor:
				document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] ??
				null,
			status:
				document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] ?? null,
		};
	});
	return {
		frameCount:
			rawProof.frameCountText === null
				? 0
				: parseBridgeWorktreeDevReloadIntegerToken({
						label: 'frame count',
						token: rawProof.frameCountText,
					}),
		frameGenerations: parseBridgeWorktreeDevReloadIntegerList({
			label: 'frame generations',
			text: rawProof.frameGenerationsText,
		}),
		frameKinds: parseBridgeWorktreeDevReloadStringList(rawProof.frameKindsText),
		frameSequences: parseBridgeWorktreeDevReloadIntegerList({
			label: 'frame sequences',
			text: rawProof.frameSequencesText,
		}),
		frameStreamIds: parseBridgeWorktreeDevReloadStringList(rawProof.frameStreamIdsText),
		request: rawProof.request,
		sourceCursor: rawProof.sourceCursor,
		status: rawProof.status,
	};
}

async function dispatchWorktreeDevForceSplitResetReload(page: Page): Promise<void> {
	await page.evaluate((): void => {
		window.dispatchEvent(new Event('bridge-worktree-dev-force-split-reset-reload'));
	});
}

async function dispatchWorktreeDevReload(page: Page): Promise<void> {
	await page.evaluate((): void => {
		window.dispatchEvent(new Event('bridge-worktree-dev-reload'));
	});
}

async function worktreeVisibleContentText(page: Page): Promise<string> {
	return await page.evaluate((): string =>
		window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText(),
	);
}

async function assertWorktreeVisibleContentText(props: {
	readonly expectedText: string;
	readonly label: string;
	readonly page: Page;
}): Promise<void> {
	const text = await worktreeVisibleContentText(props.page);
	if (!renderedTextIncludesContent(text, props.expectedText)) {
		throw new Error(`Expected ${props.label} to be visible`);
	}
}

async function waitForWorktreeVisibleContentText(props: {
	readonly expectedText: string;
	readonly label: string;
	readonly page: Page;
}): Promise<string> {
	const deadline = Date.now() + 10_000;
	let latestText = '';
	while (Date.now() < deadline) {
		latestText = await worktreeVisibleContentText(props.page);
		if (renderedTextIncludesContent(latestText, props.expectedText)) {
			return latestText;
		}
		await props.page.waitForTimeout(100);
	}
	throw new Error(`Expected ${props.label} to be visible`);
}

function countTextLines(text: string): number {
	const trimmedText = text.endsWith('\n') ? text.slice(0, -1) : text;
	return trimmedText.length === 0 ? 0 : trimmedText.split('\n').length;
}

async function writeWorktreeDevServerProofArtifact(
	result: WorktreeDevServerVerificationResult,
): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const proofArtifactPath = join(proofRunDirectoryPath, 'worktree-dev-server-proof.json');
	const proofArtifactDisplayPath = relative(repoRootPath, proofArtifactPath);
	await writeFile(
		proofArtifactPath,
		`${JSON.stringify(
			{
				schemaVersion: 1,
				createdAtUnixMilliseconds: proofRunCreatedAtUnixMilliseconds,
				devServerUrl: worktreeDevServerUrl,
				requiredRouteUrls: worktreeDevServerRequiredRouteUrls(),
				result: {
					...result,
					proofArtifactPath: proofArtifactDisplayPath,
				},
			},
			null,
			2,
		)}\n`,
	);
	return proofArtifactDisplayPath;
}

function worktreeDevServerConsoleProof(
	result: WorktreeDevServerVerificationResult,
	proofArtifactPath: string,
): Record<string, unknown> {
	return {
		ok: true,
		devServerUrl: worktreeDevServerUrl,
		observedLocationHref: result.observedLocationHref,
		observedPageUrl: result.observedPageUrl,
		requiredRouteUrls: worktreeDevServerRequiredRouteUrls(),
		proofArtifactPath,
		scenarioName: result.scenarioName,
		selectedContentState: result.selectedContentState,
		selectedDisplayPath: result.selectedDisplayPath,
		selectedLineCount: result.selectedLineCount,
		sharedShellProof: result.sharedShellProof,
		fileToReviewHandoffProof: result.fileToReviewHandoffProof,
		reviewFileTargetRouteProof: result.reviewFileTargetRouteProof,
		reviewRouteProof: result.reviewRouteProof,
		splitResetReplacementProof: {
			devReloadFrameCount: result.splitResetReplacementProof.devReloadFrameCount,
			devReloadFrameGenerationSample:
				result.splitResetReplacementProof.devReloadFrameGenerations.slice(0, 8),
			devReloadFrameKindSample: result.splitResetReplacementProof.devReloadFrameKinds.slice(0, 8),
			devReloadFrameSequenceHead: result.splitResetReplacementProof.devReloadFrameSequences.slice(
				0,
				8,
			),
			devReloadFrameSequenceTail:
				result.splitResetReplacementProof.devReloadFrameSequences.slice(-8),
			devReloadFrameStreamIdSample: result.splitResetReplacementProof.devReloadFrameStreamIds.slice(
				0,
				3,
			),
			devReloadRequest: result.splitResetReplacementProof.devReloadRequest,
			devReloadStatus: result.splitResetReplacementProof.devReloadStatus,
			postRefreshContentRouteHitCount:
				result.splitResetReplacementProof.postRefreshContentRouteHitCount,
			postReplacementContentRouteHitCount:
				result.splitResetReplacementProof.postReplacementContentRouteHitCount,
			refreshDisabledAtFirstStale: result.splitResetReplacementProof.refreshDisabledAtFirstStale,
			refreshEnabledAfterReplacement:
				result.splitResetReplacementProof.refreshEnabledAfterReplacement,
			replacementContentRouteHitCount:
				result.splitResetReplacementProof.replacementContentRouteHitCount,
		},
		substituteGuardProof: result.substituteGuardProof,
		treePathCount: result.treePathCount,
		visibleAppProof: result.visibleAppProof,
	};
}

function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

function scenarioNameFromDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	return parsedUrl.searchParams.get('scenario') ?? 'current-worktree';
}

function fileModeUrlFromWorktreeDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	parsedUrl.searchParams.set('viewer', 'file');
	return parsedUrl.toString();
}

function reviewModeUrlFromWorktreeDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	parsedUrl.searchParams.set('viewer', 'review');
	return parsedUrl.toString();
}

function reviewFileTargetUrlFromWorktreeDevServerUrl(props: {
	readonly path: string;
	readonly url: string;
	readonly version: 'base' | 'current' | 'head';
}): string {
	const parsedUrl = new URL(props.url);
	parsedUrl.searchParams.set('viewer', 'review');
	parsedUrl.searchParams.set('presentation', 'file');
	parsedUrl.searchParams.set('path', props.path);
	parsedUrl.searchParams.set('version', props.version);
	return parsedUrl.toString();
}

function worktreeDevServerRequiredRouteUrls(): {
	readonly files: string;
	readonly review: string;
	readonly reviewFileTarget: string;
} {
	return {
		files: worktreeDevServerUrl,
		review: worktreeReviewDevServerUrl,
		reviewFileTarget: reviewFileTargetUrlFromWorktreeDevServerUrl({
			path: reviewSelectionFixtureRelativePath,
			url: worktreeDevServerUrl,
			version: 'current',
		}),
	};
}

function cssStringLiteral(value: string): string {
	return `"${value.replace(/\\/gu, '\\\\').replace(/"/gu, '\\"')}"`;
}

function timestampForPath(date: Date): string {
	return date.toISOString().replace(/[:.]/gu, '-');
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function makeDeferred<TValue>(): Deferred<TValue> {
	let resolve: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((promiseResolve) => {
		resolve = promiseResolve;
	});
	if (resolve === null) {
		throw new Error('Deferred promise did not initialize');
	}
	return { promise, resolve };
}
