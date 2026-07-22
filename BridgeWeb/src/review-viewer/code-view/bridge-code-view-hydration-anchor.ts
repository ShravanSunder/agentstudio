import type { CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import type { MutableRefObject } from 'react';

import {
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	type BridgeCodeViewInstantRevealRearmCandidate,
} from './bridge-code-view-panel-support.js';

export interface ConsumeBridgeCodeViewPendingHydrationAnchorProps {
	readonly codeViewHandle: CodeViewHandle<undefined>;
	readonly completedSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly itemId: string;
	readonly nowMilliseconds: number;
	readonly pendingPreHydrationSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<CodeViewScrollBehavior | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly scheduleRetarget: () => void;
	readonly selectionScrollKey: string;
	readonly settledInstantSelectionRevealKeyRef: MutableRefObject<string | null>;
}

/**
 * Consumes one pre-hydration selection obligation after the matching worker
 * metadata batch has installed materialized content in Pierre.
 */
export function consumeBridgeCodeViewPendingHydrationAnchor(
	props: ConsumeBridgeCodeViewPendingHydrationAnchorProps,
): boolean {
	if (props.pendingPreHydrationSelectionScrollKeyRef.current !== props.selectionScrollKey) {
		return false;
	}
	const selectedItem = props.codeViewHandle.getItem(props.itemId);
	if (
		!isBridgeCodeViewItem(selectedItem) ||
		!isMaterializedBridgeCodeViewContentState(selectedItem.bridgeMetadata.contentState)
	) {
		return false;
	}

	props.pendingPreHydrationSelectionScrollKeyRef.current = null;
	props.pendingSelectionRevealBehaviorRef.current = null;
	props.pendingSmoothSelectionScrollKeyRef.current = null;
	props.completedSelectionScrollKeyRef.current = props.selectionScrollKey;
	props.settledInstantSelectionRevealKeyRef.current = null;
	props.recentInstantSelectionRevealRef.current = {
		itemId: props.itemId,
		revealedAtMilliseconds: props.nowMilliseconds,
		selectionScrollKey: props.selectionScrollKey,
	};
	props.scheduleRetarget();
	return true;
}
