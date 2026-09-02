import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';

import {
	runAllOwnedCleanupOperations,
	startOwnedBridgeDevelopmentServer,
	type OwnedBridgeDevelopmentServer,
} from './dev-server/bridge-development-server-process.js';
import { reserveLoopbackPort } from './dev-server/reserve-loopback-port.ts';
import {
	bridgeCompleteJourneyMinimumAttemptsPerLaunch,
	reduceBridgeCompleteJourneyCohort,
	type BridgeCompleteJourney,
} from './verify-bridge-viewer-worktree-dev-server/complete-journey-cohort.ts';
import {
	bridgeCompleteJourneyLaunchForJourney,
	type BridgeDevelopmentCompleteJourneyLaunch,
} from './verify-bridge-viewer-worktree-dev-server/complete-journey-collector.ts';
import {
	completeJourneyAttemptCount,
	completeJourneyMode,
	execFileAsync,
	performanceOnlyMode,
	proofRunDirectoryPath,
	startupOnlyMode,
} from './verify-bridge-viewer-worktree-dev-server/config.ts';

const bridgeProductBackendStartupTimeoutMilliseconds = 120_000;
const bridgeProductBackendHealthRetryMilliseconds = 50;
const bridgePerformanceVerifierPaneId = '00000000-0000-7000-8000-000000000002';
const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const bridgeCompleteJourneys = [
	'firstFile',
	'firstReview',
	'fileToReview',
	'reviewToFile',
] as const satisfies readonly BridgeCompleteJourney[];

type StartupSurface = 'file' | 'review';

interface ColdStartupSurfaceResult {
	readonly browserProof: unknown;
	readonly observedPageUrl: string;
	readonly proof: unknown;
	readonly satisfied: boolean;
	readonly scenarioName: string;
	readonly surface: StartupSurface;
}

if (completeJourneyMode || performanceOnlyMode || startupOnlyMode) {
	await runSelfHostedBridgeViewerPerformanceVerifier();
} else {
	await runSelfHostedBridgeViewerProductOnlyRegression();
}

async function runSelfHostedBridgeViewerProductOnlyRegression(): Promise<void> {
	const regression =
		await import('./verify-bridge-viewer-worktree-dev-server/product-only-real-router-regression.ts');
	await regression.runSelfHostedBridgeViewerProductOnlyRegression();
}

