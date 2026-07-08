import { describe, expect, test } from 'vitest';

import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentDemandRole } from '../../core/models/bridge-demand-models.js';
import { runBridgeCodeViewMaterializationInChunks } from './bridge-code-view-panel-support.js';

interface SelectedApplyPumpTestEntry {
	readonly id: string;
	readonly rank: BridgeContentDemandRole;
}

describe('Bridge CodeView selected apply pump', () => {
	test('selected apply unit runs in turn one before visible work', () => {
		const appliedEntries: string[] = [];
		const scheduledTurns: Array<() => void> = [];

		runBridgeCodeViewMaterializationInChunks({
			entries: [
				{ id: 'visible-neighbor', rank: 'visible' },
				{ id: 'selected-large-file', rank: 'selected' },
			],
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			maxUnitsPerFrame: 1,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {
				appliedEntries.push('drained');
			},
			rankForEntry: (entry: SelectedApplyPumpTestEntry): SelectedApplyPumpTestEntry['rank'] =>
				entry.rank,
			runEntry: (entry: SelectedApplyPumpTestEntry): void => {
				if (entry.id === 'visible-neighbor') {
					appliedEntries.push('visible-neighbor');
					return;
				}
				appliedEntries.push('selected-large-file');
			},
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
		});

		expect(appliedEntries).toEqual([]);
		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(appliedEntries).toEqual(['selected-large-file']);
		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(appliedEntries).toEqual(['selected-large-file', 'visible-neighbor', 'drained']);
	});

	test('policy apply cap carries nearby speculative and background work across turns in rank order', () => {
		const appliedEntries: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		const rankedEntries: readonly SelectedApplyPumpTestEntry[] = [
			{ id: 'background-a', rank: 'background' },
			{ id: 'speculative-a', rank: 'speculative' },
			{ id: 'nearby-a', rank: 'nearby' },
			{ id: 'visible-a', rank: 'visible' },
			{ id: 'selected-a', rank: 'selected' },
		];
		const entries: readonly SelectedApplyPumpTestEntry[] = [
			...rankedEntries,
			...Array.from(
				{
					length: Math.max(
						0,
						bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame + 1 - rankedEntries.length,
					),
				},
				(_, entryIndex): SelectedApplyPumpTestEntry => ({
					id: `background-extra-${entryIndex + 1}`,
					rank: 'background',
				}),
			),
		];
		const expectedApplyOrder = [
			'selected-a',
			'visible-a',
			'nearby-a',
			'speculative-a',
			'background-a',
			...entries
				.filter((entry): boolean => entry.id.startsWith('background-extra-'))
				.map((entry): string => entry.id),
		];

		runBridgeCodeViewMaterializationInChunks({
			entries,
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {
				appliedEntries.push('drained');
			},
			rankForEntry: (entry): BridgeContentDemandRole => entry.rank,
			runEntry: (entry): void => {
				appliedEntries.push(entry.id);
			},
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
		});

		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(appliedEntries).toEqual(
			expectedApplyOrder.slice(0, bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame),
		);

		scheduledTurns.shift()?.();
		expect(appliedEntries).toEqual([...expectedApplyOrder, 'drained']);
	});
});
