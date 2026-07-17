import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import { BridgeViewerResizableRailLayout } from '../app/bridge-viewer-resizable-rail-layout.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import {
	BridgeFileViewerCodePanel,
	type BridgeFileViewerSelectedCodeViewItem,
} from './bridge-file-viewer-code-panel.js';
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
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly contentHeaderTitle: string;
	readonly dispatchVisibleFileDemand: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly displayModel: BridgeFileViewerDisplayModel;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
	readonly isActive: boolean;
	readonly onFilterModeChange: (mode: BridgeFileViewerFilterMode) => void;
	readonly onSearchModeChange: (mode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (text: string) => void;
	readonly onSelectFile: (selection: BridgeFileViewerSelection) => void;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly openFileTotalHeightPixels: number | null;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
	readonly searchMode: BridgeFileViewerSearchMode;
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
	readonly viewerHeaderControls?: ReactNode;
}

export function BridgeFileViewerShell(props: BridgeFileViewerShellProps): ReactElement {
	const selectedDisplayItem =
		props.openFileState.status === 'idle' ? null : props.openFileState.displayItem;
	const status = props.displayModel.status;
	const statusText =
		props.isActive && props.panelChromeSlice.isLoading === true
			? (props.panelChromeSlice.message ?? null)
			: null;
	return (
		<main
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
					<section className="grid h-full min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)]">
						<BridgeViewerContentHeader
							controls={props.viewerHeaderControls}
							eyebrow="Files"
							statusText={statusText}
							title={props.contentHeaderTitle}
						/>
						<BridgeFileViewerCodePanel
							openFileState={props.openFileState}
							renderFulfillmentCoordinator={props.renderFulfillmentCoordinator}
							selectedCodeViewItem={props.selectedCodeViewItem}
							totalHeightPixels={props.openFileTotalHeightPixels}
							{...(props.codeViewWorkerFactory === undefined
								? {}
								: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
							{...(props.codeViewWorkerPoolEnabled === undefined
								? {}
								: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
						/>
					</section>
				}
				contentTestId="bridge-file-viewer-content-panel"
				handleTestId="bridge-file-viewer-rail-resize-handle"
				rail={
					<BridgeFileViewerTreePanel
						completeFileQueryTransaction={props.completeFileQueryTransaction}
						filterMode={props.filterMode}
						fileTreePatchStream={props.fileTreePatchStream}
						onFilterModeChange={props.onFilterModeChange}
						onSearchModeChange={props.onSearchModeChange}
						onSearchTextChange={props.onSearchTextChange}
						onSelectFile={props.onSelectFile}
						onVisibleFileDemandChange={props.dispatchVisibleFileDemand}
						searchMode={props.searchMode}
						searchError={props.displayModel.searchError}
						searchText={props.searchText}
						selectedPath={props.selectedPath}
						source={props.displayModel.source}
						{...(props.telemetryRecorder === undefined
							? {}
							: { telemetryRecorder: props.telemetryRecorder })}
						telemetryTraceContext={props.telemetryTraceContext}
						totalTreeHeightPixels={props.totalTreeHeight.heightPixels}
						totalTreeHeightSource={props.totalTreeHeight.source}
						totalTreeRowCount={props.totalTreeRowCount}
						projectedTreeRowCount={props.displayModel.projectedRowCount}
						treeRowByPath={props.displayModel.treeRowByPath}
					/>
				}
				railTestId="bridge-file-viewer-resizable-rail"
			/>
		</main>
	);
}
