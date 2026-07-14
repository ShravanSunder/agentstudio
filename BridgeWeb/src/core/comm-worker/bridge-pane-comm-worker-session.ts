import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import { bridgeWorkerPierreRenderPolicy } from '../demand/bridge-content-demand-policy.js';
import { postBridgeCommTelemetryProducerInstall } from '../telemetry-worker/bridge-comm-telemetry-producer-install.js';
// oxlint-disable unicorn/require-post-message-target-origin -- Worker and MessagePort postMessage do not accept target origins.
import { readBridgeCommWorkerAbsoluteNowMilliseconds } from './bridge-comm-worker-telemetry.js';
import {
	postBridgePaneCommWorkerInstall,
	type BridgeProductSessionBootstrap,
} from './bridge-product-session-contracts.js';
import {
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export interface BridgePaneCommWorkerNativeBootstrap {
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly productCapability: ArrayBuffer;
}

export interface BridgePaneCommWorkerDispatcher {
	readonly dispatch: (message: BridgeWorkerMainToServerMessage) => void;
	readonly dispose: () => void;
}

export interface BridgePaneCommWorkerTelemetryProducerInstall {
	readonly enabledScopes: readonly BridgeTelemetryScope[];
	readonly preReadyRequiredSampleCapacity: number;
	readonly preReadyRequiredSampleMaxEncodedBytes: number;
	readonly producerPort: MessagePort;
}

export interface BridgePaneCommWorkerSessionProps {
	readonly bootstrapTimeoutMilliseconds?: number;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly now?: () => number;
	readonly requestNativeBootstrap?: (reason: 'workerReplacement') => void;
	readonly revokeObjectURL?: (url: string) => void;
	readonly workerFactory?: () => Promise<Worker> | Worker;
	readonly workerScriptUrl?: string;
}

interface BridgePaneCommWorkerClient {
	readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
}

const defaultWorkerScriptUrl = 'agentstudio://app/assets/bridge-comm-worker.js';

export class BridgePaneCommWorkerSession {
	readonly #clients = new Set<BridgePaneCommWorkerClient>();
	readonly #bootstrapTimeoutMilliseconds: number;
	readonly #now: () => number;
	readonly #queuedCommands: BridgeWorkerMainToServerMessage[] = [];
	#requestNativeBootstrap: (reason: 'workerReplacement') => void;
	readonly #workerFactory: () => Promise<Worker> | Worker;
	#bootstrapClient: BridgePaneCommWorkerClient | null = null;
	#bootstrapTimeout: ReturnType<typeof globalThis.setTimeout> | null = null;
	#isDisposed = false;
	#isRestartRequested = false;
	#isRuntimeReady = false;
	#mainPort: MessagePort | null = null;
	#nativeBootstrap: BridgePaneCommWorkerNativeBootstrap | null = null;
	#telemetryProducerInstall: BridgePaneCommWorkerTelemetryProducerInstall | null = null;
	#worker: Worker | null = null;
	#workerPromise: Promise<Worker> | null = null;

	constructor(props: BridgePaneCommWorkerSessionProps = {}) {
		this.#bootstrapTimeoutMilliseconds = props.bootstrapTimeoutMilliseconds ?? 5000;
		this.#now = props.now ?? readBridgeCommWorkerAbsoluteNowMilliseconds;
		this.#requestNativeBootstrap = props.requestNativeBootstrap ?? ((): void => {});
		this.#workerFactory =
			props.workerFactory ??
			createBridgePaneCommWorkerFactory({
				workerScriptUrl: props.workerScriptUrl ?? defaultWorkerScriptUrl,
				...(props.createObjectURL === undefined ? {} : { createObjectURL: props.createObjectURL }),
				...(props.revokeObjectURL === undefined ? {} : { revokeObjectURL: props.revokeObjectURL }),
			});
	}

	installNativeBootstrap(nativeBootstrap: BridgePaneCommWorkerNativeBootstrap): void {
		if (this.#isDisposed || this.#nativeBootstrap !== null) {
			throw new Error('Bridge pane comm worker native bootstrap was already consumed.');
		}
		if (this.#worker !== null || this.#workerPromise !== null) {
			this.#retireCurrentWorker();
		}
		this.#nativeBootstrap = nativeBootstrap;
		this.#isRestartRequested = false;
		void this.#ensureWorker().catch((): void => {});
	}

	setNativeBootstrapRequester(requestNativeBootstrap: (reason: 'workerReplacement') => void): void {
		if (this.#isDisposed) {
			return;
		}
		this.#requestNativeBootstrap = requestNativeBootstrap;
	}

	installTelemetryProducer(install: BridgePaneCommWorkerTelemetryProducerInstall): void {
		if (this.#isDisposed) {
			install.producerPort.close();
			return;
		}
		this.#telemetryProducerInstall?.producerPort.close();
		this.#telemetryProducerInstall = install;
		if (this.#worker !== null) {
			this.#postTelemetryProducerInstall(this.#worker);
		}
	}

	createDispatcher(props: {
		readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
		readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}): BridgePaneCommWorkerDispatcher {
		const client: BridgePaneCommWorkerClient = props;
		this.#clients.add(client);
		this.#bootstrapClient ??= client;
		return {
			dispatch: (message): void => {
				if (this.#isDisposed || !this.#clients.has(client)) {
					return;
				}
				if (!this.#isRuntimeReady || this.#mainPort === null) {
					this.#queuedCommands.push(message);
					void this.#ensureWorker().catch((): void => {});
					return;
				}
				this.#postCommand(message);
			},
			dispose: (): void => {
				this.#clients.delete(client);
			},
		};
	}

	dispose(): void {
		this.#isDisposed = true;
		this.#clearBootstrapTimeout();
		this.#clients.clear();
		this.#queuedCommands.splice(0, this.#queuedCommands.length);
		this.#telemetryProducerInstall?.producerPort.close();
		this.#telemetryProducerInstall = null;
		this.#retireCurrentWorker();
	}

	async #ensureWorker(): Promise<Worker> {
		if (this.#worker !== null) {
			return this.#worker;
		}
		if (this.#workerPromise !== null) {
			return await this.#workerPromise;
		}
		if (this.#nativeBootstrap === null || this.#bootstrapClient === null) {
			throw new Error('Bridge pane comm worker is waiting for native bootstrap.');
		}
		const nativeBootstrap = this.#nativeBootstrap;
		const bootstrapClient = this.#bootstrapClient;
		this.#nativeBootstrap = null;
		let candidateWorker: Worker | null = null;
		const workerPromise = Promise.resolve()
			.then((): Promise<Worker> | Worker => this.#workerFactory())
			.then((worker): Worker => {
				candidateWorker = worker;
				if (this.#isDisposed || this.#workerPromise !== workerPromise) {
					eraseBridgeProductCapability(nativeBootstrap.productCapability);
					worker.terminate();
					return worker;
				}
				const productChannel = new MessageChannel();
				const mainPort = productChannel.port2;
				this.#mainPort = mainPort;
				mainPort.addEventListener('message', (event): void => {
					if (this.#worker !== worker || this.#mainPort !== mainPort) {
						return;
					}
					const parsedMessage = bridgeWorkerServerToMainMessageSchema.safeParse(event.data);
					if (!parsedMessage.success) {
						this.#publishWorkerMessages([
							{
								wireVersion: 1,
								direction: 'serverWorkerToMain',
								kind: 'health',
								status: 'degraded',
								message: 'Bridge pane comm worker returned an invalid message.',
								transferDescriptors: [],
							},
						]);
						return;
					}
					if (
						parsedMessage.data.kind === 'health' &&
						parsedMessage.data.requestId === bootstrapClient.bootstrapRequest.requestId &&
						parsedMessage.data.status === 'ready'
					) {
						this.#isRuntimeReady = true;
						this.#clearBootstrapTimeout();
						this.#flushQueuedCommands();
					}
					this.#publishWorkerMessages([parsedMessage.data]);
				});
				mainPort.start();
				worker.addEventListener('error', (): void => this.#handleWorkerFailure(worker));
				worker.addEventListener('messageerror', (): void => this.#handleWorkerFailure(worker));
				postBridgePaneCommWorkerInstall(worker, {
					bootstrap: nativeBootstrap.bootstrap,
					kind: 'bridgePaneCommWorker.install',
					productCapability: nativeBootstrap.productCapability,
					productPort: productChannel.port1,
				});
				this.#postTelemetryProducerInstall(worker);
				mainPort.postMessage(
					bridgePaneCommWorkerBootstrapRequest(bootstrapClient.bootstrapRequest),
				);
				this.#worker = worker;
				this.#workerPromise = null;
				this.#bootstrapTimeout = globalThis.setTimeout((): void => {
					this.#handleWorkerFailure(worker);
				}, this.#bootstrapTimeoutMilliseconds);
				return worker;
			})
			.catch((error: unknown): never => {
				eraseBridgeProductCapability(nativeBootstrap.productCapability);
				if (candidateWorker !== null && this.#worker !== candidateWorker) {
					candidateWorker.terminate();
				}
				if (this.#workerPromise === workerPromise) {
					this.#retireCurrentWorker();
					this.#requestWorkerReplacementBootstrap();
				}
				throw error;
			});
		this.#workerPromise = workerPromise;
		return await workerPromise;
	}

	#postCommand(message: BridgeWorkerMainToServerMessage): void {
		this.#mainPort?.postMessage(
			bridgeWorkerMainToServerMessageSchema.parse({
				...message,
				issuedAtMilliseconds: this.#now(),
			}),
		);
	}

	#postTelemetryProducerInstall(worker: Worker): void {
		const install = this.#telemetryProducerInstall;
		if (install === null) {
			return;
		}
		this.#telemetryProducerInstall = null;
		postBridgeCommTelemetryProducerInstall(worker, {
			type: 'bridgePaneCommWorker.telemetryProducer.install',
			enabledScopes: install.enabledScopes,
			preReadyRequiredSampleCapacity: install.preReadyRequiredSampleCapacity,
			preReadyRequiredSampleMaxEncodedBytes: install.preReadyRequiredSampleMaxEncodedBytes,
			producerPort: install.producerPort,
		});
	}

	#flushQueuedCommands(): void {
		for (const command of this.#queuedCommands.splice(0, this.#queuedCommands.length)) {
			this.#postCommand(command);
		}
	}

	#publishWorkerMessages(messages: readonly BridgeWorkerServerToMainMessage[]): void {
		for (const client of this.#clients) {
			client.publishWorkerMessages(messages);
		}
	}

	#clearBootstrapTimeout(): void {
		if (this.#bootstrapTimeout === null) {
			return;
		}
		globalThis.clearTimeout(this.#bootstrapTimeout);
		this.#bootstrapTimeout = null;
	}

	#handleWorkerFailure(worker: Worker): void {
		if (this.#isDisposed || this.#worker !== worker) {
			return;
		}
		this.#retireCurrentWorker();
		this.#requestWorkerReplacementBootstrap();
	}

	#requestWorkerReplacementBootstrap(): void {
		if (this.#isDisposed || this.#isRestartRequested) {
			return;
		}
		this.#isRestartRequested = true;
		this.#requestNativeBootstrap('workerReplacement');
	}

	#retireCurrentWorker(): void {
		this.#clearBootstrapTimeout();
		this.#isRuntimeReady = false;
		this.#mainPort?.close();
		this.#mainPort = null;
		this.#worker?.terminate();
		this.#worker = null;
		this.#workerPromise = null;
	}
}

