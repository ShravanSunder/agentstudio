import type {
	FileContents,
	WorkerInitializationRenderOptions,
	WorkerPoolOptions,
} from '@pierre/diffs/react';
import { WorkerPoolContext, useWorkerPool } from '@pierre/diffs/react';
import {
	getOrCreateWorkerPoolSingleton,
	terminateWorkerPoolSingleton,
	type WorkerPoolManager,
} from '@pierre/diffs/worker';
import type { ReactElement, ReactNode } from 'react';
import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { z } from 'zod';

import {
	bridgePierreDarkThemeName,
	ensureBridgeCodeViewThemeResolved,
} from '../../code-view/bridge-code-view-theme.js';
import {
	attachBridgePierreWorkerDiagnostics,
	attachBridgePierreWorkerRequestDiagnostics,
	wrapBridgePierreWorkerSourceWithDiagnostics,
} from './bridge-pierre-worker-diagnostics.js';
import {
	runBridgePierreWorkerInitializationProbe,
	writeBridgePierreWorkerInitializationProbeSnapshotToDataset,
	type BridgePierreWorkerInitializationProbeSnapshot,
} from './bridge-pierre-worker-initialization-probe.js';

export {
	attachBridgePierreWorkerDiagnostics,
	wrapBridgePierreWorkerSourceWithDiagnostics,
	type BridgePierreWorkerDiagnosticDataset,
	type BridgePierreWorkerDiagnosticDatasetTarget,
} from './bridge-pierre-worker-diagnostics.js';

export const bridgePierreWorkerKindSchema = z.enum(['classicWorker', 'moduleWorker']);

export type BridgePierreWorkerKind = z.infer<typeof bridgePierreWorkerKindSchema>;

export const bridgePierreWorkerAssetManifestSchema = z
	.object({
		kind: z.literal('pierre-diffs-shiki'),
		path: z.string().min(1),
		agentStudioAppUrl: z
			.string()
			.regex(/^agentstudio:\/\/app\/.+/u, 'worker asset must resolve through agentstudio://app'),
		workerKind: bridgePierreWorkerKindSchema,
		source: z.literal('packagedAppAsset'),
		bytes: z.number().int().positive(),
		sha256: z.string().regex(/^[a-f0-9]{64}$/u),
	})
	.strict();

export type BridgePierreWorkerAssetManifest = z.infer<typeof bridgePierreWorkerAssetManifestSchema>;

export type BridgePierreWorkerStats = ReturnType<
	NonNullable<ReturnType<typeof useWorkerPool>>['getStats']
>;

export interface CreateBridgePierreWorkerFactoryProps {
	readonly workerScriptUrl?: string | URL;
	readonly workerKind?: BridgePierreWorkerKind;
	readonly createWorker?: (url: string | URL, options?: WorkerOptions) => Worker;
}

export interface CreateBridgePierreWorkerPoolOptionsProps {
	readonly workerFactory: () => Worker;
	readonly poolSize?: number;
	readonly totalASTLRUCacheSize?: number;
}

export interface CreateBridgePierreBlobWorkerFactoryProps {
	readonly workerSource: string;
	readonly workerKind?: BridgePierreWorkerKind;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
	readonly createWorker?: (url: string | URL, options?: WorkerOptions) => Worker;
}

export interface BridgePierreBlobWorkerFactory {
	readonly workerScriptUrl: string;
	readonly workerFactory: () => Worker;
	readonly revoke: () => void;
}

export interface BridgePierreWorkerPoolProviderProps {
	readonly children: ReactNode;
	readonly enabled?: boolean;
	readonly ensureCodeViewThemeResolved?: () => Promise<void>;
	readonly workerFactory?: () => Worker;
	readonly poolSize?: number;
}

type BridgePierreWorkerPoolLoadState =
	| { readonly kind: 'disabled' }
	| { readonly kind: 'loading' }
	| { readonly kind: 'ready'; readonly workerFactory: () => Worker }
	| { readonly kind: 'failed'; readonly errorMessage: string };

