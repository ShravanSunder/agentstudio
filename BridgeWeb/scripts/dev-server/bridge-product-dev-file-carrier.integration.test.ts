import { createHash, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { afterEach, describe, expect, test } from 'vitest';

import {
	bridgeProductContentRequestSchema,
	type BridgeProductFileContentDescriptor,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentStreamDecoder } from '../../src/core/comm-worker/bridge-product-content-stream-decoder.js';
import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';

const viteConfigFile = fileURLToPath(new URL('../../vite.config.ts', import.meta.url));
const liveViteCarrierTestTimeoutMilliseconds = 15_000;

describe('Bridge product real Vite carrier recovery', () => {
	let liveServer: LiveViteProductServer | null = null;

	afterEach(async (): Promise<void> => {
		await liveServer?.close();
		liveServer = null;
	});

	test(
		'reconnects, resyncs positionally, reopens, streams File content, and cancels',
		async () => {
			liveServer = await LiveViteProductServer.start();
			const client = new LiveProductClient(liveServer.baseURL);
			const opened = await client.postControl(1, { kind: 'workerSession.open', request: null });
			const source = await client.postControl(2, {
				call: { method: 'file.source.current', request: {} },
				kind: 'product.call',
				workerDerivationEpoch: 0,
			});
			if (
				source.value.kind !== 'call.completed' ||
				source.value.call.method !== 'file.source.current' ||
				source.value.call.result.status !== 'available'
			) {
				throw new Error('Expected an available live File source.');
			}

			const firstStream = await client.openStream('vite-real-stream-1', null);
			const firstAccepted = await firstStream.frames.waitFor(
				(frame) => frame.kind === 'metadataStream.accepted',
			);
			const oldSubscriptionId = 'vite-real-subscription-old';
			const oldSubscription = await client.postControl(3, {
				kind: 'subscription.open',
				subscription: {
					source: source.value.call.result.source,
					subscriptionKind: 'file.metadata',
				},
				subscriptionId: oldSubscriptionId,
				workerDerivationEpoch: 0,
			});
			if (oldSubscription.value.kind !== 'subscription.openAccepted') {
				throw new Error('Expected the old live subscription to open.');
			}
			const finalTreeWindow = await firstStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === oldSubscriptionId &&
					frame.data.subscriptionKind === 'file.metadata' &&
					frame.data.event.eventKind === 'file.treeWindow' &&
					frame.data.event.finalWindow,
			);
			const committedStreamSequence = finalTreeWindow.streamSequence;
			firstStream.close();
			await liveServer.waitForMetadataStreamClose(0);

			const replacementStream = await client.openStream(
				'vite-real-stream-2',
				committedStreamSequence,
			);
			const replacementAccepted = await replacementStream.frames.waitFor(
				(frame) => frame.kind === 'metadataStream.accepted',
			);
			const resyncRequest = bridgeProductControlRequestSchema.parse({
				...client.controlIdentity(4),
				activeSubscriptions: [
					{
						interestRevision: 0,
						interestSha256: oldSubscription.value.interestSha256,
						subscriptionId: oldSubscriptionId,
						subscriptionKind: 'file.metadata',
						workerDerivationEpoch: 0,
					},
					{
						interestRevision: 3,
						interestSha256: 'a'.repeat(64),
						subscriptionId: 'vite-real-unclaimed-review-subscription',
						subscriptionKind: 'review.metadata',
						workerDerivationEpoch: 7,
					},
				],
				kind: 'workerSession.resync',
				lastAcceptedRequestSequence: 3,
				lastAcceptedStreamSequence: committedStreamSequence,
			});
			const resync = await client.postParsedControl(resyncRequest);
			assertBridgeProductResyncReconciliationMatchesRequest({
				request: resyncRequest,
				response: resync.value,
			});
			if (resync.value.kind !== 'resync.accepted') throw new Error('Expected resync acceptance.');
			expect(resync.value.reconciliation).toEqual([
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 0,
					subscriptionId: oldSubscriptionId,
					subscriptionKind: 'file.metadata',
				},
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 7,
					subscriptionId: 'vite-real-unclaimed-review-subscription',
					subscriptionKind: 'review.metadata',
				},
			]);

			const freshSubscriptionId = 'vite-real-subscription-fresh';
			const fresh = await client.postControl(5, {
				kind: 'subscription.open',
				subscription: {
					source: source.value.call.result.source,
					subscriptionKind: 'file.metadata',
				},
				subscriptionId: freshSubscriptionId,
				workerDerivationEpoch: 0,
			});
			if (fresh.value.kind !== 'subscription.openAccepted') {
				throw new Error('Expected the fresh live subscription to open.');
			}
			const path = 'README.md';
			const targetInterestState: BridgeProductSubscriptionInterestState = {
				interests: [{ lane: 'foreground', paths: [path] }],
				pathScope: [],
				subscriptionKind: 'file.metadata',
			};
			const targetInterestSha256 = createHash('sha256')
				.update(encodeBridgeProductSubscriptionInterestState(targetInterestState))
				.digest('hex');
			const updated = await client.postControl(6, {
				baseInterestRevision: 0,
				baseInterestSha256: fresh.value.interestSha256,
				batchCount: 1,
				batchIndex: 0,
				delta: {
					add: [{ lane: 'foreground', path }],
					addPathScope: [],
					removePathScope: [],
					removePaths: [],
					subscriptionKind: 'file.metadata',
				},
				kind: 'subscription.updateBatch',
				subscriptionId: freshSubscriptionId,
				subscriptionKind: 'file.metadata',
				targetInterestRevision: 1,
				targetInterestSha256,
				totalDeltaItemCount: 1,
				updateId: 'vite-real-update-1',
				workerDerivationEpoch: 0,
			});
			expect(updated.value.kind).toBe('subscription.updateBatchAccepted');
			const descriptorFrame = await replacementStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === freshSubscriptionId &&
					frame.data.subscriptionKind === 'file.metadata' &&
					frame.data.event.eventKind === 'file.descriptorReady' &&
					frame.data.event.path === path,
			);
			const descriptorEvent =
				descriptorFrame.kind === 'subscription.data' &&
				descriptorFrame.data.subscriptionKind === 'file.metadata'
					? descriptorFrame.data.event
					: null;
			if (
				descriptorEvent?.eventKind !== 'file.descriptorReady' ||
				descriptorEvent.availability.availabilityKind !== 'available'
			) {
				throw new Error('Expected an available live File descriptor.');
			}
			const content = await client.openContent(descriptorEvent.availability.contentDescriptor);
			const cancelled = await client.postControl(7, {
				kind: 'subscription.cancel',
				subscriptionId: freshSubscriptionId,
				subscriptionKind: 'file.metadata',
				workerDerivationEpoch: 0,
			});
			const cancelledFrame = await replacementStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.cancelled' && frame.subscriptionId === freshSubscriptionId,
			);
			replacementStream.close();
			await liveServer.waitForMetadataStreamClose(1);

			expect(opened).toMatchObject({ status: 200, value: { kind: 'workerSession.accepted' } });
			expect(firstAccepted).toMatchObject({ kind: 'metadataStream.accepted', streamSequence: 0 });
			expect(replacementAccepted).toMatchObject({
				kind: 'metadataStream.accepted',
				resumeDisposition: 'snapshot_required',
				streamSequence: committedStreamSequence + 1,
			});
			expect(resync.value.metadataStreamSequenceBarrier).toBe(committedStreamSequence + 1);
			expect(content).toEqual({
				byteLength: descriptorEvent.availability.contentDescriptor.declaredByteLength,
				contentKind: 'file.content',
				status: 200,
				terminalKind: 'complete',
			});
			expect(cancelled).toMatchObject({
				status: 200,
				value: { kind: 'subscription.cancelAccepted', subscriptionId: freshSubscriptionId },
			});
			expect(cancelledFrame.streamSequence).toBeGreaterThan(replacementAccepted.streamSequence);
		},
		liveViteCarrierTestTimeoutMilliseconds,
	);
});

