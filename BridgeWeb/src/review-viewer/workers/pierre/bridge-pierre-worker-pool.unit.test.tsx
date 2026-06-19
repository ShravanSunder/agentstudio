// @vitest-environment jsdom

import type { WorkerInitializationRenderOptions, WorkerPoolOptions } from '@pierre/diffs/react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, expectTypeOf, test, vi } from 'vitest';

import { bridgePierreDarkThemeName } from '../../code-view/bridge-code-view-theme.js';
import {
	bridgePierreWorkerAssetManifestSchema,
	BridgePierreWorkerPoolProvider,
	bridgePierreDefaultWorkerScriptUrl,
	attachBridgePierreWorkerDiagnostics,
	createBridgePierreBlobWorkerFactory,
	createBridgePierreWorkerFactory,
	createBridgePierreWorkerHighlighterOptions,
	createBridgePierreWorkerPoolOptions,
	type BridgePierreWorkerAssetManifest,
} from './bridge-pierre-worker-pool.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

let mountedRoot: Root | null = null;

describe('Bridge Pierre worker pool', () => {
	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
		for (const datasetKey of Object.keys(document.documentElement.dataset)) {
			delete document.documentElement.dataset[datasetKey];
		}
		vi.unstubAllGlobals();
		vi.restoreAllMocks();
	});

	test('uses the packaged app worker URL as the default worker source', () => {
		expect(bridgePierreDefaultWorkerScriptUrl).toBe(
			'agentstudio://app/workers/pierre-diffs-worker-portable.js',
		);
	});

	test('creates a classic Worker by default for the packaged portable worker', () => {
		const createdWorkers: TestWorker[] = [];
		const workerFactory = createBridgePierreWorkerFactory({
			createWorker: (url: string | URL, options?: WorkerOptions): Worker => {
				const worker = new TestWorker(url, options);
				createdWorkers.push(worker);
				return worker;
			},
		});

		workerFactory();

		expect(createdWorkers).toEqual([
			expect.objectContaining({
				url: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
				options: undefined,
			}),
		]);
	});

	test('wraps Pierre message listeners instead of registering a competing listener', async () => {
		const worker = new ListenerOrderTestWorker('blob:bridge-pierre-worker');
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (): Worker => worker,
		});
		let consumerMessageCount = 0;

		workerFactory();
		worker.addEventListener('message', () => {
			consumerMessageCount++;
		});

		expect(worker.messageListenerOrder).toHaveLength(1);

		await Promise.resolve();
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					id: 'req_42',
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(worker.messageListenerOrder).toHaveLength(1);
		expect(consumerMessageCount).toBe(1);
		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticForwardedMessageCount'],
		).toBe('1');
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastForwardResult']).toBe(
			'ok',
		);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticSuccessCount']).toBe('1');
	});

	test('diagnostics do not starve the consumer when a worker only delivers the latest message listener', async () => {
		const worker = new LastMessageListenerWinsTestWorker('blob:bridge-pierre-worker');
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (): Worker => worker,
		});
		let consumerMessageCount = 0;

		workerFactory();
		worker.addEventListener('message', () => {
			consumerMessageCount++;
		});
		await Promise.resolve();
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					id: 'req_42',
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(consumerMessageCount).toBe(1);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticSuccessCount']).toBe('1');
	});

	test('creates a classic Worker from the packaged app worker URL', () => {
		const createdWorkers: TestWorker[] = [];
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
			workerKind: 'classicWorker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker => {
				const worker = new TestWorker(url, options);
				createdWorkers.push(worker);
				return worker;
			},
		});

		const worker = workerFactory();

		expect(worker).toBe(createdWorkers[0]);
		expect(createdWorkers).toEqual([
			expect.objectContaining({
				url: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
				options: undefined,
			}),
		]);
	});

	test('creates module workers only when manifest kind requires it', () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
			workerKind: 'moduleWorker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new TestWorker(url, options),
		});

		const worker = workerFactory();
		if (!(worker instanceof TestWorker)) {
			throw new Error('expected test worker instance');
		}

		expect(worker.options).toEqual({ type: 'module' });
	});

	test('derives worker pool and highlighter options from the factory', () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
			workerKind: 'classicWorker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new TestWorker(url, options),
		});

		const poolOptions = createBridgePierreWorkerPoolOptions({ workerFactory });
		const highlighterOptions = createBridgePierreWorkerHighlighterOptions();

		expect(poolOptions.workerFactory).toBe(workerFactory);
		expect(poolOptions.poolSize).toBeGreaterThan(0);
		expect(bridgePierreDarkThemeName).toBe('catppuccin-mocha');
		expect(highlighterOptions.theme).toEqual({
			dark: bridgePierreDarkThemeName,
			light: bridgePierreDarkThemeName,
		});
		expect(highlighterOptions.preferredHighlighter).toBe('shiki-js');
		expect(highlighterOptions.langs).toBeUndefined();
		expectTypeOf(poolOptions).toMatchTypeOf<WorkerPoolOptions>();
		expectTypeOf(highlighterOptions).toMatchTypeOf<WorkerInitializationRenderOptions>();
	});

	test('creates a blob-backed worker factory for WebKit custom-scheme pages', async () => {
		const createdWorkers: TestWorker[] = [];
		const revokedUrls: string[] = [];
		let workerScriptBlob: Blob | undefined;
		const blobWorker = createBridgePierreBlobWorkerFactory({
			workerSource: 'self.onmessage = function() {};',
			createObjectURL: (blob: Blob): string => {
				expect(blob.type).toBe('application/javascript');
				workerScriptBlob = blob;
				return 'blob:agentstudio-worker';
			},
			revokeObjectURL: (url: string): void => {
				revokedUrls.push(url);
			},
			createWorker: (url: string | URL, options?: WorkerOptions): Worker => {
				const worker = new TestWorker(url, options);
				createdWorkers.push(worker);
				return worker;
			},
		});

		const worker = blobWorker.workerFactory();
		blobWorker.revoke();

		expect(worker).toBe(createdWorkers[0]);
		expect(workerScriptBlob).not.toBeUndefined();
		const workerScriptSource = await workerScriptBlob?.text();
		expect(workerScriptSource).toContain('bridge-worker-bootstrap');
		expect(workerScriptSource).toContain('self.onmessage = function() {};');
		expect(createdWorkers).toEqual([
			expect.objectContaining({
				url: 'blob:agentstudio-worker',
				options: undefined,
			}),
		]);
		expect(revokedUrls).toEqual(['blob:agentstudio-worker']);
	});

	test('records worker bootstrap and Pierre response diagnostics on the document root', async () => {
		const createdWorkers: TestWorker[] = [];
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker => {
				const worker = new TestWorker(url, options);
				createdWorkers.push(worker);
				return worker;
			},
		});

		const worker = workerFactory();
		if (!(worker instanceof TestWorker)) {
			throw new Error('expected test worker instance');
		}
		worker.addEventListener('message', consumerMessageListenerSentinel);
		await Promise.resolve();
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					type: 'bridge-diagnostic',
					requestType: 'bridge-worker-bootstrap',
					phase: 'started',
				},
			}),
		);
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					type: 'success',
					requestType: 'diff',
				},
			}),
		);

		expect(createdWorkers).toHaveLength(1);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticBootstrapState']).toBe(
			'started',
		);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastMessageType']).toBe(
			'success',
		);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastRequestType']).toBe(
			'diff',
		);
		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessRequestType'],
		).toBe('diff');
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticSuccessCount']).toBe('2');
		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticInitializeSuccessCount'],
		).toBe('1');
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticDiffSuccessCount']).toBe(
			'1',
		);
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount']).toBe(
			'0',
		);
	});

	test('records whether Pierre success responses include a request id without exposing payloads', () => {
		const worker = new TestWorker('blob:bridge-pierre-worker');

		attachBridgePierreWorkerDiagnostics(worker);
		worker.addEventListener('message', consumerMessageListenerSentinel);
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					id: 'req_42',
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessIdState']).toBe(
			'present',
		);
		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessIdPrefix'],
		).toBe('req');
		expect(JSON.stringify(document.documentElement.dataset)).not.toContain('req_42');

		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessIdState']).toBe(
			'missing',
		);
		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessIdPrefix'],
		).toBe('none');
	});

	test('records whether initialize success ids match the request sent to the same worker', async () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new TestWorker(url, options),
		});

		const worker = workerFactory();
		worker.addEventListener('message', consumerMessageListenerSentinel);
		worker.postMessage(
			{
				id: 'req_42',
				type: 'initialize',
			},
			[],
		);
		await Promise.resolve();
		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					id: 'req_42',
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(
			document.documentElement.dataset['bridgePierreWorkerDiagnosticInitializeRequestIdState'],
		).toBe('present');
		expect(
			document.documentElement.dataset[
				'bridgePierreWorkerDiagnosticLastSuccessMatchesInitializeRequest'
			],
		).toBe('yes');
		expect(JSON.stringify(document.documentElement.dataset)).not.toContain('req_42');

		worker.dispatchEvent(
			new MessageEvent('message', {
				data: {
					id: 'req_43',
					type: 'success',
					requestType: 'initialize',
				},
			}),
		);

		expect(
			document.documentElement.dataset[
				'bridgePierreWorkerDiagnosticLastSuccessMatchesInitializeRequest'
			],
		).toBe('no');
	});

	test('records worker error diagnostics without raw error text', () => {
		const worker = new TestWorker('blob:bridge-pierre-worker');

		attachBridgePierreWorkerDiagnostics(worker);
		worker.dispatchEvent(new Event('error'));

		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticErrorCount']).toBe('1');
		expect(document.documentElement.dataset['bridgePierreWorkerDiagnosticLastErrorKind']).toBe(
			'worker-error',
		);
		expect(JSON.stringify(document.documentElement.dataset)).not.toContain('/Users/example');
	});

	test('validates packaged worker manifest fields as closed schemas', () => {
		const manifest = bridgePierreWorkerAssetManifestSchema.parse({
			kind: 'pierre-diffs-shiki',
			path: 'workers/pierre-diffs-worker-portable.js',
			agentStudioAppUrl: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
			workerKind: 'classicWorker',
			source: 'packagedAppAsset',
			bytes: 123,
			sha256: 'a'.repeat(64),
		});

		expect(manifest).toMatchObject({
			agentStudioAppUrl: 'agentstudio://app/workers/pierre-diffs-worker-portable.js',
			workerKind: 'classicWorker',
		});
		expectTypeOf(manifest).toMatchTypeOf<BridgePierreWorkerAssetManifest>();
		expect(() =>
			bridgePierreWorkerAssetManifestSchema.parse({
				...manifest,
				agentStudioAppUrl: 'https://example.com/worker.js',
			}),
		).toThrow();
		expect(() =>
			bridgePierreWorkerAssetManifestSchema.parse({
				...manifest,
				extra: 'not allowed',
			}),
		).toThrow();
	});

	test('does not mount CodeView children while the packaged worker source is loading', () => {
		installWorkerRuntimeDoubles({
			fetchImpl: () => new Promise<Response>(() => undefined),
		});

		renderWorkerPoolProvider();

		expect(
			document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="worker-pool-child"]')).toBeNull();
	});

	test('does not mount CodeView children while the CodeView theme is resolving', async () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new InitializeRespondingTestWorker(url, options),
		});
		const themeResolution = createDeferred<void>();

		renderWorkerPoolProvider({
			ensureCodeViewThemeResolved: async (): Promise<void> => themeResolution.promise,
			workerFactory,
		});
		await act(async (): Promise<void> => {
			await Promise.resolve();
		});

		expect(
			document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="worker-pool-child"]')).toBeNull();

		await act(async (): Promise<void> => {
			themeResolution.resolve();
			await themeResolution.promise;
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(document.querySelector('[data-testid="worker-pool-child"]')).not.toBeNull();
	});

	test('does not mount CodeView children while the Pierre worker pool is initializing', async () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new TestWorker(url, options),
		});

		renderWorkerPoolProvider({ enabled: true, workerFactory });
		await act(async (): Promise<void> => {
			await Promise.resolve();
		});

		expect(document.documentElement.dataset['bridgePierreWorkerPoolManagerState']).toBe(
			'initializing',
		);
		expect(
			document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="worker-pool-child"]')).toBeNull();
	});

	test('polls live worker stats when Pierre RAF stat broadcasts are delayed', async () => {
		vi.useFakeTimers();
		vi.stubGlobal(
			'requestAnimationFrame',
			vi.fn((): number => 1),
		);
		vi.stubGlobal('cancelAnimationFrame', vi.fn());
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new InitializeRespondingTestWorker(url, options),
		});

		renderWorkerPoolProvider({ enabled: true, workerFactory });
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(
			document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]'),
		).not.toBeNull();

		await act(async (): Promise<void> => {
			await vi.advanceTimersByTimeAsync(250);
		});

		expect(document.querySelector('[data-testid="worker-pool-child"]')).not.toBeNull();
		vi.useRealTimers();
	});

	test('renders an explicit degraded state instead of children when the worker source fails', async () => {
		installWorkerRuntimeDoubles({
			fetchImpl: async (): Promise<Response> => {
				throw new Error('worker unavailable');
			},
		});

		renderWorkerPoolProvider();
		await act(async (): Promise<void> => {
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(
			document.querySelector('[data-testid="bridge-pierre-worker-pool-failed"]'),
		).not.toBeNull();
		expect(document.querySelector('[data-testid="worker-pool-child"]')).toBeNull();
	});

	test('exposes public worker pool stats on the document root for native diagnostics', async () => {
		const workerFactory = createBridgePierreWorkerFactory({
			workerScriptUrl: 'blob:bridge-pierre-worker',
			createWorker: (url: string | URL, options?: WorkerOptions): Worker =>
				new TestWorker(url, options),
		});

		renderWorkerPoolProvider({ enabled: true, workerFactory });
		await act(async (): Promise<void> => {
			await Promise.resolve();
		});

		expect(document.documentElement.dataset['bridgePierreWorkerPoolState']).toBe('ready');
		expect(document.documentElement.dataset['bridgePierreWorkerPoolManagerState']).toMatch(
			/^(waiting|initializing|initialized)$/u,
		);
		expect(document.documentElement.dataset['bridgePierreWorkerPoolWorkersFailed']).toBe('false');
		expect(document.documentElement.dataset['bridgePierreWorkerPoolTotalWorkers']).toMatch(
			/^\d+$/u,
		);
		expect(document.documentElement.dataset['bridgePierreWorkerPoolQueuedTasks']).toMatch(/^\d+$/u);
	});
});

