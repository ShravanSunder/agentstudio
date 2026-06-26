import { RefreshCwIcon } from 'lucide-react';
import {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type MutableRefObject,
	type ReactElement,
	type ReactNode,
} from 'react';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDemandStimulus,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import {
	BridgeReviewButton,
	BridgeReviewIcon,
} from '../review-viewer/chrome/bridge-review-button.js';
import { BridgeFileViewerCodePanel } from '../review-viewer/code-view/bridge-file-viewer-code-panel.js';
import {
	BridgeFileViewerTreePanel,
	type BridgeFileViewerDescriptorProjection,
	type BridgeFileViewerFilterMode,
	type BridgeFileViewerSearchMode,
	type BridgeFileViewerVisibleFileDemandChange,
} from '../review-viewer/trees/bridge-file-viewer-tree-panel.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileInitialSurface,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import {
	createWorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceDemandDispatchResult,
	type WorktreeFileSurfaceLoadTelemetry,
	type WorktreeFileSurfaceLoadResult,
	type WorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeFileViewerAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fetchResource?: (props: WorktreeFileSurfaceRuntimeFetchResourceProps) => Promise<string>;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
	readonly viewerHeaderControls?: ReactNode;
}

interface BridgeFileViewerRenderState {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly provenance: WorktreeFileSurfaceProvenance | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}

type BridgeFileViewerOpenState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

interface BridgeFileViewerRefreshDebugState {
	readonly commitState: 'committed' | 'ignored';
	readonly currentRequestId: number;
	readonly descriptorId: string;
	readonly requestId: number;
	readonly result: 'ok' | Extract<WorktreeFileSurfaceLoadResult, { readonly ok: false }>['reason'];
}

type BridgeFileViewerDemandDispatchDebugState =
	| { readonly status: 'idle' }
	| {
			readonly status: 'settled';
			readonly result: WorktreeFileSurfaceDemandDispatchResult;
	  }
	| {
			readonly status: 'failed';
			readonly reason: string;
	  };

type BridgeFileViewerSearchPattern =
	| { readonly ok: true; readonly pattern: RegExp }
	| { readonly ok: false; readonly message: string };

const defaultPaneId = 'bridge-worktree-dev-pane';
const defaultFileLineHeightPixels = 20;
const pierreCodeViewFileChromeHeightPixels = 52;
const emptyRenderState: BridgeFileViewerRenderState = {
	descriptors: [],
	provenance: null,
	sourceIdentity: null,
	treeSizeFacts: null,
};

