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
import type { BridgeProductNavigationCommand } from '../core/comm-worker/bridge-product-session-contracts.js';
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
	recordBridgeFileModeSendAttempt,
	recordBridgeFileModeSendSynchronousFailure,
	recordBridgePageReadyState,
} from '../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import {
	createBridgeTelemetryRecorder,
	createBridgeTelemetryRecorderFromClient,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { setBridgeViewerNativeOpenAnchor } from '../foundation/telemetry/bridge-viewer-first-interaction.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import type { BridgeAppControlProbe } from './bridge-app-control.js';
import { BridgeFileViewerMode } from './bridge-app-file-viewer-mode.js';
import {
	applyBridgeAppNavigationCommand,
	bridgeAppRememberedNavigationTargetIsEligible,
	clearBridgeAppAcceptedNavigationSource,
	createBridgeAppNavigationAdmissionState,
	reportBridgeAppAcceptedNavigationSource,
	type BridgeAppNavigationAdmissionState,
	type BridgeAppNavigationSource,
	type BridgeAppNavigationTargetCommand,
} from './bridge-app-navigation-admission.js';
import { BridgeReviewViewerMode } from './bridge-app-review-viewer-mode.js';
export type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import {
	bridgeViewerActivationPrewarm,
	type BridgeViewerActivationPrewarmState,
} from './bridge-viewer-activation-prewarm.js';
import { BridgeViewerAppShell } from './bridge-viewer-app-shell.js';
import { BridgeViewerContextSwitcher } from './bridge-viewer-content-header.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly paneRuntime?: BridgePaneRuntime;
	readonly paneRuntimeFactory?: () => BridgePaneRuntime;
	readonly telemetryWorkerFactory?: () => Promise<BridgeTelemetryWorkerLike>;
	readonly viewerMode?: 'file' | 'review';
	readonly fileViewerProps?: BridgeFileViewerAppProps;
}

declare global {
	interface Window {
		bridgeReviewControlProbe?: BridgeAppControlProbe;
	}
}

type BridgeViewerMode = 'file' | 'review';

type BridgeNativeSurfaceSelectionRequest = Extract<
	BridgeWorkerServerToMainMessage,
	{ readonly kind: 'nativeSurfaceSelectionRequest' }
>;

interface BridgePendingNativeSurfaceSelection {
	readonly arrivalRevision: number;
	readonly request: BridgeNativeSurfaceSelectionRequest;
}

type BridgeActiveViewerSources = Record<BridgeViewerMode, BridgeActiveViewerSource | null>;

