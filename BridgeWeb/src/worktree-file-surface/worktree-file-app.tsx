import {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type MutableRefObject,
	type ReactElement,
} from 'react';

import { loadBridgeTextResourceWithTiming } from '../core/resources/bridge-resource-stream.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	bridgeFileViewerHasActiveCommentDraft,
	bridgeFileViewerStaleAutoRefreshCoalesceMilliseconds,
	shouldAutoRefreshStaleOpenFile,
} from '../file-viewer/bridge-file-viewer-stale-refresh-policy.js';
import {
	createWorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntimeFetchedResource,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
} from './worktree-file-surface-runtime.js';

export interface WorktreeFileAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly fetchResource?: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
}

export interface WorktreeFileInitialSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance?: WorktreeFileSurfaceProvenance;
	readonly source?: WorktreeFileSurfaceSourceIdentity;
}

export interface WorktreeFileSurfaceProvenance {
	readonly baseRef: string;
	readonly scenarioName: string;
	readonly worktreeRootToken: string;
}

export type WorktreeFileFrameSubscriber = (frames: readonly WorktreeFileProtocolFrame[]) => void;

export type WorktreeFileFrameSubscriptionDispose = () => void;

export type WorktreeFileFrameSubscriptionFactory = (
	subscriber: WorktreeFileFrameSubscriber,
) => WorktreeFileFrameSubscriptionDispose;

interface WorktreeFileSurfaceRenderState {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly provenance: WorktreeFileSurfaceProvenance | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}

type WorktreeFileOpenRenderState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly status: 'loading';
			readonly path: string;
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'ready';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'stale';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'refreshing';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'unavailable';
	  };

type WorktreeFileFilterMode = 'all' | 'fetchable' | 'unavailable';

const defaultPaneId = 'bridge-worktree-dev-pane';
const defaultFileLineHeightPixels = 20;
const initialRenderState: WorktreeFileSurfaceRenderState = {
	descriptors: [],
	provenance: null,
	sourceIdentity: null,
	treeSizeFacts: null,
};

