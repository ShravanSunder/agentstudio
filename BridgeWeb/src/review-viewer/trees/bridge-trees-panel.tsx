import type { FileTreeSortComparator } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import {
	mountedPierreFileRowElementsForModel,
	pierreFilePathFromEventTarget,
	pierreFilePathFromTreeEvent,
	pierreTreeScrollOwnerForModel,
	visiblePierreFileRowElementsForModel,
	type BridgePierreFileRowElement,
	type BridgePierreTreeScrollOwner,
} from '../../app/bridge-pierre-tree-adapter.js';
import {
	bridgeViewerTreeStyle,
	bridgeViewerTreeUnsafeCSS,
} from '../../app/bridge-viewer-tree-theme.js';
import type { ReviewTreeRowMetadata } from '../../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerFirstInteractionReady } from '../../foundation/telemetry/bridge-viewer-first-interaction.js';
import {
	recordBridgeTreeClickToRowHighlightTelemetrySample,
	recordBridgeTreeHoverToRenderTelemetrySample,
	recordBridgeTreeVisibleIdsCaptureTelemetrySample,
} from '../../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { BridgeTreesController, createBridgeTreesSource } from './bridge-trees-controller.js';
import { createBridgeReviewTreeVisibleItemPublisher } from './bridge-trees-visible-item-publisher.js';

const preserveInputOrderSort: FileTreeSortComparator = () => 0;
const bridgeReviewTreeInitialVisibleRowCount = 24;
const bridgeReviewTreeOverscan = 10;
const bridgeReviewTreeScrollIdleMilliseconds = 120;

type BridgeReviewTreeClickProbeSelectionResult = 'accepted' | 'rejected' | 'no_row';

interface BridgeReviewTreeClickProbe {
	captureHandlerInvokedCount: number;
	captureHandlerResolvedRowItemId: string;
	selectionCommandIssuedCount: number;
	selectionCommandAcceptedCount: number;
	selectionCommandLastResult: BridgeReviewTreeClickProbeSelectionResult;
}

type BridgeReviewTreeClickProbeRecord = Partial<BridgeReviewTreeClickProbe> &
	Record<string, unknown>;

declare global {
	interface Window {
		__bridgeReviewTreeClickProbe?: BridgeReviewTreeClickProbeRecord;
	}
}

export { createBridgeReviewTreeVisibleItemPublisher } from './bridge-trees-visible-item-publisher.js';

export interface BridgeReviewTreeSelectionRevealRequest {
	readonly itemId: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
}

export interface BridgeReviewTreesPanelProps {
	readonly isActive: boolean;
	readonly presentationPositionKey: string;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly searchOpen: boolean;
	readonly searchText: string;
	readonly selectionRevealRequest?: BridgeReviewTreeSelectionRevealRequest | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly onSearchTextChange?: (searchText: string) => void;
	readonly onVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryTraceContext?: BridgeTraceContext | null;
}

