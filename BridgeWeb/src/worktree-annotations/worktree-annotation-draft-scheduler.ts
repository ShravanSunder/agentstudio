export interface WorktreeAnnotationDraftClock {
	now(): number;
	schedule(delayMilliseconds: number, run: () => void): () => void;
}

export interface WorktreeAnnotationDraftSchedulerSnapshot {
	readonly currentBody: string;
	readonly lastAcknowledgedBody: string | null;
	readonly status: 'acknowledged' | 'failed' | 'idle' | 'persisting' | 'scheduled';
}

export interface WorktreeAnnotationDraftSchedulerProps {
	readonly clock: WorktreeAnnotationDraftClock;
	readonly persist: (body: string) => Promise<void>;
	readonly debounceMilliseconds?: number;
	readonly initialAcknowledgedBody?: string | null | undefined;
	readonly maximumWaitMilliseconds?: number;
	readonly persistFirstChangedEditImmediately?: boolean;
}

const defaultDraftDebounceMilliseconds = 1_000;
const defaultDraftMaximumWaitMilliseconds = 5_000;

export class WorktreeAnnotationDraftScheduler {
	readonly #clock: WorktreeAnnotationDraftClock;
	readonly #debounceMilliseconds: number;
	#emptyDraftPersistenceAllowed: boolean;
	readonly #maximumWaitMilliseconds: number;
	readonly #persist: (body: string) => Promise<void>;
	#cancelScheduledFlush: (() => void) | null = null;
	#currentBody = '';
	#dirtySinceMilliseconds: number | null = null;
	#hasAttemptedInitialPersist = false;
	#inFlight: Promise<void> | null = null;
	#inFlightBody: string | null = null;
	#lastAcknowledgedBody: string | null = null;
	#persistFirstChangedEditImmediately: boolean;
	#processedFirstChangedEdit = false;
	#status: WorktreeAnnotationDraftSchedulerSnapshot['status'] = 'idle';

	constructor(props: WorktreeAnnotationDraftSchedulerProps) {
		this.#clock = props.clock;
		this.#persist = props.persist;
		this.#emptyDraftPersistenceAllowed =
			props.initialAcknowledgedBody !== null && props.initialAcknowledgedBody !== undefined;
		if (props.initialAcknowledgedBody !== null && props.initialAcknowledgedBody !== undefined) {
			this.#currentBody = props.initialAcknowledgedBody;
			this.#hasAttemptedInitialPersist = true;
			this.#lastAcknowledgedBody = props.initialAcknowledgedBody;
			this.#status = 'acknowledged';
		}
		this.#debounceMilliseconds = props.debounceMilliseconds ?? defaultDraftDebounceMilliseconds;
		this.#maximumWaitMilliseconds =
			props.maximumWaitMilliseconds ?? defaultDraftMaximumWaitMilliseconds;
		this.#persistFirstChangedEditImmediately = props.persistFirstChangedEditImmediately ?? false;
	}

	edit(body: string): void {
		this.#currentBody = body;
		if (body === this.#lastAcknowledgedBody) {
			this.#cancelPendingFlush();
			this.#dirtySinceMilliseconds = null;
			this.#status = 'acknowledged';
			return;
		}
		if (this.#persistFirstChangedEditImmediately && !this.#processedFirstChangedEdit) {
			this.#processedFirstChangedEdit = true;
			void this.#flushCurrentBody().catch((): void => {});
			return;
		}
		if (!this.#hasAttemptedInitialPersist) {
			if (body.trim().length === 0) return;
			this.#hasAttemptedInitialPersist = true;
			void this.#flushCurrentBody().catch((): void => {});
			return;
		}
		this.#dirtySinceMilliseconds ??= this.#clock.now();
		this.#scheduleFlush();
	}

	adoptAcknowledgedBody(props: {
		readonly body: string;
		readonly preserveCurrentBody: boolean;
	}): void {
		this.#emptyDraftPersistenceAllowed = true;
		this.#hasAttemptedInitialPersist = true;
		this.#lastAcknowledgedBody = props.body;
		if (!props.preserveCurrentBody) this.#currentBody = props.body;
		if (this.#currentBody === this.#lastAcknowledgedBody) {
			this.#cancelPendingFlush();
			this.#dirtySinceMilliseconds = null;
			this.#status = 'acknowledged';
			return;
		}
		this.#dirtySinceMilliseconds ??= this.#clock.now();
		this.#scheduleFlush();
	}

