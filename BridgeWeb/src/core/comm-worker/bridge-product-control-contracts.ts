import { z } from 'zod';

export const bridgeActiveViewerSourceSchema = z
	.object({
		protocol: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1),
		generation: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeActiveViewerModeUpdateSchema = z
	.object({
		sessionId: z.string().min(1),
		sequence: z.number().int().positive(),
		mode: z.enum(['file', 'review']),
		activeSource: bridgeActiveViewerSourceSchema.nullable(),
	})
	.strict();

export const bridgeProductControlIntakeReadyParamsSchema = z
	.object({
		protocolId: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1).nullable().optional(),
		generation: z.number().int().nonnegative().optional(),
		reason: z.string().min(1).nullable().optional(),
	})
	.strict();

const bridgeProductControlMarkFileViewedCommandSchema = z
	.object({
		method: z.literal('review.markFileViewed'),
		params: z.object({ fileId: z.string().min(1) }).strict(),
	})
	.strict();

const bridgeProductControlActiveViewerModeUpdateCommandSchema = z
	.object({
		method: z.literal('bridge.activeViewerMode.update'),
		params: bridgeActiveViewerModeUpdateSchema,
	})
	.strict();

const bridgeProductControlIntakeReadyCommandSchema = z
	.object({
		method: z.literal('bridge.intakeReady'),
		params: bridgeProductControlIntakeReadyParamsSchema,
	})
	.strict();

export const bridgeProductControlCommandSchema = z.discriminatedUnion('method', [
	bridgeProductControlMarkFileViewedCommandSchema,
	bridgeProductControlActiveViewerModeUpdateCommandSchema,
	bridgeProductControlIntakeReadyCommandSchema,
]);

export type BridgeActiveViewerSource = z.infer<typeof bridgeActiveViewerSourceSchema>;
export type BridgeActiveViewerModeUpdate = z.infer<typeof bridgeActiveViewerModeUpdateSchema>;
export type BridgeProductControlCommand = z.infer<typeof bridgeProductControlCommandSchema>;
