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
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { recordBridgeCodeViewItemMaterializeTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	BridgeCodeViewController,
	type ApplyBridgeCodeViewItemUpdateResult,
	type BridgeCodeViewModel,
} from './bridge-code-view-controller.js';
import {
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import type { BridgeCodeViewMaterializationResourceEntry } from './bridge-code-view-panel-types.js';

export interface BridgeCodeViewMetadataReconcileProps {
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly metadataItems: readonly BridgeCodeViewItem[];
	readonly preserveItemIds?: readonly string[];
}

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

export function bridgeCodeViewMaterializationResourceEntriesForPanel(props: {
	readonly selectedContentDemandStartedAtMilliseconds: number | null | undefined;
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
	readonly selectedItemId: string | null;
	readonly visibleContentResourcesByItemId:
		| ReadonlyMap<string, BridgeCodeViewContentResources>
		| undefined;
}): readonly BridgeCodeViewMaterializationResourceEntry[] {
	const resourceEntriesByItemId = new Map<string, BridgeCodeViewMaterializationResourceEntry>();
	for (const [itemId, resources] of props.visibleContentResourcesByItemId ?? []) {
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

export function bridgeCodeViewLoadingMaterializationItemIdsForPanel(props: {
	readonly materializationResourceEntries: readonly BridgeCodeViewMaterializationResourceEntry[];
	readonly selectedContentLoadingItemId: string | null | undefined;
	readonly visibleLoadingItemIds: ReadonlySet<string> | undefined;
}): readonly string[] {
	const loadedItemIds = new Set(
		props.materializationResourceEntries.map((entry): string => entry.itemId),
	);
	const loadingItemIds = new Set(props.visibleLoadingItemIds ?? []);
	if (
		props.selectedContentLoadingItemId !== undefined &&
		props.selectedContentLoadingItemId !== null
	) {
		loadingItemIds.add(props.selectedContentLoadingItemId);
	}
	return [...loadingItemIds].filter((itemId: string): boolean => !loadedItemIds.has(itemId));
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

export function selectedContentStateForPanel(props: {
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

interface SelectedContentSummary {
	readonly cacheKeyCount: number;
	readonly characterCount: number;
	readonly lineCount: number;
}

export interface SelectedContentDiagnostics {
	readonly cacheKeys: string;
	readonly roleCount: number;
	readonly roleNames: string;
	readonly state: 'none' | 'pending' | 'ready';
	readonly summary: SelectedContentSummary;
}

const selectedContentRoleOrder: readonly BridgeContentRole[] = ['base', 'head', 'diff', 'file'];

export function selectedContentRoleNamesForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
}): string {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return '';
	}
	return selectedContentRoleOrder
		.filter((role): boolean => props.selectedContentResources?.[role] !== undefined)
		.join(',');
}

export function selectedContentCacheKeysForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
}): string {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return '';
	}
	const cacheKeys: string[] = [];
	for (const role of selectedContentRoleOrder) {
		const resource = props.selectedContentResources[role];
		if (resource !== undefined) {
			cacheKeys.push(`${role}:${resource.handle.cacheKey}`);
		}
	}
	return cacheKeys.join(',');
}

export function selectedContentSummaryForPanel(props: {
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
			(totalCharacters, resource): number =>
				totalCharacters + (resource.byteLength ?? resource.handle.sizeBytes),
			0,
		),
		lineCount: 0,
	};
}

export function selectedContentDiagnosticsForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentResources | null | undefined;
	readonly selectedItemId: string | null;
}): SelectedContentDiagnostics {
	const selectedContentResources = props.selectedContentResources;
	return {
		cacheKeys: selectedContentCacheKeysForPanel({ selectedContentResources }),
		roleCount:
			selectedContentResources === null || selectedContentResources === undefined
				? 0
				: Object.values(selectedContentResources).filter(
						(resource): boolean => resource !== undefined,
					).length,
		roleNames: selectedContentRoleNamesForPanel({ selectedContentResources }),
		state: selectedContentStateForPanel({
			selectedContentResources,
			selectedItemId: props.selectedItemId,
		}),
		summary: selectedContentSummaryForPanel({ selectedContentResources }),
	};
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
	const reconciledItems = props.metadataItems.map(
		(metadataItem: BridgeCodeViewItem): BridgeCodeViewItem => {
			const currentItem = props.getCurrentItem(metadataItem.id);
			if (
				!isBridgeCodeViewItem(currentItem) ||
				currentItem.type !== metadataItem.type ||
				currentItem.bridgeMetadata.contentState === 'placeholder'
			) {
				return metadataItem;
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
