import { z } from 'zod';

import {
	decodeBridgeTraceContext,
	type BridgeTraceContext,
} from '../../foundation/telemetry/bridge-trace-context.js';

export const bridgeIntakeFrameBaseSchema = z.object({
	streamId: z.string().min(1),
	generation: z.number().int().nonnegative(),
	sequence: z.number().int().nonnegative(),
	__traceContext: z
		.custom<BridgeTraceContext>((value): boolean => decodeBridgeTraceContext(value) !== null)
		.optional(),
});

const bridgeIntakePayloadFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.enum(['snapshot', 'delta', 'invalidate']),
	payload: z.unknown(),
});

const bridgeIntakeResetFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.literal('reset'),
	payload: z.unknown().optional(),
});

const bridgeIntakeCloseFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.literal('close'),
});

const bridgeIntakeErrorFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.literal('error'),
	message: z.string().min(1),
});

export const bridgeIntakeFrameSchema = z.discriminatedUnion('kind', [
	bridgeIntakePayloadFrameSchema,
	bridgeIntakeResetFrameSchema,
	bridgeIntakeCloseFrameSchema,
	bridgeIntakeErrorFrameSchema,
]);

export type BridgeIntakeFrame = z.infer<typeof bridgeIntakeFrameSchema>;
