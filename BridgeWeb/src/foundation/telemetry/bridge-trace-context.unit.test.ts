import { describe, expect, test } from 'vitest';

import {
	bridgeTraceparent,
	createBridgeChildTraceContext,
	decodeBridgeTraceContext,
	parseBridgeTraceparent,
} from './bridge-trace-context.js';

describe('bridge trace context', () => {
	test('decodes and serializes W3C traceparent-compatible contexts', () => {
		const context = decodeBridgeTraceContext({
			traceId: '11111111111111111111111111111111',
			spanId: '2222222222222222',
			parentSpanId: null,
			sampled: true,
		});

		expect(context).not.toBeNull();
		expect(context === null ? null : bridgeTraceparent(context)).toBe(
			'00-11111111111111111111111111111111-2222222222222222-01',
		);
	});

	test('rejects invalid and all-zero identifiers', () => {
		expect(
			decodeBridgeTraceContext({
				traceId: '00000000000000000000000000000000',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			}),
		).toBeNull();
		expect(parseBridgeTraceparent('00-INVALID-2222222222222222-01')).toBeNull();
	});

	test('creates child contexts without changing the trace id', () => {
		const parent = parseBridgeTraceparent(
			'00-11111111111111111111111111111111-2222222222222222-01',
		);
		if (parent === null) {
			throw new Error('expected parent trace context');
		}

		const child = createBridgeChildTraceContext(parent, () => '3333333333333333');

		expect(child).toEqual({
			traceId: '11111111111111111111111111111111',
			spanId: '3333333333333333',
			parentSpanId: '2222222222222222',
			sampled: true,
		});
	});
});
