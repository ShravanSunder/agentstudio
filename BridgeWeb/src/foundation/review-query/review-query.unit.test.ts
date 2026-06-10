import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../review-package/bridge-review-package-test-support.js';
import { isEndpointComparisonQuery } from './bridge-review-query.js';
import type { BridgeReviewQuery } from './bridge-review-query.js';

describe('bridge review query', () => {
	test('identifies endpoint comparison queries', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const query = {
			queryId: 'query',
			queryKind: 'compare',
			repoId: 'repo',
			worktreeId: 'worktree',
			baseEndpointId: reviewPackage.baseEndpoint.endpointId,
			headEndpointId: reviewPackage.headEndpoint.endpointId,
			comparisonSemantics: 'workingTreeDelta',
			pathScope: [],
			fileTarget: null,
			viewFilter: reviewPackage.filterState,
			grouping: { kind: 'flat', label: null },
			provenanceFilter: {
				paneIds: [],
				agentSessionIds: [],
				promptIds: [],
				operationIds: [],
				createdAfterUnixMilliseconds: null,
				createdBeforeUnixMilliseconds: null,
				sourceKinds: [],
			},
		} satisfies BridgeReviewQuery;

		expect(isEndpointComparisonQuery(query)).toBe(true);
	});
});
