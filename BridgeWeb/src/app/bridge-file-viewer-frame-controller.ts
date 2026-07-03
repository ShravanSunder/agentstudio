import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { WorktreeFileProtocolFrame } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerAppProps } from '../file-viewer/bridge-file-viewer-app.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';

interface UseBridgeFileViewerFrameControllerProps {
	readonly enabled: boolean;
	readonly fileViewerProps: BridgeFileViewerAppProps | undefined;
	readonly waitForBridgeReady: (callback: () => void) => () => void;
	/// Bumped when the file surface must re-run its full open announce — a mode
	/// switch re-activates the file shell but the WebView never remounts, so
	/// without this the surface would never re-issue `openSourceStream` and a
	/// wedged (or stale-identity) stream could never recover.
	readonly reopenSignal?: number;
	/// Fired once a surface open resolves. The re-activation owner uses this as
	/// the liveness signal so a live healthy stream is NOT re-opened on every
	/// switch — only a never-resolved (wedged/hung) surface re-opens to recover.
	readonly onSurfaceOpenResolved?: () => void;
}

interface BridgeFileViewerBufferedSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance: WorktreeFileInitialSurface['provenance'] | null;
	readonly source: WorktreeFileInitialSurface['source'] | null;
}

const emptyBufferedSurface: BridgeFileViewerBufferedSurface = {
	frames: [],
	provenance: null,
	source: null,
};

