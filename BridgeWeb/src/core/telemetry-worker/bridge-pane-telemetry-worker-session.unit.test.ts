import { describe, expect, it, vi } from 'vitest';

import {
	createBridgePaneTelemetryWorkerSession,
	type BridgeTelemetryWorkerLike,
} from './bridge-pane-telemetry-worker-session.js';
import {
	bridgeTelemetryWorkerControlRequestSchema,
	bridgeTelemetryWorkerProducerMessageSchema,
	type BridgeTelemetryWorkerProducerMessage,
} from './bridge-telemetry-worker-contracts.js';
import {
	makeBootstrap,
	makeDrainResult,
	makeWorkerSnapshot,
	nextPortReply,
} from './bridge-telemetry-worker.unit.test-support.js';

describe('pane telemetry worker session', () => {
	it('constructs no Worker or MessagePorts when telemetry is disabled', () => {
		const createWorker = vi.fn<() => BridgeTelemetryWorkerLike>();
		const createMessageChannel = vi.fn<() => MessageChannel>();

		expect(
			createBridgePaneTelemetryWorkerSession({
				bootstrap: null,
				createWorker,
				createMessageChannel,
			}),
		).toBeNull();
		expect(createWorker).not.toHaveBeenCalled();
		expect(createMessageChannel).not.toHaveBeenCalled();
	});

	it('creates one Worker and two dedicated producer channels when enabled', () => {
		const postMessage = vi.fn<(message: unknown, transfer: readonly Transferable[]) => void>();
		const terminate = vi.fn<() => void>();
		const createWorker = (): BridgeTelemetryWorkerLike => ({ postMessage, terminate });
		const createdChannels: MessageChannel[] = [];
		const createMessageChannel = (): MessageChannel => {
			const channel = new MessageChannel();
			createdChannels.push(channel);
			return channel;
		};

		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker,
			createMessageChannel,
		});
		expect(session).not.toBeNull();
		expect(createdChannels).toHaveLength(2);
		expect(postMessage).toHaveBeenCalledTimes(1);
		const [message, transfer] = postMessage.mock.calls[0] ?? [];
		expect(message).toMatchObject({
			type: 'telemetry.bootstrap',
			bootstrap: { telemetrySessionId: 'telemetry-session-entry' },
		});
		expect(JSON.stringify(message)).not.toContain('product-capability-0123456789abcdef');
		expect(transfer).toEqual([createdChannels[0]?.port1, createdChannels[1]?.port1]);
		session?.dispose();
		expect(terminate).toHaveBeenCalledTimes(1);
	});

	it('waits for worker readiness before granting producer authority', () => {
		const workerListeners: Record<
			'error' | 'message' | 'messageerror',
			Array<(event: Event) => void>
		> = {
			error: [],
			message: [],
			messageerror: [],
		};
		const worker = {
			postMessage: (): void => {},
			terminate: (): void => {},
			addEventListener: (
				type: 'error' | 'message' | 'messageerror',
				listener: (event: Event) => void,
			): void => {
				workerListeners[type].push(listener);
			},
		};
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => worker,
		});
		if (session === null) return;

		expect(
			session.mainProducer.record({
				type: 'diagnostic',
				code: 'buffer_bytes',
				timestampMilliseconds: 1,
				value: 0,
			}).disposition,
		).toBe('loss_recorded');

		workerListeners.message[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.health',
					status: 'ready',
					message: 'Telemetry worker ready.',
				},
			}),
		);
		expect(session.status()).toBe('active');
		session.dispose();
	});

	it('replays a required main sample recorded before producer ready without loss', async () => {
		const createdChannels: MessageChannel[] = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({ postMessage: (): void => {}, terminate: (): void => {} }),
			createMessageChannel: (): MessageChannel => {
				const channel = new MessageChannel();
				createdChannels.push(channel);
				return channel;
			},
		});
		if (session === null) return;
		const mainChannel = createdChannels[0];
		if (mainChannel === undefined) return;
		const requiredStartupSample = {
			type: 'interaction.lifecycle',
			stage: 'demand_issued',
			timestampMilliseconds: 1,
			surface: 'review',
			interactionSequence: 1,
			attemptId: 'attempt-startup-main',
		} as const;
		const replayedMessage = nextProducerMessage(mainChannel.port1);

		expect(session.mainProducer.record(requiredStartupSample)).toEqual({
			disposition: 'retained',
			sequence: 1,
		});
		expect(session.mainProducer.snapshot()).toMatchObject({
			pendingLossRange: null,
			retainedPreReadyRequiredSampleCount: 1,
		});

		mainChannel.port1.postMessage({
			type: 'producer.ready',
			generation: 1,
			initialSampleCredits: 1,
			initialControlCredits: 1,
		});

		expect(await replayedMessage).toEqual({
			type: 'sample',
			sequence: 1,
			sample: requiredStartupSample,
		});
		expect(session.mainProducer.snapshot()).toMatchObject({
			pendingLossRange: null,
			retainedPreReadyRequiredSampleCount: 0,
		});
		session.dispose();
	});

	it('keeps snapshot and drain nonterminal before drainAndClose terminates the worker', async () => {
		const postedMessages: unknown[] = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const terminate = vi.fn<() => void>();
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message): void => {
					postedMessages.push(message);
				},
				terminate,
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);

		const snapshot = session.snapshot();
		const snapshotRequest = bridgeTelemetryWorkerControlRequestSchema.parse(postedMessages.at(-1));
		expect(snapshotRequest).toMatchObject({ type: 'telemetry.snapshot' });
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.snapshot.result',
					requestId: snapshotRequest.requestId,
					snapshot: makeWorkerSnapshot(),
				},
			}),
		);
		expect(await snapshot).toEqual(makeWorkerSnapshot());
		expect(terminate).not.toHaveBeenCalled();
		expect(session.status()).toBe('active');

		const nonterminalDrain = session.drain();
		const nonterminalDrainRequest = bridgeTelemetryWorkerControlRequestSchema.parse(
			postedMessages.at(-1),
		);
		expect(nonterminalDrainRequest).toMatchObject({ type: 'telemetry.drain' });
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.drained',
					requestId: nonterminalDrainRequest.requestId,
					result: makeDrainResult(),
				},
			}),
		);
		expect(await nonterminalDrain).toEqual(makeDrainResult());
		expect(terminate).not.toHaveBeenCalled();
		expect(session.status()).toBe('active');

		const terminalDrain = session.drainAndClose();
		const drainRequest = bridgeTelemetryWorkerControlRequestSchema.parse(postedMessages.at(-1));
		expect(drainRequest).toMatchObject({ type: 'telemetry.drainAndClose' });
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.drainedAndClosed',
					requestId: drainRequest.requestId,
					result: makeDrainResult(),
				},
			}),
		);

		expect(await terminalDrain).toEqual(makeDrainResult());
		expect(terminate).toHaveBeenCalledTimes(1);
		expect(session.status()).toBe('closed');
	});

	it('does not alias a pending nonterminal drain with terminal close intent', async () => {
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (): void => {},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);
		session.mainProducer.grantControlCredits(2);

		const nonterminalDrain = session.drain();
		const terminalDrain = session.drainAndClose();
		void nonterminalDrain.catch((): void => {});
		void terminalDrain.catch((): void => {});

		try {
			expect(terminalDrain).not.toBe(nonterminalDrain);
		} finally {
			session.dispose();
		}
	});

	it('issues a second drain without depending on a producer-owned barrier credit', async () => {
		const postedMessages: unknown[] = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message): void => {
					postedMessages.push(message);
				},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);
		session.mainProducer.grantControlCredits(1);
		const firstDrain = session.drain();
		const firstDrainRequest = bridgeTelemetryWorkerControlRequestSchema.parse(
			postedMessages.at(-1),
		);
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.drained',
					requestId: firstDrainRequest.requestId,
					result: makeDrainResult(),
				},
			}),
		);
		await firstDrain;

		const terminalDrain = session.drainAndClose();
		void terminalDrain.catch((): void => {});

		try {
			expect(postedMessages.at(-1)).toMatchObject({ type: 'telemetry.drainAndClose' });
		} finally {
			session.dispose();
		}
	});

	it('keeps snapshot and drain timeout cancellation independent', async () => {
		const postedMessages: unknown[] = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const timeoutCancellations: Array<ReturnType<typeof vi.fn<() => void>>> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message): void => {
					postedMessages.push(message);
				},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
			scheduleDrainTimeout: (): (() => void) => {
				const cancel = vi.fn<() => void>();
				timeoutCancellations.push(cancel);
				return cancel;
			},
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);
		session.mainProducer.grantControlCredits(1);
		const snapshot = session.snapshot();
		const drain = session.drain();
		void drain.catch((): void => {});
		const snapshotRequest = bridgeTelemetryWorkerControlRequestSchema.parse(postedMessages[1]);
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.snapshot.result',
					requestId: snapshotRequest.requestId,
					snapshot: makeWorkerSnapshot(),
				},
			}),
		);

		try {
			await snapshot;
			expect(timeoutCancellations[0]).toHaveBeenCalledOnce();
			expect(timeoutCancellations[1]).not.toHaveBeenCalled();
		} finally {
			session.dispose();
		}
	});

	it('creates a fresh transferable comm producer port without replacing the telemetry worker', () => {
		const postedMessages: Array<{
			readonly message: unknown;
			readonly transfer: readonly Transferable[];
		}> = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message, transfer): void => {
					postedMessages.push({ message, transfer });
				},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);

		const producerPort = session.replaceCommProducerPort();

		expect(postedMessages).toHaveLength(2);
		expect(postedMessages[1]?.message).toMatchObject({
			type: 'telemetry.producer.replace',
			producerId: 'comm',
		});
		expect(postedMessages[1]?.transfer).toHaveLength(1);
		producerPort.close();
		session.dispose();
	});

	it('rejects comm replacement while a drain is queued or running', async () => {
		const postedMessages: unknown[] = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const createdChannels: MessageChannel[] = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message): void => {
					postedMessages.push(message);
				},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
			createMessageChannel: (): MessageChannel => {
				const channel = new MessageChannel();
				createdChannels.push(channel);
				return channel;
			},
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);
		const snapshot = session.snapshot();
		const queuedDrain = session.drain();
		void snapshot.catch((): void => {});
		void queuedDrain.catch((): void => {});

		expect(() => session.replaceCommProducerPort()).toThrow(
			'Telemetry worker must be active before replacing a producer.',
		);
		expect(createdChannels).toHaveLength(2);

		const snapshotRequest = bridgeTelemetryWorkerControlRequestSchema.parse(postedMessages.at(-1));
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.snapshot.result',
					requestId: snapshotRequest.requestId,
					snapshot: makeWorkerSnapshot(),
				},
			}),
		);
		await snapshot;
		expect(session.status()).toBe('draining');
		expect(() => session.replaceCommProducerPort()).toThrow(
			'Telemetry worker must be active before replacing a producer.',
		);

		session.dispose();
		await expect(queuedDrain).rejects.toThrow('Telemetry worker session was disposed.');
	});

	it('preserves FIFO across intervening snapshot and drain operations', async () => {
		const postedMessages: unknown[] = [];
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (message): void => {
					postedMessages.push(message);
				},
				terminate: (): void => {},
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);

		const firstSnapshot = session.snapshot();
		const drain = session.drain();
		const secondSnapshot = session.snapshot();
		const firstSnapshotRequest = bridgeTelemetryWorkerControlRequestSchema.parse(
			postedMessages.at(-1),
		);
		expect(firstSnapshot).not.toBe(secondSnapshot);
		expect(
			postedMessages
				.slice(1)
				.map((message) => bridgeTelemetryWorkerControlRequestSchema.parse(message).type),
		).toEqual(['telemetry.snapshot']);

		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.snapshot.result',
					requestId: firstSnapshotRequest.requestId,
					snapshot: makeWorkerSnapshot(),
				},
			}),
		);
		await firstSnapshot;
		const drainRequest = bridgeTelemetryWorkerControlRequestSchema.parse(postedMessages.at(-1));
		expect(drainRequest.type).toBe('telemetry.drain');
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.drained',
					requestId: drainRequest.requestId,
					result: makeDrainResult(),
				},
			}),
		);
		await drain;
		const secondSnapshotRequest = bridgeTelemetryWorkerControlRequestSchema.parse(
			postedMessages.at(-1),
		);
		expect(secondSnapshotRequest.type).toBe('telemetry.snapshot');
		expect(secondSnapshotRequest.requestId).not.toBe(firstSnapshotRequest.requestId);
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: {
					type: 'telemetry.snapshot.result',
					requestId: secondSnapshotRequest.requestId,
					snapshot: makeWorkerSnapshot(),
				},
			}),
		);
		await secondSnapshot;
		session.dispose();
	});

	it('fails active and queued controls on fatal health without scheduling later timers', async () => {
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const scheduleDrainTimeout = vi.fn((): (() => void) => (): void => {});
		const terminate = vi.fn<() => void>();
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (): void => {},
				terminate,
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
			scheduleDrainTimeout,
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);
		const snapshot = session.snapshot();
		const drain = session.drain();
		const snapshotRejection = expect(snapshot).rejects.toThrow(
			'Telemetry worker reported degraded health.',
		);
		const drainRejection = expect(drain).rejects.toThrow(
			'Telemetry worker reported degraded health.',
		);
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'degraded', message: 'failed' },
			}),
		);

		await Promise.all([snapshotRejection, drainRejection]);
		expect(session.status()).toBe('failed');
		expect(terminate).toHaveBeenCalledOnce();
		expect(scheduleDrainTimeout).toHaveBeenCalledOnce();
		await expect(session.snapshot()).rejects.toThrow('Telemetry worker session has failed.');
		await expect(session.drain()).rejects.toThrow('Telemetry worker session has failed.');
		expect(scheduleDrainTimeout).toHaveBeenCalledOnce();
	});

	it('fails proof and terminates when the terminal drain acknowledgement is missing', async () => {
		const scheduledTimeouts: Array<() => void> = [];
		const terminate = vi.fn<() => void>();
		const workerListeners: Array<(event: MessageEvent<unknown>) => void> = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({
				postMessage: (): void => {},
				terminate,
				addEventListener: (type, listener): void => {
					if (type === 'message') {
						workerListeners.push((event): void => listener(event));
					}
				},
			}),
			scheduleDrainTimeout: (callback, delayMilliseconds): (() => void) => {
				expect(delayMilliseconds).toBe(1_000);
				scheduledTimeouts.push(callback);
				return (): void => {};
			},
		});
		if (session === null) return;
		workerListeners[0]?.(
			new MessageEvent('message', {
				data: { type: 'telemetry.health', status: 'ready', message: 'ready' },
			}),
		);

		const drain = session.drainAndClose();
		const rejectedDrain = expect(drain).rejects.toThrow(
			'Telemetry worker drain acknowledgement timed out.',
		);
		scheduledTimeouts[0]?.();

		await rejectedDrain;
		expect(session.status()).toBe('failed');
		expect(terminate).toHaveBeenCalledOnce();
	});

	it('applies only strict sample and control credit grants to the main producer', async () => {
		const createdChannels: MessageChannel[] = [];
		const session = createBridgePaneTelemetryWorkerSession({
			bootstrap: makeBootstrap(),
			createWorker: () => ({ postMessage: (): void => {}, terminate: (): void => {} }),
			createMessageChannel: (): MessageChannel => {
				const channel = new MessageChannel();
				createdChannels.push(channel);
				return channel;
			},
		});
		if (session === null) return;
		const initialSnapshot = session.mainProducer.snapshot();

		const mainChannel = createdChannels[0];
		if (mainChannel === undefined) return;
		const sampleGrantDelivered = nextPortReply(mainChannel.port2);
		mainChannel.port1.postMessage({
			type: 'producer.credit-grant',
			sampleCredits: 3,
		});
		await sampleGrantDelivered;
		const controlGrantDelivered = nextPortReply(mainChannel.port2);
		mainChannel.port1.postMessage({
			type: 'producer.credit-grant',
			controlCredits: 2,
		});
		await controlGrantDelivered;
		const malformedGrantDelivered = nextPortReply(mainChannel.port2);
		mainChannel.port1.postMessage({
			type: 'producer.credit-grant',
			sampleCredits: 1,
			controlCredits: 1,
		});
		await malformedGrantDelivered;

		expect(session.mainProducer.snapshot()).toMatchObject({
			availableSampleCredits: initialSnapshot.availableSampleCredits + 3,
			availableControlCredits: initialSnapshot.availableControlCredits + 2,
		});
		session.dispose();
	});
});

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
