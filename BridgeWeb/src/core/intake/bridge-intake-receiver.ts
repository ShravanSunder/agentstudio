import type { BridgeIntakeFrame } from '../models/bridge-intake-frame.js';

export type { BridgeIntakeFrame } from '../models/bridge-intake-frame.js';

export type BridgeIntakeReceiverStatus = 'opening' | 'active' | 'resetRequired' | 'closed';

export type BridgeIntakeReceiveDropReason =
	| 'closed'
	| 'duplicate_sequence'
	| 'generation_mismatch'
	| 'reset_required'
	| 'sequence_gap'
	| 'stale_sequence'
	| 'stream_mismatch';

export interface BridgeIntakeReceiveDrop {
	readonly reason: BridgeIntakeReceiveDropReason;
	readonly frame: BridgeIntakeFrame;
	readonly expectedSequence: number;
}

export type BridgeIntakeReceiveResult =
	| {
			readonly ok: true;
			readonly status: BridgeIntakeReceiverStatus;
	  }
	| {
			readonly ok: false;
			readonly reason: BridgeIntakeReceiveDropReason;
			readonly status: BridgeIntakeReceiverStatus;
	  };

export interface BridgeIntakeReceiverState {
	readonly status: BridgeIntakeReceiverStatus;
	readonly streamId: string;
	readonly generation: number;
	readonly nextSequence: number;
}

export interface BridgeIntakeReceiver {
	readonly state: BridgeIntakeReceiverState;
	receive(frame: BridgeIntakeFrame): BridgeIntakeReceiveResult;
	close(): void;
}

export interface CreateBridgeIntakeReceiverProps {
	readonly streamId: string;
	readonly generation: number;
	readonly onFrame: (frame: BridgeIntakeFrame) => void;
	readonly onDroppedFrame?: (drop: BridgeIntakeReceiveDrop) => void;
}

export function createBridgeIntakeReceiver(
	props: CreateBridgeIntakeReceiverProps,
): BridgeIntakeReceiver {
	let status: BridgeIntakeReceiverStatus = 'opening';
	let currentGeneration = props.generation;
	let nextSequence = 0;

	function drop(
		frame: BridgeIntakeFrame,
		reason: BridgeIntakeReceiveDropReason,
	): BridgeIntakeReceiveResult {
		props.onDroppedFrame?.({
			reason,
			frame,
			expectedSequence: nextSequence,
		});
		return {
			ok: false,
			reason,
			status,
		};
	}

	return {
		get state(): BridgeIntakeReceiverState {
			return {
				status,
				streamId: props.streamId,
				generation: currentGeneration,
				nextSequence,
			};
		},
		receive(frame: BridgeIntakeFrame): BridgeIntakeReceiveResult {
			if (status === 'closed') {
				return drop(frame, 'closed');
			}
			if (frame.streamId !== props.streamId) {
				return drop(frame, 'stream_mismatch');
			}
			if (frame.kind === 'reset' && frame.generation > currentGeneration) {
				currentGeneration = frame.generation;
				nextSequence = frame.sequence + 1;
				status = 'active';
				props.onFrame(frame);
				return {
					ok: true,
					status,
				};
			}
			if (status === 'resetRequired') {
				return drop(frame, 'reset_required');
			}
			if (frame.generation !== currentGeneration) {
				return drop(frame, 'generation_mismatch');
			}
			if (frame.sequence < nextSequence) {
				if (frame.sequence === nextSequence - 1) {
					return drop(frame, 'duplicate_sequence');
				}
				return drop(frame, 'stale_sequence');
			}
			if (frame.sequence > nextSequence) {
				status = 'resetRequired';
				return drop(frame, 'sequence_gap');
			}
			nextSequence += 1;
			status = frame.kind === 'close' ? 'closed' : 'active';
			props.onFrame(frame);
			return {
				ok: true,
				status,
			};
		},
		close(): void {
			status = 'closed';
		},
	};
}
