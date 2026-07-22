import { createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';

import { describe, expect, test, vi } from 'vitest';

import {
	bridgeProductContentRequestSchema,
	type BridgeProductContentRequest,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import type { BridgeProductFrameAcknowledgementRequest } from '../../src/core/comm-worker/bridge-product-frame-acknowledgement-contracts.js';
import { BridgeProductDevContentProducer } from './bridge-product-dev-content-producer.js';
import type { BridgeProductDevWritableResponse } from './bridge-product-dev-http.js';
import { BridgeProductDevObservationGate } from './bridge-product-dev-observation-gate.js';

interface TestObservation {
	readonly requestId: string;
	readonly sequence: number;
}

describe('Bridge product dev observation gate', () => {
	test('releases one exact observation once and accepts an exact replay without releasing twice', async () => {
		// Arrange
		const gate = new BridgeProductDevObservationGate<TestObservation>();
		const observation = { requestId: 'metadata-stream-1', sequence: 0 };
		const release = vi.fn();
		const waitForObservation = gate.register({ observation, onObserved: release });

		// Act
		const accepted = gate.observe(observation);
		await waitForObservation;
		const replay = gate.observe(observation);

		// Assert
		expect(accepted).toBe('accepted');
		expect(replay).toBe('idempotentReplay');
		expect(release).toHaveBeenCalledTimes(1);
		expect(gate.snapshot()).toEqual({ hasOutstandingObservation: false, waiterCount: 0 });
	});

	test('rejects a foreign observation without releasing the outstanding waiter', async () => {
		// Arrange
		const gate = new BridgeProductDevObservationGate<TestObservation>();
		const observation = { requestId: 'content-request-1', sequence: 0 };
		const release = vi.fn();
		const waitForObservation = gate.register({ observation, onObserved: release });

		// Act
		const rejected = gate.observe({ requestId: 'content-request-2', sequence: 0 });
		const accepted = gate.observe(observation);
		await waitForObservation;

		// Assert
		expect(rejected).toBe('rejected');
		expect(accepted).toBe('accepted');
		expect(release).toHaveBeenCalledTimes(1);
	});

	test('keeps independent stream waiters from head-of-line blocking each other', async () => {
		// Arrange
		const metadataGate = new BridgeProductDevObservationGate<TestObservation>();
		const contentGate = new BridgeProductDevObservationGate<TestObservation>();
		const metadataObservation = { requestId: 'metadata-stream-1', sequence: 1 };
		const contentStreamObservation = { requestId: 'content-request-1', sequence: 1 };
		const metadataWaiter = metadataGate.register({ observation: metadataObservation });
		const contentWaiter = contentGate.register({ observation: contentStreamObservation });

		// Act
		contentGate.observe(contentStreamObservation);
		await contentWaiter;
		const metadataSnapshotBeforeRelease = metadataGate.snapshot();
		metadataGate.observe(metadataObservation);
		await metadataWaiter;

		// Assert
		expect(metadataSnapshotBeforeRelease).toEqual({
			hasOutstandingObservation: true,
			waiterCount: 1,
		});
	});
});

describe('Bridge product dev content producer', () => {
	test('paces every frame by exact observation and accepts replay without a second release', async () => {
		// Arrange
		const response = new TestWritableResponse();
		const request = fileContentRequest('content-request-1', 'lease-1');
		const producer = new BridgeProductDevContentProducer({ request, response });

		// Act
		const production = producer.start({
			bytes: new TextEncoder().encode('abc'),
			descriptor: request.descriptor,
			endOfSource: true,
		});
		await nextEventTurn();

		// Assert
		expect(response.writes).toHaveLength(1);
		expect(producer.observe(contentObservation(request, 0))).toBe('accepted');
		expect(producer.observe(contentObservation(request, 0))).toBe('idempotentReplay');
		await nextEventTurn();
		expect(response.writes).toHaveLength(2);
		expect(producer.observe(contentObservation(request, 1))).toBe('accepted');
		await nextEventTurn();
		expect(response.writes).toHaveLength(3);
		expect(producer.observe(contentObservation(request, 2))).toBe('accepted');
		await production;
		expect(response.didEnd).toBe(true);
		expect(producer.snapshot()).toEqual({ responseCount: 0, waiterCount: 0 });
	});

	test('does not let one blocked content response withhold another response', async () => {
		// Arrange
		const firstResponse = new TestWritableResponse();
		const secondResponse = new TestWritableResponse();
		const firstRequest = fileContentRequest('content-request-1', 'lease-1');
		const secondRequest = fileContentRequest('content-request-2', 'lease-2');
		const firstProducer = new BridgeProductDevContentProducer({
			request: firstRequest,
			response: firstResponse,
		});
		const secondProducer = new BridgeProductDevContentProducer({
			request: secondRequest,
			response: secondResponse,
		});
		const bytes = new TextEncoder().encode('abc');

		// Act
		const firstProduction = firstProducer.start({
			bytes,
			descriptor: firstRequest.descriptor,
			endOfSource: true,
		});
		const secondProduction = secondProducer.start({
			bytes,
			descriptor: secondRequest.descriptor,
			endOfSource: true,
		});
		await nextEventTurn();
		secondProducer.observe(contentObservation(secondRequest, 0));
		await nextEventTurn();

		// Assert
		expect(firstResponse.writes).toHaveLength(1);
		expect(secondResponse.writes).toHaveLength(2);
		firstProducer.cancel();
		secondProducer.cancel();
		await expect(firstProduction).rejects.toThrow('cancelled');
		await expect(secondProduction).rejects.toThrow('cancelled');
	});
});

function fileContentRequest(
	contentRequestId: string,
	leaseId: string,
): Extract<BridgeProductContentRequest, { readonly contentKind: 'file.content' }> {
	const bytes = new TextEncoder().encode('abc');
	const request = bridgeProductContentRequestSchema.parse({
		contentKind: 'file.content',
		contentRequestId,
		descriptor: {
			contentKind: 'file.content',
			declaredByteLength: bytes.byteLength,
			descriptorId: 'file-descriptor-1',
			encoding: 'utf-8',
			expectedSha256: createHash('sha256').update(bytes).digest('hex'),
			fileId: 'file-1',
			maximumBytes: bytes.byteLength,
			source: {
				repoId: '00000000-0000-4000-8000-000000000001',
				rootRevisionToken: null,
				sourceCursor: 'cursor-1',
				sourceId: 'source-1',
				subscriptionGeneration: 1,
				worktreeId: '00000000-0000-4000-8000-000000000002',
			},
			window: {
				kind: 'prefix',
				maximumBytes: bytes.byteLength,
				maximumLines: 10_000,
				startByte: 0,
			},
		},
		kind: 'content.open',
		leaseId,
		paneSessionId: 'pane-session-1',
		wireVersion: 2,
		workerDerivationEpoch: 1,
		workerInstanceId: 'worker-instance-1',
	});
	if (request.contentKind !== 'file.content') {
		throw new Error('Expected a File content test request.');
	}
	return request;
}

function contentObservation(
	request: ReturnType<typeof fileContentRequest>,
	contentSequence: number,
): Extract<BridgeProductFrameAcknowledgementRequest, { readonly streamKind: 'content' }> {
	return {
		contentRequestId: request.contentRequestId,
		contentSequence,
		kind: 'stream.frameObserved' as const,
		leaseId: request.leaseId,
		paneSessionId: request.paneSessionId,
		streamKind: 'content' as const,
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	};
}

class TestWritableResponse extends EventEmitter implements BridgeProductDevWritableResponse {
	destroyed = false;
	didEnd = false;
	readonly writes: Uint8Array[] = [];

	write(bytes: Uint8Array): boolean {
		this.writes.push(Uint8Array.from(bytes));
		return true;
	}

	end(): void {
		this.didEnd = true;
	}
}

async function nextEventTurn(): Promise<void> {
	await new Promise<void>((resolve): void => {
		setImmediate(resolve);
	});
}
