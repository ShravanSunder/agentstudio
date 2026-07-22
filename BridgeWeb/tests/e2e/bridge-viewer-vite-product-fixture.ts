import { execFile, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer as createHTTPServer } from 'node:http';
import { createServer as createTCPServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const bridgeWebRootPath = new URL('../../', import.meta.url).pathname;
const viteCLIPath = join(bridgeWebRootPath, 'node_modules/vite/bin/vite.js');
const serverStartupTimeoutMilliseconds = 30_000;
const serverShutdownTimeoutMilliseconds = 10_000;
const maximumServerLogTailCharacters = 8_192;

export interface BridgeViewerViteProductFixtureOracle {
	readonly baseRef: string;
	readonly changedPaths: readonly string[];
	readonly expectedReviewItemIds: readonly string[];
	readonly fileContent: BridgeViewerViteProductContentOracle;
	readonly fileTreeDeepPath: string;
	readonly largeFileLineCount: number;
	readonly largeFilePath: string;
	readonly largeFileSha256: string;
	readonly reviewFiles: readonly BridgeViewerViteProductReviewFileOracle[];
	readonly worktreeRoot: string;
}

export interface BridgeViewerViteProductContentOracle {
	readonly byteLength: number;
	readonly firstMarker: string;
	readonly finalMarker: string;
	readonly lineCount: number;
	readonly middleMarker: string;
	readonly sha256: string;
}

export interface BridgeViewerViteProductReviewFileOracle {
	readonly base: BridgeViewerViteProductReviewRoleOracle;
	readonly head: BridgeViewerViteProductReviewRoleOracle;
	readonly itemId: string;
	readonly path: string;
}

export interface BridgeViewerViteProductReviewRoleOracle {
	readonly body: string;
	readonly byteLength: number;
	readonly role: 'base' | 'head';
	readonly sha256: string;
}

export interface BridgeViewerOwnedViteProductServer {
	readonly origin: string;
	readonly pid: number;
	readonly stop: () => Promise<BridgeViewerOwnedViteProductServerCleanup>;
	readonly version: string | null;
}

export interface BridgeViewerOwnedViteProductServerCleanup {
	readonly exitCode: number | null;
	readonly exitObserved: boolean;
	readonly exitSignal: NodeJS.Signals | null;
	readonly forcedTerminationRequired: boolean;
	readonly ownedProcessAliveAfterStop: boolean;
}

export interface BridgeViewerOwnedViteProcessExit {
	readonly code: number | null;
	readonly signal: NodeJS.Signals | null;
}

export interface BridgeViewerOwnedViteProcessControl {
	readonly pid?: number | undefined;
	readonly kill: (signal: NodeJS.Signals) => boolean;
}

export interface BridgeViewerOwnedViteShutdownDependencies {
	readonly processIsAlive: (pid: number) => boolean;
	readonly waitForExitWithinDeadline: (
		exitPromise: Promise<BridgeViewerOwnedViteProcessExit>,
	) => Promise<BridgeViewerOwnedViteProcessExit | null>;
}

export async function createBridgeViewerViteProductFixture(): Promise<{
	readonly dispose: () => Promise<void>;
	readonly mutateLargeFile: () => Promise<BridgeViewerViteProductContentOracle>;
	readonly oracle: BridgeViewerViteProductFixtureOracle;
}> {
	const worktreeRoot = await mkdtemp(join(tmpdir(), 'bridge-viewer-vite-product-e2e-'));
	const largeFilePath = 'zz-large-complete-file.txt';
	const firstMarker = 'BRIDGE_VITE_PRODUCT_FIRST_BYTE_MARKER';
	const middleMarker = 'BRIDGE_VITE_PRODUCT_MIDDLE_BYTE_MARKER';
	const finalMarker = 'BRIDGE_VITE_PRODUCT_FINAL_BYTE_MARKER';
	const largeFileLines = Array.from({ length: 4_096 }, (_, lineIndex): string =>
		lineIndex === 0
			? firstMarker
			: lineIndex === 2_047
				? middleMarker
				: lineIndex === 4_095
					? finalMarker
					: `bridge-vite-product-line-${String(lineIndex + 1).padStart(4, '0')}`,
	);
	const largeFileContent = `${largeFileLines.join('\n')}\n`;
	const nestedPaths = Array.from(
		{ length: 18 },
		(_, fileIndex): string =>
			`nested/group-${String(Math.floor(fileIndex / 6) + 1).padStart(2, '0')}/file-${String(fileIndex + 1).padStart(2, '0')}.ts`,
	);
	const fileTreeOnlyPaths = Array.from(
		{ length: 180 },
		(_, fileIndex): string =>
			`tree-only/section-${String(Math.floor(fileIndex / 20) + 1).padStart(2, '0')}/entry-${String(fileIndex + 1).padStart(3, '0')}.txt`,
	);
	try {
		await writeFixtureFiles({
			fileTreeOnlyPaths,
			largeFileContent,
			largeFilePath,
			nestedPaths,
			phase: 'base',
			worktreeRoot,
		});
		await runFixtureGit(worktreeRoot, ['init', '--initial-branch=main']);
		await runFixtureGit(worktreeRoot, ['config', 'user.name', 'Bridge Vite Product E2E']);
		await runFixtureGit(worktreeRoot, ['config', 'user.email', 'bridge-vite-e2e@example.invalid']);
		await runFixtureGit(worktreeRoot, ['add', '--all']);
		await runFixtureGit(worktreeRoot, [
			'-c',
			'commit.gpgsign=false',
			'commit',
			'-m',
			'fixture base',
		]);
		await writeFixtureFiles({
			fileTreeOnlyPaths,
			largeFileContent,
			largeFilePath,
			nestedPaths,
			phase: 'head',
			worktreeRoot,
		});
		const baseRef = (await runFixtureGit(worktreeRoot, ['rev-parse', 'HEAD'])).trim();
		const changedPaths = (
			await runFixtureGit(worktreeRoot, ['diff', '--name-only', '--no-renames', baseRef, '--'])
		)
			.split('\n')
			.filter((path): boolean => path.length > 0)
			.toSorted((left, right): number => left.localeCompare(right));
		if (changedPaths.length !== nestedPaths.length) {
			throw new Error(`Disposable live-worktree oracle expected ${nestedPaths.length} changes.`);
		}
		const observedLargeFileContent = await readFile(join(worktreeRoot, largeFilePath), 'utf8');
		if (observedLargeFileContent !== largeFileContent) {
			throw new Error('Disposable live-worktree oracle did not preserve the complete large file.');
		}
		const reviewFiles = await Promise.all(
			changedPaths.map(async (path): Promise<BridgeViewerViteProductReviewFileOracle> => {
				const baseBody = await runFixtureGit(worktreeRoot, ['show', `${baseRef}:${path}`]);
				const headBody = await readFile(join(worktreeRoot, path), 'utf8');
				return {
					base: reviewRoleOracle('base', baseBody),
					head: reviewRoleOracle('head', headBody),
					itemId: `review-item-${sha256(path).slice(0, 32)}`,
					path,
				};
			}),
		);
		const fileContent = fileContentOracle({
			content: largeFileContent,
			firstMarker,
			finalMarker,
			middleMarker,
		});
		return {
			dispose: async (): Promise<void> => {
				await rm(worktreeRoot, { force: true, recursive: true });
			},
			mutateLargeFile: async (): Promise<BridgeViewerViteProductContentOracle> => {
				const mutatedFirstMarker = 'BRIDGE_VITE_PRODUCT_MUTATED_FIRST_BYTE_MARKER';
				const mutatedMiddleMarker = 'BRIDGE_VITE_PRODUCT_MUTATED_MIDDLE_BYTE_MARKER';
				const mutatedFinalMarker = 'BRIDGE_VITE_PRODUCT_MUTATED_FINAL_BYTE_MARKER';
				const mutatedLines = largeFileLines.map((line, lineIndex): string =>
					lineIndex === 0
						? mutatedFirstMarker
						: lineIndex === 2_047
							? mutatedMiddleMarker
							: lineIndex === 4_095
								? mutatedFinalMarker
								: line,
				);
				const content = `${mutatedLines.join('\n')}\n`;
				await writeFile(join(worktreeRoot, largeFilePath), content);
				return fileContentOracle({
					content,
					firstMarker: mutatedFirstMarker,
					finalMarker: mutatedFinalMarker,
					middleMarker: mutatedMiddleMarker,
				});
			},
			oracle: {
				baseRef,
				changedPaths,
				expectedReviewItemIds: reviewFiles.map(({ itemId }): string => itemId),
				fileContent,
				fileTreeDeepPath: fileTreeOnlyPaths.at(-1) ?? '',
				largeFileLineCount: largeFileLines.length,
				largeFilePath,
				largeFileSha256: sha256(largeFileContent),
				reviewFiles,
				worktreeRoot,
			},
		};
	} catch (error: unknown) {
		await rm(worktreeRoot, { force: true, recursive: true });
		throw error;
	}
}

export async function startBridgeViewerOwnedViteProductServer(
	oracle: BridgeViewerViteProductFixtureOracle,
): Promise<BridgeViewerOwnedViteProductServer> {
	const port = await reserveLoopbackPort();
	const telemetryReceiver = await startBridgeViewerOwnedTelemetryReceiver();
	const child = spawn(
		process.execPath,
		[viteCLIPath, '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
		{
			cwd: bridgeWebRootPath,
			env: {
				...process.env,
				BRIDGE_WEB_DEV_BASE: oracle.baseRef,
				BRIDGE_WEB_DEV_SCENARIO: 'current-worktree',
				BRIDGE_WEB_DEV_TELEMETRY_OTLP_LOGS_URL: `${telemetryReceiver.origin}/v1/logs`,
				BRIDGE_WEB_DEV_TELEMETRY_OTLP_METRICS_URL: `${telemetryReceiver.origin}/v1/metrics`,
				BRIDGE_WEB_DEV_WORKTREE: oracle.worktreeRoot,
			},
			stdio: ['pipe', 'pipe', 'pipe'],
		},
	);
	const exitPromise = new Promise<BridgeViewerOwnedViteProcessExit>((resolve): void => {
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
	let readinessOutput: string;
	try {
		readinessOutput = await withBoundedTimeout(
			new Promise<string>((resolve, reject): void => {
				const inspectOutput = (): void => {
					const output = stripANSI(`${stdoutTail}\n${stderrTail}`);
					if (output.includes(`http://127.0.0.1:${port}/`)) resolve(output);
				};
				child.stdout.on('data', inspectOutput);
				child.stderr.on('data', inspectOutput);
				void exitPromise.then((exit): void => {
					reject(
						new Error(
							`Owned Vite exited before readiness: ${JSON.stringify({ exit, stderrTail, stdoutTail })}`,
						),
					);
				});
			}),
			serverStartupTimeoutMilliseconds,
			'owned Vite readiness',
		);
	} catch (error: unknown) {
		try {
			return await rejectOwnedViteStartupAfterCleanup({
				child,
				exitPromise,
				startupError: error,
			});
		} finally {
			await telemetryReceiver.stop();
		}
	}
	const origin = `http://127.0.0.1:${port}`;
	return {
		origin,
		pid: child.pid ?? 0,
		stop: async (): Promise<BridgeViewerOwnedViteProductServerCleanup> => {
			try {
				return await stopOwnedViteServer({ child, exitPromise });
			} finally {
				await telemetryReceiver.stop();
			}
		},
		version: /VITE v(?<version>\d+\.\d+\.\d+)/u.exec(readinessOutput)?.groups?.['version'] ?? null,
	};
}

async function writeFixtureFiles(props: {
	readonly fileTreeOnlyPaths: readonly string[];
	readonly largeFileContent: string;
	readonly largeFilePath: string;
	readonly nestedPaths: readonly string[];
	readonly phase: 'base' | 'head';
	readonly worktreeRoot: string;
}): Promise<void> {
	await writeFile(join(props.worktreeRoot, props.largeFilePath), props.largeFileContent);
	for (const [fileIndex, relativePath] of props.nestedPaths.entries()) {
		const absolutePath = join(props.worktreeRoot, relativePath);
		// oxlint-disable-next-line no-await-in-loop -- Fixture paths must exist before their deterministic writes.
		await mkdir(join(absolutePath, '..'), { recursive: true });
		// oxlint-disable-next-line no-await-in-loop -- Stable fixture order makes source identity reproducible.
		await writeFile(
			absolutePath,
			[
				`export const fixtureValue${fileIndex + 1} = '${props.phase}-${fileIndex + 1}-bridge-vite-product-source-correlation';`,
				`export const fixtureDescription${fileIndex + 1} = 'deterministic-provider-worker-pierre-disposition-journey';`,
				'',
			].join('\n'),
		);
	}
	for (const [fileIndex, relativePath] of props.fileTreeOnlyPaths.entries()) {
		const absolutePath = join(props.worktreeRoot, relativePath);
		// oxlint-disable-next-line no-await-in-loop -- Fixture paths must exist before their deterministic writes.
		await mkdir(join(absolutePath, '..'), { recursive: true });
		// oxlint-disable-next-line no-await-in-loop -- Stable fixture order makes the deep tree reproducible.
		await writeFile(absolutePath, `unchanged-tree-entry-${fileIndex + 1}\n`);
	}
}

function fileContentOracle(props: {
	readonly content: string;
	readonly firstMarker: string;
	readonly finalMarker: string;
	readonly middleMarker: string;
}): BridgeViewerViteProductContentOracle {
	return {
		byteLength: Buffer.byteLength(props.content),
		firstMarker: props.firstMarker,
		finalMarker: props.finalMarker,
		lineCount: props.content.split('\n').length - 1,
		middleMarker: props.middleMarker,
		sha256: sha256(props.content),
	};
}

function reviewRoleOracle(
	role: 'base' | 'head',
	body: string,
): BridgeViewerViteProductReviewRoleOracle {
	return { body, byteLength: Buffer.byteLength(body), role, sha256: sha256(body) };
}

async function runFixtureGit(cwd: string, arguments_: readonly string[]): Promise<string> {
	const { stdout } = await execFileAsync('git', [...arguments_], {
		cwd,
		encoding: 'utf8',
		maxBuffer: 16 * 1024 * 1024,
	});
	return stdout;
}

async function stopOwnedViteServer(props: {
	readonly child: BridgeViewerOwnedViteProcessControl;
	readonly exitPromise: Promise<BridgeViewerOwnedViteProcessExit>;
	readonly shutdownDependencies?: BridgeViewerOwnedViteShutdownDependencies;
}): Promise<BridgeViewerOwnedViteProductServerCleanup> {
	const shutdownDependencies = props.shutdownDependencies ?? defaultOwnedViteShutdownDependencies();
	const pid = props.child.pid ?? null;
	props.child.kill('SIGTERM');
	let forcedTerminationRequired = false;
	let exit = await shutdownDependencies.waitForExitWithinDeadline(props.exitPromise);
	if (exit === null) {
		forcedTerminationRequired = true;
		props.child.kill('SIGKILL');
		exit = await shutdownDependencies.waitForExitWithinDeadline(props.exitPromise);
	}
	return {
		exitCode: exit?.code ?? null,
		exitObserved: exit !== null,
		exitSignal: exit?.signal ?? null,
		forcedTerminationRequired,
		ownedProcessAliveAfterStop: pid === null ? false : shutdownDependencies.processIsAlive(pid),
	};
}

export async function rejectOwnedViteStartupAfterCleanup(props: {
	readonly child: BridgeViewerOwnedViteProcessControl;
	readonly exitPromise: Promise<BridgeViewerOwnedViteProcessExit>;
	readonly shutdownDependencies?: BridgeViewerOwnedViteShutdownDependencies;
	readonly startupError: unknown;
}): Promise<never> {
	const cleanup = await stopOwnedViteServer(props);
	if (!cleanup.exitObserved || cleanup.ownedProcessAliveAfterStop) {
		throw new AggregateError(
			[props.startupError],
			`OWNED_VITE_STARTUP_CLEANUP_FAILED:${JSON.stringify(cleanup)}`,
		);
	}
	throw props.startupError;
}

function defaultOwnedViteShutdownDependencies(): BridgeViewerOwnedViteShutdownDependencies {
	return {
		processIsAlive,
		waitForExitWithinDeadline: async (
			exitPromise,
		): Promise<BridgeViewerOwnedViteProcessExit | null> =>
			await withBoundedTimeoutOrNull(exitPromise, serverShutdownTimeoutMilliseconds),
	};
}

async function reserveLoopbackPort(): Promise<number> {
	const server = createTCPServer();
	await new Promise<void>((resolve, reject): void => {
		server.once('error', reject);
		server.listen(0, '127.0.0.1', (): void => resolve());
	});
	const address = server.address();
	if (address === null || typeof address === 'string') {
		server.close();
		throw new Error('Failed to reserve a loopback Vite port.');
	}
	await new Promise<void>((resolve, reject): void => {
		server.close((error): void => (error === undefined ? resolve() : reject(error)));
	});
	return address.port;
}

async function startBridgeViewerOwnedTelemetryReceiver(): Promise<{
	readonly origin: string;
	readonly stop: () => Promise<void>;
}> {
	const server = createHTTPServer((request, response): void => {
		request.resume();
		if (
			request.method === 'POST' &&
			(request.url === '/v1/logs' || request.url === '/v1/metrics')
		) {
			response.statusCode = 200;
			response.end();
			return;
		}
		response.statusCode = 404;
		response.end();
	});
	await new Promise<void>((resolve, reject): void => {
		server.once('error', reject);
		server.listen(0, '127.0.0.1', (): void => resolve());
	});
	const address = server.address();
	if (address === null || typeof address === 'string') {
		server.close();
		throw new Error('Failed to start the owned Bridge telemetry receiver.');
	}
	return {
		origin: `http://127.0.0.1:${address.port}`,
		stop: async (): Promise<void> => {
			await new Promise<void>((resolve, reject): void => {
				server.close((error): void => (error === undefined ? resolve() : reject(error)));
			});
		},
	};
}

function sha256(value: string | Uint8Array): string {
	return createHash('sha256').update(value).digest('hex');
}

function appendBoundedTail(current: string, next: string): string {
	return `${current}${next}`.slice(-maximumServerLogTailCharacters);
}

function stripANSI(value: string): string {
	return value.replace(new RegExp(`${String.fromCharCode(27)}\\[[0-?]*[ -/]*[@-~]`, 'gu'), '');
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

async function withBoundedTimeout<TValue>(
	promise: Promise<TValue>,
	timeoutMilliseconds: number,
	label: string,
): Promise<TValue> {
	const result = await withBoundedTimeoutOrNull(promise, timeoutMilliseconds);
	if (result === null) throw new Error(`Timed out waiting for ${label}.`);
	return result;
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
