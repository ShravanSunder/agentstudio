import type { ReactElement, ReactNode } from 'react';
import { lazy, Suspense, useEffect, useState } from 'react';

import {
	BridgeReviewEmptyShell,
	BridgeReviewMetadataFailedShell,
	BridgeReviewMetadataLoadingShell,
	BridgeReviewNoChangesShell,
	BridgeReviewProjectionFailedShell,
	BridgeReviewProjectionPendingShell,
} from '../review-viewer/shell/review-viewer-fallback-shells.js';
import type { ReviewViewerShellProps } from '../review-viewer/shell/review-viewer-shell.js';

const LazyReviewViewerShell = lazy(async () => {
	const reviewViewerShellModule = await import('../review-viewer/shell/review-viewer-shell.js');
	return { default: reviewViewerShellModule.ReviewViewerShell };
});

export type BridgeReviewViewerPresentationState =
	| { readonly status: 'empty' }
	| { readonly status: 'readyEmpty' }
	| { readonly status: 'metadataLoading' }
	| { readonly error: string | null; readonly status: 'metadataFailed' }
	| { readonly status: 'projectionPending' }
	| { readonly status: 'projectionFailed' }
	| {
			readonly presentationKey: string;
			readonly shellProps: Omit<ReviewViewerShellProps, 'isActive' | 'viewerHeaderControls'>;
			readonly status: 'ready';
	  };

export interface BridgeReviewViewerShellBoundaryProps {
	readonly isActive: boolean;
	readonly presentationState: BridgeReviewViewerPresentationState;
	readonly viewerHeaderControls: ReactNode;
}

export function BridgeReviewViewerShellBoundary(
	props: BridgeReviewViewerShellBoundaryProps,
): ReactElement {
	const { isActive, presentationState, viewerHeaderControls } = props;
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

	switch (presentationState.status) {
		case 'empty':
			return (
				<BridgeReviewEmptyShell isActive={isActive} viewerHeaderControls={viewerHeaderControls} />
			);
		case 'readyEmpty':
			return (
				<BridgeReviewNoChangesShell
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'metadataLoading':
			return (
				<BridgeReviewMetadataLoadingShell
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'metadataFailed':
			return (
				<BridgeReviewMetadataFailedShell
					error={presentationState.error}
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'projectionPending':
			return (
				<BridgeReviewProjectionPendingShell
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			);
		case 'projectionFailed':
			return (
				<BridgeReviewProjectionFailedShell
					isActive={isActive}
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
				viewerHeaderControls={viewerHeaderControls}
			/>
		);
	}

	return (
		<Suspense
			fallback={
				<BridgeReviewProjectionPendingShell
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			}
		>
			<LazyReviewViewerShell
				{...presentationState.shellProps}
				isActive={isActive}
				viewerHeaderControls={viewerHeaderControls}
			/>
		</Suspense>
	);
}

function assertNeverPresentationState(presentationState: never): never {
	throw new Error(`Unhandled Review presentation state: ${String(presentationState)}`);
}
