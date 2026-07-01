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
import { z } from 'zod';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import { loadBridgeTextResourceWithTiming } from '../core/resources/bridge-resource-stream.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileDemandStimulus,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import {
	recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample,
	recordBridgeViewerFileOpenReadyTelemetrySample,
	recordBridgeViewerWorktreeFileContentFetchTelemetrySample,
	recordBridgeViewerWorktreeFileTreeTelemetrySample,
} from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
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
	type WorktreeFileSurfaceRuntimeFetchedResource,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeFileViewerAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fetchResource?: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly isActive?: boolean;
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly requestFileDescriptor?: (request: WorktreeFileDescriptorRequest) => Promise<void> | void;
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly viewerHeaderControls?: ReactNode;
	readonly waitForBridgeReady?: (callback: () => void) => () => void;
}

export interface BridgeFileViewerRenderState {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly provenance: WorktreeFileSurfaceProvenance | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}

type BridgeFileViewerInitialSurfaceLoadState =
	| { readonly status: 'idle' | 'loading' | 'ready' }
	| { readonly reason: string; readonly status: 'failed' };

type BridgeFileViewerOpenState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

type BridgeFileViewerActiveOpenState = Exclude<
	BridgeFileViewerOpenState,
	{ readonly status: 'idle' }
>;

interface BridgeFileViewerRenderedOpenFileContent {
	readonly body: string;
	readonly bodyVersion: number;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

interface CommitOpenFileBodyProps {
	readonly body: string;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

interface BridgeFileViewerRefreshDebugState {
	readonly commitState: 'committed' | 'ignored' | 'skipped' | 'started';
	readonly currentRequestId: number;
	readonly descriptorId: string;
	readonly requestId: number;
	readonly result:
		| 'non_stale_state'
		| 'started'
		| 'ok'
		| Extract<WorktreeFileSurfaceLoadResult, { readonly ok: false }>['reason'];
}

type BridgeFileViewerDemandDispatchDebugState =
	| { readonly status: 'idle' }
	| {
			readonly origin:
				| {
						readonly expectedVisibleFileCount: number;
						readonly kind: 'visibleViewport';
				  }
				| {
						readonly descriptorPath: string;
						readonly kind: 'recentlyUpdatedFile';
						readonly openFilePathAfter: string | null;
						readonly openFilePathBefore: string | null;
				  };
			readonly status: 'settled';
			readonly result: WorktreeFileSurfaceDemandDispatchResult;
	  }
	| {
			readonly status: 'failed';
			readonly reason: string;
	  };

interface BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand {
	readonly openFilePathBefore: string | null;
	readonly proximity: 'nearby' | 'remote';
	readonly request: WorktreeFileDescriptorRequest;
	readonly requestId: number;
}

type BridgeFileViewerSearchPattern =
	| { readonly ok: true; readonly pattern: RegExp }
	| { readonly ok: false; readonly message: string };

const bridgeFileViewerRecentlyUpdatedEventName = 'bridge-worktree-file-recently-updated';
const bridgeFileViewerRecentlyUpdatedEventDetailSchema = z
	.object({
		path: z.string().min(1),
		proximity: z.enum(['nearby', 'remote']),
		sourceIdentity: z.string().min(1),
	})
	.strict();

const defaultPaneId = 'bridge-worktree-dev-pane';
const defaultFileLineHeightPixels = 20;
const emptyRenderState: BridgeFileViewerRenderState = {
	descriptors: [],
	provenance: null,
	sourceIdentity: null,
	treeRows: [],
	treeSizeFacts: null,
};

function visibleViewportDemandDispatchSatisfied(
	state: BridgeFileViewerDemandDispatchDebugState,
): boolean {
	if (state.status !== 'settled' || state.origin.kind !== 'visibleViewport') {
		return false;
	}
	const firstLoadResult = firstSuccessfulDemandLoadResult(state.result);
	return (
		state.origin.expectedVisibleFileCount > 0 &&
		state.result.stimulusCount === 1 &&
		state.result.intentCount === state.origin.expectedVisibleFileCount &&
		state.result.loadedCount === state.origin.expectedVisibleFileCount &&
		state.result.failedCount === 0 &&
		state.result.schedulerQueuedIntentCountAfter === 0 &&
		state.result.executorQueuedLoadCountAfter === 0 &&
		firstLoadResult?.loadTelemetry.lane === 'visible' &&
		firstLoadResult.loadTelemetry.disposition === 'visible-preloaded'
	);
}

function visibleFileDemandSignature(change: BridgeFileViewerVisibleFileDemandChange): string {
	return change.descriptorRefs
		.map((ref): string => {
			const identity = ref.expectedIdentity;
			return [
				ref.descriptorId,
				ref.expectedProtocol,
				ref.expectedResourceKind,
				identity.paneId,
				identity.sourceId ?? 'source-none',
				identity.generation ?? 'generation-none',
				identity.revision ?? 'revision-none',
				identity.streamId ?? 'stream-none',
				identity.cursor ?? 'cursor-none',
			].join(':');
		})
		.join('\n');
}

export function BridgeFileViewerApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	const {
		autoOpenInitialFile = false,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		fetchResource,
		initialFrames,
		isActive = true,
		loadInitialFrames,
		loadInitialSurface,
		onOpenReviewComparison,
		subscribeFrames,
		waitForBridgeReady,
	} = props;
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const openFileBodyRef = useRef<string | null>(null);
	const provisionalOpenFileBodyRef = useRef<string | null>(null);
	const activeVisibleDemandSignatureRef = useRef<string | null>(null);
	const demandDispatchRequestIdRef = useRef(0);
	const openFileBodyVersionRef = useRef(0);
	const lastDemandDispatchDebugStateRef = useRef<BridgeFileViewerDemandDispatchDebugState>({
		status: 'idle',
	});
	const lastVisibleDemandSignatureRef = useRef<string | null>(null);
	const pendingRecentlyUpdatedDescriptorDemandRef =
		useRef<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>(null);
	const openFileRequestIdRef = useRef(0);
	const pendingSelectedDescriptorRequestRef = useRef<WorktreeFileDescriptorRequest | null>(null);
	const pendingStaleRefreshDescriptorRequestKeyRef = useRef<string | null>(null);
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const renderStateRef = useRef<BridgeFileViewerRenderState>(emptyRenderState);
	const openFileStateRef = useRef<BridgeFileViewerOpenState>({ status: 'idle' });
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
	const [openFileBodyState, setOpenFileBodyState] = useState<string | null>(null);
	const [openFileBodyVersion, setOpenFileBodyVersion] = useState(0);
	const [initialSurfaceLoadState, setInitialSurfaceLoadState] =
		useState<BridgeFileViewerInitialSurfaceLoadState>({ status: 'idle' });
	const [lastGoodOpenFileContent, setLastGoodOpenFileContent] =
		useState<BridgeFileViewerRenderedOpenFileContent | null>(null);
	const [provisionalOpenFileBody, setProvisionalOpenFileBody] = useState<string | null>(null);
	lastDemandDispatchDebugStateRef.current = lastDemandDispatchDebugState;
	const [searchText, setSearchText] = useState('');
	const [searchMode, setSearchMode] = useState<BridgeFileViewerSearchMode>('text');
	const [filterMode, setFilterMode] = useState<BridgeFileViewerFilterMode>('all');
	const selectedPath = openFileState.status === 'idle' ? null : openFileState.path;
	openFileStateRef.current = openFileState;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const fileDescriptorByPath = useMemo(
		(): ReadonlyMap<string, WorktreeFileDescriptor> =>
			new Map(renderState.descriptors.map((descriptor) => [descriptor.path, descriptor])),
		[renderState.descriptors],
	);
	const navigationTargetPath = fileViewerNavigationTargetPath(props.navigationCommand);