	beginEditing(props: {
		readonly acknowledgedBody: string | null;
		readonly persistFirstChangedEditImmediately: boolean;
	}): void {
		this.#cancelPendingFlush();
		this.#currentBody = props.acknowledgedBody ?? '';
		this.#dirtySinceMilliseconds = null;
		this.#emptyDraftPersistenceAllowed = props.acknowledgedBody !== null;
		this.#hasAttemptedInitialPersist = props.acknowledgedBody !== null;
		this.#lastAcknowledgedBody = props.acknowledgedBody;
		this.#persistFirstChangedEditImmediately = props.persistFirstChangedEditImmediately;
		this.#processedFirstChangedEdit = false;
		this.#status = props.acknowledgedBody === null ? 'idle' : 'acknowledged';
	}

	async focusLost(): Promise<void> {
		await this.#flushUntilCurrentAcknowledged();
	}

	async save(saveCommittedDraft: () => Promise<void>): Promise<void> {
		await this.#flushUntilCurrentAcknowledged();
		await saveCommittedDraft();
	}

	snapshot(): WorktreeAnnotationDraftSchedulerSnapshot {
		return {
			currentBody: this.#currentBody,
			lastAcknowledgedBody: this.#lastAcknowledgedBody,
			status: this.#status,
		};
	}

	dispose(): void {
		this.#cancelPendingFlush();
	}

	async teardown(afterFlush?: () => Promise<void>): Promise<void> {
		this.#cancelPendingFlush();
		await this.#flushUntilCurrentAcknowledged();
		await afterFlush?.();
		this.dispose();
	}

	#scheduleFlush(): void {
		this.#cancelPendingFlush();
		const dirtySinceMilliseconds = this.#dirtySinceMilliseconds ?? this.#clock.now();
		const maximumWaitRemaining = Math.max(
			0,
			this.#maximumWaitMilliseconds - (this.#clock.now() - dirtySinceMilliseconds),
		);
		const delayMilliseconds = Math.min(this.#debounceMilliseconds, maximumWaitRemaining);
		this.#status = 'scheduled';
		this.#cancelScheduledFlush = this.#clock.schedule(delayMilliseconds, (): void => {
			this.#cancelScheduledFlush = null;
			void this.#flushCurrentBody().catch((): void => {});
		});
	}

	async #flushUntilCurrentAcknowledged(): Promise<void> {
		this.#cancelPendingFlush();
		if (!this.#currentBodyNeedsPersistence()) return;
		while (this.#currentBody !== this.#lastAcknowledgedBody) {
			await this.#flushCurrentBody();
		}
	}

	async #flushCurrentBody(): Promise<void> {
		if (this.#inFlight !== null) {
			const inFlightBody = this.#inFlightBody;
			try {
				await this.#inFlight;
			} catch (error: unknown) {
				if (this.#currentBody === inFlightBody) throw error;
			}
			if (this.#currentBody === this.#lastAcknowledgedBody) return;
		}
		const body = this.#currentBody;
		if (!this.#currentBodyNeedsPersistence()) return;
		this.#cancelPendingFlush();
		this.#dirtySinceMilliseconds = null;
		this.#status = 'persisting';
		const attempt = this.#persist(body)
			.then((): void => {
				this.#emptyDraftPersistenceAllowed = true;
				this.#lastAcknowledgedBody = body;
				this.#status = this.#currentBody === body ? 'acknowledged' : 'scheduled';
			})
			.catch((error: unknown): never => {
				this.#status = 'failed';
				throw error;
			})
			.finally((): void => {
				if (this.#inFlight === attempt) {
					this.#inFlight = null;
					this.#inFlightBody = null;
				}
				if (this.#currentBody !== this.#lastAcknowledgedBody && this.#status !== 'failed') {
					this.#dirtySinceMilliseconds ??= this.#clock.now();
					this.#scheduleFlush();
				}
			});
		this.#inFlight = attempt;
		this.#inFlightBody = body;
		await attempt;
	}

	#cancelPendingFlush(): void {
		this.#cancelScheduledFlush?.();
		this.#cancelScheduledFlush = null;
	}

	#currentBodyNeedsPersistence(): boolean {
		return (
			this.#currentBody !== this.#lastAcknowledgedBody &&
			(this.#currentBody.trim().length > 0 || this.#emptyDraftPersistenceAllowed)
		);
	}
}

export const browserWorktreeAnnotationDraftClock: WorktreeAnnotationDraftClock = {
	now: (): number => performance.now(),
	schedule: (delayMilliseconds, run): (() => void) => {
		const timeoutId = globalThis.setTimeout(run, delayMilliseconds);
		return (): void => globalThis.clearTimeout(timeoutId);
	},
};
