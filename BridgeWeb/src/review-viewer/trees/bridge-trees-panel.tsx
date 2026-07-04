import type { FileTreeSortComparator } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import {
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
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { BridgeTreesController, createBridgeTreesSource } from './bridge-trees-controller.js';

const preserveInputOrderSort: FileTreeSortComparator = () => 0;
const bridgeReviewTreeInitialVisibleRowCount = 24;
const bridgeReviewTreeOverscan = 10;

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

export interface BridgeReviewTreesPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly searchOpen: boolean;
	readonly searchText: string;
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
				reviewPackage: props.reviewPackage,
				reviewTreeRows: props.reviewTreeRows,
				projection: props.projection,
			}),
		[props.projection, props.reviewPackage, props.reviewTreeRows],
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
		const nextSearchText = value ?? '';
		if (searchTextRef.current === nextSearchText) {
			return;
		}
		onSearchTextChangeRef.current?.(nextSearchText);
	}, []);
	const { model } = useFileTree({
		paths: initialSourceRef.current.orderedPaths,
		preparedInput: initialSourceRef.current.preparedInput,
		initialExpandedPaths: initialSourceRef.current.initialExpandedPaths,
		gitStatus: initialSourceRef.current.gitStatusEntries,
		sort: preserveInputOrderSort,
		search: true,
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
	const controllerRef = useRef<BridgeTreesController | null>(null);
	controllerRef.current ??= new BridgeTreesController({ model });

	useEffect((): void => {
		const updatePlan = controllerRef.current?.applySource(source);
		if (props.searchOpen && props.searchText.length > 0) {
			const modelSearchText =
				controllerRef.current?.modelSearchTextForFirstSearchMatch(props.searchText) ??
				props.searchText;
			const revealActiveSearchMatch = (): void => {
				model.openSearch(modelSearchText);
				model.setSearch(modelSearchText);
				model.focusNextSearchMatch();
				controllerRef.current?.revealFirstSearchMatch(props.searchText);
			};
			revealActiveSearchMatch();
			queueMicrotask(revealActiveSearchMatch);
			requestAnimationFrame(revealActiveSearchMatch);
			setTimeout(revealActiveSearchMatch, 0);
		}
		if (updatePlan?.kind === 'appendOnly') {
			const controller = controllerRef.current;
			const pathsToReveal = updatePlan.addedPaths;
			const revealAppendedPathAncestors = (): void => {
				for (const path of pathsToReveal) {
					controller?.revealTreePathAncestors(path);
				}
			};
			revealAppendedPathAncestors();
			queueMicrotask(revealAppendedPathAncestors);
			requestAnimationFrame(revealAppendedPathAncestors);
			setTimeout(revealAppendedPathAncestors, 0);
		}
	}, [model, props.searchOpen, props.searchText, source]);

	useEffect((): void => {
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
	}, [model, props.searchOpen, props.searchText]);

	useEffect((): void => {
		if (props.selectedItemId === null) {
			return;
		}
		const path = props.projection.primaryDisplayPathByItemId[props.selectedItemId];
		if (path === undefined) {
			return;
		}
		controllerRef.current?.selectTreePath(path);
		model.getItem(path)?.select();
	}, [model, props.projection, props.selectedItemId]);

	const publishVisibleItemIds = useCallback((): void => {
		if (onVisibleItemIdsChange === undefined) {
			return;
		}
		onVisibleItemIdsChange(
			visibleReviewTreeItemIds({
				model,
				primaryItemIdByTreePath: sourceRef.current.primaryItemIdByTreePath,
			}),
		);
	}, [model, onVisibleItemIdsChange]);
	const selectClickedFileRow = useCallback((event: Event): void => {
		applyReviewTreeSelectionFromEvent({
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
	}, []);

	useEffect((): (() => void) => {
		let scrollElement: BridgePierreTreeScrollOwner | null = null;
		let animationFrameId: number | null = null;
		const scheduleVisibleItemIds = (): void => {
			if (animationFrameId !== null) {
				return;
			}
			animationFrameId = requestAnimationFrame((): void => {
				animationFrameId = null;
				publishVisibleItemIds();
			});
		};
		const setupFrameId = requestAnimationFrame((): void => {
			scrollElement = pierreTreeScrollOwnerForModel(model);
			scrollElement?.addEventListener('scroll', scheduleVisibleItemIds, { passive: true });
			publishVisibleItemIds();
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
					}).length,
					fallbackTraceContext: telemetryTraceContext,
				});
			}
		});
		const unsubscribeModel = model.subscribe(scheduleVisibleItemIds);
		return (): void => {
			cancelAnimationFrame(setupFrameId);
			if (animationFrameId !== null) {
				cancelAnimationFrame(animationFrameId);
			}
			scrollElement?.removeEventListener('scroll', scheduleVisibleItemIds);
			unsubscribeModel();
		};
	}, [model, publishVisibleItemIds, telemetryRecorder, telemetryTraceContext]);

	return (
		<div
			aria-label="Review file tree"
			className="h-full min-h-0 overflow-hidden bg-[var(--bridge-surface-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-trees-panel"
			onClickCapture={(event): void => selectClickedFileRow(event.nativeEvent)}
		>
			<FileTree model={model} style={bridgeViewerTreeStyle} />
		</div>
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
}): readonly string[] {
	return reviewTreeItemIdsForPierreVisibleFileRows({
		primaryItemIdByTreePath: props.primaryItemIdByTreePath,
		rowElements: visiblePierreFileRowElementsForModel(props.model),
	});
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
