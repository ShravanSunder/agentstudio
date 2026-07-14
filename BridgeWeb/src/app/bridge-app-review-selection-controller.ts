import { useCallback, useLayoutEffect, useRef } from 'react';

import type { BridgeWorkerSelectCommand } from '../core/comm-worker/bridge-worker-contracts.js';

export type BridgeReviewSelectionSource = BridgeWorkerSelectCommand['selectedSource'];

export interface UseBridgeReviewSelectionControllerProps {
	readonly commitLocalSelection: (itemId: string) => void;
	readonly emitSelectIntent: (itemId: string, selectedSource: BridgeReviewSelectionSource) => void;
	readonly hasReviewItem: (itemId: string) => boolean;
	readonly isActive: boolean;
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean | void;
	readonly selectedItemId: string | null;
}

export interface BridgeReviewSelectionController {
	readonly beginForegroundReviewSelection: (
		itemId: string,
		selectedSource?: BridgeReviewSelectionSource,
	) => boolean;
	readonly selectReviewItem: (
		itemId: string,
		selectedSource?: BridgeReviewSelectionSource,
	) => boolean;
}

export interface BridgeReviewPostPaintSelectionFrameScheduler {
	readonly cancelPending: () => void;
	readonly schedule: (itemId: string, selectedSource: BridgeReviewSelectionSource) => void;
}

export function useBridgeReviewSelectionController(
	props: UseBridgeReviewSelectionControllerProps,
): BridgeReviewSelectionController {
	const selectedItemIdRef = useRef(props.selectedItemId);
	selectedItemIdRef.current = props.selectedItemId;
	const latestPropsRef = useRef(props);
	latestPropsRef.current = props;
	const lastMarkedItemIdRef = useRef<string | null>(null);
	const selectIntentSchedulerRef = useRef<BridgeReviewPostPaintSelectionFrameScheduler | null>(
		null,
	);
	if (selectIntentSchedulerRef.current === null) {
		selectIntentSchedulerRef.current = createBridgeReviewPostPaintSelectionFrameScheduler({
			cancelAnimationFrame: (frameId): void => globalThis.cancelAnimationFrame(frameId),
			onPostPaintSelection: (itemId, selectedSource): void => {
				latestPropsRef.current.emitSelectIntent(itemId, selectedSource);
			},
			isPendingIntentCurrent: (itemId): boolean =>
				latestPropsRef.current.isActive &&
				selectedItemIdRef.current === itemId &&
				latestPropsRef.current.hasReviewItem(itemId),
			requestAnimationFrame: (callback): number => globalThis.requestAnimationFrame(callback),
		});
	}
	const selectIntentScheduler = selectIntentSchedulerRef.current;
	const markViewedSchedulerRef = useRef<BridgeReviewPostPaintSelectionFrameScheduler | null>(null);
	if (markViewedSchedulerRef.current === null) {
		markViewedSchedulerRef.current = createBridgeReviewPostPaintSelectionFrameScheduler({
			cancelAnimationFrame: (frameId): void => globalThis.cancelAnimationFrame(frameId),
			onPostPaintSelection: (itemId): void => {
				scheduleReviewMarkFileViewedCommand({
					itemId,
					markFileViewed: latestPropsRef.current.markFileViewed,
					onDeliveryFailure: (): void => {
						if (lastMarkedItemIdRef.current === itemId) {
							lastMarkedItemIdRef.current = null;
						}
					},
				});
			},
			isPendingIntentCurrent: (itemId): boolean =>
				latestPropsRef.current.isActive &&
				selectedItemIdRef.current === itemId &&
				latestPropsRef.current.hasReviewItem(itemId),
			requestAnimationFrame: (callback): number => globalThis.requestAnimationFrame(callback),
		});
	}
	const markViewedScheduler = markViewedSchedulerRef.current;
	useLayoutEffect(
		(): (() => void) => (): void => {
			selectIntentScheduler.cancelPending();
			markViewedScheduler.cancelPending();
		},
		[markViewedScheduler, selectIntentScheduler],
	);
	const beginForegroundReviewSelection = useCallback(
		(itemId: string, selectedSource: BridgeReviewSelectionSource = 'user'): boolean => {
			const accepted = commitBridgeReviewPresentationSelection({
				commitLocalSelection: props.commitLocalSelection,
				currentSelectedItemId: selectedItemIdRef.current,
				hasReviewItem: props.hasReviewItem,
				isActive: props.isActive,
				itemId,
				scheduleSelectIntentAfterLocalPaint: selectIntentScheduler.schedule,
				selectedSource,
			});
			if (accepted) {
				selectedItemIdRef.current = itemId;
			}
			return accepted;
		},
		[props.commitLocalSelection, props.hasReviewItem, props.isActive, selectIntentScheduler],
	);
	const selectReviewItem = useCallback(
		(itemId: string, selectedSource: BridgeReviewSelectionSource = 'user'): boolean => {
			if (!beginForegroundReviewSelection(itemId, selectedSource)) {
				return false;
			}
			if (lastMarkedItemIdRef.current === itemId) {
				return true;
			}
			lastMarkedItemIdRef.current = itemId;
			markViewedScheduler.schedule(itemId, selectedSource);
			return true;
		},
		[beginForegroundReviewSelection, markViewedScheduler],
	);

	return { beginForegroundReviewSelection, selectReviewItem };
}

