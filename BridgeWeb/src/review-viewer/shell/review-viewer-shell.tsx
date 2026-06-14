import type { ReactElement } from 'react';

import type {
	BridgeContentFetch,
	BridgeContentResource,
} from '../../foundation/content/content-resource-loader.js';
import { loadBridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	createBridgeReviewItemRegistry,
	reviewItemPathLabel,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeSourceEndpoint,
	BridgeSourceEndpointKind,
} from '../../foundation/review-package/bridge-review-package.js';

export interface ReviewViewerShellProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly selectedContentText?: string | null;
}

export interface LoadSelectedReviewItemContentProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly fetchContent?: BridgeContentFetch;
}

export function BridgeReviewEmptyShell(): ReactElement {
	return (
		<main data-testid="bridge-review-empty-shell">
			<section aria-label="Review summary">
				<p>Bridge Review</p>
				<p>Waiting for review package</p>
			</section>
			<nav aria-label="Changed files" />
			<section aria-label="Selected content">
				<pre />
			</section>
		</main>
	);
}

export function ReviewViewerShell(props: ReviewViewerShellProps): ReactElement {
	const registry = createBridgeReviewItemRegistry({
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId,
	});
	const summary = props.reviewPackage.summary;
	const filterLabels = reviewFilterLabels(props.reviewPackage);
	const groupingLabel =
		props.reviewPackage.query.grouping.label ?? props.reviewPackage.query.grouping.kind;
	const reviewScopeLabel = reviewCheckpointOrCollationLabel(props.reviewPackage);

	return (
		<main data-testid="review-viewer-shell">
			<section aria-label="Review summary">
				<p>
					{summary.filesChanged} {summary.filesChanged === 1 ? 'file' : 'files'} changed
				</p>
				<p>
					{summary.additions} additions / {summary.deletions} deletions
				</p>
				<p>
					{props.reviewPackage.baseEndpoint.label} to {props.reviewPackage.headEndpoint.label}
				</p>
				<p>
					Generation {props.reviewPackage.reviewGeneration} · {groupingLabel}
				</p>
				<p>{reviewScopeLabel}</p>
				<p>{filterLabels.length === 0 ? 'All files' : filterLabels.join(' · ')}</p>
			</section>
			<nav aria-label="Changed files">
				{registry.visibleItems.map((item) => (
					<button
						aria-current={props.selectedItemId === item.itemId ? 'true' : undefined}
						key={item.itemId}
						onClick={() => props.onSelectItem(item.itemId)}
						type="button"
					>
						{reviewItemPathLabel(item)}
					</button>
				))}
			</nav>
			<section aria-label="Selected content">
				<pre>{props.selectedContentText ?? ''}</pre>
			</section>
		</main>
	);
}

export async function loadSelectedReviewItemContent(
	props: LoadSelectedReviewItemContentProps,
): Promise<BridgeContentResource | null> {
	if (props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return null;
	}
	const contentHandle = preferredContentHandle(selectedItem);
	if (contentHandle === null) {
		return null;
	}
	return await loadBridgeContentResource(contentHandle, props.fetchContent);
}

function preferredContentHandle(item: BridgeReviewItemDescriptor): BridgeContentHandle | null {
	return (
		item.contentRoles.head ??
		item.contentRoles.file ??
		item.contentRoles.diff ??
		item.contentRoles.base
	);
}

function reviewFilterLabels(reviewPackage: BridgeReviewPackage): readonly string[] {
	const filter = reviewPackage.filterState;
	return [
		...reviewPackage.query.pathScope.map((pathScope: string): string => `Folder: ${pathScope}`),
		...filter.includedFileClasses.map((fileClass: string): string => `Class: ${fileClass}`),
		...filter.changeKinds.map((changeKind: string): string => `Change: ${changeKind}`),
		...filter.reviewStates.map((reviewState: string): string => `State: ${reviewState}`),
		...filter.includedExtensions.map((extension: string): string => `Extension: ${extension}`),
	];
}

function reviewCheckpointOrCollationLabel(reviewPackage: BridgeReviewPackage): string {
	const checkpointEndpoint =
		checkpointEndpointLabel(reviewPackage.headEndpoint) ??
		checkpointEndpointLabel(reviewPackage.baseEndpoint);
	if (checkpointEndpoint !== null) {
		return `Checkpoint: ${checkpointEndpoint}`;
	}
	const groupingLabel = reviewPackage.query.grouping.label ?? reviewPackage.query.grouping.kind;
	return `Collation: ${groupingLabel}`;
}

function checkpointEndpointLabel(endpoint: BridgeSourceEndpoint): string | null {
	return isCheckpointEndpointKind(endpoint.kind) ? endpoint.label : null;
}

function isCheckpointEndpointKind(kind: BridgeSourceEndpointKind): boolean {
	return (
		kind === 'promptCheckpoint' ||
		kind === 'sessionCheckpoint' ||
		kind === 'manualCheckpoint' ||
		kind === 'savedTimeWindowCheckpoint'
	);
}
