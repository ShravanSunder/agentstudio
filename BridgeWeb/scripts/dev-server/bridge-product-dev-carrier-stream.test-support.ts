import { createHash } from 'node:crypto';
import { createServer, type Server } from 'node:http';

import { expect } from 'vitest';

import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import type { BridgeProductDevNavigationIntent } from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import { bridgeProductReviewMetadataEventSchema } from '../../src/core/comm-worker/bridge-product-review-metadata-contracts.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	createBridgeProductDevCarrier,
	type BridgeProductDevCarrier,
} from './bridge-product-dev-carrier.js';
import {
	authorityForDelivery,
	type TestProductAuthority,
} from './bridge-product-dev-carrier.test-support.js';
import type { BridgeProductDevReviewAdapterPort } from './bridge-product-dev-review-adapter.js';
import { worktreeFileProtocolFrameSchema } from './bridge-worktree-dev-file-fixture-contracts.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from './bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const sourceCursor = 'cursor-1';
const defaultNavigationIntent = {
	commandId: 'dev:test:file:target',
	commandKind: 'activateTarget',
	surface: 'file',
	target: { path: 'src/app.ts', targetKind: 'file', version: 'current' },
} as const satisfies BridgeProductDevNavigationIntent;

export async function startCarrierServer(props?: {
	readonly createReviewAdapter?: () => BridgeProductDevReviewAdapterPort;
	readonly getFileProvider?: () => Promise<BridgeWorktreeDevProvider>;
	readonly getReviewSourceConfig?: () => Promise<{
		readonly baseRef: string;
		readonly worktreeRoot: string;
	}>;
	readonly navigationIntent?: BridgeProductDevNavigationIntent;
}): Promise<{
	readonly authority: TestProductAuthority;
	readonly baseURL: string;
	readonly carrier: BridgeProductDevCarrier;
	readonly server: Server;
}> {
	const carrier = createBridgeProductDevCarrier({
		createReviewAdapter:
			props?.createReviewAdapter ?? ((): BridgeProductDevReviewAdapterPort => fakeReviewAdapter()),
		getFileProvider: props?.getFileProvider ?? (async () => fakeFileProvider()),
		getReviewSourceConfig:
			props?.getReviewSourceConfig ?? (async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' })),
	});
	const authority = authorityForDelivery(
		carrier.issueBootstrap({
			navigationIntent: props?.navigationIntent ?? defaultNavigationIntent,
			reason: 'initial',
		}),
	);
	const server = createServer((request, response): void => {
		switch (request.url) {
			case '/command':
				void carrier.handleCommandRequest({ request, response });
				return;
			case '/stream':
				void carrier.handleStreamRequest({ request, response });
				return;
			case '/content':
				void carrier.handleContentRequest({ request, response });
				return;
			case undefined:
			default:
				response.statusCode = 404;
				response.end();
		}
	});
	return { authority, baseURL: await listen(server), carrier, server };
}

export function fakeReviewAdapter(): BridgeProductDevReviewAdapterPort {
	return {
		loadContent: async () => null,
		loadSource: async () => ({
			cursor: 'review-cursor-1',
			events: [
				bridgeProductReviewMetadataEventSchema.parse({
					eventKind: 'review.sourceAccepted',
					generation: 1,
					packageId: 'review-package-1',
					publicationId: '00000000-0000-7000-8000-000000000011',
					revision: 1,
					sourceIdentity: 'review-source-1',
				}),
			],
			generation: 1,
			packageId: 'review-package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			revision: 1,
			sourceIdentity: 'review-source-1',
		}),
	};
}

export function fakeFileProvider(): BridgeWorktreeDevProvider {
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
			if (frame.frameKind !== 'worktree.fileDescriptor') throw new Error('Invalid fake frame.');
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
							fileClass: 'source',
							isDirectory: false,
							lineCount: 2,
							name: 'app.ts',
							parentPath: 'src',
							path: 'src/app.ts',
							rowId: 'row:src/app.ts',
							sizeBytes: 11,
						},
					],
					treeSizeFacts: {
						extentKind: 'exactPathCount',
						pathCount: 1,
						rowHeightPixels: 24,
					},
				}),
			],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			source,
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 1,
				rowHeightPixels: 24,
			},
		}),
	};
}

export class MetadataStreamClient {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #pendingFrames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#reader = reader;
	}

	async nextFrame(): Promise<BridgeProductMetadataFrame> {
		while (this.#pendingFrames.length === 0) {
			// oxlint-disable-next-line no-await-in-loop -- Network chunks are consumed in protocol order.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Metadata stream ended early.');
			this.#pendingFrames.push(...this.#decoder.push(chunk.value));
		}
		const frame = this.#pendingFrames.shift();
		if (frame === undefined) throw new Error('Metadata frame queue was unexpectedly empty.');
		return frame;
	}

	async close(): Promise<void> {
		await this.#reader.cancel();
	}
}