export function commitBridgeReviewPresentationSelection(props: {
	readonly commitLocalSelection: (itemId: string) => void;
	readonly currentSelectedItemId: string | null;
	readonly hasReviewItem: (itemId: string) => boolean;
	readonly isActive: boolean;
	readonly itemId: string;
	readonly scheduleSelectIntentAfterLocalPaint: (
		itemId: string,
		selectedSource: BridgeReviewSelectionSource,
	) => void;
	readonly selectedSource: BridgeReviewSelectionSource;
}): boolean {
	if (!props.isActive || !props.hasReviewItem(props.itemId)) {
		return false;
	}
	if (props.currentSelectedItemId === props.itemId) {
		return true;
	}
	props.commitLocalSelection(props.itemId);
	props.scheduleSelectIntentAfterLocalPaint(props.itemId, props.selectedSource);
	return true;
}

export function createBridgeReviewPostPaintSelectionFrameScheduler(props: {
	readonly cancelAnimationFrame: (frameId: number) => void;
	readonly onPostPaintSelection: (
		itemId: string,
		selectedSource: BridgeReviewSelectionSource,
	) => void;
	readonly isPendingIntentCurrent: (itemId: string) => boolean;
	readonly requestAnimationFrame: (callback: FrameRequestCallback) => number;
}): BridgeReviewPostPaintSelectionFrameScheduler {
	let pendingFrameId: number | null = null;
	let pendingIntent: {
		readonly itemId: string;
		readonly selectedSource: BridgeReviewSelectionSource;
	} | null = null;

	const cancelPending = (): void => {
		pendingIntent = null;
		if (pendingFrameId === null) {
			return;
		}
		props.cancelAnimationFrame(pendingFrameId);
		pendingFrameId = null;
	};
	const schedule = (itemId: string, selectedSource: BridgeReviewSelectionSource): void => {
		pendingIntent = { itemId, selectedSource };
		if (pendingFrameId !== null) {
			return;
		}
		pendingFrameId = props.requestAnimationFrame((): void => {
			pendingFrameId = props.requestAnimationFrame((): void => {
				pendingFrameId = null;
				const intent = pendingIntent;
				pendingIntent = null;
				if (intent === null || !props.isPendingIntentCurrent(intent.itemId)) {
					return;
				}
				props.onPostPaintSelection(intent.itemId, intent.selectedSource);
			});
		});
	};

	return { cancelPending, schedule };
}

export function scheduleReviewMarkFileViewedCommand(props: {
	readonly itemId: string;
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean | void;
	readonly onDeliveryFailure?: () => void;
}): void {
	queueMicrotask((): void => {
		if (props.markFileViewed(props.itemId, props.onDeliveryFailure) === false) {
			props.onDeliveryFailure?.();
		}
	});
}

export function createBridgeReviewSelectionControllerInteractionContract(): {
	readonly subscribedSlices: readonly string[];
} {
	return {
		subscribedSlices: [
			'selectionSlice',
			'rowPaintSlice',
			'contentAvailabilitySlice',
			'panelChromeSlice',
		],
	};
}