export function BridgeReviewTreesPanel(props: BridgeReviewTreesPanelProps): ReactElement {
	const source = useMemo(
		() =>
			createBridgeTreesSource({
				presentationPositionKey: props.presentationPositionKey,
				reviewPackage: props.reviewPackage,
				reviewTreeRows: props.reviewTreeRows,
				projection: props.projection,
			}),
		[props.presentationPositionKey, props.projection, props.reviewPackage, props.reviewTreeRows],
	);
	const sourceRef = useRef(source);
	sourceRef.current = source;
	const initialSourceRef = useRef(source);
	const onSelectItemRef = useRef(props.onSelectItem);
	onSelectItemRef.current = props.onSelectItem;
	const onSearchTextChangeRef = useRef(props.onSearchTextChange);
	onSearchTextChangeRef.current = props.onSearchTextChange;
	const onVisibleItemIdsChange = props.onVisibleItemIdsChange;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const isSyncingClickedSelectionRef = useRef(false);
	const isSyncingControlledSearchRef = useRef(false);
	const isActiveRef = useRef(props.isActive);
	isActiveRef.current = props.isActive;
	const explicitSearchCloseIntentRef = useRef(false);
	const modelRef = useRef<ReturnType<typeof useFileTree>['model'] | null>(null);
	const controllerRef = useRef<BridgeTreesController | null>(null);
	const firstInteractionMountStartedAtRef = useRef(performance.now());
	const hasRecordedFirstInteractionRef = useRef(false);
	const searchTextRef = useRef(props.searchText);
	searchTextRef.current = props.searchText;
	const onSelectionChange = useCallback((selectedPaths: readonly string[]): void => {
		if (isSyncingClickedSelectionRef.current) {
			return;
		}
		if (selectedPaths.length !== 1) {
			return;
		}
		const [path] = selectedPaths;
		if (path === undefined) {
			return;
		}
		const itemId = sourceRef.current.primaryItemIdByTreePath[path];
		if (itemId !== undefined) {
			onSelectItemRef.current(itemId);
		}
	}, []);
	const onSearchChange = useCallback((value: string | null): void => {
		if (isSyncingControlledSearchRef.current) {
			return;
		}
		if (value === null && !explicitSearchCloseIntentRef.current) {
			queueMicrotask((): void => {
				if (!isActiveRef.current || searchTextRef.current.length === 0) {
					return;
				}
				const searchText = searchTextRef.current;
				const modelSearchText =
					controllerRef.current?.modelSearchTextForFirstSearchMatch(searchText) ?? searchText;
				isSyncingControlledSearchRef.current = true;
				try {
					modelRef.current?.openSearch(modelSearchText);
				} finally {
					isSyncingControlledSearchRef.current = false;
				}
			});
			return;
		}
		const nextSearchText = value ?? '';
		if (searchTextRef.current === nextSearchText) {
			return;
		}
		onSearchTextChangeRef.current?.(nextSearchText);
	}, []);
	const { model } = useFileTree({
		paths: initialSourceRef.current.orderedPaths,
		preparedInput: initialSourceRef.current.preparedInput,
		initialExpansion: 'open',
		initialExpandedPaths: initialSourceRef.current.initialExpandedPaths,
		gitStatus: initialSourceRef.current.gitStatusEntries,
		sort: preserveInputOrderSort,
		search: true,
		searchBlurBehavior: 'retain',
		fileTreeSearchMode: 'expand-matches',
		flattenEmptyDirectories: true,
		density: 'compact',
		onSearchChange,
		initialVisibleRowCount: bridgeReviewTreeInitialVisibleRowCount,
		overscan: bridgeReviewTreeOverscan,
		onSelectionChange,
		stickyFolders: true,
		unsafeCSS: bridgeViewerTreeUnsafeCSS,
	});
	modelRef.current = model;
	const scrollActiveRef = useRef(false);
	const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	controllerRef.current ??= new BridgeTreesController({
		isProgrammaticScrollActive: (): boolean => scrollActiveRef.current,
		model,
		telemetryRecorder,
		telemetryTraceContext,
	});
	controllerRef.current.setTelemetryContext({
		telemetryRecorder,
		telemetryTraceContext,
	});
	const hoverMeasurementRef = useRef<{
		readonly path: string | null;
		readonly startedAt: number;
	} | null>(null);

	useEffect((): void => {
		isSyncingControlledSearchRef.current = true;
		try {
			controllerRef.current?.applySource(source);
		} finally {
			isSyncingControlledSearchRef.current = false;
		}
		if (props.isActive && props.searchOpen && props.searchText.length > 0) {
			const modelSearchText =
				controllerRef.current?.modelSearchTextForFirstSearchMatch(props.searchText) ??
				props.searchText;
			const revealActiveSearchMatch = (): void => {
				isSyncingControlledSearchRef.current = true;
				try {
					model.openSearch(modelSearchText);
					model.setSearch(modelSearchText);
					model.focusNextSearchMatch();
					controllerRef.current?.revealFirstSearchMatch(props.searchText);
				} finally {
					isSyncingControlledSearchRef.current = false;
				}
			};
			revealActiveSearchMatch();
			queueMicrotask(revealActiveSearchMatch);
			requestAnimationFrame(revealActiveSearchMatch);
			setTimeout(revealActiveSearchMatch, 0);
		}
	}, [model, props.isActive, props.searchOpen, props.searchText, source]);

	useEffect((): void => {
		if (!props.isActive) {
			return;
		}
		isSyncingControlledSearchRef.current = true;
		try {
			if (!props.searchOpen) {
				model.setSearch(null);
				model.closeSearch();
				return;
			}
			model.openSearch(props.searchText);
			if (props.searchText.length > 0) {
				const modelSearchText =
					controllerRef.current?.modelSearchTextForFirstSearchMatch(props.searchText) ??
					props.searchText;
				model.setSearch(modelSearchText);
				model.focusNextSearchMatch();
				controllerRef.current?.revealFirstSearchMatch(props.searchText);
			}
		} finally {
			isSyncingControlledSearchRef.current = false;
		}
	}, [model, props.isActive, props.searchOpen, props.searchText]);

	const markExplicitSearchCloseIntent = useCallback((event: Event): void => {
		if (!isPierreSearchCloseKey(event)) {
			return;
		}
		explicitSearchCloseIntentRef.current = true;
		queueMicrotask((): void => {
			explicitSearchCloseIntentRef.current = false;
		});
	}, []);

	useEffect((): void => {
		const selectionRevealRequest = props.selectionRevealRequest;
		if (selectionRevealRequest === null || selectionRevealRequest === undefined) {
			return;
		}
		if (selectionRevealRequest.reviewGeneration !== props.reviewPackage.reviewGeneration) {
			return;
		}
		if (selectionRevealRequest.packageId !== props.reviewPackage.packageId) {
			return;
		}
		const path = props.projection.primaryDisplayPathByItemId[selectionRevealRequest.itemId];
		if (path === undefined) {
			return;
		}
		controllerRef.current?.selectTreePath(path);
		model.getItem(path)?.select();
	}, [
		model,
		props.projection,
		props.reviewPackage.packageId,
		props.reviewPackage.reviewGeneration,
		props.selectionRevealRequest,
	]);

	const selectClickedFileRow = useCallback(
		(event: Event): void => {
			const startedAt = performance.now();
			const selection = reviewTreeSelectionForEventTarget({
				primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
				target: event,
			});
			const didSelect = applyReviewTreeSelectionFromEvent({
				event,
				onSelectItem: (itemId: string): void => {
					onSelectItemRef.current(itemId);
				},
				primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
				selectClickedTreePath: (path: string): string | null => {
					isSyncingClickedSelectionRef.current = true;
					try {
						return controllerRef.current?.selectClickedTreePath(path) ?? null;
					} finally {
						isSyncingClickedSelectionRef.current = false;
					}
				},
			});
			if (telemetryRecorder === undefined) {
				return;
			}
			requestAnimationFrame((): void => {
				const rowMounted =
					selection === null ? false : reviewTreeRowIsMounted({ model, path: selection.path });
				recordBridgeTreeClickToRowHighlightTelemetrySample({
					alreadySelected: selection?.itemId === props.selectedItemId,
					durationMilliseconds: performance.now() - startedAt,
					result: didSelect && rowMounted ? 'success' : 'failed',
					scrollActive: scrollActiveRef.current,
					source: clickSourceForEvent(event),
					telemetryRecorder,
					traceContext: telemetryTraceContext,
					viewer: 'review',
					visibleItemCount: visibleReviewTreeItemIds({
						model,
						primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
					}).length,
				});
			});
		},
		[model, props.selectedItemId, telemetryRecorder, telemetryTraceContext],
	);

	const measureHoverToRender = useCallback(
		(event: Event): void => {
			if (telemetryRecorder === undefined || hoverMeasurementRef.current !== null) {
				return;
			}
			const selection = reviewTreeSelectionForEventTarget({
				primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
				target: event,
			});
			hoverMeasurementRef.current = {
				path: selection?.path ?? null,
				startedAt: performance.now(),
			};
			requestAnimationFrame((): void => {
				const pendingMeasurement = hoverMeasurementRef.current;
				hoverMeasurementRef.current = null;
				if (pendingMeasurement === null) {
					return;
				}
				const rowMounted =
					pendingMeasurement.path === null
						? false
						: reviewTreeRowIsMounted({ model, path: pendingMeasurement.path });
				recordBridgeTreeHoverToRenderTelemetrySample({
					durationMilliseconds: performance.now() - pendingMeasurement.startedAt,
					result: rowMounted ? 'success' : 'failed',
					rowMounted,
					telemetryRecorder,
					traceContext: telemetryTraceContext,
					viewer: 'review',
					visibleItemCount: visibleReviewTreeItemIds({
						model,
						primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
					}).length,
				});
			});
		},
		[model, telemetryRecorder, telemetryTraceContext],
	);

	useEffect((): (() => void) => {
		let scrollElement: BridgePierreTreeScrollOwner | null = null;
		const visibleItemPublisher = createBridgeReviewTreeVisibleItemPublisher({
			captureVisibleItemIds: (): readonly string[] =>
				visibleReviewTreeItemIds({
					model,
					primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
					telemetryRecorder,
					telemetryTraceContext,
				}),
			onVisibleItemIdsChange: (itemIds): void => {
				onVisibleItemIdsChange?.(itemIds);
			},
			telemetryRecorder,
			telemetryTraceContext,
			viewer: 'review',
		});
		const scheduleVisibleItemIds = (): void => {
			visibleItemPublisher.schedule();
		};
		const markUserScrollActive = (): void => {
			scrollActiveRef.current = true;
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
			}
			scrollIdleTimeoutRef.current = setTimeout((): void => {
				scrollIdleTimeoutRef.current = null;
				scrollActiveRef.current = false;
			}, bridgeReviewTreeScrollIdleMilliseconds);
		};
		const handleTreeScroll = (): void => {
			markUserScrollActive();
			visibleItemPublisher.schedule();
		};
		const setupFrameId = requestAnimationFrame((): void => {
			scrollElement = pierreTreeScrollOwnerForModel(model);
			scrollElement?.addEventListener('scroll', handleTreeScroll, { passive: true });
			visibleItemPublisher.publishNow();
			// Only anchor time-to-first-interaction once the tree actually has rows painted.
			if (!hasRecordedFirstInteractionRef.current && sourceRef.current.orderedPaths.length > 0) {
				hasRecordedFirstInteractionRef.current = true;
				recordBridgeViewerFirstInteractionReady({
					viewer: 'review',
					telemetryRecorder,
					mountStartedAtPerfNow: firstInteractionMountStartedAtRef.current,
					visibleItemCount: visibleReviewTreeItemIds({
						model,
						primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
						telemetryRecorder,
						telemetryTraceContext,
					}).length,
					fallbackTraceContext: telemetryTraceContext,
				});
			}
		});
		const unsubscribeModel = model.subscribe(scheduleVisibleItemIds);
		return (): void => {
			cancelAnimationFrame(setupFrameId);
			visibleItemPublisher.cancel();
			if (scrollIdleTimeoutRef.current !== null) {
				clearTimeout(scrollIdleTimeoutRef.current);
				scrollIdleTimeoutRef.current = null;
			}
			scrollActiveRef.current = false;
			scrollElement?.removeEventListener('scroll', handleTreeScroll);
			unsubscribeModel();
		};
	}, [model, onVisibleItemIdsChange, telemetryRecorder, telemetryTraceContext]);

	return (
		<div
			aria-label="Review file tree"
			className="h-full min-h-0 overflow-hidden bg-[var(--bridge-surface-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-trees-panel"
			onClickCapture={(event): void => selectClickedFileRow(event.nativeEvent)}
			onKeyDownCapture={(event): void => markExplicitSearchCloseIntent(event.nativeEvent)}
			onPointerOverCapture={(event): void => measureHoverToRender(event.nativeEvent)}
			onPointerMoveCapture={(event): void => measureHoverToRender(event.nativeEvent)}
		>
			<FileTree model={model} style={bridgeViewerTreeStyle} />
		</div>
	);
}

