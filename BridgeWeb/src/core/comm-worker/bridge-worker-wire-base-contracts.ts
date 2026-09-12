import { z } from 'zod';

export const BRIDGE_WORKER_WIRE_VERSION = 1 as const;
export const bridgeWorkerRequestIdSchema = z.string().min(1);
export const bridgeWorkerEpochSchema = z.number().int().nonnegative();
export const bridgeWorkerSequenceSchema = z.number().int().nonnegative();
export const bridgeWorkerIssuedAtMillisecondsSchema = z.number().finite().nonnegative();
export const bridgeWorkerInteractionSurfaceSchema = z.enum(['fileView', 'review']);

export const bridgeWorkerTransferDescriptorSchema = z
	.object({
		messageKind: z.string().min(1),
		fieldPath: z.array(z.string().min(1)).readonly(),
		byteLength: z.number().int().nonnegative(),
		mode: z.enum(['transfer', 'clone']),
	})
	.strict();

export type BridgeWorkerTransferDescriptor = z.infer<typeof bridgeWorkerTransferDescriptorSchema>;

export const bridgeWorkerMainToServerBaseSchema = z
	.object({
		wireVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		direction: z.literal('mainToServerWorker'),
		kind: z.literal('command'),
		requestId: bridgeWorkerRequestIdSchema,
		epoch: bridgeWorkerEpochSchema,
		issuedAtMilliseconds: bridgeWorkerIssuedAtMillisecondsSchema.optional(),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();

export const bridgeWorkerServerToMainBaseSchema = z
	.object({
		wireVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		direction: z.literal('serverWorkerToMain'),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();
