import { prepareFileTreeInput } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import { GitCompareArrowsIcon, RegexIcon } from 'lucide-react';
import { useEffect, useMemo, useRef, type ReactElement } from 'react';

import { Input } from '../../components/ui/input.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from '../../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../features/worktree-file/models/worktree-file-tree-size.js';
import { BridgeReviewButton, BridgeReviewIcon } from '../chrome/bridge-review-button.js';
import { bridgeReviewTreeStyle, bridgeReviewTreeUnsafeCSS } from './bridge-tree-theme.js';

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
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly onSearchModeChange: (searchMode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (searchText: string) => void;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly totalDescriptorCount: number;
	readonly totalTreeHeightPixels: number | null;
	readonly totalTreeHeightSource: 'localProjection' | 'providerFacts' | null;
}

const bridgeFileViewerTreeRowHeightPixels = 24;

export function BridgeFileViewerTreePanel(props: BridgeFileViewerTreePanelProps): ReactElement {
	const fileDescriptorByPathRef = useRef(props.fileDescriptorByPath);
	const onOpenFileRef = useRef(props.onOpenFile);
	const isSyncingSelectedPathRef = useRef(false);
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
			if (isSyncingSelectedPathRef.current) {
				return;
			}
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
		unsafeCSS: bridgeReviewTreeUnsafeCSS,
	});
	const fallbackRenderedTreeHeightPixels =
		countFlattenedWorktreeFileTreeRows(paths) * bridgeFileViewerTreeRowHeightPixels;
	const declaredTreeHeightPixels = props.totalTreeHeightPixels ?? fallbackRenderedTreeHeightPixels;
	const declaredTreeHeightSource = props.totalTreeHeightSource ?? 'localProjection';
	const selectedDescriptor =
		props.selectedPath === null
			? null
			: (props.fileDescriptorByPath.get(props.selectedPath) ?? null);

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
			<header
				className="grid gap-2 border-b border-[var(--bridge-border-subtle)] p-2"
				data-testid="bridge-file-viewer-toolbar"
			>
				<div className="grid grid-cols-[minmax(0,1fr)_auto_auto] gap-2">
					<Input
						aria-label="Search files"
						className="h-7 border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] text-xs"
						data-testid="worktree-file-search-input"
						onChange={(event) => {
							props.onSearchTextChange(event.currentTarget.value);
						}}
						placeholder="Search files"
						spellCheck={false}
						type="search"
						value={props.searchText}
					/>
					<BridgeReviewButton
						ariaLabel={props.searchMode === 'regex' ? 'Use text search' : 'Use regex search'}
						ariaPressed={props.searchMode === 'regex'}
						className="h-7 w-7 border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-0"
						data-testid="worktree-file-regex-toggle"
						onClick={() => {
							props.onSearchModeChange(props.searchMode === 'regex' ? 'text' : 'regex');
						}}
						title={props.searchMode === 'regex' ? 'Use text search' : 'Use regex search'}
					>
						<BridgeReviewIcon>
							<RegexIcon aria-hidden="true" className="size-4" />
						</BridgeReviewIcon>
					</BridgeReviewButton>
					{props.onOpenReviewComparison === undefined ? null : (
						<BridgeReviewButton
							ariaLabel="Open selected file in review"
							className="h-7 w-7 border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-0"
							data-testid="worktree-file-open-review-comparison"
							disabled={selectedDescriptor === null}
							onClick={() => {
								if (selectedDescriptor !== null) {
									props.onOpenReviewComparison?.(selectedDescriptor);
								}
							}}
							title="Open selected file in review"
						>
							<BridgeReviewIcon>
								<GitCompareArrowsIcon aria-hidden="true" className="size-4" />
							</BridgeReviewIcon>
						</BridgeReviewButton>
					)}
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
				data-worktree-tree-total-size={String(declaredTreeHeightPixels)}
				data-worktree-tree-total-size-source={declaredTreeHeightSource}
			>
				<FileTree className="h-full min-h-full" model={model} style={bridgeReviewTreeStyle} />
			</section>
		</aside>
	);
}

function BridgeFileViewerFilterButton(props: {
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly isActive: boolean;
	readonly label: string;
	readonly onSelect: (filterMode: BridgeFileViewerFilterMode) => void;
}): ReactElement {
	return (
		<BridgeReviewButton
			ariaPressed={props.isActive}
			className="h-7 border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2 text-xs"
			data-testid={`worktree-file-filter-${props.filterMode}`}
			onClick={() => {
				props.onSelect(props.filterMode);
			}}
		>
			{props.label}
		</BridgeReviewButton>
	);
}
