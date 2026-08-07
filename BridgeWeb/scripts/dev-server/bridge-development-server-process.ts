import { execFile, spawn } from 'node:child_process';
import { access } from 'node:fs/promises';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { BRIDGE_PRODUCT_DEV_HEALTH_ROUTE } from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';

const execFileAsync = promisify(execFile);

const startupTimeoutMilliseconds = 120_000;
const shutdownTimeoutMilliseconds = 10_000;
const readinessProbeIntervalMilliseconds = 50;
const maximumLogTailCharacters = 8_192;

export interface OwnedBridgeDevelopmentServer {
	readonly origin: string;
	readonly pid: number;
	readonly stop: () => Promise<OwnedBridgeDevelopmentServerCleanup>;
}

export interface OwnedBridgeDevelopmentServerCleanup {
	readonly exitCode: number | null;
	readonly exitSignal: NodeJS.Signals | null;
	readonly forcedTerminationRequired: boolean;
	readonly ownedProcessAliveAfterStop: boolean;
}

interface ChildProcessExit {
	readonly code: number | null;
	readonly signal: NodeJS.Signals | null;
}

export type BridgeDevelopmentServerLifecycleOutcome =
	| ({ readonly kind: 'exit' } & ChildProcessExit)
	| { readonly error: Error; readonly kind: 'spawn-error' };

export interface OwnedCleanupOperation {
	readonly name: string;
	readonly run: () => Promise<void>;
}

export interface OwnedBridgeDevelopmentServerProcessControl {
	readonly pid?: number | undefined;
	readonly kill: (signal: NodeJS.Signals) => boolean;
}

type BridgeDevelopmentServerReadinessProbeOutcome =
	| {
			readonly kind: 'lifecycle';
			readonly outcome: BridgeDevelopmentServerLifecycleOutcome;
	  }
	| { readonly kind: 'probe-failed' }
	| { readonly kind: 'response'; readonly response: Response };

export async function startOwnedBridgeDevelopmentServer(props: {
	readonly baseRef: string;
	readonly repoRootPath: string;
	readonly worktreeRoot: string;
}): Promise<OwnedBridgeDevelopmentServer> {
	const port = await reserveLoopbackPort();
	const origin = `http://127.0.0.1:${port}`;
	const executablePath = await bridgeDevelopmentServerExecutablePath(props.repoRootPath);
	await access(executablePath);
	const child = spawn(
		executablePath,
		['--worktree', props.worktreeRoot, '--base', props.baseRef, '--port', String(port)],
		{
			cwd: props.repoRootPath,
			env: { ...process.env },
			stdio: ['pipe', 'pipe', 'pipe'],
		},
	);
	const lifecycleOutcome = new Promise<BridgeDevelopmentServerLifecycleOutcome>((resolve): void => {
		child.once('exit', (code, signal): void => resolve({ code, kind: 'exit', signal }));
		child.once('error', (error): void => resolve({ error, kind: 'spawn-error' }));
	});
	let stdoutTail = '';
	let stderrTail = '';
	child.stdout.setEncoding('utf8');
	child.stderr.setEncoding('utf8');
	child.stdout.on('data', (chunk: string): void => {
		stdoutTail = appendBoundedTail(stdoutTail, chunk);
	});
	child.stderr.on('data', (chunk: string): void => {
		stderrTail = appendBoundedTail(stderrTail, chunk);
	});
	try {
		await waitForBridgeDevelopmentServerReadiness({
			currentTimeMilliseconds: Date.now,
			fetchHealth: async (healthUrl): Promise<Response> =>
				await fetch(healthUrl, {
					method: 'GET',
					signal: AbortSignal.timeout(1_000),
				}),
			lifecycleOutcome,
			origin,
			stderrTail: (): string => stderrTail,
			stdoutTail: (): string => stdoutTail,
			waitForNextProbe: async (): Promise<void> => {
				await new Promise<void>((resolve): void => {
					setTimeout(resolve, readinessProbeIntervalMilliseconds);
				});
			},
		});
	} catch (error: unknown) {
		await stopOwnedBridgeDevelopmentServerProcess(child, lifecycleOutcome);
		throw error;
	}
	return {
		origin,
		pid: child.pid ?? 0,
		stop: async (): Promise<OwnedBridgeDevelopmentServerCleanup> =>
			await stopOwnedBridgeDevelopmentServerProcess(child, lifecycleOutcome),
	};
}

async function bridgeDevelopmentServerExecutablePath(repoRootPath: string): Promise<string> {
	const scratchPath = join(repoRootPath, '.build-bridge-development-server');
	const { stdout } = await execFileAsync(
		'swift',
		['build', '--package-path', repoRootPath, '--scratch-path', scratchPath, '--show-bin-path'],
		{ cwd: repoRootPath, encoding: 'utf8' },
	);
	return join(stdout.trim(), 'agentstudio-bridge-dev-server');
}

