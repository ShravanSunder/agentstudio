import type { CodeViewItem, CodeViewOptions, CodeViewScrollBehavior } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { ChevronDownIcon, ChevronRightIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import { cn } from '../../app/class-name.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { recordBridgeCodeViewHydrationTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import { BridgePierreWorkerPoolProvider } from '../workers/pierre/bridge-pierre-worker-pool.js';
import {
	BridgeCodeViewController,
	type ApplyBridgeCodeViewItemUpdateResult,
	type BridgeCodeViewModel,
} from './bridge-code-view-controller.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import { bridgePierreDarkThemeName } from './bridge-code-view-theme.js';

export interface BridgeCodeViewPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedContentLoadingItemId?: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
	readonly visibleContentResourcesByItemId?: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleLoadingItemIds?: ReadonlySet<string>;
	readonly visibleLoadingItemCount?: number;
	readonly visibleReadyItemCount?: number;
	readonly workerPoolEnabled?: boolean;
	readonly workerFactory?: () => Worker;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
	readonly onControlHandleChange?: (handle: BridgeCodeViewControlHandle | null) => void;
	readonly onVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
}

export interface BridgeCodeViewControlHandle {
	readonly scrollToItem: (itemId: string, options?: BridgeCodeViewScrollToItemOptions) => boolean;
	readonly setItemCollapsed: (itemId: string, collapsed: boolean) => boolean;
}

export interface BridgeCodeViewScrollToItemOptions {
	readonly behavior?: CodeViewScrollBehavior;
	readonly expandIfCollapsed?: boolean;
}

interface BridgeCodeViewControllerEntry {
	readonly handle: CodeViewHandle<undefined>;
	readonly controller: BridgeCodeViewController;
}

interface BridgeCodeViewMaterializationDiagnostic {
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult | 'not-run';
	readonly itemType: BridgeCodeViewItem['type'] | 'none';
	readonly itemVersion: number;
	readonly additionLineCount: number;
	readonly deletionLineCount: number;
	readonly fileLineCount: number;
}

interface BridgeCodeViewHeaderAnchor {
	readonly containerElement: HTMLElement;
	readonly itemId: string;
	readonly offsetFromScrollOwnerTop: number;
	readonly scrollOwner: HTMLElement;
}

interface BridgeCodeViewRenderedItemSnapshot {
	readonly id: string;
}

interface BridgeCodeViewRenderedItemsSource {
	readonly getRenderedItems: () => readonly BridgeCodeViewRenderedItemSnapshot[];
}

export const bridgeCodeViewOptions: CodeViewOptions<undefined> = {
	theme: {
		dark: bridgePierreDarkThemeName,
		light: bridgePierreDarkThemeName,
	},
	themeType: 'dark',
	diffStyle: 'split',
	diffIndicators: 'bars',
	overflow: 'scroll',
	useTokenTransformer: false,
	tokenizeMaxLineLength: 20_000,
	lineDiffType: 'word',
	maxLineDiffLength: 1000,
	hunkSeparators: 'line-info-basic',
	collapsedContextThreshold: 2,
	expansionLineCount: 100,
	expandUnchanged: false,
	disableVirtualizationBuffers: false,
	stickyHeaders: true,
	layout: {
		paddingTop: 0,
		paddingBottom: 0,
		gap: 1,
	},
	unsafeCSS: `
		[data-diffs-header] {
			--diffs-addition-base: var(--bridge-added);
			--diffs-deletion-base: var(--bridge-deleted);
			--diffs-modified-base: var(--bridge-accent);
			--diffs-fg: var(--bridge-text-primary);
			--diffs-fg-number: var(--bridge-text-muted);
			container-type: scroll-state;
			container-name: bridge-code-view-sticky-header;
			background-color: var(--bridge-surface-bg);
			cursor: default;
			min-height: 32px;
			user-select: none;
		}

		[data-diffs-header] * {
			cursor: default;
			user-select: none;
		}

		[data-diffs-header] button,
		[data-diffs-header] [role='button'] {
			cursor: pointer;
		}

		[data-diffs-header='default'] {
			border-block: 1px solid var(--bridge-border-subtle);
			color: var(--bridge-text-secondary);
			padding-inline: 12px;
		}

		[data-diffs-header='default'] [data-title],
		[data-diffs-header='default'] [data-prev-name] {
			color: var(--bridge-text-secondary);
			font-weight: 500;
		}

		@container bridge-code-view-sticky-header scroll-state(stuck: top) {
			[data-diffs-header]::after {
				position: absolute;
				bottom: -1px;
				left: 0;
				width: 100%;
				height: 1px;
				content: '';
				background-color: var(--bridge-border-opaque);
			}
		}
	`,
};
const codeViewHeaderAnchorRestoreFrameBudget = 30;

