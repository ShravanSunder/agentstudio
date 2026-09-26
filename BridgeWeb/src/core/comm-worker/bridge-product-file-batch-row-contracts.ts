import { z } from 'zod';

import { bridgeProductFileContentDescriptorSchema } from './bridge-product-content-contracts.js';
import {
	bridgeProductDisplayPathSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductFileChangeStatusSchema } from './bridge-product-file-tree-contracts.js';
import { bridgeProductReviewFileClassSchema } from './bridge-product-review-primitives.js';

export const bridgeProductFileBatchRowSchema = z
	.object({
		changeStatus: bridgeProductFileChangeStatusSchema.nullable(),
		displayKey: bridgeProductDisplayPathSchema,
		fileClass: bridgeProductReviewFileClassSchema.nullable(),
		kind: z.enum(['file', 'directory', 'deleted']),
		lineCount: bridgeProductNonnegativeSequenceSchema.nullable(),
		oldPath: bridgeProductDisplayPathSchema.nullable(),
		parentDisplayKey: bridgeProductDisplayPathSchema.nullable(),
		readDescriptor: bridgeProductFileContentDescriptorSchema.nullable(),
		sizeBytes: bridgeProductNonnegativeSequenceSchema.nullable(),
		sortKey: bridgeProductDisplayPathSchema,
	})
	.strict()
	.superRefine((row, context): void => {
		if (row.kind === 'file' && (row.fileClass === null || row.fileClass === 'binary')) {
			context.addIssue({ code: 'custom', message: 'File rows require a nonbinary file class.' });
		}
		if (
			row.kind !== 'file' &&
			(row.fileClass !== null || row.sizeBytes !== null || row.lineCount !== null)
		) {
			context.addIssue({
				code: 'custom',
				message: 'Directory and ghost rows have no file extent facts.',
			});
		}
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