export async function waitForBridgeDevelopmentServerReadiness(props: {
	readonly currentTimeMilliseconds: () => number;
	readonly fetchHealth: (healthUrl: string) => Promise<Response>;
	readonly lifecycleOutcome: Promise<BridgeDevelopmentServerLifecycleOutcome>;
	readonly origin: string;
	readonly stderrTail: () => string;
	readonly stdoutTail: () => string;
	readonly waitForNextProbe: () => Promise<void>;
}): Promise<void> {
	const deadline = props.currentTimeMilliseconds() + startupTimeoutMilliseconds;
	// oxlint-disable no-await-in-loop -- Readiness probes are intentionally ordered and rate-limited.
	while (props.currentTimeMilliseconds() < deadline) {
		const probeOutcome = await Promise.race<BridgeDevelopmentServerReadinessProbeOutcome>([
			props.lifecycleOutcome.then(
				(outcome): BridgeDevelopmentServerReadinessProbeOutcome => ({
					kind: 'lifecycle',
					outcome,
				}),
			),
			props.fetchHealth(`${props.origin}${BRIDGE_PRODUCT_DEV_HEALTH_ROUTE}`).then(
				(response): BridgeDevelopmentServerReadinessProbeOutcome => ({
					kind: 'response',
					response,
				}),
				(): BridgeDevelopmentServerReadinessProbeOutcome => ({ kind: 'probe-failed' }),
			),
		]);
		if (probeOutcome.kind === 'lifecycle' && probeOutcome.outcome.kind === 'spawn-error') {
			throw new Error(
				`Owned Swift development backend failed to spawn before readiness: ${JSON.stringify({ error: probeOutcome.outcome.error.message, stderrTail: props.stderrTail(), stdoutTail: props.stdoutTail() })}`,
				{ cause: probeOutcome.outcome.error },
			);
		}
		if (probeOutcome.kind === 'lifecycle' && probeOutcome.outcome.kind === 'exit') {
			throw new Error(
				`Owned Swift development backend exited before readiness: ${JSON.stringify({ exit: probeOutcome.outcome, stderrTail: props.stderrTail(), stdoutTail: props.stdoutTail() })}`,
			);
		}
		if (probeOutcome.kind === 'response') {
			try {
				await probeOutcome.response.body?.cancel();
			} catch {}
			if (bridgeDevelopmentServerHealthResponseIsReady(probeOutcome.response)) return;
		}
		await props.waitForNextProbe();
	}
	// oxlint-enable no-await-in-loop
	throw new Error(
		`Timed out waiting for owned Swift development backend: ${JSON.stringify({ stderrTail: props.stderrTail(), stdoutTail: props.stdoutTail() })}`,
	);
}

export function bridgeDevelopmentServerHealthResponseIsReady(response: Response): boolean {
	return response.status === 204;
}

export async function stopOwnedBridgeDevelopmentServerProcess(
	child: OwnedBridgeDevelopmentServerProcessControl,
	lifecycleOutcome: Promise<BridgeDevelopmentServerLifecycleOutcome>,
): Promise<OwnedBridgeDevelopmentServerCleanup> {
	const pid = child.pid ?? null;
	const outcomeBeforeStop = await settledValue(lifecycleOutcome);
	if (outcomeBeforeStop?.kind === 'spawn-error') {
		return {
			exitCode: null,
			exitSignal: null,
			forcedTerminationRequired: false,
			ownedProcessAliveAfterStop: pid === null ? false : processIsAlive(pid),
		};
	}
	child.kill('SIGTERM');
	let forcedTerminationRequired = false;
	let outcome = await withBoundedTimeoutOrNull(lifecycleOutcome, shutdownTimeoutMilliseconds);
	if (outcome === null) {
		forcedTerminationRequired = true;
		child.kill('SIGKILL');
		outcome = await withBoundedTimeoutOrNull(lifecycleOutcome, shutdownTimeoutMilliseconds);
	}
	const exit = outcome?.kind === 'exit' ? outcome : null;
	return {
		exitCode: exit?.code ?? null,
		exitSignal: exit?.signal ?? null,
		forcedTerminationRequired,
		ownedProcessAliveAfterStop: pid === null ? false : processIsAlive(pid),
	};
}

export async function runAllOwnedCleanupOperations(props: {
	readonly operations: readonly OwnedCleanupOperation[];
	readonly primaryError?: unknown;
}): Promise<void> {
	const cleanupFailures: unknown[] = [];
	const failedCleanupNames: string[] = [];
	for (const operation of props.operations) {
		try {
			// oxlint-disable-next-line no-await-in-loop -- Cleanup order is owned and every operation must run after a predecessor failure.
			await operation.run();
		} catch (error: unknown) {
			cleanupFailures.push(error);
			failedCleanupNames.push(operation.name);
		}
	}
	if (cleanupFailures.length > 0) {
		throw new AggregateError(
			props.primaryError === undefined ? cleanupFailures : [props.primaryError, ...cleanupFailures],
			`Owned cleanup failed: ${failedCleanupNames.join(', ')}.`,
		);
	}
	if (props.primaryError !== undefined) throw props.primaryError;
}

async function reserveLoopbackPort(): Promise<number> {
	const server = createServer();
	await new Promise<void>((resolve, reject): void => {
		server.once('error', reject);
		server.listen(0, '127.0.0.1', (): void => resolve());
	});
	const address = server.address();
	if (address === null || typeof address === 'string') {
		server.close();
		throw new Error('Failed to reserve a loopback Swift development backend port.');
	}
	await new Promise<void>((resolve, reject): void => {
		server.close((error): void => (error === undefined ? resolve() : reject(error)));
	});
	return address.port;
}

async function settledValue<TValue>(promise: Promise<TValue>): Promise<TValue | null> {
	return await Promise.race([promise, Promise.resolve(null)]);
}

async function withBoundedTimeoutOrNull<TValue>(
	promise: Promise<TValue>,
	timeoutMilliseconds: number,
): Promise<TValue | null> {
	let timeout: ReturnType<typeof setTimeout> | null = null;
	try {
		return await Promise.race([
			promise,
			new Promise<null>((resolve): void => {
				timeout = setTimeout((): void => resolve(null), timeoutMilliseconds);
			}),
		]);
	} finally {
		if (timeout !== null) clearTimeout(timeout);
	}
}

function appendBoundedTail(current: string, next: string): string {
	return `${current}${next}`.slice(-maximumLogTailCharacters);
}

function processIsAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch (error: unknown) {
		return !(
			typeof error === 'object' &&
			error !== null &&
			'code' in error &&
			error.code === 'ESRCH'
		);
	}
}
