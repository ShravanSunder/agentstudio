import { TriangleAlertIcon } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { AnimationEvent, ReactElement } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '../components/ui/alert.js';
import type { BridgeReviewComparisonPaneState } from './bridge-review-comparison-pane-state.js';
import type { BridgeReviewComparisonTarget } from './bridge-review-comparison-target.js';
import {
	bridgeReviewFailureDisplaySpec,
	bridgeReviewRegionDisplaySpec,
} from './bridge-review-region-display-spec.js';
import { BridgeViewerRecoveryRetryButton } from './bridge-viewer-recovery-retry-button.js';

type VisibleComparisonPaneState = Extract<
	BridgeReviewComparisonPaneState,
	{ readonly kind: 'failedInitial' | 'failedPrevious' }
>;

export function BridgeReviewComparisonStatusBanner(props: {
	readonly onRetry: (target: BridgeReviewComparisonTarget) => void;
	readonly state: BridgeReviewComparisonPaneState;
}): ReactElement | null {
	const currentVisibleState =
		props.state.kind === 'failedInitial' || props.state.kind === 'failedPrevious'
			? props.state
			: null;
	const [retainedVisibleState, setRetainedVisibleState] =
		useState<VisibleComparisonPaneState | null>(currentVisibleState);

	useEffect((): void => {
		if (currentVisibleState !== null) {
			setRetainedVisibleState(currentVisibleState);
		} else if (props.state.kind !== 'settled') {
			setRetainedVisibleState(null);
		}
	}, [currentVisibleState, props.state.kind]);

	const presentedState = currentVisibleState ?? retainedVisibleState;
	const motionState =
		currentVisibleState !== null ? 'entering' : presentedState === null ? 'settled' : 'exiting';

	const handleAnimationEnd = (event: AnimationEvent<HTMLDivElement>): void => {
		if (event.currentTarget !== event.target || motionState !== 'exiting') {
			return;
		}
		setRetainedVisibleState(null);
	};
	if (props.state.kind === 'loadingInitial' || props.state.kind === 'loadingPrevious') {
		return (
			<span
				aria-atomic="true"
				aria-live="polite"
				className="sr-only"
				data-testid="bridge-review-comparison-loading-status"
				role="status"
			>
				Loading comparison with {props.state.requestedTargetLabel}…
			</span>
		);
	}
	if (presentedState === null) {
		return null;
	}

	return (
		<div
			className="bridge-review-comparison-status-region grid overflow-hidden"
			data-motion-state={motionState}
			data-testid="bridge-review-comparison-status-region"
			onAnimationEnd={handleAnimationEnd}
		>
			<div className="min-h-0 overflow-hidden">{renderComparisonStatus(props, presentedState)}</div>
		</div>
	);
}

function renderComparisonStatus(
	props: {
		readonly onRetry: (target: BridgeReviewComparisonTarget) => void;
	},
	state: VisibleComparisonPaneState | null,
): ReactElement | null {
	if (state === null) {
		return null;
	}

	switch (state.kind) {
		case 'failedPrevious':
			return (
				<ComparisonFailureAlert
					message={bridgeReviewFailureDisplaySpec(state.failureKind).message}
					description={
						state.failureKind === 'refreshUnavailable'
							? bridgeReviewRegionDisplaySpec.stale
							: `Couldn’t load ${state.requestedTargetLabel}. Showing the previous comparison with ${state.displayedTargetLabel}.`
					}
					onRetry={props.onRetry}
					retryTarget={state.retryTarget}
				/>
			);
		case 'failedInitial':
			return (
				<ComparisonFailureAlert
					message={bridgeReviewFailureDisplaySpec(state.failureKind).message}
					description={`Couldn’t load ${state.requestedTargetLabel}.`}
					onRetry={props.onRetry}
					retryTarget={state.retryTarget}
				/>
			);
		default:
			return assertNeverComparisonStatusBannerState(state);
	}
}

function ComparisonFailureAlert(props: {
	readonly message: string;
	readonly description: string;
	readonly onRetry: (target: BridgeReviewComparisonTarget) => void;
	readonly retryTarget: BridgeReviewComparisonTarget | null;
}): ReactElement {
	const retryTarget = props.retryTarget;
	return (
		<Alert
			layout="banner"
			data-testid="bridge-review-comparison-status-banner"
			variant="destructive"
		>
			<TriangleAlertIcon aria-hidden="true" />
			<AlertTitle>{props.message}</AlertTitle>
			<AlertDescription>{props.description}</AlertDescription>
			{retryTarget === null ? null : (
				<AlertAction>
					<BridgeViewerRecoveryRetryButton
						surface="review"
						onClick={(): void => props.onRetry(retryTarget)}
					/>
				</AlertAction>
			)}
		</Alert>
	);
}

function assertNeverComparisonStatusBannerState(state: never): never {
	throw new Error(`Unexpected Review comparison banner state: ${JSON.stringify(state)}`);
}
