import type { CodeViewHandle } from '@pierre/diffs/react';
import { useEffect, type Dispatch, type MutableRefObject, type SetStateAction } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	codeViewHandleHasInstance,
	isBridgeCodeViewItem,
} from './bridge-code-view-panel-support.js';
import {
	codeViewSelectionScrollRetryFrameBudget,
	type BridgeCodeViewScrollToItemOptions,
	type BridgeCodeViewSelectionScrollDiagnostic,
} from './bridge-code-view-panel-types.js';

interface UseBridgeCodeViewSelectionScrollProps {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly codeViewMountVersion: number;
	readonly completedSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly initialItems: readonly BridgeCodeViewItem[];
	readonly initialSelectedItemByViewerKeyRef: MutableRefObject<{
		readonly selectedItemId: string | null;
		readonly sourceKey: string;
	} | null>;
	readonly lastSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingPreHydrationSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<
		BridgeCodeViewScrollToItemOptions['behavior'] | null
	>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly scrollToItem: (itemId: string, options?: BridgeCodeViewScrollToItemOptions) => boolean;
	readonly scrollToTopTargetItemIdRef: MutableRefObject<string | null>;
	readonly selectedItemId: string | null;
	readonly setSelectionScrollDiagnostic: Dispatch<
		SetStateAction<BridgeCodeViewSelectionScrollDiagnostic>
	>;
	readonly sourceKey: string;
}

export function useBridgeCodeViewSelectionScroll(
	props: UseBridgeCodeViewSelectionScrollProps,
): void {
	const {
		codeViewHandleRef,
		codeViewMountVersion,
		completedSelectionScrollKeyRef,
		initialItems,
		initialSelectedItemByViewerKeyRef,
		lastSelectionScrollKeyRef,
		pendingPreHydrationSelectionScrollKeyRef,
		pendingSelectionRevealBehaviorRef,
		pendingSelectionScrollFrameRef,
		pendingSmoothSelectionScrollKeyRef,
		reviewPackage,
		scrollToItem,
		scrollToTopTargetItemIdRef,
		selectedItemId,
		setSelectionScrollDiagnostic,
		sourceKey,
	} = props;
	useEffect((): void => {
		if (selectedItemId === null) {
			return;
		}
		const selectedItem = reviewPackage.itemsById[selectedItemId];
		if (selectedItem === undefined) {
			return;
		}
		const codeViewHandle = codeViewHandleRef.current;
		if (codeViewHandle === null) {
			return;
		}
		const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${selectedItemId}`;
		if (lastSelectionScrollKeyRef.current === selectionScrollKey) {
			return;
		}
		lastSelectionScrollKeyRef.current = selectionScrollKey;
		const shouldUseInitialPlacement =
			initialSelectedItemByViewerKeyRef.current?.sourceKey === sourceKey &&
			initialSelectedItemByViewerKeyRef.current.selectedItemId === selectedItemId &&
			initialItems[0]?.id === selectedItemId;
		if (!shouldUseInitialPlacement) {
			scrollToTopTargetItemIdRef.current = null;
		}
		pendingPreHydrationSelectionScrollKeyRef.current = shouldUseInitialPlacement
			? null
			: selectionScrollKey;
		pendingSmoothSelectionScrollKeyRef.current = shouldUseInitialPlacement
			? null
			: selectionScrollKey;
		pendingSelectionRevealBehaviorRef.current = null;
		if (pendingSelectionScrollFrameRef.current !== null) {
			cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
		}
		const scheduleSelectionScrollAttempt = (remainingFrameBudget: number): void => {
			pendingSelectionScrollFrameRef.current = requestAnimationFrame((): void => {
				pendingSelectionScrollFrameRef.current = null;
				if (
					codeViewHandleRef.current !== codeViewHandle ||
					reviewPackage.itemsById[selectedItemId] === undefined
				) {
					setSelectionScrollDiagnostic({
						didScroll: false,
						itemId: selectedItemId,
						itemTop: 'missing',
						reason: 'stale-handle-or-item',
						remainingFrameBudget,
					});
					return;
				}
				if (completedSelectionScrollKeyRef.current === selectionScrollKey) {
					setSelectionScrollDiagnostic({
						didScroll: false,
						itemId: selectedItemId,
						itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
						reason: 'already-completed',
						remainingFrameBudget,
					});
					return;
				}
				if (!codeViewHandleHasInstance(codeViewHandle)) {
					if (remainingFrameBudget > 0) {
						scheduleSelectionScrollAttempt(remainingFrameBudget - 1);
					} else if (lastSelectionScrollKeyRef.current === selectionScrollKey) {
						lastSelectionScrollKeyRef.current = null;
					}
					setSelectionScrollDiagnostic({
						didScroll: false,
						itemId: selectedItemId,
						itemTop: 'missing',
						reason: 'missing-instance',
						remainingFrameBudget,
					});
					return;
				}
				const scrollBehavior: BridgeCodeViewScrollToItemOptions['behavior'] = 'smooth-auto';
				const didScroll = scrollToItem(selectedItemId, { behavior: scrollBehavior });
				if (!didScroll) {
					if (remainingFrameBudget > 0) {
						scheduleSelectionScrollAttempt(remainingFrameBudget - 1);
					} else if (lastSelectionScrollKeyRef.current === selectionScrollKey) {
						lastSelectionScrollKeyRef.current = null;
					}
					setSelectionScrollDiagnostic({
						didScroll: false,
						itemId: selectedItemId,
						itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
						reason: 'missing-model-item',
						remainingFrameBudget,
					});
					return;
				}
				const currentItem = codeViewHandle.getItem(selectedItemId);
				const currentContentState = isBridgeCodeViewItem(currentItem)
					? currentItem.bridgeMetadata.contentState
					: 'placeholder';
				const didScrollHydratedContent =
					currentContentState === 'hydrated' || currentContentState === 'windowed';
				if (didScrollHydratedContent) {
					completedSelectionScrollKeyRef.current = selectionScrollKey;
					pendingPreHydrationSelectionScrollKeyRef.current = null;
					pendingSelectionRevealBehaviorRef.current = null;
					pendingSmoothSelectionScrollKeyRef.current = null;
				} else {
					pendingPreHydrationSelectionScrollKeyRef.current = selectionScrollKey;
					pendingSelectionRevealBehaviorRef.current = scrollBehavior;
					pendingSmoothSelectionScrollKeyRef.current = null;
				}
				setSelectionScrollDiagnostic({
					didScroll: true,
					itemId: selectedItemId,
					itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
					reason: didScrollHydratedContent ? 'hydrated' : 'pre-hydration',
					remainingFrameBudget,
				});
			});
		};
		scheduleSelectionScrollAttempt(codeViewSelectionScrollRetryFrameBudget);
	}, [
		codeViewHandleRef,
		codeViewMountVersion,
		completedSelectionScrollKeyRef,
		initialItems,
		initialSelectedItemByViewerKeyRef,
		lastSelectionScrollKeyRef,
		pendingPreHydrationSelectionScrollKeyRef,
		pendingSelectionRevealBehaviorRef,
		pendingSelectionScrollFrameRef,
		pendingSmoothSelectionScrollKeyRef,
		reviewPackage,
		scrollToItem,
		scrollToTopTargetItemIdRef,
		selectedItemId,
		setSelectionScrollDiagnostic,
		sourceKey,
	]);
}
