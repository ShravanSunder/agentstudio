import { z } from 'zod';

import { BridgeIncrementalSha256 } from './bridge-incremental-sha256.js';
import {
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';
import { bridgeProductWorktreeAnnotationMessageEntrySchema } from './bridge-product-worktree-annotation-contracts.js';

const annotationProjectionDateSchema = z.number().finite();

export const bridgeWorkerAnnotationProjectionSessionSchema = z
	.object({
		completedAt: annotationProjectionDateSchema.nullable(),
		createdAt: annotationProjectionDateSchema,
		eligibleMessageCount: bridgeProductNonnegativeSequenceSchema,
		eligibleWithoutInlinePlacementCount: bridgeProductNonnegativeSequenceSchema,
		lifecycle: z.enum(['living', 'completed']),
		semanticRevision: bridgeProductNonnegativeSequenceSchema,
		sessionId: bridgeProductReviewPublicationIdSchema,
		sourceRelationship: z.enum(['applicable', 'uncertain', 'detached']),
		updatedAt: annotationProjectionDateSchema,
	})
	.strict()
	.refine(
		(session) => session.eligibleWithoutInlinePlacementCount <= session.eligibleMessageCount,
		{
			message: 'Eligible messages without inline placement cannot exceed all eligible messages.',
			path: ['eligibleWithoutInlinePlacementCount'],
		},
	);

export const bridgeWorkerAnnotationProjectionThreadContextSchema = z
	.object({
		diffSide: z.enum(['additions', 'deletions']).nullable(),
		endLine: bridgeProductNonnegativeSequenceSchema.positive(),
		path: bridgeProductDisplayPathSchema,
		placement: z.enum(['exact', 'relocated', 'outdated', 'unavailable']),
		resolution: z.enum(['open', 'resolved']),
		scope: z.literal('located'),
		sourceIdentity: bridgeProductIdentifierSchema,
		sourceRole: z.enum(['file', 'review_base', 'review_head']),
		startLine: bridgeProductNonnegativeSequenceSchema.positive(),
		threadId: bridgeProductReviewPublicationIdSchema,
	})
	.strict()
	.refine((context) => context.endLine >= context.startLine, {
		message: 'Annotation thread endLine cannot precede startLine.',
		path: ['endLine'],
	});

export const bridgeWorkerAnnotationProjectionHeaderSchema = z
	.object({
		expectedMessageCount: bridgeProductNonnegativeSequenceSchema,
		expectedSessionCount: bridgeProductNonnegativeSequenceSchema,
		expectedThreadCount: bridgeProductNonnegativeSequenceSchema,
		projectionRevision: bridgeProductNonnegativeSequenceSchema,
		recoveryStatus: z.enum(['available', 'recovered_degraded', 'unavailable']),
		sessions: z.array(bridgeWorkerAnnotationProjectionSessionSchema).max(128).readonly(),
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict()
	.refine((header) => header.sessions.length === header.expectedSessionCount, {
		message: 'Annotation projection session count does not match its header.',
		path: ['sessions'],
	});

const bridgeWorkerAnnotationProjectionHeaderRecordSchema = z
	.object({
		header: bridgeWorkerAnnotationProjectionHeaderSchema,
		kind: z.literal('header'),
	})
	.strict();

const bridgeWorkerAnnotationProjectionMessageRecordSchema = z
	.object({
		kind: z.literal('message'),
		message: z
			.object({
				context: bridgeWorkerAnnotationProjectionThreadContextSchema,
				message: bridgeProductWorktreeAnnotationMessageEntrySchema,
			})
			.strict()
			.refine((record) => record.context.threadId === record.message.threadId, {
				message: 'Annotation projection message must match its thread context.',
				path: ['message', 'threadId'],
			}),
	})
	.strict();

const bridgeWorkerAnnotationProjectionRecordSchema = z.discriminatedUnion('kind', [
	bridgeWorkerAnnotationProjectionHeaderRecordSchema,
	bridgeWorkerAnnotationProjectionMessageRecordSchema,
]);

export const bridgeWorkerAnnotationProjectionThreadSchema = z
	.object({
		context: bridgeWorkerAnnotationProjectionThreadContextSchema,
		messages: z.array(bridgeProductWorktreeAnnotationMessageEntrySchema).min(1).readonly(),
	})
	.strict();

export const bridgeWorkerAnnotationProjectionSnapshotSchema = z
	.object({
		...bridgeWorkerAnnotationProjectionHeaderSchema.shape,
		threads: z.array(bridgeWorkerAnnotationProjectionThreadSchema).readonly(),
	})
	.strict();

export type BridgeWorkerAnnotationProjectionSnapshot = z.infer<
	typeof bridgeWorkerAnnotationProjectionSnapshotSchema
>;

export class BridgeCommWorkerAnnotationProjectionDecoder {
	#header: z.infer<typeof bridgeWorkerAnnotationProjectionHeaderSchema> | null = null;
	readonly #aggregateHasher = new BridgeIncrementalSha256();
	readonly #messagesByThreadId = new Map<
		string,
		{
			readonly context: z.infer<typeof bridgeWorkerAnnotationProjectionThreadContextSchema>;
			readonly messages: Array<z.infer<typeof bridgeProductWorktreeAnnotationMessageEntrySchema>>;
		}
	>();
	readonly #messageIds = new Set<string>();
	#messageCount = 0;

	acceptPage(bytes: Uint8Array, pageOrdinal: number): void {
		if (bytes.byteLength === 0 || bytes.at(-1) !== 0x0a) {
			throw new Error('Annotation projection page must end at an NDJSON record boundary.');
		}
		this.#aggregateHasher.update(bytes);
		let recordStart = 0;
		for (let cursor = 0; cursor < bytes.byteLength; cursor += 1) {
			if (bytes[cursor] !== 0x0a) continue;
			if (cursor === recordStart) {
				throw new Error('Annotation projection cannot contain an empty NDJSON record.');
			}
			const record = bridgeWorkerAnnotationProjectionRecordSchema.parse(
				parseBridgeProductStrictJSON(bytes.subarray(recordStart, cursor)),
			);
			this.#acceptRecord(record, pageOrdinal);
			recordStart = cursor + 1;
		}
	}

	finish(): {
		readonly aggregateSha256: string;
		readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot;
	} {
		const header = this.#header;
		if (header === null) throw new Error('Annotation projection is missing its header record.');
		if (this.#messageCount !== header.expectedMessageCount) {
			throw new Error('Annotation projection message count does not match its header.');
		}
		if (this.#messagesByThreadId.size !== header.expectedThreadCount) {
			throw new Error('Annotation projection thread count does not match its header.');
		}
		const sessionIds = new Set(header.sessions.map((session) => session.sessionId));
		for (const thread of this.#messagesByThreadId.values()) {
			let previousOrdinal = -1;
			for (const message of thread.messages) {
				if (!sessionIds.has(message.sessionId)) {
					throw new Error('Annotation projection message references an unknown session.');
				}
				if (message.ordinal <= previousOrdinal) {
					throw new Error('Annotation projection message ordinals must be strictly increasing.');
				}
				previousOrdinal = message.ordinal;
			}
		}
		return {
			aggregateSha256: this.#aggregateHasher.digestHex(),
			snapshot: bridgeWorkerAnnotationProjectionSnapshotSchema.parse({
				...header,
				threads: [...this.#messagesByThreadId.values()],
			}),
		};
	}

	#acceptRecord(
		record: z.infer<typeof bridgeWorkerAnnotationProjectionRecordSchema>,
		pageOrdinal: number,
	): void {
		if (record.kind === 'header') {
			if (this.#header !== null || pageOrdinal !== 0 || this.#messageCount !== 0) {
				throw new Error('Annotation projection header must be the first logical record.');
			}
			this.#header = record.header;
			return;
		}
		if (this.#header === null) {
			throw new Error('Annotation projection message cannot precede its header.');
		}
		if (this.#messageIds.has(record.message.message.messageId)) {
			throw new Error('Annotation projection cannot repeat a message identity.');
		}
		this.#messageIds.add(record.message.message.messageId);
		const existingThread = this.#messagesByThreadId.get(record.message.context.threadId);
		if (existingThread === undefined) {
			this.#messagesByThreadId.set(record.message.context.threadId, {
				context: record.message.context,
				messages: [record.message.message],
			});
		} else {
			if (!contextsAreEqual(existingThread.context, record.message.context)) {
				throw new Error('Annotation projection changed a thread context within one snapshot.');
			}
			existingThread.messages.push(record.message.message);
		}
		this.#messageCount += 1;
	}
}

function contextsAreEqual(
	left: z.infer<typeof bridgeWorkerAnnotationProjectionThreadContextSchema>,
	right: z.infer<typeof bridgeWorkerAnnotationProjectionThreadContextSchema>,
): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}
