import type {
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';

export function isSelectedContentReadyPreparationCurrent(props: {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}): boolean {
	const state = props.store.getState();
	return (
		state.selectedId === props.itemId &&
		state.demandByKey.get(props.itemId) === `selected:${props.epoch}`
	);
}

export function readSelectedReviewDemandEpoch(state: BridgeCommWorkerStoreState): number | null {
	if (!state.selectedDemandEnabled || state.selectedId === null) return null;
	const selectedDemandKey = state.demandByKey.get(state.selectedId);
	const selectedDemandEpochMatch = /^selected:(\d+)$/u.exec(selectedDemandKey ?? '');
	return selectedDemandEpochMatch === null ? null : Number(selectedDemandEpochMatch[1]);
}
