import {
	useCallback,
	useEffect,
	useRef,
	useState,
	type MutableRefObject,
	type ReactElement,
} from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	createWorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
} from './worktree-file-surface-runtime.js';

export interface WorktreeFileAppProps {
	readonly fetchResource?: (props: WorktreeFileSurfaceRuntimeFetchResourceProps) => Promise<string>;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
}

interface WorktreeFileSurfaceRenderState {
	readonly descriptors: readonly WorktreeFileDescriptor[];
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
			readonly status: 'failed';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'unavailable';
	  };

const defaultPaneId = 'bridge-worktree-dev-pane';
const defaultFileLineHeightPixels = 20;
const initialRenderState: WorktreeFileSurfaceRenderState = {
	descriptors: [],
	treeSizeFacts: null,
};

export function WorktreeFileApp({
	fetchResource,
	initialFrames,
	loadInitialFrames,
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

	if (runtimeRef.current === null) {
		runtimeRef.current = createWorktreeFileSurfaceRuntime({
			paneId: defaultPaneId,
			fetchResource: fetchResource ?? defaultFetchWorktreeFileResource,
		});
	}

	useEffect((): (() => void) => {
		let isCancelled = false;
		const loadFrames = async (): Promise<void> => {
			const frames =
				initialFrames ?? (loadInitialFrames === undefined ? [] : await loadInitialFrames());
			if (isCancelled) {
				return;
			}
			const nextState = applyFramesToRuntime({
				currentRenderState: renderStateRef.current,
				frames,
				runtime: runtimeRef.current,
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
		};
		void loadFrames();
		return (): void => {
			isCancelled = true;
		};
	}, [initialFrames, loadInitialFrames]);

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
			openFileBodyRef.current = result.body;
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
		const result = await runtime.refreshOpenFile({
			openFileSessionId: state.descriptor.fileId,
		});
		if (openFileRequestIdRef.current !== requestId) {
			return;
		}
		if (result.ok) {
			openFileBodyRef.current = result.body;
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

	const totalTreeHeightPixels = totalTreeHeightForSizeFacts(renderState.treeSizeFacts);
	const totalOpenFileHeightPixels = totalOpenFileHeightForState(openFileState);
	const openFileBody =
		openFileState.status === 'ready' || openFileState.status === 'stale'
			? openFileBodyRef.current
			: null;
	return (
		<main className="bridge-worktree-file-app" data-testid="worktree-file-app">
			<section
				className="bridge-worktree-file-tree"
				data-testid="worktree-file-tree"
				style={{ maxHeight: 320, overflow: 'auto' }}
				{...(totalTreeHeightPixels === null
					? {}
					: { 'data-worktree-tree-total-size': String(totalTreeHeightPixels) })}
			>
				<div
					data-testid="worktree-file-tree-extent"
					style={totalTreeHeightPixels === null ? undefined : { minHeight: totalTreeHeightPixels }}
				>
					{renderState.descriptors.map((descriptor) => (
						<button
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
			<section
				className="bridge-worktree-file-content"
				data-testid="worktree-file-content"
				style={{ maxHeight: 320, overflow: 'auto' }}
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
					{openFileState.status === 'stale' ? (
						<div data-testid="worktree-file-content-stale">
							Content changed
							<button
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

function applyFramesToRuntime(props: {
	readonly currentRenderState: WorktreeFileSurfaceRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly runtime: WorktreeFileSurfaceRuntime | null;
}): WorktreeFileSurfaceRenderState {
	const descriptorsByFileId = new Map(
		props.currentRenderState.descriptors.map((descriptor) => [descriptor.fileId, descriptor]),
	);
	let treeSizeFacts = props.currentRenderState.treeSizeFacts;
	for (const frame of props.frames) {
		props.runtime?.applyFrame(frame);
		if (frame.frameKind === 'worktree.snapshot' || frame.frameKind === 'worktree.treeWindow') {
			treeSizeFacts = frame.treeSizeFacts ?? treeSizeFacts;
		}
		if (frame.frameKind === 'worktree.fileDescriptor') {
			descriptorsByFileId.set(frame.descriptor.fileId, frame.descriptor);
		}
		if (frame.frameKind === 'worktree.fileInvalidated') {
			const latestDescriptor = frame.invalidation.latestDescriptor;
			if (latestDescriptor !== undefined) {
				descriptorsByFileId.set(latestDescriptor.fileId, latestDescriptor);
			}
		}
		if (frame.frameKind === 'worktree.reset') {
			descriptorsByFileId.clear();
			treeSizeFacts = null;
		}
	}
	return { descriptors: [...descriptorsByFileId.values()], treeSizeFacts };
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

function totalTreeHeightForSizeFacts(
	treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null,
): number | null {
	if (treeSizeFacts === null) {
		return null;
	}
	if (treeSizeFacts.pathCount !== undefined) {
		return treeSizeFacts.pathCount * treeSizeFacts.rowHeightPixels;
	}
	return treeSizeFacts.estimatedTotalHeightPixels ?? null;
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
): Promise<string> {
	const response = await fetch(props.resourceUrl, { signal: props.signal });
	if (!response.ok) {
		throw new Error(`Worktree/File resource request failed: ${response.status}`);
	}
	return await response.text();
}
