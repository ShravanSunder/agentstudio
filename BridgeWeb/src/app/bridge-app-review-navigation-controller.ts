import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useEffect, useRef } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import type {
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import type { SelectedReviewContentDemandController } from './bridge-app-review-selected-content-controller.js';
import {
	clearReviewRefinementsHidingExplicitTarget,
	itemIdForReviewFileNavigationTarget,
	type BridgeReviewFileNavigationTarget,
	type SelectedMarkdownPreviewState,
} from './bridge-app-review-selection-state.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

export interface UseBridgeReviewNavigationControllerProps {
	readonly beginForegroundReviewSelection: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly initialReviewFileTarget: BridgeReviewFileNavigationTarget | null;
	readonly isActive: boolean;
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectReviewItem: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly selectedContentAbortControllerRef: MutableRefObject<AbortController | null>;
	readonly setReviewRenderModeCodeView: () => void;
	readonly setSelectedContentResourcesState: SelectedReviewContentDemandController['setSelectedContentResourcesState'];
	readonly setSelectedReviewItemId: (itemId: string | null) => void;
	readonly setSelectedMarkdownPreviewState: Dispatch<
		SetStateAction<SelectedMarkdownPreviewState | null>
	>;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}

export function useBridgeReviewNavigationController(
	props: UseBridgeReviewNavigationControllerProps,
): void {
	const {
		beginForegroundReviewSelection,
		initialReviewFileTarget,
		isActive,
		navigationCommand,
		projection,
		reviewPackage,
		rootSnapshot,
		selectReviewItem,
		selectedContentAbortControllerRef,
		setReviewRenderModeCodeView,
		setSelectedContentResourcesState,
		setSelectedReviewItemId,
		setSelectedMarkdownPreviewState,
		viewerActions,
	} = props;
	const appliedNavigationCommandRef = useRef<BridgeViewerNavigationCommand | null>(null);

	useEffect((): void => {
		if (
			!isActive ||
			reviewPackage === null ||
			projection === null ||
			initialReviewFileTarget === null
		) {
			return;
		}
		const itemId = itemIdForReviewFileNavigationTarget({
			reviewPackage,
			target: initialReviewFileTarget,
		});
		if (itemId === null) {
			return;
		}
		if (
			appliedNavigationCommandRef.current !== null &&
			appliedNavigationCommandRef.current === navigationCommand
		) {
			return;
		}
		if (!projection.orderedItemIds.includes(itemId)) {
			if (clearReviewRefinementsHidingExplicitTarget({ rootSnapshot, viewerActions })) {
				appliedNavigationCommandRef.current = null;
			}
			return;
		}
		appliedNavigationCommandRef.current = navigationCommand ?? null;
		selectReviewItem(itemId);
	}, [
		initialReviewFileTarget,
		isActive,
		navigationCommand,
		projection,
		reviewPackage,
		rootSnapshot,
		selectReviewItem,
		viewerActions,
	]);

	useEffect((): void => {
		if (!isActive || reviewPackage === null || projection === null) {
			return;
		}
		if (
			rootSnapshot.selectedItemId !== null &&
			projection.orderedItemIds.includes(rootSnapshot.selectedItemId)
		) {
			return;
		}

		const targetItemId =
			initialReviewFileTarget === null
				? null
				: itemIdForReviewFileNavigationTarget({
						reviewPackage,
						target: initialReviewFileTarget,
					});
		const nextSelectedItemId =
			targetItemId !== null && projection.orderedItemIds.includes(targetItemId)
				? targetItemId
				: (projection.orderedItemIds[0] ?? null);
		if (rootSnapshot.selectedItemId === nextSelectedItemId) {
			return;
		}

		if (nextSelectedItemId === null) {
			selectedContentAbortControllerRef.current?.abort();
			selectedContentAbortControllerRef.current = null;
			setSelectedContentResourcesState(null);
			setSelectedReviewItemId(null);
			setReviewRenderModeCodeView();
		} else {
			beginForegroundReviewSelection(nextSelectedItemId);
		}
		setSelectedMarkdownPreviewState(null);
	}, [
		beginForegroundReviewSelection,
		initialReviewFileTarget,
		isActive,
		projection,
		reviewPackage,
		rootSnapshot.selectedItemId,
		selectedContentAbortControllerRef,
		setReviewRenderModeCodeView,
		setSelectedContentResourcesState,
		setSelectedReviewItemId,
		setSelectedMarkdownPreviewState,
	]);
}
