import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { WorktreeAnnotationCommandOutcome } from './worktree-annotation-surface-client.js';

const maximumViewedItemsPerCommand = 256;

export interface WorktreeAnnotationViewedMessage {
	readonly attentionState: 'new' | 'not_applicable' | 'viewed';
	readonly authorKind: 'agent' | 'human';
	readonly messageId: string;
	readonly savedBody: string | null;
	readonly savedRevision: number | null;
	readonly sessionId: string;
	readonly sessionRevision: number;
}

export interface WorktreeAnnotationViewedCommandResult {
	readonly failedGroupCount: number;
}

interface ViewedOverlay {
	readonly committedSessionRevision: number;
	readonly messageId: string;
	readonly savedRevision: number;
	readonly sessionId: string;
}

type ExecuteViewedOperation = (
	operation: Extract<
		BridgeProductWorktreeAnnotationOperation,
		{ readonly kind: 'message.viewed.mark' }
	>,
) => Promise<WorktreeAnnotationCommandOutcome>;

export class WorktreeAnnotationViewedController {
	readonly #execute: ExecuteViewedOperation;
	readonly #listeners = new Set<() => void>();
	readonly #inFlightByRevisionIdentity = new Map<string, Promise<boolean>>();
	readonly #overlaysByRevisionIdentity = new Map<string, ViewedOverlay>();
	readonly #requiredSessionRevisionBySessionId = new Map<string, number>();
	#revision = 0;

	constructor(execute: ExecuteViewedOperation) {
		this.#execute = execute;
	}

	getSnapshot = (): number => this.#revision;

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	dispose(): void {
		this.#inFlightByRevisionIdentity.clear();
		this.#overlaysByRevisionIdentity.clear();
		this.#requiredSessionRevisionBySessionId.clear();
		this.#listeners.clear();
	}

	reconcileProjection(
		sessionId: string,
		semanticRevision: number,
		messages: readonly WorktreeAnnotationViewedMessage[],
	): void {
		const requiredRevision = this.#requiredSessionRevisionBySessionId.get(sessionId);
		if (requiredRevision === undefined || semanticRevision < requiredRevision) return;
		let changed = false;
		for (const [identity, overlay] of this.#overlaysByRevisionIdentity) {
			if (overlay.sessionId !== sessionId) continue;
			const currentMessage = messages.find((message) => message.messageId === overlay.messageId);
			const contradictoryCurrentRevision =
				currentMessage?.savedRevision === overlay.savedRevision &&
				currentMessage.attentionState === 'new';
			if (contradictoryCurrentRevision) continue;
			this.#overlaysByRevisionIdentity.delete(identity);
			changed = true;
		}
		const retainsContradiction = [...this.#overlaysByRevisionIdentity.values()].some(
			(overlay) => overlay.sessionId === sessionId,
		);
		if (!retainsContradiction) {
			this.#requiredSessionRevisionBySessionId.delete(sessionId);
			changed = true;
		}
		if (changed) this.#notify();
	}

