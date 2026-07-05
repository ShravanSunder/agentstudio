import type { MutableRefObject } from 'react';

export type BridgeCodeViewProgrammaticRevealIntent =
	| 'hydration-reissue'
	| 'retarget'
	| 'selection-effect';

export interface BridgeCodeViewProgrammaticRevealRequest {
	readonly revealIntent: BridgeCodeViewProgrammaticRevealIntent;
	readonly targetItemId: string;
}

export interface BridgeCodeViewProgrammaticRevealGate {
	readonly onProgrammaticRevealSkipped: (request: BridgeCodeViewProgrammaticRevealRequest) => void;
	readonly shouldSkipProgrammaticReveal: (
		request: BridgeCodeViewProgrammaticRevealRequest,
	) => boolean;
}

export function createBridgeCodeViewProgrammaticRevealGate(props: {
	readonly isScrollActive: () => boolean;
	readonly lastRevealedItemId: () => string | null;
	readonly onProgrammaticRevealSkipped: (request: BridgeCodeViewProgrammaticRevealRequest) => void;
}): BridgeCodeViewProgrammaticRevealGate {
	return {
		onProgrammaticRevealSkipped: props.onProgrammaticRevealSkipped,
		shouldSkipProgrammaticReveal: (request): boolean =>
			shouldSkipBridgeCodeViewProgrammaticReveal({
				isScrollActive: props.isScrollActive(),
				lastRevealedItemId: props.lastRevealedItemId(),
				revealIntent: request.revealIntent,
				targetItemId: request.targetItemId,
			}),
	};
}

export function cancelBridgeCodeViewPendingProgrammaticReveal(props: {
	readonly pendingPreHydrationSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<unknown>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly recentInstantSelectionRevealRef: MutableRefObject<unknown>;
}): void {
	if (props.pendingSelectionScrollFrameRef.current !== null) {
		cancelAnimationFrame(props.pendingSelectionScrollFrameRef.current);
		props.pendingSelectionScrollFrameRef.current = null;
	}
	props.pendingPreHydrationSelectionScrollKeyRef.current = null;
	props.pendingSelectionRevealBehaviorRef.current = null;
	props.pendingSmoothSelectionScrollKeyRef.current = null;
	props.recentInstantSelectionRevealRef.current = null;
}

export function skipBridgeCodeViewProgrammaticRevealIfNeeded(props: {
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly recentInstantSelectionRevealRef: MutableRefObject<unknown>;
	readonly revealIntent: BridgeCodeViewProgrammaticRevealIntent;
	readonly selectionScrollKey?: string | undefined;
	readonly settledInstantSelectionRevealKeyRef?: MutableRefObject<string | null> | undefined;
	readonly targetItemId: string;
}): boolean {
	const revealRequest = {
		revealIntent: props.revealIntent,
		targetItemId: props.targetItemId,
	};
	if (!props.programmaticRevealGate.shouldSkipProgrammaticReveal(revealRequest)) {
		return false;
	}
	props.recentInstantSelectionRevealRef.current = null;
	if (
		props.selectionScrollKey !== undefined &&
		props.settledInstantSelectionRevealKeyRef !== undefined
	) {
		props.settledInstantSelectionRevealKeyRef.current = props.selectionScrollKey;
	}
	props.programmaticRevealGate.onProgrammaticRevealSkipped(revealRequest);
	return true;
}

export function shouldSkipBridgeCodeViewProgrammaticReveal(props: {
	readonly isScrollActive: boolean;
	readonly lastRevealedItemId: string | null;
	readonly revealIntent: BridgeCodeViewProgrammaticRevealIntent;
	readonly targetItemId: string;
}): boolean {
	if (!props.isScrollActive) {
		return false;
	}
	if (props.revealIntent === 'selection-effect') {
		return props.lastRevealedItemId === props.targetItemId;
	}
	return true;
}
