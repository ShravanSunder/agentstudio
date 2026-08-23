import { useEffect, type MutableRefObject } from 'react';

import type { BridgeCodeViewInstantRevealRearmCandidate } from './bridge-code-view-panel-support.js';
import type { BridgeCodeViewRenderedItemsSource } from './bridge-code-view-panel-support.js';

interface UseBridgeCodeViewPanelLifecycleProps {
	readonly annotationAttentionItemIds: readonly string[];
	readonly codeViewMountVersion: number;
	readonly materializationTaskGenerationRef: MutableRefObject<number>;
	readonly onAnnotationAttentionItemIdsChange: ((itemIds: readonly string[]) => void) | undefined;
	readonly onReadingPositionItemIdChange: ((itemId: string | null) => void) | undefined;
	readonly onScrollActivityChangeRef: MutableRefObject<((active: boolean) => void) | undefined>;
	readonly onVisibleItemIdsChange: ((itemIds: readonly string[]) => void) | undefined;
	readonly pendingMaterializationFrameRef: MutableRefObject<number | null>;
	readonly pendingPreHydrationSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingRecoveryRenderFrameRef: MutableRefObject<number | null>;
	readonly pendingRenderedItemsSourceRef: MutableRefObject<BridgeCodeViewRenderedItemsSource | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<unknown>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingVisibleHeaderPublishFrameRef: MutableRefObject<number | null>;
	readonly publishVisibleItemIdsFromCurrentHandle: () => void;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly scrollActivityActiveRef: MutableRefObject<boolean>;
	readonly scrollIdleTimeoutRef: MutableRefObject<ReturnType<typeof setTimeout> | null>;
	readonly sourceKey: string;
}

export function useBridgeCodeViewPanelLifecycle(props: UseBridgeCodeViewPanelLifecycleProps): void {
	const {
		annotationAttentionItemIds,
		codeViewMountVersion,
		materializationTaskGenerationRef,
		onAnnotationAttentionItemIdsChange,
		onReadingPositionItemIdChange,
		onScrollActivityChangeRef,
		onVisibleItemIdsChange,
		pendingMaterializationFrameRef,
		pendingPreHydrationSelectionScrollKeyRef,
		pendingRecoveryRenderFrameRef,
		pendingRenderedItemsSourceRef,
		pendingSelectionRevealBehaviorRef,
		pendingSelectionScrollFrameRef,
		pendingSmoothSelectionScrollKeyRef,
		pendingVisibleHeaderPublishFrameRef,
		publishVisibleItemIdsFromCurrentHandle,
		recentInstantSelectionRevealRef,
		scrollActivityActiveRef,
		scrollIdleTimeoutRef,
		sourceKey,
	} = props;
	useEffect((): void => {
		onAnnotationAttentionItemIdsChange?.(annotationAttentionItemIds);
	}, [annotationAttentionItemIds, onAnnotationAttentionItemIdsChange]);
	useEffect((): (() => void) | undefined => {
		if (onAnnotationAttentionItemIdsChange === undefined) return undefined;
		return (): void => onAnnotationAttentionItemIdsChange?.([]);
	}, [onAnnotationAttentionItemIdsChange]);
	useEffect((): (() => void) | undefined => {
		if (onReadingPositionItemIdChange === undefined) return undefined;
		return (): void => onReadingPositionItemIdChange?.(null);
	}, [onReadingPositionItemIdChange]);

	useEffect(
		(): (() => void) => (): void => {
			materializationTaskGenerationRef.current += 1;
			if (pendingRecoveryRenderFrameRef.current !== null) {
				cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
				pendingRecoveryRenderFrameRef.current = null;
			}
			if (pendingMaterializationFrameRef.current !== null) {
				clearTimeout(pendingMaterializationFrameRef.current);
				pendingMaterializationFrameRef.current = null;
			}
			if (pendingSelectionScrollFrameRef.current !== null) {
				cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
				pendingSelectionScrollFrameRef.current = null;
			}
			pendingPreHydrationSelectionScrollKeyRef.current = null;
			pendingSelectionRevealBehaviorRef.current = null;
			pendingSmoothSelectionScrollKeyRef.current = null;
			recentInstantSelectionRevealRef.current = null;
			if (pendingVisibleHeaderPublishFrameRef.current !== null) {
				cancelAnimationFrame(pendingVisibleHeaderPublishFrameRef.current);
				pendingVisibleHeaderPublishFrameRef.current = null;
			}
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
				scrollIdleTimeoutRef.current = null;
			}
			if (scrollActivityActiveRef.current) {
				scrollActivityActiveRef.current = false;
				onScrollActivityChangeRef.current?.(false);
			}
			pendingRenderedItemsSourceRef.current = null;
		},
		[
			materializationTaskGenerationRef,
			onScrollActivityChangeRef,
			pendingMaterializationFrameRef,
			pendingPreHydrationSelectionScrollKeyRef,
			pendingRecoveryRenderFrameRef,
			pendingRenderedItemsSourceRef,
			pendingSelectionRevealBehaviorRef,
			pendingSelectionScrollFrameRef,
			pendingSmoothSelectionScrollKeyRef,
			pendingVisibleHeaderPublishFrameRef,
			recentInstantSelectionRevealRef,
			scrollActivityActiveRef,
			scrollIdleTimeoutRef,
		],
	);

	useEffect((): (() => void) | undefined => {
		if (onVisibleItemIdsChange === undefined) return undefined;
		publishVisibleItemIdsFromCurrentHandle();
		const animationFrameId = requestAnimationFrame(publishVisibleItemIdsFromCurrentHandle);
		return (): void => cancelAnimationFrame(animationFrameId);
	}, [
		codeViewMountVersion,
		onVisibleItemIdsChange,
		publishVisibleItemIdsFromCurrentHandle,
		sourceKey,
	]);
}
