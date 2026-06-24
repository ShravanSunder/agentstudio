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
	| { readonly status: 'loading'; readonly path: string }
	| {
			readonly body: string;
			readonly path: string;
			readonly status: 'ready';
	  }
	| { readonly path: string; readonly status: 'failed' };

const defaultPaneId = 'bridge-worktree-dev-pane';

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
		setOpenFileState({ status: 'loading', path: descriptor.path });
		const runtime = runtimeRef.current;
		if (runtime === null) {
			setOpenFileState({ status: 'failed', path: descriptor.path });
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
			});
			return;
		}
		setOpenFileState({ status: 'failed', path: descriptor.path });
	}, []);

	const totalTreeHeightPixels = totalTreeHeightForSizeFacts(renderState.treeSizeFacts);
	return (
		<main className="bridge-worktree-file-app" data-testid="worktree-file-app">
			<section
				className="bridge-worktree-file-tree"
				data-testid="worktree-file-tree"
				{...(totalTreeHeightPixels === null
					? {}
					: { 'data-worktree-tree-total-size': String(totalTreeHeightPixels) })}
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
			</section>
			<section
				className="bridge-worktree-file-content"
				data-testid="worktree-file-content"
				{...(openFileState.status === 'idle'
					? {}
					: {
							'data-worktree-open-file-path': openFileState.path,
							'data-worktree-open-file-state': openFileState.status,
						})}
			>
				{openFileState.status === 'ready' ? <pre>{openFileState.body}</pre> : null}
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

async function defaultFetchWorktreeFileResource(
	props: WorktreeFileSurfaceRuntimeFetchResourceProps,
): Promise<string> {
	const response = await fetch(props.resourceUrl, { signal: props.signal });
	if (!response.ok) {
		throw new Error(`Worktree/File resource request failed: ${response.status}`);
	}
	return await response.text();
}