export function BridgeFileViewerApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	const {
		autoOpenInitialFile = false,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		fetchResource,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		onOpenReviewComparison,
		subscribeFrames,
	} = props;
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const openFileBodyRef = useRef<string | null>(null);
	const demandDispatchRequestIdRef = useRef(0);
	const openFileRequestIdRef = useRef(0);
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const renderStateRef = useRef<BridgeFileViewerRenderState>(emptyRenderState);
	const [renderState, setRenderState] = useState<BridgeFileViewerRenderState>(emptyRenderState);
	const [openFileState, setOpenFileState] = useState<BridgeFileViewerOpenState>({
		status: 'idle',
	});
	const [refreshDebugState, setRefreshDebugState] =
		useState<BridgeFileViewerRefreshDebugState | null>(null);
	const [lastOpenLoadTelemetry, setLastOpenLoadTelemetry] =
		useState<WorktreeFileSurfaceLoadTelemetry | null>(null);
	const [lastDemandDispatchDebugState, setLastDemandDispatchDebugState] =
		useState<BridgeFileViewerDemandDispatchDebugState>({ status: 'idle' });
	const [searchText, setSearchText] = useState('');
	const [searchMode, setSearchMode] = useState<BridgeFileViewerSearchMode>('text');
	const [filterMode, setFilterMode] = useState<BridgeFileViewerFilterMode>('all');
	const selectedPath = openFileState.status === 'idle' ? null : openFileState.path;
	const fileDescriptorByPath = useMemo(
		(): ReadonlyMap<string, WorktreeFileDescriptor> =>
			new Map(renderState.descriptors.map((descriptor) => [descriptor.path, descriptor])),
		[renderState.descriptors],
	);
	const navigationTargetPath = fileViewerNavigationTargetPath(props.navigationCommand);

	if (runtimeRef.current === null) {
		runtimeRef.current = createWorktreeFileSurfaceRuntime({
			paneId: defaultPaneId,
			fetchResource: fetchResource ?? defaultFetchWorktreeFileResource,
		});
	}

	const openFile = useCallback(async (descriptor: WorktreeFileDescriptor): Promise<void> => {
		const requestId = openFileRequestIdRef.current + 1;
		openFileRequestIdRef.current = requestId;
		openFileBodyRef.current = null;
		setLastOpenLoadTelemetry(null);
		setOpenFileState({ status: 'loading', path: descriptor.path, descriptor });
		const runtime = runtimeRef.current;
		if (runtime === null) {
			if (openFileRequestIdRef.current === requestId) {
				setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
			}
			return;
		}
		const result = await runtime.openFile({
			descriptor,
			openFileSessionId: descriptor.fileId,
		});
		if (openFileRequestIdRef.current !== requestId) {
			return;
		}
		if (result.ok) {
			openFileBodyRef.current = result.body;
			setLastOpenLoadTelemetry(result.loadTelemetry);
			setOpenFileState({ status: 'ready', path: descriptor.path, descriptor });
			return;
		}
		openFileBodyRef.current = null;
		setLastOpenLoadTelemetry(null);
		setOpenFileState({
			status: result.reason === 'content_unavailable' ? 'unavailable' : 'failed',
			path: descriptor.path,
			descriptor,
		});
	}, []);

	const applyIncomingFrames = useCallback(
		(
			frames: readonly WorktreeFileProtocolFrame[],
			surface?: {
				readonly provenance: WorktreeFileSurfaceProvenance | null;
				readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
			},
		): BridgeFileViewerRenderState => {
			const nextState = applyFramesToRuntime({
				currentRenderState: renderStateRef.current,
				frames,
				provenance: surface?.provenance ?? null,
				runtime: runtimeRef.current,
				sourceIdentity: surface?.sourceIdentity ?? null,
			});
			renderStateRef.current = nextState;
			setRenderState(nextState);
			setOpenFileState((currentOpenFileState) =>
				reconcileOpenFileStateWithFrames({
					currentOpenFileState,
					frames,
					openFileBodyRef,
					openFileRequestIdRef,
				}),
			);
			return nextState;
		},
		[],
	);

	useEffect((): (() => void) => {
		let isCancelled = false;
		const loadFrames = async (): Promise<void> => {
			const initialSurface =
				initialFrames !== undefined
					? { frames: initialFrames }
					: loadInitialSurface === undefined
						? { frames: loadInitialFrames === undefined ? [] : await loadInitialFrames() }
						: await loadInitialSurface();
			if (isCancelled) {
				return;
			}
			const nextState = applyIncomingFrames(initialSurface.frames, {
				provenance: initialSurface.provenance ?? null,
				sourceIdentity: initialSurface.source ?? null,
			});
			if (autoOpenInitialFile && openFileRequestIdRef.current === 0) {
				if (navigationTargetPath !== null) {
					return;
				}
				const initialDescriptor = nextState.descriptors.find((descriptor) =>
					canFetchWorktreeFileDescriptorContent(descriptor),
				);
				if (initialDescriptor !== undefined) {
					void openFile(initialDescriptor);
				}
			}
		};
		void loadFrames();
		return (): void => {
			isCancelled = true;
		};
	}, [
		applyIncomingFrames,
		autoOpenInitialFile,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		navigationTargetPath,
		openFile,
	]);

	useEffect((): ReturnType<WorktreeFileFrameSubscriptionFactory> | undefined => {
		if (subscribeFrames === undefined) {
			return undefined;
		}
		return subscribeFrames((frames) => {
			applyIncomingFrames(frames);
		});
	}, [applyIncomingFrames, subscribeFrames]);

	useEffect((): void => {
		const navigationCommand = props.navigationCommand;
		if (navigationCommand === undefined || navigationTargetPath === null) {
			return;
		}
		if (appliedNavigationCommandIdRef.current === navigationCommand.commandId) {
			return;
		}
		const targetDescriptor = renderState.descriptors.find(
			(descriptor) =>
				descriptor.path === navigationTargetPath &&
				canFetchWorktreeFileDescriptorContent(descriptor),
		);
		if (targetDescriptor === undefined) {
			return;
		}
		appliedNavigationCommandIdRef.current = navigationCommand.commandId;
		void openFile(targetDescriptor);
	}, [navigationTargetPath, openFile, props.navigationCommand, renderState.descriptors]);

	const refreshOpenFile = useCallback(async (state: BridgeFileViewerOpenState): Promise<void> => {
		if (state.status !== 'stale') {
			return;
		}
		const requestId = openFileRequestIdRef.current + 1;
		openFileRequestIdRef.current = requestId;
		setLastOpenLoadTelemetry(null);
		const runtime = runtimeRef.current;
		if (runtime === null) {
			if (openFileRequestIdRef.current === requestId) {
				setOpenFileState({ status: 'failed', path: state.path, descriptor: state.descriptor });
			}
			return;
		}
		const refreshDescriptor =
			findLatestDescriptorForOpenFile({
				descriptor: state.descriptor,
				renderState: renderStateRef.current,
			}) ?? state.descriptor;
		setOpenFileState({
			status: 'refreshing',
			path: refreshDescriptor.path,
			descriptor: refreshDescriptor,
		});
		const result = await runtime.refreshOpenFile({
			openFileSessionId: state.descriptor.fileId,
		});
		if (openFileRequestIdRef.current !== requestId) {
			setRefreshDebugState({
				commitState: 'ignored',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
				requestId,
				result: result.ok ? 'ok' : result.reason,
			});
			return;
		}
		setRefreshDebugState({
			commitState: 'committed',
			currentRequestId: openFileRequestIdRef.current,
			descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
			requestId,
			result: result.ok ? 'ok' : result.reason,
		});
		if (result.ok) {
			openFileBodyRef.current = result.body;
			setLastOpenLoadTelemetry(result.loadTelemetry);
			const refreshedDescriptor =
				findLatestDescriptorForOpenFile({
					descriptor: state.descriptor,
					renderState: renderStateRef.current,
				}) ?? state.descriptor;
			setOpenFileState({
				status: 'ready',
				path: refreshedDescriptor.path,
				descriptor: refreshedDescriptor,
			});
			return;
		}
		openFileBodyRef.current =
			result.reason === 'content_unavailable' ? null : openFileBodyRef.current;
		setLastOpenLoadTelemetry(null);
		setOpenFileState({
			status: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
			path: refreshDescriptor.path,
			descriptor: refreshDescriptor,
		});
	}, []);

	const dispatchVisibleFileDemand = useCallback(
		(change: BridgeFileViewerVisibleFileDemandChange): void => {
			const runtime = runtimeRef.current;
			if (runtime === null || change.descriptorRefs.length === 0) {
				return;
			}
			const requestId = demandDispatchRequestIdRef.current + 1;
			demandDispatchRequestIdRef.current = requestId;
			const stimuli: readonly WorktreeFileDemandStimulus[] = [
				{
					kind: 'treeViewportChanged',
					descriptorRefs: [...change.descriptorRefs],
				},
			];
			void runtime
				.dispatchDemandStimuli(stimuli)
				.then((result): void => {
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					setLastDemandDispatchDebugState({
						status: 'settled',
						result,
					});
				})
				.catch((error: unknown): void => {
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				});
		},
		[],
	);

	const descriptorProjection = useMemo(
		(): BridgeFileViewerDescriptorProjection =>
			projectBridgeFileViewerDescriptors({
				descriptors: renderState.descriptors,
				filterMode,
				searchMode,
				searchText,
			}),
		[filterMode, renderState.descriptors, searchMode, searchText],
	);
	const totalTreeHeight = totalTreeHeightForSizeFacts({
		filteredDescriptorCount: descriptorProjection.descriptors.length,
		filteredTreeRowCount: countFlattenedWorktreeFileTreeRows(
			descriptorProjection.descriptors.map((descriptor) => descriptor.path),
		),
		hasActiveProjection:
			filterMode !== 'all' ||
			searchText.trim().length > 0 ||
			descriptorProjection.searchError !== null,
		sizeFacts: renderState.treeSizeFacts,
		totalDescriptorCount: renderState.descriptors.length,
	});
	const openFileBody =
		openFileState.status === 'ready' ||
		openFileState.status === 'stale' ||
		openFileState.status === 'refreshing'
			? openFileBodyRef.current
			: null;
	const canRefreshOpenFile =
		openFileState.status === 'stale' &&
		findLatestDescriptorForOpenFile({
			descriptor: openFileState.descriptor,
			renderState,
		}) !== null;
	const openFileTotalHeightPixels = totalOpenFileHeightForState(openFileState);
	const contentHeaderTitle = bridgeFileViewerHeaderTitle({
		selectedPath,
		sourceIdentity: renderState.sourceIdentity,
	});
	const lastDemandDispatchResult =
		lastDemandDispatchDebugState.status === 'settled' ? lastDemandDispatchDebugState.result : null;
	const firstDemandLoadTelemetry =
		lastDemandDispatchResult === null
			? null
			: firstSuccessfulDemandLoadTelemetry(lastDemandDispatchResult);

	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)]"
			data-file-viewer-owner="BridgeViewerApp.FileViewer"
			data-last-refresh-commit-state={refreshDebugState?.commitState}
			data-last-refresh-current-request-id={refreshDebugState?.currentRequestId}
			data-last-refresh-descriptor-id={refreshDebugState?.descriptorId}
			data-last-refresh-request-id={refreshDebugState?.requestId}
			data-last-refresh-result={refreshDebugState?.result}
			data-last-demand-dispatch-error={
				lastDemandDispatchDebugState.status === 'failed'
					? lastDemandDispatchDebugState.reason
					: undefined
			}
			data-last-demand-dispatch-failed-count={lastDemandDispatchResult?.failedCount}
			data-last-demand-dispatch-first-disposition={firstDemandLoadTelemetry?.disposition}
			data-last-demand-dispatch-first-lane={firstDemandLoadTelemetry?.lane}
			data-last-demand-dispatch-intent-count={lastDemandDispatchResult?.intentCount}
			data-last-demand-dispatch-loaded-count={lastDemandDispatchResult?.loadedCount}
			data-last-demand-dispatch-status={lastDemandDispatchDebugState.status}
			data-last-demand-dispatch-stimulus-count={lastDemandDispatchResult?.stimulusCount}
			data-last-open-load-disposition={lastOpenLoadTelemetry?.disposition}
			data-last-open-load-duration-ms={lastOpenLoadTelemetry?.durationMilliseconds}
			data-last-open-load-estimated-bytes={lastOpenLoadTelemetry?.estimatedBytes ?? undefined}
			data-last-open-load-executor-in-flight-after={
				lastOpenLoadTelemetry?.executorInFlightCountAfter
			}
			data-last-open-load-executor-in-flight-bytes-after={
				lastOpenLoadTelemetry?.executorInFlightBytesAfter
			}
			data-last-open-load-executor-in-flight-bytes-before={
				lastOpenLoadTelemetry?.executorInFlightBytesBefore
			}
			data-last-open-load-executor-in-flight-before={
				lastOpenLoadTelemetry?.executorInFlightCountBefore
			}
			data-last-open-load-executor-queued-after={
				lastOpenLoadTelemetry?.executorQueuedLoadCountAfter
			}
			data-last-open-load-executor-queued-bytes-after={
				lastOpenLoadTelemetry?.executorQueuedBytesAfter
			}
			data-last-open-load-executor-queued-bytes-before={
				lastOpenLoadTelemetry?.executorQueuedBytesBefore
			}
			data-last-open-load-executor-queued-before={
				lastOpenLoadTelemetry?.executorQueuedLoadCountBefore
			}
			data-last-open-load-lane={lastOpenLoadTelemetry?.lane}
			data-last-open-load-scheduler-queued-bytes-after={
				lastOpenLoadTelemetry?.schedulerQueuedEstimatedBytesAfter
			}
			data-last-open-load-scheduler-queued-bytes-before={
				lastOpenLoadTelemetry?.schedulerQueuedEstimatedBytesBefore
			}
			data-last-open-load-scheduler-queued-after={
				lastOpenLoadTelemetry?.schedulerQueuedIntentCountAfter
			}
			data-last-open-load-scheduler-queued-before={
				lastOpenLoadTelemetry?.schedulerQueuedIntentCountBefore
			}
			data-selected-display-path={selectedPath ?? undefined}
			data-sidebar-position="right"
			data-testid="bridge-file-viewer-shell"
			{...(renderState.sourceIdentity === null
				? {}
				: {
						'data-worktree-source-cursor': renderState.sourceIdentity.sourceCursor,
						'data-worktree-source-id': renderState.sourceIdentity.sourceId,
						'data-worktree-source-state': 'live',
					})}
			{...(renderState.provenance === null
				? {}
				: {
						'data-worktree-base-ref': renderState.provenance.baseRef,
						'data-worktree-root-token': renderState.provenance.worktreeRootToken,
						'data-worktree-scenario': renderState.provenance.scenarioName,
					})}
		>
			<div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_minmax(260px,340px)]">
				<section className="grid min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)]">
					<BridgeViewerContentHeader
						controls={props.viewerHeaderControls}
						eyebrow="Files"
						title={contentHeaderTitle}
					/>
					<BridgeFileViewerCodePanel
						openFileBody={openFileBody}
						openFileState={openFileState}
						staleNotice={
							openFileState.status === 'stale' ? (
								<BridgeFileViewerStaleNotice
									canRefresh={canRefreshOpenFile}
									onRefresh={() => {
										void refreshOpenFile(openFileState);
									}}
								/>
							) : null
						}
						totalHeightPixels={openFileTotalHeightPixels}
						{...(codeViewWorkerFactory === undefined ? {} : { codeViewWorkerFactory })}
						{...(codeViewWorkerPoolEnabled === undefined ? {} : { codeViewWorkerPoolEnabled })}
					/>
				</section>
				<BridgeFileViewerTreePanel
					descriptorProjection={descriptorProjection}
					fileDescriptorByPath={fileDescriptorByPath}
					filterMode={filterMode}
					onFilterModeChange={setFilterMode}
					onOpenFile={openFile}
					{...(onOpenReviewComparison === undefined ? {} : { onOpenReviewComparison })}
					onSearchModeChange={setSearchMode}
					onSearchTextChange={setSearchText}
					onVisibleFileDemandChange={dispatchVisibleFileDemand}
					searchMode={searchMode}
					searchText={searchText}
					selectedPath={selectedPath}
					sourceIdentity={renderState.sourceIdentity}
					totalDescriptorCount={renderState.descriptors.length}
					totalTreeHeightPixels={totalTreeHeight.heightPixels}
					totalTreeHeightSource={totalTreeHeight.source}
				/>
			</div>
		</main>
	);
}

