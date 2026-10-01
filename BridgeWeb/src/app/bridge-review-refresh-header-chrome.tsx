import { TriangleAlertIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import type { BridgeMainReviewRefreshPresentation } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeRegionUpdatingIndicator } from './bridge-region-presentation.js';
import { bridgeReviewRegionDisplaySpec } from './bridge-review-region-display-spec.js';
import { BridgeViewerButton } from './bridge-viewer-button.js';
import { bridgeViewerChromeStatusGroupClassName } from './bridge-viewer-chrome.js';
import { BridgeViewerRecoveryRetryButton } from './bridge-viewer-recovery-retry-button.js';
import { bridgeViewerRegionApplyActionSpec } from './bridge-viewer-region-apply-action-spec.js';
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
		(failure.kind === 'installation' ||
			(failure.presentationClass.kind === 'promoted' &&
				promotedPresentationAffectsAttention({
					affectedStableFileIdentities: failure.affectedStableFileIdentities,
					attentionItemIds,
					promotionReason: failure.presentationClass.reason,
				})))
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
}): ReactElement {
	const refreshGroup =
		props.presentation.statusText === null ? null : (
			<BridgeReviewRefreshHeaderGroupContent
				onApplyNow={props.onApplyNow}
				onRetry={props.onRetry}
				presentation={props.presentation}
			/>
		);
	return (
		<div className="grid h-6 shrink-0" data-testid="bridge-review-refresh-header-slot">
			<BridgeReviewRefreshHeaderGroupSizer />
			{refreshGroup}
		</div>
	);
}

function BridgeReviewRefreshHeaderGroupContent(props: {
	readonly onApplyNow: () => void;
	readonly onRetry: () => void;
	readonly presentation: Exclude<
		BridgeReviewRefreshHeaderPresentation,
		{ readonly statusText: null }
	>;
}): ReactElement {
	if (
		props.presentation.statusText === 'Updating…' ||
		props.presentation.statusText === 'Update ready'
	) {
		const held = props.presentation.action === 'applyNow';
		return (
			<div
				className={cn(
					bridgeViewerChromeStatusGroupClassName,
					'col-start-1 row-start-1',
					held ? 'text-primary' : 'text-muted-foreground',
				)}
				data-testid="bridge-review-refresh-header-group"
			>
				<BridgeRegionUpdatingIndicator
					updatingLabel={bridgeReviewRegionDisplaySpec.updating}
					state={{ kind: 'updating', rest: held ? 'held' : null }}
					held={
						held
							? {
									label: bridgeViewerRegionApplyActionSpec('review', false).statusLabel,
									action: (
										<BridgeReviewRefreshHeaderAction
											action="applyNow"
											onApplyNow={props.onApplyNow}
											onRetry={props.onRetry}
										/>
									),
								}
							: undefined
					}
				/>
			</div>
		);
	}
	const presentationClassName = 'text-warning';
	return (
		<div
			className={cn(
				bridgeViewerChromeStatusGroupClassName,
				'col-start-1 row-start-1',
				presentationClassName,
			)}
			data-testid="bridge-review-refresh-header-group"
		>
			<span
				aria-atomic="true"
				aria-live="polite"
				className="inline-flex h-5 items-center gap-1 px-1.5 text-xs font-medium"
				role="status"
			>
				<TriangleAlertIcon aria-hidden="true" className="size-3" />
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

function BridgeReviewRefreshHeaderGroupSizer(): ReactElement {
	return (
		<div
			aria-hidden="true"
			className={cn(
				bridgeViewerChromeStatusGroupClassName,
				'invisible col-start-1 row-start-1 text-warning',
			)}
		>
			<span className="inline-flex h-5 items-center gap-1 px-1.5 text-xs font-medium">
				<TriangleAlertIcon aria-hidden="true" className="size-3" />
				Update unavailable
			</span>
			<BridgeViewerButton ariaLabel="Retry" size="xs" disabled>
				Retry
			</BridgeViewerButton>
		</div>
	);
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
					ariaLabel={bridgeViewerRegionApplyActionSpec('review', false).accessibleName}
					size="xs"
					onClick={props.onApplyNow}
				>
					{bridgeViewerRegionApplyActionSpec('review', false).label}
				</BridgeViewerButton>
			);
		case 'retry':
			return <BridgeViewerRecoveryRetryButton surface="review" onClick={props.onRetry} />;
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
