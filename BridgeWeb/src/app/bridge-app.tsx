import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import { encodeBridgeWorkerActiveViewerModeUpdateCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import {
	createBridgePaneRuntime,
	type BridgePaneRuntime,
	type BridgePaneSurfaceClient,
} from '../core/comm-worker/bridge-pane-runtime.js';
import {
	type BridgeActiveViewerModeUpdate,
	type BridgeActiveViewerSource,
} from '../core/comm-worker/bridge-product-control-contracts.js';
import type {
	BridgeWorkerHealthEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { createBridgePaneTelemetryWorkerFactory } from '../core/telemetry-worker/bridge-pane-telemetry-worker-factory.js';
import {
	createBridgePaneTelemetryWorkerSession,
	type BridgePaneTelemetryWorkerSession,
	type BridgeTelemetryWorkerLike,
} from '../core/telemetry-worker/bridge-pane-telemetry-worker-session.js';
import { bridgeTelemetryWorkerBootstrapSchema } from '../core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import { bridgeTelemetryCompactSampleForEvent } from '../core/telemetry-worker/bridge-telemetry-worker-event-adapter.js';
import type { BridgeFileViewerAppProps } from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import {
	createBridgeTelemetryRecorder,
	createBridgeTelemetryRecorderFromClient,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { setBridgeViewerNativeOpenAnchor } from '../foundation/telemetry/bridge-viewer-first-interaction.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import type { BridgeAppControlProbe } from './bridge-app-control.js';
import { BridgeFileViewerMode } from './bridge-app-file-viewer-mode.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';
export type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
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
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly paneRuntimeFactory?: () => BridgePaneRuntime;
	readonly telemetryWorkerFactory?: () => Promise<BridgeTelemetryWorkerLike>;
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

type BridgeNativeSurfaceSelectionRequest = Extract<
	BridgeWorkerServerToMainMessage,
	{ readonly kind: 'nativeSurfaceSelectionRequest' }
>;

interface BridgePendingNativeSurfaceSelection {
	readonly arrivalRevision: number;
	readonly request: BridgeNativeSurfaceSelectionRequest;
}

type BridgeRememberedNavigationCommands = Record<
	BridgeViewerMode,
	BridgeViewerNavigationCommand | undefined
>;

type BridgeActiveViewerSources = Record<BridgeViewerMode, BridgeActiveViewerSource | null>;

interface BridgePaneRuntimeHost {
	readonly fileViewClient: BridgePaneSurfaceClient;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly runtime: BridgePaneRuntime;
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

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const paneRuntimeHostRef = useRef<BridgePaneRuntimeHost | null>(null);
	paneRuntimeHostRef.current ??= createBridgePaneRuntimeHost(
		props.paneRuntimeFactory ?? createDefaultBridgePaneRuntime,
	);
	const paneRuntimeHost = paneRuntimeHostRef.current;
	const incomingNavigationCommand = props.navigationCommand;
	const incomingViewerMode = props.viewerMode;
	const [activeViewerState, setActiveViewerState] = useState<BridgeActiveViewerState>(() =>
		activeViewerStateForBridgeInputs({
			navigationCommand: incomingNavigationCommand,
			viewerMode: incomingViewerMode,
		}),
	);
	const [mountedViewerModes, setMountedViewerModes] = useState<ReadonlySet<BridgeViewerMode>>(
		() => new Set<BridgeViewerMode>(['file', 'review']),
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
	const nativeSurfaceSelectionArrivalRevisionRef = useRef(0);
	const [nativeSurfaceSelectionSignalRevision, setNativeSurfaceSelectionSignalRevision] =
		useState(0);
	const latestNativeSurfaceSelectionIdentityRef = useRef<{
		readonly nativeSelectionRequestId: string;
		readonly selectionRevision: number;
	} | null>(null);
	const pendingNativeSurfaceSelectionRef = useRef<BridgePendingNativeSurfaceSelection | null>(null);
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const telemetryWorkerSessionRef = useRef<BridgePaneTelemetryWorkerSession | null>(null);
	const telemetryWorkerFactoryRef = useRef(
		props.telemetryWorkerFactory ?? createBridgePaneTelemetryWorkerFactory(),
	);
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
	const isBridgeReadyGateOpenRef = useRef(false);
	const isBridgeReadyRef = useRef(false);
	const bridgeReadyCallbacksRef = useRef<Set<() => void>>(new Set());
	const activeViewerModeWorkerEpochRef = useRef(0);
	const activeViewerModeRequestResolversRef = useRef<Map<string, (didSend: boolean) => void>>(
		new Map(),
	);
	const activeViewerModeSettledResultsRef = useRef<Map<string, boolean>>(new Map());
	const registerBridgeReadyCallback = useCallback((callback: () => void): (() => void) => {
		bridgeReadyCallbacksRef.current.add(callback);
		if (isBridgeReadyGateOpenRef.current) {
			queueMicrotask(callback);
		}
		return (): void => {
			bridgeReadyCallbacksRef.current.delete(callback);
		};
	}, []);
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
	const applyNativeSurfaceSelectionRequest = useCallback(
		(request: BridgeNativeSurfaceSelectionRequest): void => {
			const latestIdentity = latestNativeSurfaceSelectionIdentityRef.current;
			if (
				latestIdentity !== null &&
				(request.selectionRevision < latestIdentity.selectionRevision ||
					(request.selectionRevision === latestIdentity.selectionRevision &&
						request.nativeSelectionRequestId !== latestIdentity.nativeSelectionRequestId))
			) {
				return;
			}
			nativeSurfaceSelectionArrivalRevisionRef.current += 1;
			const arrivalRevision = nativeSurfaceSelectionArrivalRevisionRef.current;
			latestNativeSurfaceSelectionIdentityRef.current = {
				nativeSelectionRequestId: request.nativeSelectionRequestId,
				selectionRevision: request.selectionRevision,
			};
			pendingNativeSurfaceSelectionRef.current = { arrivalRevision, request };
			activateViewerMode(request.surface);
			setNativeSurfaceSelectionSignalRevision(arrivalRevision);
		},
		[activateViewerMode],
	);
	useEffect((): (() => void) => {
		let telemetryConfigurationSequence = 0;
		let isEffectInstalled = true;
		const requestReplacementNativeBootstrap = (): void => {
			const telemetryWorkerSession = telemetryWorkerSessionRef.current;
			if (telemetryWorkerSession?.status() === 'active') {
				try {
					paneRuntimeHost.runtime.installTelemetryProducer({
						enabledScopes: [
							...(handshakeSessionRef.current?.getTelemetryConfig()?.enabledScopes ?? []),
						],
						preReadyRequiredSampleCapacity: telemetryWorkerSession.producerPreReadyBufferMaxSamples,
						preReadyRequiredSampleMaxEncodedBytes:
							telemetryWorkerSession.producerPreReadyBufferMaxBytes,
						producerPort: telemetryWorkerSession.replaceCommProducerPort(),
					});
				} catch {
					handshakeSessionRef.current?.requestTelemetrySessionReplacement();
				}
			}
			handshakeSessionRef.current?.requestProductSessionReplacement();
		};
		const drainTelemetrySession = async (
			session: BridgePaneTelemetryWorkerSession,
		): Promise<void> => {
			try {
				await session.drainAndClose();
			} catch {
				session.dispose();
			}
		};
		const telemetryControlGlobal = globalThis as typeof globalThis & {
			__bridgeTelemetrySidecarControl?: {
				readonly snapshot: () => Promise<unknown>;
				readonly drain: () => Promise<unknown>;
				readonly drainAndClose: () => Promise<unknown>;
			};
		};
		const unavailableTelemetryReport = (): Readonly<Record<string, string>> => ({
			kind: 'unavailable',
			reason: telemetryWorkerSessionRef.current === null ? 'disabled' : 'failed',
		});
		telemetryControlGlobal.__bridgeTelemetrySidecarControl = {
			snapshot: async (): Promise<unknown> => {
				const session = telemetryWorkerSessionRef.current;
				if (session === null || session.status() === 'failed') {
					return unavailableTelemetryReport();
				}
				return {
					kind: 'report',
					telemetrySessionId: session.telemetrySessionId,
					sidecar: await session.snapshot(),
				};
			},
			drain: async (): Promise<unknown> => {
				const session = telemetryWorkerSessionRef.current;
				if (session === null || session.status() === 'failed') {
					return unavailableTelemetryReport();
				}
				const sidecar = await session.drain();
				return {
					kind: 'report',
					telemetrySessionId: session.telemetrySessionId,
					sidecar,
				};
			},
			drainAndClose: async (): Promise<unknown> => {
				const session = telemetryWorkerSessionRef.current;
				if (session === null || session.status() === 'failed') {
					return unavailableTelemetryReport();
				}
				const sidecar = await session.drainAndClose();
				return {
					kind: 'report',
					telemetrySessionId: session.telemetrySessionId,
					sidecar,
				};
			},
		};
		const configureTelemetryRecorder = (
			nextTelemetryConfig = handshakeSessionRef.current?.getTelemetryConfig() ?? null,
		): void => {
			telemetryConfigurationSequence += 1;
			const configurationSequence = telemetryConfigurationSequence;
			const retiringSession = telemetryWorkerSessionRef.current;
			telemetryWorkerSessionRef.current = null;
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
			if (retiringSession !== null) {
				void drainTelemetrySession(retiringSession);
			}
			setBridgeViewerNativeOpenAnchor({
				openEpochUnixMillis: nextTelemetryConfig?.viewerOpenEpochUnixMillis ?? null,
				traceparent: nextTelemetryConfig?.viewerOpenTraceparent ?? null,
			});
			const decodedWorkerBootstrap = bridgeTelemetryWorkerBootstrapSchema.safeParse(
				nextTelemetryConfig?.workerBootstrap,
			);
			if (!decodedWorkerBootstrap.success || nextTelemetryConfig === null) {
				return;
			}
			void telemetryWorkerFactoryRef
				.current()
				.then((worker): void => {
					if (!isEffectInstalled || configurationSequence !== telemetryConfigurationSequence) {
						worker.terminate();
						return;
					}
					const telemetryWorkerSession = createBridgePaneTelemetryWorkerSession({
						bootstrap: decodedWorkerBootstrap.data,
						createWorker: () => worker,
					});
					if (telemetryWorkerSession === null) {
						worker.terminate();
						return;
					}
					telemetryWorkerSessionRef.current = telemetryWorkerSession;
					paneRuntimeHost.runtime.installTelemetryProducer({
						enabledScopes: [...nextTelemetryConfig.enabledScopes],
						preReadyRequiredSampleCapacity:
							decodedWorkerBootstrap.data.policy.producerPreReadyBufferMaxSamples,
						preReadyRequiredSampleMaxEncodedBytes:
							decodedWorkerBootstrap.data.policy.producerPreReadyBufferMaxBytes,
						producerPort: telemetryWorkerSession.commProducerPort,
					});
					telemetryRecorderRef.current = createBridgeTelemetryRecorderFromClient(
						nextTelemetryConfig,
						{
							record: (sample): void => {
								telemetryWorkerSession.mainProducer.record(
									bridgeTelemetryCompactSampleForEvent(
										sample,
										performance.timeOrigin + performance.now(),
									),
								);
							},
							flush: (): boolean => telemetryWorkerSession.mainProducer.flushLossSummary(),
						},
					);
				})
				.catch((): void => {
					telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
				});
		};
		handshakeSessionRef.current = installBridgePageHandshakeSession(target, {
			onProductSessionBootstrap: (productSessionBootstrap): void => {
				paneRuntimeHost.runtime.setNativeBootstrapRequester(requestReplacementNativeBootstrap);
				paneRuntimeHost.runtime.installNativeBootstrap(productSessionBootstrap);
			},
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
			onTelemetrySessionBootstrap: (result): void => {
				const currentConfig = handshakeSessionRef.current?.getTelemetryConfig() ?? null;
				if (currentConfig === null) {
					return;
				}
				if (result.kind === 'available') {
					configureTelemetryRecorder({
						...currentConfig,
						workerBootstrap: result.workerBootstrap,
					});
					return;
				}
				const { workerBootstrap: _discardedWorkerBootstrap, ...configWithoutAuthority } =
					currentConfig;
				configureTelemetryRecorder(configWithoutAuthority);
			},
		});
		configureTelemetryRecorder();
		return (): void => {
			delete telemetryControlGlobal.__bridgeTelemetrySidecarControl;
			isEffectInstalled = false;
			telemetryConfigurationSequence += 1;
			handshakeSessionRef.current?.uninstall();
			handshakeSessionRef.current = null;
			isBridgeReadyRef.current = false;
			isBridgeReadyGateOpenRef.current = false;
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(null);
			const telemetryWorkerSession = telemetryWorkerSessionRef.current;
			telemetryWorkerSessionRef.current = null;
			if (telemetryWorkerSession !== null) {
				void drainTelemetrySession(telemetryWorkerSession);
			}
		};
	}, [paneRuntimeHost, target]);
	const publishActiveViewerModeWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			for (const message of messages) {
				if (message.kind === 'nativeSurfaceSelectionRequest') {
					applyNativeSurfaceSelectionRequest(message);
				}
			}
			resolveBridgeWorkerActiveViewerModeRequestResolvers({
				messages,
				resolversByRequestId: activeViewerModeRequestResolversRef.current,
				settledResultsByRequestId: activeViewerModeSettledResultsRef.current,
			});
		},
		[applyNativeSurfaceSelectionRequest],
	);
	useEffect((): (() => void) => {
		const requestResolvers = activeViewerModeRequestResolversRef.current;
		const settledResults = activeViewerModeSettledResultsRef.current;
		const unsubscribePaneMessages = paneRuntimeHost.runtime.paneClient.subscribeMessages(
			(message): void => {
				publishActiveViewerModeWorkerMessages([message]);
			},
		);
		return (): void => {
			unsubscribePaneMessages();
			resolvePendingBridgeWorkerActiveViewerModeRequests({
				didSend: false,
				resolversByRequestId: requestResolvers,
			});
			settledResults.clear();
			paneRuntimeHost.runtime.dispose();
		};
	}, [paneRuntimeHost, publishActiveViewerModeWorkerMessages]);
	const sendActiveViewerModeWorkerUpdate = useCallback(
		(update: BridgeActiveViewerModeUpdate): Promise<boolean> => {
			let requestId: string;
			try {
				requestId = paneRuntimeHost.runtime.paneClient.send(
					encodeBridgeWorkerActiveViewerModeUpdateCommand({
						requestId: 'pane-runtime-owned',
						epoch: ++activeViewerModeWorkerEpochRef.current,
						update,
					}),
				);
			} catch {
				return Promise.resolve(false);
			}
			return new Promise<boolean>((resolve): void => {
				const settledResult = activeViewerModeSettledResultsRef.current.get(requestId);
				if (settledResult !== undefined) {
					activeViewerModeSettledResultsRef.current.delete(requestId);
					resolve(settledResult);
					return;
				}
				activeViewerModeRequestResolversRef.current.set(requestId, resolve);
			});
		},
		[paneRuntimeHost],
	);
	activeViewerModeRef.current = activeViewerState.viewerMode;
	activeViewerSourcesRef.current = activeViewerSources;
	const sendActiveViewerModeUpdate = useCallback((): void => {
		const activeViewerMode = activeViewerModeRef.current;
		const activeSource = activeViewerSourcesRef.current[activeViewerMode];
		const pendingNativeSurfaceSelection = pendingNativeSurfaceSelectionRef.current;
		if (
			pendingNativeSurfaceSelection !== null &&
			pendingNativeSurfaceSelection.request.surface === activeViewerMode
		) {
			const nativeSignalKey = `native:${pendingNativeSurfaceSelection.arrivalRevision}:${pendingNativeSurfaceSelection.request.nativeSelectionRequestId}`;
			if (lastSentActiveViewerModeSignalKeyRef.current === nativeSignalKey) {
				return;
			}
			lastSentActiveViewerModeSignalKeyRef.current = nativeSignalKey;
			activeViewerModeSequenceRef.current += 1;
			void sendActiveViewerModeWorkerUpdate({
				activeSource,
				mode: activeViewerMode,
				nativeSelectionRequestId: pendingNativeSurfaceSelection.request.nativeSelectionRequestId,
				sequence: activeViewerModeSequenceRef.current,
				sessionId: activeViewerModeSessionIdRef.current,
			}).then((didSend): void => {
				if (didSend) {
					activeViewerModeRetryAttemptsBySignalKeyRef.current.delete(nativeSignalKey);
					if (
						pendingNativeSurfaceSelectionRef.current?.arrivalRevision ===
						pendingNativeSurfaceSelection.arrivalRevision
					) {
						pendingNativeSurfaceSelectionRef.current = null;
					}
					return;
				}
				if (lastSentActiveViewerModeSignalKeyRef.current !== nativeSignalKey) {
					return;
				}
				lastSentActiveViewerModeSignalKeyRef.current = null;
				if (
					activeViewerModeRetryAttemptAvailable({
						retryAttemptsBySignalKey: activeViewerModeRetryAttemptsBySignalKeyRef.current,
						signalKey: nativeSignalKey,
					})
				) {
					setActiveViewerModeRetryRevision(
						(currentRetryRevision): number => currentRetryRevision + 1,
					);
				}
			});
			return;
		}
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
			void sendActiveViewerModeWorkerUpdate({
				sessionId: activeViewerModeSessionIdRef.current,
				sequence: activeViewerModeSequenceRef.current,
				mode: activeViewerMode,
				activeSource: null,
				nativeSelectionRequestId: null,
			}).then((didSend): void => {
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
		void sendActiveViewerModeWorkerUpdate({
			sessionId: activeViewerModeSessionIdRef.current,
			sequence: activeViewerModeSequenceRef.current,
			mode: activeViewerMode,
			activeSource,
			nativeSelectionRequestId: null,
		}).then((didSend): void => {
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
	}, [sendActiveViewerModeWorkerUpdate]);
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
		nativeSurfaceSelectionSignalRevision,
		registerBridgeReadyCallback,
		sendActiveViewerModeUpdate,
	]);
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
			...(props.codeViewWorkerFactory === undefined
				? {}
				: { workerFactory: props.codeViewWorkerFactory }),
		});
	}, [activeViewerState.viewerMode, props.codeViewWorkerFactory]);
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
						fileViewClient={paneRuntimeHost.fileViewClient}
						isActive={activeViewerState.viewerMode === 'file'}
						controlTarget={target}
						onActiveSourceChange={reportFileActiveSource}
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
						isActive={activeViewerState.viewerMode === 'review'}
						target={target}
						onActiveSourceChange={reportReviewActiveSource}
						reviewClient={paneRuntimeHost.reviewClient}
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

function createBridgePaneRuntimeHost(
	runtimeFactory: () => BridgePaneRuntime,
): BridgePaneRuntimeHost {
	const runtime = runtimeFactory();
	try {
		return {
			fileViewClient: runtime.surfaceClient('fileView'),
			reviewClient: runtime.surfaceClient('review'),
			runtime,
		};
	} catch (error: unknown) {
		runtime.dispose();
		throw error;
	}
}

function createDefaultBridgePaneRuntime(): BridgePaneRuntime {
	return createBridgePaneRuntime();
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

function resolveBridgeWorkerActiveViewerModeRequestResolvers(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
	readonly settledResultsByRequestId: Map<string, boolean>;
}): void {
	for (const message of props.messages) {
		if (message.kind !== 'health' || message.requestId === undefined) {
			continue;
		}
		const resolve = props.resolversByRequestId.get(message.requestId);
		if (resolve === undefined) {
			props.settledResultsByRequestId.set(
				message.requestId,
				bridgeWorkerActiveViewerModeHealthDidSend(message),
			);
			continue;
		}
		props.resolversByRequestId.delete(message.requestId);
		resolve(bridgeWorkerActiveViewerModeHealthDidSend(message));
	}
}

function bridgeWorkerActiveViewerModeHealthDidSend(message: BridgeWorkerHealthEvent): boolean {
	if (message.status === 'ready') {
		return true;
	}
	return message.deliveryStatus === 'unknownAfterDispatch';
}

function resolvePendingBridgeWorkerActiveViewerModeRequests(props: {
	readonly didSend: boolean;
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
}): void {
	for (const resolve of props.resolversByRequestId.values()) {
		resolve(props.didSend);
	}
	props.resolversByRequestId.clear();
}