function firstSuccessfulDemandLoadTelemetry(
	result: WorktreeFileSurfaceDemandDispatchResult,
): WorktreeFileSurfaceLoadTelemetry | null {
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			return loadResult.loadTelemetry;
		}
	}
	return null;
}

function bridgeFileViewerHeaderTitle(props: {
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
}): string {
	const sourceTitle = props.sourceIdentity?.sourceId ?? 'Source pending';
	return props.selectedPath === null ? sourceTitle : `${sourceTitle} / ${props.selectedPath}`;
}

function fileViewerNavigationTargetPath(
	navigationCommand: BridgeViewerNavigationCommand | undefined,
): string | null {
	if (navigationCommand?.context !== 'files' || navigationCommand.target?.targetKind !== 'file') {
		return null;
	}
	return navigationCommand.target.fileRef.path;
}

function BridgeFileViewerStaleNotice(props: {
	readonly canRefresh: boolean;
	readonly onRefresh: () => void;
}): ReactElement {
	return (
		<div
			className="absolute right-3 top-3 z-10 flex items-center gap-2 rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-menu-bg)] px-3 py-2 text-xs shadow-lg"
			data-testid="worktree-file-content-stale"
		>
			<span>Content changed</span>
			<BridgeReviewButton
				className="border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2"
				data-testid="worktree-file-refresh"
				disabled={!props.canRefresh}
				onClick={props.onRefresh}
			>
				<BridgeReviewIcon>
					<RefreshCwIcon aria-hidden="true" className="size-3" />
				</BridgeReviewIcon>
				Refresh
			</BridgeReviewButton>
		</div>
	);
}

