import type { CodeViewItem, CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { recordBridgeCodeViewHydrationTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import { BridgeCodeViewPanelFrame } from './bridge-code-view-panel-frame.js';
import {
	captureCodeViewHeaderAnchor,
	codeViewHeaderAnchorRestoreFrameBudget,
	codeViewHandleHasInstance,
	collapsedItemIdsWithItemState,
	controllerForHandle,
	createBridgeCodeViewHeaderRenderers,
	emptyMaterializationDiagnostic,
	hasRenderedItemsSource,
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	makeBridgeCodeViewSourceKey,
	materializationDiagnosticForCodeViewItem,
	nextCodeViewItemForCollapse,
	reconcileBridgeCodeViewMetadataItems,
	restoreCodeViewHeaderAnchorAcrossLayout,
	scrollCodeViewHeaderToScrollTopAcrossLayout,
	selectedContentDiagnosticsForPanel,
	shouldApplyBridgeCodeViewMaterialization,
	settleCodeViewScrollAtCurrentPosition,
	uniqueItemIds,
	uniqueRenderedItemIds,
	type BridgeCodeViewControllerEntry,
	type BridgeCodeViewMaterializationDiagnostic,
	type BridgeCodeViewRenderedItemsSource,
} from './bridge-code-view-panel-support.js';
import {
	codeViewMaterializationRetryFrameBudget,
	codeViewVisibleHydrationScrollIdleMilliseconds,
	codeViewVisibleMetadataScrollThrottleMilliseconds,
	initialSelectionScrollDiagnostic,
	type BridgeCodeViewControlHandle,
	type BridgeCodeViewPanelProps,
	type BridgeCodeViewScrollToItemOptions,
	type BridgeCodeViewSelectionScrollDiagnostic,
} from './bridge-code-view-panel-types.js';
import { createBridgeCodeViewVisibleInterestPublisher } from './bridge-code-view-visible-interest-publisher.js';
import { useBridgeCodeViewSelectionScroll } from './use-bridge-code-view-selection-scroll.js';

export { bridgeCodeViewOptions } from './bridge-code-view-options.js';
export {
	makeBridgeCodeViewSourceKey,
	reconcileBridgeCodeViewMetadataItems,
	selectedContentSummaryForPanel,
	shouldApplyBridgeCodeViewMaterialization,
	shouldContinueCodeViewHeaderPinLoop,
} from './bridge-code-view-panel-support.js';
export type {
	BridgeCodeViewControlHandle,
	BridgeCodeViewPanelProps,
} from './bridge-code-view-panel-types.js';
export type { BridgeCodeViewScrollToItemOptions } from './bridge-code-view-panel-types.js';

export function BridgeCodeViewPanel(props: BridgeCodeViewPanelProps): ReactElement {
	const sourceKey = makeBridgeCodeViewSourceKey(props);
	const selectedDisplayPath =
		props.selectedItemId === null
			? null
			: (props.projection.primaryDisplayPathByItemId[props.selectedItemId] ?? null);
	const selectedReviewItem =
		props.selectedItemId === null
			? null
			: (props.reviewPackage.itemsById[props.selectedItemId] ?? null);
	const selectedContentDiagnostics = selectedContentDiagnosticsForPanel({
		selectedContentResources: props.selectedContentResources,
		selectedItemId: props.selectedItemId,
	});
	const reviewItemsById = props.reviewPackage.itemsById;
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const controllerEntryRef = useRef<BridgeCodeViewControllerEntry | null>(null);
	const completedSelectionScrollKeyRef = useRef<string | null>(null);
	const lastSelectionScrollKeyRef = useRef<string | null>(null);
	const mountedHandleViewerKeyRef = useRef<string | null>(null);
	const materializationTaskGenerationRef = useRef(0);
	const pendingMaterializationFrameRef = useRef<number | null>(null);
	const pendingRecoveryRenderFrameRef = useRef<number | null>(null);
	const pendingPreHydrationSelectionScrollKeyRef = useRef<string | null>(null);
	const pendingSelectionScrollFrameRef = useRef<number | null>(null);
	const pendingSelectionRevealBehaviorRef = useRef<CodeViewScrollBehavior | null>(null);
	const pendingSmoothSelectionScrollKeyRef = useRef<string | null>(null);
	const pendingVisibleHeaderPublishFrameRef = useRef<number | null>(null);
	const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const scrollActivityActiveRef = useRef(false);
	const renderedWindowItemIdsRef = useRef<readonly string[]>([]);
	const scrollToTopTargetItemIdRef = useRef<string | null>(null);
	const visibleHeaderItemIdsRef = useRef<ReadonlySet<string>>(new Set<string>());
	const onScrollActivityChangeRef = useRef(props.onScrollActivityChange);
	onScrollActivityChangeRef.current = props.onScrollActivityChange;
	const initialSelectedItemByViewerKeyRef = useRef<{
		readonly selectedItemId: string | null;
		readonly sourceKey: string;
	} | null>(null);
	if (initialSelectedItemByViewerKeyRef.current?.sourceKey !== sourceKey) {
		initialSelectedItemByViewerKeyRef.current = {
			selectedItemId: props.selectedItemId,
			sourceKey,
		};
	}
	const [codeViewMountVersion, setCodeViewMountVersion] = useState(0);
	const [isCodeViewScrollActive, setIsCodeViewScrollActive] = useState(false);
	const [collapsedItemIds, setCollapsedItemIds] = useState<ReadonlySet<string>>(
		() => new Set<string>(),
	);
	const [selectionScrollDiagnostic, setSelectionScrollDiagnostic] =
		useState<BridgeCodeViewSelectionScrollDiagnostic>(initialSelectionScrollDiagnostic);
	const collapsedItemIdsRef = useRef<ReadonlySet<string>>(collapsedItemIds);
	collapsedItemIdsRef.current = collapsedItemIds;
	const onControlHandleChange = props.onControlHandleChange;
	const [materializationDiagnostic, setMaterializationDiagnostic] =
		useState<BridgeCodeViewMaterializationDiagnostic>(() => emptyMaterializationDiagnostic());
	const publishVisibleHydrationItemIds = useCallback((): void => {
		const onVisibleItemIdsChange = props.onVisibleItemIdsChange;
		if (onVisibleItemIdsChange === undefined) {
			return;
		}
		onVisibleItemIdsChange(
			uniqueItemIds([...visibleHeaderItemIdsRef.current, ...renderedWindowItemIdsRef.current]),
		);
	}, [props.onVisibleItemIdsChange]);
	const visibleInterestPublisher = useMemo(
		() =>
			createBridgeCodeViewVisibleInterestPublisher<ReturnType<typeof setTimeout>>({
				clearTimeout: (handle): void => {
					clearTimeout(handle);
				},
				now: (): number => performance.now(),
				publish: publishVisibleHydrationItemIds,
				setTimeout: (callback, delayMilliseconds): ReturnType<typeof setTimeout> =>
					setTimeout(callback, delayMilliseconds),
				throttleMilliseconds: codeViewVisibleMetadataScrollThrottleMilliseconds,
			}),
		[publishVisibleHydrationItemIds],
	);
	const captureVisibleItemIds = useCallback((source: BridgeCodeViewRenderedItemsSource): void => {
		renderedWindowItemIdsRef.current = uniqueRenderedItemIds(source.getRenderedItems());
	}, []);
	const publishVisibleItemIds = useCallback(
		(source: BridgeCodeViewRenderedItemsSource): void => {
			captureVisibleItemIds(source);
			publishVisibleHydrationItemIds();
		},
		[captureVisibleItemIds, publishVisibleHydrationItemIds],
	);
	const publishVisibleItemIdsFromCurrentHandle = useCallback((): void => {
		const instance = codeViewHandleRef.current?.getInstance();
		if (instance === undefined || !hasRenderedItemsSource(instance)) {
			return;
		}
		publishVisibleItemIds(instance);
	}, [publishVisibleItemIds]);
	const handleCodeViewScroll = useCallback(
		(_scrollTop: number, viewer: BridgeCodeViewRenderedItemsSource): void => {
			captureVisibleItemIds(viewer);
			visibleInterestPublisher.publishDuringScroll();
			if (!scrollActivityActiveRef.current) {
				scrollActivityActiveRef.current = true;
				setIsCodeViewScrollActive(true);
				onScrollActivityChangeRef.current?.(true);
			}
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
			}
			scrollIdleTimeoutRef.current = setTimeout((): void => {
				scrollIdleTimeoutRef.current = null;
				captureVisibleItemIds(viewer);
				scrollActivityActiveRef.current = false;
				setIsCodeViewScrollActive(false);
				onScrollActivityChangeRef.current?.(false);
				visibleInterestPublisher.publishAtScrollIdle();
			}, codeViewVisibleHydrationScrollIdleMilliseconds);
		},
		[captureVisibleItemIds, visibleInterestPublisher],
	);
	const scheduleVisibleHeaderItemIdsPublish = useCallback((): void => {
		if (scrollActivityActiveRef.current) {
			visibleInterestPublisher.publishDuringScroll();
			return;
		}
		if (pendingVisibleHeaderPublishFrameRef.current !== null) {
			cancelAnimationFrame(pendingVisibleHeaderPublishFrameRef.current);
		}
		pendingVisibleHeaderPublishFrameRef.current = requestAnimationFrame((): void => {
			pendingVisibleHeaderPublishFrameRef.current = null;
			publishVisibleHydrationItemIds();
		});
	}, [publishVisibleHydrationItemIds, visibleInterestPublisher]);
	const handleHeaderVisibilityChange = useCallback(
		(itemId: string, isVisible: boolean): void => {
			const nextVisibleItemIds = new Set(visibleHeaderItemIdsRef.current);
			if (isVisible) {
				nextVisibleItemIds.add(itemId);
			} else {
				nextVisibleItemIds.delete(itemId);
			}
			visibleHeaderItemIdsRef.current = nextVisibleItemIds;
			scheduleVisibleHeaderItemIdsPublish();
			const codeViewHandle = codeViewHandleRef.current;
			if (isVisible && codeViewHandle !== null && scrollToTopTargetItemIdRef.current === itemId) {
				scrollCodeViewHeaderToScrollTopAcrossLayout({
					handle: codeViewHandle,
					itemId,
					isCurrent: (): boolean =>
						codeViewHandleRef.current === codeViewHandle &&
						scrollToTopTargetItemIdRef.current === itemId,
				});
			}
		},
		[scheduleVisibleHeaderItemIdsPublish],
	);

	useEffect(
		(): (() => void) => (): void => {
			visibleInterestPublisher.cancel();
		},
		[visibleInterestPublisher],
	);

	const setCodeViewHandle = useCallback(
		(handle: CodeViewHandle<undefined> | null): void => {
			const previousHandle = codeViewHandleRef.current;
			codeViewHandleRef.current = handle;
			if (handle === null) {
				mountedHandleViewerKeyRef.current = null;
				return;
			}
			if (previousHandle !== handle || mountedHandleViewerKeyRef.current !== sourceKey) {
				mountedHandleViewerKeyRef.current = sourceKey;
				renderedWindowItemIdsRef.current = [];
				visibleHeaderItemIdsRef.current = new Set<string>();
				setCodeViewMountVersion((currentVersion: number): number => currentVersion + 1);
			}
		},
		[sourceKey],
	);
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
			if (currentItem.collapsed === collapsed) {
				setCollapsedItemIds(
					(currentIds: ReadonlySet<string>): ReadonlySet<string> =>
						collapsedItemIdsWithItemState({
							collapsed,
							currentIds,
							itemId,
						}),
				);
				return true;
			}
			if (pendingSmoothSelectionScrollKeyRef.current !== null) {
				settleCodeViewScrollAtCurrentPosition(codeViewHandle);
				pendingPreHydrationSelectionScrollKeyRef.current = null;
				pendingSelectionRevealBehaviorRef.current = null;
				pendingSmoothSelectionScrollKeyRef.current = null;
			}
			const headerAnchor = captureCodeViewHeaderAnchor({
				handle: codeViewHandle,
				itemId,
			});
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
			controller.applyItemUpdate(nextItem);
			if (collapsed) {
				codeViewHandle.getInstance()?.render(true);
			}
			restoreCodeViewHeaderAnchorAcrossLayout({
				anchor: headerAnchor,
				frameBudget: codeViewHeaderAnchorRestoreFrameBudget,
				isCurrent: (): boolean => codeViewHandleRef.current === codeViewHandle,
			});
			setCollapsedItemIds(
				(currentIds: ReadonlySet<string>): ReadonlySet<string> =>
					collapsedItemIdsWithItemState({
						collapsed,
						currentIds,
						itemId,
					}),
			);
			return true;
		},
		[reviewItemsById],
	);
	const scrollToItem = useCallback(
		(itemId: string, options: BridgeCodeViewScrollToItemOptions = {}): boolean => {
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
				controllerEntryRef,
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
				codeViewHandle.getInstance()?.render(true);
				setCollapsedItemIds((currentIds: ReadonlySet<string>): ReadonlySet<string> => {
					const nextIds = new Set(currentIds);
					nextIds.delete(itemId);
					return nextIds;
				});
			}
			const measuredItemTop = codeViewHandle.getInstance()?.getTopForItem(itemId);
			const scrollTopBeforeReveal = codeViewHandle.getInstance()?.getScrollTop();
			controller.scrollToItem(itemId, scrollBehavior);
			if (
				scrollBehavior === 'instant' &&
				measuredItemTop !== undefined &&
				scrollTopBeforeReveal !== undefined
			) {
				requestAnimationFrame((): void => {
					if (codeViewHandleRef.current !== codeViewHandle) {
						return;
					}
					const currentInstance = codeViewHandle.getInstance();
					if (currentInstance === undefined) {
						return;
					}
					if (Math.abs(currentInstance.getScrollTop() - scrollTopBeforeReveal) > 1) {
						return;
					}
					codeViewHandle.scrollTo({
						type: 'position',
						position: measuredItemTop,
						behavior: 'instant',
					});
					currentInstance.render(true);
				});
			}
			const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${itemId}`;
			if (currentBridgeItem?.bridgeMetadata.contentState === 'hydrated') {
				completedSelectionScrollKeyRef.current = selectionScrollKey;
			}
			if (scrollBehavior === 'instant') {
				pendingSmoothSelectionScrollKeyRef.current = null;
				pendingSelectionRevealBehaviorRef.current = null;
				scrollToTopTargetItemIdRef.current = itemId;
				scrollCodeViewHeaderToScrollTopAcrossLayout({
					handle: codeViewHandle,
					itemId,
					isCurrent: (): boolean =>
						codeViewHandleRef.current === codeViewHandle &&
						scrollToTopTargetItemIdRef.current === itemId,
				});
			} else {
				pendingSmoothSelectionScrollKeyRef.current = selectionScrollKey;
				pendingSelectionRevealBehaviorRef.current = scrollBehavior;
				scrollToTopTargetItemIdRef.current = null;
			}
			lastSelectionScrollKeyRef.current = selectionScrollKey;
			return true;
		},
		[codeViewMountVersion, reviewItemsById, sourceKey],
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
		[setItemCollapsed],
	);
	useEffect((): (() => void) | undefined => {
		if (onControlHandleChange === undefined) {
			return undefined;
		}
		const handle: BridgeCodeViewControlHandle = { scrollToItem, setItemCollapsed };
		onControlHandleChange(handle);
		return (): void => {
			onControlHandleChange(null);
		};
	}, [onControlHandleChange, scrollToItem, setItemCollapsed]);
	const headerRenderers = useMemo(
		() =>
			createBridgeCodeViewHeaderRenderers({
				collapsedItemIds,
				onHeaderVisibilityChange: handleHeaderVisibilityChange,
				onToggleItemCollapse: toggleItemCollapse,
				reviewPackage: props.reviewPackage,
			}),
		[collapsedItemIds, handleHeaderVisibilityChange, props.reviewPackage, toggleItemCollapse],
	);
	const materializationResourceEntries = useMemo((): readonly (readonly [
		string,
		BridgeCodeViewContentResources,
	])[] => {
		const resourceEntriesByItemId = new Map<string, BridgeCodeViewContentResources>();
		for (const [itemId, resources] of props.visibleContentResourcesByItemId ?? []) {
			if (
				!shouldApplyBridgeCodeViewMaterialization({
					isScrollActive: isCodeViewScrollActive,
					itemId,
					selectedItemId: props.selectedItemId,
				})
			) {
				continue;
			}
			resourceEntriesByItemId.set(itemId, resources);
		}
		if (
			props.selectedItemId !== null &&
			props.selectedContentResources !== null &&
			props.selectedContentResources !== undefined
		) {
			resourceEntriesByItemId.set(props.selectedItemId, props.selectedContentResources);
		}
		return [...resourceEntriesByItemId.entries()];
	}, [
		isCodeViewScrollActive,
		props.selectedContentResources,
		props.selectedItemId,
		props.visibleContentResourcesByItemId,
	]);
	const materializationResourceEntryItemIds = useMemo(
		(): string => materializationResourceEntries.map(([itemId]): string => itemId).join(','),
		[materializationResourceEntries],
	);
	const loadingMaterializationItemIds = useMemo((): readonly string[] => {
		const loadedItemIds = new Set(materializationResourceEntries.map(([itemId]): string => itemId));
		const loadingItemIds = new Set(props.visibleLoadingItemIds ?? []);
		if (isCodeViewScrollActive) {
			for (const itemId of loadingItemIds) {
				if (
					!shouldApplyBridgeCodeViewMaterialization({
						isScrollActive: isCodeViewScrollActive,
						itemId,
						selectedItemId: props.selectedItemId,
					})
				) {
					loadingItemIds.delete(itemId);
				}
			}
		}
		if (
			props.selectedContentLoadingItemId !== undefined &&
			props.selectedContentLoadingItemId !== null
		) {
			loadingItemIds.add(props.selectedContentLoadingItemId);
		}
		return [...loadingItemIds].filter((itemId: string): boolean => !loadedItemIds.has(itemId));
	}, [
		isCodeViewScrollActive,
		materializationResourceEntries,
		props.selectedContentLoadingItemId,
		props.selectedItemId,
		props.visibleLoadingItemIds,
	]);
	const selectedItemIdForMetadataReconcileRef = useRef(props.selectedItemId);
	selectedItemIdForMetadataReconcileRef.current = props.selectedItemId;
	const initialItems = useMemo(() => {
		const itemPresentationsByItemId =
			props.selectedItemId === null ||
			props.selectedItemPresentation === null ||
			props.selectedItemPresentation === undefined
				? undefined
				: new Map([[props.selectedItemId, props.selectedItemPresentation]]);
		return createBridgeCodeViewInitialItems({
			...(itemPresentationsByItemId === undefined ? {} : { itemPresentationsByItemId }),
			reviewPackage: props.reviewPackage,
			projection: props.projection,
		});
	}, [props.projection, props.reviewPackage, props.selectedItemId, props.selectedItemPresentation]);

	const scheduleCodeViewRecoveryRender = useCallback((): void => {
		if (pendingRecoveryRenderFrameRef.current !== null) {
			cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
		}
		pendingRecoveryRenderFrameRef.current = requestAnimationFrame((): void => {
			pendingRecoveryRenderFrameRef.current = null;
			publishVisibleItemIdsFromCurrentHandle();
		});
	}, [publishVisibleItemIdsFromCurrentHandle]);

	useLayoutEffect((): void => {
		materializationTaskGenerationRef.current += 1;
		controllerEntryRef.current = null;
		completedSelectionScrollKeyRef.current = null;
		lastSelectionScrollKeyRef.current = null;
		pendingPreHydrationSelectionScrollKeyRef.current = null;
		pendingSelectionRevealBehaviorRef.current = null;
		pendingSmoothSelectionScrollKeyRef.current = null;
		setMaterializationDiagnostic(emptyMaterializationDiagnostic());
	}, [sourceKey]);

	useEffect((): void => {
		const codeViewHandle = codeViewHandleRef.current;
		const codeViewInstance = codeViewHandle?.getInstance();
		if (codeViewHandle === null || codeViewInstance === undefined) {
			return;
		}
		codeViewInstance.setItems(
			reconcileBridgeCodeViewMetadataItems({
				getCurrentItem: (itemId: string): CodeViewItem | undefined =>
					codeViewHandle.getItem(itemId),
				metadataItems: initialItems,
				preserveItemIds:
					selectedItemIdForMetadataReconcileRef.current === null
						? []
						: [selectedItemIdForMetadataReconcileRef.current],
			}),
		);
		scheduleCodeViewRecoveryRender();
	}, [codeViewMountVersion, initialItems, scheduleCodeViewRecoveryRender, sourceKey]);

	useEffect(
		(): (() => void) => (): void => {
			materializationTaskGenerationRef.current += 1;
			if (pendingRecoveryRenderFrameRef.current !== null) {
				cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
				pendingRecoveryRenderFrameRef.current = null;
			}
			if (pendingMaterializationFrameRef.current !== null) {
				cancelAnimationFrame(pendingMaterializationFrameRef.current);
				pendingMaterializationFrameRef.current = null;
			}
			if (pendingSelectionScrollFrameRef.current !== null) {
				cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
				pendingSelectionScrollFrameRef.current = null;
			}
			pendingPreHydrationSelectionScrollKeyRef.current = null;
			pendingSelectionRevealBehaviorRef.current = null;
			pendingSmoothSelectionScrollKeyRef.current = null;
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
				setIsCodeViewScrollActive(false);
				onScrollActivityChangeRef.current?.(false);
			}
		},
		[],
	);

	useBridgeCodeViewSelectionScroll({
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
		reviewPackage: props.reviewPackage,
		scrollToItem,
		scrollToTopTargetItemIdRef,
		selectedItemId: props.selectedItemId,
		setSelectionScrollDiagnostic,
		sourceKey,
	});

	useEffect((): (() => void) | undefined => {
		if (props.onVisibleItemIdsChange === undefined) {
			return undefined;
		}
		publishVisibleItemIdsFromCurrentHandle();
		const animationFrameId = requestAnimationFrame((): void => {
			publishVisibleItemIdsFromCurrentHandle();
		});
		return (): void => {
			cancelAnimationFrame(animationFrameId);
		};
	}, [
		codeViewMountVersion,
		props.onVisibleItemIdsChange,
		publishVisibleItemIdsFromCurrentHandle,
		sourceKey,
	]);

	useEffect((): void => {
		if (loadingMaterializationItemIds.length === 0 && materializationResourceEntries.length === 0) {
			return;
		}
		const taskGeneration = materializationTaskGenerationRef.current + 1;
		materializationTaskGenerationRef.current = taskGeneration;
		if (pendingMaterializationFrameRef.current !== null) {
			cancelAnimationFrame(pendingMaterializationFrameRef.current);
			pendingMaterializationFrameRef.current = null;
		}
		const runMaterialization = (remainingFrameBudget: number): void => {
			if (materializationTaskGenerationRef.current !== taskGeneration) {
				return;
			}
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null || !codeViewHandleHasInstance(codeViewHandle)) {
				if (remainingFrameBudget > 0) {
					pendingMaterializationFrameRef.current = requestAnimationFrame((): void => {
						pendingMaterializationFrameRef.current = null;
						runMaterialization(remainingFrameBudget - 1);
					});
				}
				return;
			}
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef,
			});
			let didUpdateRenderedItems = false;
			for (const itemId of loadingMaterializationItemIds) {
				if (
					!shouldApplyBridgeCodeViewMaterialization({
						isScrollActive: scrollActivityActiveRef.current,
						itemId,
						selectedItemId: props.selectedItemId,
					})
				) {
					continue;
				}
				const loadingItemDescriptor = props.reviewPackage.itemsById[itemId];
				if (loadingItemDescriptor === undefined) {
					continue;
				}
				const loadingItem = materializeBridgeCodeViewLoadingItem(
					loadingItemDescriptor,
					itemId === props.selectedItemId ? (props.selectedItemPresentation ?? null) : null,
				);
				const existingItem = codeViewHandle.getItem(itemId);
				if (
					existingItem !== undefined &&
					isBridgeCodeViewItem(existingItem) &&
					existingItem.bridgeMetadata.contentState === 'loading' &&
					existingItem.bridgeMetadata.cacheKey === loadingItem.bridgeMetadata.cacheKey
				) {
					continue;
				}
				controller.applyItemUpdate(loadingItem);
				didUpdateRenderedItems = true;
			}
			for (const [itemId, resources] of materializationResourceEntries) {
				if (
					!shouldApplyBridgeCodeViewMaterialization({
						isScrollActive: scrollActivityActiveRef.current,
						itemId,
						selectedItemId: props.selectedItemId,
					})
				) {
					continue;
				}
				const selectedItem = props.reviewPackage.itemsById[itemId];
				if (selectedItem === undefined) {
					continue;
				}
				const itemMaterializationStartedAt = performance.now();
				const materializedItem = materializeBridgeCodeViewItem({
					item: selectedItem,
					presentation:
						itemId === props.selectedItemId ? (props.selectedItemPresentation ?? null) : null,
					resources,
				});
				if (materializedItem === null) {
					continue;
				}
				const nextMaterializedItem = collapsedItemIds.has(materializedItem.id)
					? ({
							...materializedItem,
							collapsed: true,
							version: (materializedItem.version ?? 0) + 1,
						} satisfies BridgeCodeViewItem)
					: materializedItem;
				const existingItem = codeViewHandle.getItem(itemId);
				if (
					existingItem !== undefined &&
					isBridgeCodeViewItem(existingItem) &&
					isMaterializedBridgeCodeViewContentState(existingItem.bridgeMetadata.contentState) &&
					existingItem.bridgeMetadata.cacheKey === nextMaterializedItem.bridgeMetadata.cacheKey &&
					existingItem.collapsed === nextMaterializedItem.collapsed
				) {
					continue;
				}
				const updateResult = controller.applyItemUpdate(nextMaterializedItem);
				didUpdateRenderedItems = true;
				if (itemId === props.selectedItemId) {
					codeViewHandle.getInstance()?.render(true);
					const currentModelItem = codeViewHandle.getItem(itemId);
					const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${itemId}`;
					const shouldPreserveSmoothReveal =
						pendingPreHydrationSelectionScrollKeyRef.current === selectionScrollKey ||
						pendingSmoothSelectionScrollKeyRef.current === selectionScrollKey;
					if (shouldPreserveSmoothReveal) {
						if (pendingSelectionScrollFrameRef.current !== null) {
							cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
							pendingSelectionScrollFrameRef.current = null;
						}
						// F9 re-targeting reveal: re-issue Pierre's smooth reveal so it re-resolves the
						// target's top per frame as the freshly hydrated content changes heights, keeping
						// Pierre's anchor pinned to the target through the settle window. F4: no competing
						// app-side DOM pin loop here — Pierre's smooth path is the single scroll authority,
						// so above-target growth is absorbed without oscillation.
						scrollToItem(itemId, {
							behavior: pendingSelectionRevealBehaviorRef.current ?? 'smooth-auto',
						});
						pendingPreHydrationSelectionScrollKeyRef.current = null;
						pendingSmoothSelectionScrollKeyRef.current = selectionScrollKey;
					}
					completedSelectionScrollKeyRef.current = selectionScrollKey;
					lastSelectionScrollKeyRef.current = selectionScrollKey;
					setMaterializationDiagnostic(
						materializationDiagnosticForCodeViewItem({
							durationMilliseconds: Math.max(0, performance.now() - itemMaterializationStartedAt),
							item: nextMaterializedItem,
							modelItem: isBridgeCodeViewItem(currentModelItem) ? currentModelItem : null,
							updateResult,
						}),
					);
					if (props.telemetryRecorder !== undefined) {
						recordBridgeCodeViewHydrationTelemetry({
							telemetryRecorder: props.telemetryRecorder,
							parentTraceContext: props.telemetryParentTraceContext ?? null,
							projection: props.projection,
							item: selectedItem,
							resources,
							workerPoolEnabled: props.workerPoolEnabled !== false,
						});
					}
				}
			}
			if (!didUpdateRenderedItems) {
				return;
			}
			scheduleCodeViewRecoveryRender();
		};
		queueMicrotask((): void => {
			runMaterialization(codeViewMaterializationRetryFrameBudget);
		});
	}, [
		collapsedItemIds,
		codeViewMountVersion,
		loadingMaterializationItemIds,
		materializationResourceEntries,
		props.projection,
		props.reviewPackage,
		props.selectedItemId,
		props.selectedItemPresentation,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.workerPoolEnabled,
		scheduleCodeViewRecoveryRender,
		scrollToItem,
		sourceKey,
	]);

	return (
		<BridgeCodeViewPanelFrame
			handleCodeViewScroll={handleCodeViewScroll}
			headerRenderers={headerRenderers}
			initialItems={initialItems}
			materializationDiagnostic={materializationDiagnostic}
			materializationResourceEntryCount={materializationResourceEntries.length}
			materializationResourceEntryItemIds={materializationResourceEntryItemIds}
			selectedChangeKind={selectedReviewItem?.changeKind ?? 'none'}
			selectedContentCacheKeyCount={selectedContentDiagnostics.summary.cacheKeyCount}
			selectedContentCacheKeys={selectedContentDiagnostics.cacheKeys}
			selectedContentCharacterCount={selectedContentDiagnostics.summary.characterCount}
			selectedContentLineCount={selectedContentDiagnostics.summary.lineCount}
			selectedContentRoleCount={selectedContentDiagnostics.roleCount}
			selectedContentRoleNames={selectedContentDiagnostics.roleNames}
			selectedContentState={selectedContentDiagnostics.state}
			selectedDisplayPath={selectedDisplayPath}
			selectedInitialItemIndex={initialItems.findIndex(
				(item): boolean => item.id === props.selectedItemId,
			)}
			selectedInitialItemIsFirst={initialItems[0]?.id === props.selectedItemId}
			selectedItemId={props.selectedItemId}
			selectedPresentationKind={props.selectedItemPresentation?.kind ?? 'none'}
			selectedPresentationVersion={
				props.selectedItemPresentation?.kind === 'file'
					? props.selectedItemPresentation.version
					: 'none'
			}
			selectionScrollDiagnostic={selectionScrollDiagnostic}
			setCodeViewHandle={setCodeViewHandle}
			sourceKey={sourceKey}
			visibleLoadingItemCount={props.visibleLoadingItemCount ?? 0}
			visibleReadyItemCount={props.visibleReadyItemCount ?? 0}
			{...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory })}
			{...(props.workerPoolEnabled === undefined
				? {}
				: { workerPoolEnabled: props.workerPoolEnabled })}
		/>
	);
}