	presentMessage<TMessage extends WorktreeAnnotationViewedMessage>(message: TMessage): TMessage {
		if (!isCurrentNewAgentMessage(message)) return message;
		return this.#overlaysByRevisionIdentity.has(
			revisionIdentity(message.messageId, message.savedRevision),
		)
			? { ...message, attentionState: 'viewed' }
			: message;
	}

	isOutputReady(
		sessionId: string,
		semanticRevision: number,
		messages: readonly WorktreeAnnotationViewedMessage[],
	): boolean {
		const requiredRevision = this.#requiredSessionRevisionBySessionId.get(sessionId);
		if (requiredRevision === undefined) return true;
		if (semanticRevision < requiredRevision) return false;
		const currentMessagesByIdentity = new Map(
			messages
				.filter((message): boolean => message.sessionId === sessionId)
				.map((message) => [revisionIdentity(message.messageId, message.savedRevision), message]),
		);
		for (const overlay of this.#overlaysByRevisionIdentity.values()) {
			if (overlay.sessionId !== sessionId) continue;
			const projected = currentMessagesByIdentity.get(
				revisionIdentity(overlay.messageId, overlay.savedRevision),
			);
			if (projected?.attentionState === 'new') return false;
		}
		return true;
	}

	async markMessagesViewed(
		sessionId: string,
		messages: readonly WorktreeAnnotationViewedMessage[],
	): Promise<WorktreeAnnotationViewedCommandResult> {
		const items = uniqueCurrentNewAgentItems(messages);
		let failedGroupCount = 0;
		for (let offset = 0; offset < items.length; offset += maximumViewedItemsPerCommand) {
			const group = items.slice(offset, offset + maximumViewedItemsPerCommand);
			const existing = group
				.map((item) =>
					this.#inFlightByRevisionIdentity.get(
						revisionIdentity(item.messageId, item.expectedSavedRevision),
					),
				)
				.filter((promise): promise is Promise<boolean> => promise !== undefined);
			const newGroup = group.filter(
				(item) =>
					!this.#inFlightByRevisionIdentity.has(
						revisionIdentity(item.messageId, item.expectedSavedRevision),
					),
			);
			if (newGroup.length > 0) {
				const dispatch = this.#dispatchGroup(sessionId, newGroup);
				for (const item of newGroup) {
					this.#inFlightByRevisionIdentity.set(
						revisionIdentity(item.messageId, item.expectedSavedRevision),
						dispatch,
					);
				}
				existing.push(dispatch);
			}
			// oxlint-disable-next-line no-await-in-loop -- Viewed groups must settle sequentially without retry.
			const groupSucceeded = (await Promise.all(existing)).every(Boolean);
			if (!groupSucceeded) failedGroupCount += 1;
		}
		return { failedGroupCount };
	}

	async #dispatchGroup(
		sessionId: string,
		group: Array<{ readonly expectedSavedRevision: number; readonly messageId: string }>,
	): Promise<boolean> {
		try {
			const outcome = await this.#execute({ items: group, kind: 'message.viewed.mark', sessionId });
			if (!viewedResultsMatchGroup(outcome, group, sessionId)) return false;
			for (const result of outcome.status.results) {
				if (result.kind !== 'viewed') continue;
				const identity = revisionIdentity(result.messageId, result.savedRevision);
				this.#overlaysByRevisionIdentity.set(identity, {
					committedSessionRevision: result.committedSessionRevision,
					messageId: result.messageId,
					savedRevision: result.savedRevision,
					sessionId,
				});
				this.#requiredSessionRevisionBySessionId.set(
					sessionId,
					Math.max(
						this.#requiredSessionRevisionBySessionId.get(sessionId) ?? 0,
						result.committedSessionRevision,
					),
				);
			}
			this.#notify();
			return true;
		} catch {
			return false;
		} finally {
			for (const item of group) {
				this.#inFlightByRevisionIdentity.delete(
					revisionIdentity(item.messageId, item.expectedSavedRevision),
				);
			}
		}
	}

	#notify(): void {
		this.#revision += 1;
		for (const listener of this.#listeners) listener();
	}
}

function viewedResultsMatchGroup(
	outcome: WorktreeAnnotationCommandOutcome,
	group: readonly { readonly expectedSavedRevision: number; readonly messageId: string }[],
	sessionId: string,
): outcome is WorktreeAnnotationCommandOutcome & { readonly status: { readonly kind: 'viewed' } } {
	if (
		outcome.sessionId !== sessionId ||
		outcome.status.kind !== 'viewed' ||
		outcome.status.results.length !== group.length
	)
		return false;
	return outcome.status.results.every((result, index) => {
		const requested = group[index];
		if (requested === undefined || result.messageId !== requested.messageId) return false;
		const resultRevision =
			result.kind === 'viewed' ? result.savedRevision : result.expectedSavedRevision;
		return resultRevision === requested.expectedSavedRevision;
	});
}

function uniqueCurrentNewAgentItems(
	messages: readonly WorktreeAnnotationViewedMessage[],
): Array<{ readonly expectedSavedRevision: number; readonly messageId: string }> {
	const identities = new Set<string>();
	const items: Array<{ readonly expectedSavedRevision: number; readonly messageId: string }> = [];
	for (const message of messages) {
		if (!isCurrentNewAgentMessage(message)) continue;
		const identity = revisionIdentity(message.messageId, message.savedRevision);
		if (identities.has(identity)) continue;
		identities.add(identity);
		items.push({ expectedSavedRevision: message.savedRevision, messageId: message.messageId });
	}
	return items;
}

function isCurrentNewAgentMessage(
	message: WorktreeAnnotationViewedMessage,
): message is WorktreeAnnotationViewedMessage & { readonly savedRevision: number } {
	return (
		message.authorKind === 'agent' &&
		message.attentionState === 'new' &&
		message.savedBody !== null &&
		message.savedRevision !== null
	);
}

function revisionIdentity(messageId: string, savedRevision: number | null): string {
	return `${messageId}:${savedRevision ?? 'none'}`;
}