export function BridgeCodeViewPanel(props: BridgeCodeViewPanelProps): ReactElement {
	const viewerKey = makeViewerKey(props);
	const selectedDisplayPath =
		props.selectedItemId === null
			? null
			: (props.projection.primaryDisplayPathByItemId[props.selectedItemId] ?? null);
	const selectedContentState = selectedContentStateForPanel({
		selectedContentResources: props.selectedContentResources,
		selectedItemId: props.selectedItemId,
	});
	const selectedContentRoleCount =
		props.selectedContentResources === null || props.selectedContentResources === undefined
			? 0
			: Object.values(props.selectedContentResources).filter(
					(resource): boolean => resource !== undefined,
				).length;
	const selectedContentSummary = selectedContentSummaryForPanel({
		selectedContentResources: props.selectedContentResources,
	});
	const reviewItemsById = props.reviewPackage.itemsById;
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const controllerEntryRef = useRef<BridgeCodeViewControllerEntry | null>(null);
	const completedSelectionScrollKeyRef = useRef<string | null>(null);
	const lastSelectionScrollKeyRef = useRef<string | null>(null);
	const mountedHandleViewerKeyRef = useRef<string | null>(null);
	const materializationTaskGenerationRef = useRef(0);
	const pendingRecoveryRenderFrameRef = useRef<number | null>(null);
	const pendingRenderedItemsPublishFrameRef = useRef<number | null>(null);
	const pendingSelectionScrollFrameRef = useRef<number | null>(null);
	const pendingSmoothSelectionScrollKeyRef = useRef<string | null>(null);
	const pendingVisibleHeaderPublishFrameRef = useRef<number | null>(null);
	const renderedWindowItemIdsRef = useRef<readonly string[]>([]);
	const scrollToTopTargetItemIdRef = useRef<string | null>(null);
	const visibleHeaderItemIdsRef = useRef<ReadonlySet<string>>(new Set<string>());
	const initialSelectedItemByViewerKeyRef = useRef<{
		readonly selectedItemId: string | null;
		readonly viewerKey: string;
	} | null>(null);
	if (initialSelectedItemByViewerKeyRef.current?.viewerKey !== viewerKey) {
		initialSelectedItemByViewerKeyRef.current = {
			selectedItemId: props.selectedItemId,
			viewerKey,
		};
	}
	const [codeViewMountVersion, setCodeViewMountVersion] = useState(0);
	const [collapsedItemIds, setCollapsedItemIds] = useState<ReadonlySet<string>>(
		() => new Set<string>(),
	);
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
	const publishVisibleItemIds = useCallback(
		(source: BridgeCodeViewRenderedItemsSource): void => {
			renderedWindowItemIdsRef.current = uniqueRenderedItemIds(source.getRenderedItems());
			publishVisibleHydrationItemIds();
		},
		[publishVisibleHydrationItemIds],
	);
	const publishVisibleItemIdsFromCurrentHandle = useCallback((): void => {
		const instance = codeViewHandleRef.current?.getInstance();
		if (instance === undefined || !hasRenderedItemsSource(instance)) {
			return;
		}
		publishVisibleItemIds(instance);
	}, [publishVisibleItemIds]);
	const publishVisibleItemIdsAcrossRenderFrames = useCallback(
		(source: BridgeCodeViewRenderedItemsSource, frameBudget = 4): void => {
			if (frameBudget <= 0) {
				publishVisibleItemIds(source);
				return;
			}
			if (pendingRenderedItemsPublishFrameRef.current !== null) {
				cancelAnimationFrame(pendingRenderedItemsPublishFrameRef.current);
			}
			pendingRenderedItemsPublishFrameRef.current = requestAnimationFrame((): void => {
				pendingRenderedItemsPublishFrameRef.current = null;
				publishVisibleItemIds(source);
				publishVisibleItemIdsAcrossRenderFrames(source, frameBudget - 1);
			});
		},
		[publishVisibleItemIds],
	);
	const handleCodeViewScroll = useCallback(
		(_scrollTop: number, viewer: BridgeCodeViewRenderedItemsSource): void => {
			publishVisibleItemIdsAcrossRenderFrames(viewer);
		},
		[publishVisibleItemIdsAcrossRenderFrames],
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
			codeViewHandleRef.current = handle;
			if (handle !== null && mountedHandleViewerKeyRef.current !== viewerKey) {
				mountedHandleViewerKeyRef.current = viewerKey;
				renderedWindowItemIdsRef.current = [];
				visibleHeaderItemIdsRef.current = new Set<string>();
				setCodeViewMountVersion((currentVersion: number): number => currentVersion + 1);
			}
		},
		[viewerKey],
	);
	const setItemCollapsed = useCallback(
		(itemId: string, collapsed: boolean): boolean => {
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null) {
				return false;
			}
			const currentItem = codeViewHandle.getItem(itemId);
			if (currentItem === undefined || !isBridgeCodeViewItem(currentItem)) {
				return false;
			}
			if (currentItem.collapsed === collapsed) {
				return true;
			}
			if (pendingSmoothSelectionScrollKeyRef.current !== null) {
				settleCodeViewScrollAtCurrentPosition(codeViewHandle);
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
			restoreCodeViewHeaderAnchorAcrossLayout({
				anchor: headerAnchor,
				frameBudget: codeViewHeaderAnchorRestoreFrameBudget,
				isCurrent: (): boolean => codeViewHandleRef.current === codeViewHandle,
			});
			setCollapsedItemIds((currentIds: ReadonlySet<string>): ReadonlySet<string> => {
				const nextIds = new Set(currentIds);
				if (collapsed) {
					nextIds.add(itemId);
				} else {
					nextIds.delete(itemId);
				}
				return nextIds;
			});
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
			const currentItem = codeViewHandle.getItem(itemId);
			if (currentItem === undefined || !isBridgeCodeViewItem(currentItem)) {
				return false;
			}
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef,
			});
			const scrollBehavior = options.behavior ?? 'instant';
			if ((options.expandIfCollapsed ?? true) && currentItem.collapsed === true) {
				const itemDescriptor = reviewItemsById[itemId];
				const nextItem =
					itemDescriptor === undefined
						? ({
								...currentItem,
								collapsed: false,
								version: (currentItem.version ?? 0) + 1,
							} satisfies BridgeCodeViewItem)
						: nextCodeViewItemForCollapse({
								collapsed: false,
								currentItem,
								itemDescriptor,
							});
				controller.applyItemUpdate(nextItem);
				setCollapsedItemIds((currentIds: ReadonlySet<string>): ReadonlySet<string> => {
					const nextIds = new Set(currentIds);
					nextIds.delete(itemId);
					return nextIds;
				});
			}
			controller.scrollToItem(itemId, scrollBehavior);
			const selectionScrollKey = `${viewerKey}:${codeViewMountVersion}:${itemId}`;
			if (currentItem.bridgeMetadata.contentState === 'hydrated') {
				completedSelectionScrollKeyRef.current = selectionScrollKey;
			}
			if (scrollBehavior === 'instant') {
				pendingSmoothSelectionScrollKeyRef.current = null;
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
				if (scrollBehavior === 'smooth-auto') {
					scrollToTopTargetItemIdRef.current = itemId;
					scrollCodeViewHeaderToScrollTopAcrossLayout({
						handle: codeViewHandle,
						itemId,
						isCurrent: (): boolean =>
							codeViewHandleRef.current === codeViewHandle &&
							scrollToTopTargetItemIdRef.current === itemId,
					});
				}
			}
			lastSelectionScrollKeyRef.current = selectionScrollKey;
			return true;
		},
		[codeViewMountVersion, reviewItemsById, viewerKey],
	);
	const toggleItemCollapse = useCallback(
		(itemId: string): void => {
			const codeViewHandle = codeViewHandleRef.current;
			const currentItem = codeViewHandle?.getItem(itemId);
			if (currentItem === undefined || !isBridgeCodeViewItem(currentItem)) {
				return;
			}
			setItemCollapsed(itemId, currentItem.collapsed !== true);
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
	const initialItems = useMemo(
		() =>
			createBridgeCodeViewInitialItems({
				reviewPackage: props.reviewPackage,
				projection: props.projection,
			}),
		[props.projection, props.reviewPackage],
	);
	const materializationResourceEntries = useMemo((): readonly (readonly [
		string,
		BridgeCodeViewContentResources,
	])[] => {
		const resourceEntriesByItemId = new Map<string, BridgeCodeViewContentResources>();
		for (const [itemId, resources] of props.visibleContentResourcesByItemId ?? []) {
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
	}, [props.selectedContentResources, props.selectedItemId, props.visibleContentResourcesByItemId]);
	const loadingMaterializationItemIds = useMemo((): readonly string[] => {
		const loadedItemIds = new Set(materializationResourceEntries.map(([itemId]): string => itemId));
		const loadingItemIds = new Set(props.visibleLoadingItemIds ?? []);
		if (
			props.selectedContentLoadingItemId !== undefined &&
			props.selectedContentLoadingItemId !== null
		) {
			loadingItemIds.add(props.selectedContentLoadingItemId);
		}
		return [...loadingItemIds].filter((itemId: string): boolean => !loadedItemIds.has(itemId));
	}, [
		materializationResourceEntries,
		props.selectedContentLoadingItemId,
		props.visibleLoadingItemIds,
	]);

	const scheduleCodeViewRecoveryRender = useCallback((): void => {
		if (pendingRecoveryRenderFrameRef.current !== null) {
			cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
		}
		pendingRecoveryRenderFrameRef.current = requestAnimationFrame((): void => {
			pendingRecoveryRenderFrameRef.current = null;
			codeViewHandleRef.current?.getInstance()?.render(true);
			publishVisibleItemIdsFromCurrentHandle();
		});
	}, [publishVisibleItemIdsFromCurrentHandle]);

	useEffect((): void => {
		materializationTaskGenerationRef.current += 1;
		controllerEntryRef.current = null;
		completedSelectionScrollKeyRef.current = null;
		lastSelectionScrollKeyRef.current = null;
		pendingSmoothSelectionScrollKeyRef.current = null;
		setMaterializationDiagnostic(emptyMaterializationDiagnostic());
	}, [viewerKey]);

	useEffect(
		(): (() => void) => (): void => {
			materializationTaskGenerationRef.current += 1;
			if (pendingRecoveryRenderFrameRef.current !== null) {
				cancelAnimationFrame(pendingRecoveryRenderFrameRef.current);
				pendingRecoveryRenderFrameRef.current = null;
			}
			if (pendingRenderedItemsPublishFrameRef.current !== null) {
				cancelAnimationFrame(pendingRenderedItemsPublishFrameRef.current);
				pendingRenderedItemsPublishFrameRef.current = null;
			}
			if (pendingSelectionScrollFrameRef.current !== null) {
				cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
				pendingSelectionScrollFrameRef.current = null;
			}
			if (pendingVisibleHeaderPublishFrameRef.current !== null) {
				cancelAnimationFrame(pendingVisibleHeaderPublishFrameRef.current);
				pendingVisibleHeaderPublishFrameRef.current = null;
			}
		},
		[],
	);

	useEffect((): void => {
		if (props.selectedItemId === null) {
			return;
		}
		const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
		if (selectedItem === undefined) {
			return;
		}
		const codeViewHandle = codeViewHandleRef.current;
		if (codeViewHandle === null) {
			return;
		}
		const selectedItemId = props.selectedItemId;
		const selectionScrollKey = `${viewerKey}:${codeViewMountVersion}:${selectedItemId}`;
		if (lastSelectionScrollKeyRef.current === selectionScrollKey) {
			return;
		}
		lastSelectionScrollKeyRef.current = selectionScrollKey;
		const shouldUseInitialPlacement =
			initialSelectedItemByViewerKeyRef.current?.viewerKey === viewerKey &&
			initialSelectedItemByViewerKeyRef.current.selectedItemId === selectedItemId;
		pendingSmoothSelectionScrollKeyRef.current = shouldUseInitialPlacement
			? null
			: selectionScrollKey;
		if (pendingSelectionScrollFrameRef.current !== null) {
			cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
		}
		pendingSelectionScrollFrameRef.current = requestAnimationFrame((): void => {
			pendingSelectionScrollFrameRef.current = null;
			if (
				codeViewHandleRef.current !== codeViewHandle ||
				props.reviewPackage.itemsById[selectedItemId] === undefined
			) {
				return;
			}
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef,
			});
			if (completedSelectionScrollKeyRef.current === selectionScrollKey) {
				return;
			}
			const scrollBehavior: CodeViewScrollBehavior = shouldUseInitialPlacement
				? 'instant'
				: 'smooth';
			controller.scrollToItem(selectedItemId, scrollBehavior);
			if (scrollBehavior === 'instant') {
				completedSelectionScrollKeyRef.current = selectionScrollKey;
				pendingSmoothSelectionScrollKeyRef.current = null;
				scrollToTopTargetItemIdRef.current = selectedItemId;
				scrollCodeViewHeaderToScrollTopAcrossLayout({
					handle: codeViewHandle,
					itemId: selectedItemId,
					isCurrent: (): boolean =>
						codeViewHandleRef.current === codeViewHandle &&
						scrollToTopTargetItemIdRef.current === selectedItemId,
				});
			} else {
				completedSelectionScrollKeyRef.current = selectionScrollKey;
				pendingSmoothSelectionScrollKeyRef.current = null;
			}
		});
	}, [codeViewMountVersion, props.reviewPackage, props.selectedItemId, viewerKey]);

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
		viewerKey,
	]);

	useEffect((): void => {
		if (loadingMaterializationItemIds.length === 0 && materializationResourceEntries.length === 0) {
			return;
		}
		const taskGeneration = materializationTaskGenerationRef.current + 1;
		materializationTaskGenerationRef.current = taskGeneration;
		queueMicrotask((): void => {
			if (materializationTaskGenerationRef.current !== taskGeneration) {
				return;
			}
			const codeViewHandle = codeViewHandleRef.current;
			if (codeViewHandle === null) {
				return;
			}
			const controller = controllerForHandle({
				handle: codeViewHandle,
				controllerEntryRef,
			});
			let didUpdateRenderedItems = false;
			for (const itemId of loadingMaterializationItemIds) {
				const loadingItemDescriptor = props.reviewPackage.itemsById[itemId];
				if (loadingItemDescriptor === undefined) {
					continue;
				}
				const loadingItem = materializeBridgeCodeViewLoadingItem(loadingItemDescriptor);
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
				const selectedItem = props.reviewPackage.itemsById[itemId];
				if (selectedItem === undefined) {
					continue;
				}
				const materializedItem = materializeBridgeCodeViewItem({
					item: selectedItem,
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
					existingItem.bridgeMetadata.contentState === 'hydrated' &&
					existingItem.bridgeMetadata.cacheKey === nextMaterializedItem.bridgeMetadata.cacheKey &&
					existingItem.collapsed === nextMaterializedItem.collapsed
				) {
					continue;
				}
				const updateResult = controller.applyItemUpdate(nextMaterializedItem);
				didUpdateRenderedItems = true;
				if (itemId === props.selectedItemId) {
					const selectionScrollKey = `${viewerKey}:${codeViewMountVersion}:${itemId}`;
					if (completedSelectionScrollKeyRef.current !== selectionScrollKey) {
						const shouldPreserveSmoothReveal =
							pendingSmoothSelectionScrollKeyRef.current === selectionScrollKey;
						if (shouldPreserveSmoothReveal) {
							if (pendingSelectionScrollFrameRef.current !== null) {
								cancelAnimationFrame(pendingSelectionScrollFrameRef.current);
								pendingSelectionScrollFrameRef.current = null;
								controller.scrollToItem(itemId, 'smooth');
							}
							pendingSmoothSelectionScrollKeyRef.current = null;
						} else {
							controller.scrollToItem(itemId, 'instant');
							scrollToTopTargetItemIdRef.current = itemId;
							scrollCodeViewHeaderToScrollTopAcrossLayout({
								handle: codeViewHandle,
								itemId,
								isCurrent: (): boolean =>
									codeViewHandleRef.current === codeViewHandle &&
									scrollToTopTargetItemIdRef.current === itemId,
							});
						}
						completedSelectionScrollKeyRef.current = selectionScrollKey;
						lastSelectionScrollKeyRef.current = selectionScrollKey;
					}
					setMaterializationDiagnostic(
						materializationDiagnosticForCodeViewItem({
							item: nextMaterializedItem,
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
		});
	}, [
		collapsedItemIds,
		codeViewMountVersion,
		loadingMaterializationItemIds,
		materializationResourceEntries,
		props.projection,
		props.reviewPackage,
		props.selectedItemId,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.workerPoolEnabled,
		scheduleCodeViewRecoveryRender,
		viewerKey,
	]);

	return (
		<section
			aria-label="Review content"
			className="bridge-code-view-panel relative h-full min-h-0 bg-[var(--bridge-canvas-bg)]"
			data-code-view-item-count={initialItems.length}
			data-code-view-rendered-content-resource-count={materializationResourceEntries.length}
			data-code-view-visible-loading-item-count={props.visibleLoadingItemCount ?? 0}
			data-code-view-visible-ready-item-count={props.visibleReadyItemCount ?? 0}
			data-selected-content-cache-key-count={selectedContentSummary.cacheKeyCount}
			data-selected-content-character-count={selectedContentSummary.characterCount}
			data-selected-content-line-count={selectedContentSummary.lineCount}
			data-selected-content-role-count={selectedContentRoleCount}
			data-selected-content-state={selectedContentState}
			data-selected-materialized-addition-line-count={materializationDiagnostic.additionLineCount}
			data-selected-materialized-deletion-line-count={materializationDiagnostic.deletionLineCount}
			data-selected-materialized-file-line-count={materializationDiagnostic.fileLineCount}
			data-selected-materialized-item-type={materializationDiagnostic.itemType}
			data-selected-materialized-item-version={materializationDiagnostic.itemVersion}
			data-selected-materialized-update-result={materializationDiagnostic.updateResult}
			data-selected-display-path={selectedDisplayPath ?? undefined}
			data-selected-item-id={props.selectedItemId ?? undefined}
			data-testid="bridge-code-view-panel"
		>
			<BridgePierreWorkerPoolProvider
				{...(props.workerPoolEnabled === undefined ? {} : { enabled: props.workerPoolEnabled })}
				{...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory })}
			>
				<CodeView
					className={cn(
						'bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 min-w-0',
						'flex-1 overflow-y-auto overflow-x-hidden overscroll-contain',
						'[overflow-anchor:none] [will-change:scroll-position]',
						'[&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]',
						'[&_diffs-container]:shadow-[0_-1px_0_var(--bridge-code-view-file-separator),0_1px_0_var(--bridge-code-view-file-separator)]',
					)}
					key={viewerKey}
					ref={setCodeViewHandle}
					initialItems={initialItems}
					options={bridgeCodeViewOptions}
					renderHeaderMetadata={headerRenderers.renderHeaderMetadata}
					renderHeaderPrefix={headerRenderers.renderHeaderPrefix}
					onScroll={handleCodeViewScroll}
					style={{ height: '100%' }}
				/>
			</BridgePierreWorkerPoolProvider>
		</section>
	);
}

function nextCodeViewItemForCollapse(props: {
	readonly collapsed: boolean;
	readonly currentItem: BridgeCodeViewItem;
	readonly itemDescriptor: BridgeReviewItemDescriptor;
}): BridgeCodeViewItem {
	if (!props.collapsed && props.currentItem.bridgeMetadata.contentState === 'placeholder') {
		return {
			...materializeBridgeCodeViewLoadingItem(props.itemDescriptor),
			collapsed: false,
		};
	}
	return {
		...props.currentItem,
		collapsed: props.collapsed,
		version: (props.currentItem.version ?? 0) + 1,
	};
}

function captureCodeViewHeaderAnchor(props: {
	readonly handle: CodeViewHandle<undefined>;
	readonly itemId: string;
}): BridgeCodeViewHeaderAnchor | null {
	const instance = props.handle.getInstance();
	const containerElement =
		typeof instance?.getContainerElement === 'function' ? instance.getContainerElement() : null;
	if (!(containerElement instanceof HTMLElement)) {
		return null;
	}
	const scrollOwner = containerElement.closest('.bridge-code-view-scroll-owner');
	if (!(scrollOwner instanceof HTMLElement)) {
		return null;
	}
	const anchorElement = findCodeViewHeaderAnchorElement({
		containerElement: scrollOwner,
		itemId: props.itemId,
	});
	if (anchorElement === null) {
		return null;
	}
	return {
		containerElement,
		itemId: props.itemId,
		offsetFromScrollOwnerTop:
			anchorElement.getBoundingClientRect().top - scrollOwner.getBoundingClientRect().top,
		scrollOwner,
	};
}

function settleCodeViewScrollAtCurrentPosition(handle: CodeViewHandle<undefined>): void {
	const instance = handle.getInstance();
	const containerElement =
		typeof instance?.getContainerElement === 'function' ? instance.getContainerElement() : null;
	if (!(containerElement instanceof HTMLElement)) {
		return;
	}
	const scrollOwner = containerElement.closest('.bridge-code-view-scroll-owner');
	if (!(scrollOwner instanceof HTMLElement)) {
		return;
	}
	const targetScrollTop = scrollOwner.scrollTop;
	handle.scrollTo({
		type: 'position',
		position: targetScrollTop,
		behavior: 'instant',
	});
	instance?.render(true);
	const firstSettledDelta = targetScrollTop - scrollOwner.scrollTop;
	if (Math.abs(firstSettledDelta) < 1) {
		return;
	}
	handle.scrollTo({
		type: 'position',
		position: targetScrollTop + firstSettledDelta,
		behavior: 'instant',
	});
	instance?.render(true);
	if (Math.abs(scrollOwner.scrollTop - targetScrollTop) >= 1) {
		scrollOwner.scrollTop = targetScrollTop;
	}
}

function restoreCodeViewHeaderAnchor(anchor: BridgeCodeViewHeaderAnchor | null): void {
	if (anchor === null || !anchor.scrollOwner.isConnected || !anchor.containerElement.isConnected) {
		return;
	}
	const anchorElement = findCodeViewHeaderAnchorElement({
		containerElement: anchor.scrollOwner,
		itemId: anchor.itemId,
	});
	if (anchorElement === null) {
		return;
	}
	const currentOffset =
		anchorElement.getBoundingClientRect().top - anchor.scrollOwner.getBoundingClientRect().top;
	const offsetDelta = currentOffset - anchor.offsetFromScrollOwnerTop;
	if (Math.abs(offsetDelta) < 1) {
		return;
	}
	anchor.scrollOwner.scrollTop += offsetDelta;
}

interface ScrollCodeViewHeaderToScrollTopAcrossLayoutProps {
	readonly frameBudget?: number;
	readonly handle: CodeViewHandle<undefined>;
	readonly isCurrent: () => boolean;
	readonly itemId: string;
}

function scrollCodeViewHeaderToScrollTopAcrossLayout(
	props: ScrollCodeViewHeaderToScrollTopAcrossLayoutProps,
): void {
	if (!props.isCurrent()) {
		return;
	}
	scrollCodeViewHeaderToScrollTop({
		handle: props.handle,
		itemId: props.itemId,
	});
	const frameBudget = props.frameBudget ?? codeViewHeaderAnchorRestoreFrameBudget;
	if (frameBudget <= 0) {
		return;
	}
	requestAnimationFrame((): void => {
		scrollCodeViewHeaderToScrollTopAcrossLayout({
			...props,
			frameBudget: frameBudget - 1,
		});
	});
}

function scrollCodeViewHeaderToScrollTop(props: {
	readonly handle: CodeViewHandle<undefined>;
	readonly itemId: string;
}): void {
	const instance = props.handle.getInstance();
	const containerElement =
		typeof instance?.getContainerElement === 'function' ? instance.getContainerElement() : null;
	if (!(containerElement instanceof HTMLElement)) {
		return;
	}
	const scrollOwner = containerElement.closest('.bridge-code-view-scroll-owner');
	if (!(scrollOwner instanceof HTMLElement)) {
		return;
	}
	const anchorElement = findCodeViewHeaderAnchorElement({
		containerElement: scrollOwner,
		itemId: props.itemId,
	});
	if (anchorElement === null) {
		return;
	}
	const offsetFromScrollOwnerTop =
		anchorElement.getBoundingClientRect().top - scrollOwner.getBoundingClientRect().top;
	if (Math.abs(offsetFromScrollOwnerTop) < 1) {
		return;
	}
	scrollOwner.scrollTop += offsetFromScrollOwnerTop;
}

interface RestoreCodeViewHeaderAnchorAcrossLayoutProps {
	readonly anchor: BridgeCodeViewHeaderAnchor | null;
	readonly frameBudget?: number;
	readonly isCurrent: () => boolean;
}

function restoreCodeViewHeaderAnchorAcrossLayout(
	props: RestoreCodeViewHeaderAnchorAcrossLayoutProps,
): void {
	if (!props.isCurrent()) {
		return;
	}
	restoreCodeViewHeaderAnchor(props.anchor);
	const frameBudget = props.frameBudget ?? codeViewHeaderAnchorRestoreFrameBudget;
	if (frameBudget <= 0 || props.anchor === null) {
		return;
	}
	requestAnimationFrame((): void => {
		restoreCodeViewHeaderAnchorAcrossLayout({
			anchor: props.anchor,
			frameBudget: frameBudget - 1,
			isCurrent: props.isCurrent,
		});
	});
}

function findCodeViewHeaderAnchorElement(props: {
	readonly containerElement: HTMLElement;
	readonly itemId: string;
}): HTMLElement | null {
	const searchRoots: ParentNode[] = [props.containerElement];
	if (props.containerElement.shadowRoot !== null) {
		searchRoots.push(props.containerElement.shadowRoot);
	}
	for (const diffsContainer of props.containerElement.querySelectorAll<HTMLElement>(
		'diffs-container',
	)) {
		if (diffsContainer.shadowRoot !== null) {
			searchRoots.push(diffsContainer.shadowRoot);
		}
	}
	const localAnchor = findCodeViewHeaderAnchorElementInRoots({
		itemId: props.itemId,
		searchRoots,
	});
	if (localAnchor !== null) {
		return localAnchor;
	}
	const globalSearchRoots: ParentNode[] = [document];
	for (const diffsContainer of document.querySelectorAll<HTMLElement>('diffs-container')) {
		if (diffsContainer.shadowRoot !== null) {
			globalSearchRoots.push(diffsContainer.shadowRoot);
		}
	}
	return findCodeViewHeaderAnchorElementInRoots({
		itemId: props.itemId,
		searchRoots: globalSearchRoots,
	});
}

function findCodeViewHeaderAnchorElementInRoots(props: {
	readonly itemId: string;
	readonly searchRoots: readonly ParentNode[];
}): HTMLElement | null {
	for (const searchRoot of props.searchRoots) {
		for (const candidate of searchRoot.querySelectorAll<HTMLElement>(
			'[data-bridge-code-view-item-id]',
		)) {
			if (candidate.dataset['bridgeCodeViewItemId'] === props.itemId) {
				return candidate.closest<HTMLElement>('[data-diffs-header]') ?? candidate;
			}
		}
	}
	return null;
}

function selectedContentStateForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
	readonly selectedItemId: string | null;
}): 'none' | 'pending' | 'ready' {
	if (props.selectedItemId === null) {
		return 'none';
	}
	return props.selectedContentResources === null || props.selectedContentResources === undefined
		? 'pending'
		: 'ready';
}

function hasRenderedItemsSource(value: unknown): value is BridgeCodeViewRenderedItemsSource {
	return (
		typeof value === 'object' &&
		value !== null &&
		'getRenderedItems' in value &&
		typeof value.getRenderedItems === 'function'
	);
}

function uniqueRenderedItemIds(
	renderedItems: readonly BridgeCodeViewRenderedItemSnapshot[],
): readonly string[] {
	return uniqueItemIds(renderedItems.map((renderedItem): string => renderedItem.id));
}

function uniqueItemIds(candidateItemIds: readonly string[]): readonly string[] {
	const itemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const itemId of candidateItemIds) {
		if (seenItemIds.has(itemId)) {
			continue;
		}
		seenItemIds.add(itemId);
		itemIds.push(itemId);
	}
	return itemIds;
}