type BridgeCodeViewThemeLoadState =
	| { readonly kind: 'loading' }
	| { readonly kind: 'ready' }
	| { readonly kind: 'failed'; readonly errorMessage: string };

type BridgePierreWorkerPoolReadinessState =
	| { readonly kind: 'loading' }
	| { readonly kind: 'ready' }
	| { readonly kind: 'failed' };

export const bridgePierreDefaultWorkerScriptUrl =
	'agentstudio://app/workers/pierre-diffs-worker-portable.js';
const defaultWorkerScriptUrl = bridgePierreDefaultWorkerScriptUrl;
const defaultBridgePierreWorkerKind = 'classicWorker' satisfies BridgePierreWorkerKind;
// DiffsHub desktop parity: apps/diffshub/app/_components/WorkerPoolContext.tsx caps at 3.
const defaultPoolSize = 3;
const defaultTotalASTLRUCacheSize = 128;
const bridgePierreWorkerPoolStatsPollIntervalMilliseconds = 100;
const bridgePierreUnrankedWorkerTaskRank = Number.MAX_SAFE_INTEGER;
let bridgePierreWorkerPoolProviderInstanceCount = 0;

export function createBridgePierreWorkerFactory(
	props: CreateBridgePierreWorkerFactoryProps = {},
): () => Worker {
	const workerScriptUrl = props.workerScriptUrl ?? defaultWorkerScriptUrl;
	const workerKind = props.workerKind ?? defaultBridgePierreWorkerKind;
	const createWorker = props.createWorker ?? defaultCreateWorker;

	return (): Worker => {
		const worker =
			workerKind === 'moduleWorker'
				? createWorker(workerScriptUrl, { type: 'module' })
				: createWorker(workerScriptUrl);
		if (typeof document !== 'undefined') {
			attachBridgePierreWorkerRequestDiagnostics(worker);
			attachBridgePierreWorkerDiagnostics(worker);
		}
		return worker;
	};
}

export function createBridgePierreWorkerPoolOptions(
	props: CreateBridgePierreWorkerPoolOptionsProps,
): WorkerPoolOptions {
	return {
		workerFactory: props.workerFactory,
		poolSize: props.poolSize ?? defaultPoolSize,
		totalASTLRUCacheSize: props.totalASTLRUCacheSize ?? defaultTotalASTLRUCacheSize,
	};
}

export function terminateBridgePierreWorkerPoolSingletonForTest(): void {
	terminateWorkerPoolSingleton();
}

export function createBridgePierreBlobWorkerFactory(
	props: CreateBridgePierreBlobWorkerFactoryProps,
): BridgePierreBlobWorkerFactory {
	const workerKind = props.workerKind ?? defaultBridgePierreWorkerKind;
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	const workerScriptBlob = new Blob(
		[wrapBridgePierreWorkerSourceWithDiagnostics(props.workerSource)],
		{
			type: 'application/javascript',
		},
	);
	const workerScriptUrl = createObjectURL(workerScriptBlob);
	const workerFactory = createBridgePierreWorkerFactory({
		workerScriptUrl,
		workerKind,
		...(props.createWorker === undefined ? {} : { createWorker: props.createWorker }),
	});

	return {
		workerScriptUrl,
		workerFactory,
		revoke: (): void => {
			revokeObjectURL(workerScriptUrl);
		},
	};
}

export function createBridgePierreWorkerHighlighterOptions(): WorkerInitializationRenderOptions {
	return {
		theme: {
			dark: bridgePierreDarkThemeName,
			light: bridgePierreDarkThemeName,
		},
		preferredHighlighter: 'shiki-js',
		useTokenTransformer: false,
		tokenizeMaxLineLength: 20_000,
		lineDiffType: 'word',
		maxLineDiffLength: 1000,
	};
}

type BridgePierreDemandRankedFile = FileContents & {
	readonly bridgeDemandRank?: number;
};