function isPierreSearchCloseKey(event: Event): boolean {
	if (!(event instanceof KeyboardEvent) || (event.key !== 'Enter' && event.key !== 'Escape')) {
		return false;
	}
	return event
		.composedPath()
		.some(
			(target): boolean =>
				target instanceof HTMLElement && target.hasAttribute('data-file-tree-search-input'),
		);
}

export function reviewTreeItemIdForEventTarget(props: {
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly target: EventTarget | null;
}): string | null {
	return (
		reviewTreeSelectionForEventTarget({
			primaryItemIdByTreePath: props.primaryItemIdByTreePath,
			target: props.target,
		})?.itemId ?? null
	);
}

export interface ReviewTreeSelection {
	readonly itemId: string;
	readonly path: string;
}

export function applyReviewTreeSelectionFromEvent(props: {
	readonly event: Event;
	readonly onSelectItem: (itemId: string) => void;
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly selectClickedTreePath: (path: string) => string | null;
}): boolean {
	const selection = reviewTreeSelectionForEventTarget({
		primaryItemIdByTreePath: props.primaryItemIdByTreePath,
		target: props.event,
	});
	if (selection === null) {
		recordBridgeReviewTreeClickProbeCapture({
			itemId: '',
			result: 'no_row',
		});
		return false;
	}
	recordBridgeReviewTreeClickProbeCapture({
		itemId: selection.itemId,
		result: null,
	});
	recordBridgeReviewTreeClickProbeSelectionCommandIssued();
	let selectedTreePathResult: string | null = null;
	try {
		selectedTreePathResult = props.selectClickedTreePath(selection.path);
	} catch (error) {
		recordBridgeReviewTreeClickProbeSelectionCommandResult('rejected');
		throw error;
	}
	recordBridgeReviewTreeClickProbeSelectionCommandResult(
		selectedTreePathResult === null ? 'rejected' : 'accepted',
	);
	queueMicrotask((): void => props.onSelectItem(selection.itemId));
	return true;
}

