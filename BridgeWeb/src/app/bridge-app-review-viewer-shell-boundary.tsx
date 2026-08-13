import type { ReactElement, ReactNode } from 'react';
import { lazy, Suspense, useEffect, useState } from 'react';

import {
	BridgeReviewComparisonInitialShell,
	BridgeReviewEmptyShell,
	BridgeReviewMetadataFailedShell,
	BridgeReviewMetadataLoadingShell,
	BridgeReviewProjectionFailedShell,
	BridgeReviewProjectionPendingShell,
} from '../review-viewer/shell/review-viewer-fallback-shells.js';
import type { ReviewViewerShellProps } from '../review-viewer/shell/review-viewer-shell.js';
import type { BridgeReviewComparisonPaneState } from './bridge-review-comparison-pane-state.js';
import type { BridgeReviewComparisonTarget } from './bridge-review-comparison-target.js';

const LazyReviewViewerShell = lazy(async () => {
	const reviewViewerShellModule = await import('../review-viewer/shell/review-viewer-shell.js');
	return { default: reviewViewerShellModule.ReviewViewerShell };
});

export type BridgeReviewViewerPresentationState =
	| { readonly status: 'empty' }
	| { readonly status: 'metadataLoading' }
	| { readonly error: string | null; readonly status: 'metadataFailed' }
	| { readonly status: 'projectionPending' }
	| { readonly status: 'projectionFailed' }
	| {
			readonly presentationKey: string;
			readonly shellProps: Omit<
				ReviewViewerShellProps,
				'isActive' | 'viewerContextSwitcher' | 'viewerHeaderControls'
			>;
			readonly status: 'ready';
	  };

export interface BridgeReviewViewerShellBoundaryProps {
	readonly comparisonPaneState: BridgeReviewComparisonPaneState;
	readonly isActive: boolean;
	readonly onRetryComparison: (target: BridgeReviewComparisonTarget) => void;
	readonly presentationState: BridgeReviewViewerPresentationState;
	readonly viewerContextSwitcher: ReactNode;
	readonly viewerHeaderControls: ReactNode;
}

export function BridgeReviewViewerShellBoundary(
	props: BridgeReviewViewerShellBoundaryProps,
): ReactElement {
	const {
		comparisonPaneState,
		isActive,
		onRetryComparison,
		presentationState,
		viewerContextSwitcher,
		viewerHeaderControls,
	} = props;
	const [hasActivatedReadyPresentation, setHasActivatedReadyPresentation] = useState(false);
	useEffect((): void => {
		if (presentationState.status !== 'ready') {
			setHasActivatedReadyPresentation(false);
			return;
		}
		if (isActive) {
			setHasActivatedReadyPresentation(true);
		}
	}, [isActive, presentationState]);

	if (
		comparisonPaneState.kind === 'loadingInitial' ||
		comparisonPaneState.kind === 'failedInitial'
	) {
		return (
			<BridgeReviewComparisonInitialShell
				comparisonPaneState={comparisonPaneState}
				isActive={isActive}
				onRetryComparison={onRetryComparison}
				viewerContextSwitcher={viewerContextSwitcher}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}

	switch (presentationState.status) {
		case 'empty':
			return (
				<BridgeReviewEmptyShell
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'metadataLoading':
			return (
				<BridgeReviewMetadataLoadingShell
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'metadataFailed':
			return (
				<BridgeReviewMetadataFailedShell
					error={presentationState.error}
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'projectionPending':
			return (
				<BridgeReviewProjectionPendingShell
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'projectionFailed':
			return (
				<BridgeReviewProjectionFailedShell
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'ready':
			break;
		default:
			return assertNeverPresentationState(presentationState);
	}

	if (!isActive && !hasActivatedReadyPresentation) {
		return (
			<BridgeReviewProjectionPendingShell
				isActive={isActive}
				viewerContextSwitcher={viewerContextSwitcher}
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}

	return (
		<Suspense
			fallback={
				<BridgeReviewProjectionPendingShell
					isActive={isActive}
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={viewerHeaderControls}
				/>
			}
		>
			<LazyReviewViewerShell
				{...presentationState.shellProps}
				isActive={isActive}
				viewerContextSwitcher={viewerContextSwitcher}
				viewerHeaderControls={viewerHeaderControls}
			/>
		</Suspense>
	);
}

function assertNeverPresentationState(presentationState: never): never {
	throw new Error(`Unhandled Review presentation state: ${String(presentationState)}`);
}
