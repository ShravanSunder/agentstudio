import { describe, expect, test } from 'vitest';

import { bridgeIntakeFrameSchema } from './bridge-intake-frame.js';

describe('bridge intake frame schema', () => {
	test('parses data and lifecycle frames', () => {
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'snapshot',
				streamId: 'stream-1',
				generation: 1,
				sequence: 0,
				payload: { ready: true },
			}).success,
		).toBe(true);
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'reset',
				streamId: 'stream-1',
				generation: 2,
				sequence: 0,
			}).success,
		).toBe(true);
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'close',
				streamId: 'stream-1',
				generation: 2,
				sequence: 1,
			}).success,
		).toBe(true);
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'error',
				streamId: 'stream-1',
				generation: 2,
				sequence: 2,
				message: 'backend stream failed',
			}).success,
		).toBe(true);
	});

	test('rejects malformed identity and unknown frame kinds', () => {
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'snapshot',
				streamId: '',
				generation: 1,
				sequence: 0,
				payload: {},
			}).success,
		).toBe(false);
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'comment',
				streamId: 'stream-1',
				generation: 1,
				sequence: 0,
				payload: {},
			}).success,
		).toBe(false);
		expect(
			bridgeIntakeFrameSchema.safeParse({
				kind: 'error',
				streamId: 'stream-1',
				generation: 1,
				sequence: 0,
				payload: { message: 'wrong shape' },
			}).success,
		).toBe(false);
	});
});