class LiveViteProductServer {
	readonly baseURL: string;
	readonly #metadataStreamClosures: readonly Promise<void>[];
	readonly #server: ViteDevServer;

	private constructor(props: {
		readonly baseURL: string;
		readonly metadataStreamClosures: readonly Promise<void>[];
		readonly server: ViteDevServer;
	}) {
		this.baseURL = props.baseURL;
		this.#metadataStreamClosures = props.metadataStreamClosures;
		this.#server = props.server;
	}

	static async start(): Promise<LiveViteProductServer> {
		const metadataStreamClosures: Promise<void>[] = [];
		const server = await createViteServer({
			configFile: viteConfigFile,
			logLevel: 'silent',
			plugins: [
				{
					configureServer(viteServer): void {
						viteServer.middlewares.use((request, response, next): void => {
							if (request.url?.startsWith('/__bridge-product/stream') === true) {
								metadataStreamClosures.push(
									new Promise<void>((resolve): void => {
										response.once('close', resolve);
									}),
								);
							}
							next();
						});
					},
					enforce: 'pre',
					name: 'bridge-product-live-proof-close-observer',
				},
			],
			server: { host: '127.0.0.1', port: 0, strictPort: false },
		});
		await server.listen();
		const address = server.httpServer?.address();
		if (address === undefined || address === null || typeof address === 'string') {
			await server.close();
			throw new Error('Expected a live Vite TCP address.');
		}
		return new LiveViteProductServer({
			baseURL: `http://127.0.0.1:${address.port}`,
			metadataStreamClosures,
			server,
		});
	}

	close(): Promise<void> {
		return this.#server.close();
	}

	waitForMetadataStreamClose(index: number): Promise<void> {
		const closure = this.#metadataStreamClosures[index];
		if (closure === undefined) throw new Error(`Missing metadata stream ${index} close hook.`);
		return closure;
	}
}