interface BridgePierreWorkerPoolQueuedTask {
	readonly id?: number;
	readonly request?: {
		readonly file?: BridgePierreDemandRankedFile;
	};
}

const bridgePierreRankSchedulerInstalledManagers = new WeakSet<WorkerPoolManager>();

export function bridgePierreDemandRankForWorkerTask(
	task: BridgePierreWorkerPoolQueuedTask,
): number {
	const demandRank = task.request?.file?.bridgeDemandRank;
	return typeof demandRank === 'number' && Number.isFinite(demandRank)
		? demandRank
		: bridgePierreUnrankedWorkerTaskRank;
}

export function sortBridgePierreWorkerPoolQueuedTasksForDemandRank(
	queuedTasks: BridgePierreWorkerPoolQueuedTask[],
): void {
	queuedTasks.sort((left, right): number => {
		const demandRankComparison =
			bridgePierreDemandRankForWorkerTask(left) - bridgePierreDemandRankForWorkerTask(right);
		if (demandRankComparison !== 0) {
			return demandRankComparison;
		}
		return (
			(left.id ?? bridgePierreUnrankedWorkerTaskRank) -
			(right.id ?? bridgePierreUnrankedWorkerTaskRank)
		);
	});
}

export function installBridgePierreWorkerPoolRankScheduler(workerPool: WorkerPoolManager): void {
	if (bridgePierreRankSchedulerInstalledManagers.has(workerPool)) {
		return;
	}
	const enqueueRenderTask = Reflect.get(workerPool, 'enqueueRenderTask');
	if (typeof enqueueRenderTask !== 'function') {
		return;
	}
	Reflect.set(
		workerPool,
		'enqueueRenderTask',
		(task: BridgePierreWorkerPoolQueuedTask, instance?: unknown): void => {
			Reflect.apply(enqueueRenderTask, workerPool, [task, instance]);
			const queuedTasks = Reflect.get(workerPool, 'queuedTasks');
			if (Array.isArray(queuedTasks)) {
				sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);
			}
		},
	);
	bridgePierreRankSchedulerInstalledManagers.add(workerPool);
}

