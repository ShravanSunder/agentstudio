import type { BridgeWorkerContentAvailabilityPatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type { ReviewContentDemandLoadResult } from '../review-viewer/content/review-content-demand-loader.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-loader.js';
import { makeReviewItemContentResourcesKey } from '../review-viewer/content/visible-review-content-hydration.js';
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

export interface SelectedContentResourcesState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly demandStartedAtMilliseconds?: number | null;
	readonly status: 'loading' | 'ready' | 'failed';
	readonly resources: BridgeCodeViewContentResources | null;
}

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

interface SelectedContentResourcesForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

export function selectedContentResourcesForCurrentSelection(
	props: SelectedContentResourcesForCurrentSelectionProps,
): BridgeCodeViewContentResources | null {
	// Content-addressed validity with metadata-only-keep: the loaded resources stay valid while the
	// per-role contentHash is unchanged OR the current item lost that role's descriptor (metadata-only
	// re-touch, no fresher content identity). Only a genuine contentHash change or a generation
	// rotation invalidates. reviewContentValidityDropReason is the single authority; a non-'valid'
	// result is a real drop and is reported to telemetry so it can never be silent.
	if (
		reviewContentValidityDropReason({
			reviewPackage: props.reviewPackage,
			selectedItemId: props.selectedItemId,
			selectedContentResourcesState: props.selectedContentResourcesState,
		}) !== 'valid'
	) {
		return null;
	}
	return props.selectedContentResourcesState?.resources ?? null;
}

export function selectedContentDemandStartedAtMillisecondsForCurrentSelection(
	props: SelectedContentResourcesForCurrentSelectionProps,
): number | null {
	if (
		reviewContentValidityDropReason({
			reviewPackage: props.reviewPackage,
			selectedItemId: props.selectedItemId,
			selectedContentResourcesState: props.selectedContentResourcesState,
		}) !== 'valid'
	) {
		return null;
	}
	return props.selectedContentResourcesState?.demandStartedAtMilliseconds ?? null;
}

export type ReviewContentValidityDropReason =
	| 'no_selection'
	| 'valid'
	| 'generation_rotation'
	| 'contenthash_change'
	| 'revision_churn';

interface ReviewContentValidityDropReasonProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

interface ReviewContentValidityRoleHandlePair {
	readonly currentHandle: BridgeContentHandle | null | undefined;
	readonly loadedHandle: BridgeContentHandle | undefined;
}

/**
 * Classifies WHY selectedContentResourcesForCurrentSelection dropped an already-loaded, ready
 * SelectedContentResourcesState instead of painting it. The drop itself is detected purely by a
 * contentKey mismatch (see makeSelectedContentResourcesKey); this classifier re-derives the reason
 * from the loaded resources' handles vs. the current item's content-role handles so a silently
 * dropped load can always be attributed to a specific, telemetry-reportable cause.
 */
