import { describe, expect, test } from 'vitest';

import {
	createBridgeDevelopmentServerSupervisor,
	type BridgeDevelopmentServerSupervisorClock,
	type BridgeDevelopmentServerSupervisorClockOperation,
} from './bridge-development-server-supervisor.ts';

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly reject: (error: unknown) => void;
	readonly resolve: (value: TValue) => void;
}

class ManualSupervisorClock implements BridgeDevelopmentServerSupervisorClock {
	private currentTimeMilliseconds = 0;
	private nextOperationId = 0;
	private readonly operations = new Map<
		number,
		{ readonly deadlineMilliseconds: number; readonly operation: () => void }
	>();

	schedule(
		delayMilliseconds: number,
		operation: () => void,
	): BridgeDevelopmentServerSupervisorClockOperation {
		this.nextOperationId += 1;
		const operationId = this.nextOperationId;
		this.operations.set(operationId, {
			deadlineMilliseconds: this.currentTimeMilliseconds + delayMilliseconds,
			operation,
		});
		return {
			cancel: (): void => {
				this.operations.delete(operationId);
			},
		};
	}

	advanceBy(delayMilliseconds: number): void {
		this.currentTimeMilliseconds += delayMilliseconds;
		const dueOperations = [...this.operations.entries()]
			.filter(([, scheduled]) => scheduled.deadlineMilliseconds <= this.currentTimeMilliseconds)
			.toSorted(
				([leftId, left], [rightId, right]): number =>
					left.deadlineMilliseconds - right.deadlineMilliseconds || leftId - rightId,
			);
		for (const [operationId, scheduled] of dueOperations) {
			this.operations.delete(operationId);
			scheduled.operation();
		}
	}
}