export function BridgePierreWorkerPoolProvider(
	props: BridgePierreWorkerPoolProviderProps,
): ReactElement {
	const enabled = props.enabled ?? typeof Worker !== 'undefined';
	const ensureCodeViewThemeResolved =
		props.ensureCodeViewThemeResolved ?? ensureBridgeCodeViewThemeResolved;
	const [themeLoadState, setThemeLoadState] = useState<BridgeCodeViewThemeLoadState>({
		kind: 'loading',
	});
	const workerLoadState = useBridgePierreWorkerPoolLoadState({
		enabled,
		...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory }),
	});
	const workerFactory = workerLoadState.kind === 'ready' ? workerLoadState.workerFactory : null;
	const poolOptions = useMemo(() => {
		if (workerFactory === null) {
			return null;
		}

		return createBridgePierreWorkerPoolOptions({
			workerFactory,
			...(props.poolSize === undefined ? {} : { poolSize: props.poolSize }),
		});
	}, [props.poolSize, workerFactory]);
	const highlighterOptions = useMemo(() => createBridgePierreWorkerHighlighterOptions(), []);

	useEffect((): (() => void) | void => {
		let didCancel = false;
		setThemeLoadState({ kind: 'loading' });
		void ensureCodeViewThemeResolved()
			.then((): void => {
				if (!didCancel) {
					setThemeLoadState({ kind: 'ready' });
				}
			})
			.catch((error: unknown): void => {
				if (!didCancel) {
					setThemeLoadState({
						kind: 'failed',
						errorMessage: error instanceof Error ? error.message : String(error),
					});
				}
			});

		return (): void => {
			didCancel = true;
		};
	}, [ensureCodeViewThemeResolved]);

	useEffect((): (() => void) => {
		const rootElement = document.documentElement;
		rootElement.dataset['bridgePierreWorkerPoolState'] = workerLoadState.kind;
		return (): void => {
			if (rootElement.dataset['bridgePierreWorkerPoolState'] === workerLoadState.kind) {
				delete rootElement.dataset['bridgePierreWorkerPoolState'];
			}
		};
	}, [workerLoadState.kind]);

	useEffect((): (() => void) => {
		const rootElement = document.documentElement;
		rootElement.dataset['bridgePierreCodeViewThemeState'] = themeLoadState.kind;
		if (themeLoadState.kind === 'failed') {
			rootElement.dataset['bridgePierreCodeViewThemeError'] = themeLoadState.errorMessage;
		} else {
			delete rootElement.dataset['bridgePierreCodeViewThemeError'];
		}

		return (): void => {
			if (rootElement.dataset['bridgePierreCodeViewThemeState'] === themeLoadState.kind) {
				delete rootElement.dataset['bridgePierreCodeViewThemeState'];
				delete rootElement.dataset['bridgePierreCodeViewThemeError'];
			}
		};
	}, [themeLoadState]);

	if (themeLoadState.kind === 'failed') {
		return (
			<div
				className="flex h-full min-h-[240px] items-center justify-center bg-[var(--bridge-canvas-bg)] text-xs text-[var(--bridge-text-secondary)]"
				data-testid="bridge-pierre-worker-pool-failed"
				role="alert"
			>
				Code highlighting worker unavailable
			</div>
		);
	}

	if (themeLoadState.kind === 'loading' || workerLoadState.kind === 'loading') {
		return (
			<div
				className="flex h-full min-h-[240px] items-center justify-center bg-[var(--bridge-canvas-bg)] text-xs text-[var(--bridge-text-secondary)]"
				data-testid="bridge-pierre-worker-pool-loading"
				role="status"
			>
				Preparing code viewer
			</div>
		);
	}

	if (!enabled) {
		return <Fragment>{props.children}</Fragment>;
	}

	if (workerLoadState.kind === 'failed' || poolOptions === null) {
		return (
			<div
				className="flex h-full min-h-[240px] items-center justify-center bg-[var(--bridge-canvas-bg)] text-xs text-[var(--bridge-text-secondary)]"
				data-testid="bridge-pierre-worker-pool-failed"
				role="alert"
			>
				Code highlighting worker unavailable
			</div>
		);
	}

	return (
		<BridgePierreRankedWorkerPoolContextProvider
			highlighterOptions={highlighterOptions}
			poolOptions={poolOptions}
		>
			<BridgePierreWorkerPoolDiagnostics />
			<BridgePierreWorkerPoolReadinessGate>{props.children}</BridgePierreWorkerPoolReadinessGate>
		</BridgePierreRankedWorkerPoolContextProvider>
	);
}

function BridgePierreRankedWorkerPoolContextProvider(props: {
	readonly children: ReactNode;
	readonly highlighterOptions: WorkerInitializationRenderOptions;
	readonly poolOptions: WorkerPoolOptions;
}): ReactElement {
	const [workerPool] = useState((): WorkerPoolManager | undefined => {
		if (typeof window === 'undefined') {
			return undefined;
		}
		const manager = getOrCreateWorkerPoolSingleton({
			highlighterOptions: props.highlighterOptions,
			poolOptions: props.poolOptions,
		});
		installBridgePierreWorkerPoolRankScheduler(manager);
		return manager;
	});

	useEffect((): (() => void) | void => {
		if (workerPool === undefined) {
			return;
		}
		bridgePierreWorkerPoolProviderInstanceCount += 1;
		return (): void => {
			bridgePierreWorkerPoolProviderInstanceCount -= 1;
		};
	}, [workerPool]);

	useEffect((): (() => void) => {
		return (): void => {
			if (bridgePierreWorkerPoolProviderInstanceCount === 0) {
				terminateWorkerPoolSingleton();
			}
		};
	}, []);

	return (
		<WorkerPoolContext.Provider value={workerPool}>{props.children}</WorkerPoolContext.Provider>
	);
}

export function useBridgePierreWorkerStats(): BridgePierreWorkerStats | null {
	return useWorkerPool()?.getStats() ?? null;
}

