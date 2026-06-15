import { z } from 'zod';

import {
	decodeBridgeTraceContext,
	type BridgeTraceContext,
} from '../foundation/telemetry/bridge-trace-context.js';

export type BridgePushStore = 'diff' | 'review' | 'agent' | 'connection';
export type BridgePushOp = 'merge' | 'replace';
export type BridgePushLevel = 'hot' | 'warm' | 'cold';

export interface BridgePushEnvelope {
	readonly version: 1 | null;
	readonly pushId: string | null;
	readonly revision: number;
	readonly epoch: number;
	readonly store: BridgePushStore;
	readonly op: BridgePushOp;
	readonly level: BridgePushLevel | null;
	readonly traceContext: BridgeTraceContext | null;
	readonly data: unknown;
}

const bridgePushEnvelopeSchema = z
	.object({
		__v: z.literal(1).optional(),
		__pushId: z.string().optional(),
		__revision: z.number().int().nonnegative(),
		__epoch: z.number().int().nonnegative(),
		__traceContext: z.unknown().optional(),
		store: z.enum(['diff', 'review', 'agent', 'connection']),
		op: z.enum(['merge', 'replace']),
		level: z.enum(['hot', 'warm', 'cold']).optional(),
		data: z.unknown().optional(),
		payload: z.unknown().optional(),
	})
	.superRefine((value, context): void => {
		if (value.data === undefined && value.payload === undefined) {
			context.addIssue({
				code: 'custom',
				message: 'Bridge push envelope requires data or payload',
				path: ['data'],
			});
		}
	});

export function decodeBridgePushEnvelope(value: unknown): BridgePushEnvelope {
	const result = bridgePushEnvelopeSchema.safeParse(value);
	if (!result.success) {
		throw new Error(`Invalid bridge push envelope: ${result.error.message}`);
	}
	const parsedEnvelope = result.data;
	const data = parsedEnvelope.data === undefined ? parsedEnvelope.payload : parsedEnvelope.data;
	const version = parsedEnvelope['__v'] ?? null;
	const pushId = parsedEnvelope['__pushId'] ?? null;
	const revision = parsedEnvelope['__revision'];
	const epoch = parsedEnvelope['__epoch'];
	const traceContext =
		parsedEnvelope['__traceContext'] === undefined
			? null
			: decodeBridgeTraceContext(parsedEnvelope['__traceContext']);
	return {
		version,
		pushId,
		revision,
		epoch,
		store: parsedEnvelope.store,
		op: parsedEnvelope.op,
		level: parsedEnvelope.level ?? null,
		traceContext,
		data,
	};
}
