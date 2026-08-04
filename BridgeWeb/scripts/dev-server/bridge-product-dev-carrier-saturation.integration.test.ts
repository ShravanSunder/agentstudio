import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeCommWorkerGlobalScope } from '../../src/core/comm-worker/bridge-comm-worker-entry.js';
import type {
	BridgeProductContentDescriptor,
	BridgeProductContentKind,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { bridgePaneCommWorkerInstallSchema } from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionEvent } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import type {
	BridgeProductIdentifierPurpose,
	BridgeProductTransportSession,
	CreateBridgeProductTransportProps,
} from '../../src/core/comm-worker/bridge-product-transport.js';
import {
	LiveProductClient,
	LiveViteProductServer,
	liveViteCarrierTestTimeoutMilliseconds,
} from './bridge-product-dev-carrier-live.test-support.js';

const bridgeProductTransportModulePath = '../../src/core/comm-worker/bridge-product-transport.js';
const bridgeCommWorkerViteEntryModulePath =
	'../../src/core/comm-worker/bridge-comm-worker-vite-entry.js';

describe('Bridge product real Vite shared response admission', () => {
	let liveServer: LiveViteProductServer | null = null;

	afterEach(async (): Promise<void> => {
		await liveServer?.close();
		liveServer = null;
		vi.doUnmock(bridgeProductTransportModulePath);
		vi.unstubAllGlobals();
		vi.resetModules();
	});

	test(
		'holds four shared HTTP content responses while metadata and control continue, then reuses full capacity',
		async () => {
			liveServer = await LiveViteProductServer.start();
			const client = await LiveProductClient.connect(liveServer.baseURL);
			const nativeFetch = globalThis.fetch;
			const requestProbe = createHeldViteFetchProbe(liveServer.baseURL, nativeFetch);
			const workerScope = createDispatchableBridgeCommWorkerGlobalScope();
			let installedProductTransport: BridgeProductTransportSession | null = null;
			let productSessionOpen = (): Promise<void> =>
				Promise.reject(new Error('Vite worker entry did not install a product session.'));
			vi.doMock(bridgeProductTransportModulePath, async (importOriginal) => {
				const original =
					await importOriginal<
						typeof import('../../src/core/comm-worker/bridge-product-transport.js')
					>();
				return {
					...original,
					createBridgeProductTransport: (
						props: CreateBridgeProductTransportProps,
					): BridgeProductTransportSession => {
						productSessionOpen = (): Promise<void> => props.authority.open;
						installedProductTransport = original.createBridgeProductTransport({
							...props,
							createIdentifier: productPurposeIdentifier(),
						});
						return installedProductTransport;
					},
				};
			});
			vi.stubGlobal('fetch', requestProbe.fetch);
			vi.stubGlobal('self', workerScope.scope);
			await import(bridgeCommWorkerViteEntryModulePath);
			const productChannel = new MessageChannel();
			workerScope.dispatch(
				bridgePaneCommWorkerInstallSchema.parse({
					...client.productSessionInstallInput(),
					kind: 'bridgePaneCommWorker.install',
					productPort: productChannel.port1,
				}),
			);
			if (installedProductTransport === null) {
				throw new Error('Expected the Vite worker entry to install one product transport.');
			}
			await productSessionOpen();
			const transport: BridgeProductTransportSession = installedProductTransport;
			const source = await transport.call('file.source.current', {});
			if (source.status !== 'available') throw new Error('Expected a live File source.');
			const subscription = transport.subscribe('file.metadata', {
				interests: [{ lane: 'foreground', paths: ['README.md'] }],
				pathScope: [],
				source: source.source,
			});
			const descriptor = await waitForAvailableFileDescriptor(subscription.events);
			const metadataObservationCountBeforeContent = requestProbe.metadataObservationCount();
			const firstContentStreams = openContentBatch(transport, descriptor, 5);
			await waitForCondition(() => requestProbe.contentRequestInvocationCount() === 4);
			await waitForCondition(() => requestProbe.heldContentResponseCount() === 4);

			expect(requestProbe.contentRequestInvocationCount()).toBe(4);
			expect(requestProbe.heldContentResponseCount()).toBe(4);
			await expect(transport.call('file.source.current', {})).resolves.toMatchObject({
				status: 'available',
			});
			transport.bumpWorkerDerivationEpoch('review');
			const reviewSubscription = transport.subscribe('review.metadata', {
				interests: [],
			});
			const reviewMetadataEvent = await waitForFirstReviewMetadataEvent(reviewSubscription.events);
			expect(reviewMetadataEvent.eventKind).toBe('review.sourceAccepted');
			await waitForCondition(
				() => requestProbe.metadataObservationCount() > metadataObservationCountBeforeContent,
			);
			expect(requestProbe.metadataObservationCount()).toBeGreaterThan(
				metadataObservationCountBeforeContent,
			);
			expect(requestProbe.contentRequestInvocationCount()).toBe(4);
			expect(requestProbe.heldContentResponseCount()).toBe(4);

			requestProbe.releaseContentResponses();
			await expectCompletedContentBatch(firstContentStreams);

			requestProbe.pauseContentResponses();
			const abortedBatchStartCount = requestProbe.contentRequestInvocationCount();
			const abortedBatch = openAbortableContentBatch(transport, descriptor, 5);
			await waitForCondition(
				() => requestProbe.contentRequestInvocationCount() === abortedBatchStartCount + 4,
			);
			await waitForCondition(() => requestProbe.heldContentResponseCount() === 4);
			expect(requestProbe.contentRequestInvocationCount()).toBe(abortedBatchStartCount + 4);
			expect(requestProbe.heldContentResponseCount()).toBe(4);
			for (const abortController of abortedBatch.abortControllers) {
				abortController.abort(new DOMException('test cleanup', 'AbortError'));
			}
			requestProbe.releaseContentResponses();
			await Promise.allSettled(abortedBatch.streams.map(({ terminal }) => terminal));
			expect(requestProbe.heldContentResponseCount()).toBe(0);

			requestProbe.pauseContentResponses();
			const postAbortBatchStartCount = requestProbe.contentRequestInvocationCount();
			const postAbortContentStreams = openContentBatch(transport, descriptor, 5);
			await waitForCondition(
				() => requestProbe.contentRequestInvocationCount() === postAbortBatchStartCount + 4,
			);
			await waitForCondition(() => requestProbe.heldContentResponseCount() === 4);
			expect(requestProbe.contentRequestInvocationCount()).toBe(postAbortBatchStartCount + 4);
			expect(requestProbe.heldContentResponseCount()).toBe(4);
			requestProbe.releaseContentResponses();
			await expectCompletedContentBatch(postAbortContentStreams);

			await reviewSubscription.cancel();
			await subscription.cancel();
			expect(requestProbe.heldContentResponseCount()).toBe(0);
			productChannel.port1.close();
			productChannel.port2.close();
		},
		liveViteCarrierTestTimeoutMilliseconds,
	);
});

