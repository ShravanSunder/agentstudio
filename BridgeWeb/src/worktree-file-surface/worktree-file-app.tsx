import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';

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
			readonly body: string;
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'ready';
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

export function WorktreeFileApp({
	fetchResource,
	initialFrames,
	loadInitialFrames,
}: WorktreeFileAppProps = {}): ReactElement {
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const [renderState, setRenderState] = useState<WorktreeFileSurfaceRenderState>({
		descriptors: [],
		treeSizeFacts: null,
	});
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
				frames,
				runtime: runtimeRef.current,
			});
			setRenderState(nextState);
		};
		void loadFrames();
		return (): void => {
			isCancelled = true;
		};
	}, [initialFrames, loadInitialFrames]);

	const openFile = useCallback(async (descriptor: WorktreeFileDescriptor): Promise<void> => {
		setOpenFileState({ status: 'loading', path: descriptor.path, descriptor });
		const runtime = runtimeRef.current;
		if (runtime === null) {
			setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
			return;
		}
		const result = await runtime.openFile({
			descriptor,
			openFileSessionId: descriptor.fileId,
		});
		if (result.ok) {
			setOpenFileState({
				status: 'ready',
				path: descriptor.path,
				body: result.body,
				descriptor,
			});
			return;
		}
		if (result.reason === 'content_unavailable') {
			setOpenFileState({ status: 'unavailable', path: descriptor.path, descriptor });
			return;
		}
		setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
	}, []);

	const totalTreeHeightPixels = totalTreeHeightForSizeFacts(renderState.treeSizeFacts);
	const totalOpenFileHeightPixels = totalOpenFileHeightForState(openFileState);
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
					{openFileState.status === 'ready' ? <pre>{openFileState.body}</pre> : null}
					{openFileState.status === 'unavailable' ? (
						<div data-testid="worktree-file-content-unavailable">Content unavailable</div>
					) : null}
				</div>
			</section>
		</main>
	);
}

function applyFramesToRuntime(props: {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly runtime: WorktreeFileSurfaceRuntime | null;
}): WorktreeFileSurfaceRenderState {
	const descriptors: WorktreeFileDescriptor[] = [];
	let treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null = null;
	for (const frame of props.frames) {
		props.runtime?.applyFrame(frame);
		if (frame.frameKind === 'worktree.snapshot' || frame.frameKind === 'worktree.treeWindow') {
			treeSizeFacts = frame.treeSizeFacts ?? treeSizeFacts;
		}
		if (frame.frameKind === 'worktree.fileDescriptor') {
			descriptors.push(frame.descriptor);
		}
	}
	return { descriptors, treeSizeFacts };
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
