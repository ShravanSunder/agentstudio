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
import type { BridgeCodeViewProgrammaticRevealGate } from './bridge-code-view-programmatic-reveal-gate.js';

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
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly reviewPackage: BridgeReviewPackage;
	readonly scrollToItem: (itemId: string, options?: BridgeCodeViewScrollToItemOptions) => boolean;
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
		programmaticRevealGate,
		reviewPackage,
		scrollToItem,
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
		const revealRequest = {
			revealIntent: 'selection-effect' as const,
			selectionScrollKey,
			targetItemId: selectedItemId,
		};
		const didBeginSelectionReveal = programmaticRevealGate.beginSelectionReveal({
			selectionScrollKey,
			targetItemId: selectedItemId,
		});
		if (!didBeginSelectionReveal) {
			pendingPreHydrationSelectionScrollKeyRef.current = null;
			pendingSelectionRevealBehaviorRef.current = null;
			pendingSmoothSelectionScrollKeyRef.current = null;
			programmaticRevealGate.onProgrammaticRevealSkipped(revealRequest);
			setSelectionScrollDiagnostic({
				didScroll: false,
				itemId: selectedItemId,
				itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
				reason: 'scroll-active',
				remainingFrameBudget: codeViewSelectionScrollRetryFrameBudget,
			});
			return;
		}
		const shouldUseInitialPlacement =
			initialSelectedItemByViewerKeyRef.current?.sourceKey === sourceKey &&
			(initialSelectedItemByViewerKeyRef.current.selectedItemId === selectedItemId ||
				initialSelectedItemByViewerKeyRef.current.selectedItemId === null) &&
			initialItems[0]?.id === selectedItemId &&
			codeViewHandle.getInstance()?.getScrollTop() === 0;
		pendingPreHydrationSelectionScrollKeyRef.current = selectionScrollKey;
		pendingSmoothSelectionScrollKeyRef.current = shouldUseInitialPlacement
			? null
			: selectionScrollKey;
		pendingSelectionRevealBehaviorRef.current = null;
		if (shouldUseInitialPlacement) {
			pendingSelectionRevealBehaviorRef.current = 'instant';
			programmaticRevealGate.transitionSelectionReveal({
				phase: 'awaiting-hydration',
				selectionScrollKey,
			});
			setSelectionScrollDiagnostic({
				didScroll: false,
				itemId: selectedItemId,
				itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
				reason: 'initial-placement',
				remainingFrameBudget: codeViewSelectionScrollRetryFrameBudget,
			});
			return;
		}
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
				if (programmaticRevealGate.shouldSkipProgrammaticReveal(revealRequest)) {
					pendingPreHydrationSelectionScrollKeyRef.current = null;
					pendingSelectionRevealBehaviorRef.current = null;
					pendingSmoothSelectionScrollKeyRef.current = null;
					programmaticRevealGate.onProgrammaticRevealSkipped(revealRequest);
					setSelectionScrollDiagnostic({
						didScroll: false,
						itemId: selectedItemId,
						itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
						reason: 'scroll-active',
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
				// Uniform instant reveals (user decision 2026-07-03): Pierre's
				// 'smooth-auto' animates only within 10 viewport-heights and
				// teleports beyond, so identical tree clicks produced different
				// motion. Instant everywhere matches GitHub-style file
				// navigation; landing precision is held by the R3/R4 gates and
				// the F9 instant re-target loop in bridge-code-view-panel.
				const scrollBehavior: BridgeCodeViewScrollToItemOptions['behavior'] = 'instant';
				const didScroll = scrollToItem(selectedItemId, {
					behavior: scrollBehavior,
					revealIntent: 'selection-effect',
					selectionScrollKey,
				});
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
		programmaticRevealGate,
		reviewPackage,
		scrollToItem,
		selectedItemId,
		setSelectionScrollDiagnostic,
		sourceKey,
	]);
}
