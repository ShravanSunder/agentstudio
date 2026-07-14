import type { MutableRefObject } from 'react';

export type BridgeCodeViewProgrammaticRevealIntent =
	| 'hydration-reissue'
	| 'retarget'
	| 'selection-effect';

export interface BridgeCodeViewProgrammaticRevealRequest {
	readonly revealIntent: BridgeCodeViewProgrammaticRevealIntent;
	readonly selectionScrollKey?: string | undefined;
	readonly targetItemId: string;
}

export type BridgeCodeViewSelectionRevealPhase =
	| 'awaiting-hydration'
	| 'cancelled'
	| 'initial'
	| 'retargeting'
	| 'settled';

export interface BridgeCodeViewSelectionRevealIdentity {
	readonly selectionScrollKey: string;
	readonly targetItemId: string;
}

interface BridgeCodeViewActiveSelectionReveal extends BridgeCodeViewSelectionRevealIdentity {
	readonly phase: BridgeCodeViewSelectionRevealPhase;
	readonly userScrollGenerationAtStart: number;
}

export interface BridgeCodeViewProgrammaticRevealGate {
	readonly beginSelectionReveal: (request: BridgeCodeViewSelectionRevealIdentity) => boolean;
	readonly onProgrammaticRevealSkipped: (request: BridgeCodeViewProgrammaticRevealRequest) => void;
	readonly recordUserScrollIntent: () => void;
	readonly shouldSkipProgrammaticReveal: (
		request: BridgeCodeViewProgrammaticRevealRequest,
	) => boolean;
	readonly transitionSelectionReveal: (request: {
		readonly phase: BridgeCodeViewSelectionRevealPhase;
		readonly selectionScrollKey: string;
	}) => void;
}

export function createBridgeCodeViewProgrammaticRevealGate(props: {
	readonly isScrollActive: () => boolean;
	readonly lastRevealedItemId: () => string | null;
	readonly onProgrammaticRevealSkipped: (request: BridgeCodeViewProgrammaticRevealRequest) => void;
}): BridgeCodeViewProgrammaticRevealGate {
	let activeSelectionReveal: BridgeCodeViewActiveSelectionReveal | null = null;
	let userScrollGeneration = 0;

	return {
		beginSelectionReveal: (request): boolean => {
			if (props.isScrollActive() && props.lastRevealedItemId() === request.targetItemId) {
				return false;
			}
			activeSelectionReveal = {
				...request,
				phase: 'initial',
				userScrollGenerationAtStart: userScrollGeneration,
			};
			return true;
		},
		onProgrammaticRevealSkipped: props.onProgrammaticRevealSkipped,
		recordUserScrollIntent: (): void => {
			userScrollGeneration += 1;
			if (
				activeSelectionReveal !== null &&
				activeSelectionReveal.phase !== 'cancelled' &&
				activeSelectionReveal.phase !== 'settled'
			) {
				activeSelectionReveal = { ...activeSelectionReveal, phase: 'cancelled' };
			}
		},
		shouldSkipProgrammaticReveal: (request): boolean => {
			if (request.selectionScrollKey !== undefined) {
				return !selectionRevealCanPerformRequest({
					activeSelectionReveal,
					request: {
						...request,
						selectionScrollKey: request.selectionScrollKey,
					},
					userScrollGeneration,
				});
			}
			return shouldSkipBridgeCodeViewProgrammaticReveal({
				isScrollActive: props.isScrollActive(),
				lastRevealedItemId: props.lastRevealedItemId(),
				revealIntent: request.revealIntent,
				targetItemId: request.targetItemId,
			});
		},
		transitionSelectionReveal: (request): void => {
			if (
				activeSelectionReveal === null ||
				activeSelectionReveal.selectionScrollKey !== request.selectionScrollKey ||
				activeSelectionReveal.phase === 'cancelled' ||
				activeSelectionReveal.phase === 'settled'
			) {
				return;
			}
			activeSelectionReveal = { ...activeSelectionReveal, phase: request.phase };
		},
	};
}

function selectionRevealCanPerformRequest(props: {
	readonly activeSelectionReveal: BridgeCodeViewActiveSelectionReveal | null;
	readonly request: BridgeCodeViewProgrammaticRevealRequest & {
		readonly selectionScrollKey: string;
	};
	readonly userScrollGeneration: number;
}): boolean {
	const activeSelectionReveal = props.activeSelectionReveal;
	if (
		activeSelectionReveal === null ||
		activeSelectionReveal.selectionScrollKey !== props.request.selectionScrollKey ||
		activeSelectionReveal.targetItemId !== props.request.targetItemId ||
		activeSelectionReveal.userScrollGenerationAtStart !== props.userScrollGeneration ||
		activeSelectionReveal.phase === 'cancelled' ||
		activeSelectionReveal.phase === 'settled'
	) {
		return false;
	}
	return (
		props.request.revealIntent !== 'selection-effect' || activeSelectionReveal.phase === 'initial'
	);
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
	readonly currentSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly recentInstantSelectionRevealRef: MutableRefObject<unknown>;
	readonly revealIntent: BridgeCodeViewProgrammaticRevealIntent;
	readonly selectionScrollKey?: string | undefined;
	readonly settledInstantSelectionRevealKeyRef?: MutableRefObject<string | null> | undefined;
	readonly targetItemId: string;
}): boolean {
	const revealRequest = {
		revealIntent: props.revealIntent,
		...(props.selectionScrollKey === undefined
			? {}
			: { selectionScrollKey: props.selectionScrollKey }),
		targetItemId: props.targetItemId,
	};
	if (!props.programmaticRevealGate.shouldSkipProgrammaticReveal(revealRequest)) {
		return false;
	}
	const skippedRequestOwnsCurrentSelection =
		props.selectionScrollKey === undefined ||
		props.currentSelectionScrollKeyRef.current === props.selectionScrollKey;
	if (skippedRequestOwnsCurrentSelection) {
		props.recentInstantSelectionRevealRef.current = null;
		if (
			props.selectionScrollKey !== undefined &&
			props.settledInstantSelectionRevealKeyRef !== undefined
		) {
			props.settledInstantSelectionRevealKeyRef.current = props.selectionScrollKey;
		}
		props.programmaticRevealGate.onProgrammaticRevealSkipped(revealRequest);
	}
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
