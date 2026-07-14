import { execFile, spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createHash } from 'node:crypto';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { resolveBridgeWorktreeDevProviderConfig } from '../dev-server/bridge-worktree-dev-provider/config.ts';
import { loadBridgeWorktreeDevMetadataSnapshot } from '../dev-server/bridge-worktree-dev-provider/metadata.ts';
import {
	bridgeProductStartupFixtureIdentities,
	collectBridgeViewerProductOnlyContractViolations,
	type BridgeViewerProductOnlyContractViolation,
	type BridgeViewerProductOnlyJourneyProof,
} from './product-only-real-router-contract.ts';
import { runBridgeViewerProductOnlyJourney } from './product-only-real-router-page.ts';

const execFileAsync = promisify(execFile);
const bridgeWebRootPath = fileURLToPath(new URL('../../', import.meta.url));
const repoRootPath = fileURLToPath(new URL('../../../', import.meta.url));
const viteCLIPath = join(bridgeWebRootPath, 'node_modules/vite/bin/vite.js');
const serverStartupTimeoutMilliseconds = 30_000;
const serverShutdownTimeoutMilliseconds = 10_000;
const maximumGitDiffBytes = 256 * 1024 * 1024;
const maximumServerLogTailCharacters = 8_192;

interface BridgeViewerSourceFreshnessProof {
	readonly branch: string;
	readonly commitSha: string;
	readonly fixtureSha256: typeof bridgeProductStartupFixtureIdentities;
	readonly statusEntryCount: number;
	readonly trackedDiffSha256: string;
	readonly untrackedContentSha256: string;
	readonly untrackedFileCount: number;
	readonly worktreeStatusSha256: string;
}

interface BridgeViewerViteServerStartProof {
	readonly origin: string;
	readonly pid: number;
	readonly version: string | null;
}

interface BridgeViewerViteServerCleanupProof {
	readonly exitCode: number | null;
	readonly exitSignal: NodeJS.Signals | null;
	readonly exitedWithinTimeout: boolean;
	readonly forcedTerminationRequired: boolean;
	readonly ownedProcessAliveAfterStop: boolean;
	readonly pid: number | null;
}

interface BridgeViewerProductOnlyRegressionArtifact {
	readonly cleanup: BridgeViewerViteServerCleanupProof;
	readonly createdAtUnixMilliseconds: number;
	readonly harnessFailure: string | null;
	readonly journey: BridgeViewerProductOnlyJourneyProof | null;
	readonly phase:
		| 'a0-product-only-green'
		| 'initial-product-transport-red'
		| 'n2a-transport-green-composition-red'
		| 'not-reached';
	readonly schemaVersion: 1;
	readonly server: BridgeViewerViteServerStartProof | null;
	readonly source: BridgeViewerSourceFreshnessProof;
	readonly taskId: 'F1b0-R1b0-red-01';
	readonly violations: readonly BridgeViewerProductOnlyContractViolation[];
}

interface ChildProcessExit {
	readonly code: number | null;
	readonly signal: NodeJS.Signals | null;
}

export async function runSelfHostedBridgeViewerProductOnlyRegression(): Promise<void> {
	const createdAtUnixMilliseconds = Date.now();
	const source = await readSourceFreshnessProof();
	let cleanup: BridgeViewerViteServerCleanupProof = {
		exitCode: null,
		exitSignal: null,
		exitedWithinTimeout: true,
		forcedTerminationRequired: false,
		ownedProcessAliveAfterStop: false,
		pid: null,
	};
	let harnessFailure: string | null = null;
	let journey: BridgeViewerProductOnlyJourneyProof | null = null;
	let serverProof: BridgeViewerViteServerStartProof | null = null;
	let server: BridgeViewerOwnedViteServer | null = null;
	try {
		const expectedReviewItemIds = await readExpectedReviewItemIds();
		server = await BridgeViewerOwnedViteServer.start();
		serverProof = server.startProof;
		journey = await runBridgeViewerProductOnlyJourney({
			baseUrl: server.startProof.origin,
			expectedReviewItemIds,
		});
	} catch (error: unknown) {
		harnessFailure = boundedErrorMessage(error);
	} finally {
		if (server !== null) cleanup = await server.stop();
	}

	const violations =
		journey === null ? [] : collectBridgeViewerProductOnlyContractViolations(journey);
	const artifact: BridgeViewerProductOnlyRegressionArtifact = {
		cleanup,
		createdAtUnixMilliseconds,
		harnessFailure,
		journey,
		phase:
			harnessFailure === null && journey !== null
				? bridgeViewerProductOnlyRegressionPhase(violations)
				: 'not-reached',
		schemaVersion: 1,
		server: serverProof,
		source,
		taskId: 'F1b0-R1b0-red-01',
		violations,
	};
	const artifactPath = await writeRegressionArtifact(artifact);
	console.log(
		JSON.stringify(
			{
				browser: journey?.browser ?? null,
				browserCleanup: journey?.browserCleanup ?? null,
				cleanup,
				commitSha: source.commitSha,
				documentGeneration: journey?.documentGeneration ?? null,
				fixtureSha256: source.fixtureSha256,
				harnessFailure,
				legacyIntakeEventCount: journey?.legacyIntakeTranscript.length ?? null,
				legacyRouteCount: journey?.legacyRouteTranscript.length ?? null,
				mainWindowProductRouteTranscript: journey?.mainWindowProductRouteTranscript ?? null,
				ok: harnessFailure === null && violations.length === 0,
				phase: artifact.phase,
				productRouteCount: journey?.productRouteTranscript.length ?? null,
				proofArtifactPath: relative(repoRootPath, artifactPath),
				server: serverProof,
				taskId: artifact.taskId,
				violationCodes: violations.map((violation) => violation.code),
				violationCount: violations.length,
				workers: journey?.workers ?? null,
			},
			null,
			2,
		),
	);
	if (harnessFailure !== null) {
		process.exitCode = 2;
		return;
	}
	if (violations.length > 0) process.exitCode = 1;
}