	if (runtimeRef.current === null) {
		const telemetryRecorder = props.telemetryRecorder;
		runtimeRef.current = createWorktreeFileSurfaceRuntime({
			paneId: defaultPaneId,
			fetchResource: fetchResource ?? defaultFetchWorktreeFileResource,
			resourceLoadProbe:
				telemetryRecorder === undefined
					? undefined
					: {
							isEnabled: (): boolean => telemetryRecorder.isEnabled('web'),
							now: (): number => performance.now(),
							record: (sample): void => {
								recordBridgeViewerWorktreeFileContentFetchTelemetrySample({
									...sample,
									telemetryRecorder,
									traceContext: props.telemetryTraceContext ?? null,
								});
							},
						},
		});
	}

	const commitOpenFileBody = useCallback((commit: CommitOpenFileBodyProps): void => {
		const nextBodyVersion = openFileBodyVersionRef.current + 1;
		openFileBodyVersionRef.current = nextBodyVersion;
		openFileBodyRef.current = commit.body;
		setOpenFileBodyState(commit.body);
		setOpenFileBodyVersion(nextBodyVersion);
		setLastGoodOpenFileContent({
			body: commit.body,
			bodyVersion: nextBodyVersion,
			descriptor: commit.descriptor,
			path: commit.path,
		});
	}, []);

	useEffect((): void => {
		if (isActive) {
			return;
		}
		activeVisibleDemandSignatureRef.current = null;
		demandDispatchRequestIdRef.current += 1;
	}, [isActive]);

