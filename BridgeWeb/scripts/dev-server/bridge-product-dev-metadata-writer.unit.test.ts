import { EventEmitter } from 'node:events';

import { describe, expect, test } from 'vitest';

import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import type { BridgeProductDevWritableResponse } from './bridge-product-dev-http.js';
import { BridgeProductDevMetadataWriter } from './bridge-product-dev-metadata-writer.js';

describe('Bridge product dev metadata writer', () => {
	test('orders frames behind backpressure and stops the queued tail on close', async () => {
		const response = new ControlledWritableResponse();
		const writer = new BridgeProductDevMetadataWriter({
			metadataStreamId: 'metadata-stream-1',
			paneSessionId: 'pane-session-1',
			response,
			workerInstanceId: 'worker-instance-1',
		});

		await writer.writeMetadataFrame({
			kind: 'metadataStream.accepted',
			resumeDisposition: 'snapshot_required',
		});
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

		await expect(blockedByClose).rejects.toThrow('closed during backpressure');
		await expect(queued).rejects.toThrow('closed during backpressure');
		expect(response.writes).toHaveLength(3);
		expect(writer.streamSequence).toBe(1);
		const decoder = new BridgeProductMetadataFrameDecoder();
		const frames = response.writes.flatMap((bytes) => decoder.push(bytes));
		expect(frames.map((frame) => frame.streamSequence)).toEqual([0, 1, 2]);
	});
});

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