async function readExpectedReviewItemIds(): Promise<readonly string[]> {
	const config = await resolveBridgeWorktreeDevProviderConfig({
		env: process.env,
		packageRoot: bridgeWebRootPath,
		requestUrl: '/?fixture=worktree&scenario=current-worktree&viewer=review&workers=on',
	});
	const snapshot = await loadBridgeWorktreeDevMetadataSnapshot(config);
	const orderedItemIds = snapshot.changedFiles.map(
		(changedFile): string =>
			`review-item-${createHash('sha256').update(changedFile.path).digest('hex').slice(0, 32)}`,
	);
	if (orderedItemIds.length === 0) {
		throw new Error('Review metadata oracle returned no changed-file item ids.');
	}
	return orderedItemIds;
}

export function bridgeViewerProductOnlyRegressionPhase(
	violations: readonly BridgeViewerProductOnlyContractViolation[],
): BridgeViewerProductOnlyRegressionArtifact['phase'] {
	if (violations.length === 0) return 'a0-product-only-green';
	const transportRedCodes = new Set([
		'transport.file.metadata-accepted',
		'transport.frame-observation-bodyless-204',
		'transport.review.metadata-accepted',
	]);
	return violations.some((violation): boolean => transportRedCodes.has(violation.code))
		? 'initial-product-transport-red'
		: 'n2a-transport-green-composition-red';
}

class BridgeViewerOwnedViteServer {
	readonly #child: ChildProcessWithoutNullStreams;
	readonly #exitPromise: Promise<ChildProcessExit>;
	#exit: ChildProcessExit | null = null;
	readonly startProof: BridgeViewerViteServerStartProof;