export function reviewContentValidityDropReason(
	props: ReviewContentValidityDropReasonProps,
): ReviewContentValidityDropReason {
	const { reviewPackage, selectedItemId, selectedContentResourcesState } = props;
	if (
		reviewPackage === null ||
		selectedItemId === null ||
		selectedContentResourcesState === null ||
		selectedContentResourcesState.itemId !== selectedItemId ||
		selectedContentResourcesState.status !== 'ready'
	) {
		return 'no_selection';
	}
	const currentItem = reviewPackage.itemsById[selectedItemId];
	if (currentItem === undefined) {
		return 'no_selection';
	}
	const currentContentKey = makeSelectedContentResourcesKey(reviewPackage, selectedItemId);
	if (selectedContentResourcesState.contentKey === currentContentKey) {
		return 'valid';
	}
	const loadedResources = selectedContentResourcesState.resources;
	const contentRolePairs: readonly ReviewContentValidityRoleHandlePair[] = [
		{ currentHandle: currentItem.contentRoles.base, loadedHandle: loadedResources?.base?.handle },
		{ currentHandle: currentItem.contentRoles.head, loadedHandle: loadedResources?.head?.handle },
		{ currentHandle: currentItem.contentRoles.diff, loadedHandle: loadedResources?.diff?.handle },
		{ currentHandle: currentItem.contentRoles.file, loadedHandle: loadedResources?.file?.handle },
	];
	const hasGenerationRotation = contentRolePairs.some(
		(pair): boolean =>
			pair.loadedHandle !== undefined &&
			pair.loadedHandle.reviewGeneration !== reviewPackage.reviewGeneration,
	);
	if (hasGenerationRotation) {
		return 'generation_rotation';
	}
	// Genuinely newer content invalidates: a role the current item STILL resolves to a handle
	// (fresher content identity) whose contentHash differs from what we loaded.
	const hasContentHashChange = contentRolePairs.some(
		(pair): boolean =>
			pair.loadedHandle !== undefined &&
			pair.currentHandle !== null &&
			pair.currentHandle !== undefined &&
			pair.loadedHandle.contentHash !== pair.currentHandle.contentHash,
	);
	if (hasContentHashChange) {
		return 'contenthash_change';
	}
	// Metadata-only-keep: the key diverged only because a metadata re-touch dropped a role's
	// descriptor (current handle null → no fresher content identity). The loaded content is still
	// valid — keep it rather than strand the row on a placeholder that can never reload.
	const hasMetadataOnlyDowngrade = contentRolePairs.some(
		(pair): boolean =>
			pair.loadedHandle !== undefined &&
			(pair.currentHandle === null || pair.currentHandle === undefined),
	);
	if (hasMetadataOnlyDowngrade) {
		return 'valid';
	}
	// SENTINEL: the key diverged but reviewGeneration matches, no resolved role's contentHash
	// changed, and no role was downgraded to metadata-only. Under a content-addressed key this must
	// be unreachable (only packageId/generation/itemId/role-hashes compose the key); if it fires, a
	// revision-stamped field leaked back into makeReviewItemContentResourcesKey.
	return 'revision_churn';
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

export function selectedContentResourcesStateFromLoadResult(props: {
	readonly itemId: string;
	readonly contentKey: string;
	readonly contentResources: BridgeCodeViewContentResources | null;
}): SelectedContentResourcesState {
	return {
		itemId: props.itemId,
		contentKey: props.contentKey,
		status: props.contentResources === null ? 'failed' : 'ready',
		resources: props.contentResources,
	};
}

export function selectedContentResourcesStateFromDemandLoadResult(props: {
	readonly itemId: string;
	readonly contentKey: string;
	readonly demandStartedAtMilliseconds?: number | null;
	readonly loadResult: ReviewContentDemandLoadResult;
}): SelectedContentResourcesState {
	if (props.loadResult.status === 'ready') {
		return {
			itemId: props.itemId,
			contentKey: props.contentKey,
			demandStartedAtMilliseconds: props.demandStartedAtMilliseconds ?? null,
			status: 'ready',
			resources: props.loadResult.resources,
		};
	}
	return {
		itemId: props.itemId,
		contentKey: props.contentKey,
		demandStartedAtMilliseconds: props.demandStartedAtMilliseconds ?? null,
		status: 'failed',
		resources: null,
	};
}

export function contentResourceCount(resources: BridgeCodeViewContentResources): number {
	return [resources.base, resources.head, resources.diff, resources.file].filter(
		(resource): boolean => resource !== undefined,
	).length;
}

export interface ShouldPauseVisibleReviewContentHydrationProps {
	readonly isActive: boolean;
	readonly codeViewScrollActive: boolean;
	readonly currentSelectedContentKey: string | null;
	readonly foregroundSelectedContentKey: string | null;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
}

export interface ShouldStartSelectedReviewContentDemandProps {
	readonly activeSelectedContentLoadKey: string | null;
	readonly currentSelectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedContentKey: string;
	readonly selectedContentLoadKey: string;
}

export function shouldStartSelectedReviewContentDemand(
	props: ShouldStartSelectedReviewContentDemandProps,
): boolean {
	if (
		props.currentSelectedContentResourcesState?.contentKey === props.selectedContentKey &&
		props.currentSelectedContentResourcesState.status === 'ready'
	) {
		return false;
	}
	return props.activeSelectedContentLoadKey !== props.selectedContentLoadKey;
}

export function shouldPauseVisibleReviewContentHydration(
	props: ShouldPauseVisibleReviewContentHydrationProps,
): boolean {
	const selectedAvailabilityIsPending =
		props.selectedContentAvailability === null ||
		props.selectedContentAvailability.state === 'loading' ||
		props.selectedContentAvailability.state === 'stale';
	return (
		props.codeViewScrollActive ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.foregroundSelectedContentKey === props.currentSelectedContentKey) ||
		(props.isActive && props.currentSelectedContentKey !== null && selectedAvailabilityIsPending)
	);
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
	if (props.selectedContentAvailability?.state === 'loading') {
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
