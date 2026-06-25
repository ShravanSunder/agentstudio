import { RefreshCwIcon } from 'lucide-react';
import {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type MutableRefObject,
	type ReactElement,
} from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import { BridgeFileViewerCodePanel } from '../review-viewer/code-view/bridge-file-viewer-code-panel.js';
import {
	BridgeFileViewerTreePanel,
	type BridgeFileViewerDescriptorProjection,
	type BridgeFileViewerFilterMode,
	type BridgeFileViewerSearchMode,
} from '../review-viewer/trees/bridge-file-viewer-tree-panel.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileInitialSurface,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import {
	createWorktreeFileSurfaceRuntime,
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
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
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
		subscribeFrames,
	} = props;
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const openFileBodyRef = useRef<string | null>(null);
	const openFileRequestIdRef = useRef(0);
	const renderStateRef = useRef<BridgeFileViewerRenderState>(emptyRenderState);
	const [renderState, setRenderState] = useState<BridgeFileViewerRenderState>(emptyRenderState);
	const [openFileState, setOpenFileState] = useState<BridgeFileViewerOpenState>({
		status: 'idle',
	});
	const [searchText, setSearchText] = useState('');
	const [searchMode, setSearchMode] = useState<BridgeFileViewerSearchMode>('text');
	const [filterMode, setFilterMode] = useState<BridgeFileViewerFilterMode>('all');
	const selectedPath = openFileState.status === 'idle' ? null : openFileState.path;
	const fileDescriptorByPath = useMemo(
		(): ReadonlyMap<string, WorktreeFileDescriptor> =>
			new Map(renderState.descriptors.map((descriptor) => [descriptor.path, descriptor])),
		[renderState.descriptors],
	);

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
			setOpenFileState({ status: 'ready', path: descriptor.path, descriptor });
			return;
		}
		openFileBodyRef.current = null;
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
				const initialDescriptor = nextState.descriptors.find((descriptor) =>
					canFetchDescriptorContent(descriptor),
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

	const refreshOpenFile = useCallback(async (state: BridgeFileViewerOpenState): Promise<void> => {
		if (state.status !== 'stale') {
			return;
		}
		const requestId = openFileRequestIdRef.current + 1;
		openFileRequestIdRef.current = requestId;
		const runtime = runtimeRef.current;
		if (runtime === null) {
			if (openFileRequestIdRef.current === requestId) {
				setOpenFileState({ status: 'failed', path: state.path, descriptor: state.descriptor });
			}
			return;
		}
		setOpenFileState({
			status: 'refreshing',
			path: state.path,
			descriptor: state.descriptor,
		});
		const result = await runtime.refreshOpenFile({
			openFileSessionId: state.descriptor.fileId,
		});
		if (openFileRequestIdRef.current !== requestId) {
			return;
		}
		if (result.ok) {
			openFileBodyRef.current = result.body;
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
		setOpenFileState({
			status: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
			path: state.path,
			descriptor: state.descriptor,
		});
	}, []);

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
	const openFileTotalHeightPixels = totalOpenFileHeightForState(openFileState);

	return (
		<main
			className="flex h-screen min-h-screen w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)]"
			data-file-viewer-owner="BridgeViewerApp.FileViewer"
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
				<BridgeFileViewerCodePanel
					openFileBody={openFileBody}
					openFileState={openFileState}
					staleNotice={
						openFileState.status === 'stale' ? (
							<BridgeFileViewerStaleNotice
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
				<BridgeFileViewerTreePanel
					descriptorProjection={descriptorProjection}
					fileDescriptorByPath={fileDescriptorByPath}
					filterMode={filterMode}
					onFilterModeChange={setFilterMode}
					onOpenFile={openFile}
					onSearchModeChange={setSearchMode}
					onSearchTextChange={setSearchText}
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

function BridgeFileViewerStaleNotice(props: { readonly onRefresh: () => void }): ReactElement {
	return (
		<div
			className="absolute right-3 top-3 z-10 flex items-center gap-2 rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-menu-bg)] px-3 py-2 text-xs shadow-lg"
			data-testid="worktree-file-content-stale"
		>
			<span>Content changed</span>
			<button
				className="inline-flex items-center gap-1 rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2 py-1"
				data-testid="worktree-file-refresh"
				onClick={props.onRefresh}
				type="button"
			>
				<RefreshCwIcon aria-hidden="true" size={12} />
				Refresh
			</button>
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
			return canFetchDescriptorContent(props.descriptor);
		case 'unavailable':
			return props.descriptor.isBinary || props.descriptor.virtualizedExtentKind === 'unavailable';
	}
	return false;
}

function canFetchDescriptorContent(descriptor: WorktreeFileDescriptor): boolean {
	return !descriptor.isBinary && descriptor.virtualizedExtentKind !== 'unavailable';
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
	props.openFileRequestIdRef.current += 1;
	return {
		status: 'stale',
		path: currentOpenFileState.path,
		descriptor: currentOpenFileState.descriptor,
	};
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