interface SelectedContentSummary {
	readonly cacheKeyCount: number;
	readonly characterCount: number;
	readonly lineCount: number;
}

function selectedContentSummaryForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
}): SelectedContentSummary {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return {
			cacheKeyCount: 0,
			characterCount: 0,
			lineCount: 0,
		};
	}

	const resources = Object.values(props.selectedContentResources).filter(
		(resource): resource is NonNullable<typeof resource> => resource !== undefined,
	);
	return {
		cacheKeyCount: new Set(resources.map((resource): string => resource.handle.cacheKey)).size,
		characterCount: resources.reduce(
			(totalCharacters, resource): number => totalCharacters + resource.text.length,
			0,
		),
		lineCount: resources.reduce(
			(totalLines, resource): number => totalLines + lineCountForContentResourceText(resource.text),
			0,
		),
	};
}

function lineCountForContentResourceText(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return text.split('\n').length;
}

function emptyMaterializationDiagnostic(): BridgeCodeViewMaterializationDiagnostic {
	return {
		updateResult: 'not-run',
		itemType: 'none',
		itemVersion: 0,
		additionLineCount: 0,
		deletionLineCount: 0,
		fileLineCount: 0,
	};
}

function materializationDiagnosticForCodeViewItem(props: {
	readonly item: BridgeCodeViewItem;
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult;
}): BridgeCodeViewMaterializationDiagnostic {
	if (props.item.type === 'diff') {
		return {
			updateResult: props.updateResult,
			itemType: props.item.type,
			itemVersion: props.item.version ?? 0,
			additionLineCount: props.item.fileDiff.additionLines.length,
			deletionLineCount: props.item.fileDiff.deletionLines.length,
			fileLineCount: 0,
		};
	}
	return {
		updateResult: props.updateResult,
		itemType: props.item.type,
		itemVersion: props.item.version ?? 0,
		additionLineCount: 0,
		deletionLineCount: 0,
		fileLineCount: lineCountForContentResourceText(props.item.file.contents),
	};
}