async function runSelfHostedBridgeViewerPerformanceVerifier(): Promise<void> {
	const previousBackendOrigin = process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];
	const previousWorktreeDevServerUrl = process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
	let backendDataRootPath: string | null = null;
	let bridgeDevelopmentServer: OwnedBridgeDevelopmentServer | null = null;
	let viteServer: ViteDevServer | null = null;
	try {
		backendDataRootPath = await mkdtemp(join(tmpdir(), 'agentstudio-bridge-performance-'));
		const backendPort = await reserveLoopbackPort();
		bridgeDevelopmentServer = await startOwnedBridgeDevelopmentServer({
			dataRootPath: backendDataRootPath,
			initialTarget: 'HEAD',
			paneId: bridgePerformanceVerifierPaneId,
			port: backendPort,
			repoRootPath,
			worktreeRoot: repoRootPath,
		});
		process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = bridgeDevelopmentServer.origin;
		if (completeJourneyMode) {
			await runCompleteJourneyDevelopmentCohort();
			return;
		}
		if (startupOnlyMode) {
			const file = await runColdStartupSurfaceLifecycle({ surface: 'file' });
			const review = await runColdStartupSurfaceLifecycle({ surface: 'review' });
			console.log(
				JSON.stringify(
					{
						browserProof: { file: file.browserProof, review: review.browserProof },
						file: file.proof,
						observedPageUrls: { file: file.observedPageUrl, review: review.observedPageUrl },
						review: review.proof,
						scenarioName: file.scenarioName,
					},
					null,
					2,
				),
			);
			if (!file.satisfied || !review.satisfied) process.exitCode = 1;
			return;
		}
		const vitePort = await reserveLoopbackPort();
		viteServer = await createViteServer({
			configFile: fileURLToPath(new URL('../vite.config.ts', import.meta.url)),
			server: {
				host: '127.0.0.1',
				port: vitePort,
				strictPort: true,
			},
		});
		await viteServer.listen();
		const serverAddress = viteServer.httpServer?.address();
		if (
			serverAddress === null ||
			serverAddress === undefined ||
			typeof serverAddress === 'string'
		) {
			throw new Error('Expected the owned performance Vite server to expose a loopback port.');
		}
		process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] =
			`http://127.0.0.1:${serverAddress.port}/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`;
		await waitForBridgeProductBackendReady(`http://127.0.0.1:${serverAddress.port}`);

		const loadedRunner: unknown = await viteServer.ssrLoadModule(
			'/scripts/verify-bridge-viewer-worktree-dev-server/runner.ts',
		);
		if (typeof loadedRunner !== 'object' || loadedRunner === null) {
			throw new Error('Expected the owned performance verifier runner module.');
		}
		const runVerifier = (loadedRunner as Readonly<Record<string, unknown>>)[
			'runBridgeViewerWorktreeDevServerVerifier'
		];
		if (typeof runVerifier !== 'function') {
			throw new Error('Expected the owned performance verifier runner entrypoint.');
		}
		await runVerifier();
	} finally {
		try {
			const cleanupOperations = [
				{
					name: 'performance Vite server',
					run: async (): Promise<void> => await viteServer?.close(),
				},
				{
					name: 'performance Swift development backend',
					run: async (): Promise<void> => {
						await bridgeDevelopmentServer?.stop();
					},
				},
				{
					name: 'performance backend data root',
					run: async (): Promise<void> => {
						if (backendDataRootPath !== null) {
							await rm(backendDataRootPath, { force: true, recursive: true });
						}
					},
				},
			];
			await runAllOwnedCleanupOperations({ operations: cleanupOperations });
		} finally {
			if (previousBackendOrigin === undefined) {
				delete process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];
			} else {
				process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = previousBackendOrigin;
			}
			if (previousWorktreeDevServerUrl === undefined) {
				delete process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
			} else {
				process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] = previousWorktreeDevServerUrl;
			}
		}
	}
}

async function runCompleteJourneyDevelopmentCohort(): Promise<void> {
	const sourceHeadResult = await execFileAsync('/usr/bin/git', ['rev-parse', 'HEAD'], {
		cwd: repoRootPath,
		encoding: 'utf8',
	});
	const sourceHead = sourceHeadResult.stdout.trim();
	const launches: BridgeDevelopmentCompleteJourneyLaunch[] = [];
	for (let launchIndex = 0; launchIndex < 3; launchIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Acceptance requires three independent Vite/browser launches.
		launches.push(
			await runCompleteJourneyLaunchLifecycle({
				attemptCount: completeJourneyAttemptCount,
				launchIndex,
				sourceHead,
			}),
		);
	}
	const diagnosticOnly =
		completeJourneyAttemptCount < bridgeCompleteJourneyMinimumAttemptsPerLaunch;
	const reductions = diagnosticOnly
		? null
		: bridgeCompleteJourneys.map((journey) =>
				reduceBridgeCompleteJourneyCohort({
					carrier: 'development',
					journey,
					launches: launches.map((launch) =>
						bridgeCompleteJourneyLaunchForJourney(launch, journey),
					),
				}),
			);
	const failureCount = launches.reduce(
		(count, launch) =>
			count +
			bridgeCompleteJourneys.reduce(
				(journeyCount, journey) =>
					journeyCount +
					launch.attemptsByJourney[journey].filter((attempt) => attempt.outcome === 'failed')
						.length,
				0,
			),
		0,
	);
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const artifactPath = join(proofRunDirectoryPath, 'bridge-complete-journey-development.json');
	await writeFile(
		artifactPath,
		`${JSON.stringify({ diagnosticOnly, failureCount, launches, reductions }, null, 2)}\n`,
		'utf8',
	);
	console.log(
		JSON.stringify(
			{
				artifactPath,
				attemptCountPerJourneyPerLaunch: completeJourneyAttemptCount,
				diagnosticOnly,
				failureCount,
				reductions,
			},
			null,
			2,
		),
	);
	if (failureCount > 0 || reductions?.some((reduction) => !reduction.satisfied) === true) {
		process.exitCode = 1;
	}
}

