import { z } from 'zod';

const bridgeIntakeFrameIdentitySchema = z.object({
	streamId: z.string().min(1),
	generation: z.number().int().nonnegative(),
	sequence: z.number().int().nonnegative(),
});

const bridgeIntakePayloadFrameSchema = bridgeIntakeFrameIdentitySchema.extend({
	kind: z.enum(['snapshot', 'delta', 'invalidate']),
	payload: z.unknown(),
});

const bridgeIntakeResetFrameSchema = bridgeIntakeFrameIdentitySchema.extend({
	kind: z.literal('reset'),
});

const bridgeIntakeCloseFrameSchema = bridgeIntakeFrameIdentitySchema.extend({
	kind: z.literal('close'),
});

const bridgeIntakeErrorFrameSchema = bridgeIntakeFrameIdentitySchema.extend({
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
