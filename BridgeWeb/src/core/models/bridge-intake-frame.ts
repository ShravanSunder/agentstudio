import { z } from 'zod';

export const bridgeIntakeFrameBaseSchema = z.object({
	streamId: z.string().min(1),
	generation: z.number().int().nonnegative(),
	sequence: z.number().int().nonnegative(),
});

const bridgeIntakePayloadFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.enum(['snapshot', 'delta', 'invalidate']),
	payload: z.unknown(),
});

const bridgeIntakeResetFrameSchema = bridgeIntakeFrameBaseSchema.extend({
	kind: z.literal('reset'),
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
