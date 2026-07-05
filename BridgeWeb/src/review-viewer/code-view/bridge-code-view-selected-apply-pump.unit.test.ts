import { describe, expect, test } from 'vitest';

import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentDemandRole } from '../../core/models/bridge-demand-models.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	materializeBridgeCodeViewItem,
	selectedBridgeCodeViewContentWindowLineCount,
} from './bridge-code-view-materialization.js';
import { runBridgeCodeViewMaterializationInChunks } from './bridge-code-view-panel-support.js';

interface SelectedApplyPumpTestEntry {
	readonly id: string;
	readonly rank: BridgeContentDemandRole;
}

describe('Bridge CodeView selected apply pump', () => {
	test('large selected file paints the first visible window in turn one before later apply turns', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected source fixture item');
		}
		const headHandle = item.contentRoles.head;
		if (headHandle === null || headHandle === undefined) {
			throw new Error('expected head content handle');
		}
		const lineCount = selectedBridgeCodeViewContentWindowLineCount * 3;
		const body = Array.from(
			{ length: lineCount },
			(_, lineIndex): string => `line ${lineIndex}\n`,
		).join('');
		const resource: BridgeContentResource = {
			authoritative: true,
			byteLength: body.length,
			handle: {
				...makeBridgeContentHandle('source-high', 'head'),
				...headHandle,
				sizeBytes: body.length,
			},
			readText: (): string => body,
		};
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
				const firstWindow = materializeBridgeCodeViewItem({
					contentDemandRole: 'selected',
					contentWindowLineLimit:
						bridgeContentDemandExecutionPolicy.selectedApplyInitialWindowLineCount,
					item: {
						...item,
						contentLineCountsByRole: { head: lineCount },
					},
					presentation: { kind: 'file', version: 'head' },
					resources: { head: resource },
				});

				if (firstWindow?.type !== 'file') {
					throw new Error('expected first selected window file item');
				}
				expect(firstWindow.bridgeMetadata.contentState).toBe('windowed');
				expect(firstWindow.file.contents.split('\n').length - 1).toBe(
					bridgeContentDemandExecutionPolicy.selectedApplyInitialWindowLineCount,
				);
				expect(firstWindow.file.contents).toContain('line 0\n');
				expect(firstWindow.file.contents).not.toContain(`line ${lineCount - 1}\n`);
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