async function runCompleteJourneyLaunchLifecycle(props: {
	readonly attemptCount: number;
	readonly launchIndex: number;
	readonly sourceHead: string;
}): Promise<BridgeDevelopmentCompleteJourneyLaunch> {
	const previousViteCacheDirectory = process.env['BRIDGE_WEB_VITE_CACHE_DIR'];
	const previousWorktreeDevServerUrl = process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
	const viteCacheDirectoryPath = await mkdtemp(
		join(tmpdir(), `agentstudio-bridge-complete-journey-${props.launchIndex}-`),
	);
	let viteServer: ViteDevServer | null = null;
	try {
		process.env['BRIDGE_WEB_VITE_CACHE_DIR'] = viteCacheDirectoryPath;
		const vitePort = await reserveLoopbackPort();
		viteServer = await createViteServer({
			configFile: fileURLToPath(new URL('../vite.config.ts', import.meta.url)),
			server: { host: '127.0.0.1', port: vitePort, strictPort: true },
		});
		await viteServer.listen();
		const serverAddress = viteServer.httpServer?.address();
		if (
			serverAddress === null ||
			serverAddress === undefined ||
			typeof serverAddress === 'string'
		) {
			throw new Error('Expected complete-journey Vite to expose a loopback port.');
		}
		const viteOrigin = `http://127.0.0.1:${serverAddress.port}`;
		process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] =
			`${viteOrigin}/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`;
		await waitForBridgeProductBackendReady(viteOrigin);
		const loadedRunner: unknown = await viteServer.ssrLoadModule(
			'/scripts/verify-bridge-viewer-worktree-dev-server/runner.ts',
		);
		if (typeof loadedRunner !== 'object' || loadedRunner === null) {
			throw new Error('Expected the complete-journey verifier runner module.');
		}
		const runLaunch = (loadedRunner as Readonly<Record<string, unknown>>)[
			'runBridgeViewerWorktreeDevServerCompleteJourneyLaunch'
		];
		if (typeof runLaunch !== 'function') {
			throw new Error('Expected the complete-journey launch entrypoint.');
		}
		return completeJourneyLaunchFromUnknown(
			await runLaunch({
				attemptCount: props.attemptCount,
				launchId: `development-launch-${props.launchIndex}`,
				sourceHead: props.sourceHead,
			}),
		);
	} finally {
		try {
			await viteServer?.close();
		} finally {
			await rm(viteCacheDirectoryPath, { force: true, recursive: true });
			restoreEnvironmentValue('BRIDGE_WEB_VITE_CACHE_DIR', previousViteCacheDirectory);
			restoreEnvironmentValue(
				'BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL',
				previousWorktreeDevServerUrl,
			);
		}
	}
}

function completeJourneyLaunchFromUnknown(value: unknown): BridgeDevelopmentCompleteJourneyLaunch {
	if (
		typeof value !== 'object' ||
		value === null ||
		!('launchId' in value) ||
		typeof value.launchId !== 'string' ||
		!('evidence' in value) ||
		typeof value.evidence !== 'object' ||
		value.evidence === null ||
		!('attemptsByJourney' in value) ||
		typeof value.attemptsByJourney !== 'object' ||
		value.attemptsByJourney === null
	) {
		throw new Error('Expected a complete-journey development launch result.');
	}
	return value as BridgeDevelopmentCompleteJourneyLaunch;
}

function restoreEnvironmentValue(name: string, previousValue: string | undefined): void {
	if (previousValue === undefined) {
		delete process.env[name];
	} else {
		process.env[name] = previousValue;
	}
}

