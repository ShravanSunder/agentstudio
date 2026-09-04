const defaultQuietWindowMilliseconds = 10_000;
const defaultBuildTimeoutMilliseconds = 300_000;
const launchRetryDelayMilliseconds = 1_000;
const maximumLaunchAttempts = 3;
const maximumUnexpectedExitRecoveries = 3;

export interface BridgeDevelopmentServerSupervisorClockOperation {
	readonly cancel: () => void;
}

export interface BridgeDevelopmentServerSupervisorClock {
	readonly schedule: (
		delayMilliseconds: number,
		operation: () => void,
	) => BridgeDevelopmentServerSupervisorClockOperation;
}

export interface SupervisedBridgeDevelopmentServer {
	readonly stop: () => Promise<unknown>;
	readonly whenExited: Promise<void>;
}

export interface BridgeDevelopmentServerSupervisor {
	readonly recordRelevantChange: () => void;
	readonly start: () => Promise<void>;
	readonly stop: () => Promise<void>;
}

export function createBridgeDevelopmentServerSupervisor(props: {
	readonly buildCandidate: (signal: AbortSignal) => Promise<void>;
	readonly buildTimeoutMilliseconds?: number;
	readonly clock?: BridgeDevelopmentServerSupervisorClock;
	readonly launchServer: () => Promise<SupervisedBridgeDevelopmentServer>;
	readonly quietWindowMilliseconds?: number;
	readonly report: (message: string) => void;
}): BridgeDevelopmentServerSupervisor {
	return new DefaultBridgeDevelopmentServerSupervisor({
		buildCandidate: props.buildCandidate,
		buildTimeoutMilliseconds: props.buildTimeoutMilliseconds ?? defaultBuildTimeoutMilliseconds,
		clock: props.clock ?? systemSupervisorClock,
		launchServer: props.launchServer,
		quietWindowMilliseconds: props.quietWindowMilliseconds ?? defaultQuietWindowMilliseconds,
		report: props.report,
	});
}

class DefaultBridgeDevelopmentServerSupervisor implements BridgeDevelopmentServerSupervisor {
	private activeServer: SupervisedBridgeDevelopmentServer | null = null;
	private activeBuildController: AbortController | null = null;
	private buildDrainPromise: Promise<void> | null = null;
	private changeGeneration = 0;
	private pendingBuild = false;
	private quietWindowOperation: BridgeDevelopmentServerSupervisorClockOperation | null = null;
	private launchRetryOperation: BridgeDevelopmentServerSupervisorClockOperation | null = null;
	private readonly expectedExitServers = new Set<SupervisedBridgeDevelopmentServer>();
	private resolveLaunchRetryDelay: ((shouldRetry: boolean) => void) | null = null;
	private started = false;
	private stopped = false;
	private stopPromise: Promise<void> | null = null;
	private unexpectedExitRecoveryCount = 0;

	constructor(
		private readonly props: {
			readonly buildCandidate: (signal: AbortSignal) => Promise<void>;
			readonly buildTimeoutMilliseconds: number;
			readonly clock: BridgeDevelopmentServerSupervisorClock;
			readonly launchServer: () => Promise<SupervisedBridgeDevelopmentServer>;
			readonly quietWindowMilliseconds: number;
			readonly report: (message: string) => void;
		},
	) {}

	async start(): Promise<void> {
		if (this.started || this.stopped) return;
		this.started = true;
		this.pendingBuild = true;
		await this.ensureBuildDrain();
	}

	recordRelevantChange(): void {
		if (this.stopped) return;
		this.changeGeneration += 1;
		this.unexpectedExitRecoveryCount = 0;
		this.cancelLaunchRetryDelay();
		this.quietWindowOperation?.cancel();
		this.quietWindowOperation = this.props.clock.schedule(
			this.props.quietWindowMilliseconds,
			(): void => {
				this.quietWindowOperation = null;
				this.pendingBuild = true;
				void this.ensureBuildDrain();
			},
		);
	}

	async stop(): Promise<void> {
		this.stopPromise ??= this.stopOnce();
		await this.stopPromise;
	}

	private async stopOnce(): Promise<void> {
		this.stopped = true;
		this.pendingBuild = false;
		this.quietWindowOperation?.cancel();
		this.quietWindowOperation = null;
		this.cancelLaunchRetryDelay();
		this.activeBuildController?.abort(new Error('Bridge development supervisor stopped.'));
		await this.buildDrainPromise;
		const server = this.activeServer;
		if (server === null) return;
		this.expectedExitServers.add(server);
		try {
			await server.stop();
		} finally {
			this.expectedExitServers.delete(server);
		}
		if (this.activeServer === server) this.activeServer = null;
	}

	private ensureBuildDrain(): Promise<void> {
		if (this.buildDrainPromise !== null) return this.buildDrainPromise;
		const drainPromise = this.drainBuildQueue();
		this.buildDrainPromise = drainPromise;
		const finishBuildDrain = (): void => {
			if (this.buildDrainPromise === drainPromise) this.buildDrainPromise = null;
			if (this.pendingBuild && !this.stopped) void this.ensureBuildDrain();
		};
		void drainPromise.then(finishBuildDrain, (error: unknown): void => {
			this.props.report(`Bridge development server supervisor failed: ${errorMessage(error)}`);
			finishBuildDrain();
		});
		return drainPromise;
	}