interface BridgeCodeViewHeaderRenderers {
	readonly renderHeaderMetadata: (item: CodeViewItem) => ReactNode;
	readonly renderHeaderPrefix: (item: CodeViewItem) => ReactNode;
}

interface CreateBridgeCodeViewHeaderRenderersProps {
	readonly collapsedItemIds: ReadonlySet<string>;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
	readonly onToggleItemCollapse: (itemId: string) => void;
	readonly reviewPackage: BridgeReviewPackage;
}

function createBridgeCodeViewHeaderRenderers(
	props: CreateBridgeCodeViewHeaderRenderersProps,
): BridgeCodeViewHeaderRenderers {
	return {
		renderHeaderPrefix: (item: CodeViewItem): ReactNode =>
			renderBridgeCodeViewHeaderPrefix({
				collapsedItemIds: props.collapsedItemIds,
				item,
				onHeaderVisibilityChange: props.onHeaderVisibilityChange,
				onToggleItemCollapse: props.onToggleItemCollapse,
				reviewPackage: props.reviewPackage,
			}),
		renderHeaderMetadata: (item: CodeViewItem): ReactNode =>
			renderBridgeCodeViewHeaderMetadata({ item, reviewPackage: props.reviewPackage }),
	};
}

interface RenderBridgeCodeViewHeaderProps {
	readonly collapsedItemIds?: ReadonlySet<string>;
	readonly item: CodeViewItem;
	readonly onHeaderVisibilityChange?: (itemId: string, isVisible: boolean) => void;
	readonly onToggleItemCollapse?: (itemId: string) => void;
	readonly reviewPackage: BridgeReviewPackage;
}

