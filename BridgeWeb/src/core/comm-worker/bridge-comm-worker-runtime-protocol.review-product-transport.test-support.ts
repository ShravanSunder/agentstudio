import { makeReviewPanePresentationFrame } from './bridge-comm-worker-runtime-protocol.review-product-pane-presentation.test-support.js';
import {
	createIdleWorktreeAnnotationSubscription,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';

export function makeReviewProductTransport(props: {
	readonly initialReviewEpoch?: number;
	readonly onPanePresentationSink?: (
		sink: (frame: BridgeProductPanePresentationFrame) => void,
	) => void;
	readonly openedContentKinds?: string[];
	readonly reviewSubscription: BridgeProductSubscription<'review.metadata'>;
	readonly subscribedKinds: string[];
}): BridgeProductTransportSession {
	let reviewEpoch = props.initialReviewEpoch ?? 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'review' ? reviewEpoch : 0;
		},
		call: async (): Promise<never> => ({ reason: 'notConfigured', status: 'unavailable' }) as never,
		openContent: (descriptor) => {
			if (descriptor.contentKind !== 'review.content') {
				throw new Error(`Unexpected product content kind ${descriptor.contentKind}.`);
			}
			props.openedContentKinds?.push(descriptor.contentKind);
			return makeImmediateReviewContentStream(descriptor, 'hello world\n') as never;
		},
		setPanePresentationFrameSink: (sink): void => {
			props.onPanePresentationSink?.(sink);
			sink(makeReviewPanePresentationFrame(1, 'foreground'));
		},
		subscribe: (...arguments_): never => {
			const [subscriptionKind] = arguments_;
			props.subscribedKinds.push(subscriptionKind);
			if (subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') {
				return createIdleWorktreeAnnotationSubscription(subscriptionKind) as never;
			}
			if (subscriptionKind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${subscriptionKind}.`);
			}
			return props.reviewSubscription as never;
		},
		workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
	};
}
