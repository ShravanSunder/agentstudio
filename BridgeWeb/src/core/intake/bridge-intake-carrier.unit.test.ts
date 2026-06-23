import { describe, expect, test } from 'vitest';

import type { BridgeIntakeFrame } from '../models/bridge-intake-frame.js';
import {
	installBridgeIntakeEventCarrier,
	type BridgeIntakeCarrierDrop,
} from './bridge-intake-carrier.js';
import { createBridgeIntakeReceiver } from './bridge-intake-receiver.js';

describe('bridge intake event carrier', () => {
	test('validates nonce and forwards decoded frames to the receiver', () => {
		const target = new EventTarget();
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeCarrierDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
		});
		const uninstall = installBridgeIntakeEventCarrier({
			target,
			eventName: '__bridge_intake_json',
			getNonce: () => 'nonce-1',
			receiver,
			maxFrameBytes: 512,
			onDroppedFrame: (drop: BridgeIntakeCarrierDrop): void => {
				droppedFrames.push(drop);
			},
		});

		dispatchIntake(target, createFrame({ sequence: 0 }), 'wrong-nonce');
		dispatchIntake(target, createFrame({ sequence: 0 }), 'nonce-1');
		uninstall();
		dispatchIntake(target, createFrame({ sequence: 1 }), 'nonce-1');

		expect(acceptedFrames.map((frame: BridgeIntakeFrame): number => frame.sequence)).toEqual([0]);
		expect(
			droppedFrames.map((drop: BridgeIntakeCarrierDrop): BridgeIntakeCarrierDrop['reason'] => {
				return drop.reason;
			}),
		).toEqual(['carrier_nonce_mismatch']);
	});

	test('rejects oversized JSON frames before parsing or receiver mutation', () => {
		const target = new EventTarget();
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeCarrierDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
		});
		const uninstall = installBridgeIntakeEventCarrier({
			target,
			eventName: '__bridge_intake_json',
			getNonce: () => 'nonce-1',
			receiver,
			maxFrameBytes: 16,
			onDroppedFrame: (drop: BridgeIntakeCarrierDrop): void => {
				droppedFrames.push(drop);
			},
		});

		dispatchIntake(target, createFrame({ sequence: 0 }), 'nonce-1');
		uninstall();

		expect(acceptedFrames).toHaveLength(0);
		expect(droppedFrames).toEqual([
			{
				reason: 'frame_too_large',
				byteLength: utf8ByteLength(JSON.stringify(createFrame({ sequence: 0 }))),
			},
		]);
	});

	test('measures frame limits as UTF-8 bytes instead of JavaScript string length', () => {
		const target = new EventTarget();
		const acceptedFrames: BridgeIntakeFrame[] = [];
		const droppedFrames: BridgeIntakeCarrierDrop[] = [];
		const receiver = createBridgeIntakeReceiver({
			streamId: 'stream-1',
			generation: 1,
			onFrame: (frame: BridgeIntakeFrame): void => {
				acceptedFrames.push(frame);
			},
		});
		const unicodeFrame = createFrame({ sequence: 0, value: 'é'.repeat(32) });
		const json = JSON.stringify(unicodeFrame);
		const uninstall = installBridgeIntakeEventCarrier({
			target,
			eventName: '__bridge_intake_json',
			getNonce: () => 'nonce-1',
			receiver,
			maxFrameBytes: json.length + 16,
			onDroppedFrame: (drop: BridgeIntakeCarrierDrop): void => {
				droppedFrames.push(drop);
			},
		});

		dispatchIntake(target, unicodeFrame, 'nonce-1');
		uninstall();

		expect(utf8ByteLength(json)).toBeGreaterThan(json.length + 16);
		expect(acceptedFrames).toHaveLength(0);
		expect(droppedFrames).toEqual([
			{
				reason: 'frame_too_large',
				byteLength: utf8ByteLength(json),
			},
		]);
	});
});

interface CreateFrameProps {
	readonly sequence: number;
	readonly value?: unknown;
}

function createFrame(props: CreateFrameProps): BridgeIntakeFrame {
	return {
		kind: 'snapshot',
		streamId: 'stream-1',
		generation: 1,
		sequence: props.sequence,
		payload: { value: props.value ?? props.sequence },
	};
}

function dispatchIntake(target: EventTarget, frame: BridgeIntakeFrame, nonce: string): void {
	target.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				nonce,
				json: JSON.stringify(frame),
			},
		}),
	);
}

function utf8ByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}
