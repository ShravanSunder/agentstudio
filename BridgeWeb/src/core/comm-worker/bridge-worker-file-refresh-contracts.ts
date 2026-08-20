import { z } from 'zod';

import { bridgeWorkerMainToServerBaseSchema } from './bridge-worker-wire-base-contracts.js';

export const bridgeWorkerFileRefreshRetryCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({ command: z.literal('fileRefreshRetry') })
	.strict();

export type BridgeWorkerFileRefreshRetryCommand = z.infer<
	typeof bridgeWorkerFileRefreshRetryCommandSchema
>;