function renderBridgeCodeViewHeaderPrefix(props: RenderBridgeCodeViewHeaderProps): ReactNode {
	const descriptor = bridgeReviewItemForCodeViewItem(props);
	if (descriptor === null) {
		return null;
	}

	if (!isBridgeCodeViewItem(props.item)) {
		return null;
	}
	const itemId = props.item.bridgeMetadata.itemId;
	const collapsed = props.collapsedItemIds?.has(itemId) === true || props.item.collapsed === true;

	return (
		<span className="ml-[-2px] inline-flex items-center">
			{props.onHeaderVisibilityChange === undefined ? null : (
				<BridgeCodeViewVisibleHeaderReporter
					itemId={itemId}
					onHeaderVisibilityChange={props.onHeaderVisibilityChange}
				/>
			)}
			<button
				aria-expanded={!collapsed}
				aria-label={collapsed ? 'Expand file' : 'Collapse file'}
				className="inline-flex size-6 cursor-pointer select-none items-center justify-center rounded-md border border-transparent text-[11px] text-[var(--bridge-text-secondary)] hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-surface-raised-bg)] hover:text-[var(--bridge-text-primary)] focus-visible:border-[var(--bridge-accent)] focus-visible:outline-none"
				data-bridge-code-view-item-id={itemId}
				data-testid="bridge-code-view-header-collapse-button"
				onClick={(event): void => {
					event.preventDefault();
					event.stopPropagation();
					props.onToggleItemCollapse?.(itemId);
				}}
				type="button"
			>
				{collapsed ? (
					<ChevronRightIcon aria-hidden="true" className="size-3.5" />
				) : (
					<ChevronDownIcon aria-hidden="true" className="size-3.5" />
				)}
			</button>
		</span>
	);
}

