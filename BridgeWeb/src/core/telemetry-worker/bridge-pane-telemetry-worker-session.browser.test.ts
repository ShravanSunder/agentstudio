// oxlint-disable unicorn/require-post-message-target-origin -- MessagePort.postMessage does not accept targetOrigin.
import { describe, expect, it, vi } from 'vitest';

import {
	createBridgePaneTelemetryWorkerSession,
	type BridgeTelemetryWorkerLike,
} from './bridge-pane-telemetry-worker-session.js';
import type { BridgeTelemetryWorkerBootstrap } from './bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetryWorkerPortReply } from './bridge-telemetry-worker-entry.js';
import { createBridgeTelemetryWorkerProducer } from './bridge-telemetry-worker-producer.js';

function makeBrowserBootstrap(): BridgeTelemetryWorkerBootstrap {
	return {
		enabledScopes: ['web'],
		endpointUrl: 'agentstudio://telemetry/batch',
		telemetryCapability: 'telemetry-capability-browser-01234567',
		telemetryCapabilityDigest: 'telemetry-digest-browser-0123456789',
		telemetrySessionId: 'telemetry-session-browser-lifecycle',
		policy: {
			initialControlCredits: 2,
			initialSampleCredits: 2,
			compactSampleMaxEncodedBytes: 1_024,
			producerLossKeyCap: 16,
			producerPreReadyBufferMaxBytes: 4 * 1024,
			producerPreReadyBufferMaxSamples: 2,
			workerBufferMaxBytes: 8_192,
			workerBufferMaxSamples: 8,
			batchMaxBytes: 4_096,
			batchMaxSamples: 4,
			outboxMaxBytes: 8_192,
			outboxMaxCount: 2,
			maxRetryAttempts: 2,
			drainTimeoutMilliseconds: 2_000,
			minimumFlushIntervalMilliseconds: 0,
		},
	};
}

function nextPortReply(port: MessagePort): Promise<BridgeTelemetryWorkerPortReply> {
	return new Promise((resolve) => {
		port.addEventListener(
			'message',
			(event: MessageEvent<BridgeTelemetryWorkerPortReply>): void => resolve(event.data),
			{ once: true },
		);
		port.start();
	});
}

function attachProducer(port: MessagePort): void {
	const producer = createBridgeTelemetryWorkerProducer({
		initialSampleCredits: 0,
		initialControlCredits: 0,
		send: (message): void => port.postMessage(message),
	});
	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		producer.acceptWorkerCommand(event.data);
	});
	port.start();
}

describe('pane telemetry worker browser lifecycle', () => {
	it('constructs no Worker or MessageChannel when telemetry is disabled', () => {
		const createWorker = vi.fn<() => BridgeTelemetryWorkerLike>();
		const createMessageChannel = vi.fn<() => MessageChannel>();

		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: null,
			createWorker,
			createMessageChannel,
		});

		expect(session).toBeNull();
		expect(createWorker).not.toHaveBeenCalled();
		expect(createMessageChannel).not.toHaveBeenCalled();
	});

	it('keeps one real worker session across comm rotation and terminates after the drain ack', async () => {
		const realWorker = new Worker(new URL('./bridge-telemetry-worker-entry.ts', import.meta.url), {
			type: 'module',
		});
		const terminate = vi.fn((): void => realWorker.terminate());
		const worker: BridgeTelemetryWorkerLike = {
			postMessage: (message, transfer): void => realWorker.postMessage(message, transfer),
			terminate,
			addEventListener: (type, listener): void => realWorker.addEventListener(type, listener),
		};
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBrowserBootstrap(),
			createWorker: () => worker,
		});
		if (session === null) throw new Error('Expected enabled telemetry session');
		const initialCommPort = session.commProducerPort;
		attachProducer(initialCommPort);
		const initialCommReady = nextPortReply(initialCommPort);

		expect(await initialCommReady).toMatchObject({ type: 'producer.ready' });
		const initialSnapshot = await session.snapshot();
		expect(session.status()).toBe('active');
		expect(initialSnapshot.producers.comm?.generation).toBe(1);
		const telemetrySessionId = session.telemetrySessionId;

		const replacementCommPort = session.replaceCommProducerPort();
		attachProducer(replacementCommPort);
		expect(await nextPortReply(replacementCommPort)).toMatchObject({ type: 'producer.ready' });
		const rotatedSnapshot = await session.snapshot();

		expect(session.telemetrySessionId).toBe(telemetrySessionId);
		expect(rotatedSnapshot.producers.comm?.generation).toBe(2);
		expect(terminate).not.toHaveBeenCalled();

		const nonterminalDrain = await session.drain();
		expect(nonterminalDrain).toMatchObject({
			type: 'drained',
			proofEligible: true,
			settlementDisposition: 'reopened',
			requiredLossCount: 0,
			optionalLossCount: 0,
			sequenceGapCount: 0,
			producerHighWatermarks: { main: 0, comm: 0 },
		});
		expect(session.status()).toBe('active');
		expect(terminate).not.toHaveBeenCalled();

		const terminalDrain = await session.drainAndClose();

		expect(terminalDrain).toMatchObject({
			type: 'drained',
			proofEligible: true,
			settlementDisposition: 'closed',
			requiredLossCount: 0,
			optionalLossCount: 0,
			sequenceGapCount: 0,
			producerHighWatermarks: { main: 0, comm: 0 },
		});
		expect(session.status()).toBe('closed');
		expect(terminate).toHaveBeenCalledOnce();
		initialCommPort.close();
		replacementCommPort.close();
	});
});