	private async drainBuildQueue(): Promise<void> {
		while (this.pendingBuild && !this.stopped) {
			this.pendingBuild = false;
			// oxlint-disable-next-line no-await-in-loop -- Builds are intentionally serialized and coalesced.
			await this.buildAndReplaceCurrentGeneration();
		}
	}

	private async buildAndReplaceCurrentGeneration(): Promise<void> {
		const candidateGeneration = this.changeGeneration;
		const buildController = new AbortController();
		this.activeBuildController = buildController;
		const buildTimeout = this.props.clock.schedule(
			this.props.buildTimeoutMilliseconds,
			(): void => {
				buildController.abort(
					new Error(
						`Bridge development server build exceeded ${this.props.buildTimeoutMilliseconds}ms.`,
					),
				);
			},
		);
		try {
			await this.props.buildCandidate(buildController.signal);
		} catch (error: unknown) {
			if (!this.stopped) this.props.report(buildFailureMessage(error));
			return;
		} finally {
			buildTimeout.cancel();
			if (this.activeBuildController === buildController) this.activeBuildController = null;
		}
		if (this.stopped) return;
		if (candidateGeneration !== this.changeGeneration) {
			this.props.report(
				'Bridge development server build became stale; waiting for current source.',
			);
			return;
		}
		const previousServer = this.activeServer;
		if (previousServer !== null) {
			this.expectedExitServers.add(previousServer);
			try {
				await previousServer.stop();
			} catch (error: unknown) {
				this.expectedExitServers.delete(previousServer);
				this.props.report(
					`Bridge development server replacement stop failed; retaining cleanup authority: ${errorMessage(error)}`,
				);
				return;
			}
			this.expectedExitServers.delete(previousServer);
			if (this.activeServer === previousServer) this.activeServer = null;
		}
		if (this.stopped) return;
		// oxlint-disable no-await-in-loop -- Launch retries are bounded, delayed, and reuse one successful build.
		for (let launchAttempt = 1; launchAttempt <= maximumLaunchAttempts; launchAttempt += 1) {
			if (this.stopped) return;
			if (candidateGeneration !== this.changeGeneration) {
				this.props.report(
					'Bridge development server launch candidate became stale; waiting for current source.',
				);
				return;
			}
			try {
				const launchedServer = await this.props.launchServer();
				this.activeServer = launchedServer;
				this.observeUnexpectedExit(launchedServer);
				this.props.report('Bridge development server is ready.');
				return;
			} catch (error: unknown) {
				this.props.report(
					`Bridge development server launch failed (${launchAttempt}/${maximumLaunchAttempts}): ${errorMessage(error)}`,
				);
			}
			if (launchAttempt < maximumLaunchAttempts && !(await this.waitForLaunchRetryDelay())) {
				return;
			}
		}
		// oxlint-enable no-await-in-loop
	}

	private observeUnexpectedExit(server: SupervisedBridgeDevelopmentServer): void {
		void server.whenExited.then((): void => {
			if (this.stopped || this.expectedExitServers.has(server) || this.activeServer !== server) {
				return;
			}
			this.activeServer = null;
			this.unexpectedExitRecoveryCount += 1;
			if (this.unexpectedExitRecoveryCount > maximumUnexpectedExitRecoveries) {
				this.props.report(
					`Bridge development server exited unexpectedly; recovery limit ${maximumUnexpectedExitRecoveries} reached.`,
				);
				return;
			}
			this.props.report(
				`Bridge development server exited unexpectedly; rebuilding (${this.unexpectedExitRecoveryCount}/${maximumUnexpectedExitRecoveries}).`,
			);
			this.pendingBuild = true;
			void this.ensureBuildDrain();
		});
	}

	private async waitForLaunchRetryDelay(): Promise<boolean> {
		if (this.stopped) return false;
		return await new Promise<boolean>((resolve): void => {
			this.resolveLaunchRetryDelay = resolve;
			this.launchRetryOperation = this.props.clock.schedule(
				launchRetryDelayMilliseconds,
				(): void => {
					this.launchRetryOperation = null;
					this.resolveLaunchRetryDelay = null;
					resolve(!this.stopped);
				},
			);
		});
	}

	private cancelLaunchRetryDelay(): void {
		this.launchRetryOperation?.cancel();
		this.launchRetryOperation = null;
		const resolveRetryDelay = this.resolveLaunchRetryDelay;
		this.resolveLaunchRetryDelay = null;
		resolveRetryDelay?.(false);
	}
}

const systemSupervisorClock: BridgeDevelopmentServerSupervisorClock = {
	schedule: (delayMilliseconds, operation): BridgeDevelopmentServerSupervisorClockOperation => {
		const timeout = setTimeout(operation, delayMilliseconds);
		return { cancel: (): void => clearTimeout(timeout) };
	},
};

function buildFailureMessage(error: unknown): string {
	return `Bridge development server build failed; keeping the current server: ${errorMessage(error)}`;
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
