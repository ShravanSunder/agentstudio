import type {
	BridgeIntakeReceiver,
	BridgeIntakeReceiverState,
	BridgeIntakeReceiveResult,
} from '../core/intake/bridge-intake-receiver.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import {
	reviewProtocolFrameSchema,
	type ReviewProtocolFrame,
} from '../features/review/models/review-protocol-models.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';

export function createBridgeReviewIntakeReceiver(props: {
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
