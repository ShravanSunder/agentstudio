import { describe, expect, test } from 'vitest';

import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import {
	bridgeProductCallRequestSchema,
	bridgeProductCallResultSchema,
	bridgeProductFileSourceCurrentRequestSchema,
	bridgeProductFileSourceCurrentResultSchema,
	bridgeProductReviewIntakeReadyRequestSchema,
} from './bridge-product-call-contracts.js';

const currentFileSource = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: '00000000-0000-4000-8000-000000000001',
	rootPathToken: 'root-token-1',
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge product call contracts', () => {
	test('defines a strict closed File source discovery call', () => {
		const request = { method: 'file.source.current', request: {} } as const;
		const availableResult = {
			method: 'file.source.current',
			result: { source: currentFileSource, status: 'available' },
		} as const;
		const unavailableResult = {
			method: 'file.source.current',
			result: { reason: 'no-file-source-authority', status: 'unavailable' },
		} as const;

		expect(bridgeProductFileSourceCurrentRequestSchema.parse(request.request)).toEqual({});
		expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
		expect(bridgeProductFileSourceCurrentResultSchema.parse(availableResult.result)).toEqual(
			availableResult.result,
		);
		expect(bridgeProductFileSourceCurrentResultSchema.parse(unavailableResult.result)).toEqual(
			unavailableResult.result,
		);
		expect(bridgeProductCallResultSchema.parse(availableResult)).toEqual(availableResult);
		expect(bridgeProductCallResultSchema.parse(unavailableResult)).toEqual(unavailableResult);

		for (const invalidRequest of [{ extra: true }, { source: currentFileSource }, null]) {
			expect(bridgeProductFileSourceCurrentRequestSchema.safeParse(invalidRequest).success).toBe(
				false,
			);
		}
		for (const invalidResult of [
			{ status: 'available' },
			{ source: { ...currentFileSource, freshness: 'cached' }, status: 'available' },
			{ reason: 'temporarily-unavailable', status: 'unavailable' },
			{ reason: 'no-file-source-authority', source: currentFileSource, status: 'unavailable' },
		]) {
			expect(bridgeProductFileSourceCurrentResultSchema.safeParse(invalidResult).success).toBe(
				false,
			);
		}
	});

	test('parses the shared File source discovery corpus through the closed call schemas', () => {
		for (const testCase of validProductSessionCorpus.fileSourceCurrentCases) {
			expect(bridgeProductCallRequestSchema.parse(testCase.request)).toEqual(testCase.request);
			expect(bridgeProductCallResultSchema.parse(testCase.result)).toEqual(testCase.result);
		}
	});

	test('defines strict Review intake readiness request and null result contracts', () => {
		const request = {
			method: 'review.intake.ready',
			request: { reason: 'sequence_gap', streamId: 'review:stream-1' },
		} as const;
		const nullRequest = {
			method: 'review.intake.ready',
			request: { reason: null, streamId: null },
		} as const;
		const result = { method: 'review.intake.ready', result: null } as const;

		expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
		expect(bridgeProductCallRequestSchema.parse(nullRequest)).toEqual(nullRequest);
		expect(bridgeProductCallResultSchema.parse(result)).toEqual(result);
		for (const invalidRequest of [
			{ reason: null },
			{ streamId: null },
			{ extra: true, reason: null, streamId: null },
			{ reason: '', streamId: null },
			{ reason: 'contains spaces', streamId: null },
			{ reason: null, streamId: '' },
			{ reason: null, streamId: 'contains spaces' },
		]) {
			expect(bridgeProductReviewIntakeReadyRequestSchema.safeParse(invalidRequest).success).toBe(
				false,
			);
		}
		expect(
			bridgeProductCallResultSchema.safeParse({
				method: 'review.intake.ready',
				result: {},
			}).success,
		).toBe(false);
	});
});
