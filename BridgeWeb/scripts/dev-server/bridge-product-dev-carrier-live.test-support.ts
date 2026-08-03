import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { expect } from 'vitest';

import {
	bridgeProductContentRequestSchema,
	type BridgeProductFileContentDescriptor,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentStreamDecoder } from '../../src/core/comm-worker/bridge-product-content-stream-decoder.js';
import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
	decodeBridgeProductDevBootstrapDelivery,
} from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
	type BridgeProductSessionBootstrap,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';

const viteConfigFile = fileURLToPath(new URL('../../vite.config.ts', import.meta.url));

export const liveViteCarrierTestTimeoutMilliseconds = 15_000;

export class LiveViteProductServer {
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
	readonly #observe: (frame: BridgeProductMetadataFrame) => Promise<void>;
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(
		reader: ReadableStreamDefaultReader<Uint8Array>,
		observe: (frame: BridgeProductMetadataFrame) => Promise<void>,
	) {
		this.#reader = reader;
		this.#observe = observe;
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
			const frames = this.#decoder.push(chunk.value);
			for (const frame of frames) {
				// oxlint-disable-next-line no-await-in-loop -- Physical observations preserve stream order.
				await this.#observe(frame);
			}
			this.#frames.push(...frames);
		}
	}
}

export class LiveProductClient {
	readonly #baseURL: string;
	readonly #bootstrap: BridgeProductSessionBootstrap;
	readonly #capability: string;
	readonly #paneSessionId: string;
	readonly #workerInstanceId: string;

	private constructor(props: {
		readonly baseURL: string;
		readonly bootstrap: BridgeProductSessionBootstrap;
		readonly capability: string;
		readonly paneSessionId: string;
		readonly workerInstanceId: string;
	}) {
		this.#baseURL = props.baseURL;
		this.#bootstrap = props.bootstrap;
		this.#capability = props.capability;
		this.#paneSessionId = props.paneSessionId;
		this.#workerInstanceId = props.workerInstanceId;
	}

	static async connect(baseURL: string): Promise<LiveProductClient> {
		const response = await fetch(`${baseURL}${BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE}`, {
			body: JSON.stringify({ reason: 'initial' }),
			headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE },
			method: 'POST',
		});
		const responseMediaType = response.headers.get('content-type');
		expect(response.status).toBe(200);
		expect(responseMediaType).toBe(BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE);
		const delivery = decodeBridgeProductDevBootstrapDelivery(await response.arrayBuffer());
		return new LiveProductClient({
			baseURL,
			bootstrap: delivery.bootstrap,
			capability: encodeBridgeProductCapabilityHeader(delivery.productCapability),
			paneSessionId: delivery.bootstrap.paneSessionId,
			workerInstanceId: delivery.bootstrap.workerInstanceId,
		});
	}

	productSessionInstallInput(): {
		readonly bootstrap: BridgeProductSessionBootstrap;
		readonly productCapability: ArrayBuffer;
	} {
		return {
			bootstrap: this.#bootstrap,
			productCapability: Uint8Array.from(Buffer.from(this.#capability, 'base64url')).buffer,
		};
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
			frames: new LiveFrames(reader, async (frame) => await this.#observeMetadataFrame(frame)),
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
		if (response.body === null) throw new Error('Expected the live content body.');
		const decoder = new BridgeProductContentStreamDecoder(request);
		const reader = response.body.getReader();
		let terminal: Awaited<ReturnType<typeof decoder.push>>['terminal'] = null;
		while (true) {
			// oxlint-disable-next-line no-await-in-loop -- Content response chunks preserve frame order.
			const chunk = await reader.read();
			if (chunk.done) break;
			// oxlint-disable-next-line no-await-in-loop -- Content frame validation is ordered.
			const decoded = await decoder.push(chunk.value);
			for (const frame of decoded.frames) {
				// oxlint-disable-next-line no-await-in-loop -- Each physical content frame requires an exact observation.
				await this.#observeContentFrame(request, frame.header.contentSequence);
			}
			terminal = decoded.terminal ?? terminal;
		}
		decoder.finish();
		if (terminal?.kind !== 'complete') {
			throw new Error('Expected the live File content stream to complete.');
		}
		return {
			byteLength: terminal.bytes.byteLength,
			contentKind: terminal.contentKind,
			status: response.status,
			terminalKind: terminal.kind,
		};
	}

	async #observeContentFrame(
		request: ReturnType<typeof bridgeProductContentRequestSchema.parse>,
		contentSequence: number,
	): Promise<void> {
		const response = await fetch(
			`${this.#baseURL}/__bridge-product/command?scenario=current-worktree`,
			{
				body: JSON.stringify({
					contentRequestId: request.contentRequestId,
					contentSequence,
					kind: 'stream.frameObserved',
					leaseId: request.leaseId,
					paneSessionId: request.paneSessionId,
					streamKind: 'content',
					wireVersion: request.wireVersion,
					workerInstanceId: request.workerInstanceId,
				}),
				headers: this.#headers(),
				method: 'POST',
			},
		);
		expect(response.status).toBe(204);
		expect(await response.text()).toBe('');
	}

	async #observeMetadataFrame(frame: BridgeProductMetadataFrame): Promise<void> {
		const response = await fetch(
			`${this.#baseURL}/__bridge-product/command?scenario=current-worktree`,
			{
				body: JSON.stringify({
					kind: 'stream.frameObserved',
					metadataStreamId: frame.metadataStreamId,
					paneSessionId: frame.paneSessionId,
					streamKind: 'metadata',
					streamSequence: frame.streamSequence,
					wireVersion: frame.wireVersion,
					workerInstanceId: frame.workerInstanceId,
				}),
				headers: this.#headers(),
				method: 'POST',
			},
		);
		expect(response.status).toBe(204);
		expect(await response.text()).toBe('');
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
