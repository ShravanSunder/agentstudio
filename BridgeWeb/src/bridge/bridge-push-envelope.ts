import { z } from 'zod/mini';

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
	readonly data: unknown;
}

const bridgePushEnvelopeSchema = z
	.object({
		__v: z.optional(z.literal(1)),
		__pushId: z.optional(z.string()),
		__revision: z.number().check(z.int(), z.nonnegative()),
		__epoch: z.number().check(z.int(), z.nonnegative()),
		store: z.enum(['diff', 'review', 'agent', 'connection']),
		op: z.enum(['merge', 'replace']),
		level: z.optional(z.enum(['hot', 'warm', 'cold'])),
		data: z.optional(z.unknown()),
		payload: z.optional(z.unknown()),
	})
	.check((payload): void => {
		if (payload.value.data === undefined && payload.value.payload === undefined) {
			payload.issues.push({
				code: 'custom',
				input: payload.value,
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
	return {
		version,
		pushId,
		revision,
		epoch,
		store: parsedEnvelope.store,
		op: parsedEnvelope.op,
		level: parsedEnvelope.level ?? null,
		data,
	};
}
