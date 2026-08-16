import { createServer } from 'node:http';

import { describe, expect, expectTypeOf, test } from 'vitest';

import {
	bridgeDevelopmentServerArguments,
	bridgeDevelopmentServerExecutablePath,
	bridgeDevelopmentServerProcessOwnsListeningPort,
	resolveBridgeDevelopmentServerPort,
	runAllOwnedCleanupOperations,
	startOwnedBridgeDevelopmentServer,
	stopOwnedBridgeDevelopmentServerProcess,
	waitForBridgeDevelopmentServerReadiness,
} from './bridge-development-server-process.ts';

describe('owned Bridge development server executable', () => {
	test('start contract requires persisted identity inputs', () => {
		expectTypeOf(startOwnedBridgeDevelopmentServer).parameter(0).toEqualTypeOf<{
			readonly dataRootPath: string;
			readonly initialTarget: string;
			readonly paneId: string;
			readonly port?: number;
			readonly repoRootPath: string;
			readonly worktreeRoot: string;
		}>();
	});

	test('uses the configured Vite proxy port without reserving another port', async () => {
		// Arrange: ignoring this value would launch a backend the fixed Vite proxy cannot reach.
		let reservePortCallCount = 0;

		// Act
		const port = await resolveBridgeDevelopmentServerPort({
			configuredPort: 43_871,
			reservePort: async (): Promise<number> => {
				reservePortCallCount += 1;
				return 43_872;
			},
		});

		// Assert
		expect(port).toBe(43_871);
		expect(reservePortCallCount).toBe(0);
	});

	test('reserves an isolated port when the caller does not configure one', async () => {
		// Arrange: the existing test fixtures require independent concurrent backend ports.
		let reservePortCallCount = 0;

		// Act
		const port = await resolveBridgeDevelopmentServerPort({
			reservePort: async (): Promise<number> => {
				reservePortCallCount += 1;
				return 43_872;
			},
		});

		// Assert
		expect(port).toBe(43_872);
		expect(reservePortCallCount).toBe(1);
	});

	test('launch arguments carry one isolated root and exact pane identity without base authority', () => {
		// Arrange
		const paneId = '019fe721-7d8b-7ca0-b5c7-89e5fd7463f3';

		// Act
		const developmentServerArguments = bridgeDevelopmentServerArguments({
			dataRootPath: '/tmp/bridge-development-data',
			initialTarget: 'refs/heads/review-base',
			paneId,
			port: 43_871,
			worktreeRoot: '/tmp/repository',
		});

		// Assert
		expect(developmentServerArguments).toEqual([
			'--data-root',
			'/tmp/bridge-development-data',
			'--pane-id',
			paneId,
			'--seed-worktree',
			'/tmp/repository',
			'--seed-target',
			'refs/heads/review-base',
			'--port',
			'43871',
		]);
		expect(developmentServerArguments).not.toContain('--base');
	});

	test('resolves the prebuilt stable artifact path', () => {
		// Arrange
		const repoRootPath = '/tmp/agent-studio';

		// Act
		const executablePath = bridgeDevelopmentServerExecutablePath(repoRootPath);

		// Assert
		expect(executablePath).toBe(
			'/tmp/agent-studio/.build-bridge-development-server/agentstudio-bridge-dev-server',
		);
	});
});

describe('owned Bridge development server lifecycle', () => {
	test('rejects a healthy response served by a process other than the owned child', async () => {
		// A process already listening on the selected origin must not satisfy owned-child readiness.
		const collider = createServer((_request, response): void => {
			response.writeHead(204).end();
		});
		await new Promise<void>((resolve, reject): void => {
			collider.once('error', reject);
			collider.listen(0, '127.0.0.1', (): void => resolve());
		});
		const address = collider.address();
		if (address === null || typeof address === 'string') {
			throw new Error('Collider did not bind a loopback TCP port.');
		}
		const observedTimes = [0, 0, 120_001];

		try {
			expect(
				await bridgeDevelopmentServerProcessOwnsListeningPort({
					pid: process.pid,
					port: address.port,
				}),
			).toBe(true);

			// Act
			const readiness = waitForBridgeDevelopmentServerReadiness({
				currentTimeMilliseconds: (): number => observedTimes.shift() ?? 120_001,
				fetchHealth: async (healthUrl): Promise<Response> => await fetch(healthUrl),
				lifecycleOutcome: new Promise((): void => {}),
				origin: `http://127.0.0.1:${address.port}`,
				readinessOwnershipProbe: async (): Promise<boolean> =>
					await bridgeDevelopmentServerProcessOwnsListeningPort({
						pid: process.pid + 1_000_000,
						port: address.port,
					}),
				stderrTail: (): string => '',
				stdoutTail: (): string => '',
				waitForNextProbe: async (): Promise<void> => {},
			});

			// Assert
			await expect(readiness).rejects.toThrow(/Timed out waiting/u);
		} finally {
			await new Promise<void>((resolve, reject): void => {
				collider.close((error): void => (error === undefined ? resolve() : reject(error)));
			});
		}
	});

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
			readinessOwnershipProbe: async (): Promise<boolean> => true,
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
			readinessOwnershipProbe: async (): Promise<boolean> => true,
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
