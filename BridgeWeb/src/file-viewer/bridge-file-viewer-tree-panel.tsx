import { prepareFileTreeInput, type FileTreeBatchOperation } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import { GitCompareArrowsIcon } from 'lucide-react';
import {
	useCallback,
	useEffect,
	useRef,
	useState,
	type ReactElement,
	type MouseEvent as ReactMouseEvent,
} from 'react';

import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSearchInputClassName,
	bridgeViewerChromeToolbarClassName,
} from '../app/bridge-viewer-chrome.js';
import {
	BridgeViewerFilterMenu,
	type BridgeViewerFilterOption,
} from '../app/bridge-viewer-filter-menu.js';
import { BridgeViewerSearchControl } from '../app/bridge-viewer-search-control.js';
import {
	bridgeViewerTreeStyle,
	bridgeViewerTreeUnsafeCSS,
} from '../app/bridge-viewer-tree-theme.js';
import { cn } from '../app/class-name.js';
import { Input } from '../components/ui/input.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeScrollVisibleDemandTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';

export type BridgeFileViewerFilterMode = 'all' | 'fetchable' | 'unavailable';
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerDescriptorProjection {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly paths: readonly string[];
	readonly searchError: string | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}

export interface BridgeFileViewerVisibleFileDemandChange {
	readonly descriptorRefs: readonly BridgeDescriptorRef[];
	readonly visibleFileCount: number;
}

