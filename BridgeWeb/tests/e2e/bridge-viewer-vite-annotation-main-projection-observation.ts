import type { Page, Response } from 'playwright';

// Test-only observation of the actual Main projection owner, never a replacement store.
export function observeAnnotationMainProjection(page: Page): {
	readonly install: () => Promise<void>;
} {
	let moduleUrl: string | null = null;
	const observeResponse = (response: Response): void => {
		if (new URL(response.url()).pathname.endsWith('/worktree-annotation-projection-store.ts')) {
			moduleUrl = response.url();
		}
	};
	page.on('response', observeResponse);
	return {
		install: async (): Promise<void> => {
			page.off('response', observeResponse);
			if (moduleUrl === null)
				throw new Error('Main annotation observer did not see the live store module.');
			// Native browser import avoids Vite SSR rewriting a serialized callback's imports.
			await page.evaluate(`(async () => {
				const { WorktreeAnnotationProjectionStore } = await import(${JSON.stringify(moduleUrl)});
				const observations = [];
				const stores = new Set();
				const summarize = store => {
					const snapshot = store.getSnapshot();
					return {
						operationCorrelationId: snapshot.operationCorrelationId,
						revision: snapshot.revision, sourceGeneration: snapshot.sourceGeneration,
						presentationRevision: snapshot.presentationRevision, readStatus: snapshot.readStatus,
						application: snapshot.reviewAnnotationApplication === null ? null : {
							applicationId: snapshot.reviewAnnotationApplication.applicationId,
							affectedItemCount: snapshot.reviewAnnotationApplication.affectedItemIds?.length ?? null,
							changedThreadCount: snapshot.reviewAnnotationApplication.changedThreadOwnerContexts.length
						},
						sessions: snapshot.sessions.slice(0, 8).map(session => ({
							sessionId: session.sessionId, lifecycle: session.lifecycle,
							sourceRelationship: session.sourceRelationship, semanticRevision: session.semanticRevision
						})),
						threads: [...snapshot.threads, ...snapshot.commandConfirmedThreads].slice(0, 8).map(thread => ({
							threadId: thread.context.threadId, placement: thread.context.placement,
							sourceRole: thread.context.sourceRole, startLine: thread.context.startLine,
							endLine: thread.context.endLine, messageCount: thread.messages.length,
							sessionIds: [...new Set(thread.messages.map(message => message.sessionId))]
						}))
					};
				};
				for (const method of ['apply', 'applyCatalogStaging', 'recordCommandOutcome', 'prepareForWorkerReplacement', 'markRefreshing', 'markUnavailable']) {
					const original = WorktreeAnnotationProjectionStore.prototype[method];
					WorktreeAnnotationProjectionStore.prototype[method] = function (...args) {
						const result = original.apply(this, args);
						stores.add(this);
						observations.push({ method, result: typeof result === 'boolean' ? result : result?.status ?? null,
							atMilliseconds: Math.round(performance.now()), snapshot: summarize(this) });
						if (observations.length > 24) observations.shift();
						return result;
					};
				}
				Object.defineProperty(globalThis, '__bridgeAnnotationMainProjectionObservation', {
					get: () => ({ observations, current: [...stores].map(summarize) })
				});
			})()`);
		},
	};
}

export async function readAnnotationMainProjectionObservation(page: Page): Promise<unknown> {
	return await page.evaluate((): unknown =>
		Reflect.get(globalThis, '__bridgeAnnotationMainProjectionObservation'),
	);
}