function bridgePaneCommWorkerBootstrapRequest(
	request: BridgeCommWorkerBootstrapRequest,
): BridgeCommWorkerBootstrapRequest {
	return {
		...request,
		runtime: {
			...request.runtime,
			surfacePolicies: {
				fileView: {
					bridgeDemandRank: { lane: 'selected', priority: 0 },
					budget: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
				},
				review: {
					bridgeDemandRank: { lane: 'selected', priority: 0 },
					budget: bridgeWorkerPierreRenderPolicy.reviewInteractiveRenderBudget,
				},
			},
		},
	};
}

function eraseBridgeProductCapability(productCapability: ArrayBuffer): void {
	new Uint8Array(productCapability).fill(0);
}

let defaultPaneSession: BridgePaneCommWorkerSession | null = null;

export function installBridgePaneCommWorkerSessionForHost(
	session: BridgePaneCommWorkerSession,
): void {
	if (defaultPaneSession !== null) {
		throw new Error('Bridge pane comm worker session host was already installed.');
	}
	defaultPaneSession = session;
}

export function getBridgePaneCommWorkerSession(): BridgePaneCommWorkerSession {
	defaultPaneSession ??= new BridgePaneCommWorkerSession();
	return defaultPaneSession;
}

export function createBridgePaneCommWorkerDispatcher(props: {
	readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
}): BridgePaneCommWorkerDispatcher {
	return getBridgePaneCommWorkerSession().createDispatcher(props);
}

export function disposeBridgePaneCommWorkerSession(): void {
	defaultPaneSession?.dispose();
	defaultPaneSession = null;
}

function createBridgePaneCommWorkerFactory(props: {
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
	readonly workerScriptUrl: string;
}): () => Promise<Worker> {
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	let workerScriptBlobUrl: string | null = null;

	return async (): Promise<Worker> => {
		if (workerScriptBlobUrl === null) {
			const response = await fetch(props.workerScriptUrl);
			if (!response.ok) {
				throw new Error(`Failed to load bridge comm worker: ${response.status}`);
			}
			const workerSource = await response.text();
			workerScriptBlobUrl = createObjectURL(
				new Blob([workerSource], { type: 'application/javascript' }),
			);
		}
		const worker = new Worker(workerScriptBlobUrl, { type: 'module' });
		worker.addEventListener(
			'error',
			(): void => {
				if (workerScriptBlobUrl !== null) {
					revokeObjectURL(workerScriptBlobUrl);
					workerScriptBlobUrl = null;
				}
			},
			{ once: true },
		);
		return worker;
	};
}