function BridgePierreWorkerPoolDiagnostics(): null {
	const workerPool = useWorkerPool();
	const [workerStats, setWorkerStats] = useState<BridgePierreWorkerStats | null>(
		() => workerPool?.getStats() ?? null,
	);
	const [detailedInitializationProbe, setDetailedInitializationProbe] =
		useState<BridgePierreWorkerInitializationProbeSnapshot | null>(null);
	const didStartDetailedInitializationProbe = useRef(false);
	const initializationProbe = bridgePierreWorkerInitializationProbeForStats(
		workerStats,
		detailedInitializationProbe,
	);

	useEffect((): (() => void) | void => {
		if (workerPool === undefined) {
			setWorkerStats(null);
			return;
		}

		return subscribeToBridgePierreWorkerPoolStats(workerPool, setWorkerStats);
	}, [workerPool]);

	useEffect((): (() => void) | void => {
		if (
			workerStats === null ||
			workerStats.managerState !== 'initializing' ||
			workerStats.totalWorkers > 0 ||
			didStartDetailedInitializationProbe.current
		) {
			return;
		}

		let didCancel = false;
		didStartDetailedInitializationProbe.current = true;
		void runBridgePierreWorkerInitializationProbe({
			themeNames: [bridgePierreDarkThemeName],
			languages: [],
			timeoutMilliseconds: 250,
			onSnapshot: (snapshot): void => {
				if (!didCancel) {
					writeBridgePierreWorkerInitializationProbeSnapshotToDataset({
						rootElement: document.documentElement,
						snapshot,
					});
					setDetailedInitializationProbe(snapshot);
				}
			},
		});

		return (): void => {
			didCancel = true;
		};
	}, [workerStats]);

	useEffect((): (() => void) => {
		const rootElement = document.documentElement;
		if (workerStats === null) {
			delete rootElement.dataset['bridgePierreWorkerPoolManagerState'];
			delete rootElement.dataset['bridgePierreWorkerPoolWorkersFailed'];
			delete rootElement.dataset['bridgePierreWorkerPoolTotalWorkers'];
			delete rootElement.dataset['bridgePierreWorkerPoolBusyWorkers'];
			delete rootElement.dataset['bridgePierreWorkerPoolQueuedTasks'];
			delete rootElement.dataset['bridgePierreWorkerPoolActiveTasks'];
			delete rootElement.dataset['bridgePierreWorkerPoolFileCacheSize'];
			delete rootElement.dataset['bridgePierreWorkerPoolDiffCacheSize'];
			return (): void => {};
		}

		rootElement.dataset['bridgePierreWorkerPoolManagerState'] = workerStats.managerState;
		rootElement.dataset['bridgePierreWorkerPoolWorkersFailed'] = String(workerStats.workersFailed);
		rootElement.dataset['bridgePierreWorkerPoolTotalWorkers'] = String(workerStats.totalWorkers);
		rootElement.dataset['bridgePierreWorkerPoolBusyWorkers'] = String(workerStats.busyWorkers);
		rootElement.dataset['bridgePierreWorkerPoolQueuedTasks'] = String(workerStats.queuedTasks);
		rootElement.dataset['bridgePierreWorkerPoolActiveTasks'] = String(workerStats.activeTasks);
		rootElement.dataset['bridgePierreWorkerPoolFileCacheSize'] = String(workerStats.fileCacheSize);
		rootElement.dataset['bridgePierreWorkerPoolDiffCacheSize'] = String(workerStats.diffCacheSize);
		writeBridgePierreWorkerInitializationProbeSnapshotToDataset({
			rootElement,
			snapshot: initializationProbe,
		});
		return (): void => {
			delete rootElement.dataset['bridgePierreWorkerPoolManagerState'];
			delete rootElement.dataset['bridgePierreWorkerPoolWorkersFailed'];
			delete rootElement.dataset['bridgePierreWorkerPoolTotalWorkers'];
			delete rootElement.dataset['bridgePierreWorkerPoolBusyWorkers'];
			delete rootElement.dataset['bridgePierreWorkerPoolQueuedTasks'];
			delete rootElement.dataset['bridgePierreWorkerPoolActiveTasks'];
			delete rootElement.dataset['bridgePierreWorkerPoolFileCacheSize'];
			delete rootElement.dataset['bridgePierreWorkerPoolDiffCacheSize'];
			delete rootElement.dataset['bridgePierreWorkerPoolInitProbeStage'];
			delete rootElement.dataset['bridgePierreWorkerPoolInitProbeThemeCount'];
			delete rootElement.dataset['bridgePierreWorkerPoolInitProbeLanguageCount'];
			delete rootElement.dataset['bridgePierreWorkerPoolInitProbeFailureReason'];
		};
	}, [initializationProbe, workerStats]);

	return null;
}

