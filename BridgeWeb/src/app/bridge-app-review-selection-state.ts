import type { Dispatch, SetStateAction } from 'react';

import type {
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
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.status !== 'ready'
	) {
		return null;
	}
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	return props.selectedContentResourcesState.contentKey === selectedContentKey
		? props.selectedContentResourcesState.resources
		: null;
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
		status: props.loadResult.status === 'deferred' ? 'loading' : 'failed',
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
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

export interface ShouldStartSelectedReviewContentDemandProps {
	readonly activeSelectedContentLoadKey: string | null;
	readonly currentSelectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedContentKey: string;
	readonly selectedContentLoadKey: string;
}

export interface ShouldRetrySelectedReviewContentAfterDescriptorRegistrationProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly registeredDescriptorRefCount: number;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly lastSelectedDemandTelemetry: ReviewContentDemandTelemetry | null;
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

export function shouldRetrySelectedReviewContentAfterDescriptorRegistration(
	props: ShouldRetrySelectedReviewContentAfterDescriptorRegistrationProps,
): boolean {
	if (
		props.registeredDescriptorRefCount <= 0 ||
		props.reviewPackage === null ||
		props.selectedItemId === null ||
		props.selectedContentResourcesState === null ||
		props.lastSelectedDemandTelemetry === null
	) {
		return false;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return false;
	}
	const selectedContentKey = makeReviewItemContentResourcesKey({
		item: selectedItem,
		reviewPackage: props.reviewPackage,
	});
	return (
		props.selectedContentResourcesState.itemId === props.selectedItemId &&
		props.selectedContentResourcesState.contentKey === selectedContentKey &&
		props.selectedContentResourcesState.status === 'failed' &&
		props.lastSelectedDemandTelemetry.itemId === props.selectedItemId &&
		props.lastSelectedDemandTelemetry.packageId === props.reviewPackage.packageId &&
		props.lastSelectedDemandTelemetry.reviewGeneration === props.reviewPackage.reviewGeneration &&
		props.lastSelectedDemandTelemetry.revision === props.reviewPackage.revision &&
		props.lastSelectedDemandTelemetry.interest === 'selected' &&
		props.lastSelectedDemandTelemetry.resultStatus === 'failed' &&
		props.lastSelectedDemandTelemetry.resultReason === 'descriptor_missing'
	);
}

export function shouldPauseVisibleReviewContentHydration(
	props: ShouldPauseVisibleReviewContentHydrationProps,
): boolean {
	return (
		props.codeViewScrollActive ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState === null) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState !== null &&
			props.selectedContentResourcesState.contentKey !== props.currentSelectedContentKey) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.foregroundSelectedContentKey === props.currentSelectedContentKey) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState !== null &&
			props.selectedContentResourcesState.contentKey === props.currentSelectedContentKey &&
			props.selectedContentResourcesState.status === 'loading')
	);
}

export function scheduleSelectedContentRetry(props: {
	readonly scheduledRef: { current: boolean };
	readonly setSelectedContentRetryVersion: Dispatch<SetStateAction<number>>;
}): void {
	if (props.scheduledRef.current) {
		return;
	}
	props.scheduledRef.current = true;
	const scheduleRetry =
		typeof requestAnimationFrame === 'function'
			? (callback: () => void): void => {
					requestAnimationFrame(callback);
				}
			: (callback: () => void): void => {
					queueMicrotask(callback);
				};
	scheduleRetry((): void => {
		props.scheduledRef.current = false;
		props.setSelectedContentRetryVersion((version: number): number => version + 1);
	});
}

interface SelectedContentUnavailablePathForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

export function selectedContentUnavailablePathForCurrentSelection(
	props: SelectedContentUnavailablePathForCurrentSelectionProps,
): string | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.contentKey !== selectedContentKey ||
		props.selectedContentResourcesState.status !== 'failed'
	) {
		return null;
	}
	return selectedItem?.headPath ?? selectedItem?.basePath ?? props.selectedItemId;
}

interface SelectedCanvasLoadingReasonForCurrentSelectionProps {
	readonly selectedItemId: string | null;
	readonly selectedContentKey: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
}

export function selectedCanvasLoadingReasonForCurrentSelection(
	props: SelectedCanvasLoadingReasonForCurrentSelectionProps,
): BridgeReviewCanvasLoadingReason | null {
	if (props.selectedItemId === null || props.selectedContentKey === null) {
		return null;
	}
	if (
		props.selectedContentResourcesState !== null &&
		props.selectedContentResourcesState.itemId === props.selectedItemId &&
		props.selectedContentResourcesState.contentKey === props.selectedContentKey &&
		props.selectedContentResourcesState.status === 'loading'
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
