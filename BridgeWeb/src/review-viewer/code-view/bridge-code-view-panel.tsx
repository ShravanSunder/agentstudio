import type { CodeViewItem, CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { scheduleBridgeCodeViewInstantRevealRetargetForPanel } from './bridge-code-view-instant-reveal-retarget.js';
import {
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import { applyBridgeCodeViewMetadataItems } from './bridge-code-view-metadata-apply.js';
import { BridgeCodeViewPanelFrame } from './bridge-code-view-panel-frame.js';
import {
	bridgeCodeViewLoadingMaterializationItemIdsForPanel,
	codeViewHandleHasInstance,
	controllerForHandle,
	createBridgeCodeViewInitialItemsForPanel,
	createBridgeCodeViewHeaderRenderers,
	emptyMaterializationDiagnostic,
	hasRenderedItemsSource,
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	makeBridgeCodeViewSourceKey,
	nextCodeViewItemForCollapse,
	reconcileBridgeCodeViewMetadataItems,
	shouldRearmCodeViewInstantRevealForMaterialization,
	uniqueItemIds,
	uniqueRenderedItemIds,
	type BridgeCodeViewInstantRevealRearmCandidate,
	type BridgeCodeViewControllerEntry,
	type BridgeCodeViewMaterializationDiagnostic,
	type BridgeCodeViewRenderedItemsSource,
} from './bridge-code-view-panel-support.js';
import {
	bridgeCodeViewInstantRevealPolicy,
	codeViewMaterializationRetryFrameBudget,
	codeViewVisibleHydrationScrollIdleMilliseconds,
	codeViewVisibleMetadataScrollThrottleMilliseconds,
	initialSelectionScrollDiagnostic,
	type BridgeCodeViewControlHandle,
	type BridgeCodeViewPanelProps,
	type BridgeCodeViewScrollToItemOptions,
	type BridgeCodeViewSelectionScrollDiagnostic,
} from './bridge-code-view-panel-types.js';
import {
	cancelBridgeCodeViewPendingProgrammaticReveal,
	createBridgeCodeViewProgrammaticRevealGate,
} from './bridge-code-view-programmatic-reveal-gate.js';
import {
	selectedContentDiagnosticsForPanel,
	selectedMaterializationDiagnosticForPanel,
} from './bridge-code-view-selected-diagnostics.js';
import { createBridgeCodeViewVisibleInterestPublisher } from './bridge-code-view-visible-interest-publisher.js';
import { useBridgeCodeViewCollapseController } from './use-bridge-code-view-collapse-controller.js';
import { useBridgeCodeViewSelectionScroll } from './use-bridge-code-view-selection-scroll.js';

export { bridgeCodeViewOptions } from './bridge-code-view-options.js';
export {
	makeBridgeCodeViewSourceKey,
	reconcileBridgeCodeViewMetadataItems,
} from './bridge-code-view-panel-support.js';
export { selectedContentSummaryForPanel } from './bridge-code-view-selected-diagnostics.js';
export {
	recordBridgeSelectedContentPaintedProbeAnchoredDelivery,
	scheduleSelectedContentPaintedTelemetry,
	shouldScheduleSelectedContentPaintedTelemetry,
	type BridgeSelectedContentPaintedProbe,
} from './bridge-code-view-painted-telemetry.js';
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
		selectedCodeViewItem: props.selectedCodeViewItem,
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
	const lastMetadataApplySourceKeyRef = useRef<string | null>(null);
	const lastMetadataApplyMountVersionRef = useRef<number | null>(null);
	const recentInstantSelectionRevealRef = useRef<BridgeCodeViewInstantRevealRearmCandidate | null>(
		null,
	);
	const settledInstantSelectionRevealKeyRef = useRef<string | null>(null);
	const lastProgrammaticRevealItemIdRef = useRef<string | null>(null);
	const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const scrollActivityActiveRef = useRef(false);
	const renderedWindowItemIdsRef = useRef<readonly string[]>([]);
	const pendingRenderedItemsSourceRef = useRef<BridgeCodeViewRenderedItemsSource | null>(null);
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
	const selectedMaterializationDiagnostic = selectedMaterializationDiagnosticForPanel({
		materializationDiagnostic,
		selectedCodeViewItem: props.selectedCodeViewItem,
	});
	const cancelPendingProgrammaticReveal = useCallback((): void => {
		cancelBridgeCodeViewPendingProgrammaticReveal({
			pendingPreHydrationSelectionScrollKeyRef,
			pendingSelectionRevealBehaviorRef,
			pendingSelectionScrollFrameRef,
			pendingSmoothSelectionScrollKeyRef,
			recentInstantSelectionRevealRef,
		});
	}, []);
	const programmaticRevealGate = useMemo(
		() =>
			createBridgeCodeViewProgrammaticRevealGate({
				isScrollActive: (): boolean => scrollActivityActiveRef.current,
				lastRevealedItemId: (): string | null => lastProgrammaticRevealItemIdRef.current,
				onProgrammaticRevealSkipped: (): void => {
					cancelPendingProgrammaticReveal();
				},
			}),
		[cancelPendingProgrammaticReveal],
	);
	const publishVisibleHydrationItemIds = useCallback((): void => {
		const pendingRenderedItemsSource = pendingRenderedItemsSourceRef.current;
		if (pendingRenderedItemsSource !== null) {
			pendingRenderedItemsSourceRef.current = null;
			renderedWindowItemIdsRef.current = uniqueRenderedItemIds(
				pendingRenderedItemsSource.getRenderedItems(),
			);
		}
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
			pendingRenderedItemsSourceRef.current = viewer;
			visibleInterestPublisher.publishDuringScroll();
			if (!scrollActivityActiveRef.current) {
				scrollActivityActiveRef.current = true;
				cancelPendingProgrammaticReveal();
				onScrollActivityChangeRef.current?.(true);
			}
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
			}
			scrollIdleTimeoutRef.current = setTimeout((): void => {
				scrollIdleTimeoutRef.current = null;
				const codeViewInstance = codeViewHandleRef.current?.getInstance();
				if (codeViewInstance !== undefined && hasRenderedItemsSource(codeViewInstance)) {
					codeViewInstance.render(true);
					pendingRenderedItemsSourceRef.current = codeViewInstance;
				} else {
					pendingRenderedItemsSourceRef.current = viewer;
				}
				scrollActivityActiveRef.current = false;
				onScrollActivityChangeRef.current?.(false);
				visibleInterestPublisher.publishAtScrollIdle();
			}, codeViewVisibleHydrationScrollIdleMilliseconds);
		},
		[cancelPendingProgrammaticReveal, visibleInterestPublisher],
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
	const { setItemCollapsed, toggleItemCollapse } = useBridgeCodeViewCollapseController({
		codeViewHandleRef,
		collapsedItemIdsRef,
		controllerEntryRef,
		pendingPreHydrationSelectionScrollKeyRef,
		pendingSelectionRevealBehaviorRef,
		pendingSmoothSelectionScrollKeyRef,
		recentInstantSelectionRevealRef,
		reviewItemsById,
		setCollapsedItemIds,
		settledInstantSelectionRevealKeyRef,
	});
	const scheduleInstantSelectionRevealRetarget = useCallback(
		(params: {
			readonly codeViewHandle: CodeViewHandle<undefined>;
			readonly itemId: string;
			readonly selectionScrollKey: string;
			readonly viewportOffsetTolerancePixels: number;
		}): void => {
			scheduleBridgeCodeViewInstantRevealRetargetForPanel({
				codeViewHandle: params.codeViewHandle,
				codeViewHandleRef,
				itemId: params.itemId,
				lastSelectionScrollKeyRef,
				pendingSelectionScrollFrameRef,
				programmaticRevealGate,
				recentInstantSelectionRevealRef,
				selectionScrollKey: params.selectionScrollKey,
				settledInstantSelectionRevealKeyRef,
				viewportOffsetTolerancePixels: params.viewportOffsetTolerancePixels,
			});
		},
		[programmaticRevealGate],
	);
	const scrollToItem = useCallback(
		(itemId: string, options: BridgeCodeViewScrollToItemOptions = {}): boolean => {
			const revealRequest = {
				revealIntent: options.revealIntent ?? 'hydration-reissue',
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
			controller.scrollToItem(itemId, scrollBehavior);
			lastProgrammaticRevealItemIdRef.current = itemId;
			const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${itemId}`;
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
			codeViewMountVersion,
			programmaticRevealGate,
			reviewItemsById,
			scheduleInstantSelectionRevealRetarget,
			sourceKey,
		],
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
	const loadingMaterializationItemIds = useMemo((): readonly string[] => {
		return bridgeCodeViewLoadingMaterializationItemIdsForPanel({
			selectedContentLoadingItemId: props.selectedContentLoadingItemId,
		});
	}, [props.selectedContentLoadingItemId]);
	const selectedItemIdForMetadataReconcileRef = useRef(props.selectedItemId);
	selectedItemIdForMetadataReconcileRef.current = props.selectedItemId;
	const initialItems = useMemo(() => {
		return createBridgeCodeViewInitialItemsForPanel({
			projection: props.projection,
			reviewPackage: props.reviewPackage,
			selectedCodeViewItem: props.selectedCodeViewItem,
			selectedItemId: props.selectedItemId,
			selectedItemPresentation: props.selectedItemPresentation,
			visibleCodeViewItems: props.visibleCodeViewItems,
		});
	}, [
		props.projection,
		props.reviewPackage,
		props.selectedCodeViewItem,
		props.selectedItemId,
		props.selectedItemPresentation,
		props.visibleCodeViewItems,
	]);

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
		lastMetadataApplySourceKeyRef.current = null;
		lastMetadataApplyMountVersionRef.current = null;
		pendingPreHydrationSelectionScrollKeyRef.current = null;
		pendingSelectionRevealBehaviorRef.current = null;
		pendingSmoothSelectionScrollKeyRef.current = null;
		recentInstantSelectionRevealRef.current = null;
		settledInstantSelectionRevealKeyRef.current = null;
		setMaterializationDiagnostic(emptyMaterializationDiagnostic());
	}, [sourceKey]);

	useEffect((): void => {
		const codeViewHandle = codeViewHandleRef.current;
		const codeViewInstance = codeViewHandle?.getInstance();
		if (codeViewHandle === null || codeViewInstance === undefined) {
			return;
		}
		const sourceReset =
			lastMetadataApplySourceKeyRef.current !== sourceKey ||
			lastMetadataApplyMountVersionRef.current !== codeViewMountVersion;
		const metadataItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string): CodeViewItem | undefined => codeViewHandle.getItem(itemId),
			metadataItems: initialItems,
			preserveItemIds:
				selectedItemIdForMetadataReconcileRef.current === null
					? []
					: [selectedItemIdForMetadataReconcileRef.current],
		});
		const controller = controllerForHandle({
			handle: codeViewHandle,
			controllerEntryRef,
		});
		applyBridgeCodeViewMetadataItems({
			applyItemUpdate: (item): void => {
				controller.applyItemUpdate(item);
			},
			getCurrentItem: (itemId: string): CodeViewItem | undefined => codeViewHandle.getItem(itemId),
			items: metadataItems,
			setItems: (items): void => {
				codeViewInstance.setItems(items);
			},
			sourceReset,
		});
		lastMetadataApplySourceKeyRef.current = sourceKey;
		lastMetadataApplyMountVersionRef.current = codeViewMountVersion;
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
		programmaticRevealGate,
		reviewPackage: props.reviewPackage,
		scrollToItem,
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
		if (loadingMaterializationItemIds.length === 0) {
			return;
		}
		const taskGeneration = materializationTaskGenerationRef.current + 1;
		materializationTaskGenerationRef.current = taskGeneration;
		if (pendingMaterializationFrameRef.current !== null) {
			clearTimeout(pendingMaterializationFrameRef.current);
			pendingMaterializationFrameRef.current = null;
		}
		const scheduleMaterializationTurn = (callback: () => void): void => {
			pendingMaterializationFrameRef.current = window.setTimeout((): void => {
				pendingMaterializationFrameRef.current = null;
				callback();
			}, 0);
		};
		const runMaterialization = (remainingFrameBudget: number): void => {
			if (materializationTaskGenerationRef.current !== taskGeneration) {
				return;
			}
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null || !codeViewHandleHasInstance(codeViewHandle)) {
				if (remainingFrameBudget > 0) {
					scheduleMaterializationTurn((): void => {
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
			const materializedItemIds: string[] = [];
			for (const itemId of loadingMaterializationItemIds) {
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
				materializedItemIds.push(itemId);
			}
			const finishMaterialization = (): void => {
				if (!didUpdateRenderedItems) {
					return;
				}
				if (props.selectedItemId !== null) {
					const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${props.selectedItemId}`;
					if (
						shouldRearmCodeViewInstantRevealForMaterialization({
							isSelectedRevealSettled:
								settledInstantSelectionRevealKeyRef.current === selectionScrollKey,
							materializedItemIds,
							nowMilliseconds: performance.now(),
							orderedItemIds: props.reviewPackage.orderedItemIds,
							rearmWindowMilliseconds:
								bridgeCodeViewInstantRevealPolicy.hydrationRearmWindowMilliseconds,
							recentReveal: recentInstantSelectionRevealRef.current,
							selectedItemId: props.selectedItemId,
							selectionScrollKey,
						})
					) {
						scheduleInstantSelectionRevealRetarget({
							codeViewHandle,
							itemId: props.selectedItemId,
							selectionScrollKey,
							viewportOffsetTolerancePixels:
								bridgeCodeViewInstantRevealPolicy.hydrationRearmViewportOffsetTolerancePixels,
						});
					}
				}
				scheduleCodeViewRecoveryRender();
			};
			finishMaterialization();
		};
		scheduleMaterializationTurn((): void => {
			runMaterialization(codeViewMaterializationRetryFrameBudget);
		});
	}, [
		collapsedItemIds,
		codeViewMountVersion,
		loadingMaterializationItemIds,
		props.projection,
		props.reviewPackage,
		props.selectedItemId,
		props.selectedItemPresentation,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.workerPoolEnabled,
		scheduleCodeViewRecoveryRender,
		scheduleInstantSelectionRevealRetarget,
		scrollToItem,
		sourceKey,
	]);

	return (
		<BridgeCodeViewPanelFrame
			handleCodeViewScroll={handleCodeViewScroll}
			headerRenderers={headerRenderers}
			initialItems={initialItems}
			materializationDiagnostic={selectedMaterializationDiagnostic}
			materializationResourceEntryCount={0}
			materializationResourceEntryItemIds=""
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
			{...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory })}
			{...(props.workerPoolEnabled === undefined
				? {}
				: { workerPoolEnabled: props.workerPoolEnabled })}
		/>
	);
}