function projectBridgeFileViewerDescriptors(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
}): BridgeFileViewerDescriptorProjection {
	const trimmedSearchText = props.searchText.trim();
	const searchPattern =
		trimmedSearchText.length === 0
			? null
			: makeBridgeFileViewerSearchPattern({
					searchMode: props.searchMode,
					searchText: trimmedSearchText,
				});
	if (searchPattern?.ok === false) {
		return { descriptors: [], searchError: searchPattern.message };
	}
	const descriptors = props.descriptors.filter((descriptor): boolean => {
		if (!descriptorMatchesFilterMode({ descriptor, filterMode: props.filterMode })) {
			return false;
		}
		return searchPattern === null ? true : searchPattern.pattern.test(descriptor.path);
	});
	return { descriptors, searchError: null };
}

function descriptorMatchesFilterMode(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly filterMode: BridgeFileViewerFilterMode;
}): boolean {
	switch (props.filterMode) {
		case 'all':
			return true;
		case 'fetchable':
			return canFetchWorktreeFileDescriptorContent(props.descriptor);
		case 'unavailable':
			return props.descriptor.isBinary || props.descriptor.virtualizedExtentKind === 'unavailable';
	}
	return false;
}

function makeBridgeFileViewerSearchPattern(props: {
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
}): BridgeFileViewerSearchPattern {
	if (props.searchMode === 'text') {
		return { ok: true, pattern: new RegExp(escapeRegExp(props.searchText), 'iu') };
	}
	try {
		return { ok: true, pattern: new RegExp(props.searchText, 'iu') };
	} catch (error) {
		return { ok: false, message: error instanceof Error ? error.message : 'Invalid regex' };
	}
}

