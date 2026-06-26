import type { Dispatch, ReactElement, SetStateAction } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useStore } from 'zustand';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import {
	type BridgePushDropReason,
	installBridgePushReceiver,
} from '../bridge/bridge-push-receiver.js';
import { createBridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import { createBridgeTelemetryEventSink } from '../bridge/bridge-telemetry-event-sink.js';
import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import {
	createBridgeDemandScheduler,
	type BridgeDemandScheduler,
} from '../core/demand/bridge-demand-scheduler.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutor,
} from '../core/demand/bridge-resource-executor.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeIdentity,
} from '../core/models/bridge-resource-descriptor.js';
import {
	createBridgeResourceDescriptorRegistry,
	type BridgeResourceDescriptorRegistry,
} from '../core/resources/bridge-resource-registry.js';
import {
	applyReviewProtocolFrame,
	type ReviewMaterializerDelta,
} from '../features/review/materialization/review-materializer.js';
import {
	reviewProtocolFrameSchema,
	type ReviewDeltaFrame,
	type ReviewInvalidationFrame,
	type ReviewProtocolFrame,
	type ReviewResetFrame,
	type ReviewSnapshotFrame,
} from '../features/review/models/review-protocol-models.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	BridgeFileViewerApp,
	type BridgeFileViewerAppProps,
} from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeReviewDelta } from '../foundation/review-package/bridge-review-delta.js';
import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../foundation/review-package/bridge-review-item-registry.js';
import {
	bridgeReviewDeltaSchema,
	bridgeReviewPackageSchema,
} from '../foundation/review-package/bridge-review-package-schema.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import {
	createBridgeTelemetryRecorder,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	planeForBridgeTelemetrySlice,
	priorityForBridgeTelemetrySlice,
	type BridgeTelemetrySlice,
} from '../foundation/telemetry/bridge-telemetry-taxonomy.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type {
	BridgeCodeViewControlHandle,
	BridgeCodeViewScrollToItemOptions,
} from '../review-viewer/code-view/bridge-code-view-panel.js';
import {
	demandCancellationGroupForReviewDescriptorRef,
	demandCancellationGroupsForReviewDescriptorRef,
	demandFreshnessKeyForReviewDescriptorRef,
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandInterest,
	type ReviewContentDemandLoadResult,
} from '../review-viewer/content/review-content-demand-loader.js';
import type { LoadReviewItemContentResourcesProps } from '../review-viewer/content/review-content-loader.js';
import {
	createBridgeReviewContentRegistry,
	type BridgeReviewContentRegistry,
} from '../review-viewer/content/review-content-registry.js';
import {
	makeReviewItemContentResourcesKey,
	type VisibleReviewContentLoadResult,
	useVisibleReviewContentHydration,
} from '../review-viewer/content/visible-review-content-hydration.js';
import {
	bridgeMarkdownPreviewMaxBytes,
	resolveBridgeMarkdownPreviewDecision,
	type BridgeMarkdownPreviewFallbackReason,
} from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import { useBridgeReviewProjectionCoordinator } from '../review-viewer/projections/use-review-projection-coordinator.js';
import {
	BridgeReviewEmptyShell,
	BridgeReviewPackageFailedShell,
	BridgeReviewPackageLoadingShell,
	BridgeReviewProjectionFailedShell,
	BridgeReviewProjectionPendingShell,
	ReviewViewerShell,
	type BridgeReviewCanvasLoadingReason,
} from '../review-viewer/shell/review-viewer-shell.js';
import {
	createBridgeReviewViewerStore,
	selectBridgeReviewViewerRootSnapshot,
	type BridgeReviewViewerStore,
	type BridgeReviewViewerRootSnapshot,
	type BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import { recordBridgeViewerContentQueueTelemetry } from '../review-viewer/telemetry/bridge-review-viewer-telemetry.js';
import type {
	BridgeMarkdownRenderWorkerClient,
	BridgeMarkdownRenderWorkerClientCompletion,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import { createBridgeMarkdownRenderWebWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-transport.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-client.js';
import { createBridgeReviewProjectionWebWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-transport.js';
import {
	bridgeAppControlCommandSchema,
	type BridgeAppControlCommand,
	type BridgeAppControlProbe,
} from './bridge-app-control.js';
import { BridgeViewerAppShell } from './bridge-viewer-app-shell.js';
import { BridgeViewerContextSwitcher } from './bridge-viewer-content-header.js';
import type {
	BridgeViewerNavigationCommand,
	BridgeViewerSource,
} from './bridge-viewer-navigation-models.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
	readonly projectionWorkerClient?: BridgeReviewProjectionWorkerClient;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly viewerMode?: 'file' | 'review';
	readonly fileViewerProps?: BridgeFileViewerAppProps;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly reviewNavigationSource?: Extract<
		BridgeViewerSource,
		{ readonly sourceKind: 'reviewComparison' }
	>;
}

declare global {
	interface Window {
		bridgeReviewControlProbe?: BridgeAppControlProbe;
	}
}

interface BridgeReviewPackageTelemetryContext {
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
}

interface BridgeDiffStatusState {
	readonly status: 'idle' | 'loading' | 'ready' | 'error';
	readonly error: string | null;
	readonly epoch: number;
}

interface SelectReviewItemOptions {
	readonly revealBehavior?: BridgeCodeViewScrollToItemOptions['behavior'];
	readonly revealInCodeView?: boolean;
}

interface BridgeReviewFrameAuthority {
	readonly paneId: string;
	readonly streamId: string;
}

type BridgeReviewFileNavigationTarget = Extract<
	NonNullable<BridgeViewerNavigationCommand['target']>,
	{ readonly targetKind: 'file' }
>;

interface BridgeActiveViewerState {
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly viewerMode: 'file' | 'review';
}

type BridgeViewerMode = BridgeActiveViewerState['viewerMode'];

type BridgeRememberedNavigationCommands = Record<
	BridgeViewerMode,
	BridgeViewerNavigationCommand | undefined
>;

export interface SelectedContentResourcesState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly status: 'loading' | 'ready' | 'failed';
	readonly resources: BridgeCodeViewContentResources | null;
}

interface SelectedMarkdownPreviewState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly sourcePath: string;
	readonly status: 'rendering' | 'ready' | 'failed';
	readonly html: string | null;
}

const bridgeMarkdownPreviewAbortKey = 'bridge-review-markdown-preview';
const bridgeReviewBodyRegistryMaxBytes = 24 * 1024 * 1024;
const bridgeReviewResourceExecutorMaxConcurrentLoads = 8;
const bridgeReviewResourceExecutorMaxInFlightBytes = 8 * 1024 * 1024;
const bridgeReviewResourceExecutorMaxQueuedLoads = 128;
const bridgeReviewResourceExecutorMaxQueuedBytes = 8 * 1024 * 1024;
const bridgeReviewDemandMaxQueuedIntentsPerLane = 128;
const bridgeReviewDemandMaxQueuedEstimatedBytes = 8 * 1024 * 1024;
const bridgeReviewPaneIdAttribute = 'data-bridge-review-pane-id';
const bridgeReviewStreamIdAttribute = 'data-bridge-review-stream-id';
const bridgeReviewAllowedResourceKindsByProtocol = {
	review: new Set(['content', 'review-package', 'review-delta']),
};

type MarkdownPreviewFallbackTelemetryReason =
	| BridgeMarkdownPreviewFallbackReason
	| 'workerUnavailable';

function useBridgeReviewViewerStore(): BridgeReviewViewerStore {
	const storeRef = useRef<BridgeReviewViewerStore | null>(null);
	if (storeRef.current === null) {
		storeRef.current = createBridgeReviewViewerStore();
	}
	return storeRef.current;
}

function useBridgeReviewContentRegistry(): BridgeReviewContentRegistry {
	const registryRef = useRef<BridgeReviewContentRegistry | null>(null);
	if (registryRef.current === null) {
		registryRef.current = createBridgeReviewContentRegistry();
	}
	return registryRef.current;
}

function useBridgeResourceDescriptorRegistry(): BridgeResourceDescriptorRegistry {
	const registryRef = useRef<BridgeResourceDescriptorRegistry | null>(null);
	if (registryRef.current === null) {
		registryRef.current = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
		});
	}
	return registryRef.current;
}

interface UseBridgeReviewResourceExecutorProps {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly descriptorRefsByDescriptorIdRef: {
		readonly current: ReadonlyMap<string, BridgeDescriptorRef>;
	};
	readonly fetchContentRef: { readonly current: BridgeContentFetch | undefined };
	readonly invalidatedFreshnessKeysRef: { readonly current: Set<string> };
}

function useBridgeReviewResourceExecutor(
	props: UseBridgeReviewResourceExecutorProps,
): BridgeResourceExecutor<string> {
	const bodyRegistryRef = useRef(
		createBridgeBodyRegistry<string>({
			maxBytes: bridgeReviewBodyRegistryMaxBytes,
		}),
	);
	const executorRef = useRef<BridgeResourceExecutor<string> | null>(null);
	if (executorRef.current === null) {
		executorRef.current = createBridgeResourceExecutor<string>({
			registry: props.descriptorRegistry,
			maxConcurrentLoads: bridgeReviewResourceExecutorMaxConcurrentLoads,
			maxInFlightBytes: bridgeReviewResourceExecutorMaxInFlightBytes,
			maxQueuedLoads: bridgeReviewResourceExecutorMaxQueuedLoads,
			maxQueuedBytes: bridgeReviewResourceExecutorMaxQueuedBytes,
			isFresh: (intent): boolean => {
				const currentDescriptorRef = props.descriptorRefsByDescriptorIdRef.current.get(
					intent.descriptorRef.descriptorId,
				);
				return (
					currentDescriptorRef !== undefined &&
					demandFreshnessKeyForReviewDescriptorRef(currentDescriptorRef) === intent.freshnessKey
				);
			},
			loadResource: async ({ descriptor, intent, signal }) => {
				const cacheKey = descriptor.resourceUrl;
				const shouldBypassCachedBody = props.invalidatedFreshnessKeysRef.current.has(
					intent.freshnessKey,
				);
				const cachedBody = shouldBypassCachedBody
					? null
					: bodyRegistryRef.current.get({
							cacheKey,
							freshnessKey: intent.freshnessKey,
						});
				if (cachedBody !== null) {
					return {
						body: cachedBody,
						byteLength: encodedByteLength(cachedBody),
					};
				}
				const fetchContent = props.fetchContentRef.current ?? fetch;
				const response = await fetchContent(descriptor.resourceUrl, { signal });
				if (!response.ok) {
					throw new Error(`Bridge descriptor content request failed: ${response.status}`);
				}
				const body = await response.text();
				const byteLength = encodedByteLength(body);
				bodyRegistryRef.current.put({
					cacheKey,
					freshnessKey: intent.freshnessKey,
					body,
					byteLength,
				});
				if (shouldBypassCachedBody) {
					props.invalidatedFreshnessKeysRef.current.delete(intent.freshnessKey);
				}
				return { body, byteLength };
			},
		});
	}
	return executorRef.current;
}

function createBridgeReviewDemandScheduler(): BridgeDemandScheduler {
	return createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: bridgeReviewDemandMaxQueuedIntentsPerLane,
		maxQueuedEstimatedBytes: bridgeReviewDemandMaxQueuedEstimatedBytes,
	});
}

function encodedByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

function activeViewerStateForBridgeInputs(props: {
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly viewerMode: 'file' | 'review' | undefined;
}): BridgeActiveViewerState {
	if (props.navigationCommand !== undefined) {
		return {
			navigationCommand: props.navigationCommand,
			viewerMode: viewerModeForBridgeNavigationCommand(props.navigationCommand),
		};
	}
	return {
		navigationCommand: undefined,
		viewerMode: props.viewerMode ?? 'review',
	};
}

function viewerModeForBridgeNavigationCommand(
	navigationCommand: BridgeViewerNavigationCommand,
): 'file' | 'review' {
	switch (navigationCommand.context) {
		case 'files':
			return 'file';
		case 'review':
			return 'review';
	}
	return 'review';
}

export function bridgeReviewNavigationCommandForWorktreeDescriptor(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly reviewSource?: Extract<BridgeViewerSource, { readonly sourceKind: 'reviewComparison' }>;
}): BridgeViewerNavigationCommand {
	const reviewSource =
		props.reviewSource ??
		defaultReviewSourceForWorktreeDescriptor({
			descriptor: props.descriptor,
		});
	return {
		commandId: [
			'bridge',
			'worktree',
			'review',
			'file',
			props.descriptor.sourceIdentity.sourceId,
			props.descriptor.fileId,
			props.descriptor.contentHash ?? props.descriptor.contentHandle,
		].join(':'),
		commandKind: 'activateTarget',
		context: 'review',
		restoreMemory: true,
		source: reviewSource,
		target: {
			targetKind: 'file',
			comparisonId: reviewSource.comparisonId,
			fileRef: {
				sourceId: reviewSource.sourceId,
				path: props.descriptor.path,
			},
			version: 'current',
		},
	};
}

function defaultReviewSourceForWorktreeDescriptor(props: {
	readonly descriptor: WorktreeFileDescriptor;
}): Extract<BridgeViewerSource, { readonly sourceKind: 'reviewComparison' }> {
	return {
		sourceKind: 'reviewComparison',
		sourceId: `${props.descriptor.sourceIdentity.sourceId}:review`,
		comparisonId: `worktree:${props.descriptor.sourceIdentity.worktreeId}:${props.descriptor.sourceIdentity.subscriptionGeneration}`,
	};
}

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const incomingNavigationCommand = props.navigationCommand;
	const incomingViewerMode = props.viewerMode;
	const [activeViewerState, setActiveViewerState] = useState<BridgeActiveViewerState>(() =>
		activeViewerStateForBridgeInputs({
			navigationCommand: incomingNavigationCommand,
			viewerMode: incomingViewerMode,
		}),
	);
	const rememberedNavigationCommandsRef = useRef<BridgeRememberedNavigationCommands>({
		file: activeViewerState.viewerMode === 'file' ? activeViewerState.navigationCommand : undefined,
		review:
			activeViewerState.viewerMode === 'review' ? activeViewerState.navigationCommand : undefined,
	});
	const [mountedViewerModes, setMountedViewerModes] = useState<ReadonlySet<BridgeViewerMode>>(
		() => new Set<BridgeViewerMode>([activeViewerState.viewerMode]),
	);
	useEffect((): void => {
		const nextViewerState = activeViewerStateForBridgeInputs({
			navigationCommand: incomingNavigationCommand,
			viewerMode: incomingViewerMode,
		});
		if (nextViewerState.navigationCommand !== undefined) {
			rememberedNavigationCommandsRef.current[nextViewerState.viewerMode] =
				nextViewerState.navigationCommand;
		}
		setMountedViewerModes((currentMountedViewerModes): ReadonlySet<BridgeViewerMode> => {
			if (currentMountedViewerModes.has(nextViewerState.viewerMode)) {
				return currentMountedViewerModes;
			}
			return new Set<BridgeViewerMode>([...currentMountedViewerModes, nextViewerState.viewerMode]);
		});
		setActiveViewerState(nextViewerState);
	}, [incomingNavigationCommand, incomingViewerMode]);
	const activateViewerMode = useCallback((viewerMode: BridgeViewerMode): void => {
		setMountedViewerModes((currentMountedViewerModes): ReadonlySet<BridgeViewerMode> => {
			if (currentMountedViewerModes.has(viewerMode)) {
				return currentMountedViewerModes;
			}
			return new Set<BridgeViewerMode>([...currentMountedViewerModes, viewerMode]);
		});
		setActiveViewerState({
			navigationCommand: rememberedNavigationCommandsRef.current[viewerMode],
			viewerMode,
		});
	}, []);
	const activateNavigationCommand = useCallback(
		(navigationCommand: BridgeViewerNavigationCommand) => {
			const viewerMode = viewerModeForBridgeNavigationCommand(navigationCommand);
			rememberedNavigationCommandsRef.current[viewerMode] = navigationCommand;
			setMountedViewerModes((currentMountedViewerModes): ReadonlySet<BridgeViewerMode> => {
				if (currentMountedViewerModes.has(viewerMode)) {
					return currentMountedViewerModes;
				}
				return new Set<BridgeViewerMode>([...currentMountedViewerModes, viewerMode]);
			});
			setActiveViewerState({
				navigationCommand,
				viewerMode,
			});
		},
		[],
	);
	const rememberedFileNavigationCommand = rememberedNavigationCommandsRef.current.file;
	const rememberedReviewNavigationCommand = rememberedNavigationCommandsRef.current.review;

	return (
		<BridgeViewerAppShell appOwner="BridgeApp" mode={activeViewerState.viewerMode}>
			{mountedViewerModes.has('file') ? (
				<div
					className="h-full min-h-0"
					data-bridge-viewer-mode-active={
						activeViewerState.viewerMode === 'file' ? 'true' : 'false'
					}
					data-bridge-viewer-mode-host="file"
					data-testid="bridge-viewer-mode-host-file"
					hidden={activeViewerState.viewerMode !== 'file'}
				>
					<BridgeFileViewerMode
						{...props}
						isActive={activeViewerState.viewerMode === 'file'}
						onActivateNavigationCommand={activateNavigationCommand}
						viewerHeaderControls={
							<BridgeViewerContextSwitcher
								mode={activeViewerState.viewerMode}
								onModeChange={activateViewerMode}
							/>
						}
						{...(rememberedFileNavigationCommand === undefined
							? {}
							: { navigationCommand: rememberedFileNavigationCommand })}
					/>
				</div>
			) : null}
			{mountedViewerModes.has('review') ? (
				<div
					className="h-full min-h-0"
					data-bridge-viewer-mode-active={
						activeViewerState.viewerMode === 'review' ? 'true' : 'false'
					}
					data-bridge-viewer-mode-host="review"
					data-testid="bridge-viewer-mode-host-review"
					hidden={activeViewerState.viewerMode !== 'review'}
				>
					<BridgeReviewViewerMode
						{...props}
						isActive={activeViewerState.viewerMode === 'review'}
						viewerHeaderControls={
							<BridgeViewerContextSwitcher
								mode={activeViewerState.viewerMode}
								onModeChange={activateViewerMode}
							/>
						}
						{...(rememberedReviewNavigationCommand === undefined
							? {}
							: { navigationCommand: rememberedReviewNavigationCommand })}
					/>
				</div>
			) : null}
		</BridgeViewerAppShell>
	);
}

