import { createHash } from 'node:crypto';
import { createServer, type Server } from 'node:http';

import { afterEach, describe, expect, test } from 'vitest';

import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import { bridgeProductReviewMetadataEventSchema } from '../../src/core/comm-worker/bridge-product-review-metadata-contracts.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';
import {
	createBridgeProductDevCarrier,
	type BridgeProductDevCarrier,
} from './bridge-product-dev-carrier.js';
import type { BridgeProductDevReviewAdapterPort } from './bridge-product-dev-review-adapter.js';
import {
	worktreeFileProtocolFrameSchema,
	type WorktreeFileDescriptor,
	type WorktreeFileSurfaceSourceIdentity,
} from './bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const failingPath = 'src/unreadable.ts';
const healthyPath = 'src/app.ts';
const sourceCursor = 'item-error-source-cursor';

describe('Bridge product dev item-error isolation', () => {
	let carrier: BridgeProductDevCarrier | null = null;
	let server: Server | null = null;

	afterEach(async (): Promise<void> => {
		carrier?.dispose();
		carrier = null;
		await closeServer(server);
		server = null;
	});

	test('keeps File and Review metadata alive after one known File descriptor failure', async () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => itemFailureProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		const delivery = carrier.issueBootstrap({ reason: 'initial' });
		const authority = {
			capability: encodeBridgeProductCapabilityHeader(delivery.productCapability),
			paneSessionId: delivery.bootstrap.paneSessionId,
			workerInstanceId: delivery.bootstrap.workerInstanceId,
		} satisfies ProductAuthority;
		server = createServer((request, response): void => {
			if (request.url === '/command') {
				void carrier?.handleCommandRequest({ request, response });
				return;
			}
			if (request.url === '/stream') {
				void carrier?.handleStreamRequest({ request, response });
				return;
			}
			response.statusCode = 404;
			response.end();
		});
		const baseURL = await listen(server);
		await postControl({
			authority,
			baseURL,
			request: controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
		});
		const stream = await MetadataStreamClient.open({ authority, baseURL });
		await stream.nextAndObserve();

		const reviewSubscriptionId = 'review-subscription-item-error';
		await postControl({
			authority,
			baseURL,
			request: controlRequest(
				authority,
				{
					kind: 'subscription.open',
					subscription: { subscriptionKind: 'review.metadata' },
					subscriptionId: reviewSubscriptionId,
					workerDerivationEpoch: 1,
				},
				2,
			),
		});
		await stream.nextAndObserve();
		const reviewSourceFrame = await stream.nextAndObserve();

		const fileSource = await postControl({
			authority,
			baseURL,
			request: controlRequest(
				authority,
				{
					call: { method: 'file.source.current', request: {} },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				3,
			),
		});
		if (
			fileSource.kind !== 'call.completed' ||
			fileSource.call.method !== 'file.source.current' ||
			fileSource.call.result.status !== 'available'
		) {
			throw new Error('Expected an available File source for item-error proof.');
		}
		const fileSubscriptionId = 'file-subscription-item-error';
		const fileOpened = await postControl({
			authority,
			baseURL,
			request: controlRequest(
				authority,
				{
					kind: 'subscription.open',
					subscription: {
						source: fileSource.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId: fileSubscriptionId,
					workerDerivationEpoch: 1,
				},
				4,
			),
		});
		if (fileOpened.kind !== 'subscription.openAccepted') {
			throw new Error('Expected a File subscription for item-error proof.');
		}
		await stream.nextAndObserve();
		await stream.nextAndObserve();
		await stream.nextAndObserve();

		// Act
		const failingInterest = fileInterestState([failingPath]);
		await postControl({
			authority,
			baseURL,
			request: subscriptionUpdateRequest({
				authority,
				baseInterestRevision: 0,
				baseInterestSha256: fileOpened.interestSha256,
				path: failingPath,
				requestSequence: 5,
				subscriptionId: fileSubscriptionId,
				targetInterest: failingInterest,
				targetInterestRevision: 1,
				updateId: 'file-item-error-update',
			}),
		});
		await stream.nextAndObserve();
		const unavailableFrame = await stream.nextAndObserve();

		const healthyInterest = fileInterestState([failingPath, healthyPath]);
		await postControl({
			authority,
			baseURL,
			request: subscriptionUpdateRequest({
				authority,
				baseInterestRevision: 1,
				baseInterestSha256: interestHash(failingInterest),
				path: healthyPath,
				requestSequence: 6,
				subscriptionId: fileSubscriptionId,
				targetInterest: healthyInterest,
				targetInterestRevision: 2,
				updateId: 'file-item-recovery-update',
			}),
		});
		await stream.nextAndObserve();
		const healthyFrame = await stream.nextAndObserve();
		await postControl({
			authority,
			baseURL,
			request: controlRequest(
				authority,
				{
					kind: 'subscription.cancel',
					subscriptionId: reviewSubscriptionId,
					subscriptionKind: 'review.metadata',
					workerDerivationEpoch: 1,
				},
				7,
			),
		});
		const reviewCancelledFrame = await stream.nextAndObserve();

		// Assert
		expect(unavailableFrame).toMatchObject({
			data: {
				event: {
					availability: { availabilityKind: 'unavailable', reason: 'unreadable' },
					eventKind: 'file.descriptorReady',
					path: failingPath,
				},
				subscriptionKind: 'file.metadata',
			},
			kind: 'subscription.data',
			subscriptionId: fileSubscriptionId,
		});
		expect(healthyFrame).toMatchObject({
			data: {
				event: {
					availability: { availabilityKind: 'available' },
					eventKind: 'file.descriptorReady',
					path: healthyPath,
				},
				subscriptionKind: 'file.metadata',
			},
			kind: 'subscription.data',
			subscriptionId: fileSubscriptionId,
		});
		expect(reviewCancelledFrame).toMatchObject({
			kind: 'subscription.cancelled',
			subscriptionId: reviewSubscriptionId,
		});
		expect(reviewSourceFrame).toMatchObject({
			data: {
				event: { eventKind: 'review.sourceAccepted' },
				subscriptionKind: 'review.metadata',
			},
			kind: 'subscription.data',
			subscriptionId: reviewSubscriptionId,
		});
		expect(reviewCancelledFrame.streamSequence).toBeGreaterThan(unavailableFrame.streamSequence);
		expect(carrier.snapshot()).toMatchObject({ subscriptions: 1, waiters: 0 });
		await stream.close();
	}, 10_000);
});

interface ProductAuthority {
	readonly capability: string;
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
}

interface SubscriptionUpdateRequestProps {
	readonly authority: ProductAuthority;
	readonly baseInterestRevision: number;
	readonly baseInterestSha256: string;
	readonly path: string;
	readonly requestSequence: number;
	readonly subscriptionId: string;
	readonly targetInterest: BridgeProductSubscriptionInterestState;
	readonly targetInterestRevision: number;
	readonly updateId: string;
}

function subscriptionUpdateRequest(
	props: SubscriptionUpdateRequestProps,
): BridgeProductControlRequest {
	return controlRequest(
		props.authority,
		{
			baseInterestRevision: props.baseInterestRevision,
			baseInterestSha256: props.baseInterestSha256,
			batchCount: 1,
			batchIndex: 0,
			delta: {
				add: [{ lane: 'foreground', path: props.path }],
				addPathScope: [],
				removePathScope: [],
				removePaths: [],
				subscriptionKind: 'file.metadata',
			},
			kind: 'subscription.updateBatch',
			subscriptionId: props.subscriptionId,
			subscriptionKind: 'file.metadata',
			targetInterestRevision: props.targetInterestRevision,
			targetInterestSha256: interestHash(props.targetInterest),
			totalDeltaItemCount: 1,
			updateId: props.updateId,
			workerDerivationEpoch: 1,
		},
		props.requestSequence,
	);
}

function controlRequest(
	authority: Pick<ProductAuthority, 'paneSessionId' | 'workerInstanceId'>,
	request: Readonly<Record<string, unknown>>,
	requestSequence: number,
): BridgeProductControlRequest {
	return bridgeProductControlRequestSchema.parse({
		paneSessionId: authority.paneSessionId,
		requestId: `item-error-request-${requestSequence}`,
		requestSequence,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerInstanceId: authority.workerInstanceId,
		...request,
	});
}

function fileInterestState(paths: readonly string[]): BridgeProductSubscriptionInterestState {
	return {
		interests: [{ lane: 'foreground', paths }],
		pathScope: [],
		subscriptionKind: 'file.metadata',
	};
}

function interestHash(state: BridgeProductSubscriptionInterestState): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

async function postControl(props: {
	readonly authority: ProductAuthority;
	readonly baseURL: string;
	readonly request: BridgeProductControlRequest;
}): Promise<BridgeProductControlResponse> {
	const response = await fetch(`${props.baseURL}/command`, {
		body: JSON.stringify(props.request),
		headers: productHeaders(props.authority.capability),
		method: 'POST',
	});
	const responseText = await response.text();
	expect(response.status, responseText).toBe(200);
	return bridgeProductControlResponseSchema.parse(JSON.parse(responseText) as unknown);
}

class MetadataStreamClient {
	readonly #authority: ProductAuthority;
	readonly #baseURL: string;
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #pendingFrames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	private constructor(props: {
		readonly authority: ProductAuthority;
		readonly baseURL: string;
		readonly reader: ReadableStreamDefaultReader<Uint8Array>;
	}) {
		this.#authority = props.authority;
		this.#baseURL = props.baseURL;
		this.#reader = props.reader;
	}

	static async open(props: {
		readonly authority: ProductAuthority;
		readonly baseURL: string;
	}): Promise<MetadataStreamClient> {
		const response = await fetch(`${props.baseURL}/stream`, {
			body: JSON.stringify(
				bridgeProductMetadataStreamRequestSchema.parse({
					kind: 'metadataStream.open',
					metadataStreamId: 'item-error-metadata-stream',
					paneSessionId: props.authority.paneSessionId,
					resumeFromStreamSequence: null,
					wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
					workerInstanceId: props.authority.workerInstanceId,
				}),
			),
			headers: productHeaders(props.authority.capability),
			method: 'POST',
		});
		expect(response.status).toBe(200);
		if (response.body === null) throw new Error('Expected an item-error metadata stream.');
		return new MetadataStreamClient({
			authority: props.authority,
			baseURL: props.baseURL,
			reader: response.body.getReader(),
		});
	}

	async nextAndObserve(): Promise<BridgeProductMetadataFrame> {
		const frame = await this.#nextFrame();
		const response = await fetch(`${this.#baseURL}/command`, {
			body: JSON.stringify({
				kind: 'stream.frameObserved',
				metadataStreamId: frame.metadataStreamId,
				paneSessionId: frame.paneSessionId,
				streamKind: 'metadata',
				streamSequence: frame.streamSequence,
				wireVersion: frame.wireVersion,
				workerInstanceId: frame.workerInstanceId,
			}),
			headers: productHeaders(this.#authority.capability),
			method: 'POST',
		});
		expect(response.status).toBe(204);
		expect(await response.text()).toBe('');
		return frame;
	}

	close(): Promise<void> {
		return this.#reader.cancel();
	}

	async #nextFrame(): Promise<BridgeProductMetadataFrame> {
		while (this.#pendingFrames.length === 0) {
			// oxlint-disable-next-line no-await-in-loop -- Metadata frames are consumed in physical order.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Item-error metadata stream ended early.');
			this.#pendingFrames.push(...this.#decoder.push(chunk.value));
		}
		const frame = this.#pendingFrames.shift();
		if (frame === undefined) throw new Error('Item-error metadata frame queue was empty.');
		return frame;
	}
}

