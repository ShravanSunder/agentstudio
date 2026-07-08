import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import {
	createBridgeRPCClient,
	type BridgeActiveViewerSource,
} from '../bridge/bridge-rpc-client.js';
import { createBridgeTelemetryEventSink } from '../bridge/bridge-telemetry-event-sink.js';
import { createBridgeCommWorkerTelemetryClient } from '../core/comm-worker/bridge-comm-worker-telemetry.js';
import type { BridgeFileViewerAppProps } from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeTelemetryBootstrapConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import {
	createBridgeTelemetryRecorder,
	createBridgeTelemetryRecorderFromClient,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { setBridgeViewerNativeOpenAnchor } from '../foundation/telemetry/bridge-viewer-first-interaction.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-client.js';
import type { BridgeAppControlProbe } from './bridge-app-control.js';
import { BridgeFileViewerMode } from './bridge-app-file-viewer-mode.js';
import type { CreateBridgeReviewRuntimeProtocolDispatcherProps } from './bridge-app-review-render-snapshot-controller.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';
export { bridgeReviewNavigationCommandForWorktreeDescriptor } from './bridge-review-navigation.js';
export {
	reviewItemDemandCancellationTargetForSelectionChange,
	reviewSnapshotDescriptorRefsByHandleIdForPackage,
	reviewSnapshotFrameDescriptorsMatchPackage,
} from './bridge-app-review-descriptors.js';
export type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
export {
	applyReviewMetadataDeltaToReviewPackage,
	pruneEmptyReviewTreeDirectories,
	reviewTreeRowsWithMetadataDelta,
} from './bridge-app-review-metadata-package.js';
export type { BridgeReviewContentDemandByteBudget } from './bridge-app-review-runtime.js';
export {
	bridgeReviewContentDemandByteBudget,
	contentDemandResourceUrl,
} from './bridge-app-review-runtime.js';
export {
	selectedCanvasLoadingReasonForCurrentSelection,
	selectedContentUnavailablePathForCurrentSelection,
	reviewFileTargetForReviewPackagePath,
} from './bridge-app-review-selection-state.js';
import {
	bridgeViewerActivationPrewarm,
	type BridgeViewerActivationPrewarmState,
} from './bridge-viewer-activation-prewarm.js';
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
	readonly reviewWorkerTransportFactory?: CreateBridgeReviewRuntimeProtocolDispatcherProps['transportFactory'];
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

interface BridgeActiveViewerState {
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly viewerMode: 'file' | 'review';
}

type BridgeViewerMode = BridgeActiveViewerState['viewerMode'];

type BridgeRememberedNavigationCommands = Record<
	BridgeViewerMode,
	BridgeViewerNavigationCommand | undefined
>;

type BridgeActiveViewerSources = Record<BridgeViewerMode, BridgeActiveViewerSource | null>;

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
	const activationPrewarmStateRef = useRef<BridgeViewerActivationPrewarmState>({
		prewarmedModes: new Set(),
	});
	const activeViewerModeSessionIdRef = useRef<string>(createBridgeActiveViewerModeSessionId());
	const activeViewerModeSequenceRef = useRef(0);
	const activeViewerModeRef = useRef<BridgeViewerMode>(activeViewerState.viewerMode);
	const previousActiveViewerModeRef = useRef<BridgeViewerMode>(activeViewerState.viewerMode);
	const activeViewerModeActivationRevisionRef = useRef(0);
	const lastSentActiveViewerModeSignalKeyRef = useRef<string | null>(null);
	const activeViewerModeSourceSentActivationRevisionsRef = useRef<Set<number>>(new Set());
	const [activeViewerSources, setActiveViewerSources] = useState<BridgeActiveViewerSources>({
		file: null,
		review: null,
	});
	const activeViewerSourcesRef = useRef<BridgeActiveViewerSources>(activeViewerSources);
	const [activeViewerSourceSignalRevision, setActiveViewerSourceSignalRevision] = useState(0);
	const activeViewerModeRetryAttemptsBySignalKeyRef = useRef<Map<string, number>>(new Map());
	const [activeViewerModeRetryRevision, setActiveViewerModeRetryRevision] = useState(0);
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
	const [telemetryConfig, setTelemetryConfig] = useState<BridgeTelemetryBootstrapConfig | null>(
		null,
	);
	const isBridgeReadyGateOpenRef = useRef(false);
	const isBridgeReadyRef = useRef(false);
	const bridgeReadyCallbacksRef = useRef<Set<() => void>>(new Set());
	const registerBridgeReadyCallback = useCallback((callback: () => void): (() => void) => {
		bridgeReadyCallbacksRef.current.add(callback);
		if (isBridgeReadyGateOpenRef.current) {
			queueMicrotask(callback);
		}
		return (): void => {
			bridgeReadyCallbacksRef.current.delete(callback);
		};
	}, []);
	useEffect((): (() => void) => {
		const configureTelemetryRecorder = (
			nextTelemetryConfig = handshakeSessionRef.current?.getTelemetryConfig() ?? null,
		): void => {
			if (nextTelemetryConfig === null) {
				telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
			} else {
				const telemetryClient = createBridgeCommWorkerTelemetryClient({
					config: nextTelemetryConfig,
					streamId: 'page',
					sink: createBridgeTelemetryEventSink({
						endpointUrl: nextTelemetryConfig.endpointUrl,
					}),
				});
				telemetryRecorderRef.current = createBridgeTelemetryRecorderFromClient(
					nextTelemetryConfig,
					telemetryClient,
				);
			}
			setTelemetryConfig(nextTelemetryConfig);
			setBridgeViewerNativeOpenAnchor({
				openEpochUnixMillis: nextTelemetryConfig?.viewerOpenEpochUnixMillis ?? null,
				traceparent: nextTelemetryConfig?.viewerOpenTraceparent ?? null,
			});
		};
		handshakeSessionRef.current = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				isBridgeReadyRef.current = true;
				isBridgeReadyGateOpenRef.current = true;
				queueMicrotask((): void => {
					if (!isBridgeReadyRef.current) {
						return;
					}
					for (const callback of bridgeReadyCallbacksRef.current) {
						callback();
					}
				});
			},
			onReadyError: (): void => {
				isBridgeReadyRef.current = false;
				isBridgeReadyGateOpenRef.current = false;
			},
			onTelemetryConfig: configureTelemetryRecorder,
		});
		configureTelemetryRecorder();
		return (): void => {
			handshakeSessionRef.current?.uninstall();
			handshakeSessionRef.current = null;
			isBridgeReadyRef.current = false;
			isBridgeReadyGateOpenRef.current = false;
			setTelemetryConfig(null);
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
		};
	}, [target]);
	const activeViewerModeRPCClient = useMemo(() => createBridgeRPCClient({ target }), [target]);
	activeViewerModeRef.current = activeViewerState.viewerMode;
	activeViewerSourcesRef.current = activeViewerSources;
	const sendActiveViewerModeUpdate = useCallback((): void => {
		const activeViewerMode = activeViewerModeRef.current;
		const activeSource = activeViewerSourcesRef.current[activeViewerMode];
		const activationRevision = activeViewerModeActivationRevisionRef.current;
		if (activeSource === null) {
			if (
				activationRevision === 0 ||
				activeViewerModeSourceSentActivationRevisionsRef.current.has(activationRevision)
			) {
				return;
			}
			const pendingSignalKey = `${activationRevision}:${activeViewerMode}:pending-source`;
			if (lastSentActiveViewerModeSignalKeyRef.current === pendingSignalKey) {
				return;
			}
			lastSentActiveViewerModeSignalKeyRef.current = pendingSignalKey;
			activeViewerModeSequenceRef.current += 1;
			void activeViewerModeRPCClient
				.sendCommandAndWait({
					method: 'bridge.activeViewerMode.update',
					params: {
						sessionId: activeViewerModeSessionIdRef.current,
						sequence: activeViewerModeSequenceRef.current,
						mode: activeViewerMode,
						activeSource: null,
					},
				})
				.then((didSend): void => {
					if (!didSend && lastSentActiveViewerModeSignalKeyRef.current === pendingSignalKey) {
						lastSentActiveViewerModeSignalKeyRef.current = null;
						if (
							activeViewerModeRetryAttemptAvailable({
								retryAttemptsBySignalKey: activeViewerModeRetryAttemptsBySignalKeyRef.current,
								signalKey: pendingSignalKey,
							})
						) {
							setActiveViewerModeRetryRevision(
								(currentRetryRevision): number => currentRetryRevision + 1,
							);
						}
					}
				});
			return;
		}
		const signalKey = `${activationRevision}:${activeViewerMode}:${activeSource.protocol}:${activeSource.streamId}:${activeSource.generation}`;
		if (lastSentActiveViewerModeSignalKeyRef.current === signalKey) {
			return;
		}
		lastSentActiveViewerModeSignalKeyRef.current = signalKey;
		activeViewerModeSourceSentActivationRevisionsRef.current.add(activationRevision);
		activeViewerModeSequenceRef.current += 1;
		void activeViewerModeRPCClient
			.sendCommandAndWait({
				method: 'bridge.activeViewerMode.update',
				params: {
					sessionId: activeViewerModeSessionIdRef.current,
					sequence: activeViewerModeSequenceRef.current,
					mode: activeViewerMode,
					activeSource,
				},
			})
			.then((didSend): void => {
				if (didSend) {
					activeViewerModeRetryAttemptsBySignalKeyRef.current.delete(signalKey);
					return;
				}
				if (lastSentActiveViewerModeSignalKeyRef.current !== signalKey) {
					return;
				}
				lastSentActiveViewerModeSignalKeyRef.current = null;
				activeViewerModeSourceSentActivationRevisionsRef.current.delete(activationRevision);
				if (
					activeViewerModeRetryAttemptAvailable({
						retryAttemptsBySignalKey: activeViewerModeRetryAttemptsBySignalKeyRef.current,
						signalKey,
					})
				) {
					setActiveViewerModeRetryRevision(
						(currentRetryRevision): number => currentRetryRevision + 1,
					);
				}
			});
	}, [activeViewerModeRPCClient]);
	useLayoutEffect((): void => {
		if (previousActiveViewerModeRef.current === activeViewerState.viewerMode) {
			return;
		}
		activeViewerModeActivationRevisionRef.current += 1;
		previousActiveViewerModeRef.current = activeViewerState.viewerMode;
	}, [activeViewerState.viewerMode]);
	const reportFileActiveSource = useCallback(
		(activeSource: BridgeActiveViewerSource | null): void => {
			setActiveViewerSources((currentSources): BridgeActiveViewerSources => {
				if (bridgeActiveViewerSourcesEqual(currentSources.file, activeSource)) {
					return currentSources;
				}
				return { ...currentSources, file: activeSource };
			});
			if (activeSource !== null) {
				setActiveViewerSourceSignalRevision((revision) => revision + 1);
			}
		},
		[],
	);
	const reportReviewActiveSource = useCallback(
		(activeSource: BridgeActiveViewerSource | null): void => {
			setActiveViewerSources((currentSources): BridgeActiveViewerSources => {
				if (bridgeActiveViewerSourcesEqual(currentSources.review, activeSource)) {
					return currentSources;
				}
				return { ...currentSources, review: activeSource };
			});
			if (activeSource !== null) {
				setActiveViewerSourceSignalRevision((revision) => revision + 1);
			}
		},
		[],
	);
	useLayoutEffect((): (() => void) => {
		if (isBridgeReadyGateOpenRef.current) {
			sendActiveViewerModeUpdate();
			return (): void => {};
		}
		return registerBridgeReadyCallback(sendActiveViewerModeUpdate);
	}, [
		activeViewerSources,
		activeViewerSourceSignalRevision,
		activeViewerState.viewerMode,
		activeViewerModeRetryRevision,
		registerBridgeReadyCallback,
		sendActiveViewerModeUpdate,
	]);
	const [mountedViewerModes, setMountedViewerModes] = useState<ReadonlySet<BridgeViewerMode>>(
		() => new Set<BridgeViewerMode>(['file', 'review']),
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
	useEffect((): void => {
		bridgeViewerActivationPrewarm({
			activeViewerMode: activeViewerState.viewerMode,
			state: activationPrewarmStateRef.current,
		});
	}, [activeViewerState.viewerMode]);
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
						onActiveSourceChange={reportFileActiveSource}
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
						onActiveSourceChange={reportReviewActiveSource}
						registerBridgeReadyCallback={registerBridgeReadyCallback}
						telemetryConfig={telemetryConfig}
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

function bridgeActiveViewerSourcesEqual(
	left: BridgeActiveViewerSource | null,
	right: BridgeActiveViewerSource | null,
): boolean {
	return (
		left?.protocol === right?.protocol &&
		left?.streamId === right?.streamId &&
		left?.generation === right?.generation
	);
}

function createBridgeActiveViewerModeSessionId(): string {
	return `active-viewer-${crypto.randomUUID()}`;
}

function activeViewerModeRetryAttemptAvailable(props: {
	readonly retryAttemptsBySignalKey: Map<string, number>;
	readonly signalKey: string;
}): boolean {
	const currentAttemptCount = props.retryAttemptsBySignalKey.get(props.signalKey) ?? 0;
	if (currentAttemptCount >= 3) {
		return false;
	}
	props.retryAttemptsBySignalKey.set(props.signalKey, currentAttemptCount + 1);
	return true;
}
