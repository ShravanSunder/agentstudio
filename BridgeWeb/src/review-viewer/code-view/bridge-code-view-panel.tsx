import type { CodeViewItem, CodeViewOptions, CodeViewScrollBehavior } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import { consumeBridgeCodeViewPendingHydrationAnchor } from './bridge-code-view-hydration-anchor.js';
import { createBridgeCodeViewInitialItemsForPanelSelector } from './bridge-code-view-initial-items-selector.js';
import {
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import {
	bridgeCodeViewMetadataRequiresManifestReconciliation,
	runBridgeCodeViewMetadataApplyInChunks,
	runBridgeCodeViewMetadataReconciliationInChunks,
	type RunBridgeCodeViewMetadataApplyInChunksProps,
} from './bridge-code-view-metadata-apply.js';
import { BridgeCodeViewPanelFrame } from './bridge-code-view-panel-frame.js';
import {
	bridgeCodeViewInitialItemsWithMetadataDeltaItems,
	bridgeCodeViewItemsWithMetadataItem,
	bridgeCodeViewLoadingMaterializationItemIdsForPanel,
	bridgeCodeViewLoadingPlaceholderMatchesDescriptor,
	codeViewHandleHasInstance,
	controllerForHandle,
	createBridgeCodeViewHeaderRenderers,
	emptyMaterializationDiagnostic,
	hasRenderedItemsSource,
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	makeBridgeCodeViewSourceKey,
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
	codeViewSelectionScrollRetryFrameBudget,
	codeViewVisibleHydrationScrollIdleMilliseconds,
	initialSelectionScrollDiagnostic,
	type BridgeCodeViewControlHandle,
	type BridgeCodeViewPanelProps,
	type BridgeCodeViewSelectionScrollDiagnostic,
} from './bridge-code-view-panel-types.js';
import { createBridgeCodeViewPostRenderVisibleInterestPublisher } from './bridge-code-view-post-render-visible-interest.js';
import {
	cancelBridgeCodeViewPendingProgrammaticReveal,
	createBridgeCodeViewProgrammaticRevealGate,
} from './bridge-code-view-programmatic-reveal-gate.js';
import { prepareBridgeCodeViewPublicationPresentationItem } from './bridge-code-view-publication-presentation.js';
import {
	observeBridgeCodeViewRenderFulfillment,
	reconcileBridgeCodeViewRenderFulfillment,
} from './bridge-code-view-render-fulfillment.js';
import {
	selectedContentDiagnosticsForPanel,
	selectedMaterializationDiagnosticForPanel,
} from './bridge-code-view-selected-diagnostics.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanelSelector } from './bridge-code-view-worker-prepared-items.js';
import {
	applyResultForSetItemsItem,
	recordBridgeCodeViewWorkerPreparedApplyTelemetry,
	type BridgeCodeViewWorkerPreparedTelemetryContext,
} from './bridge-code-view-worker-prepared-telemetry.js';
import { useBridgeCodeViewCollapseController } from './use-bridge-code-view-collapse-controller.js';
import { useBridgeCodeViewProgrammaticScroll } from './use-bridge-code-view-programmatic-scroll.js';
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

const bridgeCodeViewExactManifestPolicyVersion = 'complete-authoritative-manifest-v1';

interface BridgeCodeViewExactManifestPolicyReceipt {
	readonly initialItems: readonly BridgeCodeViewItem[];
	readonly mountVersion: number;
	readonly policyVersion: string;
	readonly sourceKey: string;
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
		selectedCodeViewItem: props.selectedCodeViewItem,
		selectedItemId: props.selectedItemId,
	});
	const reviewItemsById = props.reviewPackage.itemsById;
	const reviewPackageRef = useRef(props.reviewPackage);
	const projectionRef = useRef(props.projection);
	useLayoutEffect((): void => {
		reviewPackageRef.current = props.reviewPackage;
		projectionRef.current = props.projection;
	}, [props.projection, props.reviewPackage]);
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const controllerEntryRef = useRef<BridgeCodeViewControllerEntry | null>(null);
	const completedSelectionScrollKeyRef = useRef<string | null>(null);
	const lastSelectionScrollKeyRef = useRef<string | null>(null);
	const mountedHandleViewerKeyRef = useRef<string | null>(null);
	const materializationTaskGenerationRef = useRef(0);
	const metadataApplyTaskGenerationRef = useRef(0);
	const currentCodeViewItemsRef = useRef<readonly BridgeCodeViewItem[]>([]);
	const currentCodeViewManifestMountKeyRef = useRef<string | null>(null);
	const pendingMetadataApplyFrameRef = useRef<number | null>(null);
	const pendingMaterializationFrameRef = useRef<number | null>(null);
	const pendingRecoveryRenderFrameRef = useRef<number | null>(null);
	const pendingPreHydrationSelectionScrollKeyRef = useRef<string | null>(null);
	const pendingSelectionScrollFrameRef = useRef<number | null>(null);
	const pendingSelectionRevealBehaviorRef = useRef<CodeViewScrollBehavior | null>(null);
	const pendingSmoothSelectionScrollKeyRef = useRef<string | null>(null);
	const pendingVisibleHeaderPublishFrameRef = useRef<number | null>(null);
	const scrollActivityActiveRef = useRef(false);
	const lastMetadataApplySourceKeyRef = useRef<string | null>(null);
	const lastMetadataApplyMountVersionRef = useRef<number | null>(null);
	const lastMetadataManifestItemsRef = useRef<readonly BridgeCodeViewItem[] | null>(null);
	const exactManifestPolicyReceiptRef = useRef<BridgeCodeViewExactManifestPolicyReceipt | null>(
		null,
	);
	const recentInstantSelectionRevealRef = useRef<BridgeCodeViewInstantRevealRearmCandidate | null>(
		null,
	);
	const settledInstantSelectionRevealKeyRef = useRef<string | null>(null);
	const lastProgrammaticRevealItemIdRef = useRef<string | null>(null);
	const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
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
	const postRenderVisibleInterestPublisher = useMemo(
		() =>
			createBridgeCodeViewPostRenderVisibleInterestPublisher({
				publishSettledWindow: publishVisibleItemIdsFromCurrentHandle,
				queueMicrotask: (callback): void => {
					globalThis.queueMicrotask(callback);
				},
			}),
		[publishVisibleItemIdsFromCurrentHandle],
	);
	const handleCodeViewPostRender = useCallback<
		NonNullable<CodeViewOptions<undefined>['onPostRender']>
	>(
		(_node, _instance, phase, context): void => {
			const exactPresentationItem = isBridgeCodeViewItem(context.item) ? context.item : null;
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: exactPresentationItem,
				visibleCodeViewItems: undefined,
			});
			postRenderVisibleInterestPublisher.schedule();
		},
		[postRenderVisibleInterestPublisher, props.renderFulfillmentCoordinator],
	);
	useEffect(
		(): (() => void) => (): void => {
			postRenderVisibleInterestPublisher.cancel();
		},
		[postRenderVisibleInterestPublisher],
	);
	const scheduleCodeViewRecoveryRender = useCallback((): void => {
		if (pendingRecoveryRenderFrameRef.current !== null) {
			cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
		}
		pendingRecoveryRenderFrameRef.current = requestAnimationFrame((): void => {
			pendingRecoveryRenderFrameRef.current = null;
			publishVisibleItemIdsFromCurrentHandle();
		});
	}, [publishVisibleItemIdsFromCurrentHandle]);
	const scheduleCodeViewScrollIdle = useCallback(
		(viewer: BridgeCodeViewRenderedItemsSource | null = null): void => {
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
			}
			scrollIdleTimeoutRef.current = setTimeout((): void => {
				scrollIdleTimeoutRef.current = null;
				const codeViewInstance = codeViewHandleRef.current?.getInstance();
				if (codeViewInstance !== undefined && hasRenderedItemsSource(codeViewInstance)) {
					pendingRenderedItemsSourceRef.current = codeViewInstance;
				} else if (viewer !== null) {
					pendingRenderedItemsSourceRef.current = viewer;
				}
				if (scrollActivityActiveRef.current) {
					scrollActivityActiveRef.current = false;
					onScrollActivityChangeRef.current?.(false);
				}
				publishVisibleHydrationItemIds();
			}, codeViewVisibleHydrationScrollIdleMilliseconds);
		},
		[publishVisibleHydrationItemIds],
	);
	const handleCodeViewUserScrollIntent = useCallback((): void => {
		programmaticRevealGate.recordUserScrollIntent();
		cancelPendingProgrammaticReveal();
		if (!scrollActivityActiveRef.current) {
			scrollActivityActiveRef.current = true;
			onScrollActivityChangeRef.current?.(true);
		}
		scheduleCodeViewScrollIdle();
	}, [cancelPendingProgrammaticReveal, programmaticRevealGate, scheduleCodeViewScrollIdle]);
	const handleCodeViewScroll = useCallback(
		(_scrollTop: number, viewer: BridgeCodeViewRenderedItemsSource): void => {
			pendingRenderedItemsSourceRef.current = viewer;
			publishVisibleItemIds(viewer);
			scheduleCodeViewScrollIdle(viewer);
		},
		[publishVisibleItemIds, scheduleCodeViewScrollIdle],
	);
	const scheduleVisibleHeaderItemIdsPublish = useCallback((): void => {
		if (pendingVisibleHeaderPublishFrameRef.current !== null) {
			cancelAnimationFrame(pendingVisibleHeaderPublishFrameRef.current);
		}
		pendingVisibleHeaderPublishFrameRef.current = requestAnimationFrame((): void => {
			pendingVisibleHeaderPublishFrameRef.current = null;
			publishVisibleHydrationItemIds();
		});
	}, [publishVisibleHydrationItemIds]);
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
	const { scheduleInstantSelectionRevealRetarget, scrollToItem } =
		useBridgeCodeViewProgrammaticScroll({
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
		});
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
	const initialItemsSelector = useMemo(
		() => createBridgeCodeViewInitialItemsForPanelSelector(),
		[],
	);
	const metadataDeltaItemsSelector = useMemo(
		() => createBridgeCodeViewMetadataDeltaItemsForPanelSelector(),
		[],
	);
	const initialItems = useMemo(() => {
		return initialItemsSelector({
			projection: props.projection,
			reviewPackage: props.reviewPackage,
			sourceKey,
		});
	}, [initialItemsSelector, props.projection, props.reviewPackage, sourceKey]);
	const authoritativeItemIds = useMemo(
		(): readonly string[] => initialItems.map((item): string => item.id),
		[initialItems],
	);
	const authoritativeIndexByItemId = useMemo(
		(): ReadonlyMap<string, number> =>
			new Map(initialItems.map((item, index): readonly [string, number] => [item.id, index])),
		[initialItems],
	);
	const metadataDeltaItems = useMemo((): readonly BridgeCodeViewItem[] => {
		return metadataDeltaItemsSelector({
			reviewPackage: props.reviewPackage,
			selectedCodeViewItem: props.selectedCodeViewItem,
			selectedContentLoadingItemId: props.selectedContentLoadingItemId,
			selectedItemId: props.selectedItemId,
			selectedItemPresentation: props.selectedItemPresentation,
			sourceKey,
			visibleCodeViewItems: props.visibleCodeViewItems,
		});
	}, [
		metadataDeltaItemsSelector,
		props.reviewPackage,
		props.selectedCodeViewItem,
		props.selectedContentLoadingItemId,
		props.selectedItemId,
		props.selectedItemPresentation,
		props.visibleCodeViewItems,
		sourceKey,
	]);
	const initialPresentationItems = useMemo(
		(): readonly BridgeCodeViewItem[] =>
			bridgeCodeViewInitialItemsWithMetadataDeltaItems({
				initialItems,
				metadataDeltaItems,
			}),
		[initialItems, metadataDeltaItems],
	);
	useLayoutEffect((): void => {
		materializationTaskGenerationRef.current += 1;
		metadataApplyTaskGenerationRef.current += 1;
		currentCodeViewItemsRef.current = [];
		currentCodeViewManifestMountKeyRef.current = null;
		if (pendingMetadataApplyFrameRef.current !== null) {
			clearTimeout(pendingMetadataApplyFrameRef.current);
			pendingMetadataApplyFrameRef.current = null;
		}
		controllerEntryRef.current = null;
		completedSelectionScrollKeyRef.current = null;
		lastSelectionScrollKeyRef.current = null;
		lastMetadataApplySourceKeyRef.current = null;
		lastMetadataApplyMountVersionRef.current = null;
		lastMetadataManifestItemsRef.current = null;
		exactManifestPolicyReceiptRef.current = null;
		pendingPreHydrationSelectionScrollKeyRef.current = null;
		pendingSelectionRevealBehaviorRef.current = null;
		pendingSmoothSelectionScrollKeyRef.current = null;
		recentInstantSelectionRevealRef.current = null;
		settledInstantSelectionRevealKeyRef.current = null;
		setMaterializationDiagnostic(emptyMaterializationDiagnostic());
	}, [sourceKey]);
	useLayoutEffect((): void => {
		const manifestMountKey = `${sourceKey}:${codeViewMountVersion}`;
		if (currentCodeViewManifestMountKeyRef.current === manifestMountKey) {
			return;
		}
		currentCodeViewItemsRef.current = initialPresentationItems;
		currentCodeViewManifestMountKeyRef.current = manifestMountKey;
	}, [codeViewMountVersion, initialPresentationItems, sourceKey]);

	useEffect((): (() => void) | void => {
		const codeViewHandle = codeViewHandleRef.current;
		const codeViewInstance = codeViewHandle?.getInstance();
		if (codeViewHandle === null || codeViewInstance === undefined) {
			return;
		}
		const sourceReset =
			lastMetadataApplySourceKeyRef.current !== sourceKey ||
			lastMetadataApplyMountVersionRef.current !== codeViewMountVersion;
		const manifestChanged = lastMetadataManifestItemsRef.current !== initialItems;
		const exactManifestPolicyReceipt = exactManifestPolicyReceiptRef.current;
		const forceAuthoritativeReplacement =
			exactManifestPolicyReceipt === null ||
			exactManifestPolicyReceipt.initialItems !== initialItems ||
			exactManifestPolicyReceipt.mountVersion !== codeViewMountVersion ||
			exactManifestPolicyReceipt.policyVersion !== bridgeCodeViewExactManifestPolicyVersion ||
			exactManifestPolicyReceipt.sourceKey !== sourceKey;
		const requiresManifestReconciliation =
			forceAuthoritativeReplacement ||
			bridgeCodeViewMetadataRequiresManifestReconciliation({
				authoritativeIndexByItemId,
				authoritativeItemIds,
				getCurrentItem: (itemId: string): CodeViewItem | undefined =>
					codeViewHandle.getItem(itemId),
				getCurrentItemTop: (itemId: string): number | undefined =>
					codeViewInstance.getTopForItem(itemId),
				manifestChanged,
				metadataDeltaItems,
				sourceReset,
			});
		const taskGeneration = metadataApplyTaskGenerationRef.current + 1;
		metadataApplyTaskGenerationRef.current = taskGeneration;
		if (pendingMetadataApplyFrameRef.current !== null) {
			clearTimeout(pendingMetadataApplyFrameRef.current);
			pendingMetadataApplyFrameRef.current = null;
		}
		const metadataSourceItems = requiresManifestReconciliation
			? bridgeCodeViewInitialItemsWithMetadataDeltaItems({
					initialItems,
					metadataDeltaItems,
				})
			: metadataDeltaItems;
		const metadataItems = reconcileBridgeCodeViewMetadataItems({
			forceReplaceItemIds:
				props.selectedItemId !== null &&
				props.selectedItemPresentation !== null &&
				props.selectedItemPresentation !== undefined &&
				metadataDeltaItems.some(
					(item): boolean =>
						item.id === props.selectedItemId && item.bridgeMetadata.contentState === 'loading',
				)
					? [props.selectedItemId]
					: [],
			getCurrentItem: (itemId: string): CodeViewItem | undefined => codeViewHandle.getItem(itemId),
			metadataItems: metadataSourceItems,
			preparePresentationItem: ({ currentItem, metadataItem }): BridgeCodeViewItem => {
				return prepareBridgeCodeViewPublicationPresentationItem({
					currentItem,
					getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
					metadataItem,
					renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				});
			},
			preserveItemIds: sourceReset
				? []
				: selectedItemIdForMetadataReconcileRef.current === null
					? []
					: [selectedItemIdForMetadataReconcileRef.current],
		});
		const scheduleMetadataApplyTurn = (callback: () => void): void => {
			pendingMetadataApplyFrameRef.current = window.setTimeout((): void => {
				pendingMetadataApplyFrameRef.current = null;
				callback();
			}, 0);
		};
		const controller = controllerForHandle({
			handle: codeViewHandle,
			controllerEntryRef,
		});
		const workerPreparedTelemetryContext = {
			parentTraceContext: props.telemetryParentTraceContext ?? null,
			projection: projectionRef.current,
			reviewPackage: reviewPackageRef.current,
			selectedContentPaintTelemetryStart: props.selectedContentPaintTelemetryStart ?? null,
			selectedItemId: props.selectedItemId,
			telemetryRecorder: props.telemetryRecorder,
		} satisfies BridgeCodeViewWorkerPreparedTelemetryContext;
		const metadataApplyProps = {
			applyItemUpdate: (item): void => {
				const previousItem = codeViewHandle.getItem(item.id);
				const didFindMatchingPaintedContent =
					isBridgeCodeViewItem(previousItem) &&
					isMaterializedBridgeCodeViewContentState(previousItem.bridgeMetadata.contentState) &&
					previousItem.bridgeMetadata.cacheKey === item.bridgeMetadata.cacheKey;
				const materializationStartedAtMilliseconds = performance.now();
				currentCodeViewItemsRef.current = bridgeCodeViewItemsWithMetadataItem({
					currentItems: currentCodeViewItemsRef.current,
					item,
				});
				const updateResult = controller.applyItemUpdate(item);
				const materializationCompletedAtMilliseconds = performance.now();
				reconcileBridgeCodeViewRenderFulfillment({
					exactPresentationItem: item,
					getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
					renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				});
				recordBridgeCodeViewWorkerPreparedApplyTelemetry({
					...workerPreparedTelemetryContext,
					codeViewItem: item,
					updateResult,
					materializationStartedAtMilliseconds,
					materializationCompletedAtMilliseconds,
					didFindMatchingPaintedContent,
				});
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => metadataApplyTaskGenerationRef.current !== taskGeneration,
			items: metadataItems,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => performance.now(),
			onComplete: (): void => {
				lastMetadataApplySourceKeyRef.current = sourceKey;
				lastMetadataApplyMountVersionRef.current = codeViewMountVersion;
				lastMetadataManifestItemsRef.current = initialItems;
				exactManifestPolicyReceiptRef.current = {
					initialItems,
					mountVersion: codeViewMountVersion,
					policyVersion: bridgeCodeViewExactManifestPolicyVersion,
					sourceKey,
				};
				const selectedItemId = selectedItemIdForMetadataReconcileRef.current;
				if (selectedItemId !== null) {
					const selectionScrollKey = `${sourceKey}:${codeViewMountVersion}:${selectedItemId}`;
					const didConsumeHydrationAnchor = consumeBridgeCodeViewPendingHydrationAnchor({
						codeViewHandle,
						completedSelectionScrollKeyRef,
						itemId: selectedItemId,
						nowMilliseconds: performance.now(),
						pendingPreHydrationSelectionScrollKeyRef,
						pendingSelectionRevealBehaviorRef,
						pendingSmoothSelectionScrollKeyRef,
						recentInstantSelectionRevealRef,
						scheduleRetarget: (): void => {
							scheduleInstantSelectionRevealRetarget({
								codeViewHandle,
								itemId: selectedItemId,
								selectionScrollKey,
								viewportOffsetTolerancePixels:
									bridgeCodeViewInstantRevealPolicy.hydrationRearmViewportOffsetTolerancePixels,
							});
						},
						selectionScrollKey,
						settledInstantSelectionRevealKeyRef,
					});
					if (didConsumeHydrationAnchor) {
						setSelectionScrollDiagnostic({
							didScroll: true,
							itemId: selectedItemId,
							itemTop: codeViewHandle.getInstance()?.getTopForItem(selectedItemId) ?? 'missing',
							reason: 'hydration-retarget',
							remainingFrameBudget: codeViewSelectionScrollRetryFrameBudget,
						});
					}
				}
				scheduleCodeViewRecoveryRender();
			},
			rankForItem: (item): 'selected' | 'visible' =>
				item.id === selectedItemIdForMetadataReconcileRef.current ? 'selected' : 'visible',
			replacementItemsForItem: (item): readonly BridgeCodeViewItem[] | null => {
				const currentItem = codeViewHandle.getItem(item.id);
				if (!isBridgeCodeViewItem(currentItem) || currentItem.type === item.type) {
					return null;
				}
				return bridgeCodeViewItemsWithMetadataItem({
					currentItems: currentCodeViewItemsRef.current,
					item,
				});
			},
			scheduleNextTurn: scheduleMetadataApplyTurn,
			setItems: (items): void => {
				const previousItemsById = new Map<string, CodeViewItem | undefined>(
					items.map((item): readonly [string, CodeViewItem | undefined] => [
						item.id,
						codeViewHandle.getItem(item.id),
					]),
				);
				const materializationStartedAtMilliseconds = performance.now();
				currentCodeViewItemsRef.current = items;
				codeViewInstance.setItems(items);
				const materializationCompletedAtMilliseconds = performance.now();
				for (const item of items) {
					reconcileBridgeCodeViewRenderFulfillment({
						exactPresentationItem: item,
						getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
						renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
					});
					const previousItem = previousItemsById.get(item.id);
					const didFindMatchingPaintedContent =
						isBridgeCodeViewItem(previousItem) &&
						isMaterializedBridgeCodeViewContentState(previousItem.bridgeMetadata.contentState) &&
						previousItem.bridgeMetadata.cacheKey === item.bridgeMetadata.cacheKey;
					recordBridgeCodeViewWorkerPreparedApplyTelemetry({
						...workerPreparedTelemetryContext,
						codeViewItem: item,
						updateResult: applyResultForSetItemsItem({
							currentItem: previousItem,
							nextItem: item,
						}),
						materializationStartedAtMilliseconds,
						materializationCompletedAtMilliseconds,
						didFindMatchingPaintedContent,
					});
				}
			},
			shouldSkipItem: (item): boolean => codeViewHandle.getItem(item.id) === item,
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		} satisfies RunBridgeCodeViewMetadataApplyInChunksProps;
		if (requiresManifestReconciliation) {
			runBridgeCodeViewMetadataReconciliationInChunks({
				...metadataApplyProps,
				currentItems: currentCodeViewItemsRef.current,
				forceAuthoritativeReplacement,
				getCurrentItem: (itemId) => codeViewHandle.getItem(itemId),
				getCurrentItemTop: (itemId) => codeViewInstance.getTopForItem(itemId),
				isTaskStale: (): boolean => metadataApplyTaskGenerationRef.current !== taskGeneration,
			});
		} else {
			runBridgeCodeViewMetadataApplyInChunks(metadataApplyProps);
		}
		return (): void => {
			metadataApplyTaskGenerationRef.current += 1;
			if (pendingMetadataApplyFrameRef.current !== null) {
				clearTimeout(pendingMetadataApplyFrameRef.current);
				pendingMetadataApplyFrameRef.current = null;
			}
		};
	}, [
		authoritativeIndexByItemId,
		authoritativeItemIds,
		codeViewMountVersion,
		initialItems,
		metadataDeltaItems,
		scheduleCodeViewRecoveryRender,
		props.selectedItemId,
		props.selectedContentPaintTelemetryStart,
		props.selectedItemPresentation,
		props.renderFulfillmentCoordinator,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		scheduleInstantSelectionRevealRetarget,
		sourceKey,
	]);

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
		const taskGeneration = materializationTaskGenerationRef.current + 1;
		materializationTaskGenerationRef.current = taskGeneration;
		if (pendingMaterializationFrameRef.current !== null) {
			clearTimeout(pendingMaterializationFrameRef.current);
			pendingMaterializationFrameRef.current = null;
		}
		if (loadingMaterializationItemIds.length === 0) {
			return;
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
					bridgeCodeViewLoadingPlaceholderMatchesDescriptor({
						existingItem,
						loadingItem,
					})
				) {
					continue;
				}
				controller.applyItemUpdate(loadingItem);
				currentCodeViewItemsRef.current = bridgeCodeViewItemsWithMetadataItem({
					currentItems: currentCodeViewItemsRef.current,
					item: loadingItem,
				});
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
			handleCodeViewPostRender={handleCodeViewPostRender}
			handleCodeViewScroll={handleCodeViewScroll}
			handleCodeViewUserScrollIntent={handleCodeViewUserScrollIntent}
			headerRenderers={headerRenderers}
			initialItems={initialPresentationItems}
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
			selectedInitialItemIndex={initialPresentationItems.findIndex(
				(item): boolean => item.id === props.selectedItemId,
			)}
			selectedInitialItemIsFirst={initialPresentationItems[0]?.id === props.selectedItemId}
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
