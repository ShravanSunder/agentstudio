import type { BridgeWorkerAnnotationProjectionSnapshot } from './bridge-comm-worker-annotation-projection-decoder.js';
import { bridgeProductWorktreeAnnotationDecodedCommandResultSchema } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeWorkerAnnotationCommandAcceptedEvent,
	BridgeWorkerAnnotationProjectionConvergenceEvent,
} from './bridge-worker-annotation-contracts.js';

export function bridgeCommWorkerAnnotationCommandAcceptedEvent(props: {
	readonly actionResult: unknown;
	readonly command: BridgeProductControlCommand;
	readonly requestId: string;
}): BridgeWorkerAnnotationCommandAcceptedEvent | null {
	if (
		props.command.method !== 'file.annotations.command' &&
		props.command.method !== 'review.annotations.command'
	) {
		return null;
	}
	const annotationResult = bridgeProductWorktreeAnnotationDecodedCommandResultSchema.parse(
		props.actionResult,
	);
	return {
		direction: 'serverWorkerToMain',
		kind: 'annotationCommandAccepted',
		outcome: annotationResult.outcome,
		productRequestId: annotationResult.outcome.requestId,
		requestId: props.requestId,
		surface: props.command.method === 'file.annotations.command' ? 'fileView' : 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function bridgeCommWorkerAnnotationProjectionConvergenceEvent(props: {
	readonly state:
		| { readonly kind: 'ready'; readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot }
		| { readonly error: unknown; readonly kind: 'unavailable' }
		| { readonly kind: 'refreshing' };
	readonly surface: 'file' | 'review';
}): BridgeWorkerAnnotationProjectionConvergenceEvent {
	const state =
		props.state.kind === 'unavailable'
			? {
					kind: 'unavailable' as const,
					retryable:
						props.state.error instanceof BridgeProductControlRequestError &&
						props.state.error.retryable,
				}
			: props.state;
	return {
		direction: 'serverWorkerToMain',
		kind: 'annotationProjectionConvergence',
		state,
		surface: props.surface === 'file' ? 'fileView' : 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}
