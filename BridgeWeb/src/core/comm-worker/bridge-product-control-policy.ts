/** Mirrors AppPolicies.Bridge product operation and admission deadlines. */
export const bridgeProductControlPolicy = {
	admissionRetryCount: 2,
	workerSettlementDeadlineMilliseconds: 5_000,
} as const;
