import { z } from 'zod';

import { bridgeProductNonnegativeSequenceSchema } from './bridge-product-contract-primitives.js';

export const bridgeProductReviewContentRoleSchema = z.enum(['base', 'head', 'diff', 'file']);

export const bridgeProductReviewContentLineCountsByRoleSchema = z
	.object({
		base: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
		head: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
		diff: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
		file: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
	})
	.strict();

export const bridgeProductReviewFileChangeKindSchema = z.enum([
	'added',
	'modified',
	'deleted',
	'renamed',
	'copied',
]);

export const bridgeProductReviewFileClassSchema = z.enum([
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'binary',
	'large',
	'fixture',
	'unknown',
]);

export const bridgeProductReviewFileStateSchema = z.enum([
	'unreviewed',
	'viewed',
	'annotated',
	'resolved',
]);

export const bridgeProductReviewGroupingKindSchema = z.enum([
	'flat',
	'folder',
	'fileClass',
	'changeKind',
	'reviewState',
	'agentStream',
	'prompt',
	'session',
	'checkpoint',
	'timeWindow',
	'custom',
]);

export const bridgeProductReviewPrioritySchema = z.enum(['low', 'normal', 'high']);

export const bridgeProductReviewSourceEndpointKindSchema = z.enum([
	'gitRef',
	'workingTree',
	'index',
	'promptCheckpoint',
	'sessionCheckpoint',
	'manualCheckpoint',
	'savedTimeWindowCheckpoint',
]);

export const bridgeProductReviewPackageSummarySchema = z
	.object({
		additions: bridgeProductNonnegativeSequenceSchema,
		deletions: bridgeProductNonnegativeSequenceSchema,
		filesChanged: bridgeProductNonnegativeSequenceSchema,
		hiddenFileCount: bridgeProductNonnegativeSequenceSchema,
		visibleFileCount: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();