function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

function applyFramesToRuntime(props: {
	readonly currentRenderState: BridgeFileViewerRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance?: WorktreeFileSurfaceProvenance | null;
	readonly runtime: WorktreeFileSurfaceRuntime | null;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity | null;
}): BridgeFileViewerRenderState {
	const descriptorsByFileId = new Map(
		props.currentRenderState.descriptors.map((descriptor) => [descriptor.fileId, descriptor]),
	);
	const provenance = props.provenance ?? props.currentRenderState.provenance;
	let sourceIdentity = props.sourceIdentity ?? props.currentRenderState.sourceIdentity;
	let treeSizeFacts = props.currentRenderState.treeSizeFacts;
	for (const frame of props.frames) {
		props.runtime?.applyFrame(frame);
		if (frame.frameKind === 'worktree.snapshot' || frame.frameKind === 'worktree.treeWindow') {
			treeSizeFacts = frame.treeSizeFacts ?? treeSizeFacts;
		}
		if (frame.frameKind === 'worktree.snapshot') {
			sourceIdentity = frame.source;
		}
		if (frame.frameKind === 'worktree.treeWindow') {
			sourceIdentity = frame.projectionIdentity.source;
		}
		if (frame.frameKind === 'worktree.fileDescriptor') {
			sourceIdentity = frame.descriptor.sourceIdentity;
			descriptorsByFileId.set(frame.descriptor.fileId, frame.descriptor);
		}
		if (frame.frameKind === 'worktree.fileInvalidated') {
			const latestDescriptor = frame.invalidation.latestDescriptor;
			if (latestDescriptor !== undefined) {
				sourceIdentity = latestDescriptor.sourceIdentity;
				descriptorsByFileId.set(latestDescriptor.fileId, latestDescriptor);
			}
		}
		if (frame.frameKind === 'worktree.reset') {
			descriptorsByFileId.clear();
			sourceIdentity = frame.source ?? sourceIdentity;
			treeSizeFacts = null;
		}
	}
	return {
		descriptors: [...descriptorsByFileId.values()],
		provenance,
		sourceIdentity,
		treeSizeFacts,
	};
}

