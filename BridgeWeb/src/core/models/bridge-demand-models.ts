import { z } from 'zod';

import { bridgeDescriptorRefSchema } from './bridge-resource-descriptor.js';

export const bridgeDemandLaneSchema = z.enum([
	'foreground',
	'active',
	'visible',
	'nearby',
	'speculative',
	'idle',
]);

export const bridgeDemandIntentSchema = z
	.object({
		descriptorRef: bridgeDescriptorRefSchema,
		lane: bridgeDemandLaneSchema,
		orderingKey: z.string().min(1),
		dedupeKey: z.string().min(1),
		freshnessKey: z.string().min(1),
		cancellationGroup: z.string().min(1),
	})
	.strict();

export const bridgeDescriptorDemandStateSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('missing') }).strict(),
	z
		.object({
			kind: z.literal('valid'),
			freshnessKey: z.string().min(1),
			needsBodyOrWindow: z.boolean(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('stale'),
			freshnessKey: z.string().min(1),
			needsBodyOrWindow: z.boolean(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('reset'),
			sourceIdentity: z.string().min(1),
		})
		.strict(),
]);

export const bridgeViewInterestSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('none') }).strict(),
	z.object({ kind: z.literal('selected') }).strict(),
	z.object({ kind: z.literal('open') }).strict(),
	z.object({ kind: z.literal('visible') }).strict(),
	z.object({ kind: z.literal('nearby') }).strict(),
	z.object({ kind: z.literal('speculative') }).strict(),
	z.object({ kind: z.literal('background') }).strict(),
]);

export const bridgeDemandKeysSchema = z
	.object({
		orderingKey: z.string().min(1),
		dedupeKey: z.string().min(1),
		freshnessKey: z.string().min(1),
		cancellationGroup: z.string().min(1),
	})
	.strict();

export type BridgeDemandLane = z.infer<typeof bridgeDemandLaneSchema>;
export type BridgeDemandIntent = z.infer<typeof bridgeDemandIntentSchema>;
export type BridgeDescriptorDemandState = z.infer<typeof bridgeDescriptorDemandStateSchema>;
export type BridgeViewInterest = z.infer<typeof bridgeViewInterestSchema>;
export type BridgeDemandKeys = z.infer<typeof bridgeDemandKeysSchema>;