export interface BridgeFileViewerTreePanelProps {
	readonly descriptorProjection: BridgeFileViewerDescriptorProjection;
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly onFilterModeChange: (filterMode: BridgeFileViewerFilterMode) => void;
	readonly onOpenFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly onRequestFileDescriptor?: (
		request: WorktreeFileDescriptorRequest,
	) => Promise<void> | void;
	readonly onSearchModeChange: (searchMode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (searchText: string) => void;
	readonly onVisibleFileDemandChange?: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly totalTreeRowCount: number;
	readonly totalTreeHeightPixels: number | null;
	readonly totalTreeHeightSource: 'localProjection' | 'providerFacts' | null;
}

const bridgeFileViewerTreeRowHeightPixels = 24;
const bridgeFileViewerTreeOptions = {
	flattenEmptyDirectories: true,
	sort: 'default',
} as const;
const bridgeFileViewerFilterOptions = [
	{
		value: 'all',
		label: 'All files',
		selectedLabel: 'All',
		icon: '*',
	},
	{
		value: 'fetchable',
		label: 'Text files',
		selectedLabel: 'Text',
		icon: 'T',
	},
	{
		value: 'unavailable',
		label: 'Unavailable files',
		selectedLabel: 'Unavailable',
		icon: '!',
	},
] satisfies readonly BridgeViewerFilterOption<BridgeFileViewerFilterMode>[];

export function BridgeFileViewerTreePanel(props: BridgeFileViewerTreePanelProps): ReactElement {
	const fileDescriptorByPathRef = useRef(props.fileDescriptorByPath);
	const onOpenFileRef = useRef(props.onOpenFile);
	const onRequestFileDescriptorRef = useRef(props.onRequestFileDescriptor);
	const sourceIdentityRef = useRef(props.sourceIdentity);
	const treeRowsRef = useRef(props.descriptorProjection.treeRows);
	const isSyncingSelectedPathRef = useRef(false);
	const lastSelectionChangePathRef = useRef<string | null>(null);
	const [isSearchOpen, setIsSearchOpen] = useState(false);
	const paths = props.descriptorProjection.paths;
	const appliedTreePathsRef = useRef(paths);
	const initialPreparedInputRef = useRef<ReturnType<typeof prepareFileTreeInput> | null>(null);
	const initialPreparedInput =
		initialPreparedInputRef.current ?? prepareFileTreeInput(paths, bridgeFileViewerTreeOptions);
	initialPreparedInputRef.current = initialPreparedInput;
	fileDescriptorByPathRef.current = props.fileDescriptorByPath;
	onOpenFileRef.current = props.onOpenFile;
	onRequestFileDescriptorRef.current = props.onRequestFileDescriptor;
	sourceIdentityRef.current = props.sourceIdentity;
	treeRowsRef.current = props.descriptorProjection.treeRows;
	const openOrRequestPath = useCallback((selectedPath: string): void => {
		const descriptor = fileDescriptorByPathRef.current.get(selectedPath);
		if (descriptor !== undefined) {
			void onOpenFileRef.current(descriptor);
			return;
		}
		const request = descriptorRequestForSelectedPath({
			path: selectedPath,
			sourceIdentity: sourceIdentityRef.current,
			treeRows: treeRowsRef.current,
		});
		if (request !== null) {
			void onRequestFileDescriptorRef.current?.(request);
		}
	}, []);
	const { model } = useFileTree({
		preparedInput: initialPreparedInput,
		flattenEmptyDirectories: true,
		initialExpansion: 'open',
		initialSelectedPaths: props.selectedPath === null ? [] : [props.selectedPath],
		itemHeight: bridgeFileViewerTreeRowHeightPixels,
		onSelectionChange: (selectedPaths): void => {
			if (isSyncingSelectedPathRef.current) {
				return;
			}
			const selectedPath = selectedPaths[0];
			if (selectedPath === undefined) {
				return;
			}
			lastSelectionChangePathRef.current = selectedPath;
			openOrRequestPath(selectedPath);
		},
		search: false,
		sort: 'default',
		unsafeCSS: bridgeViewerTreeUnsafeCSS,
	});
	const fallbackRenderedTreeHeightPixels =
		countFlattenedWorktreeFileTreeRows(paths) * bridgeFileViewerTreeRowHeightPixels;
	const declaredTreeHeightPixels = props.totalTreeHeightPixels ?? fallbackRenderedTreeHeightPixels;
	const declaredTreeHeightSource = props.totalTreeHeightSource ?? 'localProjection';
	const selectedDescriptor =
		props.selectedPath === null
			? null
			: (props.fileDescriptorByPath.get(props.selectedPath) ?? null);
	const fileDescriptorByPath = props.fileDescriptorByPath;
	const onVisibleFileDemandChange = props.onVisibleFileDemandChange;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const shouldShowSearchInput =
		isSearchOpen ||
		props.searchText.trim().length > 0 ||
		props.descriptorProjection.searchError !== null;

	useEffect((): void => {
		const previousPaths = appliedTreePathsRef.current;
		if (previousPaths === paths) {
			return;
		}
		const appendedPaths = appendedOnlyPaths({
			nextPaths: paths,
			previousPaths,
		});
		if (appendedPaths === null) {
			model.resetPaths(paths, {
				preparedInput: prepareFileTreeInput(paths, bridgeFileViewerTreeOptions),
			});
		} else if (appendedPaths.length > 0) {
			model.batch(appendedPaths.map(fileTreeAddOperation));
			expandAncestorDirectoriesForAppendedPaths({
				model,
				paths: appendedPaths,
			});
		}
		appliedTreePathsRef.current = paths;
	}, [model, paths]);

	const publishVisibleFileDemand = useCallback((): void => {
		if (onVisibleFileDemandChange === undefined) {
			return;
		}
		const publishStartedAt = performance.now();
		const descriptorRefs = visibleDescriptorRefsForDemand({
			fileDescriptorByPath,
			model,
		});
		if (descriptorRefs.length === 0) {
			return;
		}
		onVisibleFileDemandChange({
			descriptorRefs,
			visibleFileCount: descriptorRefs.length,
		});
		if (telemetryRecorder !== undefined) {
			recordBridgeTreeScrollVisibleDemandTelemetrySample({
				durationMilliseconds: performance.now() - publishStartedAt,
				telemetryRecorder,
				traceContext: telemetryTraceContext,
				viewer: 'file',
				visibleItemCount: descriptorRefs.length,
			});
		}
	}, [
		fileDescriptorByPath,
		model,
		onVisibleFileDemandChange,
		telemetryRecorder,
		telemetryTraceContext,
	]);

	useEffect((): (() => void) => {
		let scrollElement: HTMLElement | null = null;
		let animationFrameId: number | null = null;
		const scheduleVisibleFileDemand = (): void => {
			if (animationFrameId !== null) {
				return;
			}
			animationFrameId = requestAnimationFrame((): void => {
				animationFrameId = null;
				publishVisibleFileDemand();
			});
		};
		const setupFrameId = requestAnimationFrame((): void => {
			scrollElement = fileTreeScrollElementForDemand(model);
			scrollElement?.addEventListener('scroll', scheduleVisibleFileDemand, { passive: true });
			publishVisibleFileDemand();
		});
		const unsubscribeModel = model.subscribe(scheduleVisibleFileDemand);
		return (): void => {
			cancelAnimationFrame(setupFrameId);
			if (animationFrameId !== null) {
				cancelAnimationFrame(animationFrameId);
			}
			scrollElement?.removeEventListener('scroll', scheduleVisibleFileDemand);
			unsubscribeModel();
		};
	}, [model, paths, publishVisibleFileDemand]);

	useEffect((): void => {
		if (props.selectedPath === null) {
			return;
		}
		const item = model.getItem(props.selectedPath);
		if (item === null || item.isSelected()) {
			return;
		}
		isSyncingSelectedPathRef.current = true;
		try {
			item.select();
		} finally {
			isSyncingSelectedPathRef.current = false;
		}
		model.scrollToPath(props.selectedPath, { focus: true, offset: 'nearest' });
	}, [model, props.selectedPath, paths]);

	return (
		<aside
			aria-label="Files"
			className="grid min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] border-l border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)]"
			data-pierre-file-tree-owner="FileTree"
			data-testid="bridge-file-viewer-sidebar"
		>
			<header className="grid grid-rows-[auto_auto]" data-testid="bridge-file-viewer-toolbar">
				<div
					className={cn(
						'flex min-w-0 items-center justify-between gap-2',
						bridgeViewerChromeToolbarClassName,
					)}
					data-bridge-shared-rail-toolbar="true"
					data-testid="bridge-file-viewer-rail-toolbar"
				>
					<div
						aria-live="polite"
						className="sr-only"
						data-testid="bridge-file-viewer-rail-toolbar-leading"
						role="status"
					>
						{props.descriptorProjection.searchError === null
							? `${props.descriptorProjection.treeRows.length}/${props.totalTreeRowCount}`
							: 'Invalid regex'}{' '}
						{props.sourceIdentity === null ? 'Source pending' : props.sourceIdentity.sourceId}
						<span className="hidden" data-testid="worktree-file-filter-count">
							{props.descriptorProjection.searchError === null
								? `${props.descriptorProjection.treeRows.length}/${props.totalTreeRowCount}`
								: 'Invalid regex'}
						</span>
						<span className="hidden" data-testid="worktree-file-provenance">
							{props.sourceIdentity === null ? 'Source pending' : props.sourceIdentity.sourceId}
						</span>
					</div>
					<div
						className="flex shrink-0 items-center justify-end gap-1"
						data-testid="bridge-file-viewer-rail-toolbar-trailing"
					>
						<BridgeViewerFilterMenu
							label="File class filter"
							onChange={props.onFilterModeChange}
							options={bridgeFileViewerFilterOptions}
							testId="worktree-file-filter-menu"
							value={props.filterMode}
						/>
						<BridgeViewerSearchControl
							isActive={shouldShowSearchInput}
							onOpenSearch={() => {
								setIsSearchOpen(true);
							}}
							onSearchModeChange={(searchMode) => {
								setIsSearchOpen(true);
								props.onSearchModeChange(searchMode.kind);
							}}
							searchMode={{ kind: props.searchMode }}
						/>
						{props.onOpenReviewComparison === undefined ? null : (
							<BridgeViewerButton
								ariaLabel="Open selected file in review"
								className={bridgeViewerChromeIconButtonClassName}
								data-testid="worktree-file-open-review-comparison"
								disabled={selectedDescriptor === null}
								onClick={() => {
									if (selectedDescriptor !== null) {
										props.onOpenReviewComparison?.(selectedDescriptor);
									}
								}}
								title="Open selected file in review"
							>
								<BridgeViewerIcon>
									<GitCompareArrowsIcon
										aria-hidden="true"
										className={bridgeViewerChromeLucideIconClassName}
									/>
								</BridgeViewerIcon>
							</BridgeViewerButton>
						)}
					</div>
				</div>
				{shouldShowSearchInput ? (
					<Input
						aria-label="Search files"
						className={cn('mx-2 mb-1', bridgeViewerChromeSearchInputClassName)}
						data-testid="worktree-file-search-input"
						onChange={(event) => {
							props.onSearchTextChange(event.currentTarget.value);
						}}
						placeholder="Search files"
						spellCheck={false}
						type="search"
						value={props.searchText}
					/>
				) : null}
				<div className="sr-only" data-testid="worktree-file-filter-status">
					{props.descriptorProjection.searchError === null
						? `${props.descriptorProjection.treeRows.length}/${props.totalTreeRowCount}`
						: 'Invalid regex'}
				</div>
			</header>
			<section
				className="min-h-0 overflow-auto bridge-scrollbar"
				data-testid="bridge-file-viewer-pierre-file-tree"
				data-worktree-tree-total-size={String(declaredTreeHeightPixels)}
				data-worktree-tree-total-size-source={declaredTreeHeightSource}
				onClick={(event) => {
					const selectedPath = fileTreePathFromClickEvent(event);
					if (selectedPath === null) {
						return;
					}
					if (lastSelectionChangePathRef.current === selectedPath) {
						lastSelectionChangePathRef.current = null;
						return;
					}
					openOrRequestPath(selectedPath);
				}}
			>
				<FileTree className="h-full min-h-full" model={model} style={bridgeViewerTreeStyle} />
			</section>
		</aside>
	);
}

function fileTreePathFromClickEvent(event: ReactMouseEvent<HTMLElement>): string | null {
	for (const target of event.nativeEvent.composedPath()) {
		if (!(target instanceof HTMLElement)) {
			continue;
		}
		const itemType = target.getAttribute('data-item-type');
		const itemPath = target.getAttribute('data-item-path');
		if (itemType === 'file' && itemPath !== null && itemPath.length > 0) {
			return itemPath;
		}
	}
	return null;
}

function descriptorRequestForSelectedPath(props: {
	readonly path: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const row = props.treeRows.find((candidate): boolean => candidate.path === props.path);
	if (row === undefined || row.isDirectory || row.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: row.rowId,
		path: row.path,
		fileId: row.fileId,
		lane: 'foreground',
	};
}

function fileTreeScrollElementForDemand(
	model: ReturnType<typeof useFileTree>['model'],
): HTMLElement | null {
	const fileTreeContainer = model.getFileTreeContainer();
	const rowContainer = fileTreeContainer?.shadowRoot ?? fileTreeContainer;
	return (
		rowContainer?.querySelector<HTMLElement>('[data-file-tree-virtualized-scroll="true"]') ?? null
	);
}

function visibleDescriptorRefsForDemand(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly model: ReturnType<typeof useFileTree>['model'];
}): readonly BridgeDescriptorRef[] {
	const fileTreeContainer = props.model.getFileTreeContainer();
	const rowContainer = fileTreeContainer?.shadowRoot ?? fileTreeContainer;
	if (rowContainer === undefined || rowContainer === null) {
		return [];
	}
	const descriptorRefs: BridgeDescriptorRef[] = [];
	const seenDescriptorIds = new Set<string>();
	for (const rowElement of rowContainer.querySelectorAll<HTMLElement>(
		'[data-type="item"][data-item-type="file"][data-item-path]',
	)) {
		const path = rowElement.getAttribute('data-item-path');
		if (path === null) {
			continue;
		}
		const descriptor = props.fileDescriptorByPath.get(path);
		if (
			descriptor === undefined ||
			!canFetchWorktreeFileDescriptorContent(descriptor) ||
			seenDescriptorIds.has(descriptor.contentDescriptor.ref.descriptorId)
		) {
			continue;
		}
		seenDescriptorIds.add(descriptor.contentDescriptor.ref.descriptorId);
		descriptorRefs.push(descriptor.contentDescriptor.ref);
	}
	return descriptorRefs;
}

export interface BridgeFileViewerTreeDirectoryHandle {
	readonly isDirectory: () => boolean;
	readonly isExpanded: () => boolean;
	readonly expand: () => void;
}

export interface BridgeFileViewerTreeItemHandleForAppend {
	readonly isDirectory: () => boolean;
	readonly isExpanded?: () => boolean;
	readonly expand?: () => void;
}

export interface BridgeFileViewerTreeModelForAppend {
	readonly getItem: (path: string) => BridgeFileViewerTreeItemHandleForAppend | null;
	readonly resolveMountedDirectoryPathFromInput?: (path: string) => string | null;
}

export function appendedOnlyPaths(props: {
	readonly nextPaths: readonly string[];
	readonly previousPaths: readonly string[];
}): readonly string[] | null {
	if (props.nextPaths.length < props.previousPaths.length) {
		return null;
	}
	for (let index = 0; index < props.previousPaths.length; index += 1) {
		if (props.nextPaths[index] !== props.previousPaths[index]) {
			return null;
		}
	}
	return props.nextPaths.slice(props.previousPaths.length);
}

function fileTreeAddOperation(path: string): FileTreeBatchOperation {
	return { type: 'add', path };
}

export function expandAncestorDirectoriesForAppendedPaths(props: {
	readonly model: BridgeFileViewerTreeModelForAppend;
	readonly paths: readonly string[];
}): void {
	for (const path of props.paths) {
		for (const ancestorPath of ancestorDirectoryPaths(path)) {
			const item = directoryItemForInputPath({
				model: props.model,
				path: ancestorPath,
			});
			if (isExpandableDirectoryHandle(item) && !item.isExpanded()) {
				item.expand();
			}
		}
	}
}

function directoryItemForInputPath(props: {
	readonly model: BridgeFileViewerTreeModelForAppend;
	readonly path: string;
}): BridgeFileViewerTreeItemHandleForAppend | null {
	const slashPath = `${props.path}/`;
	const mountedPath =
		props.model.resolveMountedDirectoryPathFromInput?.(props.path) ??
		props.model.resolveMountedDirectoryPathFromInput?.(slashPath) ??
		null;
	if (mountedPath !== null) {
		return props.model.getItem(mountedPath);
	}
	return props.model.getItem(props.path) ?? props.model.getItem(slashPath);
}

function isExpandableDirectoryHandle(
	item: BridgeFileViewerTreeItemHandleForAppend | null,
): item is BridgeFileViewerTreeDirectoryHandle {
	return (
		item?.isDirectory() === true &&
		typeof item.isExpanded === 'function' &&
		typeof item.expand === 'function'
	);
}

function ancestorDirectoryPaths(path: string): readonly string[] {
	const segments = path.split('/').filter((segment: string): boolean => segment.length > 0);
	const ancestorPaths: string[] = [];
	let currentPath = '';
	for (const segment of segments.slice(0, -1)) {
		currentPath = currentPath.length === 0 ? segment : `${currentPath}/${segment}`;
		ancestorPaths.push(currentPath);
	}
	return ancestorPaths;
}