function reconcileOpenFileStateWithFrames(props: {
	readonly currentOpenFileState: BridgeFileViewerOpenState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
}): BridgeFileViewerOpenState {
	if (props.currentOpenFileState.status === 'idle') {
		return props.currentOpenFileState;
	}
	const currentOpenFileState = props.currentOpenFileState;
	const resetFrame = props.frames.find((frame) => frame.frameKind === 'worktree.reset');
	if (resetFrame !== undefined) {
		props.openFileRequestIdRef.current += 1;
		return {
			status: 'stale',
			path: currentOpenFileState.path,
			descriptor: currentOpenFileState.descriptor,
		};
	}
	const matchedInvalidation = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileInvalidated' &&
			(frame.invalidation.fileId === currentOpenFileState.descriptor.fileId ||
				frame.invalidation.path === currentOpenFileState.path),
	);
	const matchedReplacementDescriptor = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileDescriptor' &&
			(frame.descriptor.fileId === currentOpenFileState.descriptor.fileId ||
				frame.descriptor.path === currentOpenFileState.path),
	);
	if (
		matchedInvalidation?.frameKind !== 'worktree.fileInvalidated' &&
		matchedReplacementDescriptor?.frameKind !== 'worktree.fileDescriptor'
	) {
		return currentOpenFileState;
	}
	if (
		isFrameForCurrentDescriptorVersion({
			currentDescriptor: currentOpenFileState.descriptor,
			matchedInvalidation,
			matchedReplacementDescriptor,
		})
	) {
		return currentOpenFileState;
	}
	props.openFileRequestIdRef.current += 1;
	return {
		status: 'stale',
		path: currentOpenFileState.path,
		descriptor: currentOpenFileState.descriptor,
	};
}

