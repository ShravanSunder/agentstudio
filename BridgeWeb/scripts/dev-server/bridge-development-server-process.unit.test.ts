import { describe, expect, test } from 'vitest';

import {
	runAllOwnedCleanupOperations,
	stopOwnedBridgeDevelopmentServerProcess,
	waitForBridgeDevelopmentServerReadiness,
} from './bridge-development-server-process.ts';

describe('owned Bridge development server lifecycle', () => {
	test('treats a child spawn error as a terminal readiness outcome', async () => {
		// Arrange
		const spawnError = new Error('spawn ENOENT');
		const lifecycleOutcome = makeDeferred<{
			readonly error: Error;
			readonly kind: 'spawn-error';
		}>();
		const healthResponse = makeDeferred<Response>();
		let healthProbeCount = 0;

		// Act
		const readiness = waitForBridgeDevelopmentServerReadiness({
			currentTimeMilliseconds: (): number => 0,
			fetchHealth: async (): Promise<Response> => {
				healthProbeCount += 1;
				return await healthResponse.promise;
			},
			lifecycleOutcome: lifecycleOutcome.promise,
			origin: 'http://127.0.0.1:1',
			stderrTail: (): string => '',
			stdoutTail: (): string => '',
			waitForNextProbe: async (): Promise<void> => {},
		});
		await flushMicrotasks();
		let rejectionObserved = false;
		void readiness.catch((): void => {
			rejectionObserved = true;
		});
		lifecycleOutcome.resolve({ error: spawnError, kind: 'spawn-error' });
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});
		const rejectedBeforeHealthResponse = rejectionObserved;
		healthResponse.resolve(new Response(null, { status: 503 }));

		// Assert
		expect(healthProbeCount).toBe(1);
		expect(rejectedBeforeHealthResponse).toBe(true);
		await expect(readiness).rejects.toThrow(/spawn ENOENT/u);
	});

	test('does not signal or wait for exit after a child spawn error', async () => {
		// Arrange
		const observedSignals: NodeJS.Signals[] = [];

		// Act
		const cleanup = await stopOwnedBridgeDevelopmentServerProcess(
			{
				kill: (signal): boolean => {
					observedSignals.push(signal);
					return true;
				},
			},
			Promise.resolve({ error: new Error('spawn ENOENT'), kind: 'spawn-error' }),
		);

		// Assert
		expect(cleanup).toEqual({
			exitCode: null,
			exitSignal: null,
			forcedTerminationRequired: false,
			ownedProcessAliveAfterStop: false,
		});
		expect(observedSignals).toEqual([]);
	});

	test('waits before retrying after a non-ready health response', async () => {
		// Arrange
		const events: string[] = [];
		let healthProbeCount = 0;

		// Act
		await waitForBridgeDevelopmentServerReadiness({
			currentTimeMilliseconds: (): number => 0,
			fetchHealth: async (): Promise<Response> => {
				healthProbeCount += 1;
				events.push(`probe-${healthProbeCount}`);
				return new Response(null, { status: healthProbeCount === 1 ? 503 : 204 });
			},
			lifecycleOutcome: new Promise((): void => {}),
			origin: 'http://127.0.0.1:1',
			stderrTail: (): string => '',
			stdoutTail: (): string => '',
			waitForNextProbe: async (): Promise<void> => {
				events.push('wait');
			},
		});

		// Assert
		expect(events).toEqual(['probe-1', 'wait', 'probe-2']);
	});
});

function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
} {
	let resolvePromise: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (value): void => {
			if (resolvePromise === null) throw new Error('Deferred promise resolver is unavailable.');
			resolvePromise(value);
		},
	};
}

async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
}

describe('owned Bridge development cleanup', () => {
	test('runs every cleanup and preserves the primary failure with cleanup failures', async () => {
		// Arrange
		const primaryError = new Error('journey failed');
		const firstCleanupError = new Error('Vite cleanup failed');
		const secondCleanupError = new Error('backend cleanup failed');
		const observedCleanupNames: string[] = [];

		// Act
		const cleanup = runAllOwnedCleanupOperations({
			operations: [
				{
					name: 'Vite',
					run: async (): Promise<void> => {
						observedCleanupNames.push('Vite');
						throw firstCleanupError;
					},
				},
				{
					name: 'backend',
					run: async (): Promise<void> => {
						observedCleanupNames.push('backend');
						throw secondCleanupError;
					},
				},
				{
					name: 'telemetry',
					run: async (): Promise<void> => {
						observedCleanupNames.push('telemetry');
					},
				},
			],
			primaryError,
		});

		// Assert
		await expect(cleanup).rejects.toEqual(
			expect.objectContaining({
				errors: [primaryError, firstCleanupError, secondCleanupError],
			}),
		);
		expect(observedCleanupNames).toEqual(['Vite', 'backend', 'telemetry']);
	});
});
