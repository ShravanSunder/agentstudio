import { createServer, type Server } from 'node:http';

import { afterEach, describe, expect, test } from 'vitest';

import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	createBridgeProductDevCarrier,
	type BridgeProductDevCarrier,
} from './bridge-product-dev-carrier.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

let authority: TestProductAuthority | null = null;
let carrier: BridgeProductDevCarrier | null = null;

describe('Bridge product dev pane carrier resync', () => {
	let server: Server | null = null;

	afterEach(async () => {
		carrier?.dispose();
		carrier = null;
		authority = null;
		if (server === null) return;
		server.closeAllConnections();
		await new Promise<void>((resolve): void => {
			server?.close((): void => resolve());
		});
		server = null;
	});

	test('reconnects, returns positional reopenRequired outcomes, and permits fresh ids', async () => {
		const testCarrier = createBridgeProductDevCarrier({
			getFileProvider: async () => fakeProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		carrier = testCarrier;
		const delivery = testCarrier.issueBootstrap({ reason: 'initial' });
		authority = {
			capability: encodeBridgeProductCapabilityHeader(delivery.productCapability),
			paneSessionId: delivery.bootstrap.paneSessionId,
			workerInstanceId: delivery.bootstrap.workerInstanceId,
		};
		const metadataStreamClosures: Promise<void>[] = [];
		server = createServer((request, response): void => {
			const props = { request, response };
			if (request.url === '/command') void testCarrier.handleCommandRequest(props);
			else if (request.url === '/stream') {
				metadataStreamClosures.push(
					new Promise<void>((resolve): void => {
						response.once('close', resolve);
					}),
				);
				void testCarrier.handleStreamRequest(props);
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
		const firstFrames = new MetadataFrames(baseURL, firstStream.reader);
		await firstFrames.waitFor((frame) => frame.kind === 'metadataStream.accepted');
		const foregroundPresentation = await firstFrames.waitFor(
			(frame) => frame.kind === 'pane.presentation',
		);
		expect(foregroundPresentation).toMatchObject({
			activityRevision: 1,
			nativeActivity: 'foreground',
			refreshingLanes: [],
		});
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
		const committedSourceFrame = await firstFrames.waitFor(
			(frame) =>
				frame.kind === 'subscription.data' &&
				frame.subscriptionId === oldSubscriptionId &&
				frame.data.subscriptionKind === 'file.metadata' &&
				frame.data.event.eventKind === 'file.sourceAccepted',
		);
		const lastAcceptedStreamSequence = committedSourceFrame.streamSequence;
		firstStream.close();
		await requireMetadataStreamClosure(metadataStreamClosures, 0);

		const replacementStream = await openMetadataStream(
			baseURL,
			'stream-2',
			lastAcceptedStreamSequence,
		);
		const replacementFrames = new MetadataFrames(baseURL, replacementStream.reader);
		const replacementAccepted = await replacementFrames.waitFor(
			(frame) => frame.kind === 'metadataStream.accepted',
		);
		expect(replacementAccepted).toMatchObject({
			kind: 'metadataStream.accepted',
			resumeDisposition: 'snapshot_required',
			streamSequence: lastAcceptedStreamSequence + 1,
		});
		const replacementForegroundPresentation = await replacementFrames.waitFor(
			(frame) => frame.kind === 'pane.presentation',
		);

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
			metadataStreamSequenceBarrier: replacementForegroundPresentation.streamSequence,
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
		const freshSourceFrame = await replacementFrames.waitFor(
			(frame) =>
				frame.kind === 'subscription.data' &&
				frame.subscriptionId === 'subscription-fresh' &&
				frame.data.subscriptionKind === 'file.metadata' &&
				frame.data.event.eventKind === 'file.sourceAccepted',
		);
		const freshLastStreamSequence = freshSourceFrame.streamSequence;
		replacementStream.close();
		await requireMetadataStreamClosure(metadataStreamClosures, 1);
		const emptyListStream = await openMetadataStream(baseURL, 'stream-3', freshLastStreamSequence);
		const emptyListFrames = new MetadataFrames(baseURL, emptyListStream.reader);
		await emptyListFrames.waitFor((frame) => frame.kind === 'metadataStream.accepted');
		await emptyListFrames.waitFor((frame) => frame.kind === 'pane.presentation');
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
	readonly #baseURL: string;
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #frames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(baseURL: string, reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#baseURL = baseURL;
		this.#reader = reader;
	}

	async waitFor(
		predicate: (frame: BridgeProductMetadataFrame) => boolean,
	): Promise<BridgeProductMetadataFrame> {
		while (true) {
			const matchingFrame = this.#frames.find(predicate);
			if (matchingFrame !== undefined) return matchingFrame;
			// oxlint-disable-next-line no-await-in-loop -- Protocol frames are ordered.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Metadata stream ended early.');
			const frames = this.#decoder.push(chunk.value);
			for (const frame of frames) {
				// oxlint-disable-next-line no-await-in-loop -- Each physical frame must be observed in order.
				await postMetadataObservation(this.#baseURL, frame);
			}
			this.#frames.push(...frames);
		}
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
	const productAuthority = requireProductAuthority();
	return {
		paneSessionId: productAuthority.paneSessionId,
		requestId: `resync-request-${requestSequence}`,
		requestSequence,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerInstanceId: productAuthority.workerInstanceId,
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

async function postMetadataObservation(
	baseURL: string,
	frame: BridgeProductMetadataFrame,
): Promise<void> {
	const response = await fetch(`${baseURL}/command`, {
		body: JSON.stringify({
			kind: 'stream.frameObserved',
			metadataStreamId: frame.metadataStreamId,
			paneSessionId: frame.paneSessionId,
			streamKind: 'metadata',
			streamSequence: frame.streamSequence,
			wireVersion: frame.wireVersion,
			workerInstanceId: frame.workerInstanceId,
		}),
		headers: productHeaders(),
		method: 'POST',
	});
	expect(response.status).toBe(204);
	expect(await response.text()).toBe('');
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
				paneSessionId: requireProductAuthority().paneSessionId,
				resumeFromStreamSequence,
				wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
				workerInstanceId: requireProductAuthority().workerInstanceId,
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
		'X-AgentStudio-Bridge-Product-Capability': requireProductAuthority().capability,
	};
}

interface TestProductAuthority {
	readonly capability: string;
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
}

function requireProductAuthority(): TestProductAuthority {
	if (authority === null) throw new Error('Bridge product resync authority is not installed.');
	return authority;
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
