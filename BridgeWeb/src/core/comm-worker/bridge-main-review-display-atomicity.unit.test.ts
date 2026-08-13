import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';
import { BRIDGE_WORKER_WIRE_VERSION } from './bridge-worker-contracts.js';
import { bridgeWorkerReviewSourceContext } from './bridge-worker-review-display.test-support.js';

describe('Bridge main Review display atomicity', () => {
	test('notifies every listener only after source and comparison commit together', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		const reviewComparison = {
			activeTarget: { basis: 'commonCommit', kind: 'branch', name: 'origin/main' },
			attempt: { reviewGeneration: 1, status: 'settled' },
			displayedSnapshot: {
				packageId: 'package-1',
				reviewGeneration: 1,
				revision: 11,
				status: 'current',
			},
			repositoryDefaultTarget: null,
		} as const;
		const observedPairs: unknown[] = [];
		const observePair = (): void => {
			const snapshot = store.getSnapshot();
			observedPairs.push({
				packageId:
					snapshot.reviewSourceSlice?.status === 'ready'
						? snapshot.reviewSourceSlice.packageId
						: null,
				reviewComparison: snapshot.panelChromeSlice.reviewComparison,
			});
		};
		const unsubscribeRoot = store.subscribe(observePair);
		const unsubscribeSource = store.subscribeReviewSource(observePair);

		// Act
		store.applyReviewDisplayPatchEvent({
			direction: 'serverWorkerToMain',
			epoch: 2,
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						...bridgeWorkerReviewSourceContext('package-1'),
						metadataSourceId: 'source-1',
						metadataWindowIdentity: 'window-1',
						packageId: 'package-1',
						reviewGeneration: 1,
						revision: 11,
						status: 'ready',
						summary: null,
						totalItemCount: 0,
						totalTreeRowCount: 0,
					},
					slice: 'reviewSource',
				},
				{ operation: 'replace', payload: reviewComparison, slice: 'reviewComparison' },
			],
			projectionRevision: 1,
			sequence: 1,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		// Assert
		expect(observedPairs).toEqual([
			{ packageId: 'package-1', reviewComparison },
			{ packageId: 'package-1', reviewComparison },
		]);
		unsubscribeRoot();
		unsubscribeSource();
	});
});
