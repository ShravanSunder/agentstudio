import { describe, expect, test, vi } from 'vitest';

import {
	WorktreeAnnotationDraftScheduler,
	type WorktreeAnnotationDraftClock,
} from './worktree-annotation-draft-scheduler.js';

describe('WorktreeAnnotationDraftScheduler', () => {
	test('persists the first non-empty edit immediately and suppresses acknowledged equality', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
			},
		});

		scheduler.edit('');
		scheduler.edit('First');
		await clock.flushMicrotasks();
		scheduler.edit('First');
		clock.advanceBy(5_000);

		expect(persistedBodies).toEqual(['First']);
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'First',
			lastAcknowledgedBody: 'First',
			status: 'acknowledged',
		});
	});

	test('reschedules failed pending intent when projection transport recovers', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		let transportAvailable = false;
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
				if (!transportAvailable) throw new Error('transport unavailable');
			},
		});

		scheduler.edit('Pending body');
		await clock.flushMicrotasks();
		expect(scheduler.snapshot().status).toBe('failed');
		transportAvailable = true;
		scheduler.retryFailedPersistence();
		clock.advanceBy(1_000);
		await clock.flushMicrotasks();

		expect(persistedBodies).toEqual(['Pending body', 'Pending body']);
		expect(scheduler.snapshot().status).toBe('acknowledged');
	});

	test('debounces focused edits at one second and enforces a five-second maximum wait', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
			},
		});
		scheduler.edit('First');
		await clock.flushMicrotasks();

		for (let editIndex = 1; editIndex <= 6; editIndex += 1) {
			scheduler.edit(`Edit ${editIndex}`);
			clock.advanceBy(900);
			await clock.flushMicrotasks();
		}

		expect(persistedBodies).toEqual(['First', 'Edit 6']);
	});

	test('flushes on focus loss and waits for the latest committed body before Save', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		const save = vi.fn<() => Promise<void>>(async (): Promise<void> => {});
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
			},
		});
		scheduler.edit('First');
		await clock.flushMicrotasks();
		scheduler.edit('Blurred body');
		await scheduler.focusLost();
		scheduler.edit('Saved body');

		await scheduler.save(save);

		expect(persistedBodies).toEqual(['First', 'Blurred body', 'Saved body']);
		expect(save).toHaveBeenCalledOnce();
	});

	test('focus loss returns without persistence for an untouched blank composer', async () => {
		const clock = new ControlledDraftClock();
		const persist = vi.fn<(body: string) => Promise<void>>(async (): Promise<void> => {});
		const scheduler = new WorktreeAnnotationDraftScheduler({ clock, persist });

		await scheduler.focusLost();

		expect(persist).not.toHaveBeenCalled();
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: '',
			lastAcknowledgedBody: null,
			status: 'idle',
		});
	});

	test('persists an empty working draft when editing an existing saved body', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			initialAcknowledgedBody: 'Saved body',
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
			},
		});

		scheduler.edit('');
		await scheduler.focusLost();

		expect(persistedBodies).toEqual(['']);
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: '',
			lastAcknowledgedBody: '',
			status: 'acknowledged',
		});
	});

	test('persists the first changed saved-message edit immediately, including an empty edit', async () => {
		const clock = new ControlledDraftClock();
		const persistedBodies: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			initialAcknowledgedBody: 'Saved body',
			persistFirstChangedEditImmediately: true,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
			},
		});

		scheduler.edit('');
		await clock.flushMicrotasks();

		expect(persistedBodies).toEqual(['']);
	});

	test('flushes a cleared durable never-saved draft before teardown and then releases ownership', async () => {
		const clock = new ControlledDraftClock();
		const events: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			initialAcknowledgedBody: 'Durable draft',
			persist: async (body): Promise<void> => {
				events.push(`persist:${body}`);
			},
		});
		scheduler.edit('');

		await scheduler.teardown(async (): Promise<void> => {
			events.push('release');
		});

		expect(events).toEqual(['persist:', 'release']);
	});

	test('adopts a late durable acknowledgement without overwriting newer local input', () => {
		const clock = new ControlledDraftClock();
		const persist = vi.fn<(body: string) => Promise<void>>(async (): Promise<void> => {});
		const scheduler = new WorktreeAnnotationDraftScheduler({ clock, persist });

		scheduler.adoptAcknowledgedBody({ body: 'Durable body', preserveCurrentBody: false });
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'Durable body',
			lastAcknowledgedBody: 'Durable body',
			status: 'acknowledged',
		});

		scheduler.edit('Newer local body');
		scheduler.adoptAcknowledgedBody({ body: 'Durable body', preserveCurrentBody: true });
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'Newer local body',
			lastAcknowledgedBody: 'Durable body',
			status: 'scheduled',
		});
	});

	test('retains editor text and permits retry after a rejected flush', async () => {
		const clock = new ControlledDraftClock();
		let attemptCount = 0;
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (): Promise<void> => {
				attemptCount += 1;
				if (attemptCount === 1) throw new Error('conflict');
			},
		});

		scheduler.edit('Keep this text');
		await clock.flushMicrotasks();
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'Keep this text',
			status: 'failed',
		});

		await scheduler.focusLost();
		expect(attemptCount).toBe(2);
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'Keep this text',
			lastAcknowledgedBody: 'Keep this text',
			status: 'acknowledged',
		});
	});

	test('retries the latest focused edit after an older in-flight flush is rejected', async () => {
		const clock = new ControlledDraftClock();
		const firstAttempt = deferredPromise();
		const secondAttemptStarted = deferredPromise();
		const persistedBodies: string[] = [];
		const scheduler = new WorktreeAnnotationDraftScheduler({
			clock,
			persist: async (body): Promise<void> => {
				persistedBodies.push(body);
				if (persistedBodies.length === 1) await firstAttempt.promise;
				if (persistedBodies.length === 2) secondAttemptStarted.resolve();
			},
		});

		scheduler.edit('First in flight');
		scheduler.edit('Newest focused edit');
		clock.advanceBy(1_000);
		firstAttempt.reject(new Error('conflict'));
		await secondAttemptStarted.promise;
		await clock.flushMicrotasks();

		expect(persistedBodies).toEqual(['First in flight', 'Newest focused edit']);
		expect(scheduler.snapshot()).toMatchObject({
			currentBody: 'Newest focused edit',
			lastAcknowledgedBody: 'Newest focused edit',
			status: 'acknowledged',
		});
	});
});

