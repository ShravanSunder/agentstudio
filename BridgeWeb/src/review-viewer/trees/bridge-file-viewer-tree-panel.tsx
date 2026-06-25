import { prepareFileTreeInput } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import { useEffect, useMemo, useRef, type ReactElement } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from '../../features/worktree-file/models/worktree-file-protocol-models.js';

export type BridgeFileViewerFilterMode = 'all' | 'fetchable' | 'unavailable';
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerDescriptorProjection {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly searchError: string | null;
}

export interface BridgeFileViewerTreePanelProps {
	readonly descriptorProjection: BridgeFileViewerDescriptorProjection;
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly onFilterModeChange: (filterMode: BridgeFileViewerFilterMode) => void;
	readonly onOpenFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly onSearchModeChange: (searchMode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (searchText: string) => void;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly totalDescriptorCount: number;
	readonly totalTreeHeightPixels: number | null;
}

const bridgeFileViewerTreeRowHeightPixels = 24;

export function BridgeFileViewerTreePanel(props: BridgeFileViewerTreePanelProps): ReactElement {
	const fileDescriptorByPathRef = useRef(props.fileDescriptorByPath);
	const onOpenFileRef = useRef(props.onOpenFile);
	const paths = useMemo(
		(): readonly string[] =>
			props.descriptorProjection.descriptors.map((descriptor) => descriptor.path),
		[props.descriptorProjection.descriptors],
	);
	const preparedInput = useMemo(
		() => prepareFileTreeInput(paths, { flattenEmptyDirectories: true, sort: 'default' }),
		[paths],
	);
	const { model } = useFileTree({
		preparedInput,
		flattenEmptyDirectories: true,
		initialExpansion: 'open',
		initialSelectedPaths: props.selectedPath === null ? [] : [props.selectedPath],
		itemHeight: bridgeFileViewerTreeRowHeightPixels,
		onSelectionChange: (selectedPaths): void => {
			const selectedPath = selectedPaths[0];
			if (selectedPath === undefined) {
				return;
			}
			const descriptor = fileDescriptorByPathRef.current.get(selectedPath);
			if (descriptor !== undefined) {
				void onOpenFileRef.current(descriptor);
			}
		},
		search: false,
	});
	const renderedTreeHeightPixels =
		countPierreFileTreeRows(paths) * bridgeFileViewerTreeRowHeightPixels;

	useEffect((): void => {
		fileDescriptorByPathRef.current = props.fileDescriptorByPath;
		onOpenFileRef.current = props.onOpenFile;
	}, [props.fileDescriptorByPath, props.onOpenFile]);

	useEffect((): void => {
		model.resetPaths(preparedInput.paths, { preparedInput });
	}, [model, paths, preparedInput]);

	useEffect((): void => {
		if (props.selectedPath === null) {
			return;
		}
		const item = model.getItem(props.selectedPath);
		if (item === null || item.isSelected()) {
			return;
		}
		item.select();
		model.scrollToPath(props.selectedPath, { focus: true, offset: 'nearest' });
	}, [model, props.selectedPath, paths]);

	return (
		<aside
			aria-label="Files"
			className="grid min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] border-l border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)]"
			data-pierre-file-tree-owner="FileTree"
			data-testid="bridge-file-viewer-sidebar"
		>
			<header
				className="grid gap-2 border-b border-[var(--bridge-border-subtle)] p-2"
				data-testid="bridge-file-viewer-toolbar"
			>
				<div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2">
					<input
						aria-label="Search files"
						className="min-w-0 rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2 py-1 text-xs outline-none"
						data-testid="worktree-file-search-input"
						onChange={(event) => {
							props.onSearchTextChange(event.currentTarget.value);
						}}
						placeholder="Search files"
						spellCheck={false}
						type="search"
						value={props.searchText}
					/>
					<button
						aria-pressed={props.searchMode === 'regex'}
						className="rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2 py-1 text-xs"
						data-testid="worktree-file-regex-toggle"
						onClick={() => {
							props.onSearchModeChange(props.searchMode === 'regex' ? 'text' : 'regex');
						}}
						title={props.searchMode === 'regex' ? 'Use text search' : 'Use regex search'}
						type="button"
					>
						.*
					</button>
				</div>
				<div className="flex flex-wrap items-center gap-1" role="group">
					<BridgeFileViewerFilterButton
						filterMode="all"
						isActive={props.filterMode === 'all'}
						label="All"
						onSelect={props.onFilterModeChange}
					/>
					<BridgeFileViewerFilterButton
						filterMode="fetchable"
						isActive={props.filterMode === 'fetchable'}
						label="Text"
						onSelect={props.onFilterModeChange}
					/>
					<BridgeFileViewerFilterButton
						filterMode="unavailable"
						isActive={props.filterMode === 'unavailable'}
						label="Unavailable"
						onSelect={props.onFilterModeChange}
					/>
				</div>
				<div
					className="flex items-center justify-between gap-2 text-xs text-[var(--bridge-text-secondary)]"
					data-testid="worktree-file-filter-status"
				>
					<span data-testid="worktree-file-filter-count">
						{props.descriptorProjection.searchError === null
							? `${props.descriptorProjection.descriptors.length}/${props.totalDescriptorCount}`
							: 'Invalid regex'}
					</span>
					<span data-testid="worktree-file-provenance">
						{props.sourceIdentity === null ? 'Source pending' : props.sourceIdentity.sourceId}
					</span>
				</div>
			</header>
			<section
				className="min-h-0 overflow-auto bridge-scrollbar"
				data-testid="bridge-file-viewer-pierre-file-tree"
				data-worktree-tree-total-size={String(renderedTreeHeightPixels)}
			>
				<FileTree className="h-full min-h-full" model={model} />
			</section>
		</aside>
	);
}

function countPierreFileTreeRows(paths: readonly string[]): number {
	const rootNode: BridgeFileViewerTreeDirectoryNode = { directories: new Map(), fileCount: 0 };
	for (const path of paths) {
		const parts = path.split('/').filter((part) => part.length > 0);
		if (parts.length === 0) {
			continue;
		}
		let currentNode = rootNode;
		for (let index = 0; index < parts.length - 1; index += 1) {
			const directoryName = parts[index];
			if (directoryName === undefined) {
				continue;
			}
			let childNode = currentNode.directories.get(directoryName);
			if (childNode === undefined) {
				childNode = { directories: new Map(), fileCount: 0 };
				currentNode.directories.set(directoryName, childNode);
			}
			currentNode = childNode;
		}
		currentNode.fileCount += 1;
	}
	return countPierreVisibleRowsForDirectory(rootNode, true);
}

interface BridgeFileViewerTreeDirectoryNode {
	readonly directories: Map<string, BridgeFileViewerTreeDirectoryNode>;
	fileCount: number;
}

function countPierreVisibleRowsForDirectory(
	node: BridgeFileViewerTreeDirectoryNode,
	isRoot: boolean,
): number {
	let visibleChildRows = node.fileCount;
	for (const childNode of node.directories.values()) {
		visibleChildRows += countPierreVisibleRowsForDirectory(childNode, false);
	}
	if (isRoot) {
		return visibleChildRows;
	}
	const childCount = node.fileCount + node.directories.size;
	const onlyChildIsDirectory = node.fileCount === 0 && node.directories.size === 1;
	if (childCount === 1 && onlyChildIsDirectory) {
		return visibleChildRows;
	}
	return 1 + visibleChildRows;
}

function BridgeFileViewerFilterButton(props: {
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly isActive: boolean;
	readonly label: string;
	readonly onSelect: (filterMode: BridgeFileViewerFilterMode) => void;
}): ReactElement {
	return (
		<button
			aria-pressed={props.isActive}
			className="rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2 py-1 text-xs data-[active=true]:bg-[var(--bridge-header-control-active-bg)]"
			data-active={props.isActive}
			data-testid={`worktree-file-filter-${props.filterMode}`}
			onClick={() => {
				props.onSelect(props.filterMode);
			}}
			type="button"
		>
			{props.label}
		</button>
	);
}