export function WorktreeFileApp({
	autoOpenInitialFile = false,
	fetchResource,
	initialFrames,
	loadInitialSurface,
	loadInitialFrames,
	subscribeFrames,
}: WorktreeFileAppProps = {}): ReactElement {
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const openFileBodyRef = useRef<string | null>(null);
	const openFileRequestIdRef = useRef(0);
	const renderStateRef = useRef<WorktreeFileSurfaceRenderState>(initialRenderState);
	const [renderState, setRenderState] =
		useState<WorktreeFileSurfaceRenderState>(initialRenderState);
	const [openFileState, setOpenFileState] = useState<WorktreeFileOpenRenderState>({
		status: 'idle',
	});
	const [searchText, setSearchText] = useState('');
	const [searchMode, setSearchMode] = useState<'text' | 'regex'>('text');
	const [filterMode, setFilterMode] = useState<WorktreeFileFilterMode>('all');
	const [initialSurfaceLoadError, setInitialSurfaceLoadError] = useState<string | null>(null);

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
			if (openFileRequestIdRef.current !== requestId) {
				return;
			}
			setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
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
			openFileBodyRef.current = result.content.readText();
			setOpenFileState({
				status: 'ready',
				path: descriptor.path,
				descriptor,
			});
			return;
		}
		openFileBodyRef.current = null;
		if (result.reason === 'content_unavailable') {
			setOpenFileState({ status: 'unavailable', path: descriptor.path, descriptor });
			return;
		}
		setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
	}, []);

	const applyIncomingFrames = useCallback(
		(
			frames: readonly WorktreeFileProtocolFrame[],
			surface?: {
				readonly provenance: WorktreeFileSurfaceProvenance | null;
				readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
			},
		): WorktreeFileSurfaceRenderState => {
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
			// A hard-failed native open (e.g. during a git-status storm) must
			// land as a visible surface state, not an unhandled rejection.
			let initialSurface: WorktreeFileInitialSurface;
			try {
				initialSurface =
					initialFrames !== undefined
						? { frames: initialFrames }
						: loadInitialSurface === undefined
							? { frames: loadInitialFrames === undefined ? [] : await loadInitialFrames() }
							: await loadInitialSurface();
			} catch (error) {
				if (isCancelled) {
					return;
				}
				setInitialSurfaceLoadError(error instanceof Error ? error.message : String(error));
				return;
			}
			if (isCancelled) {
				return;
			}
			setInitialSurfaceLoadError(null);
			const nextState = applyIncomingFrames(initialSurface.frames, {
				provenance: initialSurface.provenance ?? null,
				sourceIdentity: initialSurface.source ?? null,
			});
			if (autoOpenInitialFile && openFileRequestIdRef.current === 0) {
				const initialDescriptor = nextState.descriptors.find(
					(descriptor) => !descriptor.isBinary && descriptor.contentDescriptor !== null,
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

	useEffect((): WorktreeFileFrameSubscriptionDispose | undefined => {
		if (subscribeFrames === undefined) {
			return undefined;
		}
		return subscribeFrames((frames) => {
			applyIncomingFrames(frames);
		});
	}, [applyIncomingFrames, subscribeFrames]);

	const refreshOpenFile = useCallback(async (state: WorktreeFileOpenRenderState): Promise<void> => {
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
			openFileBodyRef.current = result.content.readText();
			setOpenFileState({
				status: 'ready',
				path: state.path,
				descriptor: state.descriptor,
			});
			return;
		}
		if (result.reason === 'content_unavailable') {
			openFileBodyRef.current = null;
			setOpenFileState({ status: 'unavailable', path: state.path, descriptor: state.descriptor });
			return;
		}
		setOpenFileState({ status: 'failed', path: state.path, descriptor: state.descriptor });
	}, []);

	useEffect((): (() => void) | undefined => {
		if (openFileState.status !== 'stale') {
			return undefined;
		}
		if (
			!shouldAutoRefreshStaleOpenFile({
				hasActiveCommentDraft: bridgeFileViewerHasActiveCommentDraft,
			})
		) {
			return undefined;
		}
		const coalesceTimeout = setTimeout((): void => {
			void refreshOpenFile(openFileState);
		}, bridgeFileViewerStaleAutoRefreshCoalesceMilliseconds);
		return (): void => {
			clearTimeout(coalesceTimeout);
		};
	}, [openFileState, refreshOpenFile]);

	const descriptorProjection = useMemo(
		() =>
			projectWorktreeFileDescriptors({
				descriptors: renderState.descriptors,
				filterMode,
				searchMode,
				searchText,
			}),
		[filterMode, renderState.descriptors, searchMode, searchText],
	);
	const totalTreeHeightPixels = totalTreeHeightForSizeFacts({
		hasActiveProjection:
			filterMode !== 'all' ||
			searchText.trim().length > 0 ||
			descriptorProjection.searchError !== null,
		filteredDescriptorCount: descriptorProjection.descriptors.length,
		sizeFacts: renderState.treeSizeFacts,
	});
	const totalOpenFileHeightPixels = totalOpenFileHeightForState(openFileState);
	const openFileBody =
		openFileState.status === 'ready' ||
		openFileState.status === 'stale' ||
		openFileState.status === 'refreshing'
			? openFileBodyRef.current
			: null;
	return (
		<main
			className="bridge-worktree-file-app"
			data-testid="worktree-file-app"
			{...(renderState.sourceIdentity === null
				? initialSurfaceLoadError === null
					? {}
					: { 'data-worktree-source-state': 'failed' }
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
			<aside className="bridge-worktree-file-sidebar">
				<header className="bridge-worktree-file-toolbar" data-testid="worktree-file-toolbar">
					<input
						aria-label="Search files"
						className="bridge-worktree-file-search-input"
						data-testid="worktree-file-search-input"
						onChange={(event) => {
							setSearchText(event.currentTarget.value);
						}}
						placeholder="Search files"
						spellCheck={false}
						type="search"
						value={searchText}
					/>
					<button
						aria-pressed={searchMode === 'regex'}
						className="bridge-worktree-file-toolbar-button"
						data-testid="worktree-file-regex-toggle"
						onClick={() => {
							setSearchMode((currentSearchMode) =>
								currentSearchMode === 'regex' ? 'text' : 'regex',
							);
						}}
						title={searchMode === 'regex' ? 'Use text search' : 'Use regex search'}
						type="button"
					>
						.*
					</button>
					<div className="bridge-worktree-file-filter-group" role="group">
						<WorktreeFileFilterButton
							filterMode="all"
							isActive={filterMode === 'all'}
							label="All"
							onSelect={setFilterMode}
						/>
						<WorktreeFileFilterButton
							filterMode="fetchable"
							isActive={filterMode === 'fetchable'}
							label="Text"
							onSelect={setFilterMode}
						/>
						<WorktreeFileFilterButton
							filterMode="unavailable"
							isActive={filterMode === 'unavailable'}
							label="Unavailable"
							onSelect={setFilterMode}
						/>
					</div>
					<div
						className="bridge-worktree-file-query-status"
						data-testid="worktree-file-filter-status"
					>
						{descriptorProjection.searchError === null
							? `${descriptorProjection.descriptors.length}/${renderState.descriptors.length}`
							: 'Invalid regex'}
					</div>
					<div
						className="bridge-worktree-file-provenance"
						data-testid="worktree-file-provenance"
						{...(initialSurfaceLoadError === null ? {} : { title: initialSurfaceLoadError })}
					>
						{renderState.sourceIdentity === null || renderState.provenance === null
							? initialSurfaceLoadError === null
								? 'Source pending'
								: 'Source load failed'
							: `${renderState.provenance.scenarioName} · ${renderState.sourceIdentity.sourceId}`}
					</div>
				</header>
				<section
					className="bridge-worktree-file-tree bridge-scrollbar"
					data-testid="worktree-file-tree"
					{...(totalTreeHeightPixels === null
						? {}
						: { 'data-worktree-tree-total-size': String(totalTreeHeightPixels) })}
				>
					<div
						className="bridge-worktree-file-tree-extent"
						data-testid="worktree-file-tree-extent"
						style={
							totalTreeHeightPixels === null ? undefined : { minHeight: totalTreeHeightPixels }
						}
					>
						{descriptorProjection.descriptors.map((descriptor) => (
							<button
								className="bridge-worktree-file-tree-row"
								data-worktree-file-path={descriptor.path}
								key={descriptor.fileId}
								onClick={() => {
									void openFile(descriptor);
								}}
								type="button"
							>
								{descriptor.path}
							</button>
						))}
					</div>
				</section>
			</aside>
			<section
				className="bridge-worktree-file-content bridge-scrollbar"
				data-testid="worktree-file-content"
				{...(openFileState.status === 'idle'
					? {}
					: {
							'data-worktree-open-file-path': openFileState.path,
							'data-worktree-open-file-state': openFileState.status,
						})}
				{...(totalOpenFileHeightPixels === null
					? {}
					: { 'data-worktree-open-file-total-size': String(totalOpenFileHeightPixels) })}
			>
				<div
					className="bridge-worktree-file-content-extent"
					data-testid="worktree-file-content-extent"
					style={
						totalOpenFileHeightPixels === null
							? undefined
							: { minHeight: totalOpenFileHeightPixels }
					}
				>
					{openFileBody === null ? null : (
						<pre
							style={{
								lineHeight: `${defaultFileLineHeightPixels}px`,
								margin: 0,
								whiteSpace: 'pre',
							}}
						>
							{openFileBody}
						</pre>
					)}
					{openFileState.status === 'stale' &&
					!shouldAutoRefreshStaleOpenFile({
						hasActiveCommentDraft: bridgeFileViewerHasActiveCommentDraft,
					}) ? (
						<div
							className="bridge-worktree-file-stale-notice"
							data-testid="worktree-file-content-stale"
						>
							<span>Content changed</span>
							<button
								className="bridge-worktree-file-toolbar-button"
								data-testid="worktree-file-refresh"
								onClick={() => {
									void refreshOpenFile(openFileState);
								}}
								type="button"
							>
								Refresh
							</button>
						</div>
					) : null}
					{openFileState.status === 'unavailable' ? (
						<div data-testid="worktree-file-content-unavailable">Content unavailable</div>
					) : null}
				</div>
			</section>
		</main>
	);
}

interface WorktreeFileFilterButtonProps {
	readonly filterMode: WorktreeFileFilterMode;
	readonly isActive: boolean;
	readonly label: string;
	readonly onSelect: (filterMode: WorktreeFileFilterMode) => void;
}

function WorktreeFileFilterButton(props: WorktreeFileFilterButtonProps): ReactElement {
	return (
		<button
			aria-pressed={props.isActive}
			className="bridge-worktree-file-toolbar-button"
			data-testid={`worktree-file-filter-${props.filterMode}`}
			onClick={() => {
				props.onSelect(props.filterMode);
			}}
			type="button"
		>
			{props.label}
		</button>
	);
}

interface WorktreeFileDescriptorProjection {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly searchError: string | null;
}

function projectWorktreeFileDescriptors(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly filterMode: WorktreeFileFilterMode;
	readonly searchMode: 'text' | 'regex';
	readonly searchText: string;
}): WorktreeFileDescriptorProjection {
	const trimmedSearchText = props.searchText.trim();
	const searchPattern =
		trimmedSearchText.length === 0
			? null
			: makeWorktreeFileSearchPattern({
					searchMode: props.searchMode,
					searchText: trimmedSearchText,
				});
	if (searchPattern?.ok === false) {
		return { descriptors: [], searchError: searchPattern.message };
	}
	const descriptors = props.descriptors.filter((descriptor) => {
		if (!descriptorMatchesFilterMode({ descriptor, filterMode: props.filterMode })) {
			return false;
		}
		if (searchPattern === null) {
			return true;
		}
		return searchPattern.pattern.test(descriptor.path);
	});
	return { descriptors, searchError: null };
}

function descriptorMatchesFilterMode(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly filterMode: WorktreeFileFilterMode;
}): boolean {
	switch (props.filterMode) {
		case 'all':
			return true;
		case 'fetchable':
			return !props.descriptor.isBinary && props.descriptor.contentDescriptor !== null;
		case 'unavailable':
			return props.descriptor.isBinary || props.descriptor.virtualizedExtentKind === 'unavailable';
	}
	return false;
}

type WorktreeFileSearchPattern =
	| { readonly ok: true; readonly pattern: RegExp }
	| { readonly ok: false; readonly message: string };

function makeWorktreeFileSearchPattern(props: {
	readonly searchMode: 'text' | 'regex';
	readonly searchText: string;
}): WorktreeFileSearchPattern {
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
	readonly currentRenderState: WorktreeFileSurfaceRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance?: WorktreeFileSurfaceProvenance | null;
	readonly runtime: WorktreeFileSurfaceRuntime | null;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity | null;
}): WorktreeFileSurfaceRenderState {
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
	readonly currentOpenFileState: WorktreeFileOpenRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
}): WorktreeFileOpenRenderState {
	if (props.currentOpenFileState.status === 'idle') {
		return props.currentOpenFileState;
	}
	const currentOpenFileState = props.currentOpenFileState;
	const resetFrame = props.frames.find((frame) => frame.frameKind === 'worktree.reset');
	if (resetFrame !== undefined) {
		const replacementDescriptor = props.frames
			.filter((frame) => frame.frameKind === 'worktree.fileDescriptor')
			.map((frame) => frame.descriptor)
			.find(
				(descriptor) =>
					descriptor.fileId === currentOpenFileState.descriptor.fileId ||
					descriptor.path === currentOpenFileState.path,
			);
		props.openFileRequestIdRef.current += 1;
		return replacementDescriptor === undefined
			? {
					status: 'unavailable',
					path: currentOpenFileState.path,
					descriptor: currentOpenFileState.descriptor,
				}
			: {
					status: 'stale',
					path: replacementDescriptor.path,
					descriptor: replacementDescriptor,
				};
	}
	const matchedInvalidation = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileInvalidated' &&
			(frame.invalidation.fileId === currentOpenFileState.descriptor.fileId ||
				frame.invalidation.path === currentOpenFileState.path),
	);
	if (matchedInvalidation?.frameKind !== 'worktree.fileInvalidated') {
		return currentOpenFileState;
	}
	props.openFileRequestIdRef.current += 1;
	return {
		status: 'stale',
		path: currentOpenFileState.path,
		descriptor:
			matchedInvalidation.invalidation.latestDescriptor ?? currentOpenFileState.descriptor,
	};
}

function totalTreeHeightForSizeFacts(props: {
	readonly filteredDescriptorCount: number;
	readonly hasActiveProjection: boolean;
	readonly sizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}): number | null {
	if (props.sizeFacts === null) {
		return null;
	}
	if (!props.hasActiveProjection && props.sizeFacts.pathCount !== undefined) {
		return props.sizeFacts.pathCount * props.sizeFacts.rowHeightPixels;
	}
	return Math.max(1, props.filteredDescriptorCount) * props.sizeFacts.rowHeightPixels;
}

function totalOpenFileHeightForState(openFileState: WorktreeFileOpenRenderState): number | null {
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
				: descriptor.lineCount * defaultFileLineHeightPixels;
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
): Promise<WorktreeFileSurfaceRuntimeFetchedResource> {
	return await loadBridgeTextResourceWithTiming({
		integrity: props.descriptor.content.integrity,
		maxBytes: props.descriptor.content.maxBytes,
		onTextChunk: props.onTextChunk,
		performFetch: async (): Promise<Response> =>
			await fetch(props.resourceUrl, { signal: props.signal }),
		probe: props.probe,
		signal: props.signal,
	});
}
