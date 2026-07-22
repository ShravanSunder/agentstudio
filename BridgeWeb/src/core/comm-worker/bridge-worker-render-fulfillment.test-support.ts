import type { BridgeProductSurface } from './bridge-product-contract-primitives.js';
import type { BridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.js';

export interface MakeBridgeWorkerRenderReceiptIdentityProps {
	readonly itemId: string;
	readonly publicationSequence: number;
	readonly surface: BridgeProductSurface;
	readonly workerDerivationEpoch: number;
}

export function makeBridgeWorkerRenderReceiptIdentity(
	props: MakeBridgeWorkerRenderReceiptIdentityProps,
): BridgeWorkerRenderReceiptIdentity {
	const identitySuffix = `${props.surface}-${props.publicationSequence}`;
	return {
		attemptId: `attempt-${identitySuffix}`,
		itemId: props.itemId,
		paneSessionId: 'pane-session-test',
		publicationId: `publication-${identitySuffix}`,
		publicationSequence: props.publicationSequence,
		submissionId: `submission-${identitySuffix}`,
		surface: props.surface,
		windowKey: `window-${identitySuffix}`,
		workerDerivationEpoch: props.workerDerivationEpoch,
		workerInstanceId: 'worker-instance-test',
	};
}