	const openFile = useCallback(
		async (descriptor: WorktreeFileDescriptor): Promise<void> => {
			const openFileStartedAt = performance.now();
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			openFileBodyRef.current = null;
			setOpenFileBodyState(null);
			provisionalOpenFileBodyRef.current = null;
			setProvisionalOpenFileBody(null);
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
				onProvisionalTextChunk: (chunk): void => {
					if (openFileRequestIdRef.current !== requestId) {
						return;
					}
					provisionalOpenFileBodyRef.current = `${provisionalOpenFileBodyRef.current ?? ''}${chunk.text}`;
					setProvisionalOpenFileBody(provisionalOpenFileBodyRef.current);
				},
				openFileSessionId: descriptor.fileId,
			});
			if (openFileRequestIdRef.current !== requestId) {
				return;
			}
			if (result.ok) {
				const openFileBody = result.content.readText();
				commitOpenFileBody({
					body: openFileBody,
					descriptor,
					path: descriptor.path,
				});
				if (telemetryRecorder !== undefined) {
					recordBridgeViewerFileOpenReadyTelemetrySample({
						disposition: result.loadTelemetry.disposition,
						durationMilliseconds: performance.now() - openFileStartedAt,
						estimatedBytes: result.loadTelemetry.estimatedBytes,
						executorInFlightMilliseconds: result.loadTelemetry.executorInFlightMilliseconds,
						executorPendingWaitMilliseconds: result.loadTelemetry.executorPendingWaitMilliseconds,
						lane: result.loadTelemetry.lane,
						requestId,
						resourceBodyRegistryCommitMilliseconds:
							result.loadTelemetry.resourceBodyRegistryCommitMilliseconds,
						resourceFetchResponseWaitMilliseconds:
							result.loadTelemetry.resourceFetchResponseWaitMilliseconds,
						resourceFirstChunkWaitMilliseconds:
							result.loadTelemetry.resourceFirstChunkWaitMilliseconds,
						resourceStreamReadMilliseconds: result.loadTelemetry.resourceStreamReadMilliseconds,
						result: 'success',
						resultReason: null,
						schedulerQueueWaitMilliseconds: result.loadTelemetry.schedulerQueueWaitMilliseconds,
						sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
						telemetryRecorder,
						traceContext: telemetryTraceContext,
					});
				}
				provisionalOpenFileBodyRef.current = null;
				setProvisionalOpenFileBody(null);
				setLastOpenLoadTelemetry(result.loadTelemetry);
				setOpenFileState({ status: 'ready', path: descriptor.path, descriptor });
				return;
			}
			openFileBodyRef.current = null;
			setOpenFileBodyState(null);
			provisionalOpenFileBodyRef.current = null;
			setProvisionalOpenFileBody(null);
			setLastOpenLoadTelemetry(null);
			if (telemetryRecorder !== undefined) {
				recordBridgeViewerFileOpenReadyTelemetrySample({
					disposition: 'none',
					durationMilliseconds: performance.now() - openFileStartedAt,
					estimatedBytes: descriptor.contentDescriptor.descriptor.content.expectedBytes ?? null,
					executorInFlightMilliseconds: null,
					executorPendingWaitMilliseconds: null,
					lane: 'foreground',
					requestId,
					resourceBodyRegistryCommitMilliseconds: null,
					resourceFetchResponseWaitMilliseconds: null,
					resourceFirstChunkWaitMilliseconds: null,
					resourceStreamReadMilliseconds: null,
					result: 'failed',
					resultReason: result.reason,
					schedulerQueueWaitMilliseconds: null,
					sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
					telemetryRecorder,
					traceContext: telemetryTraceContext,
				});
			}
			setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'failed',
				path: descriptor.path,
				descriptor,
			});
		},
		[commitOpenFileBody, telemetryRecorder, telemetryTraceContext],
	);

	const openPendingSelectedDescriptor = useCallback(
		(nextState: BridgeFileViewerRenderState): void => {
			const pendingRequest = pendingSelectedDescriptorRequestRef.current;
			if (pendingRequest === null) {
				return;
			}
			const descriptor = nextState.descriptors.find(
				(candidate): boolean =>
					candidate.fileId === pendingRequest.fileId &&
					candidate.path === pendingRequest.path &&
					canFetchWorktreeFileDescriptorContent(candidate),
			);
			if (descriptor === undefined) {
				return;
			}
			pendingSelectedDescriptorRequestRef.current = null;
			void openFile(descriptor);
		},
		[openFile],
	);

	const requestFileDescriptorFromHost = props.requestFileDescriptor;
	const requestFileDescriptor = useCallback(
		(request: WorktreeFileDescriptorRequest): void => {
			pendingSelectedDescriptorRequestRef.current = request;
			const requestResult = requestFileDescriptorFromHost?.(request);
			if (requestResult === undefined) {
				return;
			}
			void Promise.resolve(requestResult).catch((): void => {
				if (pendingSelectedDescriptorRequestRef.current !== request) {
					return;
				}
				pendingSelectedDescriptorRequestRef.current = null;
			});
		},
		[requestFileDescriptorFromHost],
	);

	const requestFileDescriptorForDemand = useCallback(
		(request: WorktreeFileDescriptorRequest): void => {
			const requestResult = requestFileDescriptorFromHost?.(request);
			if (requestResult === undefined) {
				return;
			}
			void Promise.resolve(requestResult).catch((): void => {
				// Demand lanes are advisory warming; failed descriptor requests must not surface
				// as unhandled promise rejections or poison foreground selection state.
			});
		},
		[requestFileDescriptorFromHost],
	);

	const dispatchRecentlyUpdatedDescriptorDemand = useCallback(
		(demandProps: {
			readonly descriptor: WorktreeFileDescriptor;
			readonly openFilePathBefore: string | null;
			readonly proximity: 'nearby' | 'remote';
			readonly requestId: number;
		}): void => {
			const runtime = runtimeRef.current;
			if (runtime === null) {
				return;
			}
			const stimuli: readonly WorktreeFileDemandStimulus[] = [
				{
					kind: 'recentlyUpdatedFile',
					descriptorRef: demandProps.descriptor.contentDescriptor.ref,
					proximity: demandProps.proximity,
					sourceIdentity: demandProps.descriptor.sourceIdentity.sourceId,
				},
			];
			void runtime
				.dispatchDemandStimuli(stimuli)
				.then((result): void => {
					if (!isActive) {
						return;
					}
					if (demandDispatchRequestIdRef.current !== demandProps.requestId) {
						return;
					}
					const openFilePathAfter =
						openFileStateRef.current.status === 'idle' ? null : openFileStateRef.current.path;
					setLastDemandDispatchDebugState({
						origin: {
							descriptorPath: demandProps.descriptor.path,
							kind: 'recentlyUpdatedFile',
							openFilePathAfter,
							openFilePathBefore: demandProps.openFilePathBefore,
						},
						status: 'settled',
						result,
					});
				})
				.catch((error: unknown): void => {
					if (!isActive) {
						return;
					}
					if (demandDispatchRequestIdRef.current !== demandProps.requestId) {
						return;
					}
					setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				});
		},
		[isActive],
	);

	const dispatchPendingRecentlyUpdatedDescriptorDemand = useCallback(
		(nextState: BridgeFileViewerRenderState): void => {
			const pendingDemand = pendingRecentlyUpdatedDescriptorDemandRef.current;
			if (pendingDemand === null) {
				return;
			}
			const descriptor = nextState.descriptors.find(
				(candidate): boolean =>
					candidate.fileId === pendingDemand.request.fileId &&
					candidate.path === pendingDemand.request.path &&
					canFetchWorktreeFileDescriptorContent(candidate),
			);
			if (descriptor === undefined) {
				return;
			}
			pendingRecentlyUpdatedDescriptorDemandRef.current = null;
			dispatchRecentlyUpdatedDescriptorDemand({
				descriptor,
				openFilePathBefore: pendingDemand.openFilePathBefore,
				proximity: pendingDemand.proximity,
				requestId: pendingDemand.requestId,
			});
		},
		[dispatchRecentlyUpdatedDescriptorDemand],
	);

	const applyIncomingFrames = useCallback(
		(
			frames: readonly WorktreeFileProtocolFrame[],
			surface?: {
				readonly provenance: WorktreeFileSurfaceProvenance | null;
				readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
			},
		): BridgeFileViewerRenderState => {
			const applyStartedAt = performance.now();
			const nextState = applyFramesToRuntime({
				currentRenderState: renderStateRef.current,
				frames,
				provenance: surface?.provenance ?? null,
				runtime: runtimeRef.current,
				sourceIdentity: surface?.sourceIdentity ?? null,
			});
			if (props.telemetryRecorder !== undefined) {
				recordBridgeViewerWorktreeFileTreeTelemetrySample({
					descriptorCount: nextState.descriptors.length,
					durationMilliseconds: performance.now() - applyStartedAt,
					frameCount: frames.length,
					phase: 'worktree_file_frame_apply',
					result: 'success',
					telemetryRecorder: props.telemetryRecorder,
					traceContext: props.telemetryTraceContext ?? null,
					treeRowCount: nextState.treeRows.length,
					treeWindowRowCount: worktreeTreeWindowRowCount(frames),
				});
			}
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
			dispatchPendingRecentlyUpdatedDescriptorDemand(nextState);
			openPendingSelectedDescriptor(nextState);
			return nextState;
		},
		[
			dispatchPendingRecentlyUpdatedDescriptorDemand,
			openPendingSelectedDescriptor,
			props.telemetryRecorder,
			props.telemetryTraceContext,
		],
	);
	const applyIncomingFramesRef = useRef(applyIncomingFrames);
	applyIncomingFramesRef.current = applyIncomingFrames;
	const initialFramesRef = useRef(initialFrames);
	const loadInitialFramesRef = useRef(loadInitialFrames);
	const loadInitialSurfaceRef = useRef(loadInitialSurface);
	const waitForBridgeReadyRef = useRef(waitForBridgeReady);
	initialFramesRef.current = initialFrames;
	loadInitialFramesRef.current = loadInitialFrames;
	loadInitialSurfaceRef.current = loadInitialSurface;
	waitForBridgeReadyRef.current = waitForBridgeReady;

	useEffect((): (() => void) => {
		let isCancelled = false;
		let didStartLoad = false;
		const loadFrames = async (): Promise<void> => {
			setInitialSurfaceLoadState({ status: 'loading' });
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
				setInitialSurfaceLoadState({ status: 'ready' });
			} catch (error: unknown) {
				if (isCancelled) {
					return;
				}
				setInitialSurfaceLoadState({
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

	useEffect((): ReturnType<WorktreeFileFrameSubscriptionFactory> | undefined => {
		if (subscribeFrames === undefined) {
			return undefined;
		}
		return subscribeFrames((frames) => {
			applyIncomingFrames(frames);
		});
	}, [applyIncomingFrames, subscribeFrames]);

	useEffect((): void => {
		if (!autoOpenInitialFile || openFileRequestIdRef.current !== 0) {
			return;
		}
		if (navigationTargetPath !== null) {
			return;
		}
		if (pendingSelectedDescriptorRequestRef.current !== null) {
			return;
		}
		const initialDescriptor = renderState.descriptors.find((descriptor) =>
			canFetchWorktreeFileDescriptorContent(descriptor),
		);
		if (initialDescriptor !== undefined) {
			void openFile(initialDescriptor);
			return;
		}
		const initialDescriptorRequest = descriptorRequestForFirstFileTreeRow({
			sourceIdentity: renderState.sourceIdentity,
			treeRows: renderState.treeRows,
		});
		if (initialDescriptorRequest !== null) {
			requestFileDescriptor(initialDescriptorRequest);
		}
	}, [
		autoOpenInitialFile,
		navigationTargetPath,
		openFile,
		renderState.descriptors,
		renderState.sourceIdentity,
		renderState.treeRows,
		requestFileDescriptor,
	]);

	useEffect((): void => {
		if (openFileState.status !== 'stale') {
			pendingStaleRefreshDescriptorRequestKeyRef.current = null;
			return;
		}
		const latestDescriptor = findLatestDescriptorForOpenFile({
			descriptor: openFileState.descriptor,
			renderState,
		});
		if (latestDescriptor !== null) {
			pendingStaleRefreshDescriptorRequestKeyRef.current = null;
			return;
		}
		const descriptorRequest = descriptorRequestForTreePath({
			lane: 'foreground',
			path: openFileState.path,
			sourceIdentity: renderState.sourceIdentity,
			treeRows: renderState.treeRows,
		});
		if (descriptorRequest === null) {
			return;
		}
		const requestKey = `${descriptorRequest.sourceIdentity.sourceId}:${descriptorRequest.sourceIdentity.sourceCursor}:${descriptorRequest.fileId}:${descriptorRequest.path}`;
		if (pendingStaleRefreshDescriptorRequestKeyRef.current === requestKey) {
			return;
		}
		pendingStaleRefreshDescriptorRequestKeyRef.current = requestKey;
		requestFileDescriptorForDemand(descriptorRequest);
	}, [openFileState, renderState, requestFileDescriptorForDemand]);

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
			const descriptorRequest = descriptorRequestForTreePath({
				lane: 'foreground',
				path: navigationTargetPath,
				sourceIdentity: renderState.sourceIdentity,
				treeRows: renderState.treeRows,
			});
			if (
				descriptorRequest !== null &&
				!worktreeFileDescriptorRequestsMatch(
					pendingSelectedDescriptorRequestRef.current,
					descriptorRequest,
				)
			) {
				requestFileDescriptor(descriptorRequest);
			}
			return;
		}
		appliedNavigationCommandIdRef.current = navigationCommand.commandId;
		void openFile(targetDescriptor);
	}, [
		navigationTargetPath,
		openFile,
		props.navigationCommand,
		renderState.descriptors,
		renderState.sourceIdentity,
		renderState.treeRows,
		requestFileDescriptor,
	]);

	const refreshOpenFile = useCallback(
		async (state: BridgeFileViewerOpenState): Promise<void> => {
			if (state.status !== 'stale') {
				setRefreshDebugState({
					commitState: 'skipped',
					currentRequestId: openFileRequestIdRef.current,
					descriptorId: 'none',
					requestId: openFileRequestIdRef.current,
					result: 'non_stale_state',
				});
				return;
			}
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			provisionalOpenFileBodyRef.current = null;
			setProvisionalOpenFileBody(null);
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
			setRefreshDebugState({
				commitState: 'started',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
				requestId,
				result: 'started',
			});
			const result = await runtime.refreshOpenFile({
				onProvisionalTextChunk: (chunk): void => {
					if (openFileRequestIdRef.current !== requestId) {
						return;
					}
					provisionalOpenFileBodyRef.current = `${provisionalOpenFileBodyRef.current ?? ''}${chunk.text}`;
					setProvisionalOpenFileBody(provisionalOpenFileBodyRef.current);
				},
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
				const openFileBody = result.content.readText();
				commitOpenFileBody({
					body: openFileBody,
					descriptor: refreshDescriptor,
					path: refreshDescriptor.path,
				});
				provisionalOpenFileBodyRef.current = null;
				setProvisionalOpenFileBody(null);
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
			setOpenFileBodyState(
				result.reason === 'content_unavailable' ? null : openFileBodyRef.current,
			);
			provisionalOpenFileBodyRef.current = null;
			setProvisionalOpenFileBody(null);
			setLastOpenLoadTelemetry(null);
			setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
				path: refreshDescriptor.path,
				descriptor: refreshDescriptor,
			});
		},
		[commitOpenFileBody],
	);

	const dispatchVisibleFileDemand = useCallback(
		(change: BridgeFileViewerVisibleFileDemandChange): void => {
			if (!isActive) {
				return;
			}
			const runtime = runtimeRef.current;
			if (runtime === null || change.descriptorRefs.length === 0) {
				return;
			}
			const visibleDemandSignature = visibleFileDemandSignature(change);
			if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
				return;
			}
			if (
				lastVisibleDemandSignatureRef.current === visibleDemandSignature &&
				visibleViewportDemandDispatchSatisfied(lastDemandDispatchDebugStateRef.current)
			) {
				return;
			}
			activeVisibleDemandSignatureRef.current = visibleDemandSignature;
			const requestId = demandDispatchRequestIdRef.current + 1;
			demandDispatchRequestIdRef.current = requestId;
			const visibleDemandStartedAt = performance.now();
			const stimuli: readonly WorktreeFileDemandStimulus[] = [
				{
					kind: 'treeViewportChanged',
					descriptorRefs: [...change.descriptorRefs],
				},
			];
			void runtime
				.dispatchDemandStimuli(stimuli)
				.then((result): void => {
					if (!isActive) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					const nextDebugState: BridgeFileViewerDemandDispatchDebugState = {
						origin: {
							expectedVisibleFileCount: change.visibleFileCount,
							kind: 'visibleViewport',
						},
						status: 'settled',
						result,
					};
					if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
						activeVisibleDemandSignatureRef.current = null;
					}
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					if (visibleViewportDemandDispatchSatisfied(nextDebugState)) {
						lastVisibleDemandSignatureRef.current = visibleDemandSignature;
					}
					if (telemetryRecorder !== undefined) {
						const firstLoadTelemetry =
							firstSuccessfulDemandLoadResult(result)?.loadTelemetry ?? null;
						recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample({
							durationMilliseconds: performance.now() - visibleDemandStartedAt,
							enqueueAcceptedCount: result.enqueueAcceptedCount,
							enqueueRejectedCount: result.enqueueRejectedCount,
							executorInFlightMilliseconds:
								firstLoadTelemetry?.executorInFlightMilliseconds ?? null,
							executorPendingWaitMilliseconds:
								firstLoadTelemetry?.executorPendingWaitMilliseconds ?? null,
							failedCount: result.failedCount,
							firstChunkWaitMilliseconds:
								firstLoadTelemetry?.resourceFirstChunkWaitMilliseconds ?? null,
							intentCount: result.intentCount,
							lane: firstLoadTelemetry?.lane ?? null,
							loadedCount: result.loadedCount,
							requestId,
							responseWaitMilliseconds:
								firstLoadTelemetry?.resourceFetchResponseWaitMilliseconds ?? null,
							result: result.failedCount === 0 ? 'success' : 'failed',
							resultReason: result.failedCount === 0 ? null : 'load_failed',
							schedulerQueueWaitMilliseconds:
								firstLoadTelemetry?.schedulerQueueWaitMilliseconds ?? null,
							streamReadMilliseconds: firstLoadTelemetry?.resourceStreamReadMilliseconds ?? null,
							telemetryRecorder,
							traceContext: telemetryTraceContext,
							visibleItemCount: change.visibleFileCount,
						});
					}
					setLastDemandDispatchDebugState(nextDebugState);
				})
				.catch((error: unknown): void => {
					if (!isActive) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
						activeVisibleDemandSignatureRef.current = null;
					}
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					if (telemetryRecorder !== undefined) {
						recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample({
							durationMilliseconds: performance.now() - visibleDemandStartedAt,
							enqueueAcceptedCount: 0,
							enqueueRejectedCount: 0,
							executorInFlightMilliseconds: null,
							executorPendingWaitMilliseconds: null,
							failedCount: change.visibleFileCount,
							firstChunkWaitMilliseconds: null,
							intentCount: change.visibleFileCount,
							lane: 'visible',
							loadedCount: 0,
							requestId,
							responseWaitMilliseconds: null,
							result: 'failed',
							resultReason: 'load_failed',
							schedulerQueueWaitMilliseconds: null,
							streamReadMilliseconds: null,
							telemetryRecorder,
							traceContext: telemetryTraceContext,
							visibleItemCount: change.visibleFileCount,
						});
					}
					setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				});
		},
		[isActive, telemetryRecorder, telemetryTraceContext],
	);

	const dispatchRecentlyUpdatedFileDemand = useCallback(
		(event: Event): void => {
			if (!isActive) {
				return;
			}
			if (!(event instanceof CustomEvent)) {
				return;
			}
			const parsedDetail = bridgeFileViewerRecentlyUpdatedEventDetailSchema.safeParse(event.detail);
			if (!parsedDetail.success) {
				return;
			}
			const runtime = runtimeRef.current;
			const currentRenderState = renderStateRef.current;
			if (runtime === null || currentRenderState.sourceIdentity === null) {
				return;
			}
			if (currentRenderState.sourceIdentity.sourceId !== parsedDetail.data.sourceIdentity) {
				return;
			}
			const descriptor = currentRenderState.descriptors.find(
				(candidateDescriptor): boolean => candidateDescriptor.path === parsedDetail.data.path,
			);
			const openFilePathBefore =
				openFileStateRef.current.status === 'idle' ? null : openFileStateRef.current.path;
			const requestId = demandDispatchRequestIdRef.current + 1;
			demandDispatchRequestIdRef.current = requestId;
			if (descriptor !== undefined && canFetchWorktreeFileDescriptorContent(descriptor)) {
				dispatchRecentlyUpdatedDescriptorDemand({
					descriptor,
					openFilePathBefore,
					proximity: parsedDetail.data.proximity,
					requestId,
				});
				return;
			}
			const treeRow = currentRenderState.treeRows.find(
				(candidateTreeRow): boolean => candidateTreeRow.path === parsedDetail.data.path,
			);
			if (treeRow === undefined || treeRow.fileId === undefined) {
				return;
			}
			const descriptorRequest: WorktreeFileDescriptorRequest = {
				fileId: treeRow.fileId,
				lane: parsedDetail.data.proximity === 'nearby' ? 'nearby' : 'speculative',
				path: treeRow.path,
				rowId: treeRow.rowId,
				sourceIdentity: currentRenderState.sourceIdentity,
			};
			pendingRecentlyUpdatedDescriptorDemandRef.current = {
				openFilePathBefore,
				proximity: parsedDetail.data.proximity,
				request: descriptorRequest,
				requestId,
			};
			requestFileDescriptorForDemand(descriptorRequest);
		},
		[dispatchRecentlyUpdatedDescriptorDemand, isActive, requestFileDescriptorForDemand],
	);

	useEffect((): (() => void) => {
		if (!isActive) {
			return (): void => {};
		}
		window.addEventListener(
			bridgeFileViewerRecentlyUpdatedEventName,
			dispatchRecentlyUpdatedFileDemand,
		);
		return (): void => {
			window.removeEventListener(
				bridgeFileViewerRecentlyUpdatedEventName,
				dispatchRecentlyUpdatedFileDemand,
			);
		};
	}, [dispatchRecentlyUpdatedFileDemand, isActive]);

	const descriptorProjection = useMemo((): BridgeFileViewerDescriptorProjection => {
		const projectionStartedAt = performance.now();
		const projection = projectBridgeFileViewerDescriptors({
			descriptors: renderState.descriptors,
			filterMode,
			searchMode,
			searchText,
			treeRows: renderState.treeRows,
		});
		if (props.telemetryRecorder !== undefined) {
			recordBridgeViewerWorktreeFileTreeTelemetrySample({
				descriptorCount: projection.descriptors.length,
				durationMilliseconds: performance.now() - projectionStartedAt,
				frameCount: 0,
				phase: 'worktree_file_projection',
				result: 'success',
				telemetryRecorder: props.telemetryRecorder,
				traceContext: props.telemetryTraceContext ?? null,
				treeRowCount: projection.treeRows.length,
				treeWindowRowCount: 0,
			});
		}
		return projection;
	}, [
		filterMode,
		props.telemetryRecorder,
		props.telemetryTraceContext,
		renderState.descriptors,
		renderState.treeRows,
		searchMode,
		searchText,
	]);
	const totalTreeRowCount = renderState.treeRows.length;
	const totalTreeHeight = totalTreeHeightForSizeFacts({
		filteredTreeRowCount: countFlattenedWorktreeFileTreeRows(descriptorProjection.paths),
		hasActiveProjection:
			filterMode !== 'all' ||
			searchText.trim().length > 0 ||
			descriptorProjection.searchError !== null,
		sizeFacts: renderState.treeSizeFacts,
		totalTreeRowCount,
	});
	const renderedOpenFileContent = useMemo(
		(): BridgeFileViewerRenderedOpenFileContent | null =>
			renderedOpenFileContentForState({
				lastGoodOpenFileContent,
				openFileBody: openFileBodyState,
				openFileBodyVersion,
				openFileState,
				provisionalOpenFileBody,
				selectedPath,
			}),
		[
			lastGoodOpenFileContent,
			openFileBodyState,
			openFileBodyVersion,
			openFileState,
			provisionalOpenFileBody,
			selectedPath,
		],
	);
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
	const firstDemandLoadResult =
		lastDemandDispatchResult === null
			? null
			: firstSuccessfulDemandLoadResult(lastDemandDispatchResult);
	const firstDemandLoadTelemetry = firstDemandLoadResult?.loadTelemetry ?? null;
	const metadataFileTreeRowCount = renderState.treeRows.filter(
		(treeRow): boolean => !treeRow.isDirectory && treeRow.fileId !== undefined,
	).length;

	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)]"
			data-file-viewer-active={isActive}
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
			data-last-demand-dispatch-executor-in-flight-after={
				lastDemandDispatchResult?.executorInFlightCountAfter
			}
			data-last-demand-dispatch-executor-in-flight-bytes-after={
				lastDemandDispatchResult?.executorInFlightBytesAfter
			}
			data-last-demand-dispatch-executor-queued-after={
				lastDemandDispatchResult?.executorQueuedLoadCountAfter
			}
			data-last-demand-dispatch-executor-queued-bytes-after={
				lastDemandDispatchResult?.executorQueuedBytesAfter
			}
			data-last-demand-dispatch-failed-count={lastDemandDispatchResult?.failedCount}
			data-last-demand-dispatch-failed-count-by-lane={
				lastDemandDispatchResult === null
					? undefined
					: JSON.stringify(worktreeFileDemandFailedCountByLane(lastDemandDispatchResult))
			}
			data-last-demand-dispatch-failed-count-by-reason={
				lastDemandDispatchResult === null
					? undefined
					: JSON.stringify(worktreeFileDemandFailedCountByReason(lastDemandDispatchResult))
			}
			data-last-demand-dispatch-first-disposition={firstDemandLoadTelemetry?.disposition}
			data-last-demand-dispatch-first-dedupe-key={firstDemandLoadResult?.dedupeKey}
			data-last-demand-dispatch-first-freshness-key={firstDemandLoadResult?.freshnessKey}
			data-last-demand-dispatch-first-executor-in-flight-ms={
				firstDemandLoadTelemetry?.executorInFlightMilliseconds ?? undefined
			}
			data-last-demand-dispatch-first-executor-pending-wait-ms={
				firstDemandLoadTelemetry?.executorPendingWaitMilliseconds ?? undefined
			}
			data-last-demand-dispatch-first-lane={firstDemandLoadTelemetry?.lane}
			data-last-demand-dispatch-first-scheduler-queue-wait-ms={
				firstDemandLoadTelemetry?.schedulerQueueWaitMilliseconds ?? undefined
			}
			data-last-demand-dispatch-origin={
				lastDemandDispatchDebugState.status === 'settled'
					? lastDemandDispatchDebugState.origin.kind
					: undefined
			}
			data-last-demand-dispatch-expected-visible-file-count={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'visibleViewport'
					? lastDemandDispatchDebugState.origin.expectedVisibleFileCount
					: undefined
			}
			data-last-demand-dispatch-open-file-path-before={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'recentlyUpdatedFile'
					? (lastDemandDispatchDebugState.origin.openFilePathBefore ?? undefined)
					: undefined
			}
			data-last-demand-dispatch-open-file-path-after={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'recentlyUpdatedFile'
					? (lastDemandDispatchDebugState.origin.openFilePathAfter ?? undefined)
					: undefined
			}
			data-last-demand-dispatch-intent-count={lastDemandDispatchResult?.intentCount}
			data-last-demand-dispatch-loaded-count={lastDemandDispatchResult?.loadedCount}
			data-last-demand-dispatch-scheduler-queued-after={
				lastDemandDispatchResult?.schedulerQueuedIntentCountAfter
			}
			data-last-demand-dispatch-scheduler-queued-bytes-after={
				lastDemandDispatchResult?.schedulerQueuedEstimatedBytesAfter
			}
			data-last-demand-dispatch-status={lastDemandDispatchDebugState.status}
			data-last-demand-dispatch-stimulus-count={lastDemandDispatchResult?.stimulusCount}
			data-worktree-initial-surface-error={
				initialSurfaceLoadState.status === 'failed' ? initialSurfaceLoadState.reason : undefined
			}
			data-worktree-initial-surface-state={initialSurfaceLoadState.status}
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
			data-last-open-load-executor-in-flight-ms={
				lastOpenLoadTelemetry?.executorInFlightMilliseconds ?? undefined
			}
			data-last-open-load-executor-pending-wait-ms={
				lastOpenLoadTelemetry?.executorPendingWaitMilliseconds ?? undefined
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
			data-last-open-load-resource-body-registry-commit-ms={
				lastOpenLoadTelemetry?.resourceBodyRegistryCommitMilliseconds ?? undefined
			}
			data-last-open-load-resource-fetch-response-wait-ms={
				lastOpenLoadTelemetry?.resourceFetchResponseWaitMilliseconds ?? undefined
			}
			data-last-open-load-resource-first-chunk-wait-ms={
				lastOpenLoadTelemetry?.resourceFirstChunkWaitMilliseconds ?? undefined
			}
			data-last-open-load-resource-stream-read-ms={
				lastOpenLoadTelemetry?.resourceStreamReadMilliseconds ?? undefined
			}
			data-last-open-load-scheduler-queue-wait-ms={
				lastOpenLoadTelemetry?.schedulerQueueWaitMilliseconds ?? undefined
			}
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
			data-worktree-metadata-file-row-count={metadataFileTreeRowCount}
			data-worktree-metadata-tree-row-count={renderState.treeRows.length}
			data-worktree-tree-extent-kind={renderState.treeSizeFacts?.extentKind ?? undefined}
			data-worktree-tree-path-count={renderState.treeSizeFacts?.pathCount ?? undefined}
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
						openFileState={openFileState}
						renderedFileContent={renderedOpenFileContent}
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
					onRequestFileDescriptor={requestFileDescriptor}
					onSearchModeChange={setSearchMode}
					onSearchTextChange={setSearchText}
					onVisibleFileDemandChange={dispatchVisibleFileDemand}
					searchMode={searchMode}
					searchText={searchText}
					selectedPath={selectedPath}
					sourceIdentity={renderState.sourceIdentity}
					{...(telemetryRecorder === undefined ? {} : { telemetryRecorder })}
					telemetryTraceContext={telemetryTraceContext}
					totalTreeRowCount={totalTreeRowCount}
					totalTreeHeightPixels={totalTreeHeight.heightPixels}
					totalTreeHeightSource={totalTreeHeight.source}
				/>
			</div>
		</main>
	);
}

