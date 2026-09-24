import { useCallback, useEffect, useRef } from 'react';

import type { BridgeProductFileSelectionReceipt } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import type {
	BridgeFileViewerDisplaySource,
	BridgeFileViewerOpenState,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import type { BridgeFileViewerSelectionGateOutcome } from './bridge-file-viewer-selection-gate.js';

type BridgeFileViewerNavigationCommand = NonNullable<BridgeFileViewerAppProps['navigationCommand']>;

interface BridgeFileViewerNativeSelection {
	readonly commandId: string;
	readonly fileId: string;
}

export interface UseBridgeFileViewerSelectionReceiptsProps {
	readonly isActive: boolean;
	readonly openFileStatus: BridgeFileViewerOpenState['status'];
	readonly selection: BridgeFileViewerSelection | null;
	readonly sendFileSelectionReceipt: (receipt: BridgeProductFileSelectionReceipt) => void;
	readonly source: BridgeFileViewerDisplaySource | null;
}

export interface BridgeFileViewerSelectionReceipts {
	/**
	 * Track a native file navigation from the moment it enters the selection
	 * gate, so its displayed receipt carries the command id even when the file
	 * was already on screen.
	 */
	readonly trackNativeNavigation: (
		command: BridgeFileViewerNavigationCommand,
		selection: BridgeFileViewerSelection,
		outcome: Promise<BridgeFileViewerSelectionGateOutcome>,
	) => void;
	/** Settle a native file navigation whose target the unfiltered tree does not list. */
	readonly reportNativeNavigationNotListed: (command: BridgeFileViewerNavigationCommand) => void;
}

/**
 * Reports the File selection that actually reached the screen, so native can
 * record it through the navigation rules: `displayed` once its content is
 * ready, `unavailable` when it cannot render, and `refused` when a native
 * navigation could not leave a document whose editor failed to flush. A tree
 * highlight alone is never a receipt. Equal receipts are sent once.
 */
export function useBridgeFileViewerSelectionReceipts(
	props: UseBridgeFileViewerSelectionReceiptsProps,
): BridgeFileViewerSelectionReceipts {
	const { isActive, openFileStatus, selection, sendFileSelectionReceipt, source } = props;
	const nativeSelectionRef = useRef<BridgeFileViewerNativeSelection | null>(null);
	const lastReceiptKeyRef = useRef<string | null>(null);

	const trackNativeNavigation = useCallback(
		(
			command: BridgeFileViewerNavigationCommand,
			nextSelection: BridgeFileViewerSelection,
			outcome: Promise<BridgeFileViewerSelectionGateOutcome>,
		): void => {
			const nativeSelection: BridgeFileViewerNativeSelection = {
				commandId: command.commandId,
				fileId: nextSelection.fileId,
			};
			nativeSelectionRef.current = nativeSelection;
			void outcome.then((settledOutcome): void => {
				if (settledOutcome === 'committed') return;
				if (nativeSelectionRef.current === nativeSelection) nativeSelectionRef.current = null;
				if (settledOutcome !== 'refused') return;
				sendFileSelectionReceipt({
					displayPath: command.target.path,
					nativeNavigationCommandId: command.commandId,
					outcome: 'refused',
					source: {
						sourceId: command.source.sourceId,
						subscriptionGeneration: command.source.subscriptionGeneration,
					},
				});
			});
		},
		[sendFileSelectionReceipt],
	);

	const reportNativeNavigationNotListed = useCallback(
		(command: BridgeFileViewerNavigationCommand): void => {
			sendFileSelectionReceipt({
				displayPath: command.target.path,
				nativeNavigationCommandId: command.commandId,
				outcome: 'notListed',
				source: {
					sourceId: command.source.sourceId,
					subscriptionGeneration: command.source.subscriptionGeneration,
				},
			});
		},
		[sendFileSelectionReceipt],
	);

	useEffect((): void => {
		if (!isActive || selection === null || source === null) return;
		const outcome = selectionReceiptOutcome(openFileStatus);
		if (outcome === null) return;
		const nativeSelection = nativeSelectionRef.current;
		const nativeNavigationCommandId =
			nativeSelection?.fileId === selection.fileId ? nativeSelection.commandId : null;
		const receiptKey = [
			selection.fileId,
			source.sourceId,
			source.generation,
			nativeNavigationCommandId ?? '',
			outcome,
		].join('\u0000');
		if (lastReceiptKeyRef.current === receiptKey) return;
		lastReceiptKeyRef.current = receiptKey;
		sendFileSelectionReceipt({
			displayPath: selection.path,
			nativeNavigationCommandId,
			outcome,
			source: { sourceId: source.sourceId, subscriptionGeneration: source.generation },
		});
	}, [isActive, openFileStatus, selection, sendFileSelectionReceipt, source]);

	return { reportNativeNavigationNotListed, trackNativeNavigation };
}

function selectionReceiptOutcome(
	status: BridgeFileViewerOpenState['status'],
): BridgeProductFileSelectionReceipt['outcome'] | null {
	switch (status) {
		case 'ready':
			return 'displayed';
		case 'failed':
		case 'unavailable':
			return 'unavailable';
		case 'idle':
		case 'loading':
		case 'stale':
			return null;
	}
}