function renderWorkerPoolProvider(
	props: {
		readonly enabled?: boolean;
		readonly ensureCodeViewThemeResolved?: () => Promise<void>;
		readonly workerFactory?: () => Worker;
	} = {},
): void {
	const container = document.createElement('div');
	document.body.append(container);
	mountedRoot = createRoot(container);

	act((): void => {
		mountedRoot?.render(
			<BridgePierreWorkerPoolProvider
				{...(props.enabled === undefined ? {} : { enabled: props.enabled })}
				{...(props.ensureCodeViewThemeResolved === undefined
					? {}
					: { ensureCodeViewThemeResolved: props.ensureCodeViewThemeResolved })}
				{...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory })}
			>
				<div data-testid="worker-pool-child" />
			</BridgePierreWorkerPoolProvider>,
		);
	});
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
	readonly reject: (reason?: unknown) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveDeferred: ((value: TValue) => void) | undefined;
	let rejectDeferred: ((reason?: unknown) => void) | undefined;
	const promise = new Promise<TValue>((resolve, reject): void => {
		resolveDeferred = resolve;
		rejectDeferred = reject;
	});
	if (resolveDeferred === undefined || rejectDeferred === undefined) {
		throw new Error('expected Promise executor to initialize deferred callbacks');
	}

	return {
		promise,
		resolve: resolveDeferred,
		reject: rejectDeferred,
	};
}

