import { useRef, type ReactElement, type ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import { BridgeViewerResizableRailLayout } from '../app/bridge-viewer-resizable-rail-layout.js';
import { BridgeMarkdownCanvas } from '../app/markdown/bridge-markdown-canvas.js';
import type { BridgeMermaidRenderer } from '../app/markdown/bridge-mermaid-renderer.js';
import type { BridgeMarkdownPresentationState } from '../app/markdown/use-bridge-markdown-presentation.js';
import { useBridgeViewerSearchFocusRestoration } from '../app/use-bridge-viewer-search-focus-restoration.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { WorktreeAnnotationShareSurface } from '../worktree-annotations/worktree-annotation-output-controls.js';
import {
	BridgeFileViewerCodePanel,
	type BridgeFileViewerSelectedCodeViewItem,
} from './bridge-file-viewer-code-panel.js';
import type { BridgeFilesCodeViewOptions } from './bridge-file-viewer-code-view-options.js';
import type {
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import type {
	BridgeFileViewerDisplayModel,
	BridgeFileViewerOpenState,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import { BridgeFileViewerTreePanel } from './bridge-file-viewer-tree-panel.js';

export interface BridgeFileViewerShellProps {
	readonly codeViewOptions?: BridgeFilesCodeViewOptions;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly contentHeaderTitle: string;
	readonly dispatchVisibleFileDemand: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly displayModel: BridgeFileViewerDisplayModel;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly isFilterMenuOpen: boolean;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
	readonly fileActivationSequence?: number | null;
	readonly fileActivationStartedAtPerfNow?: number | null;
	readonly isActive: boolean;
	readonly isSearchOpen: boolean;
	readonly onClearSearch: () => void;
	readonly onFilterMenuOpenChange: (isOpen: boolean) => void;
	readonly onFilterModeChange: (mode: BridgeFileViewerFilterMode) => void;
	readonly onSearchModeChange: (mode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (text: string) => void;
	readonly onSelectFile: (selection: BridgeFileViewerSelection) => void;
	readonly onToggleSearch: () => void;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly markdownPresentation?: {
		readonly mermaidRenderer: BridgeMermaidRenderer | undefined;
		readonly presentationState: BridgeMarkdownPresentationState;
		readonly retry: () => void;
	} | null;
	readonly openFileTotalHeightPixels: number | null;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchError: string | null;
	readonly searchStatusMessage: string | null;
	readonly searchText: string;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly selectedPath: string | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
	readonly totalTreeHeight: {
		readonly heightPixels: number | null;
		readonly source: 'localProjection' | 'providerFacts' | null;
	};
	readonly totalTreeRowCount: number;
	readonly viewerContextSwitcher?: ReactNode;
	readonly viewerHeaderControls?: ReactNode;
}

export function BridgeFileViewerShell(props: BridgeFileViewerShellProps): ReactElement {
	const surfaceRootRef = useRef<HTMLElement>(null);
	const searchTriggerRef = useRef<HTMLButtonElement>(null);
	useBridgeViewerSearchFocusRestoration({
		isActive: props.isActive,
		isSearchOpen: props.isSearchOpen,
		searchTriggerRef,
		surfaceRootRef,
	});
	const selectedDisplayItem =
		props.openFileState.status === 'idle' ? null : props.openFileState.displayItem;
	const status = props.displayModel.status;
	const statusText = bridgeFileViewerHeaderStatusText(props.isActive, props.panelChromeSlice);
	return (
		<main
			ref={surfaceRootRef}
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)]"
			data-file-display-branch={
				status?.state === 'ready' ? (status.branchName ?? undefined) : undefined
			}
			data-file-display-generation={props.displayModel.source?.generation}
			data-file-display-item-count={props.displayModel.fileItemById.size}
			data-file-display-source-id={props.displayModel.source?.sourceId}
			data-file-display-status={status?.state ?? 'pending'}
			data-file-display-tree-row-count={props.displayModel.projectedRowCount}
			data-file-viewer-active={props.isActive}
			data-file-viewer-owner="BridgeViewerApp.FileViewer"
			data-selected-display-path={props.selectedPath ?? undefined}
			data-sidebar-position="right"
			data-testid="bridge-file-viewer-shell"
			data-worktree-metadata-file-row-count={props.displayModel.fileItemById.size}
			data-worktree-metadata-tree-row-count={props.displayModel.projectedRowCount}
			tabIndex={-1}
			{...(props.openFileState.status === 'idle'
				? {}
				: {
						'data-worktree-open-file-path': props.openFileState.path,
						'data-worktree-open-file-state': props.openFileState.status,
					})}
			{...(selectedDisplayItem === null
				? {}
				: {
						'data-file-display-ends-mid-line': selectedDisplayItem.endsMidLine,
						'data-file-display-ends-with-newline': selectedDisplayItem.endsWithNewline,
						'data-file-display-payload-byte-count': selectedDisplayItem.payloadByteCount,
						'data-file-display-payload-line-count': selectedDisplayItem.payloadLineCount,
						'data-file-display-total-line-count': selectedDisplayItem.totalLineCount ?? undefined,
						'data-file-display-truncation-kind': selectedDisplayItem.truncationKind,
					})}
		>
			<BridgeViewerResizableRailLayout
				autosaveId="bridge-viewer-right-rail"
				isActive={true}
				content={
					<section className="grid h-full min-h-0 min-w-0 grid-rows-[auto_auto_minmax(0,1fr)]">
						<BridgeViewerContentHeader
							controls={props.viewerHeaderControls}
							mode="file"
							statusText={statusText}
							title={props.contentHeaderTitle}
						/>
						<WorktreeAnnotationShareSurface />
						{props.markdownPresentation === null || props.markdownPresentation === undefined ? (
							<BridgeFileViewerCodePanel
								openFileState={props.openFileState}
								renderFulfillmentCoordinator={props.renderFulfillmentCoordinator}
								selectedCodeViewItem={props.selectedCodeViewItem}
								totalHeightPixels={props.openFileTotalHeightPixels}
								{...(props.codeViewOptions === undefined
									? {}
									: { codeViewOptions: props.codeViewOptions })}
								{...(props.codeViewWorkerFactory === undefined
									? {}
									: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
								{...(props.codeViewWorkerPoolEnabled === undefined
									? {}
									: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
							/>
						) : (
							<BridgeMarkdownCanvas
								isActive={props.isActive}
								presentationState={props.markdownPresentation.presentationState}
								retry={props.markdownPresentation.retry}
								{...(props.markdownPresentation.mermaidRenderer === undefined
									? {}
									: { mermaidRenderer: props.markdownPresentation.mermaidRenderer })}
							/>
						)}
					</section>
				}
				contentTestId="bridge-file-viewer-content-panel"
				handleTestId="bridge-file-viewer-rail-resize-handle"
				rail={
					<BridgeFileViewerTreePanel
						completeFileQueryTransaction={props.completeFileQueryTransaction}
						filterMode={props.filterMode}
						isFilterMenuOpen={props.isFilterMenuOpen}
						fileTreePatchStream={props.fileTreePatchStream}
						fileActivationSequence={props.fileActivationSequence ?? null}
						fileActivationStartedAtPerfNow={props.fileActivationStartedAtPerfNow ?? null}
						isActive={props.isActive}
						isSearchOpen={props.isSearchOpen}
						onFilterMenuOpenChange={props.onFilterMenuOpenChange}
						onFilterModeChange={props.onFilterModeChange}
						onClearSearch={props.onClearSearch}
						onSearchModeChange={props.onSearchModeChange}
						onSearchTextChange={props.onSearchTextChange}
						onSelectFile={props.onSelectFile}
						onToggleSearch={props.onToggleSearch}
						onVisibleFileDemandChange={props.dispatchVisibleFileDemand}
						searchMode={props.searchMode}
						searchError={props.searchError}
						searchText={props.searchText}
						searchStatusMessage={props.searchStatusMessage}
						selectedPath={props.selectedPath}
						searchTriggerRef={searchTriggerRef}
						source={props.displayModel.source}
						{...(props.telemetryRecorder === undefined
							? {}
							: { telemetryRecorder: props.telemetryRecorder })}
						telemetryTraceContext={props.telemetryTraceContext}
						totalTreeHeightPixels={props.totalTreeHeight.heightPixels}
						totalTreeHeightSource={props.totalTreeHeight.source}
						totalTreeRowCount={props.totalTreeRowCount}
						viewerContextSwitcher={props.viewerContextSwitcher}
						projectedTreeRowCount={props.displayModel.projectedRowCount}
						treeRowByPath={props.displayModel.treeRowByPath}
					/>
				}
				railTestId="bridge-file-viewer-resizable-rail"
			/>
		</main>
	);
}

export function bridgeFileViewerHeaderStatusText(
	isActive: boolean,
	panelChromeSlice: BridgeWorkerPanelChromePatchPayload,
): string | null {
	if (!isActive) return null;
	if (panelChromeSlice.isLoading === true) return panelChromeSlice.message ?? null;
	return panelChromeSlice.fileRefreshFailure === undefined ||
		panelChromeSlice.fileRefreshFailure === null
		? null
		: (panelChromeSlice.message ?? 'Files unavailable');
}
