import { type MutableRefObject, useEffect, useRef } from 'react';

import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import {
	type BridgePushDropReason,
	installBridgePushReceiver,
} from '../bridge/bridge-push-receiver.js';
import {
	installBridgeIntakeEventCarrier,
	type BridgeIntakeCarrierDrop,
} from '../core/intake/bridge-intake-carrier.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import type { BridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type {
	ReviewInvalidationFrame,
	ReviewProtocolFrame,
	ReviewTreeRowMetadata,
} from '../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewSelectionSlice } from '../review-viewer/state/review-viewer-store.js';
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
	readonly getPushNonce: () => string | null;
	readonly getReviewFrameAuthority: () => BridgeReviewFrameAuthority | null;
	readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
	readonly reviewEnvelopeApplyTailRef: MutableRefObject<Promise<void>>;
	readonly beginForegroundReviewSelection: (itemId: string) => boolean;
	readonly setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void;
	readonly getReviewTreeRows: () => readonly ReviewTreeRowMetadata[];
	readonly setReviewTreeRows: (rows: readonly ReviewTreeRowMetadata[]) => void;
	readonly setDiffStatus: (
		update: (current: BridgeDiffStatusState) => BridgeDiffStatusState,
	) => void;
	readonly setSelectedItemId: (itemId: string | null) => void;
	readonly selectionSliceRef: MutableRefObject<BridgeReviewSelectionSlice>;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly reviewPackageTelemetryContextRef: MutableRefObject<
		Map<string, BridgeReviewPackageTelemetryContext>
	>;
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly reviewReadyStartMillisecondsByPackageKeyRef: MutableRefObject<Map<string, number>>;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly dispatchReviewInvalidation: (frame: ReviewInvalidationFrame) => void;
	readonly sendReviewIntakeReady: (props: {
		readonly reason: string | null;
		readonly streamId: string | null;
	}) => Promise<boolean>;
	readonly synchronizeReviewWorkerSource: (source: {
		readonly reviewPackage: BridgeReviewPackage | null;
		readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	}) => void;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export function useBridgeReviewIntakeController(props: UseBridgeReviewIntakeControllerProps): void {
	const {
		target,
		isActive,
		getPushNonce,
		getReviewFrameAuthority,
		registerBridgeReadyCallback,
		reviewEnvelopeApplyTailRef,
		beginForegroundReviewSelection,
		setReviewPackage,
		getReviewTreeRows,
		setReviewTreeRows,
		setDiffStatus,
		setSelectedItemId,
		selectionSliceRef,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		currentReviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		descriptorRegistry,
		dispatchReviewInvalidation,
		sendReviewIntakeReady,
		synchronizeReviewWorkerSource,
		telemetryRecorderRef,
	} = props;
	const requestReviewIntakeReadyRef = useRef<(() => void) | null>(null);
	useEffect((): (() => void) => {
		let didMarkReviewIntakeReady = false;
		let isMarkingReviewIntakeReady = false;
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
		const scheduleIntakeReadyRetry = (reason: string | null): void => {
			if (retryHandle !== null || retryCount >= maxIntakeReadyRetries) {
				return;
			}
			retryCount += 1;
			if (typeof requestAnimationFrame === 'function') {
				const id = requestAnimationFrame((): void => {
					retryHandle = null;
					scheduleMarkReviewIntakeReady(reason);
				});
				retryHandle = { kind: 'animationFrame', id };
				return;
			}
			const id = window.setTimeout((): void => {
				retryHandle = null;
				scheduleMarkReviewIntakeReady(reason);
			}, 0);
			retryHandle = { kind: 'timeout', id };
		};
		const markReviewIntakeReady = async (reason: string | null = null): Promise<boolean> => {
			if (didMarkReviewIntakeReady || isMarkingReviewIntakeReady) {
				return true;
			}
			if (getPushNonce() === null) {
				return false;
			}
			const streamId = getReviewFrameAuthority()?.streamId ?? null;
			isMarkingReviewIntakeReady = true;
			const didSendIntakeReady = await sendReviewIntakeReady({
				reason,
				streamId,
			}).finally((): void => {
				isMarkingReviewIntakeReady = false;
			});
			if (!didSendIntakeReady) {
				return false;
			}
			didMarkReviewIntakeReady = true;
			clearScheduledIntakeReadyRetry();
			requestIntakeReplay();
			return true;
		};
		const scheduleMarkReviewIntakeReady = (reason: string | null = null): void => {
			if (didMarkReviewIntakeReady || isMarkingReviewIntakeReady) {
				return;
			}
			void markReviewIntakeReady(reason).then((didMark): void => {
				if (!didMark) {
					scheduleIntakeReadyRetry(reason);
				}
			});
		};
		const requestReviewIntakeReady = (): void => {
			didMarkReviewIntakeReady = false;
			retryCount = 0;
			scheduleMarkReviewIntakeReady();
		};
		requestReviewIntakeReadyRef.current = requestReviewIntakeReady;
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
				attributeFilter: [bridgeReviewPaneIdAttribute, bridgeReviewStreamIdAttribute],
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
						getReviewTreeRows,
						setReviewTreeRows,
						setDiffStatus,
						selectInitialReviewItem: beginForegroundReviewSelection,
						setSelectedItemId,
						getSelectedItemId: (): string | null => selectionSliceRef.current.selectedItemId,
						reviewPackageRef,
						telemetryContextByPackageKey: reviewPackageTelemetryContextRef.current,
						currentReviewPackageTelemetryContextRef,
						reviewReadyStartMillisecondsByPackageKeyRef,
						descriptorRegistry,
						dispatchReviewInvalidation,
						synchronizeReviewWorkerSource,
						reviewFrameAuthority: getReviewFrameAuthority(),
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
			getNonce: getPushNonce,
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
					scheduleMarkReviewIntakeReady('sequence_gap');
				}
			},
		});
		const unregisterBridgeReadyCallback = registerBridgeReadyCallback((): void => {
			queueMicrotask(scheduleMarkReviewIntakeReady);
		});
		scheduleMarkReviewIntakeReady();
		const uninstallPushReceiver = installBridgePushReceiver({
			target,
			getPushNonce,
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
			if (requestReviewIntakeReadyRef.current === requestReviewIntakeReady) {
				requestReviewIntakeReadyRef.current = null;
			}
			clearScheduledIntakeReadyRetry();
			reviewIntakeReadyObserver?.disconnect();
			uninstallIntakeCarrier();
			uninstallPushReceiver();
			unregisterBridgeReadyCallback();
		};
	}, [
		descriptorRegistry,
		dispatchReviewInvalidation,
		beginForegroundReviewSelection,
		currentReviewPackageTelemetryContextRef,
		getPushNonce,
		getReviewFrameAuthority,
		getReviewTreeRows,
		registerBridgeReadyCallback,
		reviewEnvelopeApplyTailRef,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		sendReviewIntakeReady,
		setDiffStatus,
		setReviewPackage,
		setReviewTreeRows,
		setSelectedItemId,
		selectionSliceRef,
		synchronizeReviewWorkerSource,
		target,
		telemetryRecorderRef,
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
		requestReviewIntakeReadyRef.current?.();
	}, [isActive, reviewPackageRef]);
}
