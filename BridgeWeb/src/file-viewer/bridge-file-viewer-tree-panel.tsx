import { FileTree } from '@pierre/trees/react';
import { GitCompareArrowsIcon } from 'lucide-react';
import { useState, type ReactElement } from 'react';

import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSearchInputClassName,
} from '../app/bridge-viewer-chrome.js';
import {
	BridgeViewerFilterMenu,
	type BridgeViewerFilterOption,
} from '../app/bridge-viewer-filter-menu.js';
import { BridgeViewerRailToolbar } from '../app/bridge-viewer-rail-toolbar.js';
import { BridgeViewerRightRailShell } from '../app/bridge-viewer-right-rail-shell.js';
import { BridgeViewerSearchControl } from '../app/bridge-viewer-search-control.js';
import { bridgeViewerTreeStyle } from '../app/bridge-viewer-tree-theme.js';
import { cn } from '../app/class-name.js';
import { Input } from '../components/ui/input.js';
import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type {
	BridgeFileViewerDescriptorProjection,
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import { useBridgeFileViewerPierreTreeRuntime } from './bridge-file-viewer-pierre-tree-runtime.js';

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
	const [isSearchOpen, setIsSearchOpen] = useState(false);
	const paths = props.descriptorProjection.paths;
	const treeRuntime = useBridgeFileViewerPierreTreeRuntime({
		descriptorProjection: props.descriptorProjection,
		fileDescriptorByPath: props.fileDescriptorByPath,
		onOpenFile: props.onOpenFile,
		...(props.onRequestFileDescriptor === undefined
			? {}
			: { onRequestFileDescriptor: props.onRequestFileDescriptor }),
		...(props.onVisibleFileDemandChange === undefined
			? {}
			: { onVisibleFileDemandChange: props.onVisibleFileDemandChange }),
		selectedPath: props.selectedPath,
		sourceIdentity: props.sourceIdentity,
		...(props.telemetryRecorder === undefined
			? {}
			: { telemetryRecorder: props.telemetryRecorder }),
		telemetryTraceContext: props.telemetryTraceContext,
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

	return (
		<>
			{BridgeViewerRightRailShell({
				ariaLabel: 'Files',
				body: (
					<FileTree
						className="h-full min-h-full"
						model={treeRuntime.model}
						style={bridgeViewerTreeStyle}
					/>
				),
				bodyClassName: 'h-full min-h-0 overflow-hidden',
				bodyDataAttributes: {
					'data-worktree-tree-total-size': String(declaredTreeHeightPixels),
					'data-worktree-tree-total-size-source': declaredTreeHeightSource,
				},
				bodyElement: 'section',
				bodyOnClick: treeRuntime.handleTreeClick,
				bodyTestId: 'bridge-file-viewer-pierre-file-tree',
				border: 'subtle',
				headerTestId: 'bridge-file-viewer-toolbar',
				layout: 'grid',
				rootDataAttributes: { 'data-pierre-file-tree-owner': 'FileTree' },
				testId: 'bridge-file-viewer-sidebar',
				toolbar: BridgeViewerRailToolbar({
					className: 'min-w-0 gap-2',
					leading: (
						<>
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
						</>
					),
					leadingAriaLive: 'polite',
					leadingClassName: 'sr-only',
					leadingRole: 'status',
					leadingTestId: 'bridge-file-viewer-rail-toolbar-leading',
					testId: 'bridge-file-viewer-rail-toolbar',
					trailing: (
						<>
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
								regexToggleTestId="worktree-file-regex-toggle"
								searchMode={{ kind: props.searchMode }}
								searchToggleTestId="worktree-file-search-toggle"
								testId="worktree-file-search-control"
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
						</>
					),
					trailingClassName: 'shrink-0',
					trailingTestId: 'bridge-file-viewer-rail-toolbar-trailing',
				}),
				toolbarBelow: shouldShowSearchInput ? (
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
				) : null,
				toolbarFooter: (
					<div className="sr-only" data-testid="worktree-file-filter-status">
						{props.descriptorProjection.searchError === null
							? `${props.descriptorProjection.treeRows.length}/${props.totalTreeRowCount}`
							: 'Invalid regex'}
					</div>
				),
			})}
		</>
	);
}
