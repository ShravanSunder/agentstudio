import { z } from 'zod';

import { bridgeProductFileContentDescriptorSchema } from './bridge-product-content-contracts.js';
import { bridgeProductDisplayPathSchema } from './bridge-product-contract-primitives.js';
import { bridgeProductFileChangeStatusSchema } from './bridge-product-file-tree-contracts.js';

export const bridgeProductFileBatchRowSchema = z
	.object({
		changeStatus: bridgeProductFileChangeStatusSchema.nullable(),
		displayKey: bridgeProductDisplayPathSchema,
		kind: z.enum(['file', 'directory', 'deleted']),
		oldPath: bridgeProductDisplayPathSchema.nullable(),
		parentDisplayKey: bridgeProductDisplayPathSchema.nullable(),
		readDescriptor: bridgeProductFileContentDescriptorSchema.nullable(),
		sortKey: bridgeProductDisplayPathSchema,
	})
	.strict()
	.superRefine((row, context): void => {
		if (row.kind !== 'file' && row.readDescriptor !== null) {
			context.addIssue({ code: 'custom', message: 'Directory and deleted rows cannot be opened.' });
		}
		if (
			row.kind === 'deleted' &&
			row.changeStatus !== 'deleted' &&
			row.changeStatus !== 'renamed'
		) {
			context.addIssue({
				code: 'custom',
				message: 'A deleted row requires deleted or renamed status.',
			});
		}
	});

export type BridgeProductFileBatchRow = z.infer<typeof bridgeProductFileBatchRowSchema>;
