import { type Dispatch, type MutableRefObject, type SetStateAction, useEffect } from 'react';

import type { BridgePageHandshakeSession } from '../bridge/bridge-page-handshake.js';
import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import {
	type BridgePushDropReason,
	installBridgePushReceiver,
} from '../bridge/bridge-push-receiver.js';
import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import {
	installBridgeIntakeEventCarrier,
	type BridgeIntakeCarrierDrop,
} from '../core/intake/bridge-intake-carrier.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type {
	ReviewProtocolFrame,
	ReviewTreeRowMetadata,
} from '../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import type { BridgeReviewViewerStore } from '../review-viewer/state/review-viewer-store.js';
import {
	applyReviewEnvelope,
	applyReviewProtocolTransportFrame,
	type BridgeDiffStatusState,
} from './bridge-app-review-controller.js';
import {
	bridgeReviewPaneIdAttribute,
	bridgeReviewStreamIdAttribute,
	type BridgeReviewFrameAuthority,
} from './bridge-app-review-frame-authority.js';
import { createBridgeReviewIntakeReceiver } from './bridge-app-review-intake-receiver.js';
import { bridgeReviewIntakeMaxFrameBytes } from './bridge-app-review-runtime.js';
import {
	recordIntakeApplyTelemetry,
	recordIntakeApplyTelemetryForSlice,
	recordPushDropTelemetry,
	recordReviewIntakeDropTelemetry,
	recordReviewIntakeFrameTelemetry,
	reviewIntakeTelemetrySliceForFrameKind,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';

export interface UseBridgeReviewIntakeControllerProps {
	readonly target: EventTarget;
	readonly isActive: boolean;
	readonly bridgeHandshakeSessionRef: MutableRefObject<BridgePageHandshakeSession | null>;
	readonly getReviewFrameAuthority: () => BridgeReviewFrameAuthority | null;
	readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
	readonly reviewEnvelopeApplyTailRef: MutableRefObject<Promise<void>>;
	readonly beginForegroundReviewSelection: (itemId: string) => boolean;
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
	readonly viewerStore: BridgeReviewViewerStore;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly reviewPackageTelemetryContextRef: MutableRefObject<
		Map<string, BridgeReviewPackageTelemetryContext>
	>;
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly reviewReadyStartMillisecondsByPackageKeyRef: MutableRefObject<Map<string, number>>;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly invalidatedFreshnessKeysRef: MutableRefObject<Set<string>>;
	readonly setReviewContentInvalidationVersion: Dispatch<SetStateAction<number>>;
	readonly retrySelectedContentAfterDescriptorRegistration: (
		registeredDescriptorRefCount: number,
	) => void;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export function useBridgeReviewIntakeController(props: UseBridgeReviewIntakeControllerProps): void {
	const {
		target,
		isActive,
		bridgeHandshakeSessionRef,
		getReviewFrameAuthority,
		registerBridgeReadyCallback,
		reviewEnvelopeApplyTailRef,
		beginForegroundReviewSelection,
		setReviewPackage,
		setReviewTreeRows,
		setDiffStatus,
		setSelectedItemId,
		viewerStore,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		currentReviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		descriptorRegistry,
		reviewContentDescriptorRefsByHandleIdRef,
		resourceExecutor,
		contentRegistry,
		invalidatedFreshnessKeysRef,
		setReviewContentInvalidationVersion,
		retrySelectedContentAfterDescriptorRegistration,
		telemetryRecorderRef,
	} = props;
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
						setSelectedItemId,
						getSelectedItemId: (): string | null =>
							viewerStore.getState().rootSnapshot.selectedItemId,
						reviewPackageRef,
						telemetryContextByPackageKey: reviewPackageTelemetryContextRef.current,
						currentReviewPackageTelemetryContextRef,
						reviewReadyStartMillisecondsByPackageKeyRef,
						descriptorRegistry,
						reviewContentDescriptorRefsByHandleIdRef,
						resourceExecutor,
						contentRegistry,
						reviewFrameAuthority: getReviewFrameAuthority(),
						invalidatedFreshnessKeysRef,
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
				// A sequence gap locks the receiver in resetRequired: every
				// further same-generation frame is rejected and the surface
				// silently goes stale (frames dropped while the surface was
				// inactive are the common cause). Only a higher-generation
				// reset re-keys it, so re-announce intake-ready — native
				// re-delivers the package as a fresh generation. Firing on the
				// gap transition makes this once per wedge episode.
				if (drop.reason === 'receiver_rejected_frame' && drop.receiverReason === 'sequence_gap') {
					didMarkReviewIntakeReady = false;
					retryCount = 0;
					scheduleMarkReviewIntakeReady();
				}
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
		contentRegistry,
		currentReviewPackageTelemetryContextRef,
		getReviewFrameAuthority,
		invalidatedFreshnessKeysRef,
		registerBridgeReadyCallback,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewEnvelopeApplyTailRef,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		retrySelectedContentAfterDescriptorRegistration,
		setDiffStatus,
		setReviewContentInvalidationVersion,
		setReviewPackage,
		setReviewTreeRows,
		setSelectedItemId,
		target,
		telemetryRecorderRef,
		viewerStore,
	]);

	// A review surface re-activated WITHOUT an applied package lost its
	// stream: frames dropped while it was inactive, a sequence gap, or a
	// failed first load. Re-announcing intake-ready makes native re-deliver
	// the package as a fresh generation (native reloads on an announce for a
	// loaded pane and bootstraps for a cold one). Healthy re-activations —
	// package applied — stay silent, so mode toggles cost nothing.
	useEffect((): void => {
		if (!isActive || reviewPackageRef.current !== null) {
			return;
		}
		bridgeHandshakeSessionRef.current?.markIntakeReady({
			protocolId: 'review',
			streamId: getReviewFrameAuthority()?.streamId ?? null,
		});
	}, [bridgeHandshakeSessionRef, getReviewFrameAuthority, isActive, reviewPackageRef]);
}
