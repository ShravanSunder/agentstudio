import { describe, expect, test } from 'vitest';

import { rejectOwnedViteStartupAfterCleanup } from '../tests/e2e/bridge-viewer-vite-product-fixture.ts';

describe('Bridge Viewer owned Vite startup cleanup', () => {
	test('does not reject startup until forced termination has an observed exit', async () => {
		// Arrange
		const startupError = new Error('owned Vite readiness failed');
		const exit = makeDeferred<{
			readonly code: number | null;
			readonly signal: NodeJS.Signals | null;
		}>();
		const observedSignals: NodeJS.Signals[] = [];
		let waitAttempt = 0;
		let rejectionObserved = false;

		// Act
		const rejection = rejectOwnedViteStartupAfterCleanup({
			child: {
				kill: (signal): boolean => {
					observedSignals.push(signal);
					return true;
				},
				pid: 42,
			},
			exitPromise: exit.promise,
			shutdownDependencies: {
				processIsAlive: (): boolean => false,
				waitForExitWithinDeadline: async (exitPromise) => {
					waitAttempt += 1;
					return waitAttempt === 1 ? null : await exitPromise;
				},
			},
			startupError,
		});
		void rejection.catch((): void => {
			rejectionObserved = true;
		});
		await flushMicrotasks();

		// Assert
		expect(observedSignals).toEqual(['SIGTERM', 'SIGKILL']);
		expect(rejectionObserved).toBe(false);

		// Act
		exit.resolve({ code: null, signal: 'SIGKILL' });

		// Assert
		await expect(rejection).rejects.toBe(startupError);
		expect(rejectionObserved).toBe(true);
	});

	test('reports cleanup failure when forced termination has no observed exit and remains alive', async () => {
		// Arrange
		const startupError = new Error('owned Vite readiness failed');
		const observedSignals: NodeJS.Signals[] = [];

		// Act
		const rejection = rejectOwnedViteStartupAfterCleanup({
			child: {
				kill: (signal): boolean => {
					observedSignals.push(signal);
					return true;
				},
				pid: 43,
			},
			exitPromise: new Promise((): void => {}),
			shutdownDependencies: {
				processIsAlive: (): boolean => true,
				waitForExitWithinDeadline: async (): Promise<null> => null,
			},
			startupError,
		});

		// Assert
		await expect(rejection).rejects.toThrow(/OWNED_VITE_STARTUP_CLEANUP_FAILED/u);
		expect(observedSignals).toEqual(['SIGTERM', 'SIGKILL']);
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
