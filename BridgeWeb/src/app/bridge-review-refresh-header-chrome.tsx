import type { ReactElement } from 'react';

import type { BridgeMainReviewRefreshPresentation } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeViewerButton } from './bridge-viewer-button.js';

export type BridgeReviewRefreshHeaderPresentation =
	| { readonly action: null; readonly statusText: null }
	| { readonly action: null; readonly statusText: 'Updating…' }
	| { readonly action: 'applyNow'; readonly statusText: 'Update ready' }
	| { readonly action: 'retry'; readonly statusText: 'Update unavailable' }
	| { readonly action: null; readonly statusText: 'Update unavailable' };

export function bridgeReviewRefreshHeaderPresentation(props: {
	readonly attentionItemIds: readonly string[];
	readonly canRetry: boolean;
	readonly refreshPresentation: BridgeMainReviewRefreshPresentation;
}): BridgeReviewRefreshHeaderPresentation {
	const attentionItemIds = new Set(props.attentionItemIds);
	const candidate = props.refreshPresentation.candidate;
	if (
		candidate !== null &&
		candidate.startDisposition.kind === 'sameSource' &&
		candidate.startDisposition.presentationClass.kind === 'promoted' &&
		promotedPresentationAffectsAttention({
			affectedStableFileIdentities: candidate.affectedStableFileIdentities,
			attentionItemIds,
			promotionReason: candidate.startDisposition.presentationClass.reason,
		})
	) {
		return candidate.role === 'updateReady'
			? { action: 'applyNow', statusText: 'Update ready' }
			: { action: null, statusText: 'Updating…' };
	}
	const failure = props.refreshPresentation.failure;
	if (
		failure !== null &&
		promotedPresentationAffectsAttention({
			affectedStableFileIdentities: failure.affectedStableFileIdentities,
			attentionItemIds,
			promotionReason: failure.presentationClass.reason,
		})
	) {
		return {
			action: failure.retryable && props.canRetry ? 'retry' : null,
			statusText: 'Update unavailable',
		};
	}
	return { action: null, statusText: null };
}

export function BridgeReviewRefreshHeaderAction(props: {
	readonly action: BridgeReviewRefreshHeaderPresentation['action'];
	readonly onApplyNow: () => void;
	readonly onRetry: () => void;
}): ReactElement | null {
	switch (props.action) {
		case 'applyNow':
			return (
				<BridgeViewerButton ariaLabel="Apply now" onClick={props.onApplyNow}>
					Apply now
				</BridgeViewerButton>
			);
		case 'retry':
			return (
				<BridgeViewerButton ariaLabel="Retry" onClick={props.onRetry}>
					Retry
				</BridgeViewerButton>
			);
		case null:
			return null;
		default:
			return assertNeverRefreshHeaderAction(props.action);
	}
}

function promotedPresentationAffectsAttention(props: {
	readonly affectedStableFileIdentities: readonly string[];
	readonly attentionItemIds: ReadonlySet<string>;
	readonly promotionReason: 'activeAnchor' | 'commits' | 'files' | 'lines' | 'unknown';
}): boolean {
	if (props.promotionReason === 'unknown') return props.attentionItemIds.size > 0;
	return props.affectedStableFileIdentities.some((itemId): boolean =>
		props.attentionItemIds.has(itemId),
	);
}

function assertNeverRefreshHeaderAction(action: never): never {
	throw new Error(`Unexpected Review refresh header action: ${JSON.stringify(action)}`);
}
