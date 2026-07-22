import { describe, expect, test } from 'vitest';

import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import { runBridgeFrameApplyPump } from './bridge-frame-apply-pump.js';

describe('Bridge frame apply pump', () => {
	test('selected unit receives the first slot while visible work makes bounded progress under selected churn', () => {
		const appliedUnits: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		let selectedBatchCount = 0;
		let visibleProgressCount = 0;

		runBridgeFrameApplyPump({
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			maxUnitsPerFrame: 1,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onCounters: (counters): void => {
				selectedBatchCount += counters.selectedApplyUnitCount;
				visibleProgressCount += counters.visibleApplyUnitCount;
			},
			onDrained: (): void => {
				appliedUnits.push('drained');
			},
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
			units: [
				{ id: 'selected-a', rank: 'selected', run: () => appliedUnits.push('selected-a') },
				{ id: 'visible-a', rank: 'visible', run: () => appliedUnits.push('visible-a') },
				{ id: 'selected-b', rank: 'selected', run: () => appliedUnits.push('selected-b') },
				{ id: 'selected-c', rank: 'selected', run: () => appliedUnits.push('selected-c') },
			],
		});

		expect(scheduledTurns).toHaveLength(1);
		for (let turnIndex = 0; turnIndex < 5; turnIndex += 1) {
			scheduledTurns.shift()?.();
		}

		expect(appliedUnits[0]).toBe('selected-a');
		expect(appliedUnits).toContain('visible-a');
		expect(appliedUnits.indexOf('visible-a')).toBeLessThanOrEqual(
			bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
		);
		expect(selectedBatchCount).toBeGreaterThan(0);
		expect(visibleProgressCount).toBeGreaterThan(0);
		expect(appliedUnits.at(-1)).toBe('drained');
	});

	test('drops stale pending apply units within the policy scan cap', () => {
		const appliedUnits: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		let staleScanCount = 0;
		let staleDropCount = 0;

		runBridgeFrameApplyPump({
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (unit): boolean => unit.id.startsWith('stale'),
			maxUnitsPerFrame: 8,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onCounters: (counters): void => {
				staleScanCount += counters.staleScanCount;
				staleDropCount += counters.staleDropCount;
			},
			onDrained: (): void => {
				appliedUnits.push('drained');
			},
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			staleScanLimit: 2,
			units: [
				{ id: 'stale-a', rank: 'selected', run: () => appliedUnits.push('stale-a') },
				{ id: 'stale-b', rank: 'visible', run: () => appliedUnits.push('stale-b') },
				{ id: 'fresh-a', rank: 'visible', run: () => appliedUnits.push('fresh-a') },
			],
		});

		scheduledTurns.shift()?.();
		scheduledTurns.shift()?.();

		expect(appliedUnits).toEqual(['fresh-a', 'drained']);
		expect(staleScanCount).toBe(2);
		expect(staleDropCount).toBe(2);
	});
});
