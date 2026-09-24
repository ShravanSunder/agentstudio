import type { BridgeCommWorkerFileQueryProjection } from './bridge-comm-worker-file-query-projection.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';
import type {
	BridgeFileCollectionSearchOutcome,
	BridgeWorkerFileCollectionSearchCommand,
} from './bridge-worker-file-collection-search-contracts.js';

/**
 * Answer a native collection search from the worker's listed rows. The
 * published viewer query, selection and tree are untouched; the answer names
 * the source generation it was computed from so native can reject it once
 * that source is replaced.
 */
export function answerBridgeWorkerFileCollectionSearch(props: {
	readonly command: BridgeWorkerFileCollectionSearchCommand;
	readonly projection: BridgeCommWorkerFileQueryProjection;
}): readonly BridgeWorkerServerToMainMessage[] {
	const search = props.projection.searchCollection(props.command.criteria);
	const outcome: BridgeFileCollectionSearchOutcome =
		search.source === null
			? { kind: 'noSource' }
			: search.result.kind === 'invalidPattern'
				? search.result
				: {
						complete: search.complete,
						kind: 'matches',
						matches: search.result.matches,
						membershipRevision: search.membershipRevision,
						source: search.source,
						totalMatchCount: search.result.totalMatchCount,
						truncated: search.result.truncated,
					};
	return [
		{
			direction: 'serverWorkerToMain',
			kind: 'fileCollectionSearch',
			outcome,
			requestId: props.command.requestId,
			transferDescriptors: [],
			wireVersion: 1,
		},
		buildBridgeWorkerReadyHealthEvent(props.command.requestId),
	];
}
