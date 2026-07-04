import type { CodeViewItem, CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import {
	recordBridgeCodeViewHydrationTelemetry,
	recordBridgeCodeViewItemMaterializeTelemetry,
	recordBridgeSelectedContentPaintedTelemetry,
} from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	bridgeCodeViewApplyResultDidRenderContent,
	type ApplyBridgeCodeViewItemUpdateResult,
} from './bridge-code-view-controller.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import { BridgeCodeViewPanelFrame } from './bridge-code-view-panel-frame.js';
import {
	bridgeCodeViewRenderedHeaderCorrectionTargetPosition,
	codeViewHandleHasInstance,
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
	renderedBridgeCodeViewHeaderOffsetFromScrollOwner,
	selectedContentDiagnosticsForPanel,
	shouldApplyBridgeCodeViewMaterialization,
	shouldApplyBridgeCodeViewRenderedHeaderCorrection,
	shouldRearmCodeViewInstantRevealForMaterialization,
	uniqueItemIds,
	uniqueRenderedItemIds,
	type BridgeCodeViewInstantRevealRearmCandidate,
	type BridgeCodeViewControllerEntry,
	type BridgeCodeViewMaterializationDiagnostic,
	type BridgeCodeViewRenderedItemsSource,
} from './bridge-code-view-panel-support.js';
import {
	codeViewMaterializationRetryFrameBudget,
	codeViewSelectionScrollRetryFrameBudget,
	codeViewVisibleHydrationScrollIdleMilliseconds,
	codeViewVisibleMetadataScrollThrottleMilliseconds,
	initialSelectionScrollDiagnostic,
	type BridgeCodeViewControlHandle,
	type BridgeCodeViewPanelProps,
	type BridgeCodeViewScrollToItemOptions,
	type BridgeCodeViewSelectionScrollDiagnostic,
} from './bridge-code-view-panel-types.js';
import { createBridgeCodeViewVisibleInterestPublisher } from './bridge-code-view-visible-interest-publisher.js';
import { useBridgeCodeViewCollapseController } from './use-bridge-code-view-collapse-controller.js';
import { useBridgeCodeViewSelectionScroll } from './use-bridge-code-view-selection-scroll.js';

export { bridgeCodeViewOptions } from './bridge-code-view-options.js';
export {
	makeBridgeCodeViewSourceKey,
	reconcileBridgeCodeViewMetadataItems,
	selectedContentSummaryForPanel,
	shouldApplyBridgeCodeViewMaterialization,
} from './bridge-code-view-panel-support.js';
export type {
	BridgeCodeViewControlHandle,
	BridgeCodeViewPanelProps,
} from './bridge-code-view-panel-types.js';
export type { BridgeCodeViewScrollToItemOptions } from './bridge-code-view-panel-types.js';

const codeViewInstantRevealRetargetEpsilonPixels = 1;
const codeViewInstantRevealViewportOffsetTolerancePixels = 0;
const codeViewInstantRevealRenderedHeaderOffsetTolerancePixels = 1;
const codeViewInstantRevealHydrationRearmViewportOffsetTolerancePixels = 4;
const codeViewInstantRevealExternalScrollAbortThresholdPixels = 240;
const codeViewInstantRevealStableFrameCount = 2;
const codeViewInstantRevealHydrationRearmWindowMilliseconds = 2_000;
const selectedContentPaintedGenerationByRecorder = new WeakMap<BridgeTelemetryRecorder, number>();
const selectedContentPaintedDemandByRecorder = new WeakMap<BridgeTelemetryRecorder, number>();

