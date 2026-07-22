import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
} from './bridge-product-contract-primitives.js';

export const bridgeProductFileSourceIdentitySchema = z
	.object({
		repoId: z.uuid(),
		rootRevisionToken: bridgeProductOpaqueReferenceSchema.nullable(),
		sourceCursor: bridgeProductOpaqueReferenceSchema,
		sourceId: bridgeProductIdentifierSchema,
		subscriptionGeneration: bridgeProductNonnegativeSequenceSchema,
		worktreeId: z.uuid(),
	})
	.strict();

export type BridgeProductFileSourceIdentity = z.infer<typeof bridgeProductFileSourceIdentitySchema>;
