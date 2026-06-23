import { z } from 'zod';

import {
	bridgeProtocolIdSchema,
	bridgeResourceKindSchema,
	type BridgeProtocolId,
	type BridgeResourceKind,
} from './bridge-core-models.js';

export const bridgeIntegrityDescriptorSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('wholeHash'),
			algorithm: z.enum(['sha256']),
			value: z.string().min(1),
		})
		.strict(),
	z
		.object({
			kind: z.literal('chunkManifest'),
			algorithm: z.enum(['sha256']),
			manifestResourceId: z.string().min(1),
		})
		.strict(),
	z
		.object({
			kind: z.literal('previewOnly'),
		})
		.strict(),
]);

export const bridgeIdentitySchema = z
	.object({
		paneId: z.string().min(1),
		protocol: bridgeProtocolIdSchema,
		sourceId: z.string().min(1).optional(),
		packageId: z.string().min(1).optional(),
		generation: z.number().int().nonnegative().optional(),
		revision: z.number().int().nonnegative().optional(),
		streamId: z.string().min(1).optional(),
		cursor: z.string().min(1).optional(),
	})
	.strict();

export const bridgeResourceDescriptorSchema = z
	.object({
		descriptorId: z.string().min(1),
		protocol: bridgeProtocolIdSchema,
		resourceKind: bridgeResourceKindSchema,
		resourceUrl: z.string().min(1),
		identity: bridgeIdentitySchema,
		content: z
			.object({
				mediaType: z.string().min(1),
				encoding: z.enum(['utf-8', 'binary']).optional(),
				expectedBytes: z.number().int().nonnegative().optional(),
				maxBytes: z.number().int().positive(),
				integrity: bridgeIntegrityDescriptorSchema.optional(),
			})
			.strict(),
		window: z
			.object({
				start: z.number().int().nonnegative().optional(),
				count: z.number().int().positive().optional(),
				maxCount: z.number().int().positive(),
			})
			.strict()
			.optional(),
	})
	.strict();

export const bridgeDescriptorRefSchema = z
	.object({
		descriptorId: z.string().min(1),
		expectedProtocol: bridgeProtocolIdSchema,
		expectedResourceKind: bridgeResourceKindSchema,
		expectedIdentity: bridgeIdentitySchema,
	})
	.strict();

export const bridgeAttachedResourceDescriptorSchema = z
	.object({
		ref: bridgeDescriptorRefSchema,
		descriptor: bridgeResourceDescriptorSchema,
	})
	.strict();

export type { BridgeProtocolId, BridgeResourceKind };
export type BridgeIntegrityDescriptor = z.infer<typeof bridgeIntegrityDescriptorSchema>;
export type BridgeIdentity = z.infer<typeof bridgeIdentitySchema>;
export type BridgeResourceDescriptor = z.infer<typeof bridgeResourceDescriptorSchema>;
export type BridgeDescriptorRef = z.infer<typeof bridgeDescriptorRefSchema>;
export type BridgeAttachedResourceDescriptor = z.infer<
	typeof bridgeAttachedResourceDescriptorSchema
>;
