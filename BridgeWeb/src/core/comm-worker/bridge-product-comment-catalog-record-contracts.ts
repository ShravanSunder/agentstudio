import { z } from 'zod';

import { bridgeProductPositiveSequenceSchema } from './bridge-product-contract-primitives.js';
import { bridgeProductWorktreeAnnotationCatalogEntrySchema } from './bridge-product-worktree-annotation-contracts.js';

export const bridgeProductCommentCatalogRecordSchema = z
	.object({
		entry: bridgeProductWorktreeAnnotationCatalogEntrySchema,
		revision: bridgeProductPositiveSequenceSchema,
	})
	.strict()
	.superRefine((record, context): void => {
		if (record.entry.kind === 'session' && record.entry.semanticRevision !== record.revision) {
			context.addIssue({
				code: 'custom',
				message: 'Session record revision must match its semantic revision.',
			});
		}
	});

export function bridgeProductCommentCatalogRecordKey(
	record: z.infer<typeof bridgeProductCommentCatalogRecordSchema>,
): string {
	switch (record.entry.kind) {
		case 'session':
			return `session:${record.entry.sessionId.toLowerCase()}`;
		case 'thread':
			return `thread:${record.entry.threadId.toLowerCase()}`;
		case 'message':
			return `message:${record.entry.messageId.toLowerCase()}`;
	}
}

export type BridgeProductCommentCatalogRecord = z.infer<
	typeof bridgeProductCommentCatalogRecordSchema
>;