interface HeldViteFetchProbe {
	readonly contentRequestInvocationCount: () => number;
	readonly fetch: typeof fetch;
	readonly heldContentResponseCount: () => number;
	readonly metadataObservationCount: () => number;
	readonly pauseContentResponses: () => void;
	readonly releaseContentResponses: () => void;
}

function createHeldViteFetchProbe(baseURL: string, nativeFetch: typeof fetch): HeldViteFetchProbe {
	let contentRequestInvocationCount = 0;
	let heldContentResponseCount = 0;
	let metadataObservationCount = 0;
	let contentResponsesArePaused = true;
	let contentResponseGate = createDeferred<void>();
	const instrumentedFetch: typeof fetch = async (input, requestInit): Promise<Response> => {
		const requestURL = absoluteRequestURL(input, baseURL);
		if (requestURL.pathname === '/__bridge-product/content') {
			contentRequestInvocationCount += 1;
		}
		if (requestURL.pathname === '/__bridge-product/command') {
			const request = parseRequestInitBody(requestInit);
			if (isFrameObservation(request, 'metadata')) metadataObservationCount += 1;
		}
		const response = await nativeFetch(requestURL, requestInit);
		if (requestURL.pathname === '/__bridge-product/content' && contentResponsesArePaused) {
			heldContentResponseCount += 1;
			try {
				await contentResponseGate.promise;
			} finally {
				heldContentResponseCount -= 1;
			}
		}
		return response;
	};
	return {
		contentRequestInvocationCount: (): number => contentRequestInvocationCount,
		fetch: instrumentedFetch,
		heldContentResponseCount: (): number => heldContentResponseCount,
		metadataObservationCount: (): number => metadataObservationCount,
		pauseContentResponses: (): void => {
			if (contentResponsesArePaused || heldContentResponseCount !== 0) {
				throw new Error('Content responses cannot be paused from the current probe state.');
			}
			contentResponsesArePaused = true;
			contentResponseGate = createDeferred<void>();
		},
		releaseContentResponses: (): void => {
			contentResponsesArePaused = false;
			contentResponseGate.resolve();
		},
	};
}

function createDispatchableBridgeCommWorkerGlobalScope(): {
	readonly dispatch: (data: unknown) => void;
	readonly scope: BridgeCommWorkerGlobalScope;
} {
	const eventTarget = new EventTarget();
	return {
		dispatch: (data: unknown): void => {
			eventTarget.dispatchEvent(new MessageEvent('message', { data }));
		},
		scope: {
			postMessage: (): void => {},
			addEventListener: (type, listener): void => {
				eventTarget.addEventListener(type, (event): void => {
					if (event instanceof MessageEvent) listener(event);
				});
			},
		},
	};
}

