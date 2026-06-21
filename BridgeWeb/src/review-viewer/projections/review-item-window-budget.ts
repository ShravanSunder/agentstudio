import { z } from 'zod';

export const bridgeReviewItemWindowMemoryPressureSchema = z.enum(['normal', 'high']);

export const bridgeReviewItemWindowBudgetInputsSchema = z
	.object({
		measuredVisibleItemCount: z.number().int().nonnegative(),
		overscanItemCount: z.number().int().nonnegative(),
		resourceCacheHitRate: z.number().min(0).max(1),
		workerLatencyMilliseconds: z.number().nonnegative(),
		fetchLatencyMilliseconds: z.number().nonnegative(),
		currentPackageItemCount: z.number().int().nonnegative(),
		memoryPressure: bridgeReviewItemWindowMemoryPressureSchema,
	})
	.strict();

export type BridgeReviewItemWindowBudgetInputs = z.infer<
	typeof bridgeReviewItemWindowBudgetInputsSchema
>;

export const bridgeReviewItemWindowBudgetSchema = z
	.object({
		requestedItemCount: z.number().int().positive(),
		maxExplicitItemIds: z.number().int().positive(),
		maxCursorWindowItems: z.number().int().positive(),
	})
	.strict();

export type BridgeReviewItemWindowBudget = z.infer<typeof bridgeReviewItemWindowBudgetSchema>;

const minimumRequestedItems = 16;
const defaultMaxExplicitItemIds = 96;
const defaultMaxCursorWindowItems = 384;
const highLatencyMilliseconds = 250;
const lowCacheHitRate = 0.6;

export function resolveBridgeReviewItemWindowBudget(
	inputs: BridgeReviewItemWindowBudgetInputs,
): BridgeReviewItemWindowBudget {
	const parsedInputs = bridgeReviewItemWindowBudgetInputsSchema.parse(inputs);
	const visibleWindow = Math.max(
		minimumRequestedItems,
		parsedInputs.measuredVisibleItemCount + parsedInputs.overscanItemCount,
	);
	const latencyMultiplier =
		parsedInputs.workerLatencyMilliseconds >= highLatencyMilliseconds ||
		parsedInputs.fetchLatencyMilliseconds >= highLatencyMilliseconds
			? 2
			: 1;
	const cacheMissMultiplier = parsedInputs.resourceCacheHitRate < lowCacheHitRate ? 2 : 1;
	const pressureDivisor = parsedInputs.memoryPressure === 'high' ? 2 : 1;
	const adaptiveCount = Math.ceil(
		(visibleWindow * latencyMultiplier * cacheMissMultiplier) / pressureDivisor,
	);
	const requestedItemCount = clampInteger({
		value: adaptiveCount,
		minimum: 1,
		maximum: Math.min(parsedInputs.currentPackageItemCount || 1, defaultMaxCursorWindowItems),
	});

	return bridgeReviewItemWindowBudgetSchema.parse({
		requestedItemCount,
		maxExplicitItemIds: defaultMaxExplicitItemIds,
		maxCursorWindowItems: defaultMaxCursorWindowItems,
	});
}

function clampInteger(props: {
	readonly value: number;
	readonly minimum: number;
	readonly maximum: number;
}): number {
	return Math.max(props.minimum, Math.min(props.maximum, props.value));
}
