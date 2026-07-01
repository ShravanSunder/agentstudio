import { useEffect, useRef } from 'react';

import type {
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	WorktreeFileInitialSurface,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import type {
	BridgeFileViewerInitialSurfaceLoadState,
	BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerInitialSurfaceLoaderProps {
	readonly applyIncomingFrames: (
		frames: readonly WorktreeFileProtocolFrame[],
		surface?: {
			readonly provenance: WorktreeFileSurfaceProvenance | null;
			readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
		},
	) => BridgeFileViewerRenderState;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly setInitialSurfaceLoadState: (state: BridgeFileViewerInitialSurfaceLoadState) => void;
	readonly waitForBridgeReady?: (callback: () => void) => () => void;
}

export function useBridgeFileViewerInitialSurfaceLoader(
	props: UseBridgeFileViewerInitialSurfaceLoaderProps,
): void {
	const applyIncomingFramesRef = useRef(props.applyIncomingFrames);
	const initialFramesRef = useRef(props.initialFrames);
	const loadInitialFramesRef = useRef(props.loadInitialFrames);
	const loadInitialSurfaceRef = useRef(props.loadInitialSurface);
	const setInitialSurfaceLoadStateRef = useRef(props.setInitialSurfaceLoadState);
	const waitForBridgeReadyRef = useRef(props.waitForBridgeReady);
	applyIncomingFramesRef.current = props.applyIncomingFrames;
	initialFramesRef.current = props.initialFrames;
	loadInitialFramesRef.current = props.loadInitialFrames;
	loadInitialSurfaceRef.current = props.loadInitialSurface;
	setInitialSurfaceLoadStateRef.current = props.setInitialSurfaceLoadState;
	waitForBridgeReadyRef.current = props.waitForBridgeReady;

	useEffect((): (() => void) => {
		let isCancelled = false;
		let didStartLoad = false;
		const loadFrames = async (): Promise<void> => {
			setInitialSurfaceLoadStateRef.current({ status: 'loading' });
			try {
				const currentInitialFrames = initialFramesRef.current;
				const currentLoadInitialFrames = loadInitialFramesRef.current;
				const currentLoadInitialSurface = loadInitialSurfaceRef.current;
				const initialSurface =
					currentInitialFrames !== undefined
						? { frames: currentInitialFrames }
						: currentLoadInitialSurface === undefined
							? {
									frames:
										currentLoadInitialFrames === undefined ? [] : await currentLoadInitialFrames(),
								}
							: await currentLoadInitialSurface();
				if (isCancelled) {
					return;
				}
				applyIncomingFramesRef.current(initialSurface.frames, {
					provenance: initialSurface.provenance ?? null,
					sourceIdentity: initialSurface.source ?? null,
				});
				setInitialSurfaceLoadStateRef.current({ status: 'ready' });
			} catch (error: unknown) {
				if (isCancelled) {
					return;
				}
				setInitialSurfaceLoadStateRef.current({
					status: 'failed',
					reason: error instanceof Error ? error.message : String(error),
				});
			}
		};
		const startLoadFrames = (): void => {
			if (didStartLoad) {
				return;
			}
			didStartLoad = true;
			void loadFrames();
		};
		const currentWaitForBridgeReady = waitForBridgeReadyRef.current;
		const unregisterBridgeReady = currentWaitForBridgeReady?.(startLoadFrames);
		if (currentWaitForBridgeReady === undefined) {
			startLoadFrames();
		}
		return (): void => {
			isCancelled = true;
			unregisterBridgeReady?.();
		};
	}, []);
}
