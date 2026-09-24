import { z } from 'zod';

import { bridgeProductFileSelectionReceiptRequestSchema } from './bridge-product-call-contracts.js';
import { bridgeWorkerMainToServerBaseSchema } from './bridge-worker-wire-base-contracts.js';

export const bridgeWorkerFileSelectionReceiptCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('fileSelectionReceipt'),
		receipt: bridgeProductFileSelectionReceiptRequestSchema,
	})
	.strict();

export type BridgeWorkerFileSelectionReceiptCommand = z.infer<
	typeof bridgeWorkerFileSelectionReceiptCommandSchema
>;
