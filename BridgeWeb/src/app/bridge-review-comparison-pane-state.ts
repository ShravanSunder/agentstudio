import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import {
	bridgeReviewComparisonTargetLabel,
	type BridgeReviewComparisonTarget,
} from './bridge-review-comparison-target.js';

export type BridgeReviewComparisonPaneState =
	| { readonly kind: 'settled' }
	| {
			readonly displayedTargetLabel: string;
			readonly kind: 'loadingPrevious';
			readonly requestedTargetLabel: string;
	  }
	| { readonly kind: 'loadingInitial'; readonly requestedTargetLabel: string }
	| {
			readonly displayedTargetLabel: string;
			readonly kind: 'failedPrevious';
			readonly requestedTargetLabel: string;
			readonly retryTarget: BridgeReviewComparisonTarget | null;
	  }
	| {
			readonly kind: 'failedInitial';
			readonly requestedTargetLabel: string;
			readonly retryTarget: BridgeReviewComparisonTarget | null;
	  };

export type BridgeReviewComparisonPackageMatch =
	| 'matched'
	| 'snapshot_not_current'
	| 'package_absent'
	| 'package_id_mismatch'
	| 'review_generation_mismatch'
	| 'revision_mismatch';

export function bridgeReviewComparisonPaneState(props: {
	readonly comparisonPresentation: BridgeWorkerPanelChromePatchPayload['reviewComparison'];
	readonly displayedReviewPackage: BridgeReviewPackage | null;
}): BridgeReviewComparisonPaneState {
	const comparisonPresentation = props.comparisonPresentation;
	if (comparisonPresentation === null || comparisonPresentation === undefined) {
		return { kind: 'settled' };
	}
	const requestedTargetLabel =
		comparisonPresentation.activeTarget === null
			? 'the selected target'
			: bridgeReviewComparisonTargetLabel(comparisonPresentation.activeTarget);
	const displayedTargetLabel = displayedComparisonTargetLabel(props.displayedReviewPackage);
	const hasDisplayedComparison =
		comparisonPresentation.displayedSnapshot.status !== 'none' && displayedTargetLabel !== null;
	const displayedPackageIsCurrent =
		bridgeReviewComparisonPackageMatch({
			displayedReviewPackage: props.displayedReviewPackage,
			displayedSnapshot: comparisonPresentation.displayedSnapshot,
		}) === 'matched';

	switch (comparisonPresentation.attempt.status) {
		case 'selectionRequired':
			return { kind: 'settled' };
		case 'pending':
			return hasDisplayedComparison && displayedTargetLabel !== null
				? { displayedTargetLabel, kind: 'loadingPrevious', requestedTargetLabel }
				: { kind: 'loadingInitial', requestedTargetLabel };
		case 'settled': {
			const isAwaitingDisplayedPackage =
				comparisonPresentation.displayedSnapshot.status === 'current' && !displayedPackageIsCurrent;
			if (!isAwaitingDisplayedPackage) return { kind: 'settled' };
			return displayedTargetLabel === null
				? { kind: 'loadingInitial', requestedTargetLabel }
				: { displayedTargetLabel, kind: 'loadingPrevious', requestedTargetLabel };
		}
		case 'unavailable': {
			const retryTarget =
				comparisonPresentation.attempt.retryable && comparisonPresentation.activeTarget !== null
					? comparisonPresentation.activeTarget
					: null;
			return hasDisplayedComparison && displayedTargetLabel !== null
				? {
						displayedTargetLabel,
						kind: 'failedPrevious',
						requestedTargetLabel,
						retryTarget,
					}
				: { kind: 'failedInitial', requestedTargetLabel, retryTarget };
		}
		default:
			return assertNeverComparisonAttempt(comparisonPresentation.attempt);
	}
}

export function bridgeReviewComparisonPaneIsLoading(
	state: BridgeReviewComparisonPaneState,
): boolean {
	switch (state.kind) {
		case 'loadingInitial':
		case 'loadingPrevious':
			return true;
		case 'failedInitial':
		case 'failedPrevious':
		case 'settled':
			return false;
		default:
			return assertNeverComparisonPaneState(state);
	}
}

function displayedComparisonTargetLabel(reviewPackage: BridgeReviewPackage | null): string | null {
	const comparisonOrigin = reviewPackage?.comparisonOrigin;
	return comparisonOrigin?.kind === 'contribution'
		? bridgeReviewComparisonTargetLabel(comparisonOrigin.symbolicTarget)
		: null;
}

export function bridgeReviewComparisonPackageMatch(props: {
	readonly displayedReviewPackage: BridgeReviewPackage | null;
	readonly displayedSnapshot: NonNullable<
		BridgeWorkerPanelChromePatchPayload['reviewComparison']
	>['displayedSnapshot'];
}): BridgeReviewComparisonPackageMatch {
	const displayedReviewPackage = props.displayedReviewPackage;
	const displayedSnapshot = props.displayedSnapshot;
	if (displayedSnapshot.status !== 'current') return 'snapshot_not_current';
	if (displayedReviewPackage === null) return 'package_absent';
	if (displayedSnapshot.packageId !== displayedReviewPackage.packageId)
		return 'package_id_mismatch';
	if (displayedSnapshot.reviewGeneration !== displayedReviewPackage.reviewGeneration) {
		return 'review_generation_mismatch';
	}
	if (displayedSnapshot.revision !== displayedReviewPackage.revision) return 'revision_mismatch';
	return 'matched';
}

function assertNeverComparisonAttempt(attempt: never): never {
	throw new Error(`Unexpected Review comparison attempt: ${JSON.stringify(attempt)}`);
}

function assertNeverComparisonPaneState(state: never): never {
	throw new Error(`Unexpected Review comparison pane state: ${JSON.stringify(state)}`);
}
