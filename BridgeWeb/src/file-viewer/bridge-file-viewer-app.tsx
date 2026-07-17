import {
	lazy,
	Suspense,
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type ReactElement,
} from 'react';

import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import {
	bridgeFileViewerDisplayModelForSnapshot,
	bridgeFileViewerOpenStateForSelection,
	type BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import { useBridgeFileViewerRenderSnapshotController } from './bridge-file-viewer-render-snapshot-controller.js';
import { useBridgeFileViewerDisplaySourceReporter } from './use-bridge-file-viewer-display-source-reporter.js';
import { useBridgeFileViewerStoreBindings } from './use-bridge-file-viewer-store-bindings.js';
import { useBridgeFileViewerVisibleDemandController } from './use-bridge-file-viewer-visible-demand-controller.js';

export type { BridgeFileViewerOpenState } from './bridge-file-viewer-display-model.js';
export type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';

const LazyBridgeFileViewerShell = lazy(async () => {
	const module = await import('./bridge-file-viewer-shell.js');
	return { default: module.BridgeFileViewerShell };
});

const bridgeFileViewerDisplayLineHeightPixels = 20;
const bridgeFileViewerTreeRowHeightPixels = 24;

export function BridgeFileViewerApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	return <BridgeFileViewerAppImpl {...props} />;
}

export function BridgeFileViewerBrowserTestApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	return <BridgeFileViewerAppImpl {...props} />;
}