function fakeReviewAdapter(): BridgeProductDevReviewAdapterPort {
	return {
		loadContent: async () => null,
		loadSource: async () => ({
			cursor: 'review-cursor-item-error',
			events: [
				bridgeProductReviewMetadataEventSchema.parse({
					eventKind: 'review.sourceAccepted',
					generation: 1,
					packageId: 'review-package-item-error',
					revision: 1,
					sourceIdentity: 'review-source-item-error',
				}),
			],
			generation: 1,
			packageId: 'review-package-item-error',
			revision: 1,
			sourceIdentity: 'review-source-item-error',
		}),
	};
}

function itemFailureProvider(): BridgeWorktreeDevProvider {
	const source = fileSourceIdentity();
	return {
		loadWorktreeFileContent: async () => 'alpha\nbeta\n',
		loadWorktreeFileDescriptor: async (request) => {
			if (request.path === failingPath) {
				throw new Error('simulated item-scoped read failure');
			}
			const frame = worktreeFileProtocolFrameSchema.parse({
				descriptor: healthyDescriptor(request.path),
				frameKind: 'worktree.fileDescriptor',
				generation: 1,
				kind: 'delta',
				sequence: 2,
				streamId: 'worktree-file:item-error-pane',
			});
			if (frame.frameKind !== 'worktree.fileDescriptor') {
				throw new Error('Expected a File descriptor frame.');
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
					streamId: 'worktree-file:item-error-pane',
					treeRows: [healthyPath, failingPath].map((path, index) => ({
						changeStatus: 'modified',
						depth: 1,
						fileId: `dev-file-id-${index + 1}`,
						isDirectory: false,
						lineCount: 2,
						name: path.split('/').at(-1) ?? path,
						parentPath: 'src',
						path,
						rowId: `row:${path}`,
						sizeBytes: 11,
					})),
					treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 2, rowHeightPixels: 24 },
				}),
			],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'item-error-root-token',
			},
			source,
			treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 2, rowHeightPixels: 24 },
		}),
	};
}

function fileSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		repoId: 'item-error-repo',
		rootRevisionToken: 'item-error-revision',
		sourceCursor,
		sourceId: 'item-error-source',
		subscriptionGeneration: 1,
		worktreeId: 'item-error-worktree',
	};
}

function healthyDescriptor(path: string): WorktreeFileDescriptor {
	const content = 'alpha\nbeta\n';
	const descriptorId = 'item-error-healthy-descriptor';
	return {
		contentHandle: descriptorId,
		contentHash: `sha256:${createHash('sha256').update(content).digest('hex')}`,
		fileExtension: 'ts',
		fileId: 'dev-file-id-1',
		isBinary: false,
		unavailableReason: null,
		language: 'typescript',
		lineCount: 2,
		path,
		sizeBytes: content.length,
		sourceIdentity: fileSourceIdentity(),
		virtualizedExtentKind: 'exactLineCount',
	};
}

function productHeaders(capability: string): HeadersInit {
	return {
		'Content-Type': 'application/json',
		'X-AgentStudio-Bridge-Product-Capability': capability,
	};
}

async function listen(server: Server): Promise<string> {
	await new Promise<void>((resolve): void => {
		server.listen(0, '127.0.0.1', resolve);
	});
	const address = server.address();
	if (address === null || typeof address === 'string') throw new Error('Expected TCP address.');
	return `http://127.0.0.1:${address.port}`;
}

async function closeServer(server: Server | null): Promise<void> {
	if (server === null) return;
	server.closeAllConnections();
	await new Promise<void>((resolve): void => {
		server.close((): void => resolve());
	});
}
