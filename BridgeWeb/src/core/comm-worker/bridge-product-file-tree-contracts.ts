import { z } from 'zod';

import {
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewFileClassSchema } from './bridge-product-review-primitives.js';

export const bridgeProductFileChangeStatusSchema = z.enum([
	'added',
	'deleted',
	'modified',
	'renamed',
	'copied',
	'typeChanged',
	'unmerged',
	'untracked',
]);

export const bridgeProductFileTreeFileClassSchema = bridgeProductReviewFileClassSchema.exclude([
	'binary',
]);

export type BridgeProductFileTreeFileClass = z.infer<typeof bridgeProductFileTreeFileClassSchema>;

export const bridgeProductFileTreeRowSchema = z
	.object({
		changeStatus: bridgeProductFileChangeStatusSchema.nullable(),
		depth: bridgeProductNonnegativeSequenceSchema,
		fileId: bridgeProductIdentifierSchema.nullable(),
		fileClass: bridgeProductFileTreeFileClassSchema.nullable(),
		isDirectory: z.boolean(),
		lineCount: bridgeProductNonnegativeSequenceSchema.nullable(),
		name: bridgeProductDisplayPathSchema,
		parentPath: bridgeProductDisplayPathSchema.nullable(),
		path: bridgeProductDisplayPathSchema,
		rowId: bridgeProductIdentifierSchema,
		sizeBytes: bridgeProductNonnegativeSequenceSchema.nullable(),
	})
	.strict()
	.superRefine((row, context): void => {
		if (row.isDirectory && row.fileClass !== null) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata directory rows cannot carry a file class.',
				path: ['fileClass'],
			});
		}
		if (!row.isDirectory && row.fileClass === null) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata file rows require a path-and-size-backed file class.',
				path: ['fileClass'],
			});
		}
	});
