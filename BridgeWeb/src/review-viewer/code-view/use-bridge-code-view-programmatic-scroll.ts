import type { CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, type MutableRefObject } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { scheduleBridgeCodeViewInstantRevealRetargetForPanel } from './bridge-code-view-instant-reveal-retarget.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	bridgeCodeViewItemsWithMetadataItem,
	codeViewHandleHasInstance,
	controllerForHandle,
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	nextCodeViewItemForCollapse,
	type BridgeCodeViewControllerEntry,
	type BridgeCodeViewInstantRevealRearmCandidate,
} from './bridge-code-view-panel-support.js';
import {
	bridgeCodeViewInstantRevealPolicy,
	type BridgeCodeViewScrollToItemOptions,
} from './bridge-code-view-panel-types.js';
import type { BridgeCodeViewProgrammaticRevealGate } from './bridge-code-view-programmatic-reveal-gate.js';

interface UseBridgeCodeViewProgrammaticScrollProps {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly codeViewMountVersion: number;
	readonly completedSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly controllerEntryRef: MutableRefObject<BridgeCodeViewControllerEntry | null>;
	readonly currentCodeViewItemsRef: MutableRefObject<readonly BridgeCodeViewItem[]>;
	readonly lastProgrammaticRevealItemIdRef: MutableRefObject<string | null>;
	readonly lastSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<CodeViewScrollBehavior | null>;
	readonly pendingSelectionScrollFrameRef: MutableRefObject<number | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly programmaticRevealGate: BridgeCodeViewProgrammaticRevealGate;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly reviewItemsById: BridgeReviewPackage['itemsById'];
	readonly setCollapsedItemIds: (
		updater: (currentIds: ReadonlySet<string>) => ReadonlySet<string>,
	) => void;
	readonly settledInstantSelectionRevealKeyRef: MutableRefObject<string | null>;
	readonly sourceKey: string;
}

export interface BridgeCodeViewProgrammaticScrollController {
	readonly scheduleInstantSelectionRevealRetarget: (params: {
		readonly codeViewHandle: CodeViewHandle<undefined>;
		readonly itemId: string;
		readonly selectionScrollKey: string;
		readonly viewportOffsetTolerancePixels: number;
	}) => void;
	readonly scrollToItem: (itemId: string, options?: BridgeCodeViewScrollToItemOptions) => boolean;
}

