import { z } from 'zod';

import { bridgeFileTreeSearchTextMaximumLength } from '../models/bridge-file-tree-search.js';
import { bridgeProductFileTreeFileClassSchema } from './bridge-product-subscription-contracts.js';

export const bridgeWorkerFileQuerySchema = z
	.object({
		filterMode: z.union([z.literal('all'), bridgeProductFileTreeFileClassSchema]),
		searchMode: z.enum(['text', 'regex']),
		searchText: z.string().max(bridgeFileTreeSearchTextMaximumLength),
	})
	.strict();

export type BridgeWorkerFileQuery = z.infer<typeof bridgeWorkerFileQuerySchema>;

export function bridgeWorkerFileQueryKey(query: BridgeWorkerFileQuery): string {
	return `${query.filterMode}\u{0}${query.searchMode}\u{0}${query.searchText}`;
}

export const bridgeWorkerFileQueryDisplayPayloadSchema = bridgeWorkerFileQuerySchema
	.extend({
		projectedRowCount: z.number().int().nonnegative(),
		searchError: z.string().min(1).nullable(),
		totalRowCount: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeWorkerFileQueryDisplayPayload = z.infer<
	typeof bridgeWorkerFileQueryDisplayPayloadSchema
>;
