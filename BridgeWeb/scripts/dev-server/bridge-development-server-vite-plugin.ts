import { spawn } from 'node:child_process';
import { rmSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';

import type { Plugin, ViteDevServer } from 'vite';

import {
	runAllOwnedCleanupOperations,
	startOwnedBridgeDevelopmentServer,
	type OwnedBridgeDevelopmentServerCleanup,
} from './bridge-development-server-process.js';
import {
	createBridgeDevelopmentServerSupervisor,
	type BridgeDevelopmentServerSupervisor,
} from './bridge-development-server-supervisor.js';

const bridgeDevelopmentPaneId = '00000000-0000-7000-8000-000000000001';
const buildShutdownTimeoutMilliseconds = 10_000;

const watchedSourceDirectories = [
	'Sources/AgentStudioBridgeDevelopmentServer',
	'Sources/AgentStudio/Features/Bridge',
	'Sources/AgentStudio/Core',
	'Sources/AgentStudio/Infrastructure',
	'Sources/AgentStudio/SharedComponents',
	'Sources/AgentStudioProgrammaticControl',
] as const;

const watchedManifestAndTaskFiles = ['.mise.toml', 'Package.swift', 'Package.resolved'] as const;

const watchedBuildScriptFiles = [
	'scripts/build-bridge-development-server.sh',
	'scripts/swift-build-slot.sh',
	'scripts/vendor-worktree.sh',
] as const;

const watchedExactFileSet: ReadonlySet<string> = new Set([
	...watchedManifestAndTaskFiles,
	...watchedBuildScriptFiles,
]);

interface BridgeDevelopmentServerViteSession {
	readonly recordRelevantChange: () => void;
	readonly start: () => Promise<void>;
	readonly stop: () => Promise<void>;
}

interface BridgeDevelopmentServerHttpCloseEmitter {
	off: (eventName: 'close', listener: () => void) => unknown;
	once: (eventName: 'close', listener: () => void) => unknown;
}

type BridgeDevelopmentServerProcessTerminationEvent = 'exit' | 'SIGINT' | 'SIGTERM';

interface BridgeDevelopmentServerProcessExitEmitter {
	off: (eventName: BridgeDevelopmentServerProcessTerminationEvent, listener: () => void) => unknown;
	once: (
		eventName: BridgeDevelopmentServerProcessTerminationEvent,
		listener: () => void,
	) => unknown;
}

export function createBridgeDevelopmentServerVitePlugin(props: {
	readonly backendOrigin: string;
	readonly repoRootPath: string;
}): Plugin {
	let configuredServer: ViteDevServer | null = null;
	let closeSessionPromise: Promise<void> | null = null;
	let session: BridgeDevelopmentServerViteSession | null = null;
	let unregisterHttpCloseCleanup: (() => void) | null = null;
	let watcherEventHandler: ((eventName: string, changedPath: string) => void) | null = null;
	const closeSession = async (): Promise<void> => {
		closeSessionPromise ??= (async (): Promise<void> => {
			unregisterHttpCloseCleanup?.();
			unregisterHttpCloseCleanup = null;
			if (configuredServer !== null && watcherEventHandler !== null) {
				configuredServer.watcher.off('all', watcherEventHandler);
			}
			watcherEventHandler = null;
			configuredServer = null;
			const closingSession = session;
			session = null;
			await closingSession?.stop();
		})();
		await closeSessionPromise;
	};
	return {
		apply: 'serve',
		name: 'bridge-development-server-supervisor',
		async configureServer(server): Promise<void> {
			configuredServer = server;
			session = await createBridgeDevelopmentServerViteSession({
				backendOrigin: props.backendOrigin,
				repoRootPath: props.repoRootPath,
				report: (message): void => server.config.logger.info(`[bridge-backend] ${message}`),
			});
			watcherEventHandler = (_eventName, changedPath): void => {
				if (
					bridgeDevelopmentServerSourceChangeIsRelevant({
						changedPath,
						repoRootPath: props.repoRootPath,
					})
				) {
					session?.recordRelevantChange();
				}
			};
			server.watcher.add(bridgeDevelopmentServerWatchedPaths(props.repoRootPath));
			server.watcher.on('all', watcherEventHandler);
			unregisterHttpCloseCleanup = registerBridgeDevelopmentServerHttpCloseCleanup({
				httpServer: server.httpServer,
				reportFailure: (error): void => {
					server.config.logger.error(`[bridge-backend] shutdown failed: ${errorMessage(error)}`);
				},
				shutdown: closeSession,
			});
			const startSession = (): void => {
				void session?.start().catch((error: unknown): void => {
					server.config.logger.error(`[bridge-backend] supervisor failed: ${errorMessage(error)}`);
				});
			};
			if (server.httpServer === null) startSession();
			else server.httpServer.once('listening', startSession);
		},
		async closeBundle(): Promise<void> {
			await closeSession();
		},
	};
}

export function registerBridgeDevelopmentServerHttpCloseCleanup(props: {
	readonly httpServer: BridgeDevelopmentServerHttpCloseEmitter | null;
	readonly reportFailure: (error: unknown) => void;
	readonly shutdown: () => Promise<void>;
}): () => void {
	if (props.httpServer === null) return (): void => {};
	const closeListener = (): void => {
		void props.shutdown().catch(props.reportFailure);
	};
	props.httpServer.once('close', closeListener);
	return (): void => {
		props.httpServer?.off('close', closeListener);
	};
}

export function registerBridgeDevelopmentServerProcessExitCleanup(props: {
	readonly dataRootPath: string;
	readonly processEmitter: BridgeDevelopmentServerProcessExitEmitter;
	readonly removeDataRootSynchronously: (dataRootPath: string) => void;
}): () => void {
	const terminationEvents = ['SIGINT', 'SIGTERM', 'exit'] as const;
	const unregister = (): void => {
		for (const eventName of terminationEvents) {
			props.processEmitter.off(eventName, exitListener);
		}
	};
	const exitListener = (): void => {
		unregister();
		props.removeDataRootSynchronously(props.dataRootPath);
	};
	for (const eventName of terminationEvents) {
		props.processEmitter.once(eventName, exitListener);
	}
	return unregister;
}

export function bridgeDevelopmentServerWatchedPaths(repoRootPath: string): readonly string[] {
	return [
		...watchedManifestAndTaskFiles.map((relativePath) => join(repoRootPath, relativePath)),
		...watchedSourceDirectories.map((relativePath) => join(repoRootPath, relativePath)),
		...watchedBuildScriptFiles.map((relativePath) => join(repoRootPath, relativePath)),
	];
}

export function bridgeDevelopmentServerSourceChangeIsRelevant(props: {
	readonly changedPath: string;
	readonly repoRootPath: string;
}): boolean {
	const relativePath = relative(props.repoRootPath, resolve(props.changedPath));
	if (relativePath === '' || relativePath === '..' || relativePath.startsWith(`..${sep}`)) {
		return false;
	}
	if (isAbsolute(relativePath)) return false;
	const normalizedRelativePath = relativePath.split(sep).join('/');
	if (watchedExactFileSet.has(normalizedRelativePath)) return true;
	if (!normalizedRelativePath.endsWith('.swift')) return false;
	return watchedSourceDirectories.some(
		(sourceDirectory) =>
			normalizedRelativePath === sourceDirectory ||
			normalizedRelativePath.startsWith(`${sourceDirectory}/`),
	);
}

async function createBridgeDevelopmentServerViteSession(props: {
	readonly backendOrigin: string;
	readonly repoRootPath: string;
	readonly report: (message: string) => void;
}): Promise<BridgeDevelopmentServerViteSession> {
	const dataRootPath = await mkdtemp(join(tmpdir(), 'agentstudio-bridge-vite-'));
	const unregisterProcessExitCleanup = registerBridgeDevelopmentServerProcessExitCleanup({
		dataRootPath,
		processEmitter: process,
		removeDataRootSynchronously: (ownedDataRootPath): void => {
			rmSync(ownedDataRootPath, { force: true, recursive: true });
		},
	});
	const backendPort = bridgeDevelopmentServerPort(props.backendOrigin);
	const supervisor: BridgeDevelopmentServerSupervisor = createBridgeDevelopmentServerSupervisor({
		buildCandidate: async (signal): Promise<void> => {
			props.report('building Swift development server…');
			await runBridgeDevelopmentServerBuild({
				repoRootPath: props.repoRootPath,
				signal,
			});
		},
		launchServer: async () => {
			const ownedServer = await startOwnedBridgeDevelopmentServer({
				dataRootPath,
				initialTarget: 'HEAD',
				paneId: bridgeDevelopmentPaneId,
				port: backendPort,
				repoRootPath: props.repoRootPath,
				worktreeRoot: props.repoRootPath,
			});
			return {
				stop: async (): Promise<void> => {
					requireOwnedBridgeDevelopmentServerExit(await ownedServer.stop());
				},
			};
		},
		report: props.report,
	});
	let stopPromise: Promise<void> | null = null;
	return {
		recordRelevantChange: (): void => supervisor.recordRelevantChange(),
		start: async (): Promise<void> => await supervisor.start(),
		stop: async (): Promise<void> => {
			stopPromise ??= runAllOwnedCleanupOperations({
				operations: [
					{
						name: 'Bridge development server',
						run: async (): Promise<void> => await supervisor.stop(),
					},
					{
						name: 'Bridge development server data root',
						run: async (): Promise<void> => {
							unregisterProcessExitCleanup();
							await rm(dataRootPath, { force: true, recursive: true });
						},
					},
				],
			});
			await stopPromise;
		},
	};
}

export function requireOwnedBridgeDevelopmentServerExit(
	cleanup: OwnedBridgeDevelopmentServerCleanup,
): void {
	if (cleanup.ownedProcessAliveAfterStop) {
		throw new Error('Owned Bridge development server remained alive after bounded shutdown.');
	}
}

function bridgeDevelopmentServerPort(backendOrigin: string): number {
	const origin = new URL(backendOrigin);
	const port = Number(origin.port);
	if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
		throw new Error('The supervised Bridge development backend origin requires an explicit port.');
	}
	return port;
}