export function useBridgeCodeViewProgrammaticScroll(
	props: UseBridgeCodeViewProgrammaticScrollProps,
): BridgeCodeViewProgrammaticScrollController {
	const {
		codeViewHandleRef,
		codeViewMountVersion,
		completedSelectionScrollKeyRef,
		controllerEntryRef,
		currentCodeViewItemsRef,
		lastProgrammaticRevealItemIdRef,
		lastSelectionScrollKeyRef,
		pendingSelectionRevealBehaviorRef,
		pendingSelectionScrollFrameRef,
		pendingSmoothSelectionScrollKeyRef,
		programmaticRevealGate,
		recentInstantSelectionRevealRef,
		reviewItemsById,
		setCollapsedItemIds,
		settledInstantSelectionRevealKeyRef,
		sourceKey,
	} = props;
	const scheduleInstantSelectionRevealRetarget = useCallback(
		(params: {
			readonly codeViewHandle: CodeViewHandle<undefined>;
			readonly itemId: string;
			readonly selectionScrollKey: string;
			readonly viewportOffsetTolerancePixels: number;
		}): void => {
			programmaticRevealGate.transitionSelectionReveal({
				phase: 'retargeting',
				selectionScrollKey: params.selectionScrollKey,
			});
			scheduleBridgeCodeViewInstantRevealRetargetForPanel({
				codeViewHandle: params.codeViewHandle,
				codeViewHandleRef: codeViewHandleRef,
				itemId: params.itemId,
				lastSelectionScrollKeyRef: lastSelectionScrollKeyRef,
				pendingSelectionScrollFrameRef: pendingSelectionScrollFrameRef,
				programmaticRevealGate: programmaticRevealGate,
				recentInstantSelectionRevealRef: recentInstantSelectionRevealRef,
				selectionScrollKey: params.selectionScrollKey,
				settledInstantSelectionRevealKeyRef: settledInstantSelectionRevealKeyRef,
				viewportOffsetTolerancePixels: params.viewportOffsetTolerancePixels,
			});
		},
		[
			codeViewHandleRef,
			lastSelectionScrollKeyRef,
			pendingSelectionScrollFrameRef,
			programmaticRevealGate,
			recentInstantSelectionRevealRef,
			settledInstantSelectionRevealKeyRef,
		],
	);
	const scrollToItem = useCallback(
		(itemId: string, options: BridgeCodeViewScrollToItemOptions = {}): boolean => {
			const revealRequest = {
				revealIntent: options.revealIntent ?? 'hydration-reissue',
				...(options.selectionScrollKey === undefined
					? {}
					: { selectionScrollKey: options.selectionScrollKey }),
				targetItemId: itemId,
			};
			if (programmaticRevealGate.shouldSkipProgrammaticReveal(revealRequest)) {
				programmaticRevealGate.onProgrammaticRevealSkipped(revealRequest);
				return false;
			}
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null) {
				return false;
			}
			if (!codeViewHandleHasInstance(codeViewHandle)) {
				return false;
			}
			const currentItem = codeViewHandle.getItem(itemId);
			if (currentItem === undefined) {
				return false;
			}
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef: controllerEntryRef,
			});
			const currentBridgeItem = isBridgeCodeViewItem(currentItem) ? currentItem : null;
			const scrollBehavior = options.behavior ?? 'instant';
			if (
				(options.expandIfCollapsed ?? true) &&
				currentBridgeItem !== null &&
				currentBridgeItem.collapsed === true
			) {
				const itemDescriptor = reviewItemsById[itemId];
				const nextItem =
					itemDescriptor === undefined
						? ({
								...currentBridgeItem,
								collapsed: false,
								version: (currentBridgeItem.version ?? 0) + 1,
							} satisfies BridgeCodeViewItem)
						: nextCodeViewItemForCollapse({
								collapsed: false,
								currentItem: currentBridgeItem,
								itemDescriptor,
							});
				controller.applyItemUpdate(nextItem);
				currentCodeViewItemsRef.current = bridgeCodeViewItemsWithMetadataItem({
					currentItems: currentCodeViewItemsRef.current,
					item: nextItem,
				});
				setCollapsedItemIds((currentIds: ReadonlySet<string>): ReadonlySet<string> => {
					const nextIds = new Set(currentIds);
					nextIds.delete(itemId);
					return nextIds;
				});
			}
			controller.scrollToItem(itemId, scrollBehavior);
			lastProgrammaticRevealItemIdRef.current = itemId;
			const selectionScrollKey =
				options.selectionScrollKey ?? `${sourceKey}:${codeViewMountVersion}:${itemId}`;
			lastSelectionScrollKeyRef.current = selectionScrollKey;
			if (
				currentBridgeItem !== null &&
				isMaterializedBridgeCodeViewContentState(currentBridgeItem.bridgeMetadata.contentState)
			) {
				completedSelectionScrollKeyRef.current = selectionScrollKey;
			}
			if (scrollBehavior === 'instant') {
				pendingSmoothSelectionScrollKeyRef.current = null;
				pendingSelectionRevealBehaviorRef.current = null;
				settledInstantSelectionRevealKeyRef.current = null;
				recentInstantSelectionRevealRef.current = {
					itemId,
					revealedAtMilliseconds: performance.now(),
					selectionScrollKey,
				};
				scheduleInstantSelectionRevealRetarget({
					codeViewHandle,
					itemId,
					selectionScrollKey,
					viewportOffsetTolerancePixels:
						bridgeCodeViewInstantRevealPolicy.viewportOffsetTolerancePixels,
				});
			} else {
				pendingSmoothSelectionScrollKeyRef.current = selectionScrollKey;
				pendingSelectionRevealBehaviorRef.current = scrollBehavior;
				recentInstantSelectionRevealRef.current = null;
				settledInstantSelectionRevealKeyRef.current = null;
			}
			return true;
		},
		[
			codeViewHandleRef,
			codeViewMountVersion,
			completedSelectionScrollKeyRef,
			controllerEntryRef,
			currentCodeViewItemsRef,
			lastProgrammaticRevealItemIdRef,
			lastSelectionScrollKeyRef,
			pendingSelectionRevealBehaviorRef,
			pendingSmoothSelectionScrollKeyRef,
			programmaticRevealGate,
			recentInstantSelectionRevealRef,
			reviewItemsById,
			scheduleInstantSelectionRevealRetarget,
			setCollapsedItemIds,
			settledInstantSelectionRevealKeyRef,
			sourceKey,
		],
	);

	return { scheduleInstantSelectionRevealRetarget, scrollToItem };
}
