import type { SupportedLanguages } from '@pierre/diffs';
import type { WorkerPoolManager } from '@pierre/diffs/worker';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	loadBridgePierreDefaultWorkerFactory,
	resetBridgePierreWorkerFactoryLoaderForTest,
} from './bridge-pierre-worker-pool.js';
import {
	prewarmBridgePierreWorkerPool,
	resetBridgePierreWorkerPoolPrewarmForTest,
} from './bridge-pierre-worker-prewarm.js';

describe('Bridge Pierre worker factory loader', () => {
	afterEach(() => {
		resetBridgePierreWorkerPoolPrewarmForTest();
		resetBridgePierreWorkerFactoryLoaderForTest();
		vi.restoreAllMocks();
		vi.unstubAllGlobals();
		vi.useRealTimers();
	});

	test('shares one default packaged worker fetch across concurrent callers', async () => {
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-pierre-shared');
		const fetchWorkerSource = vi.fn(
			async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
				new Response('self.onmessage = () => undefined;', { status: 200 }),
		);
		vi.stubGlobal('fetch', fetchWorkerSource);

		const [leftFactory, rightFactory] = await Promise.all([
			loadBridgePierreDefaultWorkerFactory(),
			loadBridgePierreDefaultWorkerFactory(),
		]);

		expect(fetchWorkerSource).toHaveBeenCalledTimes(1);
		expect(leftFactory).toBe(rightFactory);
		expect(leftFactory.workerScriptUrl).toBe('blob:bridge-pierre-shared');
	});

	test('reset revokes the cached worker factory and allows a fresh load', async () => {
		vi.spyOn(URL, 'createObjectURL')
			.mockReturnValueOnce('blob:bridge-pierre-first')
			.mockReturnValueOnce('blob:bridge-pierre-second');
		const revokeObjectUrl = vi.spyOn(URL, 'revokeObjectURL').mockImplementation((): void => {});
		const fetchWorkerSource = vi.fn(
			async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
				new Response('self.onmessage = () => undefined;', { status: 200 }),
		);
		vi.stubGlobal('fetch', fetchWorkerSource);

		const firstFactory = await loadBridgePierreDefaultWorkerFactory();
		resetBridgePierreWorkerFactoryLoaderForTest();
		const secondFactory = await loadBridgePierreDefaultWorkerFactory();

		expect(fetchWorkerSource).toHaveBeenCalledTimes(2);
		expect(revokeObjectUrl).toHaveBeenCalledWith('blob:bridge-pierre-first');
		expect(firstFactory.workerScriptUrl).toBe('blob:bridge-pierre-first');
		expect(secondFactory.workerScriptUrl).toBe('blob:bridge-pierre-second');
	});

	test('rejects an in-flight load that resolves after reset', async () => {
		vi.spyOn(URL, 'createObjectURL')
			.mockReturnValueOnce('blob:bridge-pierre-stale')
			.mockReturnValueOnce('blob:bridge-pierre-fresh');
		const revokeObjectUrl = vi.spyOn(URL, 'revokeObjectURL').mockImplementation((): void => {});
		let resolveFirstFetch!: (response: Response) => void;
		const fetchWorkerSource = vi
			.fn<(_: RequestInfo | URL, _init?: RequestInit) => Promise<Response>>()
			.mockImplementationOnce(
				(_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
					new Promise<Response>((resolve): void => {
						resolveFirstFetch = resolve;
					}),
			)
			.mockImplementationOnce(
				async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
					new Response('self.onmessage = () => undefined;', { status: 200 }),
			);
		vi.stubGlobal('fetch', fetchWorkerSource);

		const staleLoadPromise = loadBridgePierreDefaultWorkerFactory();
		resetBridgePierreWorkerFactoryLoaderForTest();
		resolveFirstFetch(new Response('self.onmessage = () => undefined;', { status: 200 }));

		await expect(staleLoadPromise).rejects.toThrow('Bridge Pierre worker factory load was reset');
		const freshFactory = await loadBridgePierreDefaultWorkerFactory();

		expect(revokeObjectUrl).toHaveBeenCalledWith('blob:bridge-pierre-stale');
		expect(freshFactory.workerScriptUrl).toBe('blob:bridge-pierre-fresh');
		expect(fetchWorkerSource).toHaveBeenCalledTimes(2);
	});

	test('times out a parked packaged worker fetch instead of leaving the pool loading', async () => {
		vi.useFakeTimers();
		let fetchWasAborted = false;
		const fetchWorkerSource = vi.fn(
			(_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
				init?.signal?.addEventListener('abort', (): void => {
					fetchWasAborted = true;
				});
				return new Promise<Response>(() => undefined);
			},
		);
		vi.stubGlobal('fetch', fetchWorkerSource);

		const loadPromise = loadBridgePierreDefaultWorkerFactory();
		const rejectionExpectation = expect(loadPromise).rejects.toThrow(
			'Timed out loading packaged worker',
		);
		await vi.advanceTimersByTimeAsync(5_000);

		await rejectionExpectation;
		expect(fetchWasAborted).toBe(true);
	});

	test('default prewarm consumes the shared packaged worker factory', async () => {
		vi.stubGlobal('window', {});
		vi.stubGlobal('document', { documentElement: { dataset: {} } });
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-pierre-prewarm');
		const fetchWorkerSource = vi.fn(
			async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
				new Response('self.onmessage = () => undefined;', { status: 200 }),
		);
		vi.stubGlobal('fetch', fetchWorkerSource);
		const loadedFactory = await loadBridgePierreDefaultWorkerFactory();
		let prewarmWorkerFactory: (() => Worker) | null = null;

		await prewarmBridgePierreWorkerPool({
			languages: ['typescript'],
			ensureCodeViewThemeResolved: async (): Promise<void> => undefined,
			getWorkerPoolManager: (props): WorkerPoolManager => {
				prewarmWorkerFactory = props.workerFactory;
				return makeReadyWorkerPoolManager();
			},
		});

		expect(fetchWorkerSource).toHaveBeenCalledTimes(1);
		expect(prewarmWorkerFactory).toBe(loadedFactory.workerFactory);
	});

	test('shares one default packaged worker fetch across concurrent prewarm and pool load', async () => {
		vi.stubGlobal('window', {});
		vi.stubGlobal('document', { documentElement: { dataset: {} } });
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-pierre-concurrent');
		let resolveFetch!: (response: Response) => void;
		const fetchWorkerSource = vi.fn(
			(_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
				new Promise<Response>((resolve): void => {
					resolveFetch = resolve;
				}),
		);
		vi.stubGlobal('fetch', fetchWorkerSource);
		let prewarmWorkerFactory: (() => Worker) | null = null;

		const prewarmPromise = prewarmBridgePierreWorkerPool({
			languages: ['typescript'],
			ensureCodeViewThemeResolved: async (): Promise<void> => undefined,
			getWorkerPoolManager: (props): WorkerPoolManager => {
				prewarmWorkerFactory = props.workerFactory;
				return makeReadyWorkerPoolManager();
			},
		});
		const factoryPromise = loadBridgePierreDefaultWorkerFactory();
		resolveFetch(new Response('self.onmessage = () => undefined;', { status: 200 }));
		const loadedFactory = await factoryPromise;
		await prewarmPromise;

		expect(fetchWorkerSource).toHaveBeenCalledTimes(1);
		expect(loadedFactory.workerScriptUrl).toBe('blob:bridge-pierre-concurrent');
		expect(prewarmWorkerFactory).toBe(loadedFactory.workerFactory);
	});
});

function makeReadyWorkerPoolManager(): WorkerPoolManager {
	const workerPoolManager = {
		initialize: async (_languages: readonly SupportedLanguages[]): Promise<void> => undefined,
		subscribeToStatChanges: (): (() => void) => (): void => undefined,
	};
	// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- focused fake implements the prewarm-only WorkerPoolManager surface.
	return workerPoolManager as unknown as WorkerPoolManager;
}
