import type { CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, type MutableRefObject } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { type BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	codeViewHandleHasInstance,
	collapsedItemIdsWithItemState,
	controllerForHandle,
	isBridgeCodeViewItem,
	nextCodeViewItemForCollapse,
	shouldRequestForegroundDemandForItemExpansion,
	type BridgeCodeViewControllerEntry,
	type BridgeCodeViewInstantRevealRearmCandidate,
} from './bridge-code-view-panel-support.js';

interface UseBridgeCodeViewCollapseControllerProps {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly collapsedItemIdsRef: MutableRefObject<ReadonlySet<string>>;
	readonly controllerEntryRef: MutableRefObject<BridgeCodeViewControllerEntry | null>;
	readonly pendingPreHydrationSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly pendingSelectionRevealBehaviorRef: MutableRefObject<CodeViewScrollBehavior | null>;
	readonly pendingSmoothSelectionScrollKeyRef: MutableRefObject<string | null>;
	readonly recentInstantSelectionRevealRef: MutableRefObject<BridgeCodeViewInstantRevealRearmCandidate | null>;
	readonly onExpandedItemDemand?: (itemId: string) => void;
	readonly reviewItemsById: BridgeReviewPackage['itemsById'];
	readonly setCollapsedItemIds: (
		updater: (currentIds: ReadonlySet<string>) => ReadonlySet<string>,
	) => void;
	readonly settledInstantSelectionRevealKeyRef: MutableRefObject<string | null>;
}

export interface BridgeCodeViewCollapseController {
	readonly setItemCollapsed: (itemId: string, collapsed: boolean) => boolean;
	readonly toggleItemCollapse: (itemId: string) => void;
}

/**
 * Owns collapse/expand of a single CodeView item. Split out of BridgeCodeViewPanel so the
 * panel stays focused on reveal/materialization sequencing; collapsing clears the pending
 * reveal bookkeeping because a collapse is a fresh, terminal viewport intent.
 */
export function useBridgeCodeViewCollapseController(
	props: UseBridgeCodeViewCollapseControllerProps,
): BridgeCodeViewCollapseController {
	const {
		codeViewHandleRef,
		collapsedItemIdsRef,
		controllerEntryRef,
		pendingPreHydrationSelectionScrollKeyRef,
		pendingSelectionRevealBehaviorRef,
		pendingSmoothSelectionScrollKeyRef,
		recentInstantSelectionRevealRef,
		onExpandedItemDemand,
		reviewItemsById,
		setCollapsedItemIds,
		settledInstantSelectionRevealKeyRef,
	} = props;

	const setItemCollapsed = useCallback(
		(itemId: string, collapsed: boolean): boolean => {
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null) {
				return false;
			}
			if (!codeViewHandleHasInstance(codeViewHandle)) {
				return false;
			}
			const currentItem = codeViewHandle.getItem(itemId);
			if (currentItem === undefined || !isBridgeCodeViewItem(currentItem)) {
				return false;
			}
			const previousCollapsed =
				collapsedItemIdsRef.current.has(itemId) || currentItem.collapsed === true;
			const shouldRequestExpandedItemDemand = shouldRequestForegroundDemandForItemExpansion({
				nextCollapsed: collapsed,
				previousCollapsed,
			});
			if (currentItem.collapsed === collapsed) {
				setCollapsedItemIds(
					(currentIds: ReadonlySet<string>): ReadonlySet<string> =>
						collapsedItemIdsWithItemState({
							collapsed,
							currentIds,
							itemId,
						}),
				);
				if (shouldRequestExpandedItemDemand) {
					onExpandedItemDemand?.(itemId);
				}
				return true;
			}
			pendingPreHydrationSelectionScrollKeyRef.current = null;
			pendingSelectionRevealBehaviorRef.current = null;
			pendingSmoothSelectionScrollKeyRef.current = null;
			recentInstantSelectionRevealRef.current = null;
			settledInstantSelectionRevealKeyRef.current = null;
			const itemDescriptor = reviewItemsById[itemId];
			const nextItem =
				itemDescriptor === undefined
					? ({
							...currentItem,
							collapsed,
							version: (currentItem.version ?? 0) + 1,
						} satisfies BridgeCodeViewItem)
					: nextCodeViewItemForCollapse({
							collapsed,
							currentItem,
							itemDescriptor,
						});
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef,
			});
			// F6: collapse via a single item update and let Pierre's first-visible anchor hold
			// the viewport. Collapsing only removes body rows below the header, so the header
			// keeps its position without an app-side DOM anchor. F7: no forced render(true) —
			// updateItem's queued render coalesces and re-applies Pierre's anchor.
			controller.applyItemUpdate(nextItem);
			setCollapsedItemIds(
				(currentIds: ReadonlySet<string>): ReadonlySet<string> =>
					collapsedItemIdsWithItemState({
						collapsed,
						currentIds,
						itemId,
					}),
			);
			if (shouldRequestExpandedItemDemand) {
				onExpandedItemDemand?.(itemId);
			}
			return true;
		},
		[
			codeViewHandleRef,
			collapsedItemIdsRef,
			controllerEntryRef,
			onExpandedItemDemand,
			pendingPreHydrationSelectionScrollKeyRef,
			pendingSelectionRevealBehaviorRef,
			pendingSmoothSelectionScrollKeyRef,
			recentInstantSelectionRevealRef,
			reviewItemsById,
			setCollapsedItemIds,
			settledInstantSelectionRevealKeyRef,
		],
	);

	const toggleItemCollapse = useCallback(
		(itemId: string): void => {
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle !== null && !codeViewHandleHasInstance(codeViewHandle)) {
				return;
			}
			const currentItem = codeViewHandle?.getItem(itemId);
			if (currentItem === undefined || !isBridgeCodeViewItem(currentItem)) {
				setCollapsedItemIds(
					(currentIds: ReadonlySet<string>): ReadonlySet<string> =>
						collapsedItemIdsWithItemState({
							collapsed: !currentIds.has(itemId),
							currentIds,
							itemId,
						}),
				);
				return;
			}
			const isCollapsed = collapsedItemIdsRef.current.has(itemId) || currentItem.collapsed === true;
			setItemCollapsed(itemId, !isCollapsed);
		},
		[codeViewHandleRef, collapsedItemIdsRef, setCollapsedItemIds, setItemCollapsed],
	);

	return { setItemCollapsed, toggleItemCollapse };
}