interface BridgeCodeViewMaterializationResourceEntry {
	readonly itemId: string;
	readonly resources: BridgeCodeViewContentResources;
	readonly selectionDemandStartedAtMilliseconds: number | null;
}

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
	const recentInstantSelectionRevealRef = useRef<BridgeCodeViewInstantRevealRearmCandidate | null>(
		null,
	);
	const settledInstantSelectionRevealKeyRef = useRef<string | null>(null);
	const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const scrollActivityActiveRef = useRef(false);
	const renderedWindowItemIdsRef = useRef<readonly string[]>([]);
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
			if (pendingSelectionScrollFrameRef.current !== null) {
				cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
				pendingSelectionScrollFrameRef.current = null;
			}
			let didApplyRenderedHeaderCorrection = false;
			let lastRetargetedItemTop: number | null = null;
			let stableResolvedTopFrameCount = 0;
			let committedRevealScrollTop: number | null = null;
			const scheduleRetargetFrame = (remainingFrameBudget: number): void => {
				pendingSelectionScrollFrameRef.current = requestAnimationFrame((): void => {
					pendingSelectionScrollFrameRef.current = null;
					if (
						codeViewHandleRef.current !== params.codeViewHandle ||
						lastSelectionScrollKeyRef.current !== params.selectionScrollKey ||
						params.codeViewHandle.getItem(params.itemId) === undefined
					) {
						return;
					}
					const codeViewInstance = params.codeViewHandle.getInstance();
					if (codeViewInstance === undefined) {
						return;
					}
					// I2/I4: the reveal owns the viewport only until the user takes over. A user
					// scroll moves the viewport far from where the reveal last committed it; when
					// that happens we yield ownership (mark settled/terminal) instead of snapping
					// the selected item back and fighting the user's scroll.
					const externalScrollThresholdPixels = Math.max(
						codeViewInstantRevealExternalScrollAbortThresholdPixels,
						codeViewInstance.getContainerElement()?.clientHeight ?? 0,
					);
					if (
						committedRevealScrollTop !== null &&
						Math.abs(codeViewInstance.getScrollTop() - committedRevealScrollTop) >
							externalScrollThresholdPixels
					) {
						recentInstantSelectionRevealRef.current = null;
						settledInstantSelectionRevealKeyRef.current = params.selectionScrollKey;
						return;
					}
					const resolvedItemTop = codeViewInstance.getTopForItem(params.itemId);
					const targetViewportOffset =
						resolvedItemTop === undefined
							? null
							: resolvedItemTop - codeViewInstance.getScrollTop();
					const shouldRetarget =
						resolvedItemTop === undefined ||
						lastRetargetedItemTop === null ||
						Math.abs(resolvedItemTop - lastRetargetedItemTop) >
							codeViewInstantRevealRetargetEpsilonPixels ||
						targetViewportOffset === null ||
						Math.abs(targetViewportOffset) > params.viewportOffsetTolerancePixels;
					if (shouldRetarget) {
						stableResolvedTopFrameCount = 0;
						lastRetargetedItemTop = resolvedItemTop ?? null;
						params.codeViewHandle.scrollTo({
							type: 'item',
							id: params.itemId,
							align: 'start',
							behavior: 'instant',
						});
						codeViewInstance.render(true);
					} else {
						stableResolvedTopFrameCount += 1;
						if (stableResolvedTopFrameCount >= codeViewInstantRevealStableFrameCount) {
							const settledItem = params.codeViewHandle.getItem(params.itemId);
							const isSettledMaterialized =
								isBridgeCodeViewItem(settledItem) &&
								isMaterializedBridgeCodeViewContentState(settledItem.bridgeMetadata.contentState);
							if (
								recentInstantSelectionRevealRef.current?.selectionScrollKey !==
								params.selectionScrollKey
							) {
								return;
							}
							const renderedHeaderOffset = renderedBridgeCodeViewHeaderOffsetFromScrollOwner({
								itemId: params.itemId,
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
									tolerancePixels: codeViewInstantRevealRenderedHeaderOffsetTolerancePixels,
								})
							) {
								didApplyRenderedHeaderCorrection = true;
								params.codeViewHandle.scrollTo({
									type: 'position',
									position: bridgeCodeViewRenderedHeaderCorrectionTargetPosition({
										currentScrollTop: codeViewInstance.getScrollTop(),
										renderedHeaderOffset,
									}),
									behavior: 'instant',
								});
							}
							recentInstantSelectionRevealRef.current = null;
							settledInstantSelectionRevealKeyRef.current = params.selectionScrollKey;
						}
					}
					committedRevealScrollTop = codeViewInstance.getScrollTop();
					if (
						remainingFrameBudget > 0 &&
						stableResolvedTopFrameCount < codeViewInstantRevealStableFrameCount
					) {
						scheduleRetargetFrame(remainingFrameBudget - 1);
					}
				});
			};
			scheduleRetargetFrame(codeViewSelectionScrollRetryFrameBudget);
		},
		[],
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
			controller.scrollToItem(itemId, scrollBehavior);
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
					viewportOffsetTolerancePixels: codeViewInstantRevealViewportOffsetTolerancePixels,
				});
			} else {
				pendingSmoothSelectionScrollKeyRef.current = selectionScrollKey;
				pendingSelectionRevealBehaviorRef.current = scrollBehavior;
				recentInstantSelectionRevealRef.current = null;
				settledInstantSelectionRevealKeyRef.current = null;
			}
			return true;
		},
		[codeViewMountVersion, reviewItemsById, scheduleInstantSelectionRevealRetarget, sourceKey],
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
	const materializationResourceEntries =
		useMemo((): readonly BridgeCodeViewMaterializationResourceEntry[] => {
			const resourceEntriesByItemId = new Map<string, BridgeCodeViewMaterializationResourceEntry>();
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
				resourceEntriesByItemId.set(itemId, {
					itemId,
					resources,
					selectionDemandStartedAtMilliseconds: null,
				});
			}
			if (
				props.selectedItemId !== null &&
				props.selectedContentResources !== null &&
				props.selectedContentResources !== undefined
			) {
				resourceEntriesByItemId.set(props.selectedItemId, {
					itemId: props.selectedItemId,
					resources: props.selectedContentResources,
					selectionDemandStartedAtMilliseconds:
						props.selectedContentDemandStartedAtMilliseconds ?? null,
				});
			}
			return [...resourceEntriesByItemId.values()];
		}, [
			isCodeViewScrollActive,
			props.selectedContentDemandStartedAtMilliseconds,
			props.selectedContentResources,
			props.selectedItemId,
			props.visibleContentResourcesByItemId,
		]);
	const materializationResourceEntryItemIds = useMemo(
		(): string => materializationResourceEntries.map((entry): string => entry.itemId).join(','),
		[materializationResourceEntries],
	);
	const loadingMaterializationItemIds = useMemo((): readonly string[] => {
		const loadedItemIds = new Set(
			materializationResourceEntries.map((entry): string => entry.itemId),
		);
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
			const materializedItemIds: string[] = [];
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
				materializedItemIds.push(itemId);
			}
			for (const entry of materializationResourceEntries) {
				const { itemId, resources } = entry;
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
					if (itemId === props.selectedItemId && props.telemetryRecorder !== undefined) {
						const materializationCompletedAtMilliseconds = performance.now();
						if (
							shouldScheduleSelectedContentPaintedTelemetry({
								didFindMatchingPaintedContent: true,
								selectionDemandStartedAtMilliseconds: entry.selectionDemandStartedAtMilliseconds,
								updateResult: 'unchanged',
							})
						) {
							scheduleSelectedContentPaintedTelemetry({
								telemetryRecorder: props.telemetryRecorder,
								traceContext: props.telemetryParentTraceContext ?? null,
								selectionDemandStartedAtMilliseconds: entry.selectionDemandStartedAtMilliseconds,
								materializationStartedAtMilliseconds: itemMaterializationStartedAt,
								materializationCompletedAtMilliseconds,
							});
						}
					}
					continue;
				}
				const updateResult = controller.applyItemUpdate(nextMaterializedItem);
				const materializationCompletedAtMilliseconds = performance.now();
				const materializeMilliseconds = Math.max(
					0,
					materializationCompletedAtMilliseconds - itemMaterializationStartedAt,
				);
				didUpdateRenderedItems = true;
				materializedItemIds.push(itemId);
				if (itemId === props.selectedItemId) {
					// F7: no mid-loop render(true) — applyItemUpdate's updateItem queues a render
					// that coalesces the whole hydration batch into one layout pass, and the instant
					// reveal re-issue below restarts the bounded F9 re-target loop.
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
						// F9 re-targeting reveal: re-issue Pierre's instant item reveal so
						// scrollToItem restarts the bounded per-frame target re-resolution loop as
						// freshly hydrated content changes heights.
						scrollToItem(itemId, {
							behavior: pendingSelectionRevealBehaviorRef.current ?? 'instant',
						});
						pendingPreHydrationSelectionScrollKeyRef.current = null;
						pendingSmoothSelectionScrollKeyRef.current = selectionScrollKey;
					}
					completedSelectionScrollKeyRef.current = selectionScrollKey;
					lastSelectionScrollKeyRef.current = selectionScrollKey;
					setMaterializationDiagnostic(
						materializationDiagnosticForCodeViewItem({
							durationMilliseconds: materializeMilliseconds,
							item: nextMaterializedItem,
							modelItem: isBridgeCodeViewItem(currentModelItem) ? currentModelItem : null,
							updateResult,
						}),
					);
					if (props.telemetryRecorder !== undefined) {
						recordBridgeCodeViewItemMaterializeTelemetry({
							telemetryRecorder: props.telemetryRecorder,
							parentTraceContext: props.telemetryParentTraceContext ?? null,
							projection: props.projection,
							item: selectedItem,
							resources,
							durationMilliseconds: materializeMilliseconds,
							result: updateResult,
							selected: true,
						});
						if (
							shouldScheduleSelectedContentPaintedTelemetry({
								didFindMatchingPaintedContent: false,
								selectionDemandStartedAtMilliseconds: entry.selectionDemandStartedAtMilliseconds,
								updateResult,
							})
						) {
							scheduleSelectedContentPaintedTelemetry({
								telemetryRecorder: props.telemetryRecorder,
								traceContext: props.telemetryParentTraceContext ?? null,
								selectionDemandStartedAtMilliseconds: entry.selectionDemandStartedAtMilliseconds,
								materializationStartedAtMilliseconds: itemMaterializationStartedAt,
								materializationCompletedAtMilliseconds,
							});
						}
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
			if (props.selectedItemId !== null) {
				const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${props.selectedItemId}`;
				if (
					shouldRearmCodeViewInstantRevealForMaterialization({
						isSelectedRevealSettled:
							settledInstantSelectionRevealKeyRef.current === selectionScrollKey,
						materializedItemIds,
						nowMilliseconds: performance.now(),
						orderedItemIds: props.reviewPackage.orderedItemIds,
						rearmWindowMilliseconds: codeViewInstantRevealHydrationRearmWindowMilliseconds,
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
							codeViewInstantRevealHydrationRearmViewportOffsetTolerancePixels,
					});
				}
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
		props.selectedContentDemandStartedAtMilliseconds,
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

export function shouldScheduleSelectedContentPaintedTelemetry(props: {
	readonly didFindMatchingPaintedContent: boolean;
	readonly selectionDemandStartedAtMilliseconds: number | null;
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult;
}): boolean {
	if (props.selectionDemandStartedAtMilliseconds === null) {
		return false;
	}
	return (
		bridgeCodeViewApplyResultDidRenderContent(props.updateResult) ||
		props.didFindMatchingPaintedContent
	);
}

export function scheduleSelectedContentPaintedTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly selectionDemandStartedAtMilliseconds: number | null;
	readonly materializationStartedAtMilliseconds: number;
	readonly materializationCompletedAtMilliseconds: number;
	readonly now?: () => number;
	readonly requestAnimationFrame?: (callback: FrameRequestCallback) => number;
}): void {
	if (props.selectionDemandStartedAtMilliseconds === null) {
		return;
	}
	const selectionDemandStartedAtMilliseconds = props.selectionDemandStartedAtMilliseconds;
	if (
		selectedContentPaintedDemandByRecorder.get(props.telemetryRecorder) ===
		selectionDemandStartedAtMilliseconds
	) {
		return;
	}
	selectedContentPaintedDemandByRecorder.set(
		props.telemetryRecorder,
		selectionDemandStartedAtMilliseconds,
	);
	const now = props.now ?? performance.now.bind(performance);
	const requestFrame = props.requestAnimationFrame ?? requestAnimationFrame;
	const paintedGeneration =
		(selectedContentPaintedGenerationByRecorder.get(props.telemetryRecorder) ?? 0) + 1;
	selectedContentPaintedGenerationByRecorder.set(props.telemetryRecorder, paintedGeneration);
	requestFrame((): void => {
		if (
			selectedContentPaintedGenerationByRecorder.get(props.telemetryRecorder) !== paintedGeneration
		) {
			return;
		}
		selectedContentPaintedGenerationByRecorder.delete(props.telemetryRecorder);
		const paintedAtMilliseconds = now();
		recordBridgeSelectedContentPaintedTelemetry({
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.traceContext,
			clickToPaintMilliseconds: paintedAtMilliseconds - selectionDemandStartedAtMilliseconds,
			frameWaitMilliseconds: paintedAtMilliseconds - props.materializationCompletedAtMilliseconds,
			materializeMilliseconds: paintedAtMilliseconds - props.materializationStartedAtMilliseconds,
		});
	});
}