function BridgeFileViewerAppImpl(props: BridgeFileViewerAppProps): ReactElement {
	const {
		autoOpenInitialFile = false,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		isActive = true,
		navigationCommand,
		onDisplaySourceChange,
		telemetryRecorder,
		telemetryTraceContext,
		viewerHeaderControls,
	} = props;
	const [selection, setSelection] = useState<BridgeFileViewerSelection | null>(null);
	const isActiveRef = useRef(isActive);
	isActiveRef.current = isActive;
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const { rootSnapshot, viewerActions } = useBridgeFileViewerStoreBindings();
	const { filterMode, searchMode, searchText } = rootSnapshot;
	const renderSnapshotController = useBridgeFileViewerRenderSnapshotController({ selection });
	const dispatchFileViewQueryFact = renderSnapshotController.dispatchFileViewQueryFact;
	useEffect((): void => {
		dispatchFileViewQueryFact({ filterMode, searchMode, searchText });
	}, [dispatchFileViewQueryFact, filterMode, searchMode, searchText]);
	const displayModel = useMemo(
		() => bridgeFileViewerDisplayModelForSnapshot(renderSnapshotController.fileDisplaySnapshot),
		[renderSnapshotController.fileDisplaySnapshot],
	);
	useBridgeFileViewerDisplaySourceReporter({
		...(onDisplaySourceChange === undefined ? {} : { onDisplaySourceChange }),
		source: displayModel.source,
	});
	const selectedDisplayItem =
		selection === null ? null : (displayModel.fileItemById.get(selection.fileId) ?? null);
	const openFileState = bridgeFileViewerOpenStateForSelection({
		contentAvailability: renderSnapshotController.selectedContentAvailability,
		displayItem: selectedDisplayItem,
		hasPierreItem: renderSnapshotController.selectedCodeViewItem !== null,
		selection,
		status: displayModel.status,
	});
	const selectFile = useCallback(
		(nextSelection: BridgeFileViewerSelection, source: 'programmatic' | 'user'): void => {
			if (!isActiveRef.current) {
				return;
			}
			setSelection(nextSelection);
			renderSnapshotController.dispatchSelectedFileViewContentRequest({
				fileId: nextSelection.fileId,
				selectedSource: source,
			});
		},
		[renderSnapshotController],
	);
	const selectFileFromTree = useCallback(
		(nextSelection: BridgeFileViewerSelection): void => {
			selectFile(nextSelection, 'user');
		},
		[selectFile],
	);

	useEffect((): void => {
		if (!isActive) {
			return;
		}
		const navigationPath = bridgeFileViewerNavigationPath(navigationCommand);
		if (
			navigationPath !== null &&
			navigationCommand !== undefined &&
			appliedNavigationCommandIdRef.current !== navigationCommand.commandId
		) {
			const row = displayModel.treeRowByPath.get(navigationPath);
			if (row?.fileId !== null && row?.fileId !== undefined && !row.isDirectory) {
				appliedNavigationCommandIdRef.current = navigationCommand.commandId;
				selectFile({ fileId: row.fileId, path: row.path }, 'programmatic');
			}
			return;
		}
		if (!autoOpenInitialFile || selection !== null) {
			return;
		}
		const firstFileRow = displayModel.firstFileRow;
		if (firstFileRow?.fileId !== null && firstFileRow?.fileId !== undefined) {
			selectFile({ fileId: firstFileRow.fileId, path: firstFileRow.path }, 'programmatic');
		}
	}, [
		autoOpenInitialFile,
		displayModel.treeRowByPath,
		displayModel.firstFileRow,
		isActive,
		navigationCommand,
		selectFile,
		selection,
	]);

	const dispatchVisibleFileDemand = useBridgeFileViewerVisibleDemandController({
		dispatchVisibleFileViewViewportFact:
			renderSnapshotController.dispatchVisibleFileViewViewportFact,
		isActive,
	});
	const selectedPath = selection?.path ?? null;
	const contentHeaderTitle =
		displayModel.source === null
			? (selectedPath ?? 'Source pending')
			: selectedPath === null
				? displayModel.source.sourceId
				: `${displayModel.source.sourceId} / ${selectedPath}`;
	const openFileTotalHeightPixels =
		selectedDisplayItem === null
			? null
			: selectedDisplayItem.payloadLineCount * bridgeFileViewerDisplayLineHeightPixels;
	const totalTreeRowCount = displayModel.totalRowCount;
	const totalTreeHeight = {
		heightPixels: totalTreeRowCount * bridgeFileViewerTreeRowHeightPixels,
		source: 'localProjection' as const,
	};

	return (
		<Suspense
			fallback={
				<BridgeFileViewerLazyLoadingFrame
					isActive={isActive}
					viewerHeaderControls={viewerHeaderControls}
				/>
			}
		>
			<LazyBridgeFileViewerShell
				completeFileQueryTransaction={renderSnapshotController.completeFileQueryTransaction}
				contentHeaderTitle={contentHeaderTitle}
				dispatchVisibleFileDemand={dispatchVisibleFileDemand}
				displayModel={displayModel}
				filterMode={filterMode}
				fileTreePatchStream={renderSnapshotController.fileTreePatchStream}
				isActive={isActive}
				onFilterModeChange={viewerActions.setFilterMode}
				onSearchModeChange={viewerActions.setSearchMode}
				onSearchTextChange={viewerActions.setSearchText}
				onSelectFile={selectFileFromTree}
				openFileState={openFileState}
				openFileTotalHeightPixels={openFileTotalHeightPixels}
				panelChromeSlice={renderSnapshotController.panelChromeSlice}
				renderFulfillmentCoordinator={renderSnapshotController.renderFulfillmentCoordinator}
				searchMode={searchMode}
				searchText={searchText}
				selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}
				selectedPath={selectedPath}
				telemetryRecorder={telemetryRecorder}
				telemetryTraceContext={telemetryTraceContext ?? null}
				totalTreeHeight={totalTreeHeight}
				totalTreeRowCount={totalTreeRowCount}
				viewerHeaderControls={viewerHeaderControls}
				{...(codeViewWorkerFactory === undefined ? {} : { codeViewWorkerFactory })}
				{...(codeViewWorkerPoolEnabled === undefined ? {} : { codeViewWorkerPoolEnabled })}
			/>
		</Suspense>
	);
}

function bridgeFileViewerNavigationPath(
	navigationCommand: BridgeFileViewerAppProps['navigationCommand'],
): string | null {
	if (navigationCommand?.context !== 'files' || navigationCommand.target?.targetKind !== 'file') {
		return null;
	}
	return navigationCommand.target.fileRef.path;
}
