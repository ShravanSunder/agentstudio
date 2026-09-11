import { z } from 'zod';

import {
	bridgeWorkerRenderDispositionBatchMaximumReceiptCount,
	bridgeWorkerRenderDispositionReceiptSchema,
} from './bridge-worker-render-fulfillment.js';
import { bridgeWorkerMainToServerBaseSchema } from './bridge-worker-wire-base-contracts.js';

export const bridgeWorkerRenderDispositionCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('renderDisposition'),
		receipts: z
			.array(bridgeWorkerRenderDispositionReceiptSchema)
			.min(1)
			.max(bridgeWorkerRenderDispositionBatchMaximumReceiptCount)
			.readonly(),
	})
	.strict();
