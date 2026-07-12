import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { createServer, type Server } from 'node:http';

import { afterEach, describe, expect, test } from 'vitest';

import {
	bridgeProductContentRequestSchema,
	type BridgeProductFileContentDescriptor,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentStreamDecoder } from '../../src/core/comm-worker/bridge-product-content-stream-decoder.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionInterestState,
} from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';
import {
	worktreeFileProtocolFrameSchema,
	type WorktreeFileDescriptor,
	type WorktreeFileSurfaceSourceIdentity,
} from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { createBridgeProductDevFileCarrier } from './bridge-product-dev-file-carrier.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const capability = Buffer.alloc(32, 7).toString('base64url');
const paneSessionId = 'pane-session-1';
const workerInstanceId = 'worker-instance-1';
const sourceCursor = 'cursor-1';

describe('Bridge product dev File carrier', () => {
	let server: Server | null = null;

	afterEach(async () => {
		await closeServer(server);
		server = null;
	});

	test('does not admit an unauthenticated product call', async () => {
		const baseURL = await startCarrierServer(fakeProvider());

		const response = await fetch(`${baseURL}/command`, {
			body: JSON.stringify({ kind: 'product.call' }),
			headers: { 'Content-Type': 'application/json' },
			method: 'POST',
		});

		expect(response.status).toBe(401);
	});

	test('rejects duplicate JSON members and oversized bodies before dispatch', async () => {
		const baseURL = await startCarrierServer(fakeProvider());

		const duplicate = await fetch(`${baseURL}/command`, {
			body: '{"kind":"workerSession.open","kind":"workerSession.open"}',
			headers: productHeaders(),
			method: 'POST',
		});
		const oversized = await fetch(`${baseURL}/command`, {
			body: Buffer.alloc(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES + 1, 97),
			headers: productHeaders(),
			method: 'POST',
		});

		expect(duplicate.status).toBe(400);
		expect(oversized.status).toBe(413);
	});

	test('runs one capability-scoped call, metadata, content, and cancel lifecycle', async () => {
		const provider = fakeProvider();
		const baseURL = await startCarrierServer(provider);
		const openRequest = controlRequest({ kind: 'workerSession.open', request: null }, 1);

		const opened = await postControl(baseURL, openRequest);
		const exactRetry = await postControl(baseURL, openRequest);
		expect(exactRetry).toEqual(opened);
		expect(opened.kind).toBe('workerSession.accepted');

		const sourceResult = await postControl(
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
			sourceResult.kind !== 'call.completed' ||
			sourceResult.call.method !== 'file.source.current'
		) {
			throw new Error('Expected the File source call result.');
		}
		expect(sourceResult.call.result.status).toBe('available');
		if (sourceResult.call.result.status !== 'available')
			throw new Error('Expected available source.');

		const metadataResponse = await fetch(`${baseURL}/stream`, {
			body: JSON.stringify(
				bridgeProductMetadataStreamRequestSchema.parse({
					kind: 'metadataStream.open',
					metadataStreamId: 'metadata-stream-1',
					paneSessionId,
					resumeFromStreamSequence: null,
					wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
					workerInstanceId,
				}),
			),
			headers: productHeaders(),
			method: 'POST',
		});
		expect(metadataResponse.status).toBe(200);
		if (metadataResponse.body === null) throw new Error('Expected metadata response body.');
		const metadataReader = metadataResponse.body.getReader();
		const metadataFrames = new MetadataFrameCollector(metadataReader);
		expect((await metadataFrames.waitForCount(1))[0]?.kind).toBe('metadataStream.accepted');

		const subscriptionId = 'file-subscription-1';
		const openedSubscription = await postControl(
			baseURL,
			controlRequest(
				{
					kind: 'subscription.open',
					subscription: {
						source: sourceResult.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId,
					workerDerivationEpoch: 0,
				},
				3,
			),
		);
		expect(openedSubscription.kind).toBe('subscription.openAccepted');
		const initialFrames = await metadataFrames.waitForCount(4);
		expect(initialFrames.map((frame) => frame.kind)).toEqual([
			'metadataStream.accepted',
			'subscription.accepted',
			'subscription.data',
			'subscription.data',
		]);
		expect(subscriptionEvent(initialFrames[2]).eventKind).toBe('file.sourceAccepted');
		expect(subscriptionEvent(initialFrames[3]).eventKind).toBe('file.treeWindow');

		const targetInterestState: BridgeProductSubscriptionInterestState = {
			interests: [{ lane: 'foreground', paths: ['src/app.ts'] }],
			pathScope: [],
			subscriptionKind: 'file.metadata',
		};
		const targetInterestSha256 = interestHash(targetInterestState);
		const updated = await postControl(
			baseURL,
			controlRequest(
				{
					baseInterestRevision: 0,
					baseInterestSha256:
						openedSubscription.kind === 'subscription.openAccepted'
							? openedSubscription.interestSha256
							: '',
					batchCount: 1,
					batchIndex: 0,
					delta: {
						add: [{ lane: 'foreground', path: 'src/app.ts' }],
						addPathScope: [],
						removePathScope: [],
						removePaths: [],
						subscriptionKind: 'file.metadata',
					},
					kind: 'subscription.updateBatch',
					subscriptionId,
					subscriptionKind: 'file.metadata',
					targetInterestRevision: 1,
					targetInterestSha256,
					totalDeltaItemCount: 1,
					updateId: 'update-1',
					workerDerivationEpoch: 0,
				},
				4,
			),
		);
		expect(updated.kind).toBe('subscription.updateBatchAccepted');
		const updatedFrames = await metadataFrames.waitForCount(6);
		expect(updatedFrames[4]?.kind).toBe('subscription.interestsCommitted');
		const descriptorEvent = subscriptionEvent(updatedFrames[5]);
		expect(descriptorEvent.eventKind).toBe('file.descriptorReady');
		if (
			descriptorEvent.eventKind !== 'file.descriptorReady' ||
			descriptorEvent.availability.availabilityKind !== 'available'
		) {
			throw new Error('Expected an available File descriptor.');
		}
		const descriptor = descriptorEvent.availability.contentDescriptor;
		await expectContent(baseURL, descriptor, new TextEncoder().encode('alpha\nbeta\n'));

		const cancelled = await postControl(
			baseURL,
			controlRequest(
				{
					kind: 'subscription.cancel',
					subscriptionId,
					subscriptionKind: 'file.metadata',
					workerDerivationEpoch: 0,
				},
				5,
			),
		);
		expect(cancelled.kind).toBe('subscription.cancelAccepted');
		expect((await metadataFrames.waitForCount(7))[6]?.kind).toBe('subscription.cancelled');
		await metadataReader.cancel();
	});

	async function startCarrierServer(provider: BridgeWorktreeDevProvider): Promise<string> {
		const carrier = createBridgeProductDevFileCarrier({ getProvider: async () => provider });
		server = createServer((request, response): void => {
			switch (request.url) {
				case undefined:
					response.statusCode = 404;
					response.end();
					return;
				case '/command':
					void carrier.handleCommandRequest({ request, response });
					return;
				case '/stream':
					void carrier.handleStreamRequest({ request, response });
					return;
				case '/content':
					void carrier.handleContentRequest({ request, response });
					return;
				default:
					response.statusCode = 404;
					response.end();
			}
		});
		return await listen(server);
	}
});

class MetadataFrameCollector {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #frames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#reader = reader;
	}

	async waitForCount(count: number): Promise<readonly BridgeProductMetadataFrame[]> {
		while (this.#frames.length < count) {
			// eslint-disable-next-line no-await-in-loop -- The protocol stream is ordered.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Metadata stream ended before the expected frame count.');
			this.#frames.push(...this.#decoder.push(chunk.value));
		}
		return [...this.#frames];
	}
}

function fakeProvider(): BridgeWorktreeDevProvider {
	const source = legacySource();
	return {
		loadWorktreeFileContent: async () => 'alpha\nbeta\n',
		loadWorktreeFileDescriptor: async (request) => {
			const frame = worktreeFileProtocolFrameSchema.parse({
				descriptor: legacyDescriptor(request.path),
				frameKind: 'worktree.fileDescriptor',
				generation: 1,
				kind: 'delta',
				sequence: 2,
				streamId: 'worktree-file:dev-pane',
			});
			if (frame.frameKind !== 'worktree.fileDescriptor') {
				throw new Error('Expected the fake File descriptor frame.');
			}
			return frame;
		},
		loadWorktreeFileSurface: async () => ({
			frames: [
				worktreeFileProtocolFrameSchema.parse({
					frameKind: 'worktree.snapshot',
					generation: 1,
					kind: 'snapshot',
					metadataLineage: { lane: 'foreground', loadedBy: 'startup_window' },
					sequence: 0,
					source,
					streamId: 'worktree-file:dev-pane',
					treeRows: [
						{
							changeStatus: 'modified',
							depth: 1,
							fileId: 'dev-file-id-1',
							isDirectory: false,
							lineCount: 2,
							name: 'app.ts',
							parentPath: 'src',
							path: 'src/app.ts',
							rowId: 'row:src/app.ts',
							sizeBytes: 11,
						},
					],
					treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
				}),
			],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			source,
			treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
		}),
	};
}

function legacySource(): WorktreeFileSurfaceSourceIdentity {
	return {
		repoId: 'legacy-repo',
		rootRevisionToken: 'revision-1',
		sourceCursor,
		sourceId: 'source-1',
		subscriptionGeneration: 1,
		worktreeId: 'legacy-worktree',
	};
}

function legacyDescriptor(path: string): WorktreeFileDescriptor {
	const identity = {
		cursor: sourceCursor,
		generation: 1,
		paneId: 'dev-pane',
		protocol: 'worktree-file' as const,
		sourceId: 'source-1',
		streamId: 'worktree-file:dev-pane',
	};
	const descriptorId = 'dev-file-descriptor-1';
	return {
		contentDescriptor: {
			descriptor: {
				content: {
					encoding: 'utf-8' as const,
					expectedBytes: 11,
					maxBytes: 11,
					mediaType: 'text/typescript',
				},
				descriptorId,
				identity,
				protocol: 'worktree-file' as const,
				resourceKind: 'worktree.fileContent' as const,
				resourceUrl: 'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-1',
			},
			ref: {
				descriptorId,
				expectedIdentity: identity,
				expectedProtocol: 'worktree-file' as const,
				expectedResourceKind: 'worktree.fileContent' as const,
			},
		},
		contentHandle: descriptorId,
		contentHash: `sha256:${createHash('sha256').update('alpha\nbeta\n').digest('hex')}`,
		fileExtension: 'ts',
		fileId: 'dev-file-id-1',
		isBinary: false,
		language: 'typescript',
		lineCount: 2,
		path,
		sizeBytes: 11,
		sourceIdentity: legacySource(),
		virtualizedExtentKind: 'exactLineCount' as const,
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
		requestId: `request-${requestSequence}`,
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
	const responseText = await response.text();
	expect(response.status, responseText).toBe(200);
	return bridgeProductControlResponseSchema.parse(JSON.parse(responseText) as unknown);
}

async function expectContent(
	baseURL: string,
	descriptor: BridgeProductFileContentDescriptor,
	expectedBytes: Uint8Array,
): Promise<void> {
	const request = bridgeProductContentRequestSchema.parse({
		contentKind: 'file.content',
		contentRequestId: 'content-request-1',
		descriptor,
		kind: 'content.open',
		leaseId: 'lease-1',
		paneSessionId,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerDerivationEpoch: 0,
		workerInstanceId,
	});
	const response = await fetch(`${baseURL}/content`, {
		body: JSON.stringify(request),
		headers: productHeaders(),
		method: 'POST',
	});
	expect(response.status).toBe(200);
	const decoder = new BridgeProductContentStreamDecoder(request);
	const decoded = await decoder.push(new Uint8Array(await response.arrayBuffer()));
	decoder.finish();
	expect(decoded.terminal?.kind).toBe('complete');
	if (decoded.terminal?.kind !== 'complete') throw new Error('Expected complete content.');
	expect(new Uint8Array(decoded.terminal.bytes)).toEqual(expectedBytes);
}

function subscriptionEvent(
	frame: BridgeProductMetadataFrame | undefined,
): BridgeProductSubscriptionEvent<'file.metadata'> {
	if (frame?.kind !== 'subscription.data' || frame.subscriptionKind !== 'file.metadata') {
		throw new Error('Expected File subscription data.');
	}
	return frame.data.event;
}

function productHeaders(): HeadersInit {
	return {
		'Content-Type': 'application/json',
		'X-AgentStudio-Bridge-Product-Capability': capability,
	};
}

function interestHash(state: BridgeProductSubscriptionInterestState): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

async function listen(server: Server): Promise<string> {
	await new Promise<void>((resolve): void => {
		server.listen(0, '127.0.0.1', resolve);
	});
	const address = server.address();
	if (address === null || typeof address === 'string') {
		throw new Error('Expected an ephemeral TCP address.');
	}
	return `http://127.0.0.1:${address.port}`;
}

async function closeServer(server: Server | null): Promise<void> {
	if (server === null) return;
	server.closeAllConnections();
	await new Promise<void>((resolve, reject): void => {
		server.close((error): void => {
			if (error === undefined) resolve();
			else reject(error);
		});
	});
}
