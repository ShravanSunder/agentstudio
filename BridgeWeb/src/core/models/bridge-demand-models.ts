import { z } from 'zod';

export const bridgeDemandLaneSchema = z.enum([
	'foreground',
	'active',
	'visible',
	'nearby',
	'speculative',
	'idle',
]);

export const bridgeContentDemandRoleSchema = z.enum([
	'selected',
	'visible',
	'nearby',
	'speculative',
	'background',
]);

export type BridgeDemandLane = z.infer<typeof bridgeDemandLaneSchema>;
export type BridgeContentDemandRole = z.infer<typeof bridgeContentDemandRoleSchema>;