function absoluteRequestURL(input: RequestInfo | URL, baseURL: string): URL {
	if (input instanceof Request) return new URL(input.url, baseURL);
	return new URL(input.toString(), baseURL);
}

function isFrameObservation(value: unknown, streamKind: 'content' | 'metadata'): boolean {
	return (
		typeof value === 'object' &&
		value !== null &&
		'kind' in value &&
		value.kind === 'stream.frameObserved' &&
		'streamKind' in value &&
		value.streamKind === streamKind
	);
}

function parseRequestInitBody(requestInit: RequestInit | undefined): unknown {
	const body = requestInit?.body;
	if (body instanceof ArrayBuffer) return JSON.parse(new TextDecoder().decode(body)) as unknown;
	if (ArrayBuffer.isView(body)) return JSON.parse(new TextDecoder().decode(body)) as unknown;
	if (typeof body === 'string') return JSON.parse(body) as unknown;
	throw new Error('Expected a JSON request body.');
}

function openContentBatch(
	transport: BridgeProductTransportSession,
	descriptor: BridgeProductContentDescriptor<BridgeProductContentKind>,
	count: number,
): readonly ReturnType<BridgeProductTransportSession['openContent']>[] {
	return Array.from({ length: count }, () =>
		transport.openContent(descriptor, new AbortController().signal),
	);
}

function openAbortableContentBatch(
	transport: BridgeProductTransportSession,
	descriptor: BridgeProductContentDescriptor<BridgeProductContentKind>,
	count: number,
): {
	readonly abortControllers: readonly AbortController[];
	readonly streams: readonly ReturnType<BridgeProductTransportSession['openContent']>[];
} {
	const abortControllers = Array.from({ length: count }, () => new AbortController());
	return {
		abortControllers,
		streams: abortControllers.map((abortController) =>
			transport.openContent(descriptor, abortController.signal),
		),
	};
}

async function expectCompletedContentBatch(
	contentStreams: readonly ReturnType<BridgeProductTransportSession['openContent']>[],
): Promise<void> {
	await expect(Promise.all(contentStreams.map(({ terminal }) => terminal))).resolves.toEqual(
		expect.arrayContaining(contentStreams.map(() => expect.objectContaining({ kind: 'complete' }))),
	);
}

async function waitForAvailableFileDescriptor(
	events: AsyncIterable<BridgeProductSubscriptionEvent<'file.metadata'>>,
): Promise<BridgeProductContentDescriptor<BridgeProductContentKind>> {
	const iterator = events[Symbol.asyncIterator]();
	for (;;) {
		const next = await iterator.next();
		if (next.done) break;
		const event = next.value;
		if (
			event.eventKind === 'file.descriptorReady' &&
			event.path === 'README.md' &&
			event.availability.availabilityKind === 'available'
		) {
			return event.availability.contentDescriptor;
		}
	}
	throw new Error('Live File metadata ended before an available descriptor arrived.');
}

async function waitForFirstReviewMetadataEvent(
	events: AsyncIterable<BridgeProductSubscriptionEvent<'review.metadata'>>,
): Promise<BridgeProductSubscriptionEvent<'review.metadata'>> {
	const next = await events[Symbol.asyncIterator]().next();
	if (!next.done) return next.value;
	throw new Error('Live Review metadata ended before its first event arrived.');
}

function productPurposeIdentifier(): (purpose: BridgeProductIdentifierPurpose) => string {
	const sequenceByPurpose = new Map<BridgeProductIdentifierPurpose, number>();
	return (purpose): string => {
		const sequence = (sequenceByPurpose.get(purpose) ?? 0) + 1;
		sequenceByPurpose.set(purpose, sequence);
		return `vite-shared-${purpose}-${sequence}`;
	};
}

interface Deferred<TResult> {
	readonly promise: Promise<TResult>;
	readonly resolve: (value: TResult | PromiseLike<TResult>) => void;
}

function createDeferred<TResult>(): Deferred<TResult> {
	let resolve: Deferred<TResult>['resolve'] = (): void => {};
	const promise = new Promise<TResult>((resolvePromise): void => {
		resolve = resolvePromise;
	});
	return { promise, resolve };
}

async function waitForCondition(predicate: () => boolean): Promise<void> {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (predicate()) return;
		// oxlint-disable-next-line eslint/no-await-in-loop -- Advances one bounded live-carrier event turn.
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});
	}
	throw new Error('Timed out waiting for the bounded live carrier condition.');
}