function firstSuccessfulDemandLoadResult(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Extract<
	WorktreeFileSurfaceDemandDispatchResult['loadResults'][number],
	{ readonly ok: true }
> | null {
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			return loadResult;
		}
	}
	return null;
}

function worktreeFileDemandFailedCountByLane(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Record<string, number> {
	const countByLane: Record<string, number> = {};
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			continue;
		}
		countByLane[loadResult.lane] = (countByLane[loadResult.lane] ?? 0) + 1;
	}
	return countByLane;
}

function worktreeFileDemandFailedCountByReason(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Record<string, number> {
	const countByReason: Record<string, number> = {};
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			continue;
		}
		countByReason[loadResult.reason] = (countByReason[loadResult.reason] ?? 0) + 1;
	}
	return countByReason;
}

function worktreeTreeWindowRowCount(frames: readonly WorktreeFileProtocolFrame[]): number {
	let rowCount = 0;
	for (const frame of frames) {
		if (frame.frameKind === 'worktree.treeWindow') {
			rowCount += frame.rows?.length ?? 0;
		}
	}
	return rowCount;
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

function BridgeFileViewerStaleNotice({
	canRefresh,
	onRefresh,
}: {
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
				disabled={!canRefresh}
				onClick={onRefresh}
			>
				<BridgeReviewIcon>
					<RefreshCwIcon aria-hidden="true" className="size-3" />
				</BridgeReviewIcon>
				Refresh
			</BridgeReviewButton>
		</div>
	);
}

export function projectBridgeFileViewerDescriptors(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
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
		return { descriptors: [], paths: [], searchError: searchPattern.message, treeRows: [] };
	}
	const descriptorByPath = new Map(
		props.descriptors.map((descriptor) => [descriptor.path, descriptor]),
	);
	const treeRows = props.treeRows.filter((treeRow): boolean => {
		const descriptor = descriptorByPath.get(treeRow.path) ?? null;
		if (
			!treeRowMatchesFilterMode({
				descriptor,
				filterMode: props.filterMode,
				treeRow,
			})
		) {
			return false;
		}
		return searchPattern === null ? true : searchPattern.pattern.test(treeRow.path);
	});
	const includedPathSet = new Set(treeRows.map((treeRow) => treeRow.path));
	const descriptors = props.descriptors.filter((descriptor): boolean =>
		includedPathSet.has(descriptor.path),
	);
	return {
		descriptors,
		paths: treeRows.map(pierreFileTreePathForRow),
		searchError: null,
		treeRows,
	};
}