interface BridgePaneRuntimeHost {
	readonly disposeWithComponent: boolean;
	readonly fileViewClient: BridgePaneSurfaceClient;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly runtime: BridgePaneRuntime;
}

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const paneRuntimeHostRef = useRef<BridgePaneRuntimeHost | null>(null);
	paneRuntimeHostRef.current ??= createBridgePaneRuntimeHost({
		externallyOwnedRuntime: props.paneRuntime ?? null,
		runtimeFactory: props.paneRuntimeFactory ?? createDefaultBridgePaneRuntime,
	});
	const paneRuntimeHost = paneRuntimeHostRef.current;
	const incomingViewerMode = props.viewerMode;
	const [navigationAdmissionState, setNavigationAdmissionState] =
		useState<BridgeAppNavigationAdmissionState>(() =>
			createBridgeAppNavigationAdmissionState(incomingViewerMode ?? 'review'),
		);
	const navigationAdmissionStateRef = useRef(navigationAdmissionState);
	navigationAdmissionStateRef.current = navigationAdmissionState;
	const activeViewerMode = navigationAdmissionState.activeSurface;
	const [mountedViewerModes, setMountedViewerModes] = useState<ReadonlySet<BridgeViewerMode>>(
		() => new Set<BridgeViewerMode>(['file', 'review']),
	);
	const activationPrewarmStateRef = useRef<BridgeViewerActivationPrewarmState>({
		prewarmedModes: new Set(),
	});
	const activeViewerModeSessionIdRef = useRef<string>(createBridgeActiveViewerModeSessionId());
	const activeViewerModeSequenceRef = useRef(0);
	const activeViewerModeRef = useRef<BridgeViewerMode>(activeViewerMode);
	const previousActiveViewerModeRef = useRef<BridgeViewerMode | null>(null);
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
		const currentState = navigationAdmissionStateRef.current;
		if (currentState.activeSurface === viewerMode) return;
		const nextState = { ...currentState, activeSurface: viewerMode };
		navigationAdmissionStateRef.current = nextState;
		setNavigationAdmissionState(nextState);
	}, []);
	const applyNativeSurfaceSelectionRequest = useCallback(
		(request: BridgeNativeSurfaceSelectionRequest): void => {
			const currentState = navigationAdmissionStateRef.current;
			const nextState = applyBridgeAppNavigationCommand(currentState, request.navigationCommand);
			if (nextState === currentState) return;
			nativeSurfaceSelectionArrivalRevisionRef.current += 1;
			const arrivalRevision = nativeSurfaceSelectionArrivalRevisionRef.current;
			pendingNativeSurfaceSelectionRef.current = { arrivalRevision, request };
			navigationAdmissionStateRef.current = nextState;
			setNavigationAdmissionState(nextState);
		},
		[],
	);
	useEffect((): (() => void) => {
		recordBridgePageReadyState('awaiting');
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
				recordBridgePageReadyState('ready');
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
				recordBridgePageReadyState('failed');
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
			recordBridgePageReadyState('awaiting');
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
			if (paneRuntimeHost.disposeWithComponent) {
				paneRuntimeHost.runtime.dispose();
			}
		};
	}, [paneRuntimeHost, publishActiveViewerModeWorkerMessages]);
	const sendActiveViewerModeWorkerUpdate = useCallback(
		(update: BridgeActiveViewerModeUpdate): Promise<boolean> => {
			let requestId: string;
			if (update.mode === 'file') recordBridgeFileModeSendAttempt();
			try {
				requestId = paneRuntimeHost.runtime.paneClient.send(
					encodeBridgeWorkerActiveViewerModeUpdateCommand({
						requestId: 'pane-runtime-owned',
						epoch: ++activeViewerModeWorkerEpochRef.current,
						update,
					}),
				);
			} catch {
				if (update.mode === 'file') recordBridgeFileModeSendSynchronousFailure();
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
	activeViewerModeRef.current = activeViewerMode;
	activeViewerSourcesRef.current = activeViewerSources;
	useLayoutEffect((): void => {
		const pendingSelection = pendingNativeSurfaceSelectionRef.current;
		if (
			pendingSelection === null ||
			!bridgeAppNavigationCommandIsAdmitted(
				navigationAdmissionState,
				pendingSelection.request.navigationCommand,
			)
		) {
			return;
		}
		setNativeSurfaceSelectionSignalRevision(pendingSelection.arrivalRevision);
	}, [navigationAdmissionState]);
	const sendActiveViewerModeUpdate = useCallback((): void => {
		const currentActiveViewerMode = activeViewerModeRef.current;
		const activeSource = activeViewerSourcesRef.current[currentActiveViewerMode];
		const pendingNativeSurfaceSelection = pendingNativeSurfaceSelectionRef.current;
		const currentNavigationAdmissionState = navigationAdmissionStateRef.current;
		const pendingNativeSurfaceSelectionIsAdmitted =
			pendingNativeSurfaceSelection !== null &&
			bridgeAppNavigationCommandIsAdmitted(
				currentNavigationAdmissionState,
				pendingNativeSurfaceSelection.request.navigationCommand,
			);
		if (
			pendingNativeSurfaceSelectionIsAdmitted &&
			pendingNativeSurfaceSelection !== null &&
			pendingNativeSurfaceSelection.request.navigationCommand.surface === currentActiveViewerMode
		) {
			const nativeSignalKey = `native:${pendingNativeSurfaceSelection.arrivalRevision}:${pendingNativeSurfaceSelection.request.navigationCommand.commandId}`;
			if (lastSentActiveViewerModeSignalKeyRef.current === nativeSignalKey) {
				return;
			}
			lastSentActiveViewerModeSignalKeyRef.current = nativeSignalKey;
			activeViewerModeSequenceRef.current += 1;
			void sendActiveViewerModeWorkerUpdate({
				activeSource,
				mode: currentActiveViewerMode,
				nativeSelectionRequestId: pendingNativeSurfaceSelection.request.navigationCommand.commandId,
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
		if (
			pendingNativeSurfaceSelection !== null &&
			pendingNativeSurfaceSelection.request.navigationCommand.surface === currentActiveViewerMode &&
			currentNavigationAdmissionState.pendingCommand?.commandId !==
				pendingNativeSurfaceSelection.request.navigationCommand.commandId
		) {
			pendingNativeSurfaceSelectionRef.current = null;
		}
		const activationRevision = activeViewerModeActivationRevisionRef.current;
		if (activeSource === null) {
			if (
				activationRevision === 0 ||
				activeViewerModeSourceSentActivationRevisionsRef.current.has(activationRevision)
			) {
				return;
			}
			const pendingSignalKey = `${activationRevision}:${currentActiveViewerMode}:pending-source`;
			if (lastSentActiveViewerModeSignalKeyRef.current === pendingSignalKey) {
				return;
			}
			lastSentActiveViewerModeSignalKeyRef.current = pendingSignalKey;
			activeViewerModeSequenceRef.current += 1;
			void sendActiveViewerModeWorkerUpdate({
				sessionId: activeViewerModeSessionIdRef.current,
				sequence: activeViewerModeSequenceRef.current,
				mode: currentActiveViewerMode,
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
		const signalKey = `${activationRevision}:${currentActiveViewerMode}:${activeSource.protocol}:${activeSource.streamId}:${activeSource.generation}`;
		if (lastSentActiveViewerModeSignalKeyRef.current === signalKey) {
			return;
		}
		lastSentActiveViewerModeSignalKeyRef.current = signalKey;
		activeViewerModeSourceSentActivationRevisionsRef.current.add(activationRevision);
		activeViewerModeSequenceRef.current += 1;
		void sendActiveViewerModeWorkerUpdate({
			sessionId: activeViewerModeSessionIdRef.current,
			sequence: activeViewerModeSequenceRef.current,
			mode: currentActiveViewerMode,
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
		if (previousActiveViewerModeRef.current === activeViewerMode) {
			return;
		}
		activeViewerModeActivationRevisionRef.current += 1;
		previousActiveViewerModeRef.current = activeViewerMode;
	}, [activeViewerMode]);
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
	const reportAcceptedNavigationSource = useCallback(
		(surface: BridgeViewerMode, source: BridgeAppNavigationSource | null): void => {
			const currentState = navigationAdmissionStateRef.current;
			const nextState =
				source === null
					? clearBridgeAppAcceptedNavigationSource(currentState, surface)
					: reportBridgeAppAcceptedNavigationSource(currentState, source);
			if (nextState === currentState) return;
			navigationAdmissionStateRef.current = nextState;
			setNavigationAdmissionState(nextState);
		},
		[],
	);
	const reportFileNavigationSource = useCallback(
		(source: Extract<BridgeAppNavigationSource, { readonly sourceKind: 'file' }> | null): void => {
			reportAcceptedNavigationSource('file', source);
		},
		[reportAcceptedNavigationSource],
	);
	const reportReviewNavigationSource = useCallback(
		(
			source: Extract<BridgeAppNavigationSource, { readonly sourceKind: 'review' }> | null,
		): void => {
			reportAcceptedNavigationSource('review', source);
		},
		[reportAcceptedNavigationSource],
	);
	const isNavigationCommandStillEligible = useCallback(
		(command: BridgeAppNavigationTargetCommand): boolean =>
			bridgeAppRememberedNavigationTargetIsEligible(navigationAdmissionStateRef.current, command),
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
		activeViewerMode,
		activeViewerModeRetryRevision,
		nativeSurfaceSelectionSignalRevision,
		registerBridgeReadyCallback,
		sendActiveViewerModeUpdate,
	]);
	useEffect((): void => {
		if (incomingViewerMode === undefined) return;
		setMountedViewerModes((currentMountedViewerModes): ReadonlySet<BridgeViewerMode> => {
			if (currentMountedViewerModes.has(incomingViewerMode)) {
				return currentMountedViewerModes;
			}
			return new Set<BridgeViewerMode>([...currentMountedViewerModes, incomingViewerMode]);
		});
		const currentState = navigationAdmissionStateRef.current;
		if (currentState.activeSurface === incomingViewerMode) return;
		const nextState = { ...currentState, activeSurface: incomingViewerMode };
		navigationAdmissionStateRef.current = nextState;
		setNavigationAdmissionState(nextState);
	}, [incomingViewerMode]);
	useEffect((): void => {
		bridgeViewerActivationPrewarm({
			activeViewerMode,
			state: activationPrewarmStateRef.current,
			...(props.codeViewWorkerFactory === undefined
				? {}
				: { workerFactory: props.codeViewWorkerFactory }),
		});
	}, [activeViewerMode, props.codeViewWorkerFactory]);
	const rememberedFileNavigationCommand = navigationAdmissionState.targetCommands.file;
	const rememberedReviewNavigationCommand = navigationAdmissionState.targetCommands.review;
	const requiresFileNavigationSourceDiscovery =
		navigationAdmissionState.pendingCommand?.surface === 'file';

	return (
		<BridgeViewerAppShell appOwner="BridgeApp" mode={activeViewerMode}>
			{mountedViewerModes.has('file') ? (
				<div
					className="h-full min-h-0"
					data-bridge-viewer-mode-active={activeViewerMode === 'file' ? 'true' : 'false'}
					data-bridge-viewer-mode-host="file"
					data-testid="bridge-viewer-mode-host-file"
					hidden={activeViewerMode !== 'file'}
				>
					<BridgeFileViewerMode
						{...props}
						fileViewClient={paneRuntimeHost.fileViewClient}
						isNavigationCommandStillEligible={isNavigationCommandStillEligible}
						isActive={activeViewerMode === 'file'}
						controlTarget={target}
						onActiveSourceChange={reportFileActiveSource}
						onNavigationSourceChange={reportFileNavigationSource}
						requiresNavigationSourceDiscovery={requiresFileNavigationSourceDiscovery}
						telemetryRecorder={telemetryRecorder}
						viewerContextSwitcher={
							<BridgeViewerContextSwitcher
								mode={activeViewerMode}
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
					data-bridge-viewer-mode-active={activeViewerMode === 'review' ? 'true' : 'false'}
					data-bridge-viewer-mode-host="review"
					data-testid="bridge-viewer-mode-host-review"
					hidden={activeViewerMode !== 'review'}
				>
					<BridgeReviewViewerMode
						{...props}
						isActive={activeViewerMode === 'review'}
						isNavigationCommandStillEligible={isNavigationCommandStillEligible}
						target={target}
						onActiveSourceChange={reportReviewActiveSource}
						onNavigationSourceChange={reportReviewNavigationSource}
						reviewClient={paneRuntimeHost.reviewClient}
						telemetryRecorderRef={telemetryRecorderRef}
						viewerContextSwitcher={
							<BridgeViewerContextSwitcher
								mode={activeViewerMode}
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

function createBridgePaneRuntimeHost(props: {
	readonly externallyOwnedRuntime: BridgePaneRuntime | null;
	readonly runtimeFactory: () => BridgePaneRuntime;
}): BridgePaneRuntimeHost {
	const runtime = props.externallyOwnedRuntime ?? props.runtimeFactory();
	const disposeWithComponent = props.externallyOwnedRuntime === null;
	try {
		return {
			disposeWithComponent,
			fileViewClient: runtime.surfaceClient('fileView'),
			reviewClient: runtime.surfaceClient('review'),
			runtime,
		};
	} catch (error: unknown) {
		if (disposeWithComponent) {
			runtime.dispose();
		}
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

function bridgeAppNavigationCommandIsAdmitted(
	state: BridgeAppNavigationAdmissionState,
	command: BridgeProductNavigationCommand,
): boolean {
	if (
		state.latestBindingRevision !== command.bindingRevision ||
		state.latestCommandId !== command.commandId ||
		state.activeSurface !== command.surface
	) {
		return false;
	}
	if (command.commandKind === 'activateContext') return true;
	const admittedTarget = state.targetCommands[command.surface];
	return (
		admittedTarget?.commandId === command.commandId &&
		admittedTarget.bindingRevision === command.bindingRevision
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
