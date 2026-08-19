import { describe, expect, test } from 'vitest';

import {
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { createWorktreeAnnotationSurfaceClient } from './worktree-annotation-surface-client.js';

describe('RecordingAnnotationBrowserSurface command correlation', () => {
	test('settles a named Save behind later background session requests', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('review');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		const rootPromise = client.execute({
			admission: { kind: 'implicitOrSingle' },
			body: 'Exact receipt draft',
			editToken: 'annotation-edit-test',
			kind: 'root.create',
			origin: {
				diffSide: 'additions',
				endLine: 3,
				kind: 'located',
				path: 'Sources/App.swift',
				sourceIdentity: 'source-1',
				sourceRole: 'reviewHead',
				startLine: 2,
			},
		});
		surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'root.create');
		const rootOutcome = await rootPromise;
		const rootReceipt = rootOutcome.receipt;
		if (rootReceipt === undefined) throw new Error('Expected exact root receipt.');
		// Act
		const savePromise = client.execute({
			editToken: 'annotation-edit-test',
			expectedDraftRevision: rootReceipt.draftRevision ?? 0,
			expectedSessionRevision: rootReceipt.sessionRevision,
			kind: 'draft.save',
			messageId: rootReceipt.messageId,
			sessionId: annotationSessionId,
		});
		const releaseDemand = client.acquireSession(annotationSessionId);
		surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
		const saveOutcome = await savePromise;

		// Assert
		expect(surface.sentOperations.at(-1)?.kind).toBe('output.history');
		expect(saveOutcome.status).toEqual({ kind: 'committed' });
		expect(saveOutcome.receipt).toMatchObject({
			draftRevision: null,
			kind: 'message',
			messageId: rootReceipt.messageId,
			savedRevision: 1,
		});
		releaseDemand();
		client.dispose();
	});
});
