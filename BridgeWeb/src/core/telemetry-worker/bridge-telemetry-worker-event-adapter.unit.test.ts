import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	bridgeTelemetryCompactSampleSchema,
	bridgeTelemetryWorkerProducerMessageSchema,
	type BridgeTelemetryWorkerProducerMessage,
} from './bridge-telemetry-worker-contracts.js';
import { createBridgeTelemetryWorkerEventProducer } from './bridge-telemetry-worker-event-adapter.js';

describe('Bridge telemetry worker event producer', () => {
	test('replays a required event recorded before producer ready', async () => {
		const channel = new MessageChannel();
		const nextMessage = nextProducerMessage(channel.port1);
		const producer = createBridgeTelemetryWorkerEventProducer({
			enabledScopes: new Set(['web']),
			now: (): number => 42,
			port: channel.port2,
			preReadyRequiredSampleCapacity: 1,
			preReadyRequiredSampleMaxEncodedBytes: 4 * 1024,
		});
		const requiredEvent = makeEvent('hot');

		producer.record(requiredEvent);
		channel.port1.postMessage({
			type: 'producer.ready',
			generation: 1,
			initialSampleCredits: 1,
			initialControlCredits: 1,
		});

		expect(await nextMessage).toEqual({
			type: 'sample',
			sequence: 1,
			sample: {
				type: 'event.required',
				timestampMilliseconds: 42,
				sample: requiredEvent,
			},
		});
		producer.close();
		channel.port1.close();
	});

	test('keeps an optional pre-ready event bodyless and reports exact loss', async () => {
		const channel = new MessageChannel();
		const nextMessage = nextProducerMessage(channel.port1);
		const producer = createBridgeTelemetryWorkerEventProducer({
			enabledScopes: new Set(['web']),
			now: (): number => 42,
			port: channel.port2,
			preReadyRequiredSampleCapacity: 1,
			preReadyRequiredSampleMaxEncodedBytes: 4 * 1024,
		});

		producer.record(makeEvent('best_effort'));
		channel.port1.postMessage({
			type: 'producer.ready',
			generation: 1,
			initialSampleCredits: 1,
			initialControlCredits: 1,
		});

		const lossMessage = await nextMessage;
		expect(lossMessage).toEqual({
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 1,
			requiredCount: 0,
			optionalCount: 1,
			reason: 'queue_saturated',
		});
		expect(JSON.stringify(lossMessage)).not.toContain(
			'performance.bridge.web.selected_content_painted',
		);
		producer.close();
		channel.port1.close();
	});

	test.each([
		['hot', 'event.required'],
		['warm', 'event.required'],
		['best_effort', 'event.optional'],
	] as const)('maps %s events to the structural %s class', async (priority, expectedType) => {
		const channel = new MessageChannel();
		const nextMessage = nextProducerMessage(channel.port1);
		const producer = createBridgeTelemetryWorkerEventProducer({
			enabledScopes: new Set(['web']),
			now: (): number => 42,
			port: channel.port2,
			preReadyRequiredSampleCapacity: 4,
			preReadyRequiredSampleMaxEncodedBytes: 4 * 1024,
		});
		const readyDelivered = new Promise<void>((resolve): void => {
			channel.port2.addEventListener('message', (): void => resolve(), { once: true });
		});
		channel.port1.postMessage({
			type: 'producer.ready',
			generation: 1,
			initialSampleCredits: 1,
			initialControlCredits: 1,
		});
		await readyDelivered;

		producer.record(makeEvent(priority));

		expect(await nextMessage).toEqual({
			type: 'sample',
			sequence: 1,
			sample: {
				type: expectedType,
				timestampMilliseconds: 42,
				sample: makeEvent(priority),
			},
		});
		producer.close();
		channel.port1.close();
	});

	test('rejects required events smuggled into the optional class', () => {
		expect(
			bridgeTelemetryCompactSampleSchema.safeParse({
				type: 'event.optional',
				timestampMilliseconds: 1,
				sample: makeEvent('hot'),
			}).success,
		).toBe(false);
	});
});

function makeEvent(priority: 'best_effort' | 'hot' | 'warm'): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.selected_content_painted',
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.priority': priority,
		},
		numericAttributes: {},
		booleanAttributes: {},
	};
}

function nextProducerMessage(port: MessagePort): Promise<BridgeTelemetryWorkerProducerMessage> {
	return new Promise((resolve): void => {
		port.addEventListener(
			'message',
			(event: MessageEvent<unknown>): void => {
				resolve(bridgeTelemetryWorkerProducerMessageSchema.parse(event.data));
			},
			{ once: true },
		);
		port.start();
	});
}
