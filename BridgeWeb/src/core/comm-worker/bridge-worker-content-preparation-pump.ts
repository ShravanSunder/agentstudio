import {
	recordBridgeCommWorkerTaskTelemetry,
	type BridgeCommWorkerTelemetryRecorder,
} from './bridge-comm-worker-telemetry.js';

export type BridgeWorkerContentPreparationRank =
	| 'selected'
	| 'visible'
	| 'nearby'
	| 'speculative'
	| 'background';

export interface BridgeWorkerContentPreparationContext {
	readonly elapsedMs: number;
	readonly remainingBudgetMs: number;
}

export interface BridgeWorkerContentPreparationResult {
	readonly complete: boolean;
	readonly continuation?: 'pump' | 'external';
}

export interface BridgeWorkerContentPreparationTelemetry {
	readonly payloadClass?: string;
	readonly sourceEpoch?: number;
	readonly workKind: string;
}

export interface BridgeWorkerContentPreparationWork {
	readonly id: string;
	readonly rank: BridgeWorkerContentPreparationRank;
	readonly telemetry?: BridgeWorkerContentPreparationTelemetry;
	readonly runSlice: (
		context: BridgeWorkerContentPreparationContext,
	) => BridgeWorkerContentPreparationResult;
}

export interface CreateWorkerContentPreparationPumpProps {
	readonly maxSliceMs: number;
	readonly now?: () => number;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export interface WorkerContentPreparationPumpRunResult {
	readonly completedIds: readonly string[];
	readonly yielded: boolean;
}

export interface WorkerContentPreparationPump {
	readonly enqueue: (work: BridgeWorkerContentPreparationWork) => void;
	readonly enqueueOrPromote: (work: BridgeWorkerContentPreparationWork) => void;
	readonly cancel: (workId: string) => void;
	readonly runUntilBudget: () => WorkerContentPreparationPumpRunResult;
	readonly getPendingWorkIds: () => readonly string[];
}

const BRIDGE_WORKER_CONTENT_PREPARATION_RANK_ORDER: Readonly<
	Record<BridgeWorkerContentPreparationRank, number>
> = {
	selected: 0,
	visible: 1,
	nearby: 2,
	speculative: 3,
	background: 4,
};

export function createWorkerContentPreparationPump(
	props: CreateWorkerContentPreparationPumpProps,
): WorkerContentPreparationPump {
	const now = props.now ?? performance.now.bind(performance);
	const pendingWorkById = new Map<string, BridgeWorkerContentPreparationWork>();
	const enqueuedAtMillisecondsByWorkId = new Map<string, number>();

	return {
		enqueue: (work: BridgeWorkerContentPreparationWork): void => {
			enqueueOrPromoteBridgeWorkerPreparationWork({
				enqueuedAtMillisecondsByWorkId,
				now,
				pendingWorkById,
				work,
			});
		},
		enqueueOrPromote: (work: BridgeWorkerContentPreparationWork): void => {
			enqueueOrPromoteBridgeWorkerPreparationWork({
				enqueuedAtMillisecondsByWorkId,
				now,
				pendingWorkById,
				work,
			});
		},
		cancel: (workId: string): void => {
			pendingWorkById.delete(workId);
			enqueuedAtMillisecondsByWorkId.delete(workId);
		},
		runUntilBudget: (): WorkerContentPreparationPumpRunResult => {
			const startedAtMs = now();
			const completedIds: string[] = [];
			while (pendingWorkById.size > 0) {
				const elapsedMs = now() - startedAtMs;
				const work = takeHighestRankedWork({
					enqueuedAtMillisecondsByWorkId,
					pendingWorkById,
				});
				const sliceStartedAtMilliseconds = now();
				const queueWaitMilliseconds =
					sliceStartedAtMilliseconds -
					(enqueuedAtMillisecondsByWorkId.get(work.id) ?? sliceStartedAtMilliseconds);
				enqueuedAtMillisecondsByWorkId.delete(work.id);
				const result = work.runSlice({
					elapsedMs,
					remainingBudgetMs: Math.max(0, props.maxSliceMs - elapsedMs),
				});
				const sliceDurationMilliseconds = now() - sliceStartedAtMilliseconds;
				recordBridgeCommWorkerTaskTelemetry({
					durationMilliseconds: sliceDurationMilliseconds,
					lane: work.rank,
					queueWaitMilliseconds,
					taskKind: 'content_preparation',
					...(work.telemetry?.payloadClass === undefined
						? {}
						: { payloadClass: work.telemetry.payloadClass }),
					...(work.telemetry?.sourceEpoch === undefined
						? {}
						: { sourceEpoch: work.telemetry.sourceEpoch }),
					...(props.telemetryClient === undefined
						? {}
						: { telemetryClient: props.telemetryClient }),
					...(work.telemetry?.workKind === undefined ? {} : { workKind: work.telemetry.workKind }),
				});
				if (result.complete) {
					completedIds.push(work.id);
				} else if (result.continuation !== 'external') {
					enqueueOrPromoteBridgeWorkerPreparationWork({
						enqueuedAtMillisecondsByWorkId,
						now,
						pendingWorkById,
						work,
					});
				}
				if (pendingWorkById.size > 0 && now() - startedAtMs >= props.maxSliceMs) {
					return {
						completedIds,
						yielded: true,
					};
				}
			}
			return {
				completedIds,
				yielded: false,
			};
		},
		getPendingWorkIds: (): readonly string[] => [...pendingWorkById.keys()],
	};
}

function enqueueOrPromoteBridgeWorkerPreparationWork(props: {
	readonly enqueuedAtMillisecondsByWorkId: Map<string, number>;
	readonly now: () => number;
	readonly pendingWorkById: Map<string, BridgeWorkerContentPreparationWork>;
	readonly work: BridgeWorkerContentPreparationWork;
}): void {
	const existingWork = props.pendingWorkById.get(props.work.id);
	if (existingWork === undefined) {
		props.enqueuedAtMillisecondsByWorkId.set(props.work.id, props.now());
		props.pendingWorkById.set(props.work.id, props.work);
		return;
	}
	const promotedRank = chooseHigherPriorityBridgeWorkerPreparationRank(
		existingWork.rank,
		props.work.rank,
	);
	if (promotedRank !== existingWork.rank) {
		props.enqueuedAtMillisecondsByWorkId.set(props.work.id, props.now());
	}
	props.pendingWorkById.set(props.work.id, {
		...existingWork,
		rank: promotedRank,
	});
}

function chooseHigherPriorityBridgeWorkerPreparationRank(
	leftRank: BridgeWorkerContentPreparationRank,
	rightRank: BridgeWorkerContentPreparationRank,
): BridgeWorkerContentPreparationRank {
	return BRIDGE_WORKER_CONTENT_PREPARATION_RANK_ORDER[leftRank] <=
		BRIDGE_WORKER_CONTENT_PREPARATION_RANK_ORDER[rightRank]
		? leftRank
		: rightRank;
}

function takeHighestRankedWork(props: {
	readonly enqueuedAtMillisecondsByWorkId: Map<string, number>;
	readonly pendingWorkById: Map<string, BridgeWorkerContentPreparationWork>;
}): BridgeWorkerContentPreparationWork {
	let bestId: string | null = null;
	let bestRank = Number.POSITIVE_INFINITY;
	for (const [workId, work] of props.pendingWorkById.entries()) {
		const rank = BRIDGE_WORKER_CONTENT_PREPARATION_RANK_ORDER[work.rank];
		if (rank < bestRank) {
			bestId = workId;
			bestRank = rank;
		}
	}
	if (bestId === null) {
		throw new Error('Bridge worker content preparation queue is empty.');
	}
	const work = props.pendingWorkById.get(bestId);
	props.pendingWorkById.delete(bestId);
	if (work === undefined) {
		throw new Error('Bridge worker content preparation queue lost its selected work item.');
	}
	return work;
}
