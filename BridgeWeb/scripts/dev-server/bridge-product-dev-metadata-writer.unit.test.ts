import { EventEmitter } from 'node:events';

import { describe, expect, test } from 'vitest';

import type { BridgeProductFrameAcknowledgementRequest } from '../../src/core/comm-worker/bridge-product-frame-acknowledgement-contracts.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import type { BridgeProductDevWritableResponse } from './bridge-product-dev-http.js';
import { BridgeProductDevMetadataWriter } from './bridge-product-dev-metadata-writer.js';

describe('Bridge product dev metadata writer', () => {
	test('releases exactly one queued frame after each exact observation', async () => {
		// Arrange
		const response = new ControlledWritableResponse();
		const writer = makeWriter(response);

		// Act
		const first = writer.writeMetadataFrame({
			kind: 'metadataStream.accepted',
			resumeDisposition: 'snapshot_required',
		});
		const second = writer.writeMetadataFrame({
			code: 'internal',
			kind: 'metadataStream.error',
			retryable: false,
			safeMessage: null,
		});
		await nextEventTurn();

		// Assert
		expect(response.writes).toHaveLength(1);
		expect(writer.snapshot().waiterCount).toBe(1);
		expect(writer.observe(metadataObservation(0))).toBe('accepted');
		await first;
		await nextEventTurn();
		expect(response.writes).toHaveLength(2);
		expect(writer.observe(metadataObservation(1))).toBe('accepted');
		await second;
		expect(writer.observe(metadataObservation(1))).toBe('idempotentReplay');
	});

	test('orders frames behind backpressure and stops the queued tail on close', async () => {
		const response = new ControlledWritableResponse();
		const writer = makeWriter(response);

		const accepted = writer.writeMetadataFrame({
			kind: 'metadataStream.accepted',
			resumeDisposition: 'snapshot_required',
		});
		await nextEventTurn();
		writer.observe(metadataObservation(0));
		await accepted;
		response.applyBackpressure = true;
		const drained = writer.writeMetadataFrame({
			code: 'internal',
			kind: 'metadataStream.error',
			retryable: false,
			safeMessage: null,
		});
		await nextEventTurn();

		expect(response.writes).toHaveLength(2);
		expect(writer.streamSequence).toBe(0);
		response.drain();
		writer.observe(metadataObservation(1));
		await drained;
		expect(writer.streamSequence).toBe(1);

		response.applyBackpressure = true;
		const blockedByClose = writer.writeMetadataFrame({
			code: 'internal',
			kind: 'metadataStream.error',
			retryable: false,
			safeMessage: null,
		});
		const queued = writer.writeMetadataFrame({
			code: 'internal',
			kind: 'metadataStream.error',
			retryable: false,
			safeMessage: null,
		});
		await nextEventTurn();

		expect(response.writes).toHaveLength(3);
		expect(writer.streamSequence).toBe(1);
		response.close();
		writer.cancel();

		await expect(blockedByClose).rejects.toThrow(/closed|cancelled/u);
		await expect(queued).rejects.toThrow(/closed|cancelled/u);
		expect(response.writes).toHaveLength(3);
		expect(writer.streamSequence).toBe(1);
		const decoder = new BridgeProductMetadataFrameDecoder();
		const frames = response.writes.flatMap((bytes) => decoder.push(bytes));
		expect(frames.map((frame) => frame.streamSequence)).toEqual([0, 1, 2]);
	});
});

function makeWriter(response: ControlledWritableResponse): BridgeProductDevMetadataWriter {
	return new BridgeProductDevMetadataWriter({
		metadataStreamId: 'metadata-stream-1',
		paneSessionId: 'pane-session-1',
		response,
		workerInstanceId: 'worker-instance-1',
	});
}

function metadataObservation(
	streamSequence: number,
): Extract<BridgeProductFrameAcknowledgementRequest, { readonly streamKind: 'metadata' }> {
	return {
		kind: 'stream.frameObserved',
		metadataStreamId: 'metadata-stream-1',
		paneSessionId: 'pane-session-1',
		streamKind: 'metadata',
		streamSequence,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-1',
	};
}

class ControlledWritableResponse extends EventEmitter implements BridgeProductDevWritableResponse {
	applyBackpressure = false;
	destroyed = false;
	readonly writes: Uint8Array[] = [];

	write(bytes: Uint8Array): boolean {
		this.writes.push(Uint8Array.from(bytes));
		return !this.applyBackpressure;
	}

	end(): void {
		this.close();
	}

	drain(): void {
		this.applyBackpressure = false;
		this.emit('drain');
	}

	close(): void {
		this.destroyed = true;
		this.emit('close');
	}
}

async function nextEventTurn(): Promise<void> {
	await new Promise<void>((resolve): void => {
		setImmediate(resolve);
	});
}
