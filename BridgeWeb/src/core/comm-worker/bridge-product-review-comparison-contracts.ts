import { z } from 'zod';

export const bridgeProductReviewComparisonBasisSchema = z.enum(['commonCommit', 'branchTip']);
export const bridgeProductReviewComparisonBaseRoleSchema = z.enum([
	'commonCommit',
	'selectedTarget',
]);

export const bridgeProductReviewComparisonTargetSchema = z.discriminatedUnion('kind', [
	z
		.object({
			basis: bridgeProductReviewComparisonBasisSchema,
			branchName: z.string().min(1),
			kind: z.literal('localDefaultBranch'),
		})
		.strict(),
	z
		.object({
			basis: bridgeProductReviewComparisonBasisSchema,
			branchName: z.string().min(1),
			kind: z.literal('originDefaultBranch'),
			remoteName: z.string().min(1),
		})
		.strict(),
	z
		.object({
			basis: bridgeProductReviewComparisonBasisSchema,
			kind: z.literal('branch'),
			name: z.string().min(1),
		})
		.strict(),
	z
		.object({
			kind: z.literal('commit'),
			oid: z.string().regex(/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/iu),
		})
		.strict(),
	z
		.object({
			basis: bridgeProductReviewComparisonBasisSchema,
			kind: z.literal('ref'),
			name: z.string().min(1),
		})
		.strict(),
]);

export const bridgeProductReviewComparisonOriginSchema = z
	.object({
		baseOID: z.string().min(1),
		baseRole: bridgeProductReviewComparisonBaseRoleSchema,
		comparedRole: z.literal('capturedWorkingTree'),
		kind: z.literal('contribution'),
		resolvedTargetOID: z.string().min(1),
		reviewedHeadOID: z.string().min(1),
		symbolicTarget: bridgeProductReviewComparisonTargetSchema,
	})
	.strict();