class LiveFrames {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #frames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#reader = reader;
	}

	async waitFor(
		predicate: (frame: BridgeProductMetadataFrame) => boolean,
	): Promise<BridgeProductMetadataFrame> {
		for (;;) {
			const existing = this.#frames.find(predicate);
			if (existing !== undefined) return existing;
			// oxlint-disable-next-line no-await-in-loop -- Protocol frames must be decoded in stream order.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Live metadata stream ended early.');
			this.#frames.push(...this.#decoder.push(chunk.value));
		}
	}
}

class LiveProductClient {
	readonly #baseURL: string;
	readonly #capability = randomBytes(32).toString('base64url');
	readonly #paneSessionId = 'vite-real-carrier-proof-pane';
	readonly #workerInstanceId = 'vite-real-carrier-proof-worker';

	constructor(baseURL: string) {
		this.#baseURL = baseURL;
	}

	controlIdentity(requestSequence: number): {
		readonly paneSessionId: string;
		readonly requestId: string;
		readonly requestSequence: number;
		readonly wireVersion: 2;
		readonly workerInstanceId: string;
	} {
		return {
			paneSessionId: this.#paneSessionId,
			requestId: `vite-real-proof-${requestSequence}`,
			requestSequence,
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: this.#workerInstanceId,
		};
	}

	postControl(
		requestSequence: number,
		request: Readonly<Record<string, unknown>>,
	): Promise<LiveControlResult> {
		return this.postParsedControl(
			bridgeProductControlRequestSchema.parse({
				...this.controlIdentity(requestSequence),
				...request,
			}),
		);
	}

	async postParsedControl(request: BridgeProductControlRequest): Promise<LiveControlResult> {
		const response = await fetch(
			`${this.#baseURL}/__bridge-product/command?scenario=current-worktree`,
			{
				body: JSON.stringify(request),
				headers: this.#headers(),
				method: 'POST',
			},
		);
		const text = await response.text();
		expect(response.status, text).toBe(200);
		return {
			status: response.status,
			value: bridgeProductControlResponseSchema.parse(JSON.parse(text) as unknown),
		};
	}

	async openStream(
		metadataStreamId: string,
		resumeFromStreamSequence: number | null,
	): Promise<LiveMetadataStream> {
		const abortController = new AbortController();
		const response = await fetch(
			`${this.#baseURL}/__bridge-product/stream?scenario=current-worktree`,
			{
				body: JSON.stringify(
					bridgeProductMetadataStreamRequestSchema.parse({
						kind: 'metadataStream.open',
						metadataStreamId,
						paneSessionId: this.#paneSessionId,
						resumeFromStreamSequence,
						wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
						workerInstanceId: this.#workerInstanceId,
					}),
				),
				headers: this.#headers(),
				method: 'POST',
				signal: abortController.signal,
			},
		);
		const failureText = response.status === 200 ? '' : await response.text();
		expect(response.status, failureText).toBe(200);
		if (response.body === null) throw new Error('Expected a live metadata body.');
		const reader = response.body.getReader();
		return {
			close: (): void => abortController.abort(),
			frames: new LiveFrames(reader),
			status: response.status,
		};
	}

	async openContent(descriptor: BridgeProductFileContentDescriptor): Promise<LiveContentResult> {
		const request = bridgeProductContentRequestSchema.parse({
			contentKind: 'file.content',
			contentRequestId: 'vite-real-content-1',
			descriptor,
			kind: 'content.open',
			leaseId: 'vite-real-lease-1',
			paneSessionId: this.#paneSessionId,
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerDerivationEpoch: 0,
			workerInstanceId: this.#workerInstanceId,
		});
		const response = await fetch(
			`${this.#baseURL}/__bridge-product/content?scenario=current-worktree`,
			{
				body: JSON.stringify(request),
				headers: this.#headers(),
				method: 'POST',
			},
		);
		expect(response.status).toBe(200);
		const decoder = new BridgeProductContentStreamDecoder(request);
		const result = await decoder.push(new Uint8Array(await response.arrayBuffer()));
		decoder.finish();
		if (result.terminal?.kind !== 'complete') {
			throw new Error('Expected the live File content stream to complete.');
		}
		return {
			byteLength: result.terminal.bytes.byteLength,
			contentKind: result.terminal.contentKind,
			status: response.status,
			terminalKind: result.terminal.kind,
		};
	}

	#headers(): HeadersInit {
		return {
			'Content-Type': 'application/json',
			'X-AgentStudio-Bridge-Product-Capability': this.#capability,
		};
	}
}

interface LiveControlResult {
	readonly status: number;
	readonly value: BridgeProductControlResponse;
}

interface LiveMetadataStream {
	readonly close: () => void;
	readonly frames: LiveFrames;
	readonly status: number;
}

interface LiveContentResult {
	readonly byteLength: number;
	readonly contentKind: string;
	readonly status: number;
	readonly terminalKind: string;
}