	private constructor(props: {
		readonly child: ChildProcessWithoutNullStreams;
		readonly exitPromise: Promise<ChildProcessExit>;
		readonly startProof: BridgeViewerViteServerStartProof;
	}) {
		this.#child = props.child;
		this.#exitPromise = props.exitPromise.then((exit): ChildProcessExit => {
			this.#exit = exit;
			return exit;
		});
		this.startProof = props.startProof;
	}

	static async start(): Promise<BridgeViewerOwnedViteServer> {
		await access(viteCLIPath);
		const port = await reserveLoopbackPort();
		const child = spawn(
			process.execPath,
			[viteCLIPath, '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
			{
				cwd: bridgeWebRootPath,
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
		let readyOutput: string;
		try {
			readyOutput = await withBoundedTimeout(
				new Promise<string>((resolve, reject): void => {
					const inspectOutput = (): void => {
						const normalizedOutput = stripANSI(`${stdoutTail}\n${stderrTail}`);
						if (normalizedOutput.includes(`http://127.0.0.1:${port}/`)) {
							resolve(normalizedOutput);
						}
					};
					child.stdout.on('data', inspectOutput);
					child.stderr.on('data', inspectOutput);
					void exitPromise.then((exit): void => {
						reject(
							new Error(
								`Owned Vite exited before readiness: ${JSON.stringify({
									exit,
									stderrTail,
									stdoutTail,
								})}`,
							),
						);
					});
				}),
				serverStartupTimeoutMilliseconds,
				'owned loopback Vite readiness',
			);
		} catch (error: unknown) {
			child.kill('SIGTERM');
			const stoppedExit = await withBoundedTimeoutOrNull(
				exitPromise,
				serverShutdownTimeoutMilliseconds,
			);
			if (stoppedExit === null) child.kill('SIGKILL');
			throw error;
		}
		const origin = `http://127.0.0.1:${port}`;
		if (new URL(origin).hostname !== '127.0.0.1') {
			throw new Error(`Refusing non-loopback verifier Vite origin: ${origin}`);
		}
		return new BridgeViewerOwnedViteServer({
			child,
			exitPromise,
			startProof: {
				origin,
				pid: child.pid ?? 0,
				version: /VITE v(?<version>\d+\.\d+\.\d+)/u.exec(readyOutput)?.groups?.['version'] ?? null,
			},
		});
	}

	async stop(): Promise<BridgeViewerViteServerCleanupProof> {
		const pid = this.#child.pid ?? null;
		let forcedTerminationRequired = false;
		let exitedWithinTimeout = true;
		if (this.#exit === null) this.#child.kill('SIGTERM');
		let exit = await withBoundedTimeoutOrNull(this.#exitPromise, serverShutdownTimeoutMilliseconds);
		if (exit === null) {
			exitedWithinTimeout = false;
			forcedTerminationRequired = true;
			this.#child.kill('SIGKILL');
			exit = await withBoundedTimeoutOrNull(this.#exitPromise, serverShutdownTimeoutMilliseconds);
		}
		return {
			exitCode: exit?.code ?? null,
			exitSignal: exit?.signal ?? null,
			exitedWithinTimeout,
			forcedTerminationRequired,
			ownedProcessAliveAfterStop: pid === null ? false : processIsAlive(pid),
			pid,
		};
	}
}

async function readSourceFreshnessProof(): Promise<BridgeViewerSourceFreshnessProof> {
	const [branch, commitSha, status, trackedDiff, untrackedNames, validFixture, invalidFixture] =
		await Promise.all([
			gitStdout(['branch', '--show-current']),
			gitStdout(['rev-parse', 'HEAD']),
			gitStdout(['status', '--porcelain=v1', '-z']),
			gitStdout(['diff', '--binary', '--no-ext-diff', 'HEAD', '--']),
			gitStdout(['ls-files', '--others', '--exclude-standard', '-z']),
			readFile(
				join(
					repoRootPath,
					'Tests/BridgeContractFixtures/valid/bridge-product-startup-transcript.json',
				),
			),
			readFile(
				join(
					repoRootPath,
					'Tests/BridgeContractFixtures/invalid/bridge-product-startup-transcript.json',
				),
			),
		]);
	const untrackedFileNames = untrackedNames
		.split('\0')
		.filter((name) => name.length > 0)
		.toSorted();
	const observedFixtureSha256 = {
		invalid: sha256(invalidFixture),
		valid: sha256(validFixture),
	};
	if (
		observedFixtureSha256.valid !== bridgeProductStartupFixtureIdentities.valid ||
		observedFixtureSha256.invalid !== bridgeProductStartupFixtureIdentities.invalid
	) {
		throw new Error(
			`Bridge product startup transcript fixture identity mismatch: ${JSON.stringify(observedFixtureSha256)}`,
		);
	}
	return {
		branch: branch.trim(),
		commitSha: commitSha.trim(),
		fixtureSha256: bridgeProductStartupFixtureIdentities,
		statusEntryCount: status.split('\0').filter((entry) => entry.length > 0).length,
		trackedDiffSha256: sha256(trackedDiff),
		untrackedContentSha256: await hashUntrackedFiles(untrackedFileNames),
		untrackedFileCount: untrackedFileNames.length,
		worktreeStatusSha256: sha256(status),
	};
}

async function hashUntrackedFiles(relativePaths: readonly string[]): Promise<string> {
	const hash = createHash('sha256');
	for (const relativePath of relativePaths) {
		hash.update(relativePath);
		hash.update('\0');
		// oxlint-disable-next-line no-await-in-loop -- Stable content identity preserves sorted path order.
		hash.update(await readFile(join(repoRootPath, relativePath)));
		hash.update('\0');
	}
	return hash.digest('hex');
}

async function gitStdout(arguments_: readonly string[]): Promise<string> {
	const { stdout } = await execFileAsync('git', arguments_, {
		cwd: repoRootPath,
		encoding: 'utf8',
		maxBuffer: maximumGitDiffBytes,
	});
	return stdout;
}

async function writeRegressionArtifact(
	artifact: BridgeViewerProductOnlyRegressionArtifact,
): Promise<string> {
	const proofRootPath =
		process.env['AGENTSTUDIO_BRIDGE_WORKTREE_DEV_SERVER_PROOF_ROOT'] ??
		join(repoRootPath, 'tmp/bridge-viewer-worktree-dev-server');
	const runDirectoryPath = join(
		proofRootPath,
		new Date(artifact.createdAtUnixMilliseconds).toISOString().replace(/[:.]/gu, '-'),
	);
	await mkdir(runDirectoryPath, { recursive: true });
	const artifactPath = join(runDirectoryPath, 'product-only-real-router-proof.json');
	await writeFile(artifactPath, `${JSON.stringify(artifact, null, 2)}\n`);
	return artifactPath;
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
		throw new Error('Failed to reserve a loopback verifier port.');
	}
	await new Promise<void>((resolve, reject): void => {
		server.close((error): void => (error === undefined ? resolve() : reject(error)));
	});
	return address.port;
}

function appendBoundedTail(current: string, next: string): string {
	return `${current}${next}`.slice(-maximumServerLogTailCharacters);
}

function stripANSI(value: string): string {
	return value.replace(new RegExp(`${String.fromCharCode(27)}\\[[0-?]*[ -/]*[@-~]`, 'gu'), '');
}

function sha256(value: string | Uint8Array): string {
	return createHash('sha256').update(value).digest('hex');
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

function boundedErrorMessage(error: unknown): string {
	const message = error instanceof Error ? (error.stack ?? error.message) : String(error);
	return message.slice(0, maximumServerLogTailCharacters);
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
