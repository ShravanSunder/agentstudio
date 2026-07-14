import type { CodeViewHandle } from '@pierre/diffs/react';
import type { MutableRefObject } from 'react';

import {
	bridgeCodeViewRenderedHeaderCorrectionTargetPosition,
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	renderedBridgeCodeViewHeaderOffsetFromScrollOwner,
	shouldApplyBridgeCodeViewRenderedHeaderCorrection,
	type BridgeCodeViewInstantRevealRearmCandidate,
} from './bridge-code-view-panel-support.js';
import {
	bridgeCodeViewInstantRevealPolicy,
	codeViewSelectionScrollRetryFrameBudget,
} from './bridge-code-view-panel-types.js';
import {
	skipBridgeCodeViewProgrammaticRevealIfNeeded,
	type BridgeCodeViewProgrammaticRevealGate,
} from './bridge-code-view-programmatic-reveal-gate.js';

export interface ScheduleBridgeCodeViewInstantRevealRetargetProps {
	readonly codeViewHandle: CodeViewHandle<undefined>;
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly itemId: string;
	readonly lastSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly remainingFrameBudget: number;
	readonly selectionScrollKey: string;
	readonly settledInstantSelectionRevealKeyRef: MutableRefObject<string | null>;
	readonly viewportOffsetTolerancePixels: number;
}

export interface ScheduleBridgeCodeViewInstantRevealRetargetForPanelProps {
	readonly codeViewHandle: CodeViewHandle<undefined>;
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly itemId: string;
	readonly lastSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly selectionScrollKey: string;
	readonly settledInstantSelectionRevealKeyRef: MutableRefObject<string | null>;
	readonly viewportOffsetTolerancePixels: number;
}

export function scheduleBridgeCodeViewInstantRevealRetargetForPanel(
	props: ScheduleBridgeCodeViewInstantRevealRetargetForPanelProps,
): void {
	if (
		skipBridgeCodeViewProgrammaticRevealIfNeeded({
			currentSelectionScrollKeyRef: props.lastSelectionScrollKeyRef,
			programmaticRevealGate: props.programmaticRevealGate,
			recentInstantSelectionRevealRef: props.recentInstantSelectionRevealRef,
			revealIntent: 'retarget',
			selectionScrollKey: props.selectionScrollKey,
			settledInstantSelectionRevealKeyRef: props.settledInstantSelectionRevealKeyRef,
			targetItemId: props.itemId,
		})
	) {
		return;
	}
	scheduleBridgeCodeViewInstantRevealRetarget({
		...props,
		remainingFrameBudget: codeViewSelectionScrollRetryFrameBudget,
	});
}