function BridgeFileViewerMode(
	props: BridgeAppProps & {
		readonly isActive: boolean;
		readonly onActivateNavigationCommand: (
			navigationCommand: BridgeViewerNavigationCommand,
		) => void;
		readonly viewerHeaderControls: ReactElement;
	},
): ReactElement {
	const existingOpenReviewComparison = props.fileViewerProps?.onOpenReviewComparison;
	const onActivateNavigationCommand = props.onActivateNavigationCommand;
	const reviewNavigationSource = props.reviewNavigationSource;
	const openReviewComparison = useCallback(
		(descriptor: WorktreeFileDescriptor): void => {
			existingOpenReviewComparison?.(descriptor);
			onActivateNavigationCommand(
				bridgeReviewNavigationCommandForWorktreeDescriptor({
					descriptor,
					...(reviewNavigationSource === undefined ? {} : { reviewSource: reviewNavigationSource }),
				}),
			);
		},
		[existingOpenReviewComparison, onActivateNavigationCommand, reviewNavigationSource],
	);
	return (
		<BridgeFileViewerApp
			{...(props.codeViewWorkerFactory === undefined
				? {}
				: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
			{...(props.codeViewWorkerPoolEnabled === undefined
				? {}
				: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
			{...props.fileViewerProps}
			{...(props.navigationCommand === undefined
				? {}
				: { navigationCommand: props.navigationCommand })}
			onOpenReviewComparison={openReviewComparison}
			viewerHeaderControls={props.viewerHeaderControls}
		/>
	);
}

function BridgeReviewViewerMode(
	props: BridgeAppProps & {
		readonly isActive: boolean;
		readonly viewerHeaderControls: ReactElement;
	},
): ReactElement {
	const target = props.target ?? document;
	const reviewFrameAuthorityRef = useRef<BridgeReviewFrameAuthority | null>(
		readBridgeReviewFrameAuthority(),
	);
	const viewerStore = useBridgeReviewViewerStore();
	const contentRegistry = useBridgeReviewContentRegistry();
	const descriptorRegistry = useBridgeResourceDescriptorRegistry();
	const reviewContentDescriptorRefsByHandleIdRef = useRef<ReadonlyMap<string, BridgeDescriptorRef>>(
		new Map<string, BridgeDescriptorRef>(),
	);
	const invalidatedReviewFreshnessKeysRef = useRef<Set<string>>(new Set<string>());
	const reviewDemandSchedulerRef = useRef<BridgeDemandScheduler | null>(null);
	if (reviewDemandSchedulerRef.current === null) {
		reviewDemandSchedulerRef.current = createBridgeReviewDemandScheduler();
	}
	const reviewDemandScheduler = reviewDemandSchedulerRef.current;
	const fetchContentRef = useRef<BridgeContentFetch | undefined>(props.fetchContent);
	fetchContentRef.current = props.fetchContent;
	const resourceExecutor = useBridgeReviewResourceExecutor({
		descriptorRegistry,
		descriptorRefsByDescriptorIdRef: reviewContentDescriptorRefsByHandleIdRef,
		fetchContentRef,
		invalidatedFreshnessKeysRef: invalidatedReviewFreshnessKeysRef,
	});
	const projection = useStore(viewerStore, (state) => state.projection);
	const rootSnapshot = useStore(viewerStore, selectBridgeReviewViewerRootSnapshot);
	const viewerActions = useStore(viewerStore, (state) => state.actions);
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [diffStatus, setDiffStatus] = useState<BridgeDiffStatusState>({
		status: 'idle',
		error: null,
		epoch: 0,
	});
	const [selectedContentResourcesState, setSelectedContentResourcesState] =
		useState<SelectedContentResourcesState | null>(null);
	const [selectedContentRetryVersion, setSelectedContentRetryVersion] = useState(0);
	const selectedContentRetryScheduledRef = useRef(false);
	const [reviewContentInvalidationVersion, setReviewContentInvalidationVersion] = useState(0);
	const [selectedMarkdownPreviewState, setSelectedMarkdownPreviewState] =
		useState<SelectedMarkdownPreviewState | null>(null);
	const selectedMarkdownPreviewStateRef = useRef<SelectedMarkdownPreviewState | null>(null);
	selectedMarkdownPreviewStateRef.current = selectedMarkdownPreviewState;
	const [isTreeSearchOpen, setIsTreeSearchOpen] = useState(false);
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const lastFirstRenderPackageRef = useRef<string | null>(null);
	const codeViewControlHandleRef = useRef<BridgeCodeViewControlHandle | null>(null);
	const selectedContentAbortControllerRef = useRef<AbortController | null>(null);
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(null);
	reviewPackageRef.current = reviewPackage;
	const projectionRef = useRef(projection);
	projectionRef.current = projection;
	const rootSnapshotRef = useRef(rootSnapshot);
	rootSnapshotRef.current = rootSnapshot;
	const controlProbeSequenceRef = useRef(0);
	const rpcClient = useMemo(
		() =>
			createBridgeRPCClient({
				target,
				getTraceContext: (): BridgeTraceContext | null =>
					telemetryRecorderRef.current.isEnabled('web')
						? createChildTraceContext(
								currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
							)
						: null,
				telemetryRecorder: {
					isEnabled: (scope) => telemetryRecorderRef.current.isEnabled(scope),
					record: (sample) => telemetryRecorderRef.current.record(sample),
					measure: (measureProps) => telemetryRecorderRef.current.measure(measureProps),
					flush: (flushProps) => telemetryRecorderRef.current.flush(flushProps),
				},
			}),
		[target],
	);
	const defaultProjectionWorkerClient = useMemo(
		() => createBridgeReviewProjectionWebWorkerClient(),
		[],
	);
	const projectionWorkerClient = props.projectionWorkerClient ?? defaultProjectionWorkerClient;
	const defaultMarkdownWorkerClient = useMemo(
		() => createBridgeMarkdownRenderWebWorkerClient(),
		[],
	);
	const markdownWorkerClient =
		props.markdownWorkerClient === undefined
			? defaultMarkdownWorkerClient
			: props.markdownWorkerClient;
	const selectedContentResources = useMemo(
		(): BridgeCodeViewContentResources | null =>
			selectedContentResourcesForCurrentSelection({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				selectedContentResourcesState,
			}),
		[reviewPackage, rootSnapshot.selectedItemId, selectedContentResourcesState],
	);
	const loadVisibleContentResourcesThroughDemand = useCallback(
		async (
			loadProps: LoadReviewItemContentResourcesProps,
		): Promise<VisibleReviewContentLoadResult> =>
			loadReviewItemContentResourcesThroughDemandResult({
				reviewPackage: loadProps.reviewPackage,
				itemId: loadProps.itemId,
				interest: 'visible',
				resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
					reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
				scheduler: reviewDemandScheduler,
				executor: resourceExecutor,
				traceContext: loadProps.traceContext ?? null,
				...(loadProps.signal === undefined ? {} : { signal: loadProps.signal }),
				...(loadProps.telemetryRecorder === undefined
					? {}
					: { telemetryRecorder: loadProps.telemetryRecorder }),
			}),
		[resourceExecutor, reviewDemandScheduler],
	);
	const visibleContentHydration = useVisibleReviewContentHydration({
		contentRegistry,
		loadContentResources: loadVisibleContentResourcesThroughDemand,
		reviewPackage: props.isActive ? reviewPackage : null,
		selectedItemId: props.isActive ? rootSnapshot.selectedItemId : null,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		telemetryRecorder: telemetryRecorderRef.current,
		contentInvalidationVersion: reviewContentInvalidationVersion,
	});
	const flushTelemetry = useCallback((): void => {
		telemetryRecorderRef.current.flush();
	}, []);
	const selectReviewItem = useCallback(
		(itemId: string, options: SelectReviewItemOptions = {}): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (currentReviewPackage === null || !(itemId in currentReviewPackage.itemsById)) {
				return false;
			}
			const isSelectionChange = rootSnapshotRef.current.selectedItemId !== itemId;
			if (isSelectionChange) {
				selectedContentAbortControllerRef.current?.abort();
				selectedContentAbortControllerRef.current = null;
				cancelReviewItemDemandForInterest({
					descriptorRefsByHandleId: reviewContentDescriptorRefsByHandleIdRef.current,
					interest: 'visible',
					item: currentReviewPackage.itemsById[itemId],
					resourceExecutor,
					reviewDemandScheduler,
				});
			}
			viewerActions.setSelectedItemId(itemId);
			viewerActions.setRenderMode({ kind: 'codeView' });
			if (isSelectionChange) {
				setSelectedContentResourcesState(null);
			}
			lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(currentReviewPackage, itemId);
			rpcClient.sendCommand({
				method: 'review.markFileViewed',
				params: { fileId: itemId },
			});
			if (options.revealInCodeView !== false) {
				const revealSelectedItem = (): void => {
					if (rootSnapshotRef.current.selectedItemId !== itemId) {
						return;
					}
					codeViewControlHandleRef.current?.scrollToItem(itemId, {
						behavior: options.revealBehavior ?? 'smooth-auto',
					});
				};
				if (typeof requestAnimationFrame === 'function') {
					requestAnimationFrame(revealSelectedItem);
				} else {
					queueMicrotask(revealSelectedItem);
				}
			}
			return true;
		},
		[resourceExecutor, reviewDemandScheduler, rpcClient, viewerActions],
	);
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const initialReviewFileTarget = useMemo(
		() => reviewFileTargetForNavigationCommand(props.navigationCommand),
		[props.navigationCommand],
	);
	useEffect((): void => {
		if (
			!props.isActive ||
			reviewPackage === null ||
			projection === null ||
			initialReviewFileTarget === null
		) {
			return;
		}
		if (appliedNavigationCommandIdRef.current === props.navigationCommand?.commandId) {
			return;
		}
		const itemId = itemIdForReviewFileNavigationTarget({
			reviewPackage,
			target: initialReviewFileTarget,
		});
		if (itemId === null || !projection.orderedItemIds.includes(itemId)) {
			return;
		}
		appliedNavigationCommandIdRef.current = props.navigationCommand?.commandId ?? null;
		selectReviewItem(itemId, {
			revealBehavior: 'instant',
		});
	}, [
		initialReviewFileTarget,
		props.isActive,
		projection,
		props.navigationCommand?.commandId,
		reviewPackage,
		selectReviewItem,
	]);
	useBridgeReviewProjectionCoordinator({
		store: viewerStore,
		reviewPackage,
		projectionMode: rootSnapshot.projectionMode,
		facets: rootSnapshot.facets,
		gitStatusFilter: rootSnapshot.gitStatusFilter,
		fileClassFilter: rootSnapshot.fileClassFilter,
		projectionWorkerClient,
		telemetryRecorder: telemetryRecorderRef.current,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		flushTelemetry,
	});

	useEffect((): void => {
		if (!props.isActive || reviewPackage === null || projection === null) {
			return;
		}
		if (
			rootSnapshot.selectedItemId !== null &&
			projection.orderedItemIds.includes(rootSnapshot.selectedItemId)
		) {
			return;
		}

		const targetItemId =
			initialReviewFileTarget === null
				? null
				: itemIdForReviewFileNavigationTarget({
						reviewPackage,
						target: initialReviewFileTarget,
					});
		const nextSelectedItemId =
			targetItemId !== null && projection.orderedItemIds.includes(targetItemId)
				? targetItemId
				: (projection.orderedItemIds[0] ?? null);
		if (rootSnapshot.selectedItemId === nextSelectedItemId) {
			return;
		}

		selectedContentAbortControllerRef.current?.abort();
		selectedContentAbortControllerRef.current = null;
		setSelectedContentResourcesState(null);
		setSelectedMarkdownPreviewState(null);
		viewerActions.setSelectedItemId(nextSelectedItemId);
		viewerActions.setRenderMode({ kind: 'codeView' });
	}, [
		initialReviewFileTarget,
		projection,
		props.isActive,
		reviewPackage,
		rootSnapshot.selectedItemId,
		viewerActions,
	]);

	useEffect((): void => {
		contentRegistry.setActiveIdentity(
			reviewPackage === null
				? null
				: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
					},
		);
	}, [contentRegistry, reviewPackage]);

	useEffect((): (() => void) => {
		let handshakeSession: BridgePageHandshakeSession | null = null;
		const configureTelemetryRecorder = (): void => {
			const telemetryConfig = handshakeSession?.getTelemetryConfig() ?? null;
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(
				telemetryConfig,
				createBridgeTelemetryEventSink({
					rpcClient,
					methodName: telemetryConfig?.rpcMethodName ?? 'system.bridgeTelemetry',
				}),
			);
		};
		const uninstallPushReceiver = installBridgePushReceiver({
			target,
			getPushNonce: (): string | null => handshakeSession?.getPushNonce() ?? null,
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				recordPackageApplyTelemetry(telemetryRecorderRef.current, envelope);
				applyReviewEnvelope(
					envelope,
					setReviewPackage,
					setDiffStatus,
					(itemId: string | null): void => viewerActions.setSelectedItemId(itemId),
					(): string | null => viewerStore.getState().rootSnapshot.selectedItemId,
					reviewPackageRef,
					reviewPackageTelemetryContextRef.current,
					currentReviewPackageTelemetryContextRef,
					descriptorRegistry,
					reviewContentDescriptorRefsByHandleIdRef,
					reviewDemandScheduler,
					resourceExecutor,
					reviewFrameAuthorityRef.current,
					invalidatedReviewFreshnessKeysRef,
					setReviewContentInvalidationVersion,
				);
			},
			onDroppedEnvelope: (reason: BridgePushDropReason): void => {
				recordPushDropTelemetry(telemetryRecorderRef.current, reason);
			},
		});
		handshakeSession = installBridgePageHandshakeSession(target, {
			onTelemetryConfig: configureTelemetryRecorder,
		});
		configureTelemetryRecorder();
		return (): void => {
			uninstallPushReceiver();
			handshakeSession?.uninstall();
		};
	}, [
		descriptorRegistry,
		resourceExecutor,
		reviewDemandScheduler,
		rpcClient,
		props.isActive,
		target,
		viewerActions,
		viewerStore,
	]);

	useLayoutEffect((): (() => void) => {
		if (!props.isActive) {
			return (): void => {};
		}
		const handleSelectReviewItem = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			if (!isRecord(detail) || typeof detail['itemId'] !== 'string') {
				return;
			}
			selectReviewItem(detail['itemId']);
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		}
		return (): void => {
			target.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			}
		};
	}, [props.isActive, selectReviewItem, target]);

	useLayoutEffect((): (() => void) => {
		if (!props.isActive) {
			return (): void => {};
		}
		const handleBridgeAppControl = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const parsedCommand = bridgeAppControlCommandSchema.safeParse(detail);
			if (!parsedCommand.success) {
				publishBridgeAppControlProbe({
					probe: makeBridgeAppControlProbe({
						command: {
							method: 'bridge.fileTree.search',
							searchText: '',
							searchMode: { kind: 'text' },
						},
						status: 'rejected',
						reason: 'invalid_control_command',
						sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
						rootSnapshot: rootSnapshotRef.current,
					}),
				});
				return;
			}
			const result = applyBridgeAppControlCommand({
				command: parsedCommand.data,
				markdownWorkerClient,
				projection: projectionRef.current,
				rootSnapshot: rootSnapshotRef.current,
				reviewPackage: reviewPackageRef.current,
				selectReviewItem,
				selectedContentResources,
				selectedMarkdownPreviewState,
				setTreeSearchOpen: setIsTreeSearchOpen,
				codeViewControlHandle: codeViewControlHandleRef.current,
				viewerActions,
			});
			publishBridgeAppControlProbe({
				probe: makeBridgeAppControlProbe({
					command: parsedCommand.data,
					status: result.status,
					reason: result.reason,
					sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
					rootSnapshot: viewerStore.getState().rootSnapshot,
				}),
			});
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_review_control', handleBridgeAppControl);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_review_control', handleBridgeAppControl);
		}
		return (): void => {
			target.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			}
		};
	}, [
		markdownWorkerClient,
		props.isActive,
		selectReviewItem,
		selectedContentResources,
		selectedMarkdownPreviewState,
		target,
		viewerActions,
		viewerStore,
	]);

	useLayoutEffect((): (() => void) => {
		if (!props.isActive) {
			selectedContentAbortControllerRef.current?.abort();
			selectedContentAbortControllerRef.current = null;
			return (): void => {};
		}
		let didCancel = false;
		const contentAbortController = new AbortController();
		selectedContentAbortControllerRef.current = contentAbortController;
		const selectedItemId = rootSnapshot.selectedItemId;
		if (reviewPackage === null || selectedItemId === null) {
			setSelectedContentResourcesState(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
				if (selectedContentAbortControllerRef.current === contentAbortController) {
					selectedContentAbortControllerRef.current = null;
				}
			};
		}
		const selectedItem = reviewPackage.itemsById[selectedItemId];
		if (selectedItem === undefined) {
			setSelectedContentResourcesState(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
				if (selectedContentAbortControllerRef.current === contentAbortController) {
					selectedContentAbortControllerRef.current = null;
				}
			};
		}
		const selectedContentKey = makeSelectedContentResourcesKey(reviewPackage, selectedItemId);
		setSelectedContentResourcesState(
			(current: SelectedContentResourcesState | null): SelectedContentResourcesState | null =>
				current?.contentKey === selectedContentKey
					? current
					: {
							itemId: selectedItemId,
							contentKey: selectedContentKey,
							status: 'loading',
							resources: null,
						},
		);
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		recordBridgeViewerContentQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
			item: selectedItem,
			interest: 'selected',
		});
		void loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: selectedItemId,
			interest: 'selected',
			resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
				reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
			scheduler: reviewDemandScheduler,
			executor: resourceExecutor,
			signal: contentAbortController.signal,
			traceContext: telemetryRecorderRef.current.isEnabled('web')
				? createChildTraceContext(parentTraceContext)
				: null,
			telemetryRecorder: telemetryRecorderRef.current,
		})
			.then((loadResult): void => {
				if (!didCancel) {
					setSelectedContentResourcesState(
						selectedContentResourcesStateFromDemandLoadResult({
							itemId: selectedItemId,
							contentKey: selectedContentKey,
							loadResult,
						}),
					);
					if (loadResult.status === 'deferred') {
						scheduleSelectedContentRetry({
							scheduledRef: selectedContentRetryScheduledRef,
							setSelectedContentRetryVersion,
						});
					}
				}
			})
			.catch((): void => {
				if (!didCancel) {
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						status: 'failed',
						resources: null,
					});
				}
			});
		return (): void => {
			didCancel = true;
			contentAbortController.abort();
			if (selectedContentAbortControllerRef.current === contentAbortController) {
				selectedContentAbortControllerRef.current = null;
			}
		};
	}, [
		resourceExecutor,
		reviewDemandScheduler,
		props.isActive,
		reviewPackage,
		reviewContentInvalidationVersion,
		rootSnapshot.selectedItemId,
		selectedContentRetryVersion,
		setSelectedContentRetryVersion,
	]);

	useEffect((): (() => void) => {
		let didCancel = false;
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		if (!props.isActive) {
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}
		if (reviewPackage === null || rootSnapshot.selectedItemId === null) {
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		const selectedContentKey = makeSelectedContentResourcesKey(
			reviewPackage,
			rootSnapshot.selectedItemId,
		);
		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: rootSnapshot.selectedItemId,
			resources: selectedContentResources,
		});
		const selectedMarkdownPreviewSnapshot = selectedMarkdownPreviewStateRef.current;

		if (decision.kind === 'codeView') {
			if (
				decision.reason === 'contentPending' &&
				rootSnapshot.renderMode.kind === 'markdownPreview'
			) {
				setSelectedMarkdownPreviewState(null);
				return (): void => {
					didCancel = true;
				};
			}
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			if (decision.reason !== 'contentPending') {
				recordMarkdownPreviewFallbackTelemetry({
					telemetryRecorder: telemetryRecorderRef.current,
					parentTraceContext,
					reason: decision.reason,
				});
			}
			return (): void => {
				didCancel = true;
			};
		}

		if (
			selectedMarkdownPreviewSnapshot !== null &&
			selectedMarkdownPreviewSnapshot.itemId === rootSnapshot.selectedItemId &&
			selectedMarkdownPreviewSnapshot.contentKey === selectedContentKey &&
			selectedMarkdownPreviewSnapshot.status === 'failed'
		) {
			viewerActions.setRenderMode({ kind: 'codeView' });
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		if (markdownWorkerClient === null) {
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			recordMarkdownPreviewFallbackTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				reason: 'workerUnavailable',
			});
			return (): void => {
				didCancel = true;
			};
		}

		if (rootSnapshot.renderMode.kind !== 'markdownPreview') {
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		if (
			selectedMarkdownPreviewSnapshot !== null &&
			selectedMarkdownPreviewSnapshot.itemId === rootSnapshot.selectedItemId &&
			selectedMarkdownPreviewSnapshot.contentKey === selectedContentKey &&
			(selectedMarkdownPreviewSnapshot.status === 'rendering' ||
				selectedMarkdownPreviewSnapshot.status === 'ready')
		) {
			return (): void => {
				didCancel = true;
			};
		}

		const source = decision.source;
		const task = markdownWorkerClient.startRender({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			itemId: source.itemId,
			itemVersion: source.itemVersion,
			contentCacheKey: source.contentCacheKey,
			contentHash: source.contentHash,
			markdownText: source.markdownText,
			sourcePath: source.sourcePath,
			abortKey: bridgeMarkdownPreviewAbortKey,
		});
		setSelectedMarkdownPreviewState({
			itemId: source.itemId,
			contentKey: selectedContentKey,
			sourcePath: source.sourcePath,
			status: 'rendering',
			html: null,
		});
		recordMarkdownRenderQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
		});
		void task.completed.then((completion: BridgeMarkdownRenderWorkerClientCompletion): void => {
			if (didCancel) {
				return;
			}
			recordMarkdownRenderCompletionTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				completion,
			});
			if (completion.status !== 'success') {
				viewerActions.setRenderMode({ kind: 'codeView' });
				setSelectedMarkdownPreviewState({
					itemId: source.itemId,
					contentKey: selectedContentKey,
					sourcePath: source.sourcePath,
					status: 'failed',
					html: null,
				});
				return;
			}
			if (isOversizedMarkdownPreviewOutput(completion.response.html)) {
				viewerActions.setRenderMode({ kind: 'codeView' });
				setSelectedMarkdownPreviewState({
					itemId: source.itemId,
					contentKey: selectedContentKey,
					sourcePath: source.sourcePath,
					status: 'failed',
					html: null,
				});
				return;
			}
			setSelectedMarkdownPreviewState({
				itemId: source.itemId,
				contentKey: selectedContentKey,
				sourcePath: source.sourcePath,
				status: 'ready',
				html: completion.response.html,
			});
		});

		return (): void => {
			didCancel = true;
			markdownWorkerClient.abort(bridgeMarkdownPreviewAbortKey);
		};
	}, [
		markdownWorkerClient,
		props.isActive,
		reviewPackage,
		rootSnapshot.renderMode.kind,
		rootSnapshot.selectedItemId,
		selectedContentResources,
		viewerActions,
	]);

	useEffect((): void => {
		if (
			!props.isActive ||
			reviewPackage === null ||
			projection === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const packageKey = `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
		if (lastFirstRenderPackageRef.current === packageKey) {
			return;
		}
		lastFirstRenderPackageRef.current = packageKey;
		const telemetryContext = reviewPackageTelemetryContextRef.current.get(packageKey);
		telemetryRecorderRef.current.record({
			scope: 'web',
			name: 'performance.bridge.web.first_render',
			durationMilliseconds: null,
			traceContext: createChildTraceContext(telemetryContext?.traceContext ?? null),
			stringAttributes: {
				'agentstudio.bridge.phase': 'render',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.slice': telemetryContext?.slice ?? 'unknown',
				'agentstudio.bridge.transport': 'push',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		telemetryRecorderRef.current.flush();
	}, [projection, props.isActive, reviewPackage]);

	useEffect((): void => {
		if (
			!props.isActive ||
			reviewPackage === null ||
			rootSnapshot.selectedItemId === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const markedItemKey = makeTelemetryMarkedItemKey(reviewPackage, rootSnapshot.selectedItemId);
		if (lastTelemetryMarkedItemRef.current === markedItemKey) {
			return;
		}
		lastTelemetryMarkedItemRef.current = markedItemKey;
		rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: rootSnapshot.selectedItemId },
		});
	}, [props.isActive, reviewPackage, rootSnapshot.selectedItemId, rpcClient]);

	const currentSelectedContentKey =
		reviewPackage !== null && rootSnapshot.selectedItemId !== null
			? makeSelectedContentResourcesKey(reviewPackage, rootSnapshot.selectedItemId)
			: null;
	const selectedCanvasLoadingReason = selectedCanvasLoadingReasonForCurrentSelection({
		selectedContentKey: currentSelectedContentKey,
		selectedContentResourcesState,
		selectedItemId: rootSnapshot.selectedItemId,
		selectedMarkdownPreviewState,
	});
	const selectedContentLoadingItemId =
		selectedCanvasLoadingReason === 'content' ? rootSnapshot.selectedItemId : null;
	const selectedItemPresentation = useMemo(
		() =>
			selectedItemPresentationForReviewFileTarget({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				target: initialReviewFileTarget,
			}),
		[initialReviewFileTarget, reviewPackage, rootSnapshot.selectedItemId],
	);

	return reviewPackage === null && diffStatus.status === 'loading' ? (
		<BridgeReviewPackageLoadingShell />
	) : reviewPackage === null && diffStatus.status === 'error' ? (
		<BridgeReviewPackageFailedShell error={diffStatus.error} />
	) : reviewPackage === null ? (
		<BridgeReviewEmptyShell />
	) : rootSnapshot.projectionStatus === 'failed' ? (
		<BridgeReviewProjectionFailedShell />
	) : projection === null ? (
		<BridgeReviewProjectionPendingShell />
	) : (
		<ReviewViewerShell
			fileClassFilter={rootSnapshot.fileClassFilter}
			gitStatusFilter={rootSnapshot.gitStatusFilter}
			onCodeViewControlHandleChange={(handle): void => {
				codeViewControlHandleRef.current = handle;
			}}
			onFileClassFilterChange={viewerActions.setFileClassFilter}
			onGitStatusFilterChange={viewerActions.setGitStatusFilter}
			onProjectionModeChange={viewerActions.setProjectionMode}
			onSelectItem={selectReviewItem}
			onTreeSearchOpen={(): void => setIsTreeSearchOpen(true)}
			onTreeSearchModeChange={viewerActions.setTreeSearchMode}
			onTreeSearchTextChange={viewerActions.setTreeSearchText}
			projection={projection}
			projectionMode={rootSnapshot.projectionMode}
			reviewPackage={reviewPackage}
			viewerHeaderControls={props.viewerHeaderControls}
			selectedContentResources={selectedContentResources}
			selectedContentLoadingItemId={selectedContentLoadingItemId}
			selectedItemPresentation={selectedItemPresentation}
			selectedContentUnavailablePath={selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				selectedContentResourcesState,
			})}
			selectedCanvasLoadingReason={selectedCanvasLoadingReason}
			selectedItemId={rootSnapshot.selectedItemId}
			visibleContentResourcesByItemId={visibleContentHydration.visibleContentResourcesByItemId}
			visibleLoadingItemIds={visibleContentHydration.visibleLoadingItemIds}
			visibleLoadingItemCount={visibleContentHydration.visibleLoadingItemCount}
			visibleReadyItemCount={visibleContentHydration.visibleReadyItemCount}
			onCodeViewVisibleItemIdsChange={visibleContentHydration.setVisibleItemIds}
			{...(props.codeViewWorkerPoolEnabled === undefined
				? {}
				: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
			{...(props.codeViewWorkerFactory === undefined
				? {}
				: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
			selectedMarkdownPreviewHtml={
				rootSnapshot.renderMode.kind === 'markdownPreview' &&
				selectedMarkdownPreviewState !== null &&
				selectedMarkdownPreviewState.status === 'ready' &&
				selectedMarkdownPreviewState.itemId === rootSnapshot.selectedItemId &&
				selectedMarkdownPreviewState.contentKey === currentSelectedContentKey
					? selectedMarkdownPreviewState.html
					: null
			}
			selectedMarkdownPreviewSourcePath={
				rootSnapshot.renderMode.kind === 'markdownPreview' &&
				selectedMarkdownPreviewState !== null &&
				selectedMarkdownPreviewState.status === 'ready' &&
				selectedMarkdownPreviewState.itemId === rootSnapshot.selectedItemId &&
				selectedMarkdownPreviewState.contentKey === currentSelectedContentKey
					? selectedMarkdownPreviewState.sourcePath
					: null
			}
			telemetryParentTraceContext={
				currentReviewPackageTelemetryContextRef.current?.traceContext ?? null
			}
			telemetryRecorder={telemetryRecorderRef.current}
			treeSearchOpen={isTreeSearchOpen}
			treeSearchMode={rootSnapshot.treeSearchMode}
			treeSearchText={rootSnapshot.treeSearchText}
		/>
	);
}

interface ApplyBridgeAppControlCommandProps {
	readonly command: BridgeAppControlCommand;
	readonly codeViewControlHandle: BridgeCodeViewControlHandle | null;
	readonly markdownWorkerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectReviewItem: (itemId: string, options?: SelectReviewItemOptions) => boolean;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
	readonly setTreeSearchOpen: (isOpen: boolean) => void;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}

interface ApplyBridgeAppControlCommandResult {
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
}

interface MakeBridgeAppControlProbeProps {
	readonly command: BridgeAppControlCommand;
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
	readonly sequence: number;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
}

function applyBridgeAppControlCommand(
	props: ApplyBridgeAppControlCommandProps,
): ApplyBridgeAppControlCommandResult {
	const {
		command,
		codeViewControlHandle,
		markdownWorkerClient,
		projection,
		reviewPackage,
		selectReviewItem,
		selectedContentResources,
		selectedMarkdownPreviewState,
		viewerActions,
	} = props;
	switch (command.method) {
		case 'bridge.diff.scrollToFile':
			if (reviewPackage === null || !(command.itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (!projectionContainsItemId(projection, command.itemId)) {
				return { status: 'rejected', reason: 'item_not_rendered' };
			}
			if (codeViewControlHandle === null) {
				return { status: 'rejected', reason: 'code_view_unavailable' };
			}
			if (!codeViewControlHandle.scrollToItem(command.itemId, { behavior: 'smooth-auto' })) {
				return { status: 'rejected', reason: 'item_not_rendered' };
			}
			return selectReviewItem(command.itemId, { revealInCodeView: false })
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		case 'bridge.diff.expandFile':
		case 'bridge.diff.collapseFile':
			if (reviewPackage === null || !(command.itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (!projectionContainsItemId(projection, command.itemId)) {
				return { status: 'rejected', reason: 'item_not_rendered' };
			}
			if (codeViewControlHandle === null) {
				return { status: 'rejected', reason: 'code_view_unavailable' };
			}
			return codeViewControlHandle.setItemCollapsed(
				command.itemId,
				command.method === 'bridge.diff.collapseFile',
			)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_rendered' };
		case 'bridge.fileTree.search':
			props.setTreeSearchOpen(true);
			viewerActions.setTreeSearchText(command.searchText);
			viewerActions.setTreeSearchMode(command.searchMode);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.setFilter':
			viewerActions.setGitStatusFilter(command.gitStatusFilter);
			viewerActions.setFileClassFilter(command.fileClassFilter);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.revealPath': {
			const itemId = projection?.primaryItemIdByTreePath[command.path] ?? null;
			if (itemId === null) {
				return { status: 'rejected', reason: 'path_not_found' };
			}
			return selectReviewItem(itemId)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		}
		case 'bridge.fileView.showMarkdownPreview': {
			const itemId = command.itemId ?? props.rootSnapshot.selectedItemId;
			if (itemId === null) {
				return { status: 'rejected', reason: 'item_not_selected' };
			}
			if (reviewPackage === null || !(itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (itemId !== props.rootSnapshot.selectedItemId) {
				if (!selectReviewItem(itemId, { revealInCodeView: false })) {
					return { status: 'rejected', reason: 'item_not_found' };
				}
				viewerActions.setRenderMode({ kind: 'markdownPreview' });
				return { status: 'pending', reason: 'preview_selection_pending' };
			}
			const decision = resolveBridgeMarkdownPreviewDecision({
				reviewPackage,
				selectedItemId: itemId,
				resources: selectedContentResources,
			});
			if (decision.kind === 'codeView') {
				if (decision.reason === 'contentPending') {
					viewerActions.setRenderMode({ kind: 'markdownPreview' });
					return { status: 'pending', reason: 'preview_content_pending' };
				}
				return { status: 'rejected', reason: decision.reason };
			}
			if (markdownWorkerClient === null) {
				return { status: 'rejected', reason: 'worker_unavailable' };
			}
			if (props.rootSnapshot.renderMode.kind !== 'markdownPreview') {
				viewerActions.setRenderMode({ kind: 'markdownPreview' });
				return { status: 'pending', reason: 'preview_render_pending' };
			}
			return selectedMarkdownPreviewState !== null &&
				selectedMarkdownPreviewState.itemId === itemId &&
				selectedMarkdownPreviewState.status === 'ready'
				? { status: 'accepted', reason: null }
				: { status: 'pending', reason: 'preview_render_pending' };
		}
	}
	return { status: 'rejected', reason: 'unsupported_method' };
}

function projectionContainsItemId(
	projection: BridgeReviewProjectionResult | null,
	itemId: string,
): boolean {
	return projection?.orderedItemIds.includes(itemId) ?? false;
}

function makeBridgeAppControlProbe(props: MakeBridgeAppControlProbeProps): BridgeAppControlProbe {
	const path = props.command.method === 'bridge.fileTree.revealPath' ? props.command.path : null;
	const itemId =
		props.command.method === 'bridge.diff.scrollToFile' ||
		props.command.method === 'bridge.diff.expandFile' ||
		props.command.method === 'bridge.diff.collapseFile' ||
		props.command.method === 'bridge.fileView.showMarkdownPreview'
			? (props.command.itemId ?? props.rootSnapshot.selectedItemId)
			: props.rootSnapshot.selectedItemId;
	return {
		sequence: props.sequence,
		method: props.command.method,
		status: props.status,
		itemId,
		path,
		treeSearchText: props.rootSnapshot.treeSearchText,
		treeSearchMode: props.rootSnapshot.treeSearchMode,
		gitStatusFilter: props.rootSnapshot.gitStatusFilter,
		fileClassFilter: props.rootSnapshot.fileClassFilter,
		renderMode: props.rootSnapshot.renderMode,
		reason: props.reason,
	};
}

function publishBridgeAppControlProbe(props: { readonly probe: BridgeAppControlProbe }): void {
	if (typeof window === 'undefined') {
		return;
	}
	window.bridgeReviewControlProbe = props.probe;
}

function nextBridgeAppControlProbeSequence(ref: { current: number }): number {
	ref.current += 1;
	return ref.current;
}

function createChildTraceContext(parent: BridgeTraceContext | null): BridgeTraceContext | null {
	return parent === null ? null : createBridgeChildTraceContext(parent);
}

function makeTelemetryMarkedItemKey(reviewPackage: BridgeReviewPackage, itemId: string): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${itemId}`;
}

function makeTelemetryPackageKey(reviewPackage: BridgeReviewPackage): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
}

function makeSelectedContentResourcesKey(
	reviewPackage: BridgeReviewPackage,
	selectedItemId: string,
): string {
	const selectedItem = reviewPackage.itemsById[selectedItemId];
	if (selectedItem === undefined) {
		return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}:${selectedItemId}:missing`;
	}
	return makeReviewItemContentResourcesKey({
		item: selectedItem,
		reviewPackage,
	});
}

interface SelectedContentResourcesForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

function selectedContentResourcesForCurrentSelection(
	props: SelectedContentResourcesForCurrentSelectionProps,
): BridgeCodeViewContentResources | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.status !== 'ready'
	) {
		return null;
	}
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	return props.selectedContentResourcesState.contentKey === selectedContentKey
		? props.selectedContentResourcesState.resources
		: null;
}

function reviewFileTargetForNavigationCommand(
	navigationCommand: BridgeViewerNavigationCommand | undefined,
): BridgeReviewFileNavigationTarget | null {
	if (navigationCommand?.context !== 'review' || navigationCommand.target?.targetKind !== 'file') {
		return null;
	}
	return navigationCommand.target;
}

function itemIdForReviewFileNavigationTarget(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly target: BridgeReviewFileNavigationTarget;
}): string | null {
	const matchedItem = Object.values(props.reviewPackage.itemsById).find(
		(item: BridgeReviewItemDescriptor): boolean =>
			item.headPath === props.target.fileRef.path || item.basePath === props.target.fileRef.path,
	);
	return matchedItem?.itemId ?? null;
}

function selectedItemPresentationForReviewFileTarget(props: {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly target: BridgeReviewFileNavigationTarget | null;
}): {
	readonly kind: 'file';
	readonly version: BridgeReviewFileNavigationTarget['version'];
} | null {
	if (props.reviewPackage === null || props.selectedItemId === null || props.target === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (
		selectedItem === undefined ||
		(selectedItem.headPath !== props.target.fileRef.path &&
			selectedItem.basePath !== props.target.fileRef.path)
	) {
		return null;
	}
	return {
		kind: 'file',
		version: props.target.version,
	};
}

export function selectedContentResourcesStateFromLoadResult(props: {
	readonly itemId: string;
	readonly contentKey: string;
	readonly contentResources: BridgeCodeViewContentResources | null;
}): SelectedContentResourcesState {
	return {
		itemId: props.itemId,
		contentKey: props.contentKey,
		status: props.contentResources === null ? 'failed' : 'ready',
		resources: props.contentResources,
	};
}

export function selectedContentResourcesStateFromDemandLoadResult(props: {
	readonly itemId: string;
	readonly contentKey: string;
	readonly loadResult: ReviewContentDemandLoadResult;
}): SelectedContentResourcesState {
	if (props.loadResult.status === 'ready') {
		return {
			itemId: props.itemId,
			contentKey: props.contentKey,
			status: 'ready',
			resources: props.loadResult.resources,
		};
	}
	return {
		itemId: props.itemId,
		contentKey: props.contentKey,
		status: props.loadResult.status === 'deferred' ? 'loading' : 'failed',
		resources: null,
	};
}

export function scheduleSelectedContentRetry(props: {
	readonly scheduledRef: { current: boolean };
	readonly setSelectedContentRetryVersion: Dispatch<SetStateAction<number>>;
}): void {
	if (props.scheduledRef.current) {
		return;
	}
	props.scheduledRef.current = true;
	const scheduleRetry =
		typeof requestAnimationFrame === 'function'
			? (callback: () => void): void => {
					requestAnimationFrame(callback);
				}
			: (callback: () => void): void => {
					queueMicrotask(callback);
				};
	scheduleRetry((): void => {
		props.scheduledRef.current = false;
		props.setSelectedContentRetryVersion((version: number): number => version + 1);
	});
}

interface SelectedContentUnavailablePathForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

export function selectedContentUnavailablePathForCurrentSelection(
	props: SelectedContentUnavailablePathForCurrentSelectionProps,
): string | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.contentKey !== selectedContentKey ||
		props.selectedContentResourcesState.status !== 'failed'
	) {
		return null;
	}
	return selectedItem?.headPath ?? selectedItem?.basePath ?? props.selectedItemId;
}

interface SelectedCanvasLoadingReasonForCurrentSelectionProps {
	readonly selectedItemId: string | null;
	readonly selectedContentKey: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
}

function selectedCanvasLoadingReasonForCurrentSelection(
	props: SelectedCanvasLoadingReasonForCurrentSelectionProps,
): BridgeReviewCanvasLoadingReason | null {
	if (props.selectedItemId === null || props.selectedContentKey === null) {
		return null;
	}
	if (
		props.selectedContentResourcesState !== null &&
		props.selectedContentResourcesState.itemId === props.selectedItemId &&
		props.selectedContentResourcesState.contentKey === props.selectedContentKey &&
		props.selectedContentResourcesState.status === 'loading'
	) {
		return 'content';
	}
	if (
		props.selectedMarkdownPreviewState !== null &&
		props.selectedMarkdownPreviewState.itemId === props.selectedItemId &&
		props.selectedMarkdownPreviewState.contentKey === props.selectedContentKey &&
		props.selectedMarkdownPreviewState.status === 'rendering'
	) {
		return 'markdownPreview';
	}
	return null;
}

interface RecordMarkdownRenderQueueTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
}

function recordMarkdownRenderQueueTelemetry(props: RecordMarkdownRenderQueueTelemetryProps): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render_queue',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'markdown_queue',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'queued',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

interface RecordMarkdownRenderCompletionTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly completion: BridgeMarkdownRenderWorkerClientCompletion;
}

function recordMarkdownRenderCompletionTelemetry(
	props: RecordMarkdownRenderCompletionTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	const durationMilliseconds =
		props.completion.status === 'success'
			? props.completion.response.metrics.durationMilliseconds
			: null;
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.content_bytes_bucket':
				props.completion.status === 'success'
					? byteCountBucket(props.completion.response.metrics.inputBytes)
					: 'unknown',
			'agentstudio.bridge.phase': 'markdown_render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes:
			props.completion.status === 'success'
				? {
						'agentstudio.bridge.markdown.input_bytes': props.completion.response.metrics.inputBytes,
						'agentstudio.bridge.markdown.output_bytes':
							props.completion.response.metrics.outputBytes,
					}
				: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
			'agentstudio.bridge.worker.task_kind': 'markdown_render',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

interface RecordMarkdownPreviewFallbackTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly reason: MarkdownPreviewFallbackTelemetryReason;
}

function recordMarkdownPreviewFallbackTelemetry(
	props: RecordMarkdownPreviewFallbackTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.fallback',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.markdown.fallback_reason': props.reason,
			'agentstudio.bridge.phase': 'markdown_decision',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'fallback',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

function isOversizedMarkdownPreviewOutput(html: string): boolean {
	return new TextEncoder().encode(html).byteLength > bridgeMarkdownPreviewMaxBytes;
}

function byteCountBucket(byteCount: number): 'empty' | 'small' | 'medium' | 'large' | 'huge' {
	if (byteCount <= 0) {
		return 'empty';
	}
	if (byteCount <= 32_768) {
		return 'small';
	}
	if (byteCount <= 512_000) {
		return 'medium';
	}
	if (byteCount <= 5_000_000) {
		return 'large';
	}
	return 'huge';
}

function recordPackageApplyTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	envelope: BridgePushEnvelope,
): void {
	telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.package_apply',
		durationMilliseconds: null,
		traceContext: envelope.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': 'apply',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(envelope.slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(envelope.slice),
			'agentstudio.bridge.slice': envelope.slice,
			'agentstudio.bridge.transport': 'push',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	telemetryRecorder.flush();
}

function recordPushDropTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	reason: BridgePushDropReason,
): void {
	telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.telemetry_drop',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'dropped',
			'agentstudio.bridge.plane': 'observability',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.slice': 'telemetry_drop',
			'agentstudio.bridge.telemetry.drop_reason': reason,
			'agentstudio.bridge.transport': 'rpc',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': 1,
		},
		booleanAttributes: {},
	});
	telemetryRecorder.flush({ force: true });
}

function applyReviewEnvelope(
	envelope: BridgePushEnvelope,
	setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void,
	setDiffStatus: (update: (current: BridgeDiffStatusState) => BridgeDiffStatusState) => void,
	setSelectedItemId: (itemId: string | null) => void,
	getSelectedItemId: () => string | null,
	reviewPackageRef: { current: BridgeReviewPackage | null },
	telemetryContextByPackageKey: Map<string, BridgeReviewPackageTelemetryContext>,
	currentReviewPackageTelemetryContextRef: {
		current: BridgeReviewPackageTelemetryContext | null;
	},
	descriptorRegistry: BridgeResourceDescriptorRegistry,
	reviewContentDescriptorRefsByHandleIdRef: {
		current: ReadonlyMap<string, BridgeDescriptorRef>;
	},
	reviewDemandScheduler: BridgeDemandScheduler,
	resourceExecutor: BridgeResourceExecutor<string>,
	reviewFrameAuthority: BridgeReviewFrameAuthority | null,
	invalidatedFreshnessKeysRef: { readonly current: Set<string> },
	setReviewContentInvalidationVersion: Dispatch<SetStateAction<number>>,
): void {
	if (envelope.store !== 'diff') {
		return;
	}
	const diffStatusPayload = extractDiffStatus(envelope.data);
	if (diffStatusPayload !== null) {
		setDiffStatus(
			(current): BridgeDiffStatusState =>
				diffStatusPayload.epoch < current.epoch ? current : diffStatusPayload,
		);
		return;
	}

	const packagePayload = extractReviewPackage(envelope.data);
	if (packagePayload !== null) {
		const currentReviewPackage = reviewPackageRef.current;
		if (
			currentReviewPackage !== null &&
			isStaleReviewPackageReplacement(currentReviewPackage, packagePayload)
		) {
			return;
		}

		const materializedFrame = materializeAcceptedReviewSnapshotForPackage({
			protocolFrame: extractReviewProtocolFrame(envelope.data),
			reviewPackage: packagePayload,
			descriptorRegistry,
			reviewFrameAuthority,
		});
		if (materializedFrame === null) {
			setDiffStatus(
				(): BridgeDiffStatusState => ({
					status: 'error',
					error: 'review_protocol_frame_unavailable',
					epoch: packagePayload.reviewGeneration,
				}),
			);
			return;
		}
		cancelReviewDescriptorDemandGroups({
			descriptorRefs: reviewContentDescriptorRefsByHandleIdRef.current,
			reviewDemandScheduler,
			resourceExecutor,
		});
		reviewContentDescriptorRefsByHandleIdRef.current = materializedFrame.descriptorRefsByHandleId;
		const telemetryContext = {
			slice: envelope.slice,
			traceContext: envelope.traceContext,
		};
		telemetryContextByPackageKey.set(makeTelemetryPackageKey(packagePayload), telemetryContext);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = packagePayload;
		setDiffStatus(
			(): BridgeDiffStatusState => ({
				status: 'ready',
				error: null,
				epoch: packagePayload.reviewGeneration,
			}),
		);
		setReviewPackage((): BridgeReviewPackage => packagePayload);
		const currentSelectedItemId = getSelectedItemId();
		setSelectedItemId(
			currentSelectedItemId === null || !(currentSelectedItemId in packagePayload.itemsById)
				? firstVisibleItemId(packagePayload)
				: currentSelectedItemId,
		);
		return;
	}

	const deltaPayload = extractReviewDelta(envelope.data);
	if (deltaPayload === null) {
		const protocolFrame = extractReviewProtocolFrame(envelope.data);
		if (
			protocolFrame?.frameKind === 'review.invalidate' &&
			reviewInvalidationFrameMatchesCurrentAuthority({
				frame: protocolFrame,
				currentReviewPackage: reviewPackageRef.current,
				reviewFrameAuthority,
			})
		) {
			const materializeResult =
				reviewFrameAuthority === null
					? null
					: applyReviewProtocolFrame({
							frame: protocolFrame,
							paneId: reviewFrameAuthority.paneId,
							registry: descriptorRegistry,
						});
			if (materializeResult?.ok === true && materializeResult.delta.kind === 'invalidate') {
				const invalidatedDescriptorRefs = descriptorRefsForReviewInvalidation({
					descriptorRefsByHandleId: reviewContentDescriptorRefsByHandleIdRef.current,
					invalidation: materializeResult.delta,
					reviewPackage: reviewPackageRef.current,
				});
				cancelReviewDescriptorDemandGroups({
					descriptorRefs: invalidatedDescriptorRefs,
					reviewDemandScheduler,
					resourceExecutor,
				});
				if (invalidatedDescriptorRefs.size > 0) {
					for (const descriptorRef of invalidatedDescriptorRefs.values()) {
						invalidatedFreshnessKeysRef.current.add(
							demandFreshnessKeyForReviewDescriptorRef(descriptorRef),
						);
					}
					setReviewContentInvalidationVersion((version): number => version + 1);
				}
			}
			return;
		}
		if (
			protocolFrame?.frameKind === 'review.reset' &&
			reviewResetFrameMatchesCurrentAuthority({
				frame: protocolFrame,
				currentReviewPackage: reviewPackageRef.current,
				reviewFrameAuthority,
			})
		) {
			const materializeResult =
				reviewFrameAuthority === null
					? null
					: applyReviewProtocolFrame({
							frame: protocolFrame,
							paneId: reviewFrameAuthority.paneId,
							registry: descriptorRegistry,
						});
			if (materializeResult?.ok !== true || materializeResult.delta.kind !== 'reset') {
				return;
			}
			cancelReviewDescriptorDemandGroups({
				descriptorRefs: reviewContentDescriptorRefsByHandleIdRef.current,
				reviewDemandScheduler,
				resourceExecutor,
			});
			reviewContentDescriptorRefsByHandleIdRef.current = new Map<string, BridgeDescriptorRef>();
			reviewPackageRef.current = null;
			currentReviewPackageTelemetryContextRef.current = null;
			setReviewPackage((): null => null);
			setSelectedItemId(null);
			setDiffStatus(
				(): BridgeDiffStatusState => ({
					status: 'loading',
					error: null,
					epoch: protocolFrame.generation,
				}),
			);
		}
		return;
	}

	const telemetryContext = {
		slice: envelope.slice,
		traceContext: envelope.traceContext,
	};
	const currentReviewPackage = reviewPackageRef.current;
	if (currentReviewPackage === null) {
		return;
	}
	const result = applyDeltaToBridgeReviewItemRegistry(
		createBridgeReviewItemRegistry({ reviewPackage: currentReviewPackage, selectedItemId: null }),
		deltaPayload,
	);
	if (!result.accepted) {
		return;
	}

	const materializedFrame = materializeAcceptedReviewDeltaForPackage({
		protocolFrame: extractReviewProtocolFrame(envelope.data),
		reviewPackage: result.registry.reviewPackage,
		previousReviewPackage: currentReviewPackage,
		previousDescriptorRefsByHandleId: reviewContentDescriptorRefsByHandleIdRef.current,
		descriptorRegistry,
		reviewFrameAuthority,
	});
	if (materializedFrame === null) {
		cancelReviewDescriptorDemandGroups({
			descriptorRefs: reviewContentDescriptorRefsByHandleIdRef.current,
			reviewDemandScheduler,
			resourceExecutor,
		});
		reviewContentDescriptorRefsByHandleIdRef.current = new Map<string, BridgeDescriptorRef>();
		return;
	}
	cancelReviewDescriptorDemandGroups({
		descriptorRefs: reviewContentDescriptorRefsByHandleIdRef.current,
		reviewDemandScheduler,
		resourceExecutor,
	});
	reviewContentDescriptorRefsByHandleIdRef.current = materializedFrame.descriptorRefsByHandleId;

	telemetryContextByPackageKey.set(
		makeTelemetryPackageKey(result.registry.reviewPackage),
		telemetryContext,
	);
	currentReviewPackageTelemetryContextRef.current = telemetryContext;
	reviewPackageRef.current = result.registry.reviewPackage;
	setReviewPackage((): BridgeReviewPackage => result.registry.reviewPackage);
	const currentSelectedItemId = getSelectedItemId();
	setSelectedItemId(
		currentSelectedItemId === null ||
			!(currentSelectedItemId in result.registry.reviewPackage.itemsById)
			? firstVisibleItemId(result.registry.reviewPackage)
			: currentSelectedItemId,
	);
}

function extractDiffStatus(data: unknown): BridgeDiffStatusState | null {
	if (!isRecord(data)) {
		return null;
	}
	const status = data['status'];
	if (status !== 'idle' && status !== 'loading' && status !== 'ready' && status !== 'error') {
		return null;
	}
	const epoch = data['epoch'];
	const error = data['error'];
	return {
		status,
		error: typeof error === 'string' && error.length > 0 ? error : null,
		epoch: typeof epoch === 'number' && Number.isInteger(epoch) && epoch >= 0 ? epoch : 0,
	};
}

function isStaleReviewPackageReplacement(
	currentReviewPackage: BridgeReviewPackage,
	nextReviewPackage: BridgeReviewPackage,
): boolean {
	if (currentReviewPackage.packageId !== nextReviewPackage.packageId) {
		return false;
	}
	if (nextReviewPackage.reviewGeneration < currentReviewPackage.reviewGeneration) {
		return true;
	}
	return (
		nextReviewPackage.reviewGeneration === currentReviewPackage.reviewGeneration &&
		nextReviewPackage.revision <= currentReviewPackage.revision
	);
}

interface MaterializedReviewSnapshotForPackage {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
}

function materializeAcceptedReviewSnapshotForPackage(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): MaterializedReviewSnapshotForPackage | null {
	if (
		props.protocolFrame?.frameKind !== 'review.snapshot' ||
		!reviewSnapshotFrameMatchesPackage({
			frame: props.protocolFrame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		})
	) {
		return null;
	}
	if (props.reviewFrameAuthority === null) {
		return null;
	}
	const materializeResult = applyReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	if (!materializeResult.ok || materializeResult.delta.kind !== 'snapshot') {
		return null;
	}
	const descriptorRefsByHandleId = new Map(
		materializeResult.delta.registeredContentDescriptorRefs.map(
			(ref): readonly [string, BridgeDescriptorRef] => [ref.descriptorId, ref],
		),
	);
	return { descriptorRefsByHandleId };
}

function materializeAcceptedReviewDeltaForPackage(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly previousReviewPackage: BridgeReviewPackage;
	readonly previousDescriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): MaterializedReviewSnapshotForPackage | null {
	if (
		props.protocolFrame?.frameKind !== 'review.delta' ||
		!reviewDeltaFrameMatchesPackage({
			frame: props.protocolFrame,
			previousReviewPackage: props.previousReviewPackage,
			reviewPackage: props.reviewPackage,
			previousDescriptorRefsByHandleId: props.previousDescriptorRefsByHandleId,
			reviewFrameAuthority: props.reviewFrameAuthority,
		})
	) {
		return null;
	}
	if (props.reviewFrameAuthority === null) {
		return null;
	}
	const materializeResult = applyReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	if (!materializeResult.ok || materializeResult.delta.kind !== 'delta') {
		return null;
	}
	const attachedDescriptorRefsByHandleId = new Map(
		materializeResult.delta.registeredContentDescriptorRefs.map(
			(ref): readonly [string, BridgeDescriptorRef] => [ref.descriptorId, ref],
		),
	);
	const descriptorRefsByHandleId = descriptorRefsForDeltaPackageLineage({
		previousReviewPackage: props.previousReviewPackage,
		reviewPackage: props.reviewPackage,
		previousDescriptorRefsByHandleId: props.previousDescriptorRefsByHandleId,
		attachedDescriptorRefsByHandleId,
	});
	if (descriptorRefsByHandleId === null) {
		return null;
	}
	return { descriptorRefsByHandleId };
}

function reviewInvalidationFrameMatchesCurrentAuthority(props: {
	readonly frame: ReviewInvalidationFrame;
	readonly currentReviewPackage: BridgeReviewPackage | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (props.currentReviewPackage === null) {
		return true;
	}
	return props.frame.generation >= props.currentReviewPackage.reviewGeneration;
}

function reviewResetFrameMatchesCurrentAuthority(props: {
	readonly frame: ReviewResetFrame;
	readonly currentReviewPackage: BridgeReviewPackage | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (props.currentReviewPackage === null) {
		return true;
	}
	if (props.frame.sourceIdentity !== props.currentReviewPackage.query.queryId) {
		return false;
	}
	if (props.frame.generation < props.currentReviewPackage.reviewGeneration) {
		return false;
	}
	return (
		props.frame.packageId === undefined ||
		props.frame.packageId === props.currentReviewPackage.packageId
	);
}

function reviewSnapshotFrameMatchesPackage(props: {
	readonly frame: ReviewSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (
		props.frame.package.packageId === props.reviewPackage.packageId &&
		props.frame.package.sourceIdentity === props.reviewPackage.query.queryId &&
		props.frame.package.generation === props.reviewPackage.reviewGeneration &&
		props.frame.package.revision === props.reviewPackage.revision
	) {
		return reviewSnapshotFrameDescriptorsMatchPackage({
			frame: props.frame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		});
	}
	return false;
}

function reviewDeltaFrameMatchesPackage(props: {
	readonly frame: ReviewDeltaFrame;
	readonly previousReviewPackage: BridgeReviewPackage;
	readonly reviewPackage: BridgeReviewPackage;
	readonly previousDescriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (
		props.frame.packageId !== props.reviewPackage.packageId ||
		props.previousReviewPackage.packageId !== props.reviewPackage.packageId ||
		props.frame.generation !== props.reviewPackage.reviewGeneration ||
		props.frame.fromRevision !== props.previousReviewPackage.revision ||
		props.frame.toRevision !== props.reviewPackage.revision
	) {
		return false;
	}
	return reviewDeltaFrameDescriptorsMatchPackage({
		frame: props.frame,
		previousReviewPackage: props.previousReviewPackage,
		reviewPackage: props.reviewPackage,
		previousDescriptorRefsByHandleId: props.previousDescriptorRefsByHandleId,
		reviewFrameAuthority: props.reviewFrameAuthority,
	});
}

function reviewDeltaFrameDescriptorsMatchPackage(props: {
	readonly frame: ReviewDeltaFrame;
	readonly previousReviewPackage: BridgeReviewPackage;
	readonly reviewPackage: BridgeReviewPackage;
	readonly previousDescriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): boolean {
	const operationsIdentity: BridgeIdentity = {
		paneId: props.reviewFrameAuthority.paneId,
		protocol: 'review',
		sourceId: props.reviewPackage.query.queryId,
		packageId: props.reviewPackage.packageId,
		generation: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		streamId: props.reviewFrameAuthority.streamId,
	};
	if (
		props.frame.operationsDescriptor.descriptor.resourceKind !== 'review-delta' ||
		props.frame.operationsDescriptor.ref.expectedProtocol !== 'review' ||
		props.frame.operationsDescriptor.ref.expectedResourceKind !== 'review-delta' ||
		!bridgeIdentitiesEqual(
			props.frame.operationsDescriptor.ref.expectedIdentity,
			operationsIdentity,
		) ||
		!bridgeIdentitiesEqual(props.frame.operationsDescriptor.descriptor.identity, operationsIdentity)
	) {
		return false;
	}
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	const descriptorIds = new Set<string>();
	for (const attachedDescriptor of props.frame.contentDescriptors ?? []) {
		if (descriptorIds.has(attachedDescriptor.ref.descriptorId)) {
			return false;
		}
		descriptorIds.add(attachedDescriptor.ref.descriptorId);
		if (
			!contentDescriptorMatchesPackageHandle({
				attachedDescriptor,
				frameAuthority: props.reviewFrameAuthority,
				handlesById,
				props,
			})
		) {
			return false;
		}
	}
	return (
		descriptorRefsForDeltaPackageLineage({
			previousReviewPackage: props.previousReviewPackage,
			reviewPackage: props.reviewPackage,
			previousDescriptorRefsByHandleId: props.previousDescriptorRefsByHandleId,
			attachedDescriptorRefsByHandleId: new Map(
				(props.frame.contentDescriptors ?? []).map(
					(attachedDescriptor): readonly [string, BridgeDescriptorRef] => [
						attachedDescriptor.ref.descriptorId,
						attachedDescriptor.ref,
					],
				),
			),
		}) !== null
	);
}

function descriptorRefsForDeltaPackageLineage(props: {
	readonly previousReviewPackage: BridgeReviewPackage;
	readonly reviewPackage: BridgeReviewPackage;
	readonly previousDescriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly attachedDescriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
}): ReadonlyMap<string, BridgeDescriptorRef> | null {
	const previousHandlesById = contentHandlesByIdForReviewPackage(props.previousReviewPackage);
	const nextHandlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	const nextDescriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>();
	for (const [handleId, nextHandle] of nextHandlesById) {
		const attachedRef = props.attachedDescriptorRefsByHandleId.get(handleId) ?? null;
		if (attachedRef !== null) {
			nextDescriptorRefsByHandleId.set(handleId, attachedRef);
			continue;
		}
		const previousHandle = previousHandlesById.get(handleId) ?? null;
		const previousRef = props.previousDescriptorRefsByHandleId.get(handleId) ?? null;
		if (
			previousHandle === null ||
			previousRef === null ||
			!reviewContentHandlesHaveSameDescriptorLineage(previousHandle, nextHandle)
		) {
			return null;
		}
		nextDescriptorRefsByHandleId.set(handleId, previousRef);
	}
	return nextDescriptorRefsByHandleId;
}

function reviewContentHandlesHaveSameDescriptorLineage(
	left: BridgeContentHandle,
	right: BridgeContentHandle,
): boolean {
	return (
		left.handleId === right.handleId &&
		left.resourceUrl === right.resourceUrl &&
		left.contentHash === right.contentHash &&
		left.cacheKey === right.cacheKey &&
		left.mimeType === right.mimeType &&
		left.sizeBytes === right.sizeBytes &&
		left.reviewGeneration === right.reviewGeneration &&
		left.isBinary === right.isBinary
	);
}

function reviewSnapshotFrameDescriptorsMatchPackage(props: {
	readonly frame: ReviewSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): boolean {
	const rootIdentity: BridgeIdentity = {
		paneId: props.reviewFrameAuthority.paneId,
		protocol: 'review',
		sourceId: props.reviewPackage.query.queryId,
		packageId: props.reviewPackage.packageId,
		generation: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		streamId: props.reviewFrameAuthority.streamId,
	};
	if (
		props.frame.package.rootDescriptor.descriptor.resourceKind !== 'review-package' ||
		props.frame.package.rootDescriptor.ref.expectedProtocol !== 'review' ||
		props.frame.package.rootDescriptor.ref.expectedResourceKind !== 'review-package' ||
		!bridgeIdentitiesEqual(props.frame.package.rootDescriptor.ref.expectedIdentity, rootIdentity) ||
		!bridgeIdentitiesEqual(props.frame.package.rootDescriptor.descriptor.identity, rootIdentity)
	) {
		return false;
	}
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	const descriptorIds = new Set<string>();
	for (const attachedDescriptor of props.frame.package.contentDescriptors ?? []) {
		if (descriptorIds.has(attachedDescriptor.ref.descriptorId)) {
			return false;
		}
		descriptorIds.add(attachedDescriptor.ref.descriptorId);
		if (
			!contentDescriptorMatchesPackageHandle({
				attachedDescriptor,
				frameAuthority: props.reviewFrameAuthority,
				handlesById,
				props,
			})
		) {
			return false;
		}
	}
	return descriptorIds.size === handlesById.size;
}

function contentDescriptorMatchesPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly frameAuthority: BridgeReviewFrameAuthority;
	readonly handlesById: ReadonlyMap<string, BridgeContentHandle>;
	readonly props: {
		readonly reviewPackage: BridgeReviewPackage;
		readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	};
}): boolean {
	const handle = args.handlesById.get(args.attachedDescriptor.ref.descriptorId) ?? null;
	if (handle === null) {
		return false;
	}
	const expectedIdentity: BridgeIdentity = {
		paneId: args.frameAuthority.paneId,
		protocol: 'review',
		sourceId: args.props.reviewPackage.query.queryId,
		packageId: args.props.reviewPackage.packageId,
		generation: handle.reviewGeneration,
		...(args.attachedDescriptor.descriptor.identity.revision === undefined
			? {}
			: { revision: args.attachedDescriptor.descriptor.identity.revision }),
		streamId: args.frameAuthority.streamId,
		...(args.attachedDescriptor.descriptor.identity.cursor === undefined
			? {}
			: { cursor: args.attachedDescriptor.descriptor.identity.cursor }),
	};
	return (
		args.attachedDescriptor.ref.expectedProtocol === 'review' &&
		args.attachedDescriptor.ref.expectedResourceKind === 'content' &&
		args.attachedDescriptor.descriptor.protocol === 'review' &&
		args.attachedDescriptor.descriptor.resourceKind === 'content' &&
		args.attachedDescriptor.descriptor.resourceUrl === handle.resourceUrl &&
		args.attachedDescriptor.descriptor.content.mediaType === handle.mimeType &&
		args.attachedDescriptor.descriptor.content.expectedBytes === handle.sizeBytes &&
		bridgeIdentitiesEqual(args.attachedDescriptor.ref.expectedIdentity, expectedIdentity) &&
		bridgeIdentitiesEqual(args.attachedDescriptor.descriptor.identity, expectedIdentity)
	);
}

function contentHandlesByIdForReviewPackage(
	reviewPackage: BridgeReviewPackage,
): ReadonlyMap<string, BridgeContentHandle> {
	const handlesById = new Map<string, BridgeContentHandle>();
	for (const item of Object.values(reviewPackage.itemsById)) {
		for (const handle of Object.values(item.contentRoles)) {
			if (handle !== null && handle !== undefined) {
				handlesById.set(handle.handleId, handle);
			}
		}
	}
	return handlesById;
}

function descriptorRefsForReviewInvalidation(props: {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly invalidation: Extract<ReviewMaterializerDelta, { readonly kind: 'invalidate' }>;
	readonly reviewPackage: BridgeReviewPackage | null;
}): ReadonlyMap<string, BridgeDescriptorRef> {
	if (props.reviewPackage === null) {
		return new Map<string, BridgeDescriptorRef>();
	}
	if (props.invalidation.scope === 'package' || props.invalidation.scope === 'treeWindow') {
		return props.descriptorRefsByHandleId;
	}
	const invalidatedItemIds = new Set<string>(props.invalidation.itemIds ?? []);
	const invalidatedPathHints = new Set<string>(props.invalidation.pathHints ?? []);
	const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>();
	for (const item of Object.values(props.reviewPackage.itemsById)) {
		if (
			!invalidatedItemIds.has(item.itemId) &&
			!invalidatedPathHints.has(item.headPath ?? '') &&
			!invalidatedPathHints.has(item.basePath ?? '')
		) {
			continue;
		}
		for (const handle of Object.values(item.contentRoles)) {
			if (handle === null || handle === undefined) {
				continue;
			}
			const descriptorRef = props.descriptorRefsByHandleId.get(handle.handleId) ?? null;
			if (descriptorRef !== null) {
				descriptorRefsByHandleId.set(handle.handleId, descriptorRef);
			}
		}
	}
	return descriptorRefsByHandleId;
}

function cancelReviewDescriptorDemandGroups(props: {
	readonly descriptorRefs: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly resourceExecutor: BridgeResourceExecutor<string>;
}): number {
	let cancelledCount = 0;
	const cancellationGroups = new Set<string>();
	for (const descriptorRef of props.descriptorRefs.values()) {
		for (const cancellationGroup of demandCancellationGroupsForReviewDescriptorRef(descriptorRef)) {
			cancellationGroups.add(cancellationGroup);
		}
	}
	for (const cancellationGroup of cancellationGroups) {
		cancelledCount += props.reviewDemandScheduler.cancelGroup(cancellationGroup);
		cancelledCount += props.resourceExecutor.cancelGroup(cancellationGroup);
	}
	return cancelledCount;
}

function cancelReviewItemDemandForInterest(props: {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly interest: ReviewContentDemandInterest;
	readonly item: BridgeReviewItemDescriptor | undefined;
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly resourceExecutor: BridgeResourceExecutor<string>;
}): number {
	if (props.item === undefined) {
		return 0;
	}
	let cancelledCount = 0;
	const cancellationGroups = new Set<string>();
	for (const handle of Object.values(props.item.contentRoles)) {
		if (handle === null || handle === undefined) {
			continue;
		}
		const descriptorRef = props.descriptorRefsByHandleId.get(handle.handleId);
		if (descriptorRef === undefined) {
			continue;
		}
		cancellationGroups.add(
			demandCancellationGroupForReviewDescriptorRef(descriptorRef, props.interest),
		);
	}
	for (const cancellationGroup of cancellationGroups) {
		cancelledCount += props.reviewDemandScheduler.cancelGroup(cancellationGroup);
		cancelledCount += props.resourceExecutor.cancelGroup(cancellationGroup);
	}
	return cancelledCount;
}

function bridgeIdentitiesEqual(left: BridgeIdentity, right: BridgeIdentity): boolean {
	return (
		left.paneId === right.paneId &&
		left.protocol === right.protocol &&
		left.sourceId === right.sourceId &&
		left.packageId === right.packageId &&
		left.generation === right.generation &&
		left.revision === right.revision &&
		left.streamId === right.streamId &&
		left.cursor === right.cursor
	);
}

function extractReviewPackage(data: unknown): BridgeReviewPackage | null {
	if (!isRecord(data)) {
		return null;
	}
	const packageValue = data['package'];
	const parsedPackage = bridgeReviewPackageSchema.safeParse(packageValue);
	return parsedPackage.success ? parsedPackage.data : null;
}

function extractReviewProtocolFrame(data: unknown): ReviewProtocolFrame | null {
	if (!isRecord(data)) {
		return null;
	}
	const protocolFrameValue = data['protocolFrame'];
	const parsedProtocolFrame = reviewProtocolFrameSchema.safeParse(protocolFrameValue);
	return parsedProtocolFrame.success ? parsedProtocolFrame.data : null;
}

function readBridgeReviewFrameAuthority(): BridgeReviewFrameAuthority | null {
	const paneId = document.documentElement.getAttribute(bridgeReviewPaneIdAttribute);
	const streamId = document.documentElement.getAttribute(bridgeReviewStreamIdAttribute);
	return paneId === null || streamId === null || paneId.length === 0 || streamId.length === 0
		? null
		: { paneId, streamId };
}

function extractReviewDelta(data: unknown): BridgeReviewDelta | null {
	if (!isRecord(data)) {
		return null;
	}
	const deltaValue = data['delta'];
	const parsedDelta = bridgeReviewDeltaSchema.safeParse(deltaValue);
	return parsedDelta.success ? parsedDelta.data : null;
}

function firstVisibleItemId(reviewPackage: BridgeReviewPackage): string | null {
	const registry = createBridgeReviewItemRegistry({ reviewPackage, selectedItemId: null });
	return registry.visibleItems[0]?.itemId ?? null;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
