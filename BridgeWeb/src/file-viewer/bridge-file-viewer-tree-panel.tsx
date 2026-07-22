import { FileTree } from '@pierre/trees/react';
import { useState, type ReactElement } from 'react';

import {
	BridgeViewerFilterMenu,
	type BridgeViewerFilterOption,
} from '../app/bridge-viewer-filter-menu.js';
import { BridgeViewerRailToolbar } from '../app/bridge-viewer-rail-toolbar.js';
import { BridgeViewerRightRailShell } from '../app/bridge-viewer-right-rail-shell.js';
import { BridgeViewerSearchControl } from '../app/bridge-viewer-search-control.js';
import { BridgeViewerSearchField } from '../app/bridge-viewer-search-field.js';
import { bridgeViewerTreeStyle } from '../app/bridge-viewer-tree-theme.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type {
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import type {
	BridgeFileViewerDisplaySource,
	BridgeFileViewerDisplayTreeRow,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import { useBridgeFileViewerPierreTreeRuntime } from './bridge-file-viewer-pierre-tree-runtime.js';

export interface BridgeFileViewerTreePanelProps {
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
	readonly onFilterModeChange: (filterMode: BridgeFileViewerFilterMode) => void;
	readonly onSearchModeChange: (searchMode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (searchText: string) => void;
	readonly onSelectFile: (selection: BridgeFileViewerSelection) => void;
	readonly onVisibleFileDemandChange?: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly projectedTreeRowCount: number;
	readonly searchError: string | null;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly source: BridgeFileViewerDisplaySource | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly totalTreeHeightPixels: number | null;
	readonly totalTreeHeightSource: 'localProjection' | 'providerFacts' | null;
	readonly totalTreeRowCount: number;
	readonly treeRowByPath: {
		readonly get: (path: string) => BridgeFileViewerDisplayTreeRow | undefined;
	};
}

const bridgeFileViewerTreeRowHeightPixels = 24;
const bridgeFileViewerFilterOptions = [
	{ value: 'all', label: 'All files', selectedLabel: 'All', icon: '*' },
	{ value: 'fetchable', label: 'Text files', selectedLabel: 'Text', icon: 'T' },
	{ value: 'unavailable', label: 'Unavailable files', selectedLabel: 'Unavailable', icon: '!' },
] satisfies readonly BridgeViewerFilterOption<BridgeFileViewerFilterMode>[];

export function BridgeFileViewerTreePanel(props: BridgeFileViewerTreePanelProps): ReactElement {
	const [isSearchOpen, setIsSearchOpen] = useState(false);
	const treeRuntime = useBridgeFileViewerPierreTreeRuntime({
		completeFileQueryTransaction: props.completeFileQueryTransaction,
		fileTreePatchStream: props.fileTreePatchStream,
		treeRowByPath: props.treeRowByPath,
		onSelectFile: props.onSelectFile,
		...(props.onVisibleFileDemandChange === undefined
			? {}
			: { onVisibleFileDemandChange: props.onVisibleFileDemandChange }),
		selectedPath: props.selectedPath,
		...(props.telemetryRecorder === undefined
			? {}
			: { telemetryRecorder: props.telemetryRecorder }),
		telemetryTraceContext: props.telemetryTraceContext,
	});
	const fallbackRenderedTreeHeightPixels =
		props.projectedTreeRowCount * bridgeFileViewerTreeRowHeightPixels;
	const declaredTreeHeightPixels = props.totalTreeHeightPixels ?? fallbackRenderedTreeHeightPixels;
	const declaredTreeHeightSource = props.totalTreeHeightSource ?? 'localProjection';
	const shouldShowSearchInput =
		isSearchOpen || props.searchText.trim().length > 0 || props.searchError !== null;
	const visibleCountLabel =
		props.searchError === null
			? `${props.projectedTreeRowCount}/${props.totalTreeRowCount}`
			: 'Invalid regex';
	const sourceLabel = props.source?.sourceId ?? 'Source pending';

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
							<span className="sr-only" data-testid="worktree-file-filter-count">
								{visibleCountLabel}
							</span>
							<span className="sr-only" data-testid="worktree-file-provenance">
								{sourceLabel}
							</span>
						</>
					),
					leadingAriaLive: 'polite',
					leadingClassName: 'flex-1',
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
								searchToggleTestId="worktree-file-search-toggle"
								testId="worktree-file-search-control"
							/>
						</>
					),
					trailingClassName: 'shrink-0',
					trailingTestId: 'bridge-file-viewer-rail-toolbar-trailing',
				}),
				toolbarBelow: shouldShowSearchInput ? (
					<BridgeViewerSearchField
						clearButtonTestId="worktree-file-search-clear"
						errorMessage={props.searchError === null ? null : 'Invalid regex'}
						inputTestId="worktree-file-search-input"
						onChange={props.onSearchTextChange}
						onClear={(): void => props.onSearchTextChange('')}
						onSearchModeChange={(searchMode) => {
							props.onSearchModeChange(searchMode.kind);
						}}
						regexToggleTestId="worktree-file-regex-toggle"
						searchMode={{ kind: props.searchMode }}
						statusTestId="worktree-file-filter-status"
						value={props.searchText}
					/>
				) : null,
				toolbarFooter: null,
			})}
		</>
	);
}