export function scheduleBridgeCodeViewInstantRevealRetarget(
	props: ScheduleBridgeCodeViewInstantRevealRetargetProps,
): void {
	if (props.pendingSelectionScrollFrameRef.current !== null) {
		cancelAnimationFrame(props.pendingSelectionScrollFrameRef.current);
		props.pendingSelectionScrollFrameRef.current = null;
	}
	let didApplyRenderedHeaderCorrection = false;
	let lastRetargetedItemTop: number | null = null;
	let stableResolvedTopFrameCount = 0;
	let committedRevealScrollTop: number | null = null;
	const scheduleRetargetFrame = (remainingFrameBudget: number): void => {
		props.pendingSelectionScrollFrameRef.current = requestAnimationFrame((): void => {
			props.pendingSelectionScrollFrameRef.current = null;
			if (
				props.codeViewHandleRef.current !== props.codeViewHandle ||
				props.lastSelectionScrollKeyRef.current !== props.selectionScrollKey ||
				props.codeViewHandle.getItem(props.itemId) === undefined
			) {
				return;
			}
			if (
				skipBridgeCodeViewProgrammaticRevealIfNeeded({
					currentSelectionScrollKeyRef: props.lastSelectionScrollKeyRef,
					programmaticRevealGate: props.programmaticRevealGate,
					recentInstantSelectionRevealRef: props.recentInstantSelectionRevealRef,
					revealIntent: 'retarget',
					selectionScrollKey: props.selectionScrollKey,
					settledInstantSelectionRevealKeyRef: props.settledInstantSelectionRevealKeyRef,
					targetItemId: props.itemId,
				})
			) {
				return;
			}
			const codeViewInstance = props.codeViewHandle.getInstance();
			if (codeViewInstance === undefined) {
				return;
			}
			const externalScrollThresholdPixels = Math.max(
				bridgeCodeViewInstantRevealPolicy.externalScrollAbortThresholdPixels,
				codeViewInstance.getContainerElement()?.clientHeight ?? 0,
			);
			if (
				committedRevealScrollTop !== null &&
				Math.abs(codeViewInstance.getScrollTop() - committedRevealScrollTop) >
					externalScrollThresholdPixels
			) {
				props.recentInstantSelectionRevealRef.current = null;
				props.settledInstantSelectionRevealKeyRef.current = props.selectionScrollKey;
				props.programmaticRevealGate.transitionSelectionReveal({
					phase: 'cancelled',
					selectionScrollKey: props.selectionScrollKey,
				});
				return;
			}
			const resolvedItemTop = codeViewInstance.getTopForItem(props.itemId);
			const targetViewportOffset =
				resolvedItemTop === undefined ? null : resolvedItemTop - codeViewInstance.getScrollTop();
			const shouldRetarget =
				resolvedItemTop === undefined ||
				lastRetargetedItemTop === null ||
				Math.abs(resolvedItemTop - lastRetargetedItemTop) >
					bridgeCodeViewInstantRevealPolicy.retargetEpsilonPixels ||
				targetViewportOffset === null ||
				Math.abs(targetViewportOffset) > props.viewportOffsetTolerancePixels;
			if (shouldRetarget) {
				stableResolvedTopFrameCount = 0;
				lastRetargetedItemTop = resolvedItemTop ?? null;
				props.codeViewHandle.scrollTo({
					type: 'item',
					id: props.itemId,
					align: 'start',
					behavior: 'instant',
				});
			} else {
				stableResolvedTopFrameCount += 1;
				if (stableResolvedTopFrameCount >= bridgeCodeViewInstantRevealPolicy.stableFrameCount) {
					const settledItem = props.codeViewHandle.getItem(props.itemId);
					const isSettledMaterialized =
						isBridgeCodeViewItem(settledItem) &&
						isMaterializedBridgeCodeViewContentState(settledItem.bridgeMetadata.contentState);
					if (
						props.recentInstantSelectionRevealRef.current?.selectionScrollKey !==
						props.selectionScrollKey
					) {
						return;
					}
					const renderedHeaderOffset = renderedBridgeCodeViewHeaderOffsetFromScrollOwner({
						itemId: props.itemId,
						scrollOwner: codeViewInstance.getContainerElement(),
					});
					if (renderedHeaderOffset === null && remainingFrameBudget > 0) {
						scheduleRetargetFrame(remainingFrameBudget - 1);
						return;
					}
					if (
						renderedHeaderOffset !== null &&
						shouldApplyBridgeCodeViewRenderedHeaderCorrection({
							didApplyRenderedHeaderCorrection,
							isSelectedContentMaterialized: isSettledMaterialized,
							renderedHeaderOffset,
							tolerancePixels:
								bridgeCodeViewInstantRevealPolicy.renderedHeaderOffsetTolerancePixels,
						})
					) {
						didApplyRenderedHeaderCorrection = true;
						props.codeViewHandle.scrollTo({
							type: 'position',
							position: bridgeCodeViewRenderedHeaderCorrectionTargetPosition({
								currentScrollTop: codeViewInstance.getScrollTop(),
								renderedHeaderOffset,
							}),
							behavior: 'instant',
						});
					}
					if (isSettledMaterialized) {
						props.recentInstantSelectionRevealRef.current = null;
						props.settledInstantSelectionRevealKeyRef.current = props.selectionScrollKey;
						props.programmaticRevealGate.transitionSelectionReveal({
							phase: 'settled',
							selectionScrollKey: props.selectionScrollKey,
						});
					} else {
						props.programmaticRevealGate.transitionSelectionReveal({
							phase: 'awaiting-hydration',
							selectionScrollKey: props.selectionScrollKey,
						});
					}
				}
			}
			committedRevealScrollTop = codeViewInstance.getScrollTop();
			if (
				remainingFrameBudget > 0 &&
				stableResolvedTopFrameCount < bridgeCodeViewInstantRevealPolicy.stableFrameCount
			) {
				scheduleRetargetFrame(remainingFrameBudget - 1);
			}
		});
	};
	scheduleRetargetFrame(props.remainingFrameBudget);
}