function runBridgeDevelopmentServerBuild(props: {
	readonly repoRootPath: string;
	readonly signal: AbortSignal;
}): Promise<void> {
	return new Promise<void>((resolveBuild, rejectBuild): void => {
		const child = spawn('mise', ['run', 'build-bridge-development-server'], {
			cwd: props.repoRootPath,
			detached: true,
			env: { ...process.env },
			stdio: 'inherit',
		});
		let forcedTerminationTimeout: ReturnType<typeof setTimeout> | null = null;
		let settled = false;
		const finish = (error?: unknown): void => {
			if (settled) return;
			settled = true;
			props.signal.removeEventListener('abort', stopBuild);
			if (forcedTerminationTimeout !== null) clearTimeout(forcedTerminationTimeout);
			if (error === undefined) resolveBuild();
			else rejectBuild(error);
		};
		const signalBuildProcessGroup = (signal: NodeJS.Signals): void => {
			if (child.pid === undefined) return;
			try {
				process.kill(-child.pid, signal);
			} catch (error: unknown) {
				if (!isMissingProcessError(error)) throw error;
			}
		};
		const stopBuild = (): void => {
			try {
				signalBuildProcessGroup('SIGTERM');
				forcedTerminationTimeout = setTimeout((): void => {
					try {
						signalBuildProcessGroup('SIGKILL');
					} catch (error: unknown) {
						finish(error);
					}
				}, buildShutdownTimeoutMilliseconds);
			} catch (error: unknown) {
				finish(error);
			}
		};
		child.once('error', finish);
		child.once('exit', (code, signal): void => {
			if (props.signal.aborted) {
				finish(props.signal.reason);
				return;
			}
			if (code === 0) finish();
			else
				finish(
					new Error(`Swift development server build exited ${exitDescription(code, signal)}.`),
				);
		});
		props.signal.addEventListener('abort', stopBuild, { once: true });
		if (props.signal.aborted) stopBuild();
	});
}

function exitDescription(code: number | null, signal: NodeJS.Signals | null): string {
	return code === null ? `from signal ${signal ?? 'unknown'}` : `with code ${code}`;
}

function isMissingProcessError(error: unknown): boolean {
	return typeof error === 'object' && error !== null && 'code' in error && error.code === 'ESRCH';
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
