import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeTelemetryWorkerBootstrapSchema,
	type BridgeTelemetryCompactSample,
} from '../core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import {
	createBridgeTelemetryWorkerPortHost,
	type BridgeTelemetryWorkerPortReply,
} from '../core/telemetry-worker/bridge-telemetry-worker-entry.js';
import { createBridgeTelemetryWorkerProducer } from '../core/telemetry-worker/bridge-telemetry-worker-producer.js';
import { acceptedTransport } from '../core/telemetry-worker/bridge-telemetry-worker.unit.test-support.js';
import {
	createBridgeAppDevTelemetryBootstrapConfig,
	installBridgeAppDevTelemetryHost,
} from './bridge-app-dev-telemetry.js';

describe('Bridge app dev telemetry host', () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	test('responds to the Bridge handshake with web telemetry config', () => {
		const target = new EventTarget();
		const handshakeDetails: unknown[] = [];
		target.addEventListener('__bridge_handshake', (event: Event): void => {
			handshakeDetails.push('detail' in event ? event.detail : null);
		});
		const host = installBridgeAppDevTelemetryHost({
			createTelemetrySessionId: (): string => 'dev-telemetry-test-session',
			scenario: 'vite-dev-current-worktree',
			target,
		});

		target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

		expect(handshakeDetails).toMatchObject([
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					scenario: 'vite-dev-current-worktree',
					workerBootstrap: {
						endpointUrl: '/__bridge-dev-telemetry/batch',
						telemetrySessionId: 'dev-telemetry-test-session',
						telemetryCapability: 'dev-telemetry-capability-0123456789abcdef',
						policy: {
							initialSampleCredits: 128,
							batchMaxBytes: 64 * 1024,
							batchMaxSamples: 128,
							minimumFlushIntervalMilliseconds: 0,
						},
					},
				},
			},
		]);

		host.dispose();
	});

	test('recycles credits before the required Review reset footprint is emitted', async () => {
		const bootstrap = bridgeTelemetryWorkerBootstrapSchema.parse(
			createBridgeAppDevTelemetryBootstrapConfig(
				'vite-dev-current-worktree',
				(): string => 'dev-telemetry-review-reset-session',
			).workerBootstrap,
		);
		const mainChannel = new MessageChannel();
		const commChannel = new MessageChannel();
		const capturedBatches: Parameters<typeof acceptedTransport>[0] = [];
		const scheduledFlushes: Array<{
			readonly callback: () => Promise<void>;
			readonly delayMilliseconds: number;
		}> = [];
		const commProducer = createBridgeTelemetryWorkerProducer({
			initialSampleCredits: bootstrap.policy.initialSampleCredits,
			initialControlCredits: bootstrap.policy.initialControlCredits,
			send: (message): void => commChannel.port2.postMessage(message),
		});
		commChannel.port2.addEventListener('message', (event: MessageEvent<unknown>): void => {
			commProducer.acceptWorkerCommand(event.data);
		});
		commChannel.port2.start();
		const host = createBridgeTelemetryWorkerPortHost({
			bootstrap,
			transport: acceptedTransport(capturedBatches),
			mainPort: mainChannel.port1,
			commPort: commChannel.port1,
			scheduleFlush: (callback, delayMilliseconds): void => {
				scheduledFlushes.push({ callback, delayMilliseconds });
			},
		});

		const initialSamplesAccepted = nextAcceptedProducerSequence(
			commChannel.port2,
			bootstrap.policy.initialSampleCredits,
		);
		for (let index = 0; index < bootstrap.policy.initialSampleCredits; index += 1) {
			expect(
				commProducer.record({
					type: 'diagnostic',
					code: 'worker_queue_depth',
					timestampMilliseconds: index,
					value: index,
				}),
			).toMatchObject({ disposition: 'posted' });
		}
		await initialSamplesAccepted;
		expect(scheduledFlushes).toHaveLength(1);
		if (scheduledFlushes[0]?.delayMilliseconds === 0) {
			const initialCreditsReturned = nextSampleCreditGrant(commChannel.port2);
			await scheduledFlushes.shift()?.callback();
			expect(await initialCreditsReturned).toBe(bootstrap.policy.initialSampleCredits);
		}

		const requiredReviewResetSamples: BridgeTelemetryCompactSample[] = [
			makeRequiredReviewResetSample('source_update', 1),
		];
		for (let slice = 0; slice < 33; slice += 1) {
			requiredReviewResetSamples.push(
				makeRequiredReviewResetSample('store_action', slice + 2),
				makeRequiredReviewResetSample('content_preparation', slice + 35),
			);
		}
		const resetResults = [];
		for (const sample of requiredReviewResetSamples) {
			const expectedSequence = bootstrap.policy.initialSampleCredits + resetResults.length + 1;
			const sampleAccepted = nextAcceptedProducerSequence(commChannel.port2, expectedSequence);
			resetResults.push(commProducer.record(sample));
			commProducer.flushLossSummary();
			// oxlint-disable-next-line eslint/no-await-in-loop -- Producer sequence is an ordered wire contract.
			await sampleAccepted;
		}
		const remainingCreditsReturned = nextSampleCreditGrant(commChannel.port2);
		while (scheduledFlushes.length > 0) {
			// oxlint-disable-next-line eslint/no-await-in-loop -- Flush completion releases the next scheduled batch.
			await scheduledFlushes.shift()?.callback();
		}
		expect(await remainingCreditsReturned).toBe(
			bootstrap.policy.minimumFlushIntervalMilliseconds === 0
				? requiredReviewResetSamples.length
				: bootstrap.policy.initialSampleCredits,
		);

		expect(host.runtime.snapshot().requiredLossCount).toBe(0);
		expect(resetResults).toHaveLength(67);
		expect(resetResults.every((result) => result.disposition === 'posted')).toBe(true);
		expect(bootstrap.policy.minimumFlushIntervalMilliseconds).toBe(0);
		expect(capturedBatches).toHaveLength(2);
		expect(capturedBatches.flatMap((batch) => batch.samples)).toHaveLength(
			bootstrap.policy.initialSampleCredits + requiredReviewResetSamples.length,
		);
		expect(host.runtime.snapshot()).toMatchObject({
			proofEligible: true,
			requiredLossCount: 0,
			bufferedSampleCount: 0,
			outboxCount: 0,
			producers: { comm: { availableSampleCredits: bootstrap.policy.initialSampleCredits } },
		});

		host.dispose();
		mainChannel.port2.close();
		commChannel.port2.close();
	});

	test('does not forward script-message telemetry batches after fetch cutover', () => {
		const target = new EventTarget();
		const fetchTelemetryBatch = vi.spyOn(globalThis, 'fetch');
		const host = installBridgeAppDevTelemetryHost({
			scenario: 'vite-dev-current-worktree',
			target,
		});
		const telemetryBatch = {
			schemaVersion: 1,
			scenario: 'vite-dev-current-worktree',
			samples: [
				{
					scope: 'web',
					name: 'performance.bridge.web.first_render',
					durationMilliseconds: 12,
					traceContext: null,
					stringAttributes: {
						'agentstudio.bridge.phase': 'render',
						'agentstudio.bridge.plane': 'data',
						'agentstudio.bridge.priority': 'hot',
						'agentstudio.bridge.slice': 'review_metadata',
						'agentstudio.bridge.transport': 'intake',
					},
					numericAttributes: {},
					booleanAttributes: {},
				},
			],
		};

		target.dispatchEvent(
			new CustomEvent('__bridge_command', {
				detail: {
					jsonrpc: '2.0',
					method: 'system.bridgeTelemetry',
					params: telemetryBatch,
				},
			}),
		);

		expect(fetchTelemetryBatch).not.toHaveBeenCalled();

		host.dispose();
	});

	test('can leave handshake responses to the selected dev backend', () => {
		const target = new EventTarget();
		const handshakeDetails: unknown[] = [];
		target.addEventListener('__bridge_handshake', (event: Event): void => {
			handshakeDetails.push('detail' in event ? event.detail : null);
		});
		const host = installBridgeAppDevTelemetryHost({
			respondToHandshakeRequests: false,
			scenario: 'vite-dev-current-worktree',
			target,
		});

		target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

		expect(handshakeDetails).toEqual([]);

		host.dispose();
	});

	test('builds the expected default telemetry config', () => {
		expect(
			createBridgeAppDevTelemetryBootstrapConfig(
				'vite-dev-large-diffshub',
				(): string => 'dev-telemetry-test-session',
			),
		).toMatchObject({
			enabledScopes: ['web'],
			scenario: 'vite-dev-large-diffshub',
			workerBootstrap: {
				endpointUrl: '/__bridge-dev-telemetry/batch',
				telemetrySessionId: 'dev-telemetry-test-session',
				policy: {
					initialControlCredits: 4,
					outboxMaxCount: 4,
				},
			},
		});
	});

	test('creates a distinct telemetry session for each dev config creation', () => {
		const createTelemetrySessionId = vi
			.fn<() => string>()
			.mockReturnValueOnce('dev-telemetry-reload-1')
			.mockReturnValueOnce('dev-telemetry-reload-2');

		const firstConfig = createBridgeAppDevTelemetryBootstrapConfig(
			'vite-dev-current-worktree',
			createTelemetrySessionId,
		);
		const secondConfig = createBridgeAppDevTelemetryBootstrapConfig(
			'vite-dev-current-worktree',
			createTelemetrySessionId,
		);

		expect(firstConfig.workerBootstrap).toMatchObject({
			telemetrySessionId: 'dev-telemetry-reload-1',
		});
		expect(secondConfig.workerBootstrap).toMatchObject({
			telemetrySessionId: 'dev-telemetry-reload-2',
		});
	});
});

