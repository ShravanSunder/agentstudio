import type { BridgeAppControlCommand, BridgeAppControlProbe } from './bridge-app-control.js';

export interface BridgeAppControlProbeState {
	readonly fileClassFilter: BridgeAppControlProbe['fileClassFilter'];
	readonly gitStatusFilter: BridgeAppControlProbe['gitStatusFilter'];
	readonly renderMode: BridgeAppControlProbe['renderMode'];
	readonly selectedItemId: string | null;
	readonly treeSearchMode: BridgeAppControlProbe['treeSearchMode'];
	readonly treeSearchText: string;
}

export function publishBridgeAppControlProbe(props: {
	readonly command: BridgeAppControlCommand;
	readonly reason: string | null;
	readonly sequence: number;
	readonly state: BridgeAppControlProbeState;
	readonly status: BridgeAppControlProbe['status'];
}): void {
	if (typeof window === 'undefined') return;
	window.bridgeReviewControlProbe = {
		sequence: props.sequence,
		method: props.command.method,
		status: props.status,
		itemId: controlCommandItemId(props.command) ?? props.state.selectedItemId,
		path: props.command.method === 'bridge.fileTree.revealPath' ? props.command.path : null,
		treeSearchText: props.state.treeSearchText,
		treeSearchMode: props.state.treeSearchMode,
		gitStatusFilter: props.state.gitStatusFilter,
		fileClassFilter: props.state.fileClassFilter,
		renderMode: props.state.renderMode,
		reason: props.reason,
	};
}

export function nextBridgeAppControlProbeSequence(ref: { current: number }): number {
	ref.current += 1;
	return ref.current;
}

export const invalidBridgeAppControlProbeCommand: BridgeAppControlCommand = {
	method: 'bridge.fileTree.search',
	searchText: '',
	searchMode: { kind: 'text' },
};

function controlCommandItemId(command: BridgeAppControlCommand): string | null {
	switch (command.method) {
		case 'bridge.diff.scrollToFile':
		case 'bridge.diff.expandFile':
		case 'bridge.diff.collapseFile':
			return command.itemId;
		case 'bridge.fileView.showMarkdownPreview':
			return command.itemId ?? null;
		case 'bridge.fileTree.search':
		case 'bridge.fileTree.setFilter':
		case 'bridge.fileTree.revealPath':
			return null;
	}
	const exhaustiveCommand: never = command;
	void exhaustiveCommand;
	return null;
}