async function runColdStartupSurfaceLifecycle(props: {
	readonly surface: StartupSurface;
}): Promise<ColdStartupSurfaceResult> {
	const previousViteCacheDirectory = process.env['BRIDGE_WEB_VITE_CACHE_DIR'];
	const previousWorktreeDevServerUrl = process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
	const viteCacheDirectoryPath = await mkdtemp(
		join(tmpdir(), `agentstudio-bridge-vite-${props.surface}-`),
	);
	let viteServer: ViteDevServer | null = null;
	try {
		process.env['BRIDGE_WEB_VITE_CACHE_DIR'] = viteCacheDirectoryPath;
		const vitePort = await reserveLoopbackPort();
		viteServer = await createViteServer({
			configFile: fileURLToPath(new URL('../vite.config.ts', import.meta.url)),
			server: {
				host: '127.0.0.1',
				port: vitePort,
				strictPort: true,
			},
		});
		await viteServer.listen();
		const serverAddress = viteServer.httpServer?.address();
		if (
			serverAddress === null ||
			serverAddress === undefined ||
			typeof serverAddress === 'string'
		) {
			throw new Error('Expected the cold-start Vite server to expose a loopback port.');
		}
		const viteOrigin = `http://127.0.0.1:${serverAddress.port}`;
		process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] =
			`${viteOrigin}/?fixture=worktree&viewer=${props.surface}&workers=on&scenario=current-worktree`;
		await waitForBridgeProductBackendReady(viteOrigin);
		const loadedRunner: unknown = await viteServer.ssrLoadModule(
			'/scripts/verify-bridge-viewer-worktree-dev-server/runner.ts',
		);
		if (typeof loadedRunner !== 'object' || loadedRunner === null) {
			throw new Error('Expected the cold-start verifier runner module.');
		}
		const runSurfaceVerifier = (loadedRunner as Readonly<Record<string, unknown>>)[
			'runBridgeViewerWorktreeDevServerStartupSurfaceVerifier'
		];
		if (typeof runSurfaceVerifier !== 'function') {
			throw new Error('Expected the cold-start surface verifier entrypoint.');
		}
		return coldStartupSurfaceResultFromUnknown(
			await runSurfaceVerifier(props.surface),
			props.surface,
		);
	} finally {
		try {
			if (viteServer !== null) await viteServer.close();
		} finally {
			try {
				await rm(viteCacheDirectoryPath, { force: true, recursive: true });
			} finally {
				if (previousViteCacheDirectory === undefined) {
					delete process.env['BRIDGE_WEB_VITE_CACHE_DIR'];
				} else {
					process.env['BRIDGE_WEB_VITE_CACHE_DIR'] = previousViteCacheDirectory;
				}
				if (previousWorktreeDevServerUrl === undefined) {
					delete process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
				} else {
					process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] = previousWorktreeDevServerUrl;
				}
			}
		}
	}
}

function coldStartupSurfaceResultFromUnknown(
	value: unknown,
	expectedSurface: StartupSurface,
): ColdStartupSurfaceResult {
	if (
		typeof value !== 'object' ||
		value === null ||
		!('surface' in value) ||
		value.surface !== expectedSurface ||
		!('satisfied' in value) ||
		typeof value.satisfied !== 'boolean' ||
		!('proof' in value) ||
		typeof value.proof !== 'object' ||
		value.proof === null ||
		!('observedPageUrl' in value) ||
		typeof value.observedPageUrl !== 'string' ||
		!('scenarioName' in value) ||
		typeof value.scenarioName !== 'string' ||
		!('browserProof' in value)
	) {
		throw new Error(`Expected the ${expectedSurface} cold-start result.`);
	}
	return value as ColdStartupSurfaceResult;
}

async function waitForBridgeProductBackendReady(viteOrigin: string): Promise<void> {
	const deadline = Date.now() + bridgeProductBackendStartupTimeoutMilliseconds;
	const healthUrl = new URL('/__bridge-product/health', viteOrigin);
	while (Date.now() < deadline) {
		try {
			const response = await fetch(healthUrl);
			if (response.status === 204) return;
		} catch {
			// The owned backend may refuse proxied connections until it is ready.
		}
		await new Promise<void>((resolve): void => {
			setTimeout(resolve, bridgeProductBackendHealthRetryMilliseconds);
		});
	}
	throw new Error('Timed out waiting for the owned Bridge development backend.');
}
