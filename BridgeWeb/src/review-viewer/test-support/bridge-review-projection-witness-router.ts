import { BridgeCommWorkerReviewQueryProjection } from '../../core/comm-worker/bridge-comm-worker-review-query-projection.js';
import type {
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from '../../core/comm-worker/bridge-worker-rpc-client.js';

type ReviewProjectionUpdateCommand = Extract<
	BridgeWorkerRpcCommandInput,
	{ readonly command: 'reviewProjectionUpdate' }
>;

export class BridgeReviewProjectionWitnessRouter {
	#listener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	#latestProjectionRevision = 0;
	#latestSequence = 0;
	readonly #projection = new BridgeCommWorkerReviewQueryProjection();

	clearListener(listener: (message: BridgeWorkerServerToMainMessage) => void): void {
		if (this.#listener === listener) this.#listener = null;
	}

	publishQuery(command: ReviewProjectionUpdateCommand): void {
		const patches = this.#projection.updateQuery(command.query);
		if (patches.length === 0 || this.#listener === null) return;
		this.#latestProjectionRevision += 1;
		this.#latestSequence += 1;
		this.#listener({
			direction: 'serverWorkerToMain',
			epoch: command.epoch,
			kind: 'reviewDisplayPatch',
			patches,
			projectionRevision: this.#latestProjectionRevision,
			sequence: this.#latestSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	publishRaw(event: BridgeWorkerReviewDisplayPatchEvent): void {
		this.#latestProjectionRevision = Math.max(
			this.#latestProjectionRevision,
			event.projectionRevision,
		);
		this.#latestSequence = Math.max(this.#latestSequence, event.sequence);
		this.#listener?.({
			...event,
			patches: this.#projection.applyDisplayPatches(event.patches),
		});
	}

	setListener(listener: (message: BridgeWorkerServerToMainMessage) => void): void {
		this.#listener = listener;
	}
}
