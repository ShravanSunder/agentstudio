const defaultQuietWindowMilliseconds = 10_000;
const defaultBuildTimeoutMilliseconds = 300_000;
const launchRetryDelayMilliseconds = 1_000;
const maximumLaunchAttempts = 3;

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
	private resolveLaunchRetryDelay: ((shouldRetry: boolean) => void) | null = null;
	private started = false;
	private stopped = false;
	private stopPromise: Promise<void> | null = null;

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
		this.activeServer = null;
		await server?.stop();
	}

	private ensureBuildDrain(): Promise<void> {
		if (this.buildDrainPromise !== null) return this.buildDrainPromise;
		const drainPromise = this.drainBuildQueue();
		this.buildDrainPromise = drainPromise;
		void drainPromise.finally((): void => {
			if (this.buildDrainPromise === drainPromise) this.buildDrainPromise = null;
			if (this.pendingBuild && !this.stopped) void this.ensureBuildDrain();
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
		this.activeServer = null;
		await previousServer?.stop();
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
				this.activeServer = await this.props.launchServer();
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
