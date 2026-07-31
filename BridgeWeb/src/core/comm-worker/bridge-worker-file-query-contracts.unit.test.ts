import { describe, expect, test } from 'vitest';

import {
	bridgeWorkerFileQuerySchema,
	type BridgeWorkerFileQuery,
} from './bridge-worker-file-query-contracts.js';

describe('Bridge worker File query contracts', () => {
	test('accepts the closed query vocabulary and rejects unknown members', () => {
		const query = {
			filterMode: 'source',
			searchMode: 'regex',
			searchText: 'src/.+\\.ts$',
		} satisfies BridgeWorkerFileQuery;

		expect(bridgeWorkerFileQuerySchema.parse(query)).toEqual(query);
		for (const removedOrUnreachableFilter of ['fetchable', 'unavailable', 'binary', 'modified']) {
			expect(
				bridgeWorkerFileQuerySchema.safeParse({
					...query,
					filterMode: removedOrUnreachableFilter,
				}).success,
			).toBe(false);
		}
		expect(bridgeWorkerFileQuerySchema.safeParse({ ...query, cacheResult: true }).success).toBe(
			false,
		);
	});
});
