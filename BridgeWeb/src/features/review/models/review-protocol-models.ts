import { z } from 'zod';

import { bridgeDemandLaneSchema } from '../../../core/models/bridge-demand-models.js';

export const reviewTreeRowMetadataSchema = z
	.object({
		rowId: z.string().min(1),
		itemId: z.string().min(1).optional(),
		path: z.string().min(1),
		depth: z.number().int().nonnegative(),
		isDirectory: z.boolean(),
		loaded_by: z
			.enum([
				'startup_window',
				'foreground',
				'visible',
				'nearby',
				'speculative',
				'idle',
				'delta',
				'reset',
				'replacement',
			])
			.optional(),
		lane: bridgeDemandLaneSchema.optional(),
	})
	.strict();

export type ReviewTreeRowMetadata = z.infer<typeof reviewTreeRowMetadataSchema>;
