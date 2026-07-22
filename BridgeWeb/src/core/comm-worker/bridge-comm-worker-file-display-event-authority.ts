import {
	BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT,
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerFileDisplayPatchEventSchema,
	type BridgeWorkerFileDisplayPatch,
	type BridgeWorkerFileDisplayPatchEvent,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerFileDisplayEventAuthorityProps {
	readonly createSequence: () => number;
}

export class BridgeCommWorkerFileDisplayEventAuthority {
	readonly #createSequence: () => number;
	#projectionRevision = 0;

	constructor(props: BridgeCommWorkerFileDisplayEventAuthorityProps) {
		this.#createSequence = props.createSequence;
	}

	publish(props: {
		readonly epoch: number;
		readonly patches: readonly BridgeWorkerFileDisplayPatch[];
	}): readonly BridgeWorkerFileDisplayPatchEvent[] {
		return this.#publishGroups(props.epoch, boundedFileDisplayPatchGroups(props.patches));
	}

	publishQueryTransaction(props: {
		readonly epoch: number;
		readonly patches: readonly BridgeWorkerFileDisplayPatch[];
		readonly transactionId: string;
	}): readonly BridgeWorkerFileDisplayPatchEvent[] {
		const patchGroups = boundedFileDisplayPatchGroups(props.patches);
		return this.#publishGroups(props.epoch, patchGroups, props.transactionId);
	}

	publishQueryAbort(props: {
		readonly epoch: number;
		readonly transactionId: string;
	}): BridgeWorkerFileDisplayPatchEvent {
		this.#projectionRevision += 1;
		return bridgeWorkerFileDisplayPatchEventSchema.parse({
			direction: 'serverWorkerToMain',
			epoch: props.epoch,
			kind: 'fileDisplayPatch',
			patches: [],
			projectionRevision: this.#projectionRevision,
			queryTransaction: { phase: 'abort', transactionId: props.transactionId },
			sequence: this.#createSequence(),
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});
	}

	#publishGroups(
		epoch: number,
		patchGroups: readonly (readonly BridgeWorkerFileDisplayPatch[])[],
		queryTransactionId?: string,
	): readonly BridgeWorkerFileDisplayPatchEvent[] {
		const events: BridgeWorkerFileDisplayPatchEvent[] = [];
		for (const [batchIndex, patchGroup] of patchGroups.entries()) {
			this.#projectionRevision += 1;
			events.push(
				bridgeWorkerFileDisplayPatchEventSchema.parse({
					direction: 'serverWorkerToMain',
					epoch,
					kind: 'fileDisplayPatch',
					patches: patchGroup,
					projectionRevision: this.#projectionRevision,
					...(queryTransactionId === undefined
						? {}
						: {
								queryTransaction: {
									batchCount: patchGroups.length,
									batchIndex,
									phase: 'batch',
									transactionId: queryTransactionId,
								},
							}),
					sequence: this.#createSequence(),
					surface: 'fileView',
					transferDescriptors: [],
					wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				}),
			);
		}
		return events;
	}
}

function boundedFileDisplayPatchGroups(
	patches: readonly BridgeWorkerFileDisplayPatch[],
): readonly (readonly BridgeWorkerFileDisplayPatch[])[] {
	const groups: BridgeWorkerFileDisplayPatch[][] = [];
	let scalarGroup: BridgeWorkerFileDisplayPatch[] = [];
	const flushScalarGroup = (): void => {
		if (scalarGroup.length === 0) return;
		groups.push(scalarGroup);
		scalarGroup = [];
	};
	for (const patch of patches) {
		if (patch.slice === 'fileTree' && patch.operation === 'batch') {
			flushScalarGroup();
			groups.push([patch]);
			continue;
		}
		scalarGroup.push(patch);
		if (scalarGroup.length === BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT) flushScalarGroup();
	}
	flushScalarGroup();
	return groups;
}
