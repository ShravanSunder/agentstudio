import type { Dispatch, MutableRefObject, ReactElement, SetStateAction } from 'react';
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
import {
	installBridgeIntakeEventCarrier,
	type BridgeIntakeCarrierDrop,
} from '../core/intake/bridge-intake-carrier.js';
import type {
	BridgeIntakeReceiver,
	BridgeIntakeReceiverState,
	BridgeIntakeReceiveResult,
} from '../core/intake/bridge-intake-receiver.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
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
	bridgeTextResourceLoadErrorKind,
	readBridgeTextResourceStream,
	type BridgeTextResourceStreamResult,
} from '../core/resources/bridge-resource-stream.js';
import { parseBridgeCoreResourceUrl } from '../core/resources/bridge-resource-url.js';
import {
	applyReviewProtocolFrame,
	type ReviewMaterializerDelta,
} from '../features/review/materialization/review-materializer.js';
import {
	reviewProtocolFrameSchema,
	type ReviewMetadataDeltaFrame,
	type ReviewMetadataSnapshotFrame,
	type ReviewMetadataWindowFrame,
	type ReviewInvalidationFrame,
	type ReviewProtocolFrame,
	type ReviewResetFrame,
	type ReviewTreeRowMetadata,
} from '../features/review/models/review-protocol-models.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	BridgeFileViewerApp,
	type BridgeFileViewerAppProps,
} from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import { createBridgeReviewItemRegistry } from '../foundation/review-package/bridge-review-item-registry.js';
import { bridgeReviewPackageSchema } from '../foundation/review-package/bridge-review-package-schema.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import {
	createBridgeTelemetryRecorder,
	type BridgeTelemetryFlushProps,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	planeForBridgeTelemetrySlice,
	priorityForBridgeTelemetrySlice,
	type BridgeTelemetryPriority,
	type BridgeTelemetrySlice,
} from '../foundation/telemetry/bridge-telemetry-taxonomy.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import {
	demandCancellationGroupForReviewDescriptorRef,
	demandCancellationGroupsForReviewDescriptorRef,
	demandFreshnessKeyForReviewDescriptorRef,
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandTelemetry,
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
	BridgeReviewMetadataFailedShell,
	BridgeReviewMetadataLoadingShell,
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
	readonly projectionWorkerClient?: BridgeReviewProjectionWorkerClient | null;
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
	readonly transport: 'intake' | 'push';
}

interface PendingReviewSelectionCommitTelemetry {
	readonly itemId: string;
	readonly packageKey: string;
	readonly startedAtMilliseconds: number;
	readonly traceContext: BridgeTraceContext | null;
}

interface BridgeDiffStatusState {
	readonly status: 'idle' | 'loading' | 'ready' | 'error';
	readonly error: string | null;
	readonly epoch: number;
}

export interface BridgeReviewFrameAuthority {
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

type ReviewSnapshotMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataSnapshot' }
>;
type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;
type ReviewWindowMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataWindow' }
>;
type ReviewMetadataSnapshotApplyFailure =
	| 'review_metadata_snapshot_descriptor_mismatch'
	| 'review_metadata_snapshot_parse_failed'
	| 'review_metadata_snapshot_rejected';

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
const bridgeReviewContentMaxBytesPerRole = 50 * 1024 * 1024;
const bridgeReviewContentMaxRolesPerItem = 2;

export interface BridgeReviewContentDemandByteBudget {
	readonly maxContentBytesPerRole: number;
	readonly maxContentRolesPerItem: number;
	readonly bodyRegistryMaxBytes: number;
	readonly resourceExecutorMaxInFlightBytes: number;
	readonly resourceExecutorMaxQueuedBytes: number;
	readonly demandMaxQueuedEstimatedBytes: number;
}

export const bridgeReviewContentDemandByteBudget: BridgeReviewContentDemandByteBudget = {
	maxContentBytesPerRole: bridgeReviewContentMaxBytesPerRole,
	maxContentRolesPerItem: bridgeReviewContentMaxRolesPerItem,
	bodyRegistryMaxBytes: bridgeReviewContentMaxBytesPerRole,
	resourceExecutorMaxInFlightBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	resourceExecutorMaxQueuedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	demandMaxQueuedEstimatedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
};

const bridgeReviewBodyRegistryMaxBytes = bridgeReviewContentDemandByteBudget.bodyRegistryMaxBytes;
const bridgeReviewResourceExecutorMaxConcurrentLoads = 8;
const bridgeReviewResourceExecutorMaxInFlightBytes =
	bridgeReviewContentDemandByteBudget.resourceExecutorMaxInFlightBytes;
const bridgeReviewResourceExecutorMaxQueuedLoads = 128;
const bridgeReviewResourceExecutorMaxQueuedBytes =
	bridgeReviewContentDemandByteBudget.resourceExecutorMaxQueuedBytes;
const foregroundSelectionVisibleHydrationReleaseDelayMilliseconds = 180;
const bridgeReviewDemandMaxQueuedIntentsPerLane = 128;
const bridgeReviewDemandMaxQueuedEstimatedBytes =
	bridgeReviewContentDemandByteBudget.demandMaxQueuedEstimatedBytes;
const bridgeReviewIntakeMaxFrameBytes = 1024 * 1024;
const bridgeReviewPaneIdAttribute = 'data-bridge-review-pane-id';
const bridgeReviewStreamIdAttribute = 'data-bridge-review-stream-id';
const emptyVisibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources> =
	new Map<string, BridgeCodeViewContentResources>();
const emptyVisibleLoadingItemIds: ReadonlySet<string> = new Set<string>();
const bridgeReviewAllowedResourceKindsByProtocol = {
	review: new Set(['content']),
};

type BridgeReviewStartupTelemetryPhase =
	| 'review_metadata_apply'
	| 'review_ready'
	| 'selection_commit'
	| 'selected_content_ready';

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

type BridgeReviewResourceExecutorCachedText = BridgeTextResourceStreamResult;

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
): BridgeResourceExecutor<BridgeTextResourceStreamResult> {
	const bodyRegistryRef = useRef(
		createBridgeBodyRegistry<BridgeReviewResourceExecutorCachedText>({
			maxBytes: bridgeReviewBodyRegistryMaxBytes,
		}),
	);
	const executorRef = useRef<BridgeResourceExecutor<BridgeTextResourceStreamResult> | null>(null);
	if (executorRef.current === null) {
		executorRef.current = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: props.descriptorRegistry,
			maxConcurrentLoads: bridgeReviewResourceExecutorMaxConcurrentLoads,
			maxInFlightBytes: bridgeReviewResourceExecutorMaxInFlightBytes,
			maxQueuedLoads: bridgeReviewResourceExecutorMaxQueuedLoads,
			maxQueuedBytes: bridgeReviewResourceExecutorMaxQueuedBytes,
			classifyLoadFailure: bridgeTextResourceLoadErrorKind,
			isFresh: (intent): boolean => {
				if (isReviewProtocolBodyDescriptorRef(intent.descriptorRef)) {
					return (
						props.descriptorRegistry.lookup(intent.descriptorRef) !== null &&
						demandFreshnessKeyForReviewDescriptorRef(intent.descriptorRef) === intent.freshnessKey
					);
				}
				const currentDescriptorRef = props.descriptorRefsByDescriptorIdRef.current.get(
					intent.descriptorRef.descriptorId,
				);
				return (
					currentDescriptorRef !== undefined &&
					demandFreshnessKeyForReviewDescriptorRef(currentDescriptorRef) === intent.freshnessKey
				);
			},
			loadResource: async ({ descriptor, intent, onChunk, signal }) => {
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
						authoritative: cachedBody.authoritative,
						content: cachedBody,
						byteLength: cachedBody.byteLength,
					};
				}
				const fetchContent = props.fetchContentRef.current ?? fetch;
				const response = await fetchContent(descriptor.resourceUrl, { signal });
				if (!response.ok) {
					throw new Error(`Bridge descriptor content request failed: ${response.status}`);
				}
				const streamedText = await readBridgeTextResourceStream(response, {
					integrity: descriptor.content.integrity,
					maxBytes: descriptor.content.maxBytes,
					onTextChunk: (chunk): void => {
						onChunk({
							byteLength: chunk.byteLength,
							chunk: chunk.text,
							totalBytesRead: chunk.totalBytesRead,
						});
					},
					signal,
				});
				const byteLength = streamedText.byteLength;
				if (streamedText.authoritative) {
					bodyRegistryRef.current.put({
						cacheKey,
						freshnessKey: intent.freshnessKey,
						body: streamedText,
						byteLength,
					});
				}
				if (shouldBypassCachedBody) {
					props.invalidatedFreshnessKeysRef.current.delete(intent.freshnessKey);
				}
				return { authoritative: streamedText.authoritative, content: streamedText, byteLength };
			},
		});
	}
	return executorRef.current;
}

function isReviewProtocolBodyDescriptorRef(descriptorRef: BridgeDescriptorRef): boolean {
	return (
		descriptorRef.expectedProtocol === 'review' && descriptorRef.expectedResourceKind !== 'content'
	);
}

function createBridgeReviewDemandScheduler(): BridgeDemandScheduler {
	return createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: bridgeReviewDemandMaxQueuedIntentsPerLane,
		maxQueuedEstimatedBytes: bridgeReviewDemandMaxQueuedEstimatedBytes,
	});
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
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const telemetryRecorder = useMemo(
		(): BridgeTelemetryRecorder => ({
			isEnabled: (scope) => telemetryRecorderRef.current.isEnabled(scope),
			record: (sample) => telemetryRecorderRef.current.record(sample),
			measure: (measureProps) => telemetryRecorderRef.current.measure(measureProps),
			flush: (flushProps) => telemetryRecorderRef.current.flush(flushProps),
		}),
		[],
	);
	const target = props.target ?? document;
	const handshakeSessionRef = useRef<BridgePageHandshakeSession | null>(null);
	const isBridgeReadyRef = useRef(false);
	const bridgeReadyCallbacksRef = useRef<Set<() => void>>(new Set());
	const registerBridgeReadyCallback = useCallback((callback: () => void): (() => void) => {
		bridgeReadyCallbacksRef.current.add(callback);
		if (isBridgeReadyRef.current) {
			queueMicrotask(callback);
		}
		return (): void => {
			bridgeReadyCallbacksRef.current.delete(callback);
		};
	}, []);
	useEffect((): (() => void) => {
		const rpcClient = createBridgeRPCClient({ target });
		const configureTelemetryRecorder = (
			telemetryConfig = handshakeSessionRef.current?.getTelemetryConfig() ?? null,
		): void => {
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(
				telemetryConfig,
				createBridgeTelemetryEventSink({
					rpcClient,
					methodName: telemetryConfig?.rpcMethodName ?? 'system.bridgeTelemetry',
				}),
			);
		};
		handshakeSessionRef.current = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				isBridgeReadyRef.current = true;
				queueMicrotask((): void => {
					if (!isBridgeReadyRef.current) {
						return;
					}
					for (const callback of bridgeReadyCallbacksRef.current) {
						callback();
					}
				});
			},
			onTelemetryConfig: configureTelemetryRecorder,
		});
		configureTelemetryRecorder();
		return (): void => {
			handshakeSessionRef.current?.uninstall();
			handshakeSessionRef.current = null;
			isBridgeReadyRef.current = false;
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
		};
	}, [target]);
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
						registerBridgeReadyCallback={registerBridgeReadyCallback}
						telemetryRecorder={telemetryRecorder}
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
						handshakeSessionRef={handshakeSessionRef}
						isActive={activeViewerState.viewerMode === 'review'}
						registerBridgeReadyCallback={registerBridgeReadyCallback}
						telemetryRecorderRef={telemetryRecorderRef}
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
		readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
		readonly telemetryRecorder: BridgeTelemetryRecorder;
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
			isActive={props.isActive}
			{...(props.navigationCommand === undefined
				? {}
				: { navigationCommand: props.navigationCommand })}
			onOpenReviewComparison={openReviewComparison}
			telemetryRecorder={props.telemetryRecorder}
			telemetryTraceContext={null}
			viewerHeaderControls={props.viewerHeaderControls}
			waitForBridgeReady={props.registerBridgeReadyCallback}
		/>
	);
}