export function reviewTreeSelectionForEventTarget(props: {
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly target: Event | EventTarget | null;
}): ReviewTreeSelection | null {
	const path =
		props.target !== null && 'composedPath' in props.target
			? pierreFilePathFromTreeEvent(props.target)
			: pierreFilePathFromEventTarget(props.target);
	return reviewTreeSelectionForPath({
		path,
		primaryItemIdByTreePath: props.primaryItemIdByTreePath,
	});
}

export function reviewTreeItemIdForPath(props: {
	readonly path: string | null;
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
}): string | null {
	const path = props.path;
	if (path === null) {
		return null;
	}
	return props.primaryItemIdByTreePath[path] ?? null;
}

export function reviewTreeSelectionForPath(props: {
	readonly path: string | null;
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
}): ReviewTreeSelection | null {
	const path = props.path;
	if (path === null) {
		return null;
	}
	const itemId = props.primaryItemIdByTreePath[path];
	return itemId === undefined ? null : { itemId, path };
}

function visibleReviewTreeItemIds(props: {
	readonly model: ReturnType<typeof useFileTree>['model'];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
}): readonly string[] {
	const startedAt = performance.now();
	const rowElements = visiblePierreFileRowElementsForModel(props.model);
	const itemIds = reviewTreeItemIdsForPierreVisibleFileRows({
		primaryItemIdByTreePath: props.primaryItemIdByTreePath,
		rowElements,
	});
	if (props.telemetryRecorder !== undefined) {
		recordBridgeTreeVisibleIdsCaptureTelemetrySample({
			durationMilliseconds: performance.now() - startedAt,
			returnedDescriptorCount: 0,
			returnedItemCount: itemIds.length,
			rowCount: rowElements.length,
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.telemetryTraceContext ?? null,
			viewer: 'review',
		});
	}
	return itemIds;
}