export function useBridgeFileViewerFrameControllerProps(
	props: UseBridgeFileViewerFrameControllerProps,
): BridgeFileViewerAppProps | undefined {
	const { enabled, fileViewerProps, onSurfaceOpenResolved, reopenSignal, waitForBridgeReady } =
		props;
	const fileViewerPropsRef = useRef<BridgeFileViewerAppProps | undefined>(fileViewerProps);
	const listenersRef = useRef<Set<WorktreeFileFrameSubscriber>>(new Set());
	const bufferedSurfaceRef = useRef<BridgeFileViewerBufferedSurface>(emptyBufferedSurface);
	const loadPromiseRef = useRef<Promise<WorktreeFileInitialSurface>>(
		Promise.resolve({ frames: [] }),
	);
	const [loadedVersion, setLoadedVersion] = useState(0);
	fileViewerPropsRef.current = fileViewerProps;
	const initialFrames = fileViewerProps?.initialFrames;
	const loadInitialFrames = fileViewerProps?.loadInitialFrames;
	const loadInitialSurface = fileViewerProps?.loadInitialSurface;
	const subscribeFrames = fileViewerProps?.subscribeFrames;

	const loadBufferedInitialSurface = useCallback(
		async (): Promise<WorktreeFileInitialSurface> => await loadPromiseRef.current,
		[],
	);
	const subscribeBufferedFrames = useCallback(
		(subscriber: WorktreeFileFrameSubscriber): (() => void) => {
			listenersRef.current.add(subscriber);
			return (): void => {
				listenersRef.current.delete(subscriber);
			};
		},
		[],
	);

	useEffect((): (() => void) => {
		if (!enabled) {
			return (): void => {};
		}
		let isCancelled = false;
		let didStartLoad = false;
		let didResolveInitialSurface = false;
		let preLoadFrames: readonly WorktreeFileProtocolFrame[] = [];
		let resolveLoadPromise: (surface: WorktreeFileInitialSurface) => void = () => {};
		let rejectLoadPromise: (error: unknown) => void = () => {};
		bufferedSurfaceRef.current = emptyBufferedSurface;
		loadPromiseRef.current = new Promise<WorktreeFileInitialSurface>((resolve, reject) => {
			resolveLoadPromise = resolve;
			rejectLoadPromise = reject;
		});
		setLoadedVersion((version) => version + 1);

		const publishFrames = (frames: readonly WorktreeFileProtocolFrame[]): void => {
			if (isCancelled || frames.length === 0) {
				return;
			}
			if (!didResolveInitialSurface) {
				preLoadFrames = appendBufferedWorktreeFileFrames(preLoadFrames, frames);
				return;
			}
			bufferedSurfaceRef.current = {
				...bufferedSurfaceRef.current,
				frames: appendBufferedWorktreeFileFrames(bufferedSurfaceRef.current.frames, frames),
			};
			for (const listener of listenersRef.current) {
				listener(frames);
			}
			setLoadedVersion((version) => version + 1);
		};

		const startLoad = (): void => {
			if (didStartLoad) {
				return;
			}
			didStartLoad = true;
			void loadInitialSurfaceForFileViewerProps(fileViewerPropsRef.current)
				.then((surface): void => {
					if (isCancelled) {
						return;
					}
					const mergedSurface: WorktreeFileInitialSurface = {
						...surface,
						frames: appendBufferedWorktreeFileFrames(surface.frames, preLoadFrames),
					};
					didResolveInitialSurface = true;
					preLoadFrames = [];
					bufferedSurfaceRef.current = {
						frames: mergedSurface.frames,
						provenance: mergedSurface.provenance ?? null,
						source: mergedSurface.source ?? null,
					};
					resolveLoadPromise(mergedSurface);
					setLoadedVersion((version) => version + 1);
					onSurfaceOpenResolved?.();
				})
				.catch((error: unknown): void => {
					if (isCancelled) {
						return;
					}
					rejectLoadPromise(error);
				});
		};

		const unsubscribeFrames = subscribeFrames?.(publishFrames);
		const unregisterBridgeReady = waitForBridgeReady(startLoad);

		return (): void => {
			isCancelled = true;
			unsubscribeFrames?.();
			unregisterBridgeReady();
		};
	}, [
		enabled,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		onSurfaceOpenResolved,
		// A bumped reopenSignal re-runs this effect, which resets the buffer and
		// re-issues the surface open — the mode-switch re-announce path.
		reopenSignal,
		subscribeFrames,
		waitForBridgeReady,
	]);

	return useMemo((): BridgeFileViewerAppProps | undefined => {
		if (fileViewerProps === undefined) {
			return undefined;
		}
		const bufferedSurface = bufferedSurfaceRef.current;
		const hasLoadedSurface = loadedVersion > 1 && bufferedSurface.frames.length > 0;
		return {
			...fileViewerProps,
			...(hasLoadedSurface
				? { initialFrames: bufferedSurface.frames }
				: { loadInitialSurface: loadBufferedInitialSurface }),
			subscribeFrames: subscribeBufferedFrames,
		};
	}, [fileViewerProps, loadBufferedInitialSurface, loadedVersion, subscribeBufferedFrames]);
}

function appendBufferedWorktreeFileFrames(
	currentFrames: readonly WorktreeFileProtocolFrame[],
	nextFrames: readonly WorktreeFileProtocolFrame[],
): readonly WorktreeFileProtocolFrame[] {
	const containsAuthoritativeReset = nextFrames.some(
		(frame): boolean =>
			frame.frameKind === 'worktree.reset' || frame.frameKind === 'worktree.snapshot',
	);
	if (containsAuthoritativeReset) {
		return [...nextFrames];
	}
	return [...currentFrames, ...nextFrames];
}

async function loadInitialSurfaceForFileViewerProps(
	fileViewerProps: BridgeFileViewerAppProps | undefined,
): Promise<WorktreeFileInitialSurface> {
	if (fileViewerProps?.initialFrames !== undefined) {
		return { frames: fileViewerProps.initialFrames };
	}
	if (fileViewerProps?.loadInitialSurface !== undefined) {
		return await fileViewerProps.loadInitialSurface();
	}
	if (fileViewerProps?.loadInitialFrames !== undefined) {
		return { frames: await fileViewerProps.loadInitialFrames() };
	}
	return { frames: [] };
}