describe('Bridge development server supervisor', () => {
	test('builds once after the complete relevant-change burst has been quiet for ten seconds', async () => {
		// Arrange: removing the trailing reset would build after the first edit's deadline.
		const clock = new ManualSupervisorClock();
		let buildCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {
				buildCount += 1;
			},
			clock,
			launchServer: async () => ownedServer(),
			report: (): void => {},
		});
		await supervisor.start();
		buildCount = 0;

		// Act
		supervisor.recordRelevantChange();
		clock.advanceBy(9_000);
		supervisor.recordRelevantChange();
		clock.advanceBy(9_999);
		await flushMicrotasks();
		const countBeforeCompleteQuietWindow = buildCount;
		clock.advanceBy(1);
		await flushMicrotasks();

		// Assert
		expect(countBeforeCompleteQuietWindow).toBe(0);
		expect(buildCount).toBe(1);
		await supervisor.stop();
	});

	test('keeps the running server alive when a replacement build fails', async () => {
		// Arrange: stopping before build success would record a server stop here.
		const clock = new ManualSupervisorClock();
		let buildCount = 0;
		let serverStopCount = 0;
		const reports: string[] = [];
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {
				buildCount += 1;
				if (buildCount === 2) throw new Error('candidate did not compile');
			},
			clock,
			launchServer: async () =>
				ownedServer((): void => {
					serverStopCount += 1;
				}),
			report: (message): void => {
				reports.push(message);
			},
		});
		await supervisor.start();

		// Act
		supervisor.recordRelevantChange();
		clock.advanceBy(10_000);
		await flushMicrotasks();

		// Assert
		expect(serverStopCount).toBe(0);
		expect(reports.some((message) => message.includes('candidate did not compile'))).toBe(true);
		await supervisor.stop();
		expect(serverStopCount).toBe(1);
	});

	test('retains cleanup authority when stopping the previous server fails', async () => {
		// Clearing ownership before stop succeeds loses the only handle that shutdown can retry.
		const clock = new ManualSupervisorClock();
		const reports: string[] = [];
		const unhandledRejections: unknown[] = [];
		let launchCount = 0;
		let previousServerStopAttemptCount = 0;
		const unhandledRejectionListener = (reason: unknown): void => {
			unhandledRejections.push(reason);
		};
		process.on('unhandledRejection', unhandledRejectionListener);
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {},
			clock,
			launchServer: async () => {
				launchCount += 1;
				return {
					stop: async (): Promise<void> => {
						previousServerStopAttemptCount += 1;
						if (previousServerStopAttemptCount === 1) {
							throw new Error('previous server refused to stop');
						}
					},
					whenExited: new Promise<void>(() => {}),
				};
			},
			report: (message): void => {
				reports.push(message);
			},
		});

		try {
			await supervisor.start();

			// Act
			supervisor.recordRelevantChange();
			clock.advanceBy(10_000);
			await flushMicrotasks();
			await nextEventLoopTurn();
			const launchCountAfterFailedStop = launchCount;
			await supervisor.stop();

			// Assert
			expect(launchCountAfterFailedStop).toBe(1);
			expect(previousServerStopAttemptCount).toBe(2);
			expect(
				reports.some(
					(message) =>
						message.includes('previous server refused to stop') &&
						message.includes('retaining cleanup authority'),
				),
			).toBe(true);
			expect(unhandledRejections).toEqual([]);
		} finally {
			process.off('unhandledRejection', unhandledRejectionListener);
		}
	});

	test('does not restart from a successful build when source changed during compilation', async () => {
		// Arrange: removing the generation fence would stop server 1 after build 2.
		const clock = new ManualSupervisorClock();
		const secondBuild = deferred<void>();
		let buildCount = 0;
		let launchCount = 0;
		const stoppedServers: number[] = [];
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {
				buildCount += 1;
				if (buildCount === 2) await secondBuild.promise;
			},
			clock,
			launchServer: async () => {
				launchCount += 1;
				const serverNumber = launchCount;
				return ownedServer((): void => {
					stoppedServers.push(serverNumber);
				});
			},
			report: (): void => {},
		});
		await supervisor.start();
		supervisor.recordRelevantChange();
		clock.advanceBy(10_000);
		await flushMicrotasks();

		// Act
		supervisor.recordRelevantChange();
		secondBuild.resolve();
		await flushMicrotasks();
		const stoppedAfterStaleBuild = [...stoppedServers];
		clock.advanceBy(10_000);
		await flushMicrotasks();

		// Assert
		expect(stoppedAfterStaleBuild).toEqual([]);
		expect(stoppedServers).toEqual([1]);
		expect(launchCount).toBe(2);
		await supervisor.stop();
	});

	test('aborts a timed-out replacement build without stopping the running server', async () => {
		// Arrange: losing the build deadline would leave the supervisor permanently wedged.
		const clock = new ManualSupervisorClock();
		let buildCount = 0;
		let replacementBuildWasAborted = false;
		let serverStopCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (signal): Promise<void> => {
				buildCount += 1;
				if (buildCount === 1) return;
				await new Promise<void>((_resolve, reject): void => {
					signal.addEventListener(
						'abort',
						(): void => {
							replacementBuildWasAborted = true;
							reject(signal.reason);
						},
						{ once: true },
					);
				});
			},
			clock,
			launchServer: async () =>
				ownedServer((): void => {
					serverStopCount += 1;
				}),
			report: (): void => {},
		});
		await supervisor.start();
		supervisor.recordRelevantChange();
		clock.advanceBy(10_000);
		await flushMicrotasks();

		// Act
		clock.advanceBy(300_000);
		await flushMicrotasks();

		// Assert
		expect(replacementBuildWasAborted).toBe(true);
		expect(serverStopCount).toBe(0);
		await supervisor.stop();
	});

	test('retries a failed replacement launch from the successful build after a bounded delay', async () => {
		// Rebuilding or waiting for another edit would leave Vite without a backend after transient launch failure.
		const clock = new ManualSupervisorClock();
		let buildCount = 0;
		let launchCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {
				buildCount += 1;
			},
			clock,
			launchServer: async () => {
				launchCount += 1;
				if (launchCount === 2) throw new Error('transient bind failure');
				return ownedServer();
			},
			report: (): void => {},
		});
		await supervisor.start();

		// Act
		supervisor.recordRelevantChange();
		clock.advanceBy(10_000);
		await flushMicrotasks();
		const launchCountBeforeRetryDelay = launchCount;
		clock.advanceBy(999);
		await flushMicrotasks();
		const launchCountBeforeCompleteRetryDelay = launchCount;
		clock.advanceBy(1);
		await flushMicrotasks();

		// Assert
		expect(launchCountBeforeRetryDelay).toBe(2);
		expect(launchCountBeforeCompleteRetryDelay).toBe(2);
		expect(launchCount).toBe(3);
		expect(buildCount).toBe(2);
		await supervisor.stop();
	});

	test('cancels a pending launch retry when the supervisor stops', async () => {
		// A retry callback surviving stop would relaunch an owned backend during Vite shutdown.
		const clock = new ManualSupervisorClock();
		let launchCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {},
			clock,
			launchServer: async () => {
				launchCount += 1;
				if (launchCount === 2) throw new Error('transient bind failure');
				return ownedServer();
			},
			report: (): void => {},
		});
		await supervisor.start();
		supervisor.recordRelevantChange();
		clock.advanceBy(10_000);
		await flushMicrotasks();

		// Act
		const stopPromise = supervisor.stop();
		await stopPromise;
		clock.advanceBy(1_000);
		await flushMicrotasks();

		// Assert
		expect(launchCount).toBe(2);
	});

	test('stops retrying after three failed launches', async () => {
		// An unbounded retry loop would keep Vite startup pending forever on a persistent launch error.
		const clock = new ManualSupervisorClock();
		let launchCount = 0;
		let startSettled = false;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {},
			clock,
			launchServer: async () => {
				launchCount += 1;
				throw new Error('persistent bind failure');
			},
			report: (): void => {},
		});

		// Act
		const startPromise = supervisor.start();
		void startPromise.then((): void => {
			startSettled = true;
		});
		await flushMicrotasks();
		clock.advanceBy(1_000);
		await flushMicrotasks();
		clock.advanceBy(1_000);
		await flushMicrotasks();
		await flushMicrotasks();

		// Assert
		expect(launchCount).toBe(3);
		expect(startSettled).toBe(true);
		await startPromise;
		await supervisor.stop();
	});

	test('rebuilds and relaunches when the ready backend exits unexpectedly', async () => {
		// A ready backend can exit hours after Vite starts. Leaving the frontend
		// alive without observing that exit permanently turns every proxy route
		// into 502 until the developer restarts Vite.
		const firstServerExit = deferred<void>();
		let buildCount = 0;
		let launchCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {
				buildCount += 1;
			},
			launchServer: async () => {
				launchCount += 1;
				return {
					stop: async (): Promise<void> => {},
					whenExited: launchCount === 1 ? firstServerExit.promise : new Promise<void>(() => {}),
				};
			},
			report: (): void => {},
		});
		await supervisor.start();

		// Act
		firstServerExit.resolve();
		await flushMicrotasks();

		// Assert
		expect(buildCount).toBe(2);
		expect(launchCount).toBe(2);
		await supervisor.stop();
	});

	test('does not relaunch when supervisor shutdown causes the backend exit', async () => {
		const serverExit = deferred<void>();
		let launchCount = 0;
		const supervisor = createBridgeDevelopmentServerSupervisor({
			buildCandidate: async (): Promise<void> => {},
			launchServer: async () => {
				launchCount += 1;
				return {
					stop: async (): Promise<void> => {
						serverExit.resolve();
						await serverExit.promise;
					},
					whenExited: serverExit.promise,
				};
			},
			report: (): void => {},
		});
		await supervisor.start();

		// Act
		await supervisor.stop();
		await flushMicrotasks();

		// Assert
		expect(launchCount).toBe(1);
	});
});

function ownedServer(onStop: () => void = (): void => {}): {
	readonly stop: () => Promise<void>;
	readonly whenExited: Promise<void>;
} {
	return {
		stop: async (): Promise<void> => {
			onStop();
		},
		whenExited: new Promise<void>(() => {}),
	};
}

function deferred<TValue>(): Deferred<TValue> {
	let resolve!: (value: TValue) => void;
	let reject!: (error: unknown) => void;
	const promise = new Promise<TValue>((promiseResolve, promiseReject): void => {
		resolve = promiseResolve;
		reject = promiseReject;
	});
	return { promise, reject, resolve };
}

async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

async function nextEventLoopTurn(): Promise<void> {
	await new Promise<void>((resolve): void => {
		setImmediate(resolve);
	});
}