function BridgeCodeViewVisibleHeaderReporter(props: {
	readonly itemId: string;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
}): null {
	const { itemId, onHeaderVisibilityChange } = props;
	useLayoutEffect((): (() => void) => {
		onHeaderVisibilityChange(itemId, true);
		return (): void => {
			onHeaderVisibilityChange(itemId, false);
		};
	}, [itemId, onHeaderVisibilityChange]);
	return null;
}

function renderBridgeCodeViewHeaderMetadata(props: RenderBridgeCodeViewHeaderProps): ReactNode {
	const descriptor = bridgeReviewItemForCodeViewItem(props);
	if (descriptor === null || !isBridgeCodeViewItem(props.item)) {
		return null;
	}

	return (
		<span
			className="ml-auto inline-flex min-w-0 items-center gap-2 text-[11px] text-[var(--bridge-text-muted)]"
			data-testid="bridge-code-view-header-metadata"
		>
			<span className="shrink-0 text-[var(--bridge-deleted)]">{`-${descriptor.deletions}`}</span>
			<span className="shrink-0 text-[var(--bridge-added)]">{`+${descriptor.additions}`}</span>
		</span>
	);
}

function bridgeReviewItemForCodeViewItem(
	props: RenderBridgeCodeViewHeaderProps,
): BridgeReviewPackage['itemsById'][string] | null {
	if (!isBridgeCodeViewItem(props.item)) {
		return null;
	}
	return props.reviewPackage.itemsById[props.item.bridgeMetadata.itemId] ?? null;
}

