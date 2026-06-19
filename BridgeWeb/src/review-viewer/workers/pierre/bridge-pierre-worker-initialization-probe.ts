import type { DiffsThemeNames, SupportedLanguages } from '@pierre/diffs';
import { resolveLanguages, resolveThemes } from '@pierre/diffs';

export type BridgePierreWorkerInitializationProbeStage =
	| 'idle'
	| 'worker-manager-waiting'
	| 'worker-manager-initializing'
	| 'theme-resolution-started'
	| 'theme-resolution-resolved'
	| 'theme-resolution-timed-out'
	| 'theme-resolution-failed'
	| 'language-resolution-started'
	| 'language-resolution-resolved'
	| 'language-resolution-timed-out'
	| 'language-resolution-failed'
	| 'workers-created'
	| 'worker-manager-initialized'
	| 'worker-manager-failed';

export interface BridgePierreWorkerInitializationProbeSnapshot {
	readonly stage: BridgePierreWorkerInitializationProbeStage;
	readonly themeCount: number;
	readonly languageCount: number;
	readonly failureReason: string;
}

export interface BridgePierreWorkerInitializationProbeDataset {
	bridgePierreWorkerPoolInitProbeStage?: string;
	bridgePierreWorkerPoolInitProbeThemeCount?: string;
	bridgePierreWorkerPoolInitProbeLanguageCount?: string;
	bridgePierreWorkerPoolInitProbeFailureReason?: string;
}

export interface BridgePierreWorkerInitializationProbeDatasetTarget {
	readonly dataset: BridgePierreWorkerInitializationProbeDataset;
}

export interface BridgePierreWorkerInitializationProbeResolvers {
	readonly resolveThemes: (themeNames: readonly DiffsThemeNames[]) => Promise<readonly unknown[]>;
	readonly resolveLanguages: (
		languages: readonly SupportedLanguages[],
	) => Promise<readonly unknown[]>;
}

export interface RunBridgePierreWorkerInitializationProbeProps {
	readonly themeNames: readonly DiffsThemeNames[];
	readonly languages: readonly SupportedLanguages[];
	readonly timeoutMilliseconds?: number;
	readonly resolvers?: BridgePierreWorkerInitializationProbeResolvers;
	readonly onSnapshot?: (snapshot: BridgePierreWorkerInitializationProbeSnapshot) => void;
}

const defaultTimeoutMilliseconds = 2_000;
const defaultProbeResolvers: BridgePierreWorkerInitializationProbeResolvers = {
	resolveThemes: async (themeNames: readonly DiffsThemeNames[]): Promise<readonly unknown[]> =>
		await resolveThemes([...themeNames]),
	resolveLanguages: async (languages: readonly SupportedLanguages[]): Promise<readonly unknown[]> =>
		await resolveLanguages([...languages]),
};

export async function runBridgePierreWorkerInitializationProbe(
	props: RunBridgePierreWorkerInitializationProbeProps,
): Promise<BridgePierreWorkerInitializationProbeSnapshot> {
	const timeoutMilliseconds = props.timeoutMilliseconds ?? defaultTimeoutMilliseconds;
	const resolvers = props.resolvers ?? defaultProbeResolvers;
	const emitSnapshot = props.onSnapshot ?? ((): void => {});

	const themeStartedSnapshot = bridgePierreWorkerInitializationProbeSnapshot({
		stage: 'theme-resolution-started',
		themeCount: 0,
		languageCount: 0,
	});
	emitSnapshot(themeStartedSnapshot);

	let resolvedThemeCount = 0;
	try {
		const resolvedThemes = await bridgePierreWorkerProbeWithTimeout({
			promise: resolvers.resolveThemes(props.themeNames),
			stage: 'theme-resolution',
			timeoutMilliseconds,
		});
		resolvedThemeCount = resolvedThemes.length;
		emitSnapshot(
			bridgePierreWorkerInitializationProbeSnapshot({
				stage: 'theme-resolution-resolved',
				themeCount: resolvedThemeCount,
				languageCount: 0,
			}),
		);
	} catch (error: unknown) {
		const failedSnapshot = bridgePierreWorkerProbeFailedSnapshot({
			error,
			timeoutStage: 'theme-resolution-timed-out',
			failureStage: 'theme-resolution-failed',
			themeCount: 0,
			languageCount: 0,
		});
		emitSnapshot(failedSnapshot);
		return failedSnapshot;
	}

	emitSnapshot(
		bridgePierreWorkerInitializationProbeSnapshot({
			stage: 'language-resolution-started',
			themeCount: resolvedThemeCount,
			languageCount: 0,
		}),
	);

	try {
		const resolvedLanguages = await bridgePierreWorkerProbeWithTimeout({
			promise: resolvers.resolveLanguages(props.languages),
			stage: 'language-resolution',
			timeoutMilliseconds,
		});
		const resolvedSnapshot = bridgePierreWorkerInitializationProbeSnapshot({
			stage: 'language-resolution-resolved',
			themeCount: resolvedThemeCount,
			languageCount: resolvedLanguages.length,
		});
		emitSnapshot(resolvedSnapshot);
		return resolvedSnapshot;
	} catch (error: unknown) {
		const failedSnapshot = bridgePierreWorkerProbeFailedSnapshot({
			error,
			timeoutStage: 'language-resolution-timed-out',
			failureStage: 'language-resolution-failed',
			themeCount: resolvedThemeCount,
			languageCount: 0,
		});
		emitSnapshot(failedSnapshot);
		return failedSnapshot;
	}
}

