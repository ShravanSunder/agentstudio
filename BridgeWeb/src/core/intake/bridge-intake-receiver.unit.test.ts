import { describe, expect, test } from 'vitest';

import {
	createBridgeIntakeReceiver,
	type BridgeIntakeFrame,
	type BridgeIntakeReceiveDrop,
} from './bridge-intake-receiver.js';

describe('bridge intake receiver', () => {
	test('detects sequence gaps and rejects later frames until reset', () => {
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeReceiveDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
			onDroppedFrame: (drop: BridgeIntakeReceiveDrop): void => {
				droppedFrames.push(drop);
			},
		});

		const firstResult = receiver.receive(createFrame({ sequence: 0 }));
		const gapResult = receiver.receive(createFrame({ sequence: 2 }));
		const postGapResult = receiver.receive(createFrame({ sequence: 3 }));

		expect(firstResult).toEqual({ ok: true, status: 'active' });
		expect(gapResult).toEqual({
			ok: false,
			reason: 'sequence_gap',
			status: 'resetRequired',
		});
		expect(postGapResult).toEqual({
			ok: false,
			reason: 'reset_required',
			status: 'resetRequired',
		});
		expect(acceptedFrames.map((frame: BridgeIntakeFrame): number => frame.sequence)).toEqual([0]);
		expect(
			droppedFrames.map((drop: BridgeIntakeReceiveDrop): BridgeIntakeReceiveDrop['reason'] => {
				return drop.reason;
			}),
		).toEqual(['sequence_gap', 'reset_required']);
		expect(droppedFrames[0]?.frame).toEqual({
			kind: 'snapshot',
			streamId: 'stream-1',
			generation: 1,
			sequence: 2,
		});
	});

	test('reports dropped frames without exposing payload bytes', () => {
		const droppedFrames: BridgeIntakeReceiveDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (): void => {},
			onDroppedFrame: (drop: BridgeIntakeReceiveDrop): void => {
				droppedFrames.push(drop);
			},
		});

		receiver.receive(
			createFrame({
				sequence: 2,
				value: { body: 'must-not-leave-receiver-drop', descriptorId: 'descriptor-1' },
			}),
		);

		expect(droppedFrames).toEqual([
			{
				reason: 'sequence_gap',
				frame: {
					kind: 'snapshot',
					streamId: 'stream-1',
					generation: 1,
					sequence: 2,
				},
				expectedSequence: 0,
			},
		]);
		expect(JSON.stringify(droppedFrames)).not.toContain('must-not-leave-receiver-drop');
		expect(JSON.stringify(droppedFrames)).not.toContain('body');
	});

	test('accepts a newer-generation reset frame after a sequence gap', () => {
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
		});

		receiver.receive(createFrame({ sequence: 0 }));
		receiver.receive(createFrame({ sequence: 2 }));

		const resetResult = receiver.receive({
			kind: 'reset',
			streamId: 'stream-1',
			generation: 2,
			sequence: 0,
		});
		const resumedResult = receiver.receive(createFrame({ generation: 2, sequence: 1 }));

		expect(resetResult).toEqual({ ok: true, status: 'active' });
		expect(resumedResult).toEqual({ ok: true, status: 'active' });
		expect(receiver.state).toEqual({
			status: 'active',
			streamId: 'stream-1',
			generation: 2,
			nextSequence: 2,
		});
		expect(
			acceptedFrames.map((frame: BridgeIntakeFrame): BridgeIntakeFrame['kind'] => frame.kind),
		).toEqual(['snapshot', 'reset', 'snapshot']);
	});

	test('rejects duplicate and older-sequence frames before mutation', () => {
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeReceiveDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
			onDroppedFrame: (drop: BridgeIntakeReceiveDrop): void => {
				droppedFrames.push(drop);
			},
		});

		receiver.receive(createFrame({ sequence: 0 }));
		const duplicateResult = receiver.receive(createFrame({ sequence: 0 }));
		const nextResult = receiver.receive(createFrame({ sequence: 1 }));
		const olderResult = receiver.receive(createFrame({ sequence: 0 }));

		expect(duplicateResult).toEqual({
			ok: false,
			reason: 'duplicate_sequence',
			status: 'active',
		});
		expect(nextResult).toEqual({ ok: true, status: 'active' });
		expect(olderResult).toEqual({
			ok: false,
			reason: 'stale_sequence',
			status: 'active',
		});
		expect(acceptedFrames.map((frame: BridgeIntakeFrame): number => frame.sequence)).toEqual([
			0, 1,
		]);
		expect(
			droppedFrames.map((drop: BridgeIntakeReceiveDrop): BridgeIntakeReceiveDrop['reason'] => {
				return drop.reason;
			}),
		).toEqual(['duplicate_sequence', 'stale_sequence']);
	});

	test('rejects frames after close before mutation', () => {
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeReceiveDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
			onDroppedFrame: (drop: BridgeIntakeReceiveDrop): void => {
				droppedFrames.push(drop);
			},
		});

		receiver.receive(createFrame({ sequence: 0 }));
		const closeResult = receiver.receive({
			kind: 'close',
			streamId: 'stream-1',
			generation: 1,
			sequence: 1,
		});
		const postCloseResult = receiver.receive(createFrame({ sequence: 2 }));

		expect(closeResult).toEqual({ ok: true, status: 'closed' });
		expect(postCloseResult).toEqual({
			ok: false,
			reason: 'closed',
			status: 'closed',
		});
		expect(
			acceptedFrames.map((frame: BridgeIntakeFrame): BridgeIntakeFrame['kind'] => frame.kind),
		).toEqual(['snapshot', 'close']);
		expect(
			droppedFrames.map((drop: BridgeIntakeReceiveDrop): BridgeIntakeReceiveDrop['reason'] => {
				return drop.reason;
			}),
		).toEqual(['closed']);
	});
});

interface CreateFrameProps {
	readonly generation?: number;
	readonly sequence: number;
	readonly value?: unknown;
}

function createFrame(props: CreateFrameProps): BridgeIntakeFrame {
	return {
		kind: 'snapshot',
		streamId: 'stream-1',
		generation: props.generation ?? 1,
		sequence: props.sequence,
		payload: { value: props.value ?? props.sequence },
	};
}
