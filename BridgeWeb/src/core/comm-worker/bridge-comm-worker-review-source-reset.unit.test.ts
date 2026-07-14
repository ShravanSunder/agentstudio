import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-command-handler.js';
import { enqueueBridgeCommWorkerReviewSourceReset } from './bridge-comm-worker-review-source-reset.js';
import { makeWorkerReviewContentMetadata } from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker Review source reset', () => {
	test('rebases a chunked reset onto a newer same-epoch metadata delta', async () => {
		// Arrange
		const rows = Array.from({ length: 130 }, (_unused, index) => ({
			id: `item-${index + 1}`,
			index,
			parentId: null,
		}));
		let runtimeSource: {
			contentItems: BridgeCommWorkerReviewRuntimeSource['contentItems'][number][];
			contentRequestDescriptors: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number][];
			renderSemantics: BridgeCommWorkerReviewRuntimeSource['renderSemantics'][number][];
			rows: BridgeCommWorkerReviewRuntimeSource['rows'][number][];
		} = {
			contentItems: rows.map((row) => makeWorkerReviewContentMetadata({ itemId: row.id })),
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [...rows],
		};
		const store = createBridgeCommWorkerStore({ contentItems: [], rows: [] });
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: (): number => 0 });
		const ticket = enqueueBridgeCommWorkerReviewSourceReset({
			createSequence: (): number => 1,
			isCurrentResetEpoch: (): boolean => true,
			onResetComplete: (): void => {},
			pump,
			request: {
				affectedItemIds: rows.map((row) => row.id),
				cause: 'reviewMetadata',
				epoch: 1,
				readReviewRuntimeSource: (): BridgeCommWorkerReviewRuntimeSource => runtimeSource,
				store,
			},
			requestPreparationDrain: (): void => {},
			scheduleDemandExecution: (): boolean => false,
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
		});
		pump.runUntilBudget();
		const addedRow = { id: 'item-131', index: 130, parentId: null } as const;
		const addedContent = makeWorkerReviewContentMetadata({ itemId: addedRow.id });
		runtimeSource = {
			...runtimeSource,
			contentItems: [...runtimeSource.contentItems, addedContent],
			rows: [...runtimeSource.rows, addedRow],
		};
		store.actions.applyReviewSourceUpdateFact({
			contentItems: [addedContent],
			epoch: 1,
			resetComplete: false,
			rows: [addedRow],
		});

		// Act
		await waitForReviewResetContinuation();
		pump.runUntilBudget();
		await waitForReviewResetContinuation();
		pump.runUntilBudget();
		await ticket.completion;

		// Assert
		expect(store.getState().rowById.has(addedRow.id)).toBe(true);
		expect(store.getState().contentMetadataByItemId.has(addedRow.id)).toBe(true);
	});
});

async function waitForReviewResetContinuation(): Promise<void> {
	await new Promise<void>((resolve) => {
		setTimeout(resolve, 0);
	});
}
