import type { BridgeWorkerContentAvailabilityPatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-types.js';
import { makeReviewItemContentResourcesKey } from '../review-viewer/content/visible-review-content-hydration-identity.js';
import type { BridgeReviewCanvasLoadingReason } from '../review-viewer/shell/review-viewer-shell.js';
import type {
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

export type BridgeReviewFileNavigationTarget = Extract<
	NonNullable<BridgeViewerNavigationCommand['target']>,
	{ readonly targetKind: 'file' }
>;

export interface SelectedMarkdownPreviewState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly sourcePath: string;
	readonly status: 'rendering' | 'ready' | 'failed';
	readonly html: string | null;
}

export function makeSelectedContentResourcesKey(
	reviewPackage: BridgeReviewPackage,
	selectedItemId: string,
): string {
	const selectedItem = reviewPackage.itemsById[selectedItemId];
	if (selectedItem === undefined) {
		return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}:${selectedItemId}:missing`;
	}
	return makeReviewItemContentResourcesKey({
		item: selectedItem,
		reviewPackage,
	});
}

export function reviewContentDemandTelemetryForPackage(props: {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly telemetry: ReviewContentDemandTelemetry | null;
}): ReviewContentDemandTelemetry | null {
	if (props.reviewPackage === null || props.telemetry === null) {
		return null;
	}
	if (
		props.telemetry.packageId !== props.reviewPackage.packageId ||
		props.telemetry.reviewGeneration !== props.reviewPackage.reviewGeneration ||
		props.telemetry.revision !== props.reviewPackage.revision
	) {
		return null;
	}
	return props.reviewPackage.itemsById[props.telemetry.itemId] === undefined
		? null
		: props.telemetry;
}

export function reviewFileTargetForNavigationCommand(
	navigationCommand: BridgeViewerNavigationCommand | undefined,
): BridgeReviewFileNavigationTarget | null {
	if (navigationCommand?.context !== 'review' || navigationCommand.target?.targetKind !== 'file') {
		return null;
	}
	return navigationCommand.target;
}

export function itemIdForReviewFileNavigationTarget(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly target: BridgeReviewFileNavigationTarget;
}): string | null {
	if (
		props.target.reviewItemId !== undefined &&
		props.reviewPackage.itemsById[props.target.reviewItemId] !== undefined
	) {
		return props.target.reviewItemId;
	}
	const matchedItem = Object.values(props.reviewPackage.itemsById).find(
		(item: BridgeReviewItemDescriptor): boolean =>
			item.headPath === props.target.fileRef.path || item.basePath === props.target.fileRef.path,
	);
	return matchedItem?.itemId ?? null;
}

export function reviewFileTargetForReviewPackagePath(props: {
	readonly path: string;
	readonly reviewPackage: BridgeReviewPackage | null;
}): BridgeReviewFileNavigationTarget | null {
	if (props.reviewPackage === null) {
		return null;
	}
	const matchedItem = Object.values(props.reviewPackage.itemsById).find(
		(item: BridgeReviewItemDescriptor): boolean =>
			item.headPath === props.path || item.basePath === props.path,
	);
	if (matchedItem === undefined) {
		return null;
	}
	return {
		targetKind: 'file',
		fileRef: {
			sourceId: props.reviewPackage.query.repoId,
			path: props.path,
		},
		version:
			matchedItem.basePath === props.path && matchedItem.headPath !== props.path
				? 'base'
				: 'current',
		reviewItemId: matchedItem.itemId,
	};
}

export function clearReviewRefinementsHidingExplicitTarget(props: {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}): boolean {
	let didClearRefinement = false;
	if (props.rootSnapshot.treeSearchText.length > 0) {
		props.viewerActions.setTreeSearchText('');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.treeSearchMode.kind !== 'text') {
		props.viewerActions.setTreeSearchMode({ kind: 'text' });
		didClearRefinement = true;
	}
	if (props.rootSnapshot.gitStatusFilter !== 'all') {
		props.viewerActions.setGitStatusFilter('all');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.fileClassFilter !== 'all') {
		props.viewerActions.setFileClassFilter('all');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.facets.length > 0) {
		props.viewerActions.setProjectionFacets([]);
		didClearRefinement = true;
	}
	return didClearRefinement;
}

export function selectedItemPresentationForReviewFileTarget(props: {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly target: BridgeReviewFileNavigationTarget | null;
}): {
	readonly kind: 'file';
	readonly version: BridgeReviewFileNavigationTarget['version'];
} | null {
	if (props.reviewPackage === null || props.selectedItemId === null || props.target === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (
		props.target.reviewItemId !== undefined &&
		props.target.reviewItemId !== props.selectedItemId
	) {
		return null;
	}
	if (
		selectedItem === undefined ||
		(selectedItem.headPath !== props.target.fileRef.path &&
			selectedItem.basePath !== props.target.fileRef.path)
	) {
		return null;
	}
	return {
		kind: 'file',
		version: props.target.version,
	};
}

interface SelectedContentUnavailablePathForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedItemId: string | null;
}

export function selectedContentUnavailablePathForCurrentSelection(
	props: SelectedContentUnavailablePathForCurrentSelectionProps,
): string | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (
		props.selectedContentAvailability?.state !== 'failed' &&
		props.selectedContentAvailability?.state !== 'unavailable'
	) {
		return null;
	}
	return selectedItem?.headPath ?? selectedItem?.basePath ?? props.selectedItemId;
}

interface SelectedCanvasLoadingReasonForCurrentSelectionProps {
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedItemId: string | null;
	readonly selectedContentKey: string | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
}

export function selectedCanvasLoadingReasonForCurrentSelection(
	props: SelectedCanvasLoadingReasonForCurrentSelectionProps,
): BridgeReviewCanvasLoadingReason | null {
	if (props.selectedItemId === null || props.selectedContentKey === null) {
		return null;
	}
	if (
		props.selectedContentAvailability?.state === 'loading' ||
		props.selectedContentAvailability?.state === 'stale'
	) {
		return 'content';
	}
	if (
		props.selectedMarkdownPreviewState !== null &&
		props.selectedMarkdownPreviewState.itemId === props.selectedItemId &&
		props.selectedMarkdownPreviewState.contentKey === props.selectedContentKey &&
		props.selectedMarkdownPreviewState.status === 'rendering'
	) {
		return 'markdownPreview';
	}
	return null;
}
