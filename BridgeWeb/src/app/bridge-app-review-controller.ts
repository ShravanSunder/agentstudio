import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import type { BridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import { applyValidatedReviewProtocolFrame } from '../features/review/materialization/review-materializer.js';
import type {
	ReviewInvalidationFrame,
	ReviewProtocolFrame,
	ReviewTreeRowMetadata,
} from '../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	materializeAcceptedReviewSnapshotForPackage,
	materializeReviewProtocolDeltaFrame,
	materializeReviewProtocolSnapshotFrame,
	materializeReviewProtocolWindowFrame,
	reviewInvalidationFrameMatchesCurrentAuthority,
	reviewResetFrameMatchesCurrentAuthority,
	reviewSnapshotFrameMatchesAuthority,
} from './bridge-app-review-descriptors.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	bridgeReviewPackageFromMetadataSnapshot,
	bridgeReviewPackageWithMetadataSnapshot,
	bridgeReviewPackageWithMetadataWindow,
	firstVisibleItemId,
	isStaleReviewPackageReplacement,
	mergeReviewTreeRowsByRowId,
	reviewTreeRowsWithMetadataDelta,
} from './bridge-app-review-metadata-package.js';
import type { ReviewMetadataCarryForwardVerificationCounts } from './bridge-app-review-metadata-package.js';
import {
	createChildTraceContext,
	makeTelemetryPackageKey,
	recordReviewStartupTelemetry,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';

export interface BridgeDiffStatusState {
	readonly status: 'idle' | 'loading' | 'ready' | 'error';
	readonly error: string | null;
	readonly epoch: number;
}

type ReviewMetadataSnapshotApplyFailure =
	| 'review_metadata_snapshot_descriptor_mismatch'
	| 'review_metadata_snapshot_parse_failed'
	| 'review_metadata_snapshot_rejected';

interface BridgeReviewProtocolTransportFrameApplyProps {
	readonly protocolFrame: ReviewProtocolFrame;
	readonly setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void;
	readonly getReviewTreeRows: () => readonly ReviewTreeRowMetadata[];
	readonly setReviewTreeRows: (rows: readonly ReviewTreeRowMetadata[]) => void;
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
	readonly dispatchReviewInvalidation: (frame: ReviewInvalidationFrame) => void;
	readonly synchronizeReviewWorkerSource: (source: BridgeReviewWorkerSourceSnapshot) => void;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
	readonly telemetryContext: BridgeReviewPackageTelemetryContext;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}

export interface BridgeReviewWorkerSourceSnapshot {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
}

export async function applyReviewProtocolTransportFrame(
	props: BridgeReviewProtocolTransportFrameApplyProps,
): Promise<void> {
	await applyReviewProtocolFramePayload(props);
}

export async function applyReviewEnvelope(props: {
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
	props: BridgeReviewProtocolTransportFrameApplyProps,
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
		dispatchReviewInvalidation,
		getReviewTreeRows,
		reviewFrameAuthority,
		synchronizeReviewWorkerSource,
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
		const carryForwardVerificationCounts = emptyReviewMetadataCarryForwardVerificationCounts();
		if (shouldMergeSnapshotWithCurrentPackage) {
			packagePayload = bridgeReviewPackageWithMetadataSnapshot({
				reviewPackage: currentReviewPackage,
				snapshotPackage: packagePayload,
				snapshotFrame,
				carryForwardVerificationCounts,
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
		const telemetryContext = {
			slice: props.telemetryContext.slice,
			traceContext: props.telemetryContext.traceContext,
			transport: props.telemetryContext.transport,
		};
		const nextReviewTreeRows = shouldMergeSnapshotWithCurrentPackage
			? mergeReviewTreeRowsByRowId({
					current: getReviewTreeRows(),
					nextRows: snapshotFrame.treeRows,
				})
			: snapshotFrame.treeRows;
		const packageTelemetryKey = makeTelemetryPackageKey(packagePayload);
		telemetryContextByPackageKey.set(packageTelemetryKey, telemetryContext);
		reviewReadyStartMillisecondsByPackageKeyRef.current.set(
			packageTelemetryKey,
			applyStartMilliseconds,
		);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = packagePayload;
		synchronizeReviewWorkerSource({
			reviewPackage: packagePayload,
			reviewTreeRows: nextReviewTreeRows,
		});
		setReviewTreeRows(nextReviewTreeRows);
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
				...reviewMetadataCarryForwardVerificationNumericAttributes(carryForwardVerificationCounts),
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
		const carryForwardVerificationCounts = emptyReviewMetadataCarryForwardVerificationCounts();
		const packagePayload = bridgeReviewPackageWithMetadataWindow({
			reviewPackage: currentReviewPackage,
			windowFrame,
			carryForwardVerificationCounts,
		});
		recordReviewMetadataCarryForwardVerificationTelemetry({
			carryForwardVerificationCounts,
			telemetryContext: props.telemetryContext,
			telemetryRecorder: props.telemetryRecorder,
		});
		reviewPackageRef.current = packagePayload;
		const nextReviewTreeRows = mergeReviewTreeRowsByRowId({
			current: getReviewTreeRows(),
			nextRows: windowFrame.treeRows,
		});
		synchronizeReviewWorkerSource({
			reviewPackage: packagePayload,
			reviewTreeRows: nextReviewTreeRows,
		});
		setReviewTreeRows(nextReviewTreeRows);
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
		const carryForwardVerificationCounts = emptyReviewMetadataCarryForwardVerificationCounts();
		const packagePayload =
			currentReviewPackage === null
				? null
				: applyReviewMetadataDeltaToReviewPackage({
						deltaFrame,
						reviewPackage: currentReviewPackage,
						carryForwardVerificationCounts,
					});
		if (packagePayload !== null) {
			recordReviewMetadataCarryForwardVerificationTelemetry({
				carryForwardVerificationCounts,
				telemetryContext: props.telemetryContext,
				telemetryRecorder: props.telemetryRecorder,
			});
			reviewPackageRef.current = packagePayload;
			const nextReviewTreeRows = reviewTreeRowsWithMetadataDelta({
				current: getReviewTreeRows(),
				deltaFrame,
			});
			synchronizeReviewWorkerSource({
				reviewPackage: packagePayload,
				reviewTreeRows: nextReviewTreeRows,
			});
			setReviewTreeRows(nextReviewTreeRows);
			setReviewPackage((): BridgeReviewPackage => packagePayload);
		}
		return;
	}
	if (
		protocolFrame?.frameKind === 'review.invalidate' &&
		reviewInvalidationFrameMatchesCurrentAuthority({
			frame: protocolFrame,
			currentReviewPackage: reviewPackageRef.current,
			reviewFrameAuthority,
		})
	) {
		synchronizeReviewWorkerSource({
			reviewPackage: reviewPackageRef.current,
			reviewTreeRows: getReviewTreeRows(),
		});
		dispatchReviewInvalidation(protocolFrame);
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
				: applyValidatedReviewProtocolFrame({
						frame: protocolFrame,
						paneId: reviewFrameAuthority.paneId,
						registry: descriptorRegistry,
					});
		if (materializeResult?.ok !== true || materializeResult.delta.kind !== 'reset') {
			return;
		}
		reviewPackageRef.current = null;
		currentReviewPackageTelemetryContextRef.current = null;
		synchronizeReviewWorkerSource({
			reviewPackage: null,
			reviewTreeRows: [],
		});
		setReviewTreeRows([]);
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

function emptyReviewMetadataCarryForwardVerificationCounts(): ReviewMetadataCarryForwardVerificationCounts {
	return {
		unverifiedKeepCount: 0,
		verifiedDropCount: 0,
		verifiedKeepCount: 0,
	};
}

function reviewMetadataCarryForwardVerificationNumericAttributes(
	counts: ReviewMetadataCarryForwardVerificationCounts,
): Readonly<Record<string, number>> {
	return {
		'agentstudio.bridge.review.metadata_carry_forward.unverified_keep.count':
			counts.unverifiedKeepCount,
		'agentstudio.bridge.review.metadata_carry_forward.verified_drop.count':
			counts.verifiedDropCount,
		'agentstudio.bridge.review.metadata_carry_forward.verified_keep.count':
			counts.verifiedKeepCount,
	};
}

function recordReviewMetadataCarryForwardVerificationTelemetry(props: {
	readonly carryForwardVerificationCounts: ReviewMetadataCarryForwardVerificationCounts;
	readonly telemetryContext: BridgeReviewPackageTelemetryContext;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}): void {
	const totalCount =
		props.carryForwardVerificationCounts.unverifiedKeepCount +
		props.carryForwardVerificationCounts.verifiedDropCount +
		props.carryForwardVerificationCounts.verifiedKeepCount;
	if (totalCount === 0) {
		return;
	}
	recordReviewStartupTelemetry({
		telemetryRecorder: props.telemetryRecorder,
		phase: 'review_metadata_apply',
		slice: props.telemetryContext.slice,
		transport: props.telemetryContext.transport,
		traceContext: createChildTraceContext(props.telemetryContext.traceContext),
		durationMilliseconds: null,
		result: 'success',
		resultReason: 'metadata_carry_forward_verification',
		numericAttributes: reviewMetadataCarryForwardVerificationNumericAttributes(
			props.carryForwardVerificationCounts,
		),
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
	const exhaustiveError: never = error;
	void exhaustiveError;
	return 'snapshot_unknown';
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

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
