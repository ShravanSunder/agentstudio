export type BridgeFrameApplyUnitRank =
	| 'selected'
	| 'visible'
	| 'nearby'
	| 'speculative'
	| 'background';

export interface BridgeFrameApplyUnit {
	readonly id: string;
	readonly rank: BridgeFrameApplyUnitRank;
	readonly run: () => void;
}

export interface BridgeFrameApplyPumpCounters {
	readonly appliedUnitCount: number;
	readonly selectedApplyUnitCount: number;
	readonly staleDropCount: number;
	readonly staleScanCount: number;
	readonly visibleApplyUnitCount: number;
}

export interface RunBridgeFrameApplyPumpProps<TUnit extends BridgeFrameApplyUnit> {
	readonly frameBudgetMilliseconds: number;
	readonly isStale: (unit: TUnit) => boolean;
	readonly maxUnitsPerFrame: number;
	readonly noStarvationSelectedBatchLimit: number;
	readonly now: () => number;
	readonly onCounters?: (counters: BridgeFrameApplyPumpCounters) => void;
	readonly onDrained: () => void;
	readonly scheduleNextTurn: (callback: () => void) => void;
	readonly staleScanLimit: number;
	readonly units: readonly TUnit[];
}

const bridgeFrameApplyRankOrder: Readonly<Record<BridgeFrameApplyUnitRank, number>> = {
	selected: 0,
	visible: 1,
	nearby: 2,
	speculative: 3,
	background: 4,
};

export function runBridgeFrameApplyPump<TUnit extends BridgeFrameApplyUnit>(
	props: RunBridgeFrameApplyPumpProps<TUnit>,
): void {
	const pendingUnits = [...props.units].toSorted(
		(left, right): number =>
			bridgeFrameApplyRankOrder[left.rank] - bridgeFrameApplyRankOrder[right.rank],
	);
	let selectedBatchesSinceVisibleProgress = 0;

	const runFrame = (): void => {
		const counters = bridgeFrameApplyPumpCounters();
		dropStaleUnits({
			counters,
			isStale: props.isStale,
			pendingUnits,
			scanLimit: props.staleScanLimit,
		});

		const frameStartedAtMilliseconds = props.now();
		let unitsAppliedThisFrame = 0;
		while (pendingUnits.length > 0 && unitsAppliedThisFrame < props.maxUnitsPerFrame) {
			const unitIndex = nextApplyUnitIndex({
				noStarvationSelectedBatchLimit: props.noStarvationSelectedBatchLimit,
				pendingUnits,
				selectedBatchesSinceVisibleProgress,
			});
			const [unit] = pendingUnits.splice(unitIndex, 1);
			if (unit === undefined) {
				continue;
			}
			if (props.isStale(unit)) {
				counters.staleDropCount += 1;
				counters.staleScanCount += 1;
				continue;
			}
			unit.run();
			unitsAppliedThisFrame += 1;
			recordAppliedUnit({ counters, unit });
			if (unit.rank === 'visible') {
				selectedBatchesSinceVisibleProgress = 0;
			} else if (unit.rank === 'selected') {
				selectedBatchesSinceVisibleProgress += 1;
			}
			if (
				pendingUnits.length > 0 &&
				props.now() - frameStartedAtMilliseconds >= props.frameBudgetMilliseconds
			) {
				props.onCounters?.(counters);
				props.scheduleNextTurn(runFrame);
				return;
			}
		}

		props.onCounters?.(counters);
		if (pendingUnits.length === 0) {
			props.onDrained();
			return;
		}
		props.scheduleNextTurn(runFrame);
	};

	props.scheduleNextTurn(runFrame);
}

function bridgeFrameApplyPumpCounters(): {
	appliedUnitCount: number;
	selectedApplyUnitCount: number;
	staleDropCount: number;
	staleScanCount: number;
	visibleApplyUnitCount: number;
} {
	return {
		appliedUnitCount: 0,
		selectedApplyUnitCount: 0,
		staleDropCount: 0,
		staleScanCount: 0,
		visibleApplyUnitCount: 0,
	};
}

function dropStaleUnits<TUnit extends BridgeFrameApplyUnit>(props: {
	readonly counters: {
		staleDropCount: number;
		staleScanCount: number;
	};
	readonly isStale: (unit: TUnit) => boolean;
	readonly pendingUnits: TUnit[];
	readonly scanLimit: number;
}): void {
	let scanCount = 0;
	for (let index = 0; index < props.pendingUnits.length && scanCount < props.scanLimit; ) {
		scanCount += 1;
		props.counters.staleScanCount += 1;
		const unit = props.pendingUnits[index];
		if (unit !== undefined && props.isStale(unit)) {
			props.pendingUnits.splice(index, 1);
			props.counters.staleDropCount += 1;
			continue;
		}
		index += 1;
	}
}

function nextApplyUnitIndex(props: {
	readonly noStarvationSelectedBatchLimit: number;
	readonly pendingUnits: readonly BridgeFrameApplyUnit[];
	readonly selectedBatchesSinceVisibleProgress: number;
}): number {
	const selectedIndex = props.pendingUnits.findIndex((unit): boolean => unit.rank === 'selected');
	const visibleIndex = props.pendingUnits.findIndex((unit): boolean => unit.rank === 'visible');
	if (
		visibleIndex >= 0 &&
		props.selectedBatchesSinceVisibleProgress >= props.noStarvationSelectedBatchLimit
	) {
		return visibleIndex;
	}
	if (selectedIndex >= 0) {
		return selectedIndex;
	}
	return 0;
}

function recordAppliedUnit(props: {
	readonly counters: {
		appliedUnitCount: number;
		selectedApplyUnitCount: number;
		visibleApplyUnitCount: number;
	};
	readonly unit: BridgeFrameApplyUnit;
}): void {
	props.counters.appliedUnitCount += 1;
	if (props.unit.rank === 'selected') {
		props.counters.selectedApplyUnitCount += 1;
	}
	if (props.unit.rank === 'visible') {
		props.counters.visibleApplyUnitCount += 1;
	}
}
