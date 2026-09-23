import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
} from './bridge-product-contract-primitives.js';

export const bridgeProductFileSourceIdentitySchema = z
	.object({
		collectionToken: bridgeProductOpaqueReferenceSchema,
		rootRevisionToken: bridgeProductOpaqueReferenceSchema.nullable(),
		sourceCursor: bridgeProductOpaqueReferenceSchema,
		sourceId: bridgeProductIdentifierSchema,
		subscriptionGeneration: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

export type BridgeProductFileSourceIdentity = z.infer<typeof bridgeProductFileSourceIdentitySchema>;