function deferredPromise(): {
	readonly promise: Promise<void>;
	readonly reject: (error: Error) => void;
	readonly resolve: () => void;
} {
	let resolvePromise: () => void = (): void => {};
	let rejectPromise: (error: Error) => void = (): void => {};
	const promise = new Promise<void>((resolve, reject): void => {
		resolvePromise = resolve;
		rejectPromise = reject;
	});
	return { promise, reject: rejectPromise, resolve: resolvePromise };
}

class ControlledDraftClock implements WorktreeAnnotationDraftClock {
	#nowMilliseconds = 0;
	#nextTimerId = 0;
	readonly #timers = new Map<number, { readonly deadline: number; readonly run: () => void }>();

	now(): number {
		return this.#nowMilliseconds;
	}

	schedule(delayMilliseconds: number, run: () => void): () => void {
		this.#nextTimerId += 1;
		const timerId = this.#nextTimerId;
		this.#timers.set(timerId, {
			deadline: this.#nowMilliseconds + delayMilliseconds,
			run,
		});
		return (): void => {
			this.#timers.delete(timerId);
		};
	}

	advanceBy(milliseconds: number): void {
		const target = this.#nowMilliseconds + milliseconds;
		while (true) {
			const nextTimer = [...this.#timers.entries()]
				.filter(([, timer]) => timer.deadline <= target)
				.sort((left, right): number => left[1].deadline - right[1].deadline)[0];
			if (nextTimer === undefined) break;
			this.#nowMilliseconds = nextTimer[1].deadline;
			this.#timers.delete(nextTimer[0]);
			nextTimer[1].run();
		}
		this.#nowMilliseconds = target;
	}

	async flushMicrotasks(): Promise<void> {
		await Promise.resolve();
		await Promise.resolve();
	}
}
