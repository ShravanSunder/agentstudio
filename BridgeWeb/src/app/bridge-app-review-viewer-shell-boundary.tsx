import type { ReactElement, ReactNode } from 'react';
import { lazy, Suspense, useEffect, useState } from 'react';

import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewItemPresentation } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-types.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import {
	BridgeReviewEmptyShell,
	BridgeReviewMetadataFailedShell,
	BridgeReviewMetadataLoadingShell,
	BridgeReviewProjectionFailedShell,
	BridgeReviewProjectionPendingShell,
} from '../review-viewer/shell/review-viewer-fallback-shells.js';
import type {
	BridgeReviewCanvasLoadingReason,
	ReviewViewerShellProps,
} from '../review-viewer/shell/review-viewer-shell.js';
import type {
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import type { BridgeDiffStatusState } from './bridge-app-review-controller.js';
import type { BridgeReviewMetadataInterestRuntime } from './bridge-app-review-metadata-interest-runtime.js';
import type { SelectedMarkdownPreviewState } from './bridge-app-review-selection-state.js';
import type { SelectedContentPaintTelemetryStart } from './bridge-app-review-selection-state.js';

const LazyReviewViewerShell = lazy(async () => {
	const module = await import('../review-viewer/shell/review-viewer-shell.js');
	return { default: module.ReviewViewerShell };
});

export interface BridgeReviewViewerShellBoundaryProps {
	readonly codeViewWorkerFactory: (() => Worker) | undefined;
	readonly codeViewWorkerPoolEnabled: boolean | undefined;
	readonly currentSelectedContentKey: string | null;
	readonly diffStatus: BridgeDiffStatusState;
	readonly isActive: boolean;
	readonly lastSelectedDemandTelemetry: ReviewContentDemandTelemetry | null;
	readonly lastSelectionCommitDurationMilliseconds: number | null;
	readonly lastVisibleDemandTelemetry: ReviewContentDemandTelemetry | null;
	readonly onCodeViewControlHandleChange: (handle: BridgeCodeViewControlHandle | null) => void;
	readonly onSelectItem: (itemId: string) => void;
	readonly onTreeSearchOpen: () => void;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewMetadataInterestRuntime: BridgeReviewMetadataInterestRuntime;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectedCanvasLoadingReason: BridgeReviewCanvasLoadingReason | null;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedContentLoadingItemId: string | null;
	readonly selectedContentPaintTelemetryStart: SelectedContentPaintTelemetryStart | null;
	readonly selectedContentUnavailablePath: string | null;
	readonly selectedItemPresentation: BridgeCodeViewItemPresentation | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly treeSearchOpen: boolean;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[];
	readonly viewerActions: Pick<
		BridgeReviewViewerStoreActions,
		| 'setFileClassFilter'
		| 'setGitStatusFilter'
		| 'setProjectionMode'
		| 'setTreeSearchMode'
		| 'setTreeSearchText'
	>;
	readonly viewerHeaderControls: ReactNode;
}

export function BridgeReviewViewerShellBoundary(
	props: BridgeReviewViewerShellBoundaryProps,
): ReactElement {
	const viewerHeaderControls = props.viewerHeaderControls;
	const projection = props.projection;
	const reviewPackage = props.reviewPackage;
	const [activatedReviewViewerShellKey, setActivatedReviewViewerShellKey] = useState<string | null>(
		null,
	);
	const reviewViewerShellKey =
		reviewPackage === null
			? null
			: `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}`;
	const isReviewViewerShellReady =
		reviewPackage !== null &&
		props.rootSnapshot.projectionStatus !== 'failed' &&
		projection !== null;
	const shouldRenderReviewViewerShell =
		isReviewViewerShellReady &&
		(props.isActive || activatedReviewViewerShellKey === reviewViewerShellKey);
	useEffect((): void => {
		if (reviewViewerShellKey === null) {
			setActivatedReviewViewerShellKey(null);
			return;
		}
		if (props.isActive && isReviewViewerShellReady) {
			setActivatedReviewViewerShellKey(reviewViewerShellKey);
		}
	}, [isReviewViewerShellReady, props.isActive, reviewViewerShellKey]);

	if (reviewPackage === null && props.diffStatus.status === 'loading') {
		return (
			<BridgeReviewMetadataLoadingShell
				isActive={props.isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}
	if (reviewPackage === null && props.diffStatus.status === 'error') {
		return (
			<BridgeReviewMetadataFailedShell
				error={props.diffStatus.error}
				isActive={props.isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}
	if (reviewPackage === null) {
		return (
			<BridgeReviewEmptyShell
				isActive={props.isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}
	if (props.rootSnapshot.projectionStatus === 'failed') {
		return (
			<BridgeReviewProjectionFailedShell
				isActive={props.isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}
	if (projection === null || !isReviewViewerShellReady || !shouldRenderReviewViewerShell) {
		return (
			<BridgeReviewProjectionPendingShell
				isActive={props.isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}

	return (
		<Suspense
			fallback={
				<BridgeReviewProjectionPendingShell
					isActive={props.isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			}
		>
			<LazyReviewViewerShell
				{...reviewViewerShellPropsForBoundary({ ...props, projection, reviewPackage })}
			/>
		</Suspense>
	);
}

function reviewViewerShellPropsForBoundary(
	props: BridgeReviewViewerShellBoundaryProps & {
		readonly projection: BridgeReviewProjectionResult;
		readonly reviewPackage: BridgeReviewPackage;
	},
): ReviewViewerShellProps {
	return {
		fileClassFilter: props.rootSnapshot.fileClassFilter,
		gitStatusFilter: props.rootSnapshot.gitStatusFilter,
		isActive: props.isActive,
		selectionCommitDurationMilliseconds: props.lastSelectionCommitDurationMilliseconds,
		onCodeViewControlHandleChange: props.onCodeViewControlHandleChange,
		onFileClassFilterChange: props.viewerActions.setFileClassFilter,
		onGitStatusFilterChange: props.viewerActions.setGitStatusFilter,
		onProjectionModeChange: props.viewerActions.setProjectionMode,
		onSelectItem: props.onSelectItem,
		onTreeSearchOpen: props.onTreeSearchOpen,
		onTreeSearchModeChange: props.viewerActions.setTreeSearchMode,
		onTreeSearchTextChange: props.viewerActions.setTreeSearchText,
		projection: props.projection,
		projectionMode: props.rootSnapshot.projectionMode,
		reviewPackage: props.reviewPackage,
		reviewTreeRows: props.reviewTreeRows,
		viewerHeaderControls: props.viewerHeaderControls,
		selectedCodeViewItem: props.selectedCodeViewItem,
		selectedContentLoadingItemId: props.selectedContentLoadingItemId,
		selectedContentPaintTelemetryStart: props.selectedContentPaintTelemetryStart,
		selectedItemPresentation: props.selectedItemPresentation,
		selectedContentUnavailablePath: props.selectedContentUnavailablePath,
		selectedCanvasLoadingReason: props.selectedCanvasLoadingReason,
		selectedItemId: props.rootSnapshot.selectedItemId,
		visibleCodeViewItems: props.visibleCodeViewItems,
		lastSelectedDemandTelemetry: props.lastSelectedDemandTelemetry,
		lastVisibleDemandTelemetry: props.lastVisibleDemandTelemetry,
		onCodeViewVisibleItemIdsChange:
			props.reviewMetadataInterestRuntime.onCodeViewVisibleItemIdsChange,
		onTreeVisibleItemIdsChange: props.reviewMetadataInterestRuntime.onTreeVisibleItemIdsChange,
		...(props.codeViewWorkerPoolEnabled === undefined
			? {}
			: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled }),
		...(props.codeViewWorkerFactory === undefined
			? {}
			: { codeViewWorkerFactory: props.codeViewWorkerFactory }),
		selectedMarkdownPreviewHtml: selectedMarkdownPreviewHtmlForBoundary(props),
		selectedMarkdownPreviewSourcePath: selectedMarkdownPreviewSourcePathForBoundary(props),
		telemetryParentTraceContext: props.telemetryParentTraceContext,
		telemetryRecorder: props.telemetryRecorder,
		treeSearchOpen: props.treeSearchOpen,
		treeSearchMode: props.rootSnapshot.treeSearchMode,
		treeSearchText: props.rootSnapshot.treeSearchText,
	};
}

function selectedMarkdownPreviewHtmlForBoundary(
	props: Pick<
		BridgeReviewViewerShellBoundaryProps,
		'currentSelectedContentKey' | 'rootSnapshot' | 'selectedMarkdownPreviewState'
	>,
): string | null {
	const previewState = props.selectedMarkdownPreviewState;
	return props.rootSnapshot.renderMode.kind === 'markdownPreview' &&
		previewState !== null &&
		previewState.status === 'ready' &&
		previewState.itemId === props.rootSnapshot.selectedItemId &&
		previewState.contentKey === props.currentSelectedContentKey
		? previewState.html
		: null;
}

function selectedMarkdownPreviewSourcePathForBoundary(
	props: Pick<
		BridgeReviewViewerShellBoundaryProps,
		'currentSelectedContentKey' | 'rootSnapshot' | 'selectedMarkdownPreviewState'
	>,
): string | null {
	const previewState = props.selectedMarkdownPreviewState;
	return props.rootSnapshot.renderMode.kind === 'markdownPreview' &&
		previewState !== null &&
		previewState.status === 'ready' &&
		previewState.itemId === props.rootSnapshot.selectedItemId &&
		previewState.contentKey === props.currentSelectedContentKey
		? previewState.sourcePath
		: null;
}
