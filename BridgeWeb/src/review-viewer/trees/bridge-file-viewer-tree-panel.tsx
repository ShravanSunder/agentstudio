import { prepareFileTreeInput } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import { GitCompareArrowsIcon } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ReactElement } from 'react';

import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSearchInputClassName,
	bridgeViewerChromeToolbarClassName,
} from '../../app/bridge-viewer-chrome.js';
import { cn } from '../../app/class-name.js';
import { Input } from '../../components/ui/input.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from '../../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../features/worktree-file/models/worktree-file-tree-size.js';
import { BridgeReviewButton, BridgeReviewIcon } from '../chrome/bridge-review-button.js';
import {
	BridgeReviewFilterMenu,
	type BridgeReviewFilterOption,
} from '../chrome/bridge-review-filter-menu.js';
import { BridgeReviewSearchControl } from '../chrome/bridge-review-search-control.js';
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
] satisfies readonly BridgeReviewFilterOption<BridgeFileViewerFilterMode>[];

export function BridgeFileViewerTreePanel(props: BridgeFileViewerTreePanelProps): ReactElement {
	const fileDescriptorByPathRef = useRef(props.fileDescriptorByPath);
	const onOpenFileRef = useRef(props.onOpenFile);
	const isSyncingSelectedPathRef = useRef(false);
	const [isSearchOpen, setIsSearchOpen] = useState(false);
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
	const shouldShowSearchInput =
		isSearchOpen ||
		props.searchText.trim().length > 0 ||
		props.descriptorProjection.searchError !== null;

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
							? `${props.descriptorProjection.descriptors.length}/${props.totalDescriptorCount}`
							: 'Invalid regex'}{' '}
						{props.sourceIdentity === null ? 'Source pending' : props.sourceIdentity.sourceId}
						<span className="hidden" data-testid="worktree-file-filter-count">
							{props.descriptorProjection.searchError === null
								? `${props.descriptorProjection.descriptors.length}/${props.totalDescriptorCount}`
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
						<BridgeReviewFilterMenu
							label="File class filter"
							onChange={props.onFilterModeChange}
							options={bridgeFileViewerFilterOptions}
							testId="worktree-file-filter-menu"
							value={props.filterMode}
						/>
						<BridgeReviewSearchControl
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
							<BridgeReviewButton
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
								<BridgeReviewIcon>
									<GitCompareArrowsIcon
										aria-hidden="true"
										className={bridgeViewerChromeLucideIconClassName}
									/>
								</BridgeReviewIcon>
							</BridgeReviewButton>
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
						? `${props.descriptorProjection.descriptors.length}/${props.totalDescriptorCount}`
						: 'Invalid regex'}
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
