import type { CodeViewItem } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import { ChevronDownIcon, ChevronRightIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { useLayoutEffect } from 'react';

import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from '../../app/bridge-viewer-chrome.js';
import { cn } from '../../app/class-name.js';
import { Button } from '../../components/ui/button.js';
import {
	runBridgeFrameApplyPump,
	type BridgeFrameApplyUnitRank,
} from '../../core/rendering/bridge-frame-apply-pump.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import {
	recordBridgeCodeViewItemMaterializeTelemetry,
	recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetry,
} from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	BridgeCodeViewController,
	type ApplyBridgeCodeViewItemUpdateResult,
	type BridgeCodeViewModel,
} from './bridge-code-view-controller.js';
import {
	bridgeCodeViewMaterializationCacheKeysForItem,
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
	type BridgeCodeViewItemPresentation,
} from './bridge-code-view-materialization.js';
import type { BridgeCodeViewMetadataReconcileProps } from './bridge-code-view-metadata-apply.js';

export interface BridgeCodeViewControllerEntry {
	readonly handle: CodeViewHandle<undefined>;
	readonly controller: BridgeCodeViewController;
}

export interface BridgeCodeViewMaterializationDiagnostic {
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult | 'not-run';
	readonly itemType: BridgeCodeViewItem['type'] | 'none';
	readonly itemVersion: number;
	readonly modelContentState: BridgeCodeViewItem['bridgeMetadata']['contentState'] | 'none';
	readonly modelItemVersion: number;
	readonly additionLineCount: number;
	readonly deletionLineCount: number;
	readonly fileLineCount: number;
	readonly durationMilliseconds: number;
}

export interface RecordBridgeCodeViewItemMaterializeTelemetryForPanelProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentResources;
	readonly durationMilliseconds: number;
	readonly result: ApplyBridgeCodeViewItemUpdateResult;
	readonly selectedItemId: string | null;
}

export interface RecordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanelProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly codeViewItem: BridgeCodeViewItem;
	readonly durationMilliseconds: number;
	readonly result: ApplyBridgeCodeViewItemUpdateResult;
	readonly selectedItemId: string | null;
}

interface BridgeCodeViewRenderedItemSnapshot {
	readonly id: string;
}

export interface BridgeCodeViewRenderedItemsSource {
	readonly getRenderedItems: () => readonly BridgeCodeViewRenderedItemSnapshot[];
}

export interface BridgeCodeViewRenderedHeaderOffset {
	readonly offsetPixels: number;
	readonly stickyCompensationPixels: number;
}

