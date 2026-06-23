import { z } from 'zod';

const bridgeProtocolOrResourceNamePattern = /^[a-z][a-zA-Z0-9]*(?:[.-][a-z][a-zA-Z0-9]*)*$/u;

export const bridgeProtocolIdSchema = z.string().regex(bridgeProtocolOrResourceNamePattern);
export const bridgeResourceKindSchema = z.string().regex(bridgeProtocolOrResourceNamePattern);
export const bridgeStreamIdSchema = z.string().min(1);

export const bridgeStreamIdentitySchema = z
	.object({
		protocol: bridgeProtocolIdSchema,
		streamId: bridgeStreamIdSchema,
		generation: z.number().int().nonnegative().optional(),
		revision: z.number().int().nonnegative().optional(),
		cursor: z.string().min(1).optional(),
	})
	.strict();

export const bridgeBoundedWindowSchema = z
	.object({
		start: z.number().int().nonnegative(),
		count: z.number().int().positive(),
		maxCount: z.number().int().positive(),
	})
	.strict()
	.refine((window) => window.count <= window.maxCount, {
		message: 'count must be less than or equal to maxCount',
		path: ['count'],
	});

export type BridgeProtocolId = z.infer<typeof bridgeProtocolIdSchema>;
export type BridgeResourceKind = z.infer<typeof bridgeResourceKindSchema>;
export type BridgeStreamId = z.infer<typeof bridgeStreamIdSchema>;
export type BridgeStreamIdentity = z.infer<typeof bridgeStreamIdentitySchema>;
export type BridgeBoundedWindow = z.infer<typeof bridgeBoundedWindowSchema>;
