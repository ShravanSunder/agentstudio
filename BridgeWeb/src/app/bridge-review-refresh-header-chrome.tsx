import { CircleIcon, LoaderCircleIcon, TriangleAlertIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import type { BridgeMainReviewRefreshPresentation } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeViewerButton } from './bridge-viewer-button.js';
import {
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

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
		candidate.effectivePresentationClass.kind === 'promoted' &&
		promotedPresentationAffectsAttention({
			affectedStableFileIdentities: candidate.affectedStableFileIdentities,
			attentionItemIds,
			promotionReason: candidate.effectivePresentationClass.reason,
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

export function BridgeReviewRefreshHeaderGroup(props: {
	readonly onApplyNow: () => void;
	readonly onRetry: () => void;
	readonly presentation: BridgeReviewRefreshHeaderPresentation;
}): ReactElement | null {
	if (props.presentation.statusText === null) return null;
	const presentationClassName =
		props.presentation.statusText === 'Updating…'
			? 'text-muted-foreground'
			: props.presentation.statusText === 'Update ready'
				? 'text-primary'
				: 'text-warning';
	return (
		<div
			className={cn(bridgeViewerChromeSegmentedControlClassName, presentationClassName)}
			data-testid="bridge-review-refresh-header-group"
		>
			<span
				aria-atomic="true"
				aria-live="polite"
				className="inline-flex h-5 items-center gap-1 px-1.5 text-[11px] font-medium leading-none"
				role="status"
			>
				<BridgeReviewRefreshStatusIcon statusText={props.presentation.statusText} />
				{props.presentation.statusText}
			</span>
			<BridgeReviewRefreshHeaderAction
				action={props.presentation.action}
				onApplyNow={props.onApplyNow}
				onRetry={props.onRetry}
			/>
		</div>
	);
}

function BridgeReviewRefreshStatusIcon(props: {
	readonly statusText: Exclude<BridgeReviewRefreshHeaderPresentation['statusText'], null>;
}): ReactElement {
	switch (props.statusText) {
		case 'Updating…':
			return (
				<LoaderCircleIcon
					aria-hidden="true"
					className={cn(
						bridgeViewerChromeLucideIconClassName,
						'animate-spin motion-reduce:animate-none',
					)}
				/>
			);
		case 'Update ready':
			return <CircleIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />;
		case 'Update unavailable':
			return (
				<TriangleAlertIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			);
		default:
			return assertNeverRefreshStatus(props.statusText);
	}
}

function BridgeReviewRefreshHeaderAction(props: {
	readonly action: BridgeReviewRefreshHeaderPresentation['action'];
	readonly onApplyNow: () => void;
	readonly onRetry: () => void;
}): ReactElement | null {
	switch (props.action) {
		case 'applyNow':
			return (
				<BridgeViewerButton
					ariaLabel="Apply now"
					className={bridgeViewerChromeSegmentButtonClassName}
					onClick={props.onApplyNow}
				>
					Apply now
				</BridgeViewerButton>
			);
		case 'retry':
			return (
				<BridgeViewerButton
					ariaLabel="Retry"
					className={bridgeViewerChromeSegmentButtonClassName}
					onClick={props.onRetry}
				>
					Retry
				</BridgeViewerButton>
			);
		case null:
			return null;
		default:
			return assertNeverRefreshHeaderAction(props.action);
	}
}

function assertNeverRefreshStatus(status: never): never {
	throw new Error(`Unexpected Review refresh status: ${JSON.stringify(status)}`);
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