function isBridgeCodeViewItem(item: CodeViewItem): item is BridgeCodeViewItem {
	return 'bridgeMetadata' in item;
}

interface ControllerForHandleProps {
	readonly handle: CodeViewHandle<undefined>;
	readonly controllerEntryRef: {
		current: BridgeCodeViewControllerEntry | null;
	};
}

function controllerForHandle(props: ControllerForHandleProps): BridgeCodeViewController {
	const currentEntry = props.controllerEntryRef.current;
	if (currentEntry !== null && currentEntry.handle === props.handle) {
		return currentEntry.controller;
	}

	const controller = new BridgeCodeViewController({
		model: modelForHandle(props.handle),
	});
	props.controllerEntryRef.current = {
		handle: props.handle,
		controller,
	};
	return controller;
}

function modelForHandle(handle: CodeViewHandle<undefined>): BridgeCodeViewModel {
	return {
		addItems: (items) => handle.addItems(items),
		getItem: (id) => handle.getItem(id),
		updateItem: (item) => handle.updateItem(item),
		updateItemId: (oldId, newId) => handle.updateItemId(oldId, newId),
		scrollTo: (target) => handle.scrollTo(target),
		setSelectedLines: (selection) => handle.setSelectedLines(selection),
		renderImmediately: () => handle.getInstance()?.render(true),
	};
}

function makeViewerKey(props: BridgeCodeViewPanelProps): string {
	return [
		props.reviewPackage.packageId,
		props.reviewPackage.reviewGeneration,
		props.reviewPackage.revision,
		props.projection.projectionId,
	].join(':');
}
