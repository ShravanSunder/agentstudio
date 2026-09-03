import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationSurfaceClient,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';

export class WorktreeAnnotationEditOwnershipController {
	readonly #annotationClient: WorktreeAnnotationSurfaceClient;
	readonly #editToken: string;
	readonly #messageId: string;
	#operationTail: Promise<void> = Promise.resolve();

	constructor(props: {
		readonly annotationClient: WorktreeAnnotationSurfaceClient;
		readonly editToken: string;
		readonly messageId: string;
	}) {
		this.#annotationClient = props.annotationClient;
		this.#editToken = props.editToken;
		this.#messageId = props.messageId;
	}

	acquire(): Promise<void> {
		return this.#enqueue(async (): Promise<void> => {
			const message = this.#currentMessage();
			if (message === null) throw new Error('Annotation message is unavailable.');
			if (message.draft === null || message.draft.activeEditToken === this.#editToken) return;
			const outcome = await this.#annotationClient.execute({
				editToken: this.#editToken,
				expectedDraftRevision: message.draft.revision,
				expectedMessageRevision: message.messageRevision,
				kind: 'draft.edit.acquire',
				messageId: message.messageId,
				sessionId: message.sessionId,
			});
			assertCommittedEditOwnershipOutcome(outcome);
			await this.#annotationClient.waitForSnapshot((snapshot) => {
				const acquiredMessage = messageById(snapshot.threads, this.#messageId);
				return acquiredMessage?.draft?.activeEditToken === this.#editToken ? acquiredMessage : null;
			});
		});
	}

	release(): Promise<void> {
		return this.#enqueue(async (): Promise<void> => {
			const message = this.#currentMessage();
			if (message?.draft?.activeEditToken !== this.#editToken) return;
			const outcome = await this.#annotationClient.execute({
				editToken: this.#editToken,
				expectedDraftRevision: message.draft.revision,
				expectedMessageRevision: message.messageRevision,
				kind: 'draft.edit.release',
				messageId: message.messageId,
				sessionId: message.sessionId,
			});
			assertCommittedEditOwnershipOutcome(outcome);
		});
	}

	#currentMessage(): WorktreeAnnotationMessageEntry | null {
		return messageById(this.#annotationClient.getSnapshot().threads, this.#messageId);
	}

	#enqueue(operation: () => Promise<void>): Promise<void> {
		const queued = this.#operationTail.then(operation, operation);
		this.#operationTail = queued.catch((): void => {});
		return queued;
	}
}

function messageById(
	threads: readonly WorktreeAnnotationThreadProjection[],
	messageId: string,
): WorktreeAnnotationMessageEntry | null {
	for (const thread of threads) {
		const message = thread.messages.find((candidate) => candidate.messageId === messageId);
		if (message !== undefined) return message;
	}
	return null;
}

function assertCommittedEditOwnershipOutcome(
	outcome: Awaited<ReturnType<WorktreeAnnotationSurfaceClient['execute']>>,
): void {
	if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
	if (outcome.status.kind !== 'committed') {
		throw new Error('Annotation edit ownership command did not commit.');
	}
}
