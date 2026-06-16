import type { WorkerInitializationRenderOptions, WorkerPoolOptions } from '@pierre/diffs/react';
import { describe, expect, expectTypeOf, test } from 'vitest';

import {
	bridgePierreWorkerAssetManifestSchema,
	createBridgePierreBlobWorkerFactory,
	createBridgePierreWorkerFactory,
	createBridgePierreWorkerHighlighterOptions,
	createBridgePierreWorkerPoolOptions,
	type BridgePierreWorkerAssetManifest,
} from './bridge-pierre-worker-pool.js';

describe('Bridge Pierre worker pool', () => {
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
		expect(highlighterOptions.theme).toEqual({
			dark: 'pierre-dark',
			light: 'pierre-dark',
		});
		expect(highlighterOptions.preferredHighlighter).toBe('shiki-js');
		expect(highlighterOptions.langs).toContain('swift');
		expectTypeOf(poolOptions).toMatchTypeOf<WorkerPoolOptions>();
		expectTypeOf(highlighterOptions).toMatchTypeOf<WorkerInitializationRenderOptions>();
	});

	test('creates a blob-backed worker factory for WebKit custom-scheme pages', () => {
		const createdWorkers: TestWorker[] = [];
		const revokedUrls: string[] = [];
		const blobWorker = createBridgePierreBlobWorkerFactory({
			workerSource: 'self.onmessage = function() {};',
			createObjectURL: (blob: Blob): string => {
				expect(blob.type).toBe('application/javascript');
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
		expect(createdWorkers).toEqual([
			expect.objectContaining({
				url: 'blob:agentstudio-worker',
				options: undefined,
			}),
		]);
		expect(revokedUrls).toEqual(['blob:agentstudio-worker']);
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
});

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
