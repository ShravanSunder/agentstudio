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
}

export interface BridgeWorkerContentPreparationWork {
	readonly id: string;
	readonly rank: BridgeWorkerContentPreparationRank;
	readonly runSlice: (
		context: BridgeWorkerContentPreparationContext,
	) => BridgeWorkerContentPreparationResult;
}

export interface CreateWorkerContentPreparationPumpProps {
	readonly maxSliceMs: number;
	readonly now?: () => number;
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

	return {
		enqueue: (work: BridgeWorkerContentPreparationWork): void => {
			enqueueOrPromoteBridgeWorkerPreparationWork(pendingWorkById, work);
		},
		enqueueOrPromote: (work: BridgeWorkerContentPreparationWork): void => {
			enqueueOrPromoteBridgeWorkerPreparationWork(pendingWorkById, work);
		},
		cancel: (workId: string): void => {
			pendingWorkById.delete(workId);
		},
		runUntilBudget: (): WorkerContentPreparationPumpRunResult => {
			const startedAtMs = now();
			const completedIds: string[] = [];
			while (pendingWorkById.size > 0) {
				const elapsedMs = now() - startedAtMs;
				const work = takeHighestRankedWork(pendingWorkById);
				const result = work.runSlice({
					elapsedMs,
					remainingBudgetMs: Math.max(0, props.maxSliceMs - elapsedMs),
				});
				if (result.complete) {
					completedIds.push(work.id);
				} else {
					enqueueOrPromoteBridgeWorkerPreparationWork(pendingWorkById, work);
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

function enqueueOrPromoteBridgeWorkerPreparationWork(
	pendingWorkById: Map<string, BridgeWorkerContentPreparationWork>,
	work: BridgeWorkerContentPreparationWork,
): void {
	const existingWork = pendingWorkById.get(work.id);
	if (existingWork === undefined) {
		pendingWorkById.set(work.id, work);
		return;
	}
	const promotedRank = chooseHigherPriorityBridgeWorkerPreparationRank(
		existingWork.rank,
		work.rank,
	);
	pendingWorkById.set(work.id, {
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

function takeHighestRankedWork(
	pendingWorkById: Map<string, BridgeWorkerContentPreparationWork>,
): BridgeWorkerContentPreparationWork {
	let bestId: string | null = null;
	let bestRank = Number.POSITIVE_INFINITY;
	for (const [workId, work] of pendingWorkById.entries()) {
		const rank = BRIDGE_WORKER_CONTENT_PREPARATION_RANK_ORDER[work.rank];
		if (rank < bestRank) {
			bestId = workId;
			bestRank = rank;
		}
	}
	if (bestId === null) {
		throw new Error('Bridge worker content preparation queue is empty.');
	}
	const work = pendingWorkById.get(bestId);
	pendingWorkById.delete(bestId);
	if (work === undefined) {
		throw new Error('Bridge worker content preparation queue lost its selected work item.');
	}
	return work;
}
