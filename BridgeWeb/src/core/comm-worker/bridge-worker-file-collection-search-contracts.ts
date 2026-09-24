import { z } from 'zod';

import { bridgeFileTreeSearchTextMaximumLength } from '../models/bridge-file-tree-search.js';
import {
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import {
	bridgeWorkerMainToServerBaseSchema,
	bridgeWorkerRequestIdSchema,
	bridgeWorkerServerToMainBaseSchema,
} from './bridge-worker-wire-base-contracts.js';

export const BRIDGE_FILE_COLLECTION_SEARCH_MAXIMUM_LIMIT = 500;

export const bridgeFileCollectionSearchCriteriaSchema = z
	.object({
		limit: z.number().int().min(1).max(BRIDGE_FILE_COLLECTION_SEARCH_MAXIMUM_LIMIT),
		scope: z.discriminatedUnion('kind', [
			z.object({ kind: z.literal('all') }).strict(),
			z.object({ kind: z.literal('member'), worktreeId: bridgeProductIdentifierSchema }).strict(),
			z.object({ kind: z.literal('openedDocuments') }).strict(),
		]),
		searchMode: z.enum(['regex', 'text']),
		searchText: z.string().max(bridgeFileTreeSearchTextMaximumLength),
	})
	.strict();

export const bridgeWorkerFileCollectionSearchCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('fileCollectionSearch'),
		criteria: bridgeFileCollectionSearchCriteriaSchema,
	})
	.strict();

const bridgeFileCollectionSearchMatchSchema = z
	.object({
		displayPath: bridgeProductDisplayPathSchema,
		documentLocation: z.string().min(1).nullable(),
		fileId: bridgeProductIdentifierSchema,
		memberWorktreeId: bridgeProductIdentifierSchema.nullable(),
	})
	.strict();

export const bridgeFileCollectionSearchOutcomeSchema = z.discriminatedUnion('kind', [
	z
		.object({
			complete: z.boolean(),
			kind: z.literal('matches'),
			matches: z
				.array(bridgeFileCollectionSearchMatchSchema)
				.max(BRIDGE_FILE_COLLECTION_SEARCH_MAXIMUM_LIMIT)
				.readonly(),
			/** The member-group list the matches were attributed with; null before any arrived. */
			membershipRevision: bridgeProductNonnegativeSequenceSchema.nullable(),
			source: z
				.object({
					sourceGeneration: bridgeProductNonnegativeSequenceSchema,
					sourceId: bridgeProductIdentifierSchema,
				})
				.strict(),
			totalMatchCount: z.number().int().nonnegative(),
			truncated: z.boolean(),
		})
		.strict(),
	z.object({ kind: z.literal('invalidPattern'), searchError: z.string().min(1) }).strict(),
	/** The worker has no File source yet; nothing can be searched. */
	z.object({ kind: z.literal('noSource') }).strict(),
]);

export const bridgeWorkerFileCollectionSearchEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('fileCollectionSearch'),
		outcome: bridgeFileCollectionSearchOutcomeSchema,
		requestId: bridgeWorkerRequestIdSchema,
	})
	.strict();

export type BridgeFileCollectionSearchWireCriteria = z.infer<
	typeof bridgeFileCollectionSearchCriteriaSchema
>;
export type BridgeFileCollectionSearchOutcome = z.infer<
	typeof bridgeFileCollectionSearchOutcomeSchema
>;
export type BridgeWorkerFileCollectionSearchCommand = z.infer<
	typeof bridgeWorkerFileCollectionSearchCommandSchema
>;
export type BridgeWorkerFileCollectionSearchEvent = z.infer<
	typeof bridgeWorkerFileCollectionSearchEventSchema
>;