export function writeBridgePierreWorkerInitializationProbeSnapshotToDataset(props: {
	readonly rootElement: BridgePierreWorkerInitializationProbeDatasetTarget;
	readonly snapshot: BridgePierreWorkerInitializationProbeSnapshot;
}): void {
	props.rootElement.dataset.bridgePierreWorkerPoolInitProbeStage = props.snapshot.stage;
	props.rootElement.dataset.bridgePierreWorkerPoolInitProbeThemeCount = String(
		props.snapshot.themeCount,
	);
	props.rootElement.dataset.bridgePierreWorkerPoolInitProbeLanguageCount = String(
		props.snapshot.languageCount,
	);
	props.rootElement.dataset.bridgePierreWorkerPoolInitProbeFailureReason =
		props.snapshot.failureReason;
}

function bridgePierreWorkerInitializationProbeSnapshot(props: {
	readonly stage: BridgePierreWorkerInitializationProbeStage;
	readonly themeCount: number;
	readonly languageCount: number;
	readonly failureReason?: string;
}): BridgePierreWorkerInitializationProbeSnapshot {
	return {
		stage: props.stage,
		themeCount: props.themeCount,
		languageCount: props.languageCount,
		failureReason: props.failureReason ?? '',
	};
}

function bridgePierreWorkerProbeFailedSnapshot(props: {
	readonly error: unknown;
	readonly timeoutStage: BridgePierreWorkerInitializationProbeStage;
	readonly failureStage: BridgePierreWorkerInitializationProbeStage;
	readonly themeCount: number;
	readonly languageCount: number;
}): BridgePierreWorkerInitializationProbeSnapshot {
	if (props.error instanceof BridgePierreWorkerProbeTimeoutError) {
		return bridgePierreWorkerInitializationProbeSnapshot({
			stage: props.timeoutStage,
			themeCount: props.themeCount,
			languageCount: props.languageCount,
			failureReason: 'timeout',
		});
	}

	return bridgePierreWorkerInitializationProbeSnapshot({
		stage: props.failureStage,
		themeCount: props.themeCount,
		languageCount: props.languageCount,
		failureReason: bridgePierreWorkerProbeFailureReason(props.error),
	});
}

async function bridgePierreWorkerProbeWithTimeout<TResult>(props: {
	readonly promise: Promise<TResult>;
	readonly stage: 'theme-resolution' | 'language-resolution';
	readonly timeoutMilliseconds: number;
}): Promise<TResult> {
	let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
	const timeoutPromise = new Promise<never>((_, reject): void => {
		timeoutHandle = setTimeout((): void => {
			reject(new BridgePierreWorkerProbeTimeoutError(props.stage));
		}, props.timeoutMilliseconds);
	});

	try {
		return await Promise.race([props.promise, timeoutPromise]);
	} finally {
		if (timeoutHandle !== undefined) {
			clearTimeout(timeoutHandle);
		}
	}
}

function bridgePierreWorkerProbeFailureReason(error: unknown): string {
	if (error instanceof Error && error.name.length > 0) {
		return error.name;
	}
	return 'unknown';
}

class BridgePierreWorkerProbeTimeoutError extends Error {
	constructor(readonly stage: 'theme-resolution' | 'language-resolution') {
		super(`Bridge Pierre worker initialization probe timed out during ${stage}`);
		this.name = 'BridgePierreWorkerProbeTimeoutError';
	}
}