function BridgeReviewViewerMode(
	props: BridgeAppProps & {
		readonly handshakeSessionRef: MutableRefObject<BridgePageHandshakeSession | null>;
		readonly isActive: boolean;
		readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
		readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
		readonly viewerHeaderControls: ReactElement;
	},
): ReactElement {
	const target = props.target ?? document;
	const reviewFrameAuthorityRef = useRef<BridgeReviewFrameAuthority | null>(
		readBridgeReviewFrameAuthority(),
	);
	const getReviewFrameAuthority = useCallback(
		(): BridgeReviewFrameAuthority | null =>
			refreshBridgeReviewFrameAuthority(reviewFrameAuthorityRef),
		[],
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
	const reviewEnvelopeApplyTailRef = useRef<Promise<void>>(Promise.resolve());
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
	const [reviewTreeRows, setReviewTreeRows] = useState<readonly ReviewTreeRowMetadata[]>([]);
	const [diffStatus, setDiffStatus] = useState<BridgeDiffStatusState>({
		status: 'idle',
		error: null,
		epoch: 0,
	});
	const [selectedContentResourcesState, setSelectedContentResourcesState] =
		useState<SelectedContentResourcesState | null>(null);
	const selectedContentResourcesStateRef = useRef<SelectedContentResourcesState | null>(null);
	selectedContentResourcesStateRef.current = selectedContentResourcesState;
	const [foregroundSelectedContentKey, setForegroundSelectedContentKey] = useState<string | null>(
		null,
	);
	const foregroundSelectionReleaseCancelRef = useRef<(() => void) | null>(null);
	const cancelForegroundSelectionRelease = useCallback((): void => {
		foregroundSelectionReleaseCancelRef.current?.();
		foregroundSelectionReleaseCancelRef.current = null;
	}, []);
	const clearForegroundSelectionNow = useCallback(
		(contentKey: string): void => {
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey((currentContentKey: string | null): string | null =>
				currentContentKey === contentKey ? null : currentContentKey,
			);
		},
		[cancelForegroundSelectionRelease],
	);
	const scheduleForegroundSelectionRelease = useCallback(
		(contentKey: string): void => {
			cancelForegroundSelectionRelease();
			const timeoutId = setTimeout((): void => {
				foregroundSelectionReleaseCancelRef.current = null;
				setForegroundSelectedContentKey((currentContentKey: string | null): string | null =>
					currentContentKey === contentKey ? null : currentContentKey,
				);
			}, foregroundSelectionVisibleHydrationReleaseDelayMilliseconds);
			foregroundSelectionReleaseCancelRef.current = (): void => {
				clearTimeout(timeoutId);
			};
		},
		[cancelForegroundSelectionRelease],
	);
	const [selectedContentRetryVersion, setSelectedContentRetryVersion] = useState(0);
	const selectedContentRetryScheduledRef = useRef(false);
	const [reviewContentInvalidationVersion, setReviewContentInvalidationVersion] = useState(0);
	const [lastSelectedDemandTelemetry, setLastSelectedDemandTelemetry] =
		useState<ReviewContentDemandTelemetry | null>(null);
	const lastSelectedDemandTelemetryRef = useRef<ReviewContentDemandTelemetry | null>(null);
	lastSelectedDemandTelemetryRef.current = lastSelectedDemandTelemetry;
	const [lastVisibleDemandTelemetry, setLastVisibleDemandTelemetry] =
		useState<ReviewContentDemandTelemetry | null>(null);
	const [codeViewVisibleReviewItemIds, setCodeViewVisibleReviewItemIds] = useState<
		readonly string[]
	>([]);
	const [treeVisibleReviewItemIds, setTreeVisibleReviewItemIds] = useState<readonly string[]>([]);
	const [selectedMarkdownPreviewState, setSelectedMarkdownPreviewState] =
		useState<SelectedMarkdownPreviewState | null>(null);
	const [lastSelectionCommitDurationMilliseconds, setLastSelectionCommitDurationMilliseconds] =
		useState<number | null>(null);
	const selectedMarkdownPreviewStateRef = useRef<SelectedMarkdownPreviewState | null>(null);
	selectedMarkdownPreviewStateRef.current = selectedMarkdownPreviewState;
	const [isTreeSearchOpen, setIsTreeSearchOpen] = useState(false);
	const telemetryRecorderRef = props.telemetryRecorderRef;
	const bridgeHandshakeSessionRef = props.handshakeSessionRef;
	const registerBridgeReadyCallback = props.registerBridgeReadyCallback;
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const lastFirstRenderPackageRef = useRef<string | null>(null);
	const lastReviewReadyPackageRef = useRef<string | null>(null);
	const reviewReadyStartMillisecondsByPackageKeyRef = useRef<Map<string, number>>(new Map());
	const pendingSelectionCommitTelemetryRef = useRef<PendingReviewSelectionCommitTelemetry | null>(
		null,
	);
	const selectedContentActiveLoadKeyRef = useRef<string | null>(null);
	const selectedContentLoadStartByKeyRef = useRef<Map<string, number>>(new Map());
	const codeViewControlHandleRef = useRef<BridgeCodeViewControlHandle | null>(null);
	const selectedContentAbortControllerRef = useRef<AbortController | null>(null);
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(null);
	reviewPackageRef.current = reviewPackage;
	const projectionRef = useRef(projection);
	projectionRef.current = projection;
	const rootSnapshotRef = useRef(rootSnapshot);
	rootSnapshotRef.current = rootSnapshot;
	const [isCodeViewScrollActive, setIsCodeViewScrollActive] = useState(false);
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
		[target, telemetryRecorderRef],
	);
	const projectionWorkerClient = useMemo(
		(): BridgeReviewProjectionWorkerClient | null =>
			props.projectionWorkerClient === undefined
				? createBridgeReviewProjectionWebWorkerClient()
				: props.projectionWorkerClient,
		[props.projectionWorkerClient],
	);
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
	const currentSelectedContentKey =
		reviewPackage === null || rootSnapshot.selectedItemId === null
			? null
			: makeSelectedContentResourcesKey(reviewPackage, rootSnapshot.selectedItemId);
	const initialReviewFileTarget = useMemo(
		() => reviewFileTargetForNavigationCommand(props.navigationCommand),
		[props.navigationCommand],
	);
	const selectedItemPresentation = useMemo(
		() =>
			selectedItemPresentationForReviewFileTarget({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				target: initialReviewFileTarget,
			}),
		[initialReviewFileTarget, reviewPackage, rootSnapshot.selectedItemId],
	);
	useEffect((): void => {
		setLastSelectedDemandTelemetry((currentTelemetry) =>
			reviewContentDemandTelemetryForPackage({
				reviewPackage,
				telemetry: currentTelemetry,
			}),
		);
		setLastVisibleDemandTelemetry((currentTelemetry) =>
			reviewContentDemandTelemetryForPackage({
				reviewPackage,
				telemetry: currentTelemetry,
			}),
		);
	}, [reviewPackage]);
	const lastSelectedDemandTelemetryForCurrentPackage = reviewContentDemandTelemetryForPackage({
		reviewPackage,
		telemetry: lastSelectedDemandTelemetry,
	});
	const lastVisibleDemandTelemetryForCurrentPackage = reviewContentDemandTelemetryForPackage({
		reviewPackage,
		telemetry: lastVisibleDemandTelemetry,
	});
	const visibleContentHydrationPaused = shouldPauseVisibleReviewContentHydration({
		isActive: props.isActive,
		codeViewScrollActive: isCodeViewScrollActive,
		currentSelectedContentKey,
		foregroundSelectedContentKey,
		selectedContentResourcesState,
	});
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
				onDemandTelemetry: setLastVisibleDemandTelemetry,
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
		visibleHydrationPaused: visibleContentHydrationPaused,
	});
	const setVisibleReviewContentItemIds = visibleContentHydration.setVisibleItemIds;
	const retrySelectedContentAfterDescriptorRegistration = useCallback(
		(registeredDescriptorRefCount: number): void => {
			if (
				shouldRetrySelectedReviewContentAfterDescriptorRegistration({
					reviewPackage: reviewPackageRef.current,
					selectedItemId: rootSnapshotRef.current.selectedItemId,
					registeredDescriptorRefCount,
					selectedContentResourcesState: selectedContentResourcesStateRef.current,
					lastSelectedDemandTelemetry: lastSelectedDemandTelemetryRef.current,
				})
			) {
				scheduleSelectedContentRetry({
					scheduledRef: selectedContentRetryScheduledRef,
					setSelectedContentRetryVersion,
				});
			}
		},
		[setSelectedContentRetryVersion],
	);
	useEffect((): void => {
		setVisibleReviewContentItemIds(
			uniqueReviewVisibleItemIds([...treeVisibleReviewItemIds, ...codeViewVisibleReviewItemIds]),
		);
	}, [codeViewVisibleReviewItemIds, setVisibleReviewContentItemIds, treeVisibleReviewItemIds]);
	const flushTelemetry = useCallback(
		(flushProps: BridgeTelemetryFlushProps = {}): void => {
			telemetryRecorderRef.current.flush(flushProps);
		},
		[telemetryRecorderRef],
	);
	const beginForegroundReviewSelection = useCallback(
		(itemId: string): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (currentReviewPackage === null || !(itemId in currentReviewPackage.itemsById)) {
				return false;
			}
			const previousSelectedItemId = rootSnapshotRef.current.selectedItemId;
			const isSelectionChange = previousSelectedItemId !== itemId;
			const selectedContentKey = makeSelectedContentResourcesKey(currentReviewPackage, itemId);
			if (isSelectionChange) {
				pendingSelectionCommitTelemetryRef.current = telemetryRecorderRef.current.isEnabled('web')
					? {
							itemId,
							packageKey: makeTelemetryPackageKey(currentReviewPackage),
							startedAtMilliseconds: performance.now(),
							traceContext: createChildTraceContext(
								currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
							),
						}
					: null;
				cancelForegroundSelectionRelease();
				setForegroundSelectedContentKey(selectedContentKey);
				selectedContentAbortControllerRef.current?.abort();
				selectedContentAbortControllerRef.current = null;
				selectedContentActiveLoadKeyRef.current = null;
				cancelReviewItemDemand({
					descriptorRefsByHandleId: reviewContentDescriptorRefsByHandleIdRef.current,
					item: reviewItemDemandCancellationTargetForSelectionChange({
						previousSelectedItemId,
						reviewPackage: currentReviewPackage,
					}),
					resourceExecutor,
					reviewDemandScheduler,
				});
				setSelectedContentResourcesState({
					itemId,
					contentKey: selectedContentKey,
					status: 'loading',
					resources: null,
				});
			}
			viewerActions.setSelectedItemId(itemId);
			viewerActions.setRenderMode({ kind: 'codeView' });
			return true;
		},
		[
			cancelForegroundSelectionRelease,
			resourceExecutor,
			reviewDemandScheduler,
			telemetryRecorderRef,
			viewerActions,
		],
	);
	const selectReviewItem = useCallback(
		(itemId: string): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (!beginForegroundReviewSelection(itemId) || currentReviewPackage === null) {
				return false;
			}
			lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(currentReviewPackage, itemId);
			rpcClient.sendCommand({
				method: 'review.markFileViewed',
				params: { fileId: itemId },
			});
			return true;
		},
		[beginForegroundReviewSelection, rpcClient],
	);
	useLayoutEffect((): void => {
		const pendingTelemetry = pendingSelectionCommitTelemetryRef.current;
		if (
			pendingTelemetry === null ||
			!props.isActive ||
			reviewPackage === null ||
			projection === null ||
			rootSnapshot.selectedItemId !== pendingTelemetry.itemId
		) {
			return;
		}
		if (makeTelemetryPackageKey(reviewPackage) !== pendingTelemetry.packageKey) {
			pendingSelectionCommitTelemetryRef.current = null;
			return;
		}
		pendingSelectionCommitTelemetryRef.current = null;
		const durationMilliseconds = performance.now() - pendingTelemetry.startedAtMilliseconds;
		setLastSelectionCommitDurationMilliseconds(Math.max(0, durationMilliseconds));
		recordReviewStartupTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			phase: 'selection_commit',
			slice: 'review_projection',
			transport: 'worker',
			traceContext: pendingTelemetry.traceContext,
			durationMilliseconds,
			result: 'success',
		});
	}, [
		projection,
		props.isActive,
		reviewPackage,
		rootSnapshot.selectedItemId,
		telemetryRecorderRef,
	]);
	const appliedNavigationCommandRef = useRef<BridgeViewerNavigationCommand | null>(null);
	useEffect((): void => {
		if (
			!props.isActive ||
			reviewPackage === null ||
			projection === null ||
			initialReviewFileTarget === null
		) {
			return;
		}
		const itemId = itemIdForReviewFileNavigationTarget({
			reviewPackage,
			target: initialReviewFileTarget,
		});
		if (itemId === null) {
			return;
		}
		if (
			appliedNavigationCommandRef.current !== null &&
			appliedNavigationCommandRef.current === props.navigationCommand
		) {
			return;
		}
		if (!projection.orderedItemIds.includes(itemId)) {
			if (clearReviewRefinementsHidingExplicitTarget({ rootSnapshot, viewerActions })) {
				appliedNavigationCommandRef.current = null;
			}
			return;
		}
		appliedNavigationCommandRef.current = props.navigationCommand ?? null;
		selectReviewItem(itemId);
	}, [
		initialReviewFileTarget,
		props.isActive,
		projection,
		props.navigationCommand,
		reviewPackage,
		rootSnapshot,
		selectReviewItem,
		viewerActions,
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

		if (nextSelectedItemId === null) {
			selectedContentAbortControllerRef.current?.abort();
			selectedContentAbortControllerRef.current = null;
			setSelectedContentResourcesState(null);
			viewerActions.setSelectedItemId(null);
			viewerActions.setRenderMode({ kind: 'codeView' });
		} else {
			beginForegroundReviewSelection(nextSelectedItemId);
		}
		setSelectedMarkdownPreviewState(null);
	}, [
		beginForegroundReviewSelection,
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
		let didMarkReviewIntakeReady = false;
		let retryCount = 0;
		let retryHandle: { readonly kind: 'animationFrame' | 'timeout'; readonly id: number } | null =
			null;
		const maxIntakeReadyRetries = 30;
		const requestIntakeReplay = (): void => {
			target.dispatchEvent(new CustomEvent('__bridge_intake_replay_request'));
		};
		const clearScheduledIntakeReadyRetry = (): void => {
			if (retryHandle === null) {
				return;
			}
			if (retryHandle.kind === 'animationFrame') {
				cancelAnimationFrame(retryHandle.id);
			} else {
				clearTimeout(retryHandle.id);
			}
			retryHandle = null;
		};
		const markReviewIntakeReady = (): boolean => {
			if (didMarkReviewIntakeReady) {
				return true;
			}
			const handshakeSession = bridgeHandshakeSessionRef.current;
			const streamId = getReviewFrameAuthority()?.streamId ?? null;
			const didSendIntakeReady =
				handshakeSession?.markIntakeReady({
					protocolId: 'review',
					streamId,
				}) ?? false;
			if (!didSendIntakeReady) {
				return false;
			}
			didMarkReviewIntakeReady = true;
			clearScheduledIntakeReadyRetry();
			requestIntakeReplay();
			return true;
		};
		const scheduleMarkReviewIntakeReady = (): void => {
			if (markReviewIntakeReady() || retryHandle !== null || retryCount >= maxIntakeReadyRetries) {
				return;
			}
			retryCount += 1;
			if (typeof requestAnimationFrame === 'function') {
				const id = requestAnimationFrame((): void => {
					retryHandle = null;
					scheduleMarkReviewIntakeReady();
				});
				retryHandle = { kind: 'animationFrame', id };
				return;
			}
			const id = window.setTimeout((): void => {
				retryHandle = null;
				scheduleMarkReviewIntakeReady();
			}, 0);
			retryHandle = { kind: 'timeout', id };
		};
		const documentElement = typeof document === 'undefined' ? null : document.documentElement;
		const reviewIntakeReadyObserver =
			documentElement === null || typeof MutationObserver === 'undefined'
				? null
				: new MutationObserver((): void => {
						retryCount = 0;
						scheduleMarkReviewIntakeReady();
					});
		if (reviewIntakeReadyObserver !== null && documentElement !== null) {
			reviewIntakeReadyObserver.observe(documentElement, {
				attributeFilter: [
					'data-bridge-nonce',
					bridgeReviewPaneIdAttribute,
					bridgeReviewStreamIdAttribute,
				],
			});
		}
		const enqueueReviewProtocolFrame = (
			protocolFrame: ReviewProtocolFrame,
			telemetryContext: BridgeReviewPackageTelemetryContext,
		): void => {
			reviewEnvelopeApplyTailRef.current = reviewEnvelopeApplyTailRef.current
				.catch((): void => {})
				.then(async (): Promise<void> => {
					await applyReviewProtocolTransportFrame({
						protocolFrame,
						setReviewPackage,
						setReviewTreeRows,
						setDiffStatus,
						selectInitialReviewItem: beginForegroundReviewSelection,
						setSelectedItemId: (itemId: string | null): void =>
							viewerActions.setSelectedItemId(itemId),
						getSelectedItemId: (): string | null =>
							viewerStore.getState().rootSnapshot.selectedItemId,
						reviewPackageRef,
						telemetryContextByPackageKey: reviewPackageTelemetryContextRef.current,
						currentReviewPackageTelemetryContextRef,
						reviewReadyStartMillisecondsByPackageKeyRef,
						descriptorRegistry,
						reviewContentDescriptorRefsByHandleIdRef,
						reviewDemandScheduler,
						resourceExecutor,
						reviewFrameAuthority: getReviewFrameAuthority(),
						invalidatedFreshnessKeysRef: invalidatedReviewFreshnessKeysRef,
						setReviewContentInvalidationVersion,
						onReviewContentDescriptorRefsRegistered:
							retrySelectedContentAfterDescriptorRegistration,
						telemetryContext,
						telemetryRecorder: telemetryRecorderRef.current,
					});
				})
				.catch((): void => {
					setDiffStatus(
						(): BridgeDiffStatusState => ({
							status: 'error',
							error: 'review_resource_stream_failed',
							epoch: protocolFrame.generation,
						}),
					);
				});
		};
		const reviewIntakeReceiver = createBridgeReviewIntakeReceiver({
			getAuthority: getReviewFrameAuthority,
			onError: (frame: Extract<BridgeIntakeFrame, { readonly kind: 'error' }>): void => {
				setDiffStatus(
					(): BridgeDiffStatusState => ({
						status: 'error',
						error: frame.message,
						epoch: frame.generation,
					}),
				);
				recordReviewIntakeFrameTelemetry({
					telemetryRecorder: telemetryRecorderRef.current,
					frameKind: 'unknown',
					generation: frame.generation,
					sequence: frame.sequence,
					result: 'failed',
					resultReason: 'intake_error',
				});
			},
			onFrame: (
				protocolFrame: ReviewProtocolFrame,
				traceContext: BridgeTraceContext | null,
			): void => {
				const slice = reviewIntakeTelemetrySliceForFrameKind(protocolFrame.frameKind);
				recordReviewIntakeFrameTelemetry({
					telemetryRecorder: telemetryRecorderRef.current,
					frameKind: protocolFrame.frameKind,
					generation: protocolFrame.generation,
					sequence: protocolFrame.sequence,
					result: 'success',
					resultReason: 'none',
				});
				recordIntakeApplyTelemetryForSlice({
					telemetryRecorder: telemetryRecorderRef.current,
					slice,
					traceContext,
					transport: 'intake',
				});
				enqueueReviewProtocolFrame(protocolFrame, {
					slice,
					traceContext,
					transport: 'intake',
				});
			},
		});
		const uninstallIntakeCarrier = installBridgeIntakeEventCarrier({
			target,
			eventName: '__bridge_intake_json',
			getNonce: (): string | null => bridgeHandshakeSessionRef.current?.getPushNonce() ?? null,
			receiver: reviewIntakeReceiver,
			maxFrameBytes: bridgeReviewIntakeMaxFrameBytes,
			requestReplayOnInstall: false,
			onDroppedFrame: (drop: BridgeIntakeCarrierDrop): void => {
				recordReviewIntakeDropTelemetry(telemetryRecorderRef.current, drop);
			},
		});
		const unregisterBridgeReadyCallback = registerBridgeReadyCallback((): void => {
			queueMicrotask(scheduleMarkReviewIntakeReady);
		});
		scheduleMarkReviewIntakeReady();
		const uninstallPushReceiver = installBridgePushReceiver({
			target,
			getPushNonce: (): string | null => bridgeHandshakeSessionRef.current?.getPushNonce() ?? null,
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				reviewEnvelopeApplyTailRef.current = reviewEnvelopeApplyTailRef.current
					.catch((): void => {})
					.then(async (): Promise<void> => {
						recordIntakeApplyTelemetry(telemetryRecorderRef.current, envelope);
						await applyReviewEnvelope({
							envelope,
							hasReviewPackage: reviewPackageRef.current !== null,
							setDiffStatus,
						});
					})
					.catch((): void => {
						setDiffStatus(
							(): BridgeDiffStatusState => ({
								status: 'error',
								error: 'review_resource_stream_failed',
								epoch: envelope.epoch,
							}),
						);
					});
			},
			onDroppedEnvelope: (reason: BridgePushDropReason): void => {
				recordPushDropTelemetry(telemetryRecorderRef.current, reason);
			},
		});
		return (): void => {
			clearScheduledIntakeReadyRetry();
			reviewIntakeReadyObserver?.disconnect();
			uninstallIntakeCarrier();
			uninstallPushReceiver();
			unregisterBridgeReadyCallback();
		};
	}, [
		descriptorRegistry,
		bridgeHandshakeSessionRef,
		beginForegroundReviewSelection,
		getReviewFrameAuthority,
		registerBridgeReadyCallback,
		resourceExecutor,
		reviewDemandScheduler,
		retrySelectedContentAfterDescriptorRegistration,
		rpcClient,
		setReviewPackage,
		target,
		telemetryRecorderRef,
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
			selectedContentActiveLoadKeyRef.current = null;
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {};
		}
		let didCancel = false;
		const contentAbortController = new AbortController();
		selectedContentAbortControllerRef.current = contentAbortController;
		const selectedItemId = rootSnapshotRef.current.selectedItemId;
		const currentReviewPackage = reviewPackageRef.current;
		if (currentReviewPackage === null || selectedItemId === null) {
			setSelectedContentResourcesState(null);
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
				if (selectedContentAbortControllerRef.current === contentAbortController) {
					selectedContentAbortControllerRef.current = null;
				}
			};
		}
		const selectedItem = currentReviewPackage.itemsById[selectedItemId];
		if (selectedItem === undefined) {
			setSelectedContentResourcesState(null);
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
				if (selectedContentAbortControllerRef.current === contentAbortController) {
					selectedContentAbortControllerRef.current = null;
				}
			};
		}
		const selectedContentKey =
			currentSelectedContentKey ??
			makeSelectedContentResourcesKey(currentReviewPackage, selectedItemId);
		const selectedContentLoadKey = selectedContentKey;
		const currentSelectedContentResourcesState = selectedContentResourcesStateRef.current;
		if (
			!shouldStartSelectedReviewContentDemand({
				activeSelectedContentLoadKey: selectedContentActiveLoadKeyRef.current,
				currentSelectedContentResourcesState,
				selectedContentKey,
				selectedContentLoadKey,
			})
		) {
			scheduleForegroundSelectionRelease(selectedContentKey);
			return (): void => {};
		}
		selectedContentActiveLoadKeyRef.current = selectedContentLoadKey;
		const selectedContentLoadStarts = selectedContentLoadStartByKeyRef.current;
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
		selectedContentLoadStarts.set(selectedContentKey, performance.now());
		recordBridgeViewerContentQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
			item: selectedItem,
			interest: 'selected',
		});
		void loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage: currentReviewPackage,
			itemId: selectedItemId,
			interest: 'selected',
			presentation: selectedItemPresentation,
			resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
				reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
			scheduler: reviewDemandScheduler,
			executor: resourceExecutor,
			signal: contentAbortController.signal,
			traceContext: telemetryRecorderRef.current.isEnabled('web')
				? createChildTraceContext(parentTraceContext)
				: null,
			telemetryRecorder: telemetryRecorderRef.current,
			onDemandTelemetry: setLastSelectedDemandTelemetry,
		})
			.then((loadResult): void => {
				if (!didCancel) {
					const loadStartMilliseconds = selectedContentLoadStarts.get(selectedContentKey) ?? null;
					selectedContentLoadStarts.delete(selectedContentKey);
					if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
						selectedContentActiveLoadKeyRef.current = null;
					}
					setSelectedContentResourcesState(
						selectedContentResourcesStateFromDemandLoadResult({
							itemId: selectedItemId,
							contentKey: selectedContentKey,
							loadResult,
						}),
					);
					scheduleForegroundSelectionRelease(selectedContentKey);
					if (loadResult.status === 'ready' && loadStartMilliseconds !== null) {
						recordReviewStartupTelemetry({
							telemetryRecorder: telemetryRecorderRef.current,
							phase: 'selected_content_ready',
							slice: 'content_fetch',
							transport: 'content',
							traceContext: createChildTraceContext(parentTraceContext),
							durationMilliseconds: performance.now() - loadStartMilliseconds,
							result: 'success',
							numericAttributes: {
								'agentstudio.bridge.content.resource_count': contentResourceCount(
									loadResult.resources,
								),
							},
						});
					}
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
					selectedContentLoadStarts.delete(selectedContentKey);
					if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
						selectedContentActiveLoadKeyRef.current = null;
					}
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						status: 'failed',
						resources: null,
					});
					clearForegroundSelectionNow(selectedContentKey);
				}
			});
		return (): void => {
			didCancel = true;
			selectedContentLoadStarts.delete(selectedContentKey);
			contentAbortController.abort();
			if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
				selectedContentActiveLoadKeyRef.current = null;
			}
			if (selectedContentAbortControllerRef.current === contentAbortController) {
				selectedContentAbortControllerRef.current = null;
			}
		};
	}, [
		resourceExecutor,
		reviewDemandScheduler,
		cancelForegroundSelectionRelease,
		clearForegroundSelectionNow,
		props.isActive,
		currentSelectedContentKey,
		scheduleForegroundSelectionRelease,
		selectedContentRetryVersion,
		selectedItemPresentation,
		setSelectedContentRetryVersion,
		telemetryRecorderRef,
	]);

	useEffect((): (() => void) => {
		let didCancel = false;
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		if (!props.isActive) {
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			setSelectedMarkdownPreviewState(
				(currentState: SelectedMarkdownPreviewState | null): SelectedMarkdownPreviewState | null =>
					currentState?.status === 'rendering' ? null : currentState,
			);
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
		telemetryRecorderRef,
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
				'agentstudio.bridge.transport': telemetryContext?.transport ?? 'unknown',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		telemetryRecorderRef.current.flush({ force: true });
	}, [projection, props.isActive, reviewPackage, telemetryRecorderRef]);

	useEffect((): void => {
		if (
			!props.isActive ||
			reviewPackage === null ||
			projection === null ||
			selectedContentResourcesState?.status !== 'ready' ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const packageKey = `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
		const selectedReadyKey = `${packageKey}:${selectedContentResourcesState.itemId}:${selectedContentResourcesState.contentKey}`;
		if (lastReviewReadyPackageRef.current === selectedReadyKey) {
			return;
		}
		lastReviewReadyPackageRef.current = selectedReadyKey;
		const telemetryContext = reviewPackageTelemetryContextRef.current.get(packageKey);
		const reviewReadyStartMilliseconds =
			reviewReadyStartMillisecondsByPackageKeyRef.current.get(packageKey) ?? null;
		if (reviewReadyStartMilliseconds !== null) {
			reviewReadyStartMillisecondsByPackageKeyRef.current.delete(packageKey);
		}
		recordReviewStartupTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			phase: 'review_ready',
			slice: telemetryContext?.slice ?? 'review_projection',
			transport: telemetryContext?.transport ?? 'intake',
			traceContext: createChildTraceContext(telemetryContext?.traceContext ?? null),
			durationMilliseconds:
				reviewReadyStartMilliseconds === null
					? null
					: performance.now() - reviewReadyStartMilliseconds,
			result: 'success',
			numericAttributes: {
				'agentstudio.bridge.review.item_count': reviewPackage.orderedItemIds.length,
			},
		});
	}, [
		projection,
		props.isActive,
		reviewPackage,
		selectedContentResourcesState,
		telemetryRecorderRef,
	]);

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
	}, [props.isActive, reviewPackage, rootSnapshot.selectedItemId, rpcClient, telemetryRecorderRef]);

	const selectedCanvasLoadingReason = selectedCanvasLoadingReasonForCurrentSelection({
		selectedContentKey: currentSelectedContentKey,
		selectedContentResourcesState,
		selectedItemId: rootSnapshot.selectedItemId,
		selectedMarkdownPreviewState,
	});
	const selectedContentLoadingItemId =
		selectedCanvasLoadingReason === 'content' ? rootSnapshot.selectedItemId : null;
	const visibleContentResourcesByItemIdForCodeView = visibleContentHydrationPaused
		? emptyVisibleContentResourcesByItemId
		: visibleContentHydration.visibleContentResourcesByItemId;
	const visibleLoadingItemIdsForCodeView = visibleContentHydrationPaused
		? emptyVisibleLoadingItemIds
		: visibleContentHydration.visibleLoadingItemIds;
	const visibleLoadingItemCountForCodeView = visibleContentHydrationPaused
		? 0
		: visibleContentHydration.visibleLoadingItemCount;
	const visibleReadyItemCountForCodeView = visibleContentHydrationPaused
		? 0
		: visibleContentHydration.visibleReadyItemCount;

	return reviewPackage === null && diffStatus.status === 'loading' ? (
		<BridgeReviewMetadataLoadingShell />
	) : reviewPackage === null && diffStatus.status === 'error' ? (
		<BridgeReviewMetadataFailedShell error={diffStatus.error} />
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
			selectionCommitDurationMilliseconds={lastSelectionCommitDurationMilliseconds}
			onCodeViewControlHandleChange={(handle): void => {
				codeViewControlHandleRef.current = handle;
			}}
			onCodeViewScrollActivityChange={setIsCodeViewScrollActive}
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
			reviewTreeRows={reviewTreeRows}
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
			lastSelectedDemandTelemetry={lastSelectedDemandTelemetryForCurrentPackage}
			lastVisibleDemandTelemetry={lastVisibleDemandTelemetryForCurrentPackage}
			visibleContentResourcesByItemId={visibleContentResourcesByItemIdForCodeView}
			visibleLoadingItemIds={visibleLoadingItemIdsForCodeView}
			visibleLoadingItemCount={visibleLoadingItemCountForCodeView}
			visibleReadyItemCount={visibleReadyItemCountForCodeView}
			onCodeViewVisibleItemIdsChange={setCodeViewVisibleReviewItemIds}
			onTreeVisibleItemIdsChange={setTreeVisibleReviewItemIds}
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
	readonly selectReviewItem: (itemId: string) => boolean;
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
			return selectReviewItem(command.itemId)
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
				if (!selectReviewItem(itemId)) {
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

function reviewContentDemandTelemetryForPackage(props: {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly telemetry: ReviewContentDemandTelemetry | null;
}): ReviewContentDemandTelemetry | null {
	if (props.reviewPackage === null || props.telemetry === null) {
		return null;
	}
	if (
		props.telemetry.packageId !== props.reviewPackage.packageId ||
		props.telemetry.reviewGeneration !== props.reviewPackage.reviewGeneration ||
		props.telemetry.revision !== props.reviewPackage.revision
	) {
		return null;
	}
	return props.reviewPackage.itemsById[props.telemetry.itemId] === undefined
		? null
		: props.telemetry;
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
	if (
		props.target.reviewItemId !== undefined &&
		props.reviewPackage.itemsById[props.target.reviewItemId] !== undefined
	) {
		return props.target.reviewItemId;
	}
	const matchedItem = Object.values(props.reviewPackage.itemsById).find(
		(item: BridgeReviewItemDescriptor): boolean =>
			item.headPath === props.target.fileRef.path || item.basePath === props.target.fileRef.path,
	);
	return matchedItem?.itemId ?? null;
}

function clearReviewRefinementsHidingExplicitTarget(props: {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}): boolean {
	let didClearRefinement = false;
	if (props.rootSnapshot.treeSearchText.length > 0) {
		props.viewerActions.setTreeSearchText('');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.treeSearchMode.kind !== 'text') {
		props.viewerActions.setTreeSearchMode({ kind: 'text' });
		didClearRefinement = true;
	}
	if (props.rootSnapshot.gitStatusFilter !== 'all') {
		props.viewerActions.setGitStatusFilter('all');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.fileClassFilter !== 'all') {
		props.viewerActions.setFileClassFilter('all');
		didClearRefinement = true;
	}
	if (props.rootSnapshot.facets.length > 0) {
		props.viewerActions.setProjectionFacets([]);
		didClearRefinement = true;
	}
	return didClearRefinement;
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
		props.target.reviewItemId !== undefined &&
		props.target.reviewItemId !== props.selectedItemId
	) {
		return null;
	}
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

function contentResourceCount(resources: BridgeCodeViewContentResources): number {
	return [resources.base, resources.head, resources.diff, resources.file].filter(
		(resource): boolean => resource !== undefined,
	).length;
}

export interface ShouldPauseVisibleReviewContentHydrationProps {
	readonly isActive: boolean;
	readonly codeViewScrollActive: boolean;
	readonly currentSelectedContentKey: string | null;
	readonly foregroundSelectedContentKey: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

export interface ShouldStartSelectedReviewContentDemandProps {
	readonly activeSelectedContentLoadKey: string | null;
	readonly currentSelectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedContentKey: string;
	readonly selectedContentLoadKey: string;
}

export interface ShouldRetrySelectedReviewContentAfterDescriptorRegistrationProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly registeredDescriptorRefCount: number;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly lastSelectedDemandTelemetry: ReviewContentDemandTelemetry | null;
}

export function shouldStartSelectedReviewContentDemand(
	props: ShouldStartSelectedReviewContentDemandProps,
): boolean {
	if (
		props.currentSelectedContentResourcesState?.contentKey === props.selectedContentKey &&
		props.currentSelectedContentResourcesState.status === 'ready'
	) {
		return false;
	}
	return props.activeSelectedContentLoadKey !== props.selectedContentLoadKey;
}

export function shouldRetrySelectedReviewContentAfterDescriptorRegistration(
	props: ShouldRetrySelectedReviewContentAfterDescriptorRegistrationProps,
): boolean {
	if (
		props.registeredDescriptorRefCount <= 0 ||
		props.reviewPackage === null ||
		props.selectedItemId === null ||
		props.selectedContentResourcesState === null ||
		props.lastSelectedDemandTelemetry === null
	) {
		return false;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return false;
	}
	const selectedContentKey = makeReviewItemContentResourcesKey({
		item: selectedItem,
		reviewPackage: props.reviewPackage,
	});
	return (
		props.selectedContentResourcesState.itemId === props.selectedItemId &&
		props.selectedContentResourcesState.contentKey === selectedContentKey &&
		props.selectedContentResourcesState.status === 'failed' &&
		props.lastSelectedDemandTelemetry.itemId === props.selectedItemId &&
		props.lastSelectedDemandTelemetry.packageId === props.reviewPackage.packageId &&
		props.lastSelectedDemandTelemetry.reviewGeneration === props.reviewPackage.reviewGeneration &&
		props.lastSelectedDemandTelemetry.revision === props.reviewPackage.revision &&
		props.lastSelectedDemandTelemetry.interest === 'selected' &&
		props.lastSelectedDemandTelemetry.resultStatus === 'failed' &&
		props.lastSelectedDemandTelemetry.resultReason === 'descriptor_missing'
	);
}

export function shouldPauseVisibleReviewContentHydration(
	props: ShouldPauseVisibleReviewContentHydrationProps,
): boolean {
	return (
		props.codeViewScrollActive ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState === null) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState !== null &&
			props.selectedContentResourcesState.contentKey !== props.currentSelectedContentKey) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.foregroundSelectedContentKey === props.currentSelectedContentKey) ||
		(props.isActive &&
			props.currentSelectedContentKey !== null &&
			props.selectedContentResourcesState !== null &&
			props.selectedContentResourcesState.contentKey === props.currentSelectedContentKey &&
			props.selectedContentResourcesState.status === 'loading')
	);
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

function recordIntakeApplyTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	envelope: BridgePushEnvelope,
): void {
	recordIntakeApplyTelemetryForSlice({
		telemetryRecorder,
		slice: envelope.slice,
		traceContext: envelope.traceContext,
		transport: 'push',
	});
}

function recordIntakeApplyTelemetryForSlice(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
	readonly transport: 'intake' | 'push';
}): void {
	const eventName =
		props.transport === 'push'
			? 'performance.bridge.web.push_apply'
			: 'performance.bridge.web.intake_apply';
	props.telemetryRecorder.record({
		scope: 'web',
		name: eventName,
		durationMilliseconds: null,
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': 'apply',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.slice': props.slice,
			'agentstudio.bridge.transport': props.transport,
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush({ force: true });
}

function recordReviewStartupTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly phase: BridgeReviewStartupTelemetryPhase;
	readonly slice: BridgeTelemetrySlice;
	readonly transport: 'content' | 'intake' | 'push' | 'worker';
	readonly traceContext: BridgeTraceContext | null;
	readonly durationMilliseconds: number | null;
	readonly result: 'failed' | 'success';
	readonly resultReason?: string;
	readonly numericAttributes?: Readonly<Record<string, number>>;
}): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: `performance.bridge.web.${props.phase}`,
		durationMilliseconds:
			props.durationMilliseconds === null ? null : Math.max(0, props.durationMilliseconds),
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.priority': priorityForBridgeStartupTelemetryPhase(props.phase),
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.result_reason': props.resultReason ?? 'none',
			'agentstudio.bridge.slice': props.slice,
			'agentstudio.bridge.transport': props.transport,
		},
		numericAttributes: props.numericAttributes ?? {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush({ force: true });
}

function priorityForBridgeStartupTelemetryPhase(
	phase: BridgeReviewStartupTelemetryPhase,
): BridgeTelemetryPriority {
	switch (phase) {
		case 'selection_commit':
			return 'warm';
		case 'review_metadata_apply':
		case 'review_ready':
		case 'selected_content_ready':
			return 'hot';
	}
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

function recordReviewIntakeDropTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	drop: BridgeIntakeCarrierDrop,
): void {
	recordReviewIntakeFrameTelemetry({
		telemetryRecorder,
		frameKind:
			drop.reason === 'receiver_rejected_frame'
				? intakeTelemetryKindForFrameSummary(drop.frame.kind)
				: 'unknown',
		generation: drop.reason === 'receiver_rejected_frame' ? drop.frame.generation : 0,
		sequence: drop.reason === 'receiver_rejected_frame' ? drop.frame.sequence : 0,
		result: 'dropped',
		resultReason: drop.reason === 'receiver_rejected_frame' ? drop.receiverReason : drop.reason,
	});
}

function recordReviewIntakeFrameTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly frameKind: ReviewProtocolFrame['frameKind'] | 'unknown';
	readonly generation: number;
	readonly sequence: number;
	readonly result: 'dropped' | 'failed' | 'success';
	readonly resultReason: string;
}): void {
	const slice = reviewIntakeTelemetrySliceForFrameKind(props.frameKind);
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.intake_frame',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.intake.frame_kind': props.frameKind,
			'agentstudio.bridge.phase': 'intake',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(slice),
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.result_reason': props.resultReason,
			'agentstudio.bridge.slice': slice,
			'agentstudio.bridge.transport': 'intake',
		},
		numericAttributes: {
			'agentstudio.bridge.intake.generation': props.generation,
			'agentstudio.bridge.intake.sequence': props.sequence,
		},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush({ force: true });
}

function reviewIntakeTelemetrySliceForFrameKind(
	frameKind: ReviewProtocolFrame['frameKind'] | 'unknown',
): BridgeTelemetrySlice {
	switch (frameKind) {
		case 'review.metadataSnapshot':
		case 'review.metadataWindow':
			return 'review_metadata';
		case 'review.metadataDelta':
			return 'review_delta';
		case 'review.invalidate':
			return 'review_invalidation';
		case 'review.reset':
			return 'review_reset';
		case 'unknown':
			return 'review_projection';
	}
	return 'review_projection';
}

function intakeTelemetryKindForFrameSummary(
	frameKind: BridgeIntakeFrame['kind'],
): ReviewProtocolFrame['frameKind'] | 'unknown' {
	switch (frameKind) {
		case 'snapshot':
			return 'review.metadataSnapshot';
		case 'delta':
			return 'review.metadataDelta';
		case 'invalidate':
			return 'review.invalidate';
		case 'reset':
			return 'review.reset';
		case 'close':
		case 'error':
			return 'unknown';
	}
	return 'unknown';
}

async function applyReviewProtocolTransportFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame;
	readonly setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void;
	readonly setReviewTreeRows: (
		update: (current: readonly ReviewTreeRowMetadata[]) => readonly ReviewTreeRowMetadata[],
	) => void;
	readonly setDiffStatus: (
		update: (current: BridgeDiffStatusState) => BridgeDiffStatusState,
	) => void;
	readonly setSelectedItemId: (itemId: string | null) => void;
	readonly selectInitialReviewItem: (itemId: string) => boolean;
	readonly getSelectedItemId: () => string | null;
	readonly reviewPackageRef: { current: BridgeReviewPackage | null };
	readonly telemetryContextByPackageKey: Map<string, BridgeReviewPackageTelemetryContext>;
	readonly currentReviewPackageTelemetryContextRef: {
		current: BridgeReviewPackageTelemetryContext | null;
	};
	readonly reviewReadyStartMillisecondsByPackageKeyRef: {
		readonly current: Map<string, number>;
	};
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewContentDescriptorRefsByHandleIdRef: {
		current: ReadonlyMap<string, BridgeDescriptorRef>;
	};
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
	readonly invalidatedFreshnessKeysRef: { readonly current: Set<string> };
	readonly setReviewContentInvalidationVersion: Dispatch<SetStateAction<number>>;
	readonly onReviewContentDescriptorRefsRegistered: (registeredDescriptorRefCount: number) => void;
	readonly telemetryContext: BridgeReviewPackageTelemetryContext;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}): Promise<void> {
	await applyReviewProtocolFramePayload(props);
}

async function applyReviewEnvelope(props: {
	readonly envelope: BridgePushEnvelope;
	readonly hasReviewPackage: boolean;
	readonly setDiffStatus: (
		update: (current: BridgeDiffStatusState) => BridgeDiffStatusState,
	) => void;
}): Promise<void> {
	if (props.envelope.store !== 'diff' || props.envelope.slice !== 'diff_status') {
		return;
	}
	const diffStatusPayload = extractDiffStatus(props.envelope.data);
	if (diffStatusPayload !== null) {
		props.setDiffStatus(
			(current): BridgeDiffStatusState =>
				nextReviewDiffStatus({
					current,
					hasReviewPackage: props.hasReviewPackage,
					next: diffStatusPayload,
				}),
		);
	}
}

function nextReviewDiffStatus(props: {
	readonly current: BridgeDiffStatusState;
	readonly hasReviewPackage: boolean;
	readonly next: BridgeDiffStatusState;
}): BridgeDiffStatusState {
	if (props.next.epoch < props.current.epoch) {
		return props.current;
	}
	if (props.next.status !== 'ready' || props.hasReviewPackage) {
		return props.next;
	}
	if (props.current.status === 'error' && props.current.epoch >= props.next.epoch) {
		return props.current;
	}
	return {
		status: 'loading',
		error: null,
		epoch: props.next.epoch,
	};
}

async function applyReviewProtocolFramePayload(
	props: Parameters<typeof applyReviewProtocolTransportFrame>[0],
): Promise<void> {
	const {
		setReviewPackage,
		setReviewTreeRows,
		setDiffStatus,
		setSelectedItemId,
		selectInitialReviewItem,
		getSelectedItemId,
		reviewPackageRef,
		telemetryContextByPackageKey,
		currentReviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		descriptorRegistry,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewDemandScheduler,
		resourceExecutor,
		reviewFrameAuthority,
		invalidatedFreshnessKeysRef,
		setReviewContentInvalidationVersion,
		onReviewContentDescriptorRefsRegistered,
	} = props;
	const protocolFrame = props.protocolFrame;
	if (
		protocolFrame?.frameKind === 'review.metadataSnapshot' &&
		!reviewSnapshotFrameMatchesAuthority({
			frame: protocolFrame,
			reviewFrameAuthority,
		})
	) {
		setDiffStatus(
			(): BridgeDiffStatusState => ({
				status: 'error',
				error: 'review_protocol_frame_unavailable',
				epoch: protocolFrame.generation,
			}),
		);
		return;
	}
	const snapshotFrame = materializeReviewProtocolSnapshotFrame({
		protocolFrame,
		descriptorRegistry,
		reviewFrameAuthority,
	});
	if (protocolFrame?.frameKind === 'review.metadataSnapshot' && snapshotFrame === null) {
		failReviewMetadataSnapshotApply({
			error: 'review_metadata_snapshot_rejected',
			generation: protocolFrame.generation,
			setDiffStatus,
			telemetryContext: props.telemetryContext,
			telemetryRecorder: props.telemetryRecorder,
		});
		return;
	}
	if (snapshotFrame !== null) {
		let packagePayload: BridgeReviewPackage;
		try {
			packagePayload = bridgeReviewPackageFromMetadataSnapshot(snapshotFrame);
		} catch {
			failReviewMetadataSnapshotApply({
				error: 'review_metadata_snapshot_parse_failed',
				generation: snapshotFrame.generation,
				setDiffStatus,
				telemetryContext: props.telemetryContext,
				telemetryRecorder: props.telemetryRecorder,
			});
			return;
		}
		const currentReviewPackage = reviewPackageRef.current;
		if (
			currentReviewPackage !== null &&
			isStaleReviewPackageReplacement(currentReviewPackage, packagePayload)
		) {
			return;
		}
		const shouldMergeSnapshotWithCurrentPackage =
			currentReviewPackage !== null &&
			currentReviewPackage.packageId === packagePayload.packageId &&
			currentReviewPackage.reviewGeneration === packagePayload.reviewGeneration;
		if (shouldMergeSnapshotWithCurrentPackage) {
			packagePayload = bridgeReviewPackageWithMetadataSnapshot({
				reviewPackage: currentReviewPackage,
				snapshotPackage: packagePayload,
			});
		}

		const applyStartMilliseconds = performance.now();
		const materializedFrame = materializeAcceptedReviewSnapshotForPackage({
			descriptorRegistry,
			protocolFrame,
			reviewFrameAuthority,
			reviewPackage: packagePayload,
			snapshotFrame,
		});
		if (materializedFrame === null) {
			failReviewMetadataSnapshotApply({
				error: 'review_metadata_snapshot_descriptor_mismatch',
				generation: packagePayload.reviewGeneration,
				setDiffStatus,
				telemetryContext: props.telemetryContext,
				telemetryRecorder: props.telemetryRecorder,
			});
			return;
		}
		if (shouldMergeSnapshotWithCurrentPackage) {
			cancelReviewDescriptorDemandGroups({
				descriptorRefs: materializedFrame.descriptorRefsByHandleId,
				reviewDemandScheduler,
				resourceExecutor,
			});
			reviewContentDescriptorRefsByHandleIdRef.current = new Map([
				...reviewContentDescriptorRefsByHandleIdRef.current,
				...materializedFrame.descriptorRefsByHandleId,
			]);
		} else {
			cancelReviewDescriptorDemandGroups({
				descriptorRefs: reviewContentDescriptorRefsByHandleIdRef.current,
				reviewDemandScheduler,
				resourceExecutor,
			});
			reviewContentDescriptorRefsByHandleIdRef.current = materializedFrame.descriptorRefsByHandleId;
		}
		const telemetryContext = {
			slice: props.telemetryContext.slice,
			traceContext: props.telemetryContext.traceContext,
			transport: props.telemetryContext.transport,
		};
		const packageTelemetryKey = makeTelemetryPackageKey(packagePayload);
		telemetryContextByPackageKey.set(packageTelemetryKey, telemetryContext);
		reviewReadyStartMillisecondsByPackageKeyRef.current.set(
			packageTelemetryKey,
			applyStartMilliseconds,
		);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = packagePayload;
		setReviewTreeRows((current): readonly ReviewTreeRowMetadata[] =>
			shouldMergeSnapshotWithCurrentPackage
				? mergeReviewTreeRowsByRowId({
						current,
						nextRows: snapshotFrame.treeRows,
					})
				: snapshotFrame.treeRows,
		);
		setDiffStatus(
			(): BridgeDiffStatusState => ({
				status: 'ready',
				error: null,
				epoch: packagePayload.reviewGeneration,
			}),
		);
		setReviewPackage((): BridgeReviewPackage => packagePayload);
		recordReviewStartupTelemetry({
			telemetryRecorder: props.telemetryRecorder,
			phase: 'review_metadata_apply',
			slice: props.telemetryContext.slice,
			transport: props.telemetryContext.transport,
			traceContext: createChildTraceContext(props.telemetryContext.traceContext),
			durationMilliseconds: performance.now() - applyStartMilliseconds,
			result: 'success',
			resultReason: 'none',
			numericAttributes: {
				'agentstudio.bridge.review.item_count': packagePayload.orderedItemIds.length,
			},
		});
		const currentSelectedItemId = getSelectedItemId();
		const nextSelectedItemId =
			currentSelectedItemId === null || !(currentSelectedItemId in packagePayload.itemsById)
				? firstVisibleItemId(packagePayload)
				: currentSelectedItemId;
		if (nextSelectedItemId === null) {
			setSelectedItemId(null);
		} else {
			selectInitialReviewItem(nextSelectedItemId);
		}
		return;
	}

	const windowFrame = materializeReviewProtocolWindowFrame({
		protocolFrame,
		descriptorRegistry,
		reviewFrameAuthority,
	});
	if (windowFrame !== null) {
		const currentReviewPackage = reviewPackageRef.current;
		if (
			currentReviewPackage === null ||
			currentReviewPackage.packageId !== windowFrame.packageId ||
			currentReviewPackage.revision !== windowFrame.revision
		) {
			return;
		}
		const packagePayload = bridgeReviewPackageWithMetadataWindow({
			reviewPackage: currentReviewPackage,
			windowFrame,
		});
		reviewContentDescriptorRefsByHandleIdRef.current = new Map([
			...reviewContentDescriptorRefsByHandleIdRef.current,
			...windowFrame.registeredContentDescriptorRefs.map(
				(ref): readonly [string, BridgeDescriptorRef] => [ref.descriptorId, ref],
			),
		]);
		onReviewContentDescriptorRefsRegistered(windowFrame.registeredContentDescriptorRefs.length);
		reviewPackageRef.current = packagePayload;
		setReviewTreeRows((current): readonly ReviewTreeRowMetadata[] =>
			mergeReviewTreeRowsByRowId({
				current,
				nextRows: windowFrame.treeRows,
			}),
		);
		setReviewPackage((): BridgeReviewPackage => packagePayload);
		return;
	}

	const deltaFrame = materializeReviewProtocolDeltaFrame({
		protocolFrame,
		descriptorRegistry,
		reviewFrameAuthority,
	});
	if (deltaFrame !== null) {
		const currentReviewPackage = reviewPackageRef.current;
		const packagePayload =
			currentReviewPackage === null
				? null
				: applyReviewMetadataDeltaToReviewPackage({
						deltaFrame,
						reviewPackage: currentReviewPackage,
					});
		if (packagePayload !== null) {
			reviewContentDescriptorRefsByHandleIdRef.current = new Map([
				...reviewContentDescriptorRefsByHandleIdRef.current,
				...deltaFrame.registeredContentDescriptorRefs.map(
					(ref): readonly [string, BridgeDescriptorRef] => [ref.descriptorId, ref],
				),
			]);
			onReviewContentDescriptorRefsRegistered(deltaFrame.registeredContentDescriptorRefs.length);
			reviewPackageRef.current = packagePayload;
			setReviewTreeRows((current): readonly ReviewTreeRowMetadata[] =>
				reviewTreeRowsWithMetadataDelta({
					current,
					deltaFrame,
				}),
			);
			setReviewPackage((): BridgeReviewPackage => packagePayload);
		}
		return;
	}
	{
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
			setReviewTreeRows((): readonly ReviewTreeRowMetadata[] => []);
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
}

function failReviewMetadataSnapshotApply(props: {
	readonly error: ReviewMetadataSnapshotApplyFailure;
	readonly generation: number;
	readonly setDiffStatus: (
		update: (current: BridgeDiffStatusState) => BridgeDiffStatusState,
	) => void;
	readonly telemetryContext: BridgeReviewPackageTelemetryContext;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}): void {
	props.setDiffStatus(
		(): BridgeDiffStatusState => ({
			status: 'error',
			error: props.error,
			epoch: props.generation,
		}),
	);
	recordReviewStartupTelemetry({
		telemetryRecorder: props.telemetryRecorder,
		phase: 'review_metadata_apply',
		slice: props.telemetryContext.slice,
		transport: props.telemetryContext.transport,
		traceContext: createChildTraceContext(props.telemetryContext.traceContext),
		durationMilliseconds: null,
		result: 'failed',
		resultReason: reviewMetadataSnapshotApplyFailureResultReason(props.error),
	});
}

function reviewMetadataSnapshotApplyFailureResultReason(
	error: ReviewMetadataSnapshotApplyFailure,
): string {
	switch (error) {
		case 'review_metadata_snapshot_descriptor_mismatch':
			return 'snapshot_descriptor_mismatch';
		case 'review_metadata_snapshot_parse_failed':
			return 'snapshot_package_parse_failed';
		case 'review_metadata_snapshot_rejected':
			return 'snapshot_materializer_rejected';
	}
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

function mergeReviewTreeRowsByRowId(props: {
	readonly current: readonly ReviewTreeRowMetadata[];
	readonly nextRows: readonly ReviewTreeRowMetadata[];
}): readonly ReviewTreeRowMetadata[] {
	if (props.nextRows.length === 0) {
		return props.current;
	}
	const rowsById = new Map(
		props.current.map((row): readonly [string, ReviewTreeRowMetadata] => [row.rowId, row]),
	);
	for (const row of props.nextRows) {
		rowsById.set(row.rowId, row);
	}
	return [...rowsById.values()];
}

export function reviewTreeRowsWithMetadataDelta(props: {
	readonly current: readonly ReviewTreeRowMetadata[];
	readonly deltaFrame: ReviewDeltaMaterializerDelta;
}): readonly ReviewTreeRowMetadata[] {
	let rows: readonly ReviewTreeRowMetadata[] = props.current;
	for (const operation of props.deltaFrame.operations) {
		switch (operation.kind) {
			case 'appendItems':
			case 'invalidateContentDescriptors':
			case 'movePathPrefix':
			case 'removeItems':
			case 'replaceItemOrder':
			case 'selectItem':
			case 'upsertExtentFacts':
			case 'upsertItemMetadata':
				break;
			case 'upsertTreeRows':
				rows = mergeReviewTreeRowsByRowId({
					current: rows,
					nextRows: operation.rows,
				});
				break;
			case 'removeTreeRows': {
				const removedRowIds = new Set(operation.rowIds ?? []);
				const removedPaths = new Set(operation.paths ?? []);
				if (removedRowIds.size > 0 || removedPaths.size > 0) {
					rows = pruneEmptyReviewTreeDirectories(
						rows.filter(
							(row): boolean => !removedRowIds.has(row.rowId) && !removedPaths.has(row.path),
						),
					);
				}
				break;
			}
			case 'replaceTreeWindow':
				rows = operation.rows;
				break;
		}
	}
	return rows;
}

export function pruneEmptyReviewTreeDirectories(
	rows: readonly ReviewTreeRowMetadata[],
): readonly ReviewTreeRowMetadata[] {
	return rows.filter((row): boolean => {
		if (!row.isDirectory) {
			return true;
		}
		const descendantPathPrefix = `${row.path.replace(/\/+$/, '')}/`;
		return rows.some(
			(candidate): boolean =>
				!candidate.isDirectory && candidate.path.startsWith(descendantPathPrefix),
		);
	});
}

interface MaterializedReviewSnapshotForPackage {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
}

function materializeReviewProtocolSnapshotFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewSnapshotMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataSnapshot' ||
		!reviewSnapshotFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataSnapshot'
		? materializeResult.delta
		: null;
}

function materializeReviewProtocolDeltaFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewDeltaMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataDelta' ||
		!reviewDeltaFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataDelta'
		? materializeResult.delta
		: null;
}

function materializeReviewProtocolWindowFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewWindowMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataWindow' ||
		!reviewWindowFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataWindow'
		? materializeResult.delta
		: null;
}

function materializeAcceptedReviewSnapshotForPackage(props: {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
	readonly reviewPackage: BridgeReviewPackage;
	readonly snapshotFrame: ReviewSnapshotMaterializerDelta;
}): MaterializedReviewSnapshotForPackage | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataSnapshot' ||
		props.reviewFrameAuthority === null ||
		!reviewSnapshotFrameMatchesPackage({
			frame: props.protocolFrame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		})
	) {
		return null;
	}
	const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
		descriptorRegistry: props.descriptorRegistry,
		frame: props.protocolFrame,
		reviewFrameAuthority: props.reviewFrameAuthority,
		reviewPackage: props.reviewPackage,
	});
	if (descriptorRefsByHandleId === null) {
		return null;
	}
	return { descriptorRefsByHandleId };
}

export function reviewSnapshotDescriptorRefsByHandleIdForPackage(props: {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): ReadonlyMap<string, BridgeDescriptorRef> | null {
	if (
		!reviewSnapshotFrameMatchesPackage({
			frame: props.frame,
			reviewFrameAuthority: props.reviewFrameAuthority,
			reviewPackage: props.reviewPackage,
		})
	) {
		return null;
	}
	return deriveAndRegisterReviewContentDescriptorRefs({
		descriptorRegistry: props.descriptorRegistry,
		frame: props.frame,
		reviewFrameAuthority: props.reviewFrameAuthority,
		reviewPackage: props.reviewPackage,
	});
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
	return true;
}

function reviewSnapshotFrameMatchesPackage(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
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
		props.frame.comparison.packageId === props.reviewPackage.packageId &&
		props.frame.comparison.sourceIdentity === props.reviewPackage.query.queryId &&
		props.frame.comparison.generation === props.reviewPackage.reviewGeneration &&
		props.frame.comparison.revision === props.reviewPackage.revision
	) {
		return reviewSnapshotFrameDescriptorsMatchPackage({
			frame: props.frame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		});
	}
	return false;
}

export function reviewSnapshotFrameDescriptorsMatchPackage(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): boolean {
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	const descriptorIds = new Set<string>();
	const attachedDescriptors = props.frame.comparison.contentDescriptors ?? [];
	if (attachedDescriptors.length === 0) {
		return true;
	}
	for (const attachedDescriptor of attachedDescriptors) {
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
	return true;
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
		contentDescriptorResourceUrlMatchesPackageHandle({
			attachedDescriptor: args.attachedDescriptor,
			handle,
		}) &&
		args.attachedDescriptor.descriptor.content.mediaType === handle.mimeType &&
		contentDescriptorByteBoundsMatchPackageHandle({
			attachedDescriptor: args.attachedDescriptor,
			handle,
		}) &&
		bridgeIdentitiesEqual(args.attachedDescriptor.ref.expectedIdentity, expectedIdentity) &&
		bridgeIdentitiesEqual(args.attachedDescriptor.descriptor.identity, expectedIdentity)
	);
}

function contentDescriptorResourceUrlMatchesPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly handle: BridgeContentHandle;
}): boolean {
	const descriptorResourceUrl = parseBridgeCoreResourceUrl(
		args.attachedDescriptor.descriptor.resourceUrl,
		{
			allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
		},
	);
	const handleResourceUrl = parseBridgeCoreResourceUrl(args.handle.resourceUrl, {
		allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
	});
	return (
		descriptorResourceUrl !== null &&
		handleResourceUrl !== null &&
		descriptorResourceUrl.protocol === 'review' &&
		descriptorResourceUrl.resourceKind === 'content' &&
		descriptorResourceUrl.opaqueId === args.handle.handleId &&
		descriptorResourceUrl.canonicalUrl === handleResourceUrl.canonicalUrl
	);
}

function contentDescriptorByteBoundsMatchPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly handle: BridgeContentHandle;
}): boolean {
	const expectedBytes = args.attachedDescriptor.descriptor.content.expectedBytes;
	if (expectedBytes !== undefined) {
		return expectedBytes === args.handle.sizeBytes;
	}
	return args.attachedDescriptor.descriptor.content.maxBytes >= Math.max(args.handle.sizeBytes, 1);
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

function deriveAndRegisterReviewContentDescriptorRefs(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly frame?: ReviewMetadataSnapshotFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
}): ReadonlyMap<string, BridgeDescriptorRef> | null {
	const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>();
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	for (const attachedDescriptor of props.frame?.comparison.contentDescriptors ?? []) {
		const handle = handlesById.get(attachedDescriptor.ref.descriptorId);
		if (handle === undefined) {
			return null;
		}
		const registerResult = props.descriptorRegistry.register(attachedDescriptor);
		if (!registerResult.ok) {
			return null;
		}
		descriptorRefsByHandleId.set(handle.handleId, attachedDescriptor.ref);
	}
	for (const handle of handlesById.values()) {
		if (descriptorRefsByHandleId.has(handle.handleId)) {
			continue;
		}
		const attachedDescriptor = deriveReviewContentDescriptorFromHandle({
			handle,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		});
		if (attachedDescriptor === null) {
			return null;
		}
		const registerResult = props.descriptorRegistry.register(attachedDescriptor);
		if (!registerResult.ok) {
			return null;
		}
		descriptorRefsByHandleId.set(handle.handleId, attachedDescriptor.ref);
	}
	return descriptorRefsByHandleId;
}

function deriveReviewContentDescriptorFromHandle(props: {
	readonly handle: BridgeContentHandle;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): BridgeAttachedResourceDescriptor | null {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(props.handle.resourceUrl, {
		allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
	});
	if (
		parsedResourceUrl === null ||
		parsedResourceUrl.protocol !== 'review' ||
		parsedResourceUrl.resourceKind !== 'content' ||
		parsedResourceUrl.opaqueId !== props.handle.handleId
	) {
		return null;
	}
	const identity: BridgeIdentity = {
		paneId: props.reviewFrameAuthority.paneId,
		protocol: 'review',
		sourceId: props.reviewPackage.query.queryId,
		packageId: props.reviewPackage.packageId,
		generation: props.handle.reviewGeneration,
		...(parsedResourceUrl.revision === undefined ? {} : { revision: parsedResourceUrl.revision }),
		streamId: props.reviewFrameAuthority.streamId,
		...(parsedResourceUrl.cursor === undefined ? {} : { cursor: parsedResourceUrl.cursor }),
	};
	const integrity =
		props.handle.contentHashAlgorithm === 'sha256' && props.handle.contentHash.length > 0
			? ({
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: props.handle.contentHash,
				} as const)
			: undefined;
	const descriptor = {
		descriptorId: parsedResourceUrl.opaqueId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: parsedResourceUrl.canonicalUrl,
		identity,
		content: {
			mediaType: props.handle.mimeType,
			encoding: props.handle.isBinary ? 'binary' : 'utf-8',
			expectedBytes: props.handle.sizeBytes,
			maxBytes: Math.max(props.handle.sizeBytes, 1),
			...(integrity === undefined ? {} : { integrity }),
		},
	} satisfies BridgeAttachedResourceDescriptor['descriptor'];
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
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
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
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

function cancelReviewItemDemand(props: {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly item: BridgeReviewItemDescriptor | undefined;
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
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
		cancellationGroups.add(demandCancellationGroupForReviewDescriptorRef(descriptorRef));
	}
	for (const cancellationGroup of cancellationGroups) {
		cancelledCount += props.reviewDemandScheduler.cancelGroup(cancellationGroup);
		cancelledCount += props.resourceExecutor.cancelGroup(cancellationGroup);
	}
	return cancelledCount;
}

export function reviewItemDemandCancellationTargetForSelectionChange(props: {
	readonly previousSelectedItemId: string | null;
	readonly reviewPackage: BridgeReviewPackage;
}): BridgeReviewItemDescriptor | undefined {
	return props.previousSelectedItemId === null
		? undefined
		: props.reviewPackage.itemsById[props.previousSelectedItemId];
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

export function bridgeReviewPackageFromMetadataSnapshot(
	snapshotFrame: ReviewSnapshotMaterializerDelta,
): BridgeReviewPackage {
	const contentDescriptorsById = new Map(
		snapshotFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	const itemsById = Object.fromEntries(
		snapshotFrame.projectionInput.orderedItems.map(
			(item): readonly [string, BridgeReviewItemDescriptor] => [
				item.itemId,
				bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item,
					metadataFrame: snapshotFrame,
				}),
			],
		),
	);
	return bridgeReviewPackageSchema.parse({
		packageId: snapshotFrame.packageId,
		schemaVersion: 1,
		reviewGeneration: snapshotFrame.generation,
		revision: snapshotFrame.revision,
		query: {
			queryId: snapshotFrame.sourceIdentity,
			queryKind: 'compare',
			repoId: snapshotFrame.baseEndpoint.repoId,
			worktreeId: snapshotFrame.headEndpoint.worktreeId,
			baseEndpointId: snapshotFrame.baseEndpoint.endpointId,
			headEndpointId: snapshotFrame.headEndpoint.endpointId,
			comparisonSemantics: 'workingTreeDelta',
			pathScope: [],
			fileTarget: null,
			viewFilter: emptyBridgeReviewViewFilter(),
			grouping: { kind: 'flat', label: null },
			provenanceFilter: emptyBridgeReviewProvenanceFilter(),
		},
		baseEndpoint: snapshotFrame.baseEndpoint,
		headEndpoint: snapshotFrame.headEndpoint,
		orderedItemIds: snapshotFrame.projectionInput.orderedItems.map((item) => item.itemId),
		itemsById,
		groups: [],
		summary: snapshotFrame.summary,
		filterState: emptyBridgeReviewViewFilter(),
		generatedAtUnixMilliseconds: 0,
	});
}

function bridgeReviewPackageWithMetadataWindow(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly windowFrame: ReviewWindowMaterializerDelta;
}): BridgeReviewPackage {
	const contentDescriptorsById = new Map(
		props.windowFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	const windowItemsById = Object.fromEntries(
		props.windowFrame.itemMetadata.map((item): readonly [string, BridgeReviewItemDescriptor] => [
			item.itemId,
			reviewItemWithCarriedContentLineCounts({
				currentItem: props.reviewPackage.itemsById[item.itemId],
				nextItem: bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item,
					metadataFrame: {
						...props.windowFrame,
						baseEndpoint: props.reviewPackage.baseEndpoint,
						headEndpoint: props.reviewPackage.headEndpoint,
					},
				}),
			}),
		]),
	);
	const orderedItemIds = [
		...props.reviewPackage.orderedItemIds,
		...props.windowFrame.itemMetadata
			.map((item) => item.itemId)
			.filter((itemId) => props.reviewPackage.itemsById[itemId] === undefined),
	];
	return bridgeReviewPackageSchema.parse({
		...props.reviewPackage,
		orderedItemIds,
		itemsById: {
			...props.reviewPackage.itemsById,
			...windowItemsById,
		},
		summary: props.windowFrame.summary,
	});
}

function bridgeReviewPackageWithMetadataSnapshot(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly snapshotPackage: BridgeReviewPackage;
}): BridgeReviewPackage {
	const snapshotItemsById = Object.fromEntries(
		Object.entries(props.snapshotPackage.itemsById).map(
			([itemId, item]): readonly [string, BridgeReviewItemDescriptor] => [
				itemId,
				reviewItemWithCarriedContentLineCounts({
					currentItem: props.reviewPackage.itemsById[itemId],
					nextItem: item,
				}),
			],
		),
	);
	const orderedItemIds = [
		...props.reviewPackage.orderedItemIds,
		...props.snapshotPackage.orderedItemIds.filter(
			(itemId) => props.reviewPackage.itemsById[itemId] === undefined,
		),
	];
	return bridgeReviewPackageSchema.parse({
		...props.reviewPackage,
		baseEndpoint: props.snapshotPackage.baseEndpoint,
		headEndpoint: props.snapshotPackage.headEndpoint,
		revision: props.snapshotPackage.revision,
		orderedItemIds,
		itemsById: {
			...props.reviewPackage.itemsById,
			...snapshotItemsById,
		},
		summary: props.snapshotPackage.summary,
	});
}

export function applyReviewMetadataDeltaToReviewPackage(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly deltaFrame: ReviewDeltaMaterializerDelta;
}): BridgeReviewPackage | null {
	if (
		props.reviewPackage.packageId !== props.deltaFrame.packageId ||
		props.reviewPackage.revision !== props.deltaFrame.fromRevision
	) {
		return null;
	}
	const contentDescriptorsById = new Map(
		props.deltaFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	let itemsById: Record<string, BridgeReviewItemDescriptor> = {
		...props.reviewPackage.itemsById,
	};
	let orderedItemIds = [...props.reviewPackage.orderedItemIds];
	let didChange = false;
	const extentFacts = extentFactsFromMetadataDelta(props.deltaFrame);
	for (const operation of props.deltaFrame.operations) {
		switch (operation.kind) {
			case 'upsertItemMetadata': {
				const currentItem = itemsById[operation.item.itemId];
				const nextItem = bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item: operation.item,
					metadataFrame: {
						baseEndpoint: props.reviewPackage.baseEndpoint,
						extentFacts,
						generation: props.reviewPackage.reviewGeneration,
						headEndpoint: props.reviewPackage.headEndpoint,
						revision: props.deltaFrame.toRevision,
					},
				});
				itemsById = {
					...itemsById,
					[operation.item.itemId]: reviewItemWithCarriedContentLineCounts({
						currentItem,
						nextItem,
					}),
				};
				if (!orderedItemIds.includes(operation.item.itemId)) {
					orderedItemIds = [...orderedItemIds, operation.item.itemId];
				}
				didChange = true;
				break;
			}
			case 'appendItems': {
				for (const item of operation.items) {
					const currentItem = itemsById[item.itemId];
					const nextItem = bridgeReviewItemFromMetadataProjectionItem({
						contentDescriptorsById,
						item,
						metadataFrame: {
							baseEndpoint: props.reviewPackage.baseEndpoint,
							extentFacts,
							generation: props.reviewPackage.reviewGeneration,
							headEndpoint: props.reviewPackage.headEndpoint,
							revision: props.deltaFrame.toRevision,
						},
					});
					itemsById = {
						...itemsById,
						[item.itemId]: reviewItemWithCarriedContentLineCounts({
							currentItem,
							nextItem,
						}),
					};
					if (!orderedItemIds.includes(item.itemId)) {
						orderedItemIds = [...orderedItemIds, item.itemId];
					}
				}
				didChange = operation.items.length > 0 || didChange;
				break;
			}
			case 'removeItems': {
				const removedItemIds = new Set(operation.itemIds);
				if (removedItemIds.size === 0) {
					break;
				}
				itemsById = Object.fromEntries(
					Object.entries(itemsById).filter(([itemId]) => !removedItemIds.has(itemId)),
				);
				orderedItemIds = orderedItemIds.filter((itemId) => !removedItemIds.has(itemId));
				didChange = true;
				break;
			}
			case 'replaceItemOrder': {
				const seenItemIds = new Set<string>();
				orderedItemIds = [
					...operation.itemIds.filter((itemId) => {
						if (!(itemId in itemsById) || seenItemIds.has(itemId)) {
							return false;
						}
						seenItemIds.add(itemId);
						return true;
					}),
					...orderedItemIds.filter((itemId) => !seenItemIds.has(itemId)),
				];
				didChange = true;
				break;
			}
			case 'movePathPrefix': {
				itemsById = reviewItemsByIdWithMovedPathPrefix({
					affectedItemIds: operation.affectedItemIds,
					fromPath: operation.fromPath,
					itemsById,
					revision: props.deltaFrame.toRevision,
					toPath: operation.toPath,
				});
				didChange = operation.affectedItemIds.length > 0 || didChange;
				break;
			}
			case 'upsertTreeRows':
			case 'removeTreeRows':
			case 'replaceTreeWindow':
			case 'selectItem':
			case 'invalidateContentDescriptors':
				break;
			case 'upsertExtentFacts': {
				for (const fact of operation.facts) {
					const currentItem = itemsById[fact.itemId];
					if (currentItem === undefined) {
						continue;
					}
					itemsById = {
						...itemsById,
						[fact.itemId]: reviewItemWithExtentFacts({
							extentFacts,
							item: currentItem,
							revision: props.deltaFrame.toRevision,
						}),
					};
				}
				didChange = operation.facts.length > 0 || didChange;
				break;
			}
		}
	}
	if (!didChange && props.deltaFrame.toRevision === props.reviewPackage.revision) {
		return null;
	}
	return bridgeReviewPackageSchema.parse({
		...props.reviewPackage,
		revision: props.deltaFrame.toRevision,
		orderedItemIds,
		itemsById,
		summary: props.deltaFrame.summary,
	});
}

function extentFactsFromMetadataDelta(
	deltaFrame: ReviewDeltaMaterializerDelta,
): ReviewSnapshotMaterializerDelta['extentFacts'] {
	const facts: ReviewSnapshotMaterializerDelta['extentFacts'][number][] = [];
	for (const operation of deltaFrame.operations) {
		if (operation.kind === 'upsertExtentFacts') {
			facts.push(...operation.facts);
		}
	}
	return facts;
}

function reviewItemWithCarriedContentLineCounts(props: {
	readonly currentItem: BridgeReviewItemDescriptor | undefined;
	readonly nextItem: BridgeReviewItemDescriptor;
}): BridgeReviewItemDescriptor {
	if (
		props.nextItem.contentLineCountsByRole !== undefined ||
		props.currentItem?.contentLineCountsByRole === undefined
	) {
		return props.nextItem;
	}
	return {
		...props.nextItem,
		contentLineCountsByRole: props.currentItem.contentLineCountsByRole,
	};
}

function reviewItemWithExtentFacts(props: {
	readonly extentFacts: ReviewSnapshotMaterializerDelta['extentFacts'];
	readonly item: BridgeReviewItemDescriptor;
	readonly revision: number;
}): BridgeReviewItemDescriptor {
	const contentLineCountsByRole = contentLineCountsByRoleFromExtentFacts({
		extentFacts: props.extentFacts,
		itemId: props.item.itemId,
	});
	if (contentLineCountsByRole === undefined) {
		return props.item;
	}
	return {
		...props.item,
		contentLineCountsByRole,
		cacheKey: `${props.item.cacheKey}:metadata-delta:${props.revision}:extents`,
	};
}

function reviewItemsByIdWithMovedPathPrefix(props: {
	readonly affectedItemIds: readonly string[];
	readonly fromPath: string;
	readonly itemsById: Readonly<Record<string, BridgeReviewItemDescriptor>>;
	readonly revision: number;
	readonly toPath: string;
}): Record<string, BridgeReviewItemDescriptor> {
	const affectedItemIds = new Set(props.affectedItemIds);
	const nextItemsById: Record<string, BridgeReviewItemDescriptor> = { ...props.itemsById };
	for (const itemId of affectedItemIds) {
		const item = nextItemsById[itemId];
		if (item === undefined) {
			continue;
		}
		nextItemsById[itemId] = {
			...item,
			basePath: pathWithMovedPrefix({
				fromPath: props.fromPath,
				path: item.basePath,
				toPath: props.toPath,
			}),
			headPath: pathWithMovedPrefix({
				fromPath: props.fromPath,
				path: item.headPath,
				toPath: props.toPath,
			}),
			cacheKey: `${item.cacheKey}:metadata-delta:${props.revision}`,
		};
	}
	return nextItemsById;
}

function pathWithMovedPrefix(props: {
	readonly fromPath: string;
	readonly path: string | null | undefined;
	readonly toPath: string;
}): string | null {
	if (props.path === null || props.path === undefined) {
		return null;
	}
	if (props.path === props.fromPath) {
		return props.toPath;
	}
	const prefix = `${props.fromPath}/`;
	return props.path.startsWith(prefix)
		? `${props.toPath}/${props.path.slice(prefix.length)}`
		: props.path;
}

function bridgeReviewItemFromMetadataProjectionItem(props: {
	readonly contentDescriptorsById: ReadonlyMap<string, BridgeAttachedResourceDescriptor>;
	readonly item: ReviewSnapshotMaterializerDelta['projectionInput']['orderedItems'][number];
	readonly metadataFrame: Pick<
		ReviewSnapshotMaterializerDelta,
		'baseEndpoint' | 'generation' | 'headEndpoint' | 'revision' | 'extentFacts'
	>;
}): BridgeReviewItemDescriptor {
	const contentLineCountsByRole = contentLineCountsByRoleFromExtentFacts({
		extentFacts: props.metadataFrame.extentFacts,
		itemId: props.item.itemId,
	});
	return {
		itemId: props.item.itemId,
		itemKind:
			props.item.contentRoles.includes('diff') || props.item.contentRoles.includes('base')
				? 'diff'
				: 'file',
		itemVersion: 1,
		basePath: props.item.basePath,
		headPath: props.item.headPath,
		changeKind: props.item.changeKind,
		fileClass: props.item.fileClass,
		language: props.item.language,
		extension: props.item.extension,
		sizeBytes: 0,
		baseContentHash: null,
		headContentHash: null,
		contentHashAlgorithm: 'metadata-stream',
		additions: 0,
		deletions: 0,
		isHiddenByDefault: props.item.isHiddenByDefault,
		hiddenReason: null,
		reviewPriority: props.item.reviewPriority,
		contentRoles: {
			base: metadataContentHandleForRole({ ...props, role: 'base' }),
			head: metadataContentHandleForRole({ ...props, role: 'head' }),
			diff: metadataContentHandleForRole({ ...props, role: 'diff' }),
			file: metadataContentHandleForRole({ ...props, role: 'file' }),
		},
		contentLineCountsByRole,
		cacheKey: `metadata:${props.item.itemId}:${props.metadataFrame.revision}`,
		provenance: {
			paneIds: [],
			agentSessionIds: [...props.item.provenance.agentSessionIds],
			promptIds: [...props.item.provenance.promptIds],
			operationIds: [...props.item.provenance.operationIds],
			sourceKinds: [],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: props.item.reviewState,
		collapsed: false,
	};
}

function contentLineCountsByRoleFromExtentFacts(props: {
	readonly extentFacts: ReviewSnapshotMaterializerDelta['extentFacts'];
	readonly itemId: string;
}): BridgeReviewItemDescriptor['contentLineCountsByRole'] {
	const lineCountsByRole: NonNullable<BridgeReviewItemDescriptor['contentLineCountsByRole']> = {};
	for (const fact of props.extentFacts) {
		if (fact.itemId !== props.itemId) {
			continue;
		}
		lineCountsByRole[fact.contentRole] = fact.lineCount;
	}
	return Object.keys(lineCountsByRole).length === 0 ? undefined : lineCountsByRole;
}

function metadataContentHandleForRole(props: {
	readonly contentDescriptorsById: ReadonlyMap<string, BridgeAttachedResourceDescriptor>;
	readonly item: ReviewSnapshotMaterializerDelta['projectionInput']['orderedItems'][number];
	readonly metadataFrame: Pick<
		ReviewSnapshotMaterializerDelta,
		'baseEndpoint' | 'generation' | 'headEndpoint' | 'revision'
	>;
	readonly role: BridgeContentRole;
}): BridgeContentHandle | null {
	const descriptorId = props.item.contentDescriptorIdsByRole?.[props.role] ?? null;
	const attachedDescriptor =
		descriptorId === null ? null : (props.contentDescriptorsById.get(descriptorId) ?? null);
	if (attachedDescriptor === null) {
		return null;
	}
	const descriptor = attachedDescriptor.descriptor;
	const integrity = descriptor.content.integrity;
	const contentHash =
		integrity?.kind === 'wholeHash'
			? `${integrity.algorithm}:${integrity.value}`
			: `metadata:${descriptor.descriptorId}`;
	return {
		handleId: descriptor.descriptorId,
		itemId: props.item.itemId,
		role: props.role,
		endpointId:
			props.role === 'base'
				? props.metadataFrame.baseEndpoint.endpointId
				: props.metadataFrame.headEndpoint.endpointId,
		reviewGeneration: descriptor.identity.generation ?? props.metadataFrame.generation,
		resourceUrl: descriptor.resourceUrl,
		contentHash,
		contentHashAlgorithm: integrity?.kind === 'wholeHash' ? integrity.algorithm : 'metadata-stream',
		cacheKey: `metadata:${props.item.itemId}:${props.role}:${props.metadataFrame.revision}`,
		mimeType: descriptor.content.mediaType,
		language: props.item.language,
		sizeBytes: descriptor.content.expectedBytes ?? 0,
		isBinary: descriptor.content.encoding === 'binary',
	};
}

function emptyBridgeReviewViewFilter(): BridgeReviewPackage['filterState'] {
	return {
		includedPathGlobs: [],
		excludedPathGlobs: [],
		includedFileClasses: [],
		excludedFileClasses: [],
		includedExtensions: [],
		excludedExtensions: [],
		changeKinds: [],
		reviewStates: [],
		showHiddenFiles: false,
		showBinaryFiles: false,
		showLargeFiles: false,
	};
}

function emptyBridgeReviewProvenanceFilter(): BridgeReviewPackage['query']['provenanceFilter'] {
	return {
		paneIds: [],
		agentSessionIds: [],
		promptIds: [],
		operationIds: [],
		createdAfterUnixMilliseconds: null,
		createdBeforeUnixMilliseconds: null,
		sourceKinds: [],
	};
}

function reviewSnapshotFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return (
		props.frame.comparison.packageId.length > 0 &&
		props.frame.comparison.sourceIdentity.length > 0 &&
		props.frame.comparison.generation === props.frame.generation
	);
}

function reviewDeltaFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataDeltaFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return (
		props.frame.packageId.length > 0 &&
		props.frame.fromRevision <= props.frame.toRevision &&
		props.frame.generation >= 0
	);
}

function reviewWindowFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataWindowFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return props.frame.packageId.length > 0 && props.frame.generation >= 0;
}

function readBridgeReviewFrameAuthority(): BridgeReviewFrameAuthority | null {
	const paneId = document.documentElement.getAttribute(bridgeReviewPaneIdAttribute);
	const streamId = document.documentElement.getAttribute(bridgeReviewStreamIdAttribute);
	return paneId === null || streamId === null || paneId.length === 0 || streamId.length === 0
		? null
		: { paneId, streamId };
}

function refreshBridgeReviewFrameAuthority(authorityRef: {
	current: BridgeReviewFrameAuthority | null;
}): BridgeReviewFrameAuthority | null {
	if (authorityRef.current !== null) {
		return authorityRef.current;
	}
	const nextAuthority = readBridgeReviewFrameAuthority();
	if (nextAuthority !== null) {
		authorityRef.current = nextAuthority;
	}
	return authorityRef.current;
}

function createBridgeReviewIntakeReceiver(props: {
	readonly getAuthority: () => BridgeReviewFrameAuthority | null;
	readonly onError: (frame: Extract<BridgeIntakeFrame, { readonly kind: 'error' }>) => void;
	readonly onFrame: (frame: ReviewProtocolFrame, traceContext: BridgeTraceContext | null) => void;
}): BridgeIntakeReceiver {
	let status: BridgeIntakeReceiverState['status'] = 'active';
	let currentGeneration = 0;
	let nextSequence = 0;
	return {
		get state(): BridgeIntakeReceiverState {
			const authority = props.getAuthority();
			return {
				status,
				streamId: authority?.streamId ?? 'review-unbound',
				generation: currentGeneration,
				nextSequence,
			};
		},
		receive(frame: BridgeIntakeFrame): BridgeIntakeReceiveResult {
			if (status === 'closed') {
				return { ok: false, reason: 'closed', status };
			}
			const authority = props.getAuthority();
			if (authority === null || frame.streamId !== authority.streamId) {
				return { ok: false, reason: 'stream_mismatch', status };
			}
			if (currentGeneration === 0) {
				currentGeneration = frame.generation;
				nextSequence = frame.sequence;
			}
			if (frame.kind === 'reset' && frame.generation > currentGeneration) {
				currentGeneration = frame.generation;
				nextSequence = frame.sequence + 1;
				const protocolFrame = reviewProtocolFrameFromIntakeFrame(frame);
				if (
					protocolFrame === null ||
					!reviewIntakeFrameMatchesProtocolFrame(frame, protocolFrame) ||
					!reviewProtocolFrameMatchesAuthority(protocolFrame, authority)
				) {
					return { ok: false, reason: 'generation_mismatch', status };
				}
				props.onFrame(protocolFrame, frame.__traceContext ?? null);
				return { ok: true, status };
			}
			if (status === 'resetRequired') {
				return { ok: false, reason: 'reset_required', status };
			}
			if (frame.generation !== currentGeneration) {
				return { ok: false, reason: 'generation_mismatch', status };
			}
			if (frame.sequence < nextSequence) {
				return {
					ok: false,
					reason: frame.sequence === nextSequence - 1 ? 'duplicate_sequence' : 'stale_sequence',
					status,
				};
			}
			if (frame.sequence > nextSequence) {
				status = 'resetRequired';
				return { ok: false, reason: 'sequence_gap', status };
			}
			nextSequence += 1;
			if (frame.kind === 'error') {
				props.onError(frame);
				return { ok: true, status };
			}
			if (frame.kind === 'close') {
				status = 'closed';
				return { ok: true, status };
			}
			const protocolFrame = reviewProtocolFrameFromIntakeFrame(frame);
			if (protocolFrame === null || !reviewIntakeFrameMatchesProtocolFrame(frame, protocolFrame)) {
				return { ok: false, reason: 'generation_mismatch', status };
			}
			if (!reviewProtocolFrameMatchesAuthority(protocolFrame, authority)) {
				return { ok: false, reason: 'stream_mismatch', status };
			}
			props.onFrame(protocolFrame, frame.__traceContext ?? null);
			return { ok: true, status };
		},
		close(): void {
			status = 'closed';
		},
	};
}

function reviewProtocolFrameFromIntakeFrame(frame: BridgeIntakeFrame): ReviewProtocolFrame | null {
	if (!('payload' in frame)) {
		return null;
	}
	const parsedFrame = reviewProtocolFrameSchema.safeParse(frame.payload);
	return parsedFrame.success ? parsedFrame.data : null;
}

function reviewIntakeFrameMatchesProtocolFrame(
	frame: BridgeIntakeFrame,
	protocolFrame: ReviewProtocolFrame,
): boolean {
	const expectedIntakeKind =
		protocolFrame.frameKind === 'review.metadataSnapshot'
			? 'snapshot'
			: protocolFrame.frameKind === 'review.metadataDelta' ||
				  protocolFrame.frameKind === 'review.metadataWindow'
				? 'delta'
				: protocolFrame.frameKind === 'review.invalidate'
					? 'invalidate'
					: 'reset';
	return (
		frame.kind === expectedIntakeKind &&
		frame.streamId === protocolFrame.streamId &&
		frame.generation === protocolFrame.generation &&
		frame.sequence === protocolFrame.sequence
	);
}

function reviewProtocolFrameMatchesAuthority(
	frame: ReviewProtocolFrame,
	authority: BridgeReviewFrameAuthority,
): boolean {
	return frame.streamId === authority.streamId;
}

function firstVisibleItemId(reviewPackage: BridgeReviewPackage): string | null {
	const registry = createBridgeReviewItemRegistry({ reviewPackage, selectedItemId: null });
	return registry.visibleItems[0]?.itemId ?? null;
}

function uniqueReviewVisibleItemIds(itemIds: readonly string[]): readonly string[] {
	const uniqueItemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const itemId of itemIds) {
		if (seenItemIds.has(itemId)) {
			continue;
		}
		seenItemIds.add(itemId);
		uniqueItemIds.push(itemId);
	}
	return uniqueItemIds;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