export function nextCodeViewItemForCollapse(props: {
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

export function collapsedItemIdsWithItemState(props: {
	readonly collapsed: boolean;
	readonly currentIds: ReadonlySet<string>;
	readonly itemId: string;
}): ReadonlySet<string> {
	const nextIds = new Set(props.currentIds);
	if (props.collapsed) {
		nextIds.add(props.itemId);
	} else {
		nextIds.delete(props.itemId);
	}
	return nextIds;
}

export function shouldRequestForegroundDemandForItemExpansion(props: {
	readonly nextCollapsed: boolean;
	readonly previousCollapsed: boolean;
}): boolean {
	return props.previousCollapsed && !props.nextCollapsed;
}

export function createBridgeCodeViewInitialItemsForPanel(props: {
	readonly projection: BridgeReviewProjectionResult;
	readonly reviewPackage: BridgeReviewPackage;
}): readonly BridgeCodeViewItem[] {
	return createBridgeCodeViewInitialItems({
		reviewPackage: props.reviewPackage,
		projection: props.projection,
	});
}

export function bridgeCodeViewInitialItemsWithMetadataDeltaItems(props: {
	readonly initialItems: readonly BridgeCodeViewItem[];
	readonly metadataDeltaItems: readonly BridgeCodeViewItem[];
}): readonly BridgeCodeViewItem[] {
	if (props.metadataDeltaItems.length === 0) {
		return props.initialItems;
	}
	const deltaItemsByItemId = new Map<string, BridgeCodeViewItem>();
	for (const item of props.metadataDeltaItems) {
		if (item.bridgeMetadata.itemId === item.id) {
			deltaItemsByItemId.set(item.id, item);
		}
	}
	if (deltaItemsByItemId.size === 0) {
		return props.initialItems;
	}
	const replacedItemIds = new Set<string>();
	const nextItems = props.initialItems.map((item): BridgeCodeViewItem => {
		const deltaItem = deltaItemsByItemId.get(item.id);
		if (deltaItem === undefined) {
			return item;
		}
		replacedItemIds.add(item.id);
		return deltaItem;
	});
	const appendedItems = [...deltaItemsByItemId.values()].filter(
		(item): boolean => !replacedItemIds.has(item.id),
	);
	return appendedItems.length === 0 ? nextItems : [...nextItems, ...appendedItems];
}

export function bridgeCodeViewItemsWithMetadataItem(props: {
	readonly currentItems: readonly BridgeCodeViewItem[];
	readonly item: BridgeCodeViewItem;
}): readonly BridgeCodeViewItem[] {
	let replaced = false;
	const nextItems = props.currentItems.map((currentItem): BridgeCodeViewItem => {
		if (currentItem.id !== props.item.id) {
			return currentItem;
		}
		replaced = true;
		return props.item;
	});
	return replaced ? nextItems : [...nextItems, props.item];
}

export function bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems(props: {
	readonly initialItems: readonly BridgeCodeViewItem[];
	readonly selectedCodeViewItem: BridgeCodeViewItem | null | undefined;
	readonly selectedItemId: string | null;
	readonly visibleCodeViewItems?: readonly BridgeCodeViewItem[] | undefined;
}): readonly BridgeCodeViewItem[] {
	const workerPreparedItemsByItemId = new Map<string, BridgeCodeViewItem>();
	for (const visibleCodeViewItem of props.visibleCodeViewItems ?? []) {
		if (visibleCodeViewItem.bridgeMetadata.itemId === visibleCodeViewItem.id) {
			workerPreparedItemsByItemId.set(visibleCodeViewItem.id, visibleCodeViewItem);
		}
	}
	const selectedCodeViewItem = props.selectedCodeViewItem;
	if (
		props.selectedItemId !== null &&
		selectedCodeViewItem !== null &&
		selectedCodeViewItem !== undefined &&
		selectedCodeViewItem.bridgeMetadata.itemId === props.selectedItemId
	) {
		workerPreparedItemsByItemId.set(props.selectedItemId, selectedCodeViewItem);
	}
	if (workerPreparedItemsByItemId.size === 0) {
		return props.initialItems;
	}
	const replacedItemIds = new Set<string>();
	const nextItems = props.initialItems.map((item): BridgeCodeViewItem => {
		const workerPreparedItem = workerPreparedItemsByItemId.get(item.id);
		if (workerPreparedItem === undefined) {
			return item;
		}
		replacedItemIds.add(item.id);
		return workerPreparedItem;
	});
	const appendedItems = [...workerPreparedItemsByItemId.values()].filter(
		(item): boolean => !replacedItemIds.has(item.id),
	);
	return appendedItems.length === 0 ? nextItems : [...nextItems, ...appendedItems];
}

export function shouldSkipBridgeCodeViewItemMaterializationBeforeWork(props: {
	readonly collapsed: boolean;
	readonly contentWindowLineLimit?: number | undefined;
	readonly existingItem: BridgeCodeViewItem | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation: BridgeCodeViewItemPresentation | null;
	readonly resources: BridgeCodeViewContentResources;
}): boolean {
	if (
		props.existingItem === undefined ||
		!isMaterializedBridgeCodeViewContentState(props.existingItem.bridgeMetadata.contentState) ||
		(props.existingItem.collapsed === true) !== props.collapsed
	) {
		return false;
	}
	const existingCacheKey = props.existingItem.bridgeMetadata.cacheKey;
	const expectedCacheKeys = bridgeCodeViewMaterializationCacheKeysForItem({
		contentWindowLineLimit: props.contentWindowLineLimit,
		item: props.item,
		presentation: props.presentation,
		resources: props.resources,
	});
	return (
		expectedCacheKeys.some((cacheKey): boolean => cacheKey === existingCacheKey) ||
		bridgeCodeViewDiffMaterializationCacheKeyContainsCurrentIdentity({
			existingCacheKey,
			item: props.item,
			resources: props.resources,
		})
	);
}

export function runBridgeCodeViewMaterializationInChunks<TEntry>(props: {
	readonly entries: readonly TEntry[];
	readonly frameBudgetMilliseconds: number;
	readonly isStale: () => boolean;
	readonly maxUnitsPerFrame?: number | undefined;
	readonly now: () => number;
	readonly noStarvationSelectedBatchLimit?: number | undefined;
	readonly onComplete: () => void;
	readonly rankForEntry?: (entry: TEntry) => BridgeFrameApplyUnitRank;
	readonly runEntry: (entry: TEntry) => void;
	readonly scheduleNextTurn: (callback: () => void) => void;
	readonly staleScanLimit?: number | undefined;
}): void {
	runBridgeFrameApplyPump({
		frameBudgetMilliseconds: props.frameBudgetMilliseconds,
		isStale: (): boolean => props.isStale(),
		maxUnitsPerFrame: props.maxUnitsPerFrame ?? Number.POSITIVE_INFINITY,
		noStarvationSelectedBatchLimit:
			props.noStarvationSelectedBatchLimit ?? Number.POSITIVE_INFINITY,
		now: props.now,
		onDrained: (): void => {
			if (!props.isStale()) {
				props.onComplete();
			}
		},
		scheduleNextTurn: props.scheduleNextTurn,
		staleScanLimit: props.staleScanLimit ?? 0,
		units: props.entries.map((entry, index) => ({
			id: String(index),
			rank: props.rankForEntry?.(entry) ?? 'selected',
			run: (): void => {
				props.runEntry(entry);
			},
		})),
	});
}

function bridgeCodeViewDiffMaterializationCacheKeyContainsCurrentIdentity(props: {
	readonly existingCacheKey: string;
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentResources;
}): boolean {
	const resourceCacheKeys = [
		props.resources.base?.handle.cacheKey,
		props.resources.head?.handle.cacheKey,
	].filter((cacheKey): cacheKey is string => cacheKey !== undefined);
	return (
		resourceCacheKeys.length > 0 &&
		props.existingCacheKey.includes(props.item.cacheKey) &&
		resourceCacheKeys.every((cacheKey): boolean => props.existingCacheKey.includes(cacheKey))
	);
}

export function recordBridgeCodeViewItemMaterializeTelemetryForPanel(
	props: RecordBridgeCodeViewItemMaterializeTelemetryForPanelProps,
): void {
	recordBridgeCodeViewItemMaterializeTelemetry({
		telemetryRecorder: props.telemetryRecorder,
		parentTraceContext: props.parentTraceContext,
		projection: props.projection,
		item: props.item,
		resources: props.resources,
		durationMilliseconds: props.durationMilliseconds,
		result: props.result,
		selected: props.item.itemId === props.selectedItemId,
	});
}

export function recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel(
	props: RecordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanelProps,
): void {
	if (props.result === 'unchanged') {
		return;
	}
	recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetry({
		telemetryRecorder: props.telemetryRecorder,
		parentTraceContext: props.parentTraceContext,
		projection: props.projection,
		item: props.item,
		codeViewItem: props.codeViewItem,
		durationMilliseconds: props.durationMilliseconds,
		result: props.result,
		selected: props.item.itemId === props.selectedItemId,
	});
}

export function bridgeCodeViewLoadingMaterializationItemIdsForPanel(props: {
	readonly selectedContentLoadingItemId: string | null | undefined;
}): readonly string[] {
	return props.selectedContentLoadingItemId === undefined ||
		props.selectedContentLoadingItemId === null
		? []
		: [props.selectedContentLoadingItemId];
}

export interface BridgeCodeViewInstantRevealRearmCandidate {
	readonly itemId: string;
	readonly revealedAtMilliseconds: number;
	readonly selectionScrollKey: string;
}

export function shouldRearmCodeViewInstantRevealForMaterialization(props: {
	readonly isSelectedRevealSettled: boolean;
	readonly materializedItemIds: readonly string[];
	readonly nowMilliseconds: number;
	readonly orderedItemIds: readonly string[];
	readonly rearmWindowMilliseconds: number;
	readonly recentReveal: BridgeCodeViewInstantRevealRearmCandidate | null;
	readonly selectedItemId: string | null;
	readonly selectionScrollKey: string;
}): boolean {
	const recentReveal = props.recentReveal;
	if (
		recentReveal === null ||
		props.isSelectedRevealSettled ||
		props.selectedItemId === null ||
		recentReveal.itemId !== props.selectedItemId ||
		recentReveal.selectionScrollKey !== props.selectionScrollKey
	) {
		return false;
	}
	if (props.nowMilliseconds - recentReveal.revealedAtMilliseconds > props.rearmWindowMilliseconds) {
		return false;
	}
	const selectedItemIndex = props.orderedItemIds.indexOf(props.selectedItemId);
	if (selectedItemIndex <= 0) {
		return false;
	}
	for (const materializedItemId of props.materializedItemIds) {
		const materializedItemIndex = props.orderedItemIds.indexOf(materializedItemId);
		if (materializedItemIndex >= 0 && materializedItemIndex < selectedItemIndex) {
			return true;
		}
	}
	return false;
}

export function hasRenderedItemsSource(value: unknown): value is BridgeCodeViewRenderedItemsSource {
	return (
		typeof value === 'object' &&
		value !== null &&
		'getRenderedItems' in value &&
		typeof value.getRenderedItems === 'function'
	);
}

export function uniqueRenderedItemIds(
	renderedItems: readonly BridgeCodeViewRenderedItemSnapshot[],
): readonly string[] {
	return uniqueItemIds(renderedItems.map((renderedItem): string => renderedItem.id));
}

export function uniqueItemIds(candidateItemIds: readonly string[]): readonly string[] {
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

export function renderedBridgeCodeViewHeaderOffsetFromScrollOwner(props: {
	readonly itemId: string;
	readonly scrollOwner: HTMLElement | undefined;
}): BridgeCodeViewRenderedHeaderOffset | null {
	const scrollOwner = props.scrollOwner;
	if (scrollOwner === undefined) {
		return null;
	}
	const markerElement = bridgeCodeViewRenderedHeaderMarkerElement({
		itemId: props.itemId,
		scrollOwner,
	});
	const headerElement =
		markerElement === null ? null : bridgeCodeViewHeaderElementForMarker(markerElement);
	if (headerElement === null) {
		return null;
	}
	return {
		offsetPixels:
			headerElement.getBoundingClientRect().top - scrollOwner.getBoundingClientRect().top,
		stickyCompensationPixels: headerElement.getBoundingClientRect().height,
	};
}

export function shouldApplyBridgeCodeViewRenderedHeaderCorrection(props: {
	readonly didApplyRenderedHeaderCorrection: boolean;
	readonly isSelectedContentMaterialized: boolean;
	readonly renderedHeaderOffset: BridgeCodeViewRenderedHeaderOffset | null;
	readonly tolerancePixels: number;
}): boolean {
	if (props.didApplyRenderedHeaderCorrection || props.renderedHeaderOffset === null) {
		return false;
	}
	return Math.abs(props.renderedHeaderOffset.offsetPixels) > props.tolerancePixels;
}

export function bridgeCodeViewRenderedHeaderCorrectionTargetPosition(props: {
	readonly currentScrollTop: number;
	readonly renderedHeaderOffset: BridgeCodeViewRenderedHeaderOffset;
}): number {
	return (
		props.currentScrollTop +
		props.renderedHeaderOffset.offsetPixels +
		props.renderedHeaderOffset.stickyCompensationPixels
	);
}

function bridgeCodeViewRenderedHeaderMarkerElement(props: {
	readonly itemId: string;
	readonly scrollOwner: HTMLElement;
}): HTMLElement | null {
	const selector = `[data-bridge-code-view-item-id="${cssEscapeBridgeCodeViewSelectorValue(
		props.itemId,
	)}"]`;
	const searchRoots = uniqueBridgeCodeViewHeaderSearchRoots([
		props.scrollOwner,
		parentNodeForBridgeCodeViewRoot(props.scrollOwner.getRootNode()),
	]);
	for (const container of searchRoots.flatMap((searchRoot): readonly Element[] => [
		...searchRoot.querySelectorAll('diffs-container'),
	])) {
		if (container.shadowRoot !== null) {
			searchRoots.push(container.shadowRoot);
		}
	}
	for (const searchRoot of searchRoots) {
		const markerElement = searchRoot.querySelector(selector);
		if (markerElement instanceof HTMLElement) {
			return markerElement;
		}
	}
	return null;
}

function parentNodeForBridgeCodeViewRoot(rootNode: Node): ParentNode | null {
	if (
		rootNode instanceof Document ||
		rootNode instanceof DocumentFragment ||
		rootNode instanceof Element
	) {
		return rootNode;
	}
	return null;
}

function uniqueBridgeCodeViewHeaderSearchRoots(
	searchRoots: readonly (ParentNode | null)[],
): ParentNode[] {
	const uniqueSearchRoots: ParentNode[] = [];
	for (const searchRoot of searchRoots) {
		if (searchRoot === null || uniqueSearchRoots.includes(searchRoot)) {
			continue;
		}
		uniqueSearchRoots.push(searchRoot);
	}
	return uniqueSearchRoots;
}

function bridgeCodeViewHeaderElementForMarker(markerElement: HTMLElement): HTMLElement | null {
	const lightDomHeader = markerElement.closest<HTMLElement>('[data-diffs-header]');
	if (lightDomHeader !== null) {
		return lightDomHeader;
	}
	const markerRoot = markerElement.getRootNode();
	if (!('host' in markerRoot) || !(markerRoot.host instanceof HTMLElement)) {
		return null;
	}
	return markerRoot.host.closest<HTMLElement>('[data-diffs-header]') ?? markerRoot.host;
}

function cssEscapeBridgeCodeViewSelectorValue(value: string): string {
	return typeof CSS === 'undefined' || CSS.escape === undefined
		? value.replaceAll('"', '\\"')
		: CSS.escape(value);
}

export function emptyMaterializationDiagnostic(): BridgeCodeViewMaterializationDiagnostic {
	return {
		updateResult: 'not-run',
		itemType: 'none',
		itemVersion: 0,
		modelContentState: 'none',
		modelItemVersion: 0,
		additionLineCount: 0,
		deletionLineCount: 0,
		fileLineCount: 0,
		durationMilliseconds: 0,
	};
}

export function materializationDiagnosticForCodeViewItem(props: {
	readonly durationMilliseconds: number;
	readonly item: BridgeCodeViewItem;
	readonly modelItem: BridgeCodeViewItem | null;
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult;
}): BridgeCodeViewMaterializationDiagnostic {
	const modelContentState = props.modelItem?.bridgeMetadata.contentState ?? 'none';
	const modelItemVersion = props.modelItem?.version ?? 0;
	if (props.item.type === 'diff') {
		return {
			updateResult: props.updateResult,
			itemType: props.item.type,
			itemVersion: props.item.version ?? 0,
			modelContentState,
			modelItemVersion,
			additionLineCount: props.item.fileDiff.additionLines.length,
			deletionLineCount: props.item.fileDiff.deletionLines.length,
			fileLineCount: 0,
			durationMilliseconds: props.durationMilliseconds,
		};
	}
	return {
		updateResult: props.updateResult,
		itemType: props.item.type,
		itemVersion: props.item.version ?? 0,
		modelContentState,
		modelItemVersion,
		additionLineCount: 0,
		deletionLineCount: 0,
		fileLineCount: props.item.bridgeMetadata.lineCount ?? 0,
		durationMilliseconds: props.durationMilliseconds,
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

export function createBridgeCodeViewHeaderRenderers(
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
			<Button
				aria-expanded={!collapsed}
				aria-label={collapsed ? 'Expand file' : 'Collapse file'}
				className={cn(
					bridgeViewerChromeIconButtonClassName,
					'cursor-pointer text-[var(--bridge-text-secondary)] transition-colors',
					'aria-expanded:bg-transparent aria-expanded:text-[var(--bridge-text-secondary)]',
					'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
					'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
				)}
				data-bridge-code-view-item-id={itemId}
				data-testid="bridge-code-view-header-collapse-button"
				onClick={(event): void => {
					event.preventDefault();
					event.stopPropagation();
					props.onToggleItemCollapse?.(itemId);
				}}
				size="icon-sm"
				type="button"
				variant="ghost"
			>
				{collapsed ? (
					<ChevronRightIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				) : (
					<ChevronDownIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				)}
			</Button>
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

export function isBridgeCodeViewItem(item: CodeViewItem | undefined): item is BridgeCodeViewItem {
	return item !== undefined && 'bridgeMetadata' in item;
}

export function isMaterializedBridgeCodeViewContentState(
	contentState: BridgeCodeViewItem['bridgeMetadata']['contentState'],
): boolean {
	return contentState === 'hydrated' || contentState === 'windowed';
}

interface ControllerForHandleProps {
	readonly handle: CodeViewHandle<undefined>;
	readonly controllerEntryRef: {
		current: BridgeCodeViewControllerEntry | null;
	};
}

interface BridgeCodeViewSourceKeyProps {
	readonly projection: Pick<BridgeReviewProjectionResult, 'projectionId'>;
	readonly reviewPackage: Pick<BridgeReviewPackage, 'packageId' | 'reviewGeneration'>;
}

export function controllerForHandle(props: ControllerForHandleProps): BridgeCodeViewController {
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
		addItems: (items) => {
			if (codeViewHandleHasInstance(handle)) {
				handle.addItems(items);
			}
		},
		getItem: (id) => (codeViewHandleHasInstance(handle) ? handle.getItem(id) : undefined),
		updateItem: (item) => (codeViewHandleHasInstance(handle) ? handle.updateItem(item) : false),
		updateItemId: (oldId, newId) =>
			codeViewHandleHasInstance(handle) ? handle.updateItemId(oldId, newId) : false,
		scrollTo: (target) => {
			if (codeViewHandleHasInstance(handle)) {
				handle.scrollTo(target);
			}
		},
		setSelectedLines: (selection) => {
			if (codeViewHandleHasInstance(handle)) {
				handle.setSelectedLines(selection);
			}
		},
	};
}

export function codeViewHandleHasInstance(handle: CodeViewHandle<undefined>): boolean {
	return handle.getInstance() !== undefined;
}

export function makeBridgeCodeViewSourceKey(props: BridgeCodeViewSourceKeyProps): string {
	return [
		props.reviewPackage.packageId,
		props.reviewPackage.reviewGeneration,
		props.projection.projectionId,
	].join(':');
}

export function reconcileBridgeCodeViewMetadataItems(
	props: BridgeCodeViewMetadataReconcileProps,
): readonly BridgeCodeViewItem[] {
	const forceReplaceItemIds = new Set(props.forceReplaceItemIds ?? []);
	const reconciledItems = props.metadataItems.map(
		(metadataItem: BridgeCodeViewItem): BridgeCodeViewItem => {
			const currentItem = props.getCurrentItem(metadataItem.id);
			const replacementItem = isBridgeCodeViewItem(currentItem)
				? bridgeCodeViewMetadataReplacementForCurrentItem({ currentItem, metadataItem })
				: null;
			if (
				!isBridgeCodeViewItem(currentItem) ||
				currentItem.type !== metadataItem.type ||
				currentItem.bridgeMetadata.contentState === 'placeholder'
			) {
				return metadataItem;
			}
			if (replacementItem !== null) {
				return replacementItem;
			}
			if (forceReplaceItemIds.has(metadataItem.id)) {
				return bridgeCodeViewForcedMetadataReplacementForCurrentItem({
					currentItem,
					metadataItem,
				});
			}
			return currentItem;
		},
	);
	const reconciledItemIds = new Set(reconciledItems.map((item): string => item.id));
	for (const preserveItemId of props.preserveItemIds ?? []) {
		if (reconciledItemIds.has(preserveItemId)) {
			continue;
		}
		const currentItem = props.getCurrentItem(preserveItemId);
		if (
			!isBridgeCodeViewItem(currentItem) ||
			currentItem.bridgeMetadata.contentState === 'placeholder'
		) {
			continue;
		}
		reconciledItems.push(currentItem);
		reconciledItemIds.add(currentItem.id);
	}
	return reconciledItems;
}

function bridgeCodeViewForcedMetadataReplacementForCurrentItem(props: {
	readonly currentItem: BridgeCodeViewItem;
	readonly metadataItem: BridgeCodeViewItem;
}): BridgeCodeViewItem {
	const replacementItem =
		props.currentItem.collapsed === undefined
			? props.metadataItem
			: { ...props.metadataItem, collapsed: props.currentItem.collapsed };
	const currentVersion = props.currentItem.version ?? 0;
	const metadataVersion = props.metadataItem.version ?? 0;
	return metadataVersion > currentVersion
		? replacementItem
		: { ...replacementItem, version: currentVersion + 1 };
}

function bridgeCodeViewMetadataReplacementForCurrentItem(props: {
	readonly currentItem: BridgeCodeViewItem;
	readonly metadataItem: BridgeCodeViewItem;
}): BridgeCodeViewItem | null {
	if (
		props.currentItem.type !== props.metadataItem.type ||
		props.currentItem.bridgeMetadata.contentState !== 'loading' ||
		!isMaterializedBridgeCodeViewContentState(props.metadataItem.bridgeMetadata.contentState)
	) {
		return null;
	}
	const currentVersion = props.currentItem.version ?? 0;
	const metadataVersion = props.metadataItem.version ?? 0;
	const replacementItem =
		props.currentItem.collapsed === undefined
			? props.metadataItem
			: { ...props.metadataItem, collapsed: props.currentItem.collapsed };
	return metadataVersion > currentVersion
		? replacementItem
		: { ...replacementItem, version: currentVersion + 1 };
}