function installWorkerRuntimeDoubles(props: { readonly fetchImpl: typeof fetch }): void {
	vi.stubGlobal('Worker', TestWorker);
	vi.stubGlobal('fetch', vi.fn(props.fetchImpl));
	Object.defineProperty(URL, 'createObjectURL', {
		configurable: true,
		value: vi.fn((): string => 'blob:bridge-pierre-worker'),
	});
	Object.defineProperty(URL, 'revokeObjectURL', {
		configurable: true,
		value: vi.fn(),
	});
}

class TestWorker extends EventTarget implements Worker {
	readonly url: string;
	readonly options: WorkerOptions | undefined;
	onmessage: ((this: Worker, event: MessageEvent) => void) | null = null;
	onmessageerror: ((this: Worker, event: MessageEvent) => void) | null = null;
	onerror: ((this: AbstractWorker, event: ErrorEvent) => void) | null = null;

	constructor(url: string | URL, options?: WorkerOptions) {
		super();
		this.url = String(url);
		this.options = options;
	}

	postMessage(message: unknown, transfer: Transferable[]): void;
	postMessage(message: unknown, options?: StructuredSerializeOptions): void;
	postMessage(): void {}

	terminate(): void {}

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		super.addEventListener(type, listener, options);
	}

	override removeEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void {
		super.removeEventListener(type, listener, options);
	}
}