function pierreFileTreePathForRow(treeRow: WorktreeTreeRowMetadata): string {
	if (!treeRow.isDirectory) {
		return treeRow.path;
	}
	return treeRow.path.endsWith('/') ? treeRow.path : `${treeRow.path}/`;
}

function descriptorRequestForFirstFileTreeRow(props: {
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const firstFileRow = props.treeRows.find(
		(treeRow): boolean => !treeRow.isDirectory && treeRow.fileId !== undefined,
	);
	if (firstFileRow === undefined || firstFileRow.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: firstFileRow.rowId,
		path: firstFileRow.path,
		fileId: firstFileRow.fileId,
		lane: 'foreground',
	};
}

function descriptorRequestForTreePath(props: {
	readonly lane: WorktreeFileDescriptorRequest['lane'];
	readonly path: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const treeRow = props.treeRows.find(
		(candidate): boolean => candidate.path === props.path && !candidate.isDirectory,
	);
	if (treeRow === undefined || treeRow.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: treeRow.rowId,
		path: treeRow.path,
		fileId: treeRow.fileId,
		lane: props.lane,
	};
}

function worktreeFileDescriptorRequestsMatch(
	leftRequest: WorktreeFileDescriptorRequest | null,
	rightRequest: WorktreeFileDescriptorRequest,
): boolean {
	return (
		leftRequest !== null &&
		leftRequest.sourceIdentity.sourceId === rightRequest.sourceIdentity.sourceId &&
		leftRequest.sourceIdentity.sourceCursor === rightRequest.sourceIdentity.sourceCursor &&
		leftRequest.rowId === rightRequest.rowId &&
		leftRequest.path === rightRequest.path &&
		leftRequest.fileId === rightRequest.fileId &&
		leftRequest.lane === rightRequest.lane
	);
}

function treeRowMatchesFilterMode(props: {
	readonly descriptor: WorktreeFileDescriptor | null;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly treeRow: WorktreeTreeRowMetadata;
}): boolean {
	switch (props.filterMode) {
		case 'all':
			return true;
		case 'fetchable':
			if (props.descriptor === null) {
				return !props.treeRow.isDirectory && props.treeRow.fileId !== undefined;
			}
			return canFetchWorktreeFileDescriptorContent(props.descriptor);
		case 'unavailable':
			if (props.descriptor === null) {
				return false;
			}
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

type WorktreeFileRuntimeFrameApplier = Pick<WorktreeFileSurfaceRuntime, 'applyFrame'>;

export function applyFramesToRuntime(props: {
	readonly currentRenderState: BridgeFileViewerRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance?: WorktreeFileSurfaceProvenance | null;
	readonly runtime: WorktreeFileRuntimeFrameApplier | null;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity | null;
}): BridgeFileViewerRenderState {
	const descriptorsByFileId = new Map<string, WorktreeFileDescriptor>(
		props.currentRenderState.descriptors.map(
			(descriptor): readonly [string, WorktreeFileDescriptor] => [descriptor.fileId, descriptor],
		),
	);
	const treeRowsByPath = new Map<string, WorktreeTreeRowMetadata>(
		props.currentRenderState.treeRows.map((treeRow): readonly [string, WorktreeTreeRowMetadata] => [
			treeRow.path,
			treeRow,
		]),
	);
	const provenance = props.provenance ?? props.currentRenderState.provenance;
	let sourceIdentity = props.sourceIdentity ?? props.currentRenderState.sourceIdentity;
	let treeSizeFacts = props.currentRenderState.treeSizeFacts;

	for (const frame of props.frames) {
		const applyFrameResult = props.runtime?.applyFrame(frame);
		if (applyFrameResult?.ok === false) {
			continue;
		}
		if (frame.frameKind === 'worktree.snapshot' || frame.frameKind === 'worktree.treeWindow') {
			treeSizeFacts = frame.treeSizeFacts ?? treeSizeFacts;
		}
		if (frame.frameKind === 'worktree.snapshot') {
			sourceIdentity = frame.source;
			descriptorsByFileId.clear();
			if (frame.treeRows !== undefined) {
				treeRowsByPath.clear();
				for (const treeRow of frame.treeRows) {
					treeRowsByPath.set(treeRow.path, treeRow);
				}
			}
		}
		if (frame.frameKind === 'worktree.treeWindow') {
			sourceIdentity = frame.projectionIdentity.source;
			if (frame.rows !== undefined) {
				for (const treeRow of frame.rows) {
					treeRowsByPath.set(treeRow.path, treeRow);
				}
			}
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
			} else {
				const invalidatedFileId = frame.invalidation.fileId;
				if (invalidatedFileId !== undefined) {
					descriptorsByFileId.delete(invalidatedFileId);
				}
				for (const [fileId, descriptor] of descriptorsByFileId) {
					if (descriptor.path === frame.invalidation.path) {
						descriptorsByFileId.delete(fileId);
					}
				}
				treeRowsByPath.delete(frame.invalidation.path);
				pruneEmptyWorktreeFileTreeDirectories(treeRowsByPath);
			}
		}
		if (frame.frameKind === 'worktree.reset') {
			descriptorsByFileId.clear();
			treeRowsByPath.clear();
			sourceIdentity = frame.source ?? null;
			treeSizeFacts = null;
		}
	}

	return {
		descriptors: [...descriptorsByFileId.values()],
		provenance,
		sourceIdentity,
		treeRows: [...treeRowsByPath.values()],
		treeSizeFacts,
	};
}

export function pruneEmptyWorktreeFileTreeDirectories(
	treeRowsByPath: Map<string, WorktreeTreeRowMetadata>,
): void {
	const pathsToDelete: string[] = [];
	for (const [path, treeRow] of treeRowsByPath) {
		if (!treeRow.isDirectory) {
			continue;
		}
		const descendantPathPrefix = `${path.replace(/\/+$/, '')}/`;
		let hasFileDescendant = false;
		for (const candidate of treeRowsByPath.values()) {
			if (!candidate.isDirectory && candidate.path.startsWith(descendantPathPrefix)) {
				hasFileDescendant = true;
				break;
			}
		}
		if (!hasFileDescendant) {
			pathsToDelete.push(path);
		}
	}
	for (const path of pathsToDelete) {
		treeRowsByPath.delete(path);
	}
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
	const matchedReplacementDescriptor = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileDescriptor' &&
			(frame.descriptor.fileId === currentOpenFileState.descriptor.fileId ||
				frame.descriptor.path === currentOpenFileState.path),
	);
	const resetFrame = props.frames.find((frame) => frame.frameKind === 'worktree.reset');
	if (resetFrame !== undefined) {
		if (
			matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
			areWorktreeFileDescriptorsSameContentVersion(
				matchedReplacementDescriptor.descriptor,
				currentOpenFileState.descriptor,
			)
		) {
			return {
				...currentOpenFileState,
				path: matchedReplacementDescriptor.descriptor.path,
				descriptor: matchedReplacementDescriptor.descriptor,
			};
		}
		if (
			matchedReplacementDescriptor === undefined &&
			resetSnapshotFramesKeepOpenFilePath({
				currentOpenFileState,
				frames: props.frames,
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
	const replacementSourceSnapshot = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.snapshot' &&
			!areWorktreeFileSourceIdentitiesEqual(
				frame.source,
				currentOpenFileState.descriptor.sourceIdentity,
			),
	);
	if (replacementSourceSnapshot !== undefined) {
		if (
			matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
			areWorktreeFileDescriptorsSameContentVersion(
				matchedReplacementDescriptor.descriptor,
				currentOpenFileState.descriptor,
			)
		) {
			return {
				...currentOpenFileState,
				path: matchedReplacementDescriptor.descriptor.path,
				descriptor: matchedReplacementDescriptor.descriptor,
			};
		}
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
		left.contentDescriptor.ref.descriptorId === right.contentDescriptor.ref.descriptorId
	);
}

function areWorktreeFileSourceIdentitiesEqual(
	left: WorktreeFileSurfaceSourceIdentity,
	right: WorktreeFileSurfaceSourceIdentity,
): boolean {
	return (
		left.sourceId === right.sourceId &&
		left.repoId === right.repoId &&
		left.worktreeId === right.worktreeId &&
		left.subscriptionGeneration === right.subscriptionGeneration &&
		left.sourceCursor === right.sourceCursor
	);
}

function resetSnapshotFramesKeepOpenFilePath(props: {
	readonly currentOpenFileState: BridgeFileViewerActiveOpenState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
}): boolean {
	for (const frame of props.frames) {
		if (frame.frameKind !== 'worktree.snapshot' || frame.treeRows === undefined) {
			continue;
		}
		for (const row of frame.treeRows) {
			if (
				!row.isDirectory &&
				(row.fileId === props.currentOpenFileState.descriptor.fileId ||
					row.path === props.currentOpenFileState.path)
			) {
				return false;
			}
		}
	}
	return false;
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
	readonly filteredTreeRowCount: number;
	readonly hasActiveProjection: boolean;
	readonly sizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
	readonly totalTreeRowCount: number;
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
	if (!props.hasActiveProjection && props.sizeFacts.pathCount !== undefined) {
		return {
			heightPixels: Math.max(1, props.sizeFacts.pathCount) * props.sizeFacts.rowHeightPixels,
			source: 'providerFacts',
		};
	}
	if (
		props.hasActiveProjection &&
		props.filteredTreeRowCount === props.totalTreeRowCount &&
		props.sizeFacts.estimatedTotalHeightPixels !== undefined
	) {
		return { heightPixels: props.sizeFacts.estimatedTotalHeightPixels, source: 'providerFacts' };
	}
	if (
		props.hasActiveProjection &&
		props.filteredTreeRowCount === props.totalTreeRowCount &&
		props.sizeFacts.pathCount !== undefined
	) {
		return {
			heightPixels: Math.max(1, props.sizeFacts.pathCount) * props.sizeFacts.rowHeightPixels,
			source: 'providerFacts',
		};
	}
	return {
		heightPixels: Math.max(1, props.filteredTreeRowCount) * props.sizeFacts.rowHeightPixels,
		source: 'localProjection',
	};
}

function renderedOpenFileContentForState(props: {
	readonly lastGoodOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly openFileBody: string | null;
	readonly openFileBodyVersion: number;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly provisionalOpenFileBody: string | null;
	readonly selectedPath: string | null;
}): BridgeFileViewerRenderedOpenFileContent | null {
	if (props.openFileState.status === 'idle') {
		return null;
	}
	if (props.selectedPath !== null && props.selectedPath !== props.openFileState.path) {
		return props.lastGoodOpenFileContent;
	}
	if (props.openFileState.status === 'loading') {
		if (props.provisionalOpenFileBody !== null) {
			return {
				body: props.provisionalOpenFileBody,
				bodyVersion: props.openFileBodyVersion + 1,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		return null;
	}
	if (props.openFileState.status === 'refreshing') {
		if (props.provisionalOpenFileBody !== null) {
			return {
				body: props.provisionalOpenFileBody,
				bodyVersion: props.openFileBodyVersion + 1,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		if (props.openFileBody !== null) {
			return {
				body: props.openFileBody,
				bodyVersion: props.openFileBodyVersion,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		return props.lastGoodOpenFileContent;
	}
	if (props.openFileState.status === 'ready' || props.openFileState.status === 'stale') {
		if (props.openFileBody === null) {
			return props.lastGoodOpenFileContent;
		}
		return {
			body: props.openFileBody,
			bodyVersion: props.openFileBodyVersion,
			descriptor: props.openFileState.descriptor,
			path: props.openFileState.path,
		};
	}
	return null;
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
