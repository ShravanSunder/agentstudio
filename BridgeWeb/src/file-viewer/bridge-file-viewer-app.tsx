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

import { BridgeViewerViewSettingsMenu } from '../app/bridge-viewer-view-settings-menu.js';
import type { BridgeFilesViewSettings } from '../app/bridge-viewer-view-settings.js';
import { useBridgeViewerToolbarShortcuts } from '../app/use-bridge-viewer-toolbar-shortcuts.js';
import { bridgeWorkerFileQueryKey } from '../core/comm-worker/bridge-worker-file-query-contracts.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import {
	bridgeFileViewerCodeViewOptions,
	createBridgeFilesViewSettingsDefaults,
	deriveBridgeFilesCodeViewOptions,
} from './bridge-file-viewer-code-view-options.js';
import { bridgeFileViewerContentHeaderTitle } from './bridge-file-viewer-content-header-title.js';
import {
	bridgeFileViewerDisplayModelForSnapshot,
	bridgeFileViewerOpenStateForSelection,
	type BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import { useBridgeFileViewerRenderSnapshotController } from './bridge-file-viewer-render-snapshot-controller.js';
import { useBridgeFileViewerControlEventListeners } from './use-bridge-file-viewer-control-event-listeners.js';
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
const bridgeFilesDefaultViewSettings = createBridgeFilesViewSettingsDefaults(
	bridgeFileViewerCodeViewOptions,
);
const bridgeFileViewerNavigationCommandIsAlwaysEligible = (): boolean => true;

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
		controlTarget = document,
		isActive = true,
		isNavigationCommandStillEligible = bridgeFileViewerNavigationCommandIsAlwaysEligible,
		navigationCommand,
		onDisplaySourceChange,
		telemetryRecorder,
		telemetryTraceContext,
		viewerContextSwitcher,
	} = props;
	const [selection, setSelection] = useState<BridgeFileViewerSelection | null>(null);
	const [isFilterMenuOpen, setIsFilterMenuOpen] = useState(false);
	const [searchRejectionMessage, setSearchRejectionMessage] = useState<string | null>(null);
	const [viewSettings, setViewSettings] = useState<BridgeFilesViewSettings>(
		bridgeFilesDefaultViewSettings,
	);
	const [viewSettingsMenuOpen, setViewSettingsMenuOpen] = useState(false);
	const projectionExclusionClearedSelectionRef = useRef(false);
	const selectionQueryKeyRef = useRef('');
	useEffect((): void => {
		if (!isActive) {
			setIsFilterMenuOpen(false);
			setViewSettingsMenuOpen(false);
		}
	}, [isActive]);
	const codeViewOptions = useMemo(
		() =>
			deriveBridgeFilesCodeViewOptions({
				compatibilityOptions: bridgeFileViewerCodeViewOptions,
				viewSettings,
			}),
		[viewSettings],
	);
	const isActiveRef = useRef(isActive);
	isActiveRef.current = isActive;
	const appliedNavigationApplicationKeyRef = useRef<string | null>(null);
	const controlProbeSequenceRef = useRef(0);
	const { rootSnapshot, viewerActions, viewerStore } = useBridgeFileViewerStoreBindings();
	const { filterMode, search } = rootSnapshot;
	const { acceptedCriteria, enteredCriteria } = search;
	const searchMode = acceptedCriteria.mode;
	const searchText = acceptedCriteria.query;
	const queryKey = bridgeWorkerFileQueryKey({ filterMode, searchMode, searchText });
	const renderSnapshotController = useBridgeFileViewerRenderSnapshotController({ selection });
	const dispatchFileViewQueryFact = renderSnapshotController.dispatchFileViewQueryFact;
	useEffect((): void => {
		dispatchFileViewQueryFact({ filterMode, searchMode, searchText });
	}, [dispatchFileViewQueryFact, filterMode, searchMode, searchText]);
	const displayModel = useMemo(
		() => bridgeFileViewerDisplayModelForSnapshot(renderSnapshotController.fileDisplaySnapshot),
		[renderSnapshotController.fileDisplaySnapshot],
	);
	const toggleSearch = useCallback((): void => {
		setSearchRejectionMessage(null);
		viewerActions.transitionSearch({ type: search.isOpen ? 'close' : 'open' });
	}, [search.isOpen, viewerActions]);
	const changeSearchText = useCallback(
		(query: string): void => {
			const transition = viewerActions.transitionSearch({ type: 'change_query', query });
			setSearchRejectionMessage(
				transition.rejectionReason === 'search_query_too_long' ? 'Search query is too long' : null,
			);
		},
		[viewerActions],
	);
	const toggleFilters = useCallback(
		(): void => setIsFilterMenuOpen((isOpen): boolean => !isOpen),
		[],
	);
	useBridgeViewerToolbarShortcuts({
		isActive,
		onToggleFilters: toggleFilters,
		onToggleSearch: toggleSearch,
		target: controlTarget,
	});
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
	const contentHeaderControls = (
		<>
			{isActive ? (
				<BridgeViewerViewSettingsMenu
					defaultSettings={bridgeFilesDefaultViewSettings}
					onChange={setViewSettings}
					onOpenChange={setViewSettingsMenuOpen}
					open={viewSettingsMenuOpen}
					settings={viewSettings}
					surface="file"
				/>
			) : null}
		</>
	);
	const selectFile = useCallback(
		(nextSelection: BridgeFileViewerSelection, source: 'programmatic' | 'user'): void => {
			if (!isActiveRef.current) {
				return;
			}
			projectionExclusionClearedSelectionRef.current = false;
			selectionQueryKeyRef.current = queryKey;
			setSelection(nextSelection);
			renderSnapshotController.dispatchSelectedFileViewContentRequest({
				fileId: nextSelection.fileId,
				selectedSource: source,
			});
		},
		[queryKey, renderSnapshotController],
	);
	useEffect((): void => {
		if (
			!isActive ||
			selection === null ||
			displayModel.acceptedQueryKey !== queryKey ||
			selectionQueryKeyRef.current === queryKey
		)
			return;
		const selectedRow = displayModel.treeRowByPath.get(selection.path);
		if (selectedRow?.fileId === selection.fileId && !selectedRow.isDirectory) {
			selectionQueryKeyRef.current = queryKey;
			return;
		}
		projectionExclusionClearedSelectionRef.current = true;
		selectionQueryKeyRef.current = queryKey;
		setSelection(null);
		renderSnapshotController.clearSelectedFileViewContent();
		const treeFallback = document.querySelector(
			'[data-testid="bridge-file-viewer-pierre-file-tree"]',
		);
		if (treeFallback instanceof HTMLElement) treeFallback.focus({ preventScroll: true });
	}, [
		displayModel.acceptedQueryKey,
		displayModel.treeRowByPath,
		isActive,
		queryKey,
		renderSnapshotController,
		selection,
	]);
	const selectFileFromTree = useCallback(
		(nextSelection: BridgeFileViewerSelection): void => {
			selectFile(nextSelection, 'user');
		},
		[selectFile],
	);
	useBridgeFileViewerControlEventListeners({
		controlProbeSequenceRef,
		displayModel,
		isActive,
		onSearchResult: (reason): void => {
			setSearchRejectionMessage(
				reason === 'search_query_too_long' ? 'Search query is too long' : null,
			);
		},
		rootSnapshot,
		selectFile,
		selectedFileId: selection?.fileId ?? null,
		target: controlTarget,
		viewerActions,
		viewerStore,
	});

	useEffect((): void => {
		if (!isActive) {
			return;
		}
		const navigationPath = bridgeFileViewerNavigationPath(navigationCommand);
		const navigationApplicationKey = bridgeFileViewerNavigationApplicationKey(navigationCommand);
		if (
			navigationPath !== null &&
			navigationCommand !== undefined &&
			appliedNavigationApplicationKeyRef.current !== navigationApplicationKey
		) {
			const row = displayModel.treeRowByPath.get(navigationPath);
			if (row?.fileId !== null && row?.fileId !== undefined && !row.isDirectory) {
				if (!isNavigationCommandStillEligible(navigationCommand)) return;
				appliedNavigationApplicationKeyRef.current = navigationApplicationKey;
				selectFile({ fileId: row.fileId, path: row.path }, 'programmatic');
			}
			return;
		}
		if (
			!autoOpenInitialFile ||
			selection !== null ||
			projectionExclusionClearedSelectionRef.current
		) {
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
		isNavigationCommandStillEligible,
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
	const contentHeaderTitle = bridgeFileViewerContentHeaderTitle({
		selectedPath,
		sourceId: displayModel.source?.sourceId ?? '',
	});
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
					viewerContextSwitcher={viewerContextSwitcher}
					viewerHeaderControls={contentHeaderControls}
				/>
			}
		>
			<LazyBridgeFileViewerShell
				codeViewOptions={codeViewOptions}
				completeFileQueryTransaction={renderSnapshotController.completeFileQueryTransaction}
				contentHeaderTitle={contentHeaderTitle}
				dispatchVisibleFileDemand={dispatchVisibleFileDemand}
				displayModel={displayModel}
				filterMode={filterMode}
				isFilterMenuOpen={isFilterMenuOpen}
				fileTreePatchStream={renderSnapshotController.fileTreePatchStream}
				isActive={isActive}
				isSearchOpen={search.isOpen}
				onFilterMenuOpenChange={setIsFilterMenuOpen}
				onFilterModeChange={viewerActions.setFilterMode}
				onClearSearch={(): void => {
					setSearchRejectionMessage(null);
					viewerActions.transitionSearch({ type: 'clear_or_close' });
				}}
				onSearchModeChange={(mode): void => {
					setSearchRejectionMessage(null);
					viewerActions.transitionSearch({ type: 'change_mode', mode });
				}}
				onSearchTextChange={changeSearchText}
				onSelectFile={selectFileFromTree}
				onToggleSearch={toggleSearch}
				openFileState={openFileState}
				openFileTotalHeightPixels={openFileTotalHeightPixels}
				panelChromeSlice={renderSnapshotController.panelChromeSlice}
				renderFulfillmentCoordinator={renderSnapshotController.renderFulfillmentCoordinator}
				searchError={search.error === null ? null : 'Invalid regex'}
				searchMode={enteredCriteria.mode}
				searchStatusMessage={searchRejectionMessage}
				searchText={enteredCriteria.query}
				selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}
				selectedPath={selectedPath}
				telemetryRecorder={telemetryRecorder}
				telemetryTraceContext={telemetryTraceContext ?? null}
				totalTreeHeight={totalTreeHeight}
				totalTreeRowCount={totalTreeRowCount}
				viewerContextSwitcher={viewerContextSwitcher}
				viewerHeaderControls={contentHeaderControls}
				{...(codeViewWorkerFactory === undefined ? {} : { codeViewWorkerFactory })}
				{...(codeViewWorkerPoolEnabled === undefined ? {} : { codeViewWorkerPoolEnabled })}
			/>
		</Suspense>
	);
}

function bridgeFileViewerNavigationPath(
	navigationCommand: BridgeFileViewerAppProps['navigationCommand'],
): string | null {
	return navigationCommand?.target.path ?? null;
}

function bridgeFileViewerNavigationApplicationKey(
	navigationCommand: BridgeFileViewerAppProps['navigationCommand'],
): string | null {
	if (navigationCommand === undefined) return null;
	return [
		navigationCommand.commandId,
		navigationCommand.bindingRevision,
		navigationCommand.source.sourceId,
		navigationCommand.source.subscriptionGeneration,
	].join('\u0000');
}
