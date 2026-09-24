/**
 * How one requested File selection change ended.
 *
 * - `committed`: the selection changed (or already named the file).
 * - `refused`: an active annotation editor could not be made durable, so the
 *   old document and its editor stay displayed.
 * - `superseded`: a newer selection request arrived while this one waited.
 * - `inactive`: the viewer stopped being active before the change applied.
 */
export type BridgeFileViewerSelectionGateOutcome =
	| 'committed'
	| 'inactive'
	| 'refused'
	| 'superseded';

export interface BridgeFileViewerSelectionGateRequest {
	/** The file currently displayed, or `null` when nothing is selected. */
	readonly currentFileId: string | null;
	/** The file to display, or `null` to clear the selection. */
	readonly nextFileId: string | null;
	/** Existing `draft.flush` preparation of every active annotation editor. */
	readonly prepareActiveEditors: () => Promise<boolean>;
	/** Apply the change; returns `false` when it can no longer apply. */
	readonly commit: () => boolean;
}

export interface BridgeFileViewerSelectionGate {
	readonly request: (
		request: BridgeFileViewerSelectionGateRequest,
	) => Promise<BridgeFileViewerSelectionGateOutcome>;
}

/**
 * The single File selection gate: every change that moves the displayed
 * document away from the current one waits for active editors to be flushed
 * first, so draft text is never lost to a navigation. Only the newest request
 * applies; an older request that finishes preparing late is dropped.
 */
export function createBridgeFileViewerSelectionGate(): BridgeFileViewerSelectionGate {
	let latestRequestSequence = 0;
	return {
		request: async (request): Promise<BridgeFileViewerSelectionGateOutcome> => {
			latestRequestSequence += 1;
			const requestSequence = latestRequestSequence;
			if (request.currentFileId === null || request.currentFileId === request.nextFileId) {
				return request.commit() ? 'committed' : 'inactive';
			}
			let prepared: boolean;
			try {
				prepared = await request.prepareActiveEditors();
			} catch {
				prepared = false;
			}
			if (requestSequence !== latestRequestSequence) return 'superseded';
			if (!prepared) return 'refused';
			return request.commit() ? 'committed' : 'inactive';
		},
	};
}