function reviewTreeRowIsMounted(props: {
	readonly model: ReturnType<typeof useFileTree>['model'];
	readonly path: string;
}): boolean {
	return mountedPierreFileRowElementsForModel(props.model).some(
		(rowElement): boolean => rowElement.getAttribute('data-item-path') === props.path,
	);
}

function clickSourceForEvent(event: Event): 'keyboard' | 'mouse' | 'programmatic' {
	if (!(event instanceof MouseEvent)) {
		return 'programmatic';
	}
	return event.detail === 0 ? 'keyboard' : 'mouse';
}

function recordBridgeReviewTreeClickProbeCapture(props: {
	readonly itemId: string;
	readonly result: BridgeReviewTreeClickProbeSelectionResult | null;
}): void {
	const probe = bridgeReviewTreeClickProbe();
	if (probe === null) {
		return;
	}
	probe.captureHandlerInvokedCount = (probe.captureHandlerInvokedCount ?? 0) + 1;
	probe.captureHandlerResolvedRowItemId = props.itemId;
	if (props.result !== null) {
		probe.selectionCommandLastResult = props.result;
	}
}

function recordBridgeReviewTreeClickProbeSelectionCommandIssued(): void {
	const probe = bridgeReviewTreeClickProbe();
	if (probe === null) {
		return;
	}
	probe.selectionCommandIssuedCount = (probe.selectionCommandIssuedCount ?? 0) + 1;
}

function recordBridgeReviewTreeClickProbeSelectionCommandResult(
	result: BridgeReviewTreeClickProbeSelectionResult,
): void {
	const probe = bridgeReviewTreeClickProbe();
	if (probe === null) {
		return;
	}
	probe.selectionCommandLastResult = result;
	if (result === 'accepted') {
		probe.selectionCommandAcceptedCount = (probe.selectionCommandAcceptedCount ?? 0) + 1;
	}
}

function bridgeReviewTreeClickProbe(): BridgeReviewTreeClickProbeRecord | null {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	const probe = (probeWindow.__bridgeReviewTreeClickProbe ??= {
		captureHandlerInvokedCount: 0,
		captureHandlerResolvedRowItemId: '',
		selectionCommandIssuedCount: 0,
		selectionCommandAcceptedCount: 0,
		selectionCommandLastResult: 'no_row',
	});
	return probe;
}

export function reviewTreeItemIdsForPierreVisibleFileRows(props: {
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly rowElements: Iterable<BridgePierreFileRowElement>;
}): readonly string[] {
	const itemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const rowElement of props.rowElements) {
		const path = rowElement.getAttribute('data-item-path');
		const itemId = path === null ? undefined : props.primaryItemIdByTreePath[path];
		if (itemId === undefined || seenItemIds.has(itemId)) {
			continue;
		}
		seenItemIds.add(itemId);
		itemIds.push(itemId);
	}
	return itemIds;
}