class ListenerOrderTestWorker extends TestWorker {
	readonly messageListenerOrder: string[] = [];

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		if (type === 'message') {
			this.messageListenerOrder.push(
				listener === consumerMessageListenerSentinel ? 'consumer' : 'diagnostic',
			);
		}
		super.addEventListener(type, listener, options);
	}
}

class LastMessageListenerWinsTestWorker extends TestWorker {
	private currentMessageListener: EventListenerOrEventListenerObject | null = null;

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		if (type === 'message') {
			this.currentMessageListener = listener;
			return;
		}
		super.addEventListener(type, listener, options);
	}

	override removeEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void {
		if (type === 'message' && this.currentMessageListener === listener) {
			this.currentMessageListener = null;
			return;
		}
		super.removeEventListener(type, listener, options);
	}

	override dispatchEvent(event: Event): boolean {
		if (event.type !== 'message' || this.currentMessageListener === null) {
			return super.dispatchEvent(event);
		}
		if (typeof this.currentMessageListener === 'function') {
			this.currentMessageListener(event);
			return true;
		}
		this.currentMessageListener.handleEvent(event);
		return true;
	}
}

function consumerMessageListenerSentinel(): void {}

class InitializeRespondingTestWorker extends TestWorker {
	override postMessage(message: unknown, transfer: Transferable[]): void;
	override postMessage(message: unknown, options?: StructuredSerializeOptions): void;
	override postMessage(message: unknown): void {
		const workerRequest = workerRequestMessage(message);
		if (workerRequest === null) {
			return;
		}
		if (workerRequest.type !== 'initialize') {
			return;
		}
		queueMicrotask((): void => {
			this.dispatchEvent(
				new MessageEvent('message', {
					data: {
						type: 'success',
						requestType: 'initialize',
						id: workerRequest.id,
						sentAt: Date.now(),
					},
				}),
			);
		});
	}
}

function workerRequestMessage(
	message: unknown,
): { readonly id: string; readonly type: string } | null {
	if (typeof message !== 'object' || message === null) {
		return null;
	}
	const id = Reflect.get(message, 'id');
	const type = Reflect.get(message, 'type');
	if (typeof id !== 'string' || typeof type !== 'string') {
		return null;
	}
	return {
		id,
		type,
	};
}