function makeRequiredReviewResetSample(
	phase: 'content_preparation' | 'source_update' | 'store_action',
	timestampMilliseconds: number,
): BridgeTelemetryCompactSample {
	return {
		type: 'event.required',
		timestampMilliseconds,
		sample: {
			scope: 'web',
			name: 'performance.bridge.worker.task',
			durationMilliseconds: 1,
			traceContext: null,
			stringAttributes: {
				'agentstudio.bridge.priority': 'warm',
				'agentstudio.bridge.worker.task_kind': phase,
			},
			numericAttributes: {},
			booleanAttributes: {},
		},
	};
}

function nextAcceptedProducerSequence(port: MessagePort, sequence: number): Promise<void> {
	return new Promise((resolve) => {
		const listener = (event: MessageEvent<BridgeTelemetryWorkerPortReply>): void => {
			const reply = event.data;
			if (
				reply.type !== 'producer.ingress-result' ||
				reply.result.type !== 'accepted' ||
				reply.result.sequence !== sequence
			) {
				return;
			}
			port.removeEventListener('message', listener);
			resolve();
		};
		port.addEventListener('message', listener);
		port.start();
	});
}

function nextSampleCreditGrant(port: MessagePort): Promise<number> {
	return new Promise((resolve) => {
		const listener = (event: MessageEvent<BridgeTelemetryWorkerPortReply>): void => {
			const reply = event.data;
			if (reply.type !== 'producer.credit-grant' || !('sampleCredits' in reply)) {
				return;
			}
			port.removeEventListener('message', listener);
			resolve(reply.sampleCredits);
		};
		port.addEventListener('message', listener);
		port.start();
	});
}