function BridgePierreWorkerPoolReadinessGate(props: {
	readonly children: ReactNode;
}): ReactElement {
	const workerPool = useWorkerPool();
	const [readinessState, setReadinessState] = useState<BridgePierreWorkerPoolReadinessState>(
		(): BridgePierreWorkerPoolReadinessState =>
			bridgePierreWorkerPoolReadinessStateForStats(workerPool?.getStats() ?? null),
	);

	useEffect((): (() => void) | void => {
		if (workerPool === undefined) {
			setReadinessState({ kind: 'ready' });
			return;
		}

		return subscribeToBridgePierreWorkerPoolStats(workerPool, (stats): void => {
			setReadinessState(bridgePierreWorkerPoolReadinessStateForStats(stats));
		});
	}, [workerPool]);

	if (readinessState.kind === 'ready') {
		return <Fragment>{props.children}</Fragment>;
	}

	if (readinessState.kind === 'failed') {
		return (
			<div
				className="flex h-full min-h-[240px] items-center justify-center bg-[var(--bridge-canvas-bg)] text-xs text-[var(--bridge-text-secondary)]"
				data-testid="bridge-pierre-worker-pool-failed"
				role="alert"
			>
				Code highlighting worker unavailable
			</div>
		);
	}

	return (
		<Fragment>
			{props.children}
			<BridgePierreWorkerPoolLoadingStatus />
		</Fragment>
	);
}

function BridgePierreWorkerPoolLoadingStatus(): ReactElement {
	return (
		<div className="sr-only" data-testid="bridge-pierre-worker-pool-loading" role="status">
			Preparing code viewer
		</div>
	);
}

function bridgePierreWorkerPoolReadinessStateForStats(
	workerStats: BridgePierreWorkerStats | null,
): BridgePierreWorkerPoolReadinessState {
	if (workerStats === null || workerStats.managerState === 'initialized') {
		return { kind: 'ready' };
	}
	if (workerStats.workersFailed) {
		return { kind: 'failed' };
	}
	return { kind: 'loading' };
}

function bridgePierreWorkerInitializationProbeForStats(
	workerStats: BridgePierreWorkerStats | null,
	detailedInitializationProbe: BridgePierreWorkerInitializationProbeSnapshot | null,
): BridgePierreWorkerInitializationProbeSnapshot {
	if (workerStats === null) {
		return {
			stage: 'idle',
			themeCount: 0,
			languageCount: 0,
			failureReason: '',
		};
	}

	if (
		detailedInitializationProbe !== null &&
		workerStats.managerState === 'initializing' &&
		workerStats.totalWorkers === 0
	) {
		return detailedInitializationProbe;
	}

	if (workerStats.workersFailed) {
		return {
			stage: 'worker-manager-failed',
			themeCount: 0,
			languageCount: 0,
			failureReason: 'worker_pool_failed',
		};
	}

	if (workerStats.managerState === 'waiting') {
		return {
			stage: 'worker-manager-waiting',
			themeCount: 0,
			languageCount: 0,
			failureReason: '',
		};
	}

	if (workerStats.managerState === 'initialized') {
		return {
			stage: 'worker-manager-initialized',
			themeCount: 0,
			languageCount: 0,
			failureReason: '',
		};
	}

	return {
		stage: workerStats.totalWorkers > 0 ? 'workers-created' : 'worker-manager-initializing',
		themeCount: 0,
		languageCount: 0,
		failureReason: '',
	};
}

