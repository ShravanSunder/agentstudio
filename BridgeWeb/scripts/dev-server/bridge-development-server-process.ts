import { execFile, spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
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
	const exitPromise = new Promise<ChildProcessExit>((resolve): void => {
		child.once('exit', (code, signal): void => resolve({ code, signal }));
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
		await waitForServerReadiness({
			child,
			exitPromise,
			origin,
			stderrTail: (): string => stderrTail,
			stdoutTail: (): string => stdoutTail,
		});
	} catch (error: unknown) {
		await stopOwnedProcess(child, exitPromise);
		throw error;
	}
	return {
		origin,
		pid: child.pid ?? 0,
		stop: async (): Promise<OwnedBridgeDevelopmentServerCleanup> =>
			await stopOwnedProcess(child, exitPromise),
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

async function waitForServerReadiness(props: {
	readonly child: ChildProcessWithoutNullStreams;
	readonly exitPromise: Promise<ChildProcessExit>;
	readonly origin: string;
	readonly stderrTail: () => string;
	readonly stdoutTail: () => string;
}): Promise<void> {
	const deadline = Date.now() + startupTimeoutMilliseconds;
	while (Date.now() < deadline) {
		const exit = await settledValue(props.exitPromise);
		if (exit !== null) {
			throw new Error(
				`Owned Swift development backend exited before readiness: ${JSON.stringify({ exit, stderrTail: props.stderrTail(), stdoutTail: props.stdoutTail() })}`,
			);
		}
		try {
			const response = await fetch(`${props.origin}${BRIDGE_PRODUCT_DEV_HEALTH_ROUTE}`, {
				method: 'GET',
				signal: AbortSignal.timeout(1_000),
			});
			await response.body?.cancel();
			if (bridgeDevelopmentServerHealthResponseIsReady(response)) return;
		} catch {
			await new Promise<void>((resolve): void => {
				setTimeout(resolve, readinessProbeIntervalMilliseconds);
			});
		}
	}
	throw new Error(
		`Timed out waiting for owned Swift development backend: ${JSON.stringify({ stderrTail: props.stderrTail(), stdoutTail: props.stdoutTail() })}`,
	);
}

export function bridgeDevelopmentServerHealthResponseIsReady(response: Response): boolean {
	return response.status === 204;
}

async function stopOwnedProcess(
	child: ChildProcessWithoutNullStreams,
	exitPromise: Promise<ChildProcessExit>,
): Promise<OwnedBridgeDevelopmentServerCleanup> {
	const pid = child.pid ?? null;
	child.kill('SIGTERM');
	let forcedTerminationRequired = false;
	let exit = await withBoundedTimeoutOrNull(exitPromise, shutdownTimeoutMilliseconds);
	if (exit === null) {
		forcedTerminationRequired = true;
		child.kill('SIGKILL');
		exit = await withBoundedTimeoutOrNull(exitPromise, shutdownTimeoutMilliseconds);
	}
	return {
		exitCode: exit?.code ?? null,
		exitSignal: exit?.signal ?? null,
		forcedTerminationRequired,
		ownedProcessAliveAfterStop: pid === null ? false : processIsAlive(pid),
	};
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
