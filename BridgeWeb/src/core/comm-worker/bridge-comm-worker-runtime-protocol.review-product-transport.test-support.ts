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
	readonly calledMethods?: string[];
	readonly initialReviewEpoch?: number;
	readonly onPanePresentationSink?: (
		sink: (frame: BridgeProductPanePresentationFrame) => void,
	) => void;
	readonly onCalledMethod?: ((method: string, request: unknown) => void) | undefined;
	readonly openedContentKinds?: string[];
	readonly reviewSubscription: BridgeProductSubscription<'review.metadata'>;
	readonly reviewAnnotationSubscription?: BridgeProductSubscription<'review.annotations'>;
	readonly subscribedKinds: string[];
}): BridgeProductTransportSession {
	let reviewEpoch = props.initialReviewEpoch ?? 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'review' ? reviewEpoch : 0;
		},
		call: async (...arguments_): Promise<never> => {
			const [method, request] = arguments_;
			props.calledMethods?.push(method);
			props.onCalledMethod?.(method, request);
			return { reason: 'notConfigured', status: 'unavailable' } as never;
		},
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
			if (subscriptionKind === 'review.annotations' && props.reviewAnnotationSubscription) {
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The optional Review annotation fixture matches the narrowed subscription branch.
				return props.reviewAnnotationSubscription as never;
			}
			if (subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') {
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- Generic transport fixtures close over the requested annotation subscription kind.
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
