import { bridgeProductWorktreeAnnotationCommandResultSchema } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';
import type {
	BridgeWorkerAnnotationCommandAcceptedEvent,
	BridgeWorkerAnnotationProjectionEvent,
} from './bridge-worker-annotation-contracts.js';

export function bridgeCommWorkerAnnotationProjectionEvent(props: {
	readonly event: BridgeProductWorktreeAnnotationEvent;
	readonly subscriptionId: string;
	readonly surface: 'fileView' | 'review';
}): BridgeWorkerAnnotationProjectionEvent {
	return {
		direction: 'serverWorkerToMain',
		event: props.event,
		kind: 'annotationProjection',
		subscriptionId: props.subscriptionId,
		surface: props.surface,
		transferDescriptors: [],
		wireVersion: 1,
	};
}

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
	const annotationResult = bridgeProductWorktreeAnnotationCommandResultSchema.parse(
		props.actionResult,
	);
	return {
		direction: 'serverWorkerToMain',
		kind: 'annotationCommandAccepted',
		productRequestId: annotationResult.requestId,
		requestId: props.requestId,
		surface: props.command.method === 'file.annotations.command' ? 'fileView' : 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}