export async function openWorkerSession(
	baseURL: string,
	authority: TestProductAuthority,
): Promise<void> {
	await postControl(
		baseURL,
		controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
		authority.capability,
	);
}

export async function observeInitialMetadataFrames(
	baseURL: string,
	stream: MetadataStreamClient,
	authority: TestProductAuthority,
): Promise<void> {
	for (const expectedKind of ['metadataStream.accepted', 'pane.presentation'] as const) {
		// oxlint-disable-next-line no-await-in-loop -- Metadata bootstrap frames are acknowledged in order.
		const frame = await stream.nextFrame();
		expect(frame.kind).toBe(expectedKind);
		// oxlint-disable-next-line no-await-in-loop -- The writer gates the next frame on this receipt.
		expect(await postMetadataObservation(baseURL, frame, authority.capability)).toBe(204);
	}
}

export async function openReviewSubscription(
	baseURL: string,
	authority: TestProductAuthority,
): Promise<void> {
	await postControl(
		baseURL,
		controlRequest(
			authority,
			{
				kind: 'subscription.open',
				subscription: { subscriptionKind: 'review.metadata' },
				subscriptionId: 'navigation-review-subscription',
				workerDerivationEpoch: 1,
			},
			2,
		),
		authority.capability,
	);
}

export async function openMetadataStream(
	baseURL: string,
	authority: TestProductAuthority,
): Promise<MetadataStreamClient> {
	const response = await fetch(`${baseURL}/stream`, {
		body: JSON.stringify(
			bridgeProductMetadataStreamRequestSchema.parse({
				kind: 'metadataStream.open',
				metadataStreamId: 'metadata-stream-1',
				paneSessionId: authority.paneSessionId,
				resumeFromStreamSequence: null,
				wireVersion: 2,
				workerInstanceId: authority.workerInstanceId,
			}),
		),
		headers: productHeaders(authority.capability),
		method: 'POST',
	});
	expect(response.status).toBe(200);
	if (response.body === null) throw new Error('Expected metadata body.');
	return new MetadataStreamClient(response.body.getReader());
}

export async function postMetadataObservation(
	baseURL: string,
	frame: Pick<
		BridgeProductMetadataFrame,
		'metadataStreamId' | 'paneSessionId' | 'streamSequence' | 'wireVersion' | 'workerInstanceId'
	>,
	capability: string,
): Promise<number> {
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
		headers: productHeaders(capability),
		method: 'POST',
	});
	const responseBody = await response.text();
	if (response.status === 204) expect(responseBody).toBe('');
	return response.status;
}

export function controlRequest(
	authority: Pick<TestProductAuthority, 'paneSessionId' | 'workerInstanceId'>,
	request: Readonly<Record<string, unknown>>,
	requestSequence: number,
): BridgeProductControlRequest {
	return bridgeProductControlRequestSchema.parse({
		paneSessionId: authority.paneSessionId,
		requestId: `request-${requestSequence}`,
		requestSequence,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerInstanceId: authority.workerInstanceId,
		...request,
	});
}

export async function postControl(
	baseURL: string,
	request: BridgeProductControlRequest,
	capability: string,
): Promise<BridgeProductControlResponse> {
	const response = await fetch(`${baseURL}/command`, {
		body: JSON.stringify(request),
		headers: productHeaders(capability),
		method: 'POST',
	});
	const text = await response.text();
	expect(response.status, text).toBe(200);
	return bridgeProductControlResponseSchema.parse(JSON.parse(text) as unknown);
}

export async function closeServer(server: Server | null): Promise<void> {
	if (server === null) return;
	server.closeAllConnections();
	await new Promise<void>((resolve): void => {
		server.close((): void => resolve());
	});
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
	const descriptorId = 'dev-file-descriptor-1';
	return {
		contentHandle: descriptorId,
		contentHash: `sha256:${createHash('sha256').update('alpha\nbeta\n').digest('hex')}`,
		fileExtension: 'ts',
		fileId: 'dev-file-id-1',
		isBinary: false,
		unavailableReason: null,
		language: 'typescript',
		lineCount: 2,
		path,
		sizeBytes: 11,
		sourceIdentity: legacySource(),
		virtualizedExtentKind: 'exactLineCount',
	};
}

export function productHeaders(productCapability: string): HeadersInit {
	return {
		'Content-Type': 'application/json',
		'X-AgentStudio-Bridge-Product-Capability': productCapability,
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
