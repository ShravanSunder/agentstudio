import { z } from 'zod';

export const bridgeProductReviewComparisonTargetSchema = z.discriminatedUnion('kind', [
	z.object({ branchName: z.string().min(1), kind: z.literal('localDefaultBranch') }).strict(),
	z
		.object({
			branchName: z.string().min(1),
			kind: z.literal('originDefaultBranch'),
			remoteName: z.string().min(1),
		})
		.strict(),
	z.object({ kind: z.literal('branch'), name: z.string().min(1) }).strict(),
	z.object({ kind: z.literal('ref'), name: z.string().min(1) }).strict(),
]);

export const bridgeProductReviewComparisonOriginSchema = z
	.object({
		baseRole: z.literal('contributionBase'),
		comparedRole: z.literal('capturedWorkingTree'),
		contributionBaseOID: z.string().min(1),
		kind: z.literal('contribution'),
		resolvedTargetOID: z.string().min(1),
		reviewedHeadOID: z.string().min(1),
		symbolicTarget: bridgeProductReviewComparisonTargetSchema,
	})
	.strict();