function subscribeToBridgePierreWorkerPoolStats(
	workerPool: NonNullable<ReturnType<typeof useWorkerPool>>,
	onStats: (stats: BridgePierreWorkerStats) => void,
): () => void {
	let intervalId: number | undefined;
	const stopPolling = (): void => {
		if (intervalId !== undefined) {
			window.clearInterval(intervalId);
			intervalId = undefined;
		}
	};
	const publishStats = (stats: BridgePierreWorkerStats): void => {
		onStats(stats);
		if (!bridgePierreWorkerPoolStatsNeedPolling(stats)) {
			stopPolling();
		}
	};
	const unsubscribe = workerPool.subscribeToStatChanges(publishStats);
	intervalId = window.setInterval((): void => {
		publishStats(workerPool.getStats());
	}, bridgePierreWorkerPoolStatsPollIntervalMilliseconds);
	publishStats(workerPool.getStats());

	return (): void => {
		stopPolling();
		unsubscribe();
	};
}

function bridgePierreWorkerPoolStatsNeedPolling(stats: BridgePierreWorkerStats): boolean {
	return stats.managerState !== 'initialized' && !stats.workersFailed;
}

function useBridgePierreWorkerPoolLoadState(props: {
	readonly enabled: boolean;
	readonly workerFactory?: () => Worker;
}): BridgePierreWorkerPoolLoadState {
	const [loadState, setLoadState] = useState<BridgePierreWorkerPoolLoadState>(() =>
		initialWorkerPoolLoadState(props),
	);

	useEffect((): (() => void) | void => {
		if (!props.enabled) {
			setLoadState({ kind: 'disabled' });
			return;
		}
		if (props.workerFactory !== undefined) {
			setLoadState({ kind: 'ready', workerFactory: props.workerFactory });
			return;
		}
		if (
			typeof Worker === 'undefined' ||
			typeof fetch === 'undefined' ||
			typeof URL.createObjectURL !== 'function'
		) {
			setLoadState({
				kind: 'failed',
				errorMessage: 'Worker runtime APIs are unavailable',
			});
			return;
		}

		let didCancel = false;
		let loadedFactory: BridgePierreBlobWorkerFactory | null = null;
		setLoadState({ kind: 'loading' });

		void fetch(defaultWorkerScriptUrl)
			.then(async (response: Response): Promise<string> => {
				if (!response.ok) {
					throw new Error(`Failed to load packaged worker: ${response.status}`);
				}
				return await response.text();
			})
			.then((workerSource: string): void => {
				if (didCancel) {
					return;
				}
				loadedFactory = createBridgePierreBlobWorkerFactory({ workerSource });
				setLoadState({
					kind: 'ready',
					workerFactory: loadedFactory.workerFactory,
				});
			})
			.catch((error: unknown): void => {
				if (didCancel) {
					return;
				}
				setLoadState({
					kind: 'failed',
					errorMessage: error instanceof Error ? error.message : String(error),
				});
			});

		return (): void => {
			didCancel = true;
			loadedFactory?.revoke();
		};
	}, [props.enabled, props.workerFactory]);

	return loadState;
}

function initialWorkerPoolLoadState(props: {
	readonly enabled: boolean;
	readonly workerFactory?: () => Worker;
}): BridgePierreWorkerPoolLoadState {
	if (!props.enabled) {
		return { kind: 'disabled' };
	}
	if (props.workerFactory !== undefined) {
		return { kind: 'ready', workerFactory: props.workerFactory };
	}
	return { kind: 'loading' };
}

function defaultCreateWorker(url: string | URL, options?: WorkerOptions): Worker {
	return new Worker(url, options);
}