function isFrameForCurrentDescriptorVersion(props: {
	readonly currentDescriptor: WorktreeFileDescriptor;
	readonly matchedInvalidation: WorktreeFileProtocolFrame | undefined;
	readonly matchedReplacementDescriptor: WorktreeFileProtocolFrame | undefined;
}): boolean {
	if (
		props.matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
		areWorktreeFileDescriptorsSameContentVersion(
			props.matchedReplacementDescriptor.descriptor,
			props.currentDescriptor,
		)
	) {
		return true;
	}
	return (
		props.matchedInvalidation?.frameKind === 'worktree.fileInvalidated' &&
		props.matchedInvalidation.invalidation.latestDescriptor !== undefined &&
		areWorktreeFileDescriptorsSameContentVersion(
			props.matchedInvalidation.invalidation.latestDescriptor,
			props.currentDescriptor,
		)
	);
}

function areWorktreeFileDescriptorsSameContentVersion(
	left: WorktreeFileDescriptor,
	right: WorktreeFileDescriptor,
): boolean {
	return (
		left.fileId === right.fileId &&
		left.path === right.path &&
		left.contentHandle === right.contentHandle &&
		left.contentHash === right.contentHash &&
		left.contentDescriptor.ref.descriptorId === right.contentDescriptor.ref.descriptorId &&
		left.contentDescriptor.ref.expectedIdentity.cursor ===
			right.contentDescriptor.ref.expectedIdentity.cursor
	);
}

function findLatestDescriptorForOpenFile(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly renderState: BridgeFileViewerRenderState;
}): WorktreeFileDescriptor | null {
	return (
		props.renderState.descriptors.find(
			(descriptor) =>
				descriptor.fileId === props.descriptor.fileId || descriptor.path === props.descriptor.path,
		) ?? null
	);
}

function totalTreeHeightForSizeFacts(props: {
	readonly filteredDescriptorCount: number;
	readonly filteredTreeRowCount: number;
	readonly hasActiveProjection: boolean;
	readonly sizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
	readonly totalDescriptorCount: number;
}): {
	readonly heightPixels: number | null;
	readonly source: 'localProjection' | 'providerFacts' | null;
} {
	if (props.sizeFacts === null) {
		return { heightPixels: null, source: null };
	}
	if (!props.hasActiveProjection && props.sizeFacts.estimatedTotalHeightPixels !== undefined) {
		return { heightPixels: props.sizeFacts.estimatedTotalHeightPixels, source: 'providerFacts' };
	}
	if (
		props.hasActiveProjection &&
		props.filteredDescriptorCount === props.totalDescriptorCount &&
		props.sizeFacts.estimatedTotalHeightPixels !== undefined
	) {
		return { heightPixels: props.sizeFacts.estimatedTotalHeightPixels, source: 'providerFacts' };
	}
	return {
		heightPixels: Math.max(1, props.filteredTreeRowCount) * props.sizeFacts.rowHeightPixels,
		source: 'localProjection',
	};
}

function totalOpenFileHeightForState(openFileState: BridgeFileViewerOpenState): number | null {
	if (openFileState.status === 'idle') {
		return null;
	}
	const descriptor = openFileState.descriptor;
	if (descriptor.isBinary) {
		return null;
	}
	switch (descriptor.virtualizedExtentKind) {
		case 'exactLineCount':
			return descriptor.lineCount === undefined
				? null
				: descriptor.lineCount * defaultFileLineHeightPixels + pierreCodeViewFileChromeHeightPixels;
		case 'estimatedHeight':
			return descriptor.estimatedContentHeightPixels ?? null;
		case 'previewBounded':
		case 'unavailable':
			return null;
	}
	return null;
}

async function defaultFetchWorktreeFileResource(
	props: WorktreeFileSurfaceRuntimeFetchResourceProps,
): Promise<string> {
	const response = await fetch(props.resourceUrl, { signal: props.signal });
	if (!response.ok) {
		throw new Error(`Worktree/File resource request failed: ${response.status}`);
	}
	return await response.text();
}
