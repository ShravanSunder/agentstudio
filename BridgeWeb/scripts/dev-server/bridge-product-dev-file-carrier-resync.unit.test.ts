import { Buffer } from 'node:buffer';
import { createServer, type Server } from 'node:http';

import { afterEach, describe, expect, test } from 'vitest';

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
import { createBridgeProductDevFileCarrier } from './bridge-product-dev-file-carrier.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const capability = Buffer.alloc(32, 11).toString('base64url');
const paneSessionId = 'resync-pane-1';
const workerInstanceId = 'resync-worker-1';

describe('Bridge product dev File carrier resync', () => {
	let server: Server | null = null;

	afterEach(async () => {
		if (server === null) return;
		server.closeAllConnections();
		await new Promise<void>((resolve): void => {
			server?.close((): void => resolve());
		});
		server = null;
	});

	test('reconnects, returns positional reopenRequired outcomes, and permits fresh ids', async () => {
		const carrier = createBridgeProductDevFileCarrier({ getProvider: async () => fakeProvider() });
		const metadataStreamClosures: Promise<void>[] = [];
		server = createServer((request, response): void => {
			const props = { request, response };
			if (request.url === '/command') void carrier.handleCommandRequest(props);
			else if (request.url === '/stream') {
				metadataStreamClosures.push(
					new Promise<void>((resolve): void => {
						response.once('close', resolve);
					}),
				);
				void carrier.handleStreamRequest(props);
			} else {
				response.statusCode = 404;
				response.end();
			}
		});
		const baseURL = await listen(server);

		await postControl(baseURL, controlRequest({ kind: 'workerSession.open', request: null }, 1));
		const sourceResponse = await postControl(
			baseURL,
			controlRequest(
				{
					call: { method: 'file.source.current', request: {} },
					kind: 'product.call',
					workerDerivationEpoch: 0,
				},
				2,
			),
		);
		if (
			sourceResponse.kind !== 'call.completed' ||
			sourceResponse.call.method !== 'file.source.current' ||
			sourceResponse.call.result.status !== 'available'
		) {
			throw new Error('Expected an available File source.');
		}
		const firstStream = await openMetadataStream(baseURL, 'stream-1', null);
		const firstFrames = new MetadataFrames(firstStream.reader);
		await firstFrames.waitForCount(1);
		const oldSubscriptionId = 'subscription-old';
		const opened = await postControl(
			baseURL,
			controlRequest(
				{
					kind: 'subscription.open',
					subscription: {
						source: sourceResponse.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId: oldSubscriptionId,
					workerDerivationEpoch: 0,
				},
				3,
			),
		);
		if (opened.kind !== 'subscription.openAccepted') {
			throw new Error('Expected old subscription acceptance.');
		}
		const beforeClose = await firstFrames.waitForCount(3);
		const lastAcceptedStreamSequence = beforeClose.at(-1)?.streamSequence ?? -1;
		firstStream.close();
		await requireMetadataStreamClosure(metadataStreamClosures, 0);

		const replacementStream = await openMetadataStream(
			baseURL,
			'stream-2',
			lastAcceptedStreamSequence,
		);
		const replacementFrames = new MetadataFrames(replacementStream.reader);
		const replacementAccepted = (await replacementFrames.waitForCount(1))[0];
		expect(replacementAccepted).toMatchObject({
			kind: 'metadataStream.accepted',
			resumeDisposition: 'snapshot_required',
			streamSequence: lastAcceptedStreamSequence + 1,
		});

		const resyncRequest = controlRequest(
			{
				activeSubscriptions: [
					{
						interestRevision: 0,
						interestSha256: opened.interestSha256,
						subscriptionId: oldSubscriptionId,
						subscriptionKind: 'file.metadata',
						workerDerivationEpoch: 0,
					},
				],
				kind: 'workerSession.resync',
				lastAcceptedRequestSequence: 3,
				lastAcceptedStreamSequence,
			},
			4,
		);
		const resynced = await postControl(baseURL, resyncRequest);
		assertBridgeProductResyncReconciliationMatchesRequest({
			request: resyncRequest,
			response: resynced,
		});
		expect(resynced).toMatchObject({
			kind: 'resync.accepted',
			metadataStreamSequenceBarrier: lastAcceptedStreamSequence + 1,
			nextExpectedRequestSequence: 5,
			reconciliation: [
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 0,
					subscriptionId: oldSubscriptionId,
					subscriptionKind: 'file.metadata',
				},
			],
		});

		const fresh = await postControl(
			baseURL,
			controlRequest(
				{
					kind: 'subscription.open',
					subscription: {
						source: sourceResponse.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId: 'subscription-fresh',
					workerDerivationEpoch: 0,
				},
				5,
			),
		);
		expect(fresh).toMatchObject({
			kind: 'subscription.openAccepted',
			subscriptionId: 'subscription-fresh',
		});
		const freshFrames = await replacementFrames.waitForCount(3);
		const freshLastStreamSequence = freshFrames.at(-1)?.streamSequence ?? -1;
		replacementStream.close();
		await requireMetadataStreamClosure(metadataStreamClosures, 1);
		const emptyListStream = await openMetadataStream(baseURL, 'stream-3', freshLastStreamSequence);
		const emptyListFrames = new MetadataFrames(emptyListStream.reader);
		await emptyListFrames.waitForCount(1);
		const emptyListRequest = controlRequest(
			{
				activeSubscriptions: [],
				kind: 'workerSession.resync',
				lastAcceptedRequestSequence: 5,
				lastAcceptedStreamSequence: freshLastStreamSequence,
			},
			6,
		);
		const emptyListResponse = await postControl(baseURL, emptyListRequest);
		expect(emptyListResponse).toMatchObject({
			kind: 'resync.accepted',
			reconciliation: [],
		});
		assertBridgeProductResyncReconciliationMatchesRequest({
			request: emptyListRequest,
			response: emptyListResponse,
		});
		const afterEmptyList = await postControl(
			baseURL,
			controlRequest(
				{
					kind: 'subscription.open',
					subscription: {
						source: sourceResponse.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId: 'subscription-after-empty-list',
					workerDerivationEpoch: 0,
				},
				7,
			),
		);
		expect(afterEmptyList).toMatchObject({
			kind: 'subscription.openAccepted',
			subscriptionId: 'subscription-after-empty-list',
		});
		emptyListStream.close();
	});
});

class MetadataFrames {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #frames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#reader = reader;
	}

	async waitForCount(count: number): Promise<readonly BridgeProductMetadataFrame[]> {
		while (this.#frames.length < count) {
			// oxlint-disable-next-line no-await-in-loop -- Protocol frames are ordered.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Metadata stream ended early.');
			this.#frames.push(...this.#decoder.push(chunk.value));
		}
		return [...this.#frames];
	}
}

function fakeProvider(): BridgeWorktreeDevProvider {
	return {
		loadWorktreeFileContent: async () => '',
		loadWorktreeFileDescriptor: async () => {
			throw new Error('Descriptor demand is outside this resync proof.');
		},
		loadWorktreeFileSurface: async () => ({
			frames: [],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			source: {
				repoId: 'legacy-repo',
				rootRevisionToken: 'revision-1',
				sourceCursor: 'cursor-1',
				sourceId: 'source-1',
				subscriptionGeneration: 1,
				worktreeId: 'legacy-worktree',
			},
			treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 0, rowHeightPixels: 24 },
		}),
	};
}

function controlRequest(
	request: Readonly<Record<string, unknown>>,
	requestSequence: number,
): BridgeProductControlRequest {
	return bridgeProductControlRequestSchema.parse({
		...controlIdentity(requestSequence),
		...request,
	});
}

function controlIdentity(requestSequence: number): {
	readonly paneSessionId: string;
	readonly requestId: string;
	readonly requestSequence: number;
	readonly wireVersion: 2;
	readonly workerInstanceId: string;
} {
	return {
		paneSessionId,
		requestId: `resync-request-${requestSequence}`,
		requestSequence,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerInstanceId,
	};
}

async function postControl(
	baseURL: string,
	request: BridgeProductControlRequest,
): Promise<BridgeProductControlResponse> {
	const response = await fetch(`${baseURL}/command`, {
		body: JSON.stringify(request),
		headers: productHeaders(),
		method: 'POST',
	});
	const text = await response.text();
	expect(response.status, text).toBe(200);
	return bridgeProductControlResponseSchema.parse(JSON.parse(text) as unknown);
}

async function openMetadataStream(
	baseURL: string,
	metadataStreamId: string,
	resumeFromStreamSequence: number | null,
): Promise<{
	readonly close: () => void;
	readonly reader: ReadableStreamDefaultReader<Uint8Array>;
}> {
	const abortController = new AbortController();
	const response = await fetch(`${baseURL}/stream`, {
		body: JSON.stringify(
			bridgeProductMetadataStreamRequestSchema.parse({
				kind: 'metadataStream.open',
				metadataStreamId,
				paneSessionId,
				resumeFromStreamSequence,
				wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
				workerInstanceId,
			}),
		),
		headers: productHeaders(),
		method: 'POST',
		signal: abortController.signal,
	});
	const textOnFailure = response.ok ? '' : await response.text();
	expect(response.status, textOnFailure).toBe(200);
	if (response.body === null) throw new Error('Expected metadata response body.');
	return {
		close: (): void => abortController.abort(),
		reader: response.body.getReader(),
	};
}

function productHeaders(): HeadersInit {
	return {
		'Content-Type': 'application/json',
		'X-AgentStudio-Bridge-Product-Capability': capability,
	};
}

function requireMetadataStreamClosure(
	closures: readonly Promise<void>[],
	index: number,
): Promise<void> {
	const closure = closures[index];
	if (closure === undefined) throw new Error(`Missing metadata stream ${index} close hook.`);
	return closure;
}

async function listen(server: Server): Promise<string> {
	await new Promise<void>((resolve): void => {
		server.listen(0, '127.0.0.1', resolve);
	});
	const address = server.address();
	if (address === null || typeof address === 'string') throw new Error('Expected TCP address.');
	return `http://127.0.0.1:${address.port}`;
}
