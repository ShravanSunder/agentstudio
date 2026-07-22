import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatchEvent,
} from '../core/comm-worker/bridge-worker-contracts.js';

export function hierarchicalReviewDisplayEvent(): BridgeWorkerReviewDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: 'review-window-hierarchical',
					reviewGeneration: 1,
					status: 'ready',
					summary: {
						additions: 1,
						deletions: 0,
						filesChanged: 1,
						hiddenFileCount: 0,
						visibleFileCount: 1,
					},
					totalItemCount: 1,
					totalTreeRowCount: 2,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: [reviewDisplayItem('item-1', 'Sources/First.swift')],
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: true,
					windows: [
						{
							rows: [
								{
									depth: 0,
									isDirectory: true,
									itemId: null,
									path: 'Sources',
									rowId: 'row-sources',
								},
								{
									depth: 1,
									isDirectory: false,
									itemId: 'item-1',
									path: 'Sources/First.swift',
									rowId: 'row-item-1',
								},
							],
							startIndex: 0,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function reviewDisplayItem(itemId: string, path: string): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			basePath: path,
			changeKind: 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			extension: 'swift',
			fileClass: 'source',
			headPath: path,
			isHiddenByDefault: false,
			itemId,
			language: 'swift',
			mimeTypes: ['text/plain'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: `review-window-${itemId}`,
	};
}
