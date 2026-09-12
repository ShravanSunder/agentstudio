import { z } from 'zod';

const sourceTargetBase = z.object({
	id: z.string().min(1),
	startLine: z.number().int().positive(),
	endLine: z.number().int().positive(),
});

export const bridgeMarkdownSourceTargetSchema = z
	.discriminatedUnion('kind', [
		sourceTargetBase
			.extend({ kind: z.literal('prose'), block: z.enum(['paragraph', 'heading', 'list-item']) })
			.strict(),
		sourceTargetBase.extend({ kind: z.literal('code-line'), fenceId: z.string().min(1) }).strict(),
		sourceTargetBase.extend({ kind: z.literal('code-block') }).strict(),
		sourceTargetBase.extend({ kind: z.literal('table-row') }).strict(),
		sourceTargetBase.extend({ kind: z.literal('diagram') }).strict(),
	])
	.refine((target): boolean => target.endLine >= target.startLine, 'Source range is reversed');

export const bridgeMarkdownSourceTargetsSchema = z
	.array(bridgeMarkdownSourceTargetSchema)
	.superRefine((targets, context): void => {
		const identifiers = new Set<string>();
		let previousEndLine = 0;
		for (const [index, target] of targets.entries()) {
			if (identifiers.has(target.id) || target.startLine <= previousEndLine) {
				context.addIssue({
					code: 'custom',
					path: [index],
					message: 'Source targets must be unique, ordered and non-overlapping',
				});
			}
			identifiers.add(target.id);
			previousEndLine = target.endLine;
		}
	});

export type BridgeMarkdownSourceTarget = z.infer<typeof bridgeMarkdownSourceTargetSchema>;
