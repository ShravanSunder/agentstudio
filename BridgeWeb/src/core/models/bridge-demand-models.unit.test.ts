import { describe, expect, test } from 'vitest';

import { bridgeContentDemandRoleSchema, bridgeDemandLaneSchema } from './bridge-demand-models.js';

describe('bridge demand product vocabulary', () => {
	test('accepts the closed worker lane and content-role vocabularies', () => {
		expect(bridgeDemandLaneSchema.options).toEqual([
			'foreground',
			'active',
			'visible',
			'nearby',
			'speculative',
			'idle',
		]);
		expect(bridgeContentDemandRoleSchema.options).toEqual([
			'selected',
			'visible',
			'nearby',
			'speculative',
			'background',
		]);
	});

	test('rejects descriptor-era and unknown scheduling values', () => {
		expect(bridgeDemandLaneSchema.safeParse('selected').success).toBe(false);
		expect(bridgeDemandLaneSchema.safeParse('resource').success).toBe(false);
		expect(bridgeContentDemandRoleSchema.safeParse('foreground').success).toBe(false);
	});
});
