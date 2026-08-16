import { describe, expect, test } from 'vitest';

import {
	bridgeProductContentIdentityFromDescriptor,
	bridgeProductContentRequestSchema,
	bridgeProductSurfaceForContentKind,
} from './bridge-product-content-contracts.js';
import { bridgeProductWorktreeAnnotationEventSchema } from './bridge-product-worktree-annotation-contracts.js';
import {
	bridgeProductAnnotationOutputContentDescriptorSchema,
	bridgeProductAnnotationOutputContentIdentitySchema,
} from './bridge-product-worktree-annotation-output-contracts.js';

const markdownDescriptor = {
	attemptId: '00000000-0000-7000-8000-000000000015',
	contentKind: 'annotation.output',
	contentType: 'text/markdown; charset=utf-8',
	declaredByteLength: 5,
	descriptorId: '00000000-0000-7000-8000-000000000016',
	encoding: 'utf-8',
	expectedSha256: 'a'.repeat(64),
	formatVersion: 1,
	maximumBytes: 5,
	outputKind: 'clipboard_markdown',
	surface: 'file',
} as const;

describe('Bridge product annotation output contracts', () => {
	test('accepts strict pre-attempt JSON destination outcomes without an output summary', () => {
		for (const outcome of [
			{ kind: 'destination_cancelled' },
			{
				kind: 'destination_selection_failed',
				selectionError: 'The save panel could not choose a destination.',
			},
		] as const) {
			const event = annotationProjectionEvent(outcome);
			expect(bridgeProductWorktreeAnnotationEventSchema.parse(event)).toEqual(event);
		}
	});

	test('rejects destination outcomes with summaries, missing errors, or unknown fields', () => {
		for (const invalidOutcome of [
			{ kind: 'destination_cancelled', summary: {} },
			{ kind: 'destination_selection_failed' },
			{ kind: 'destination_selection_failed', selectionError: '' },
			{
				kind: 'destination_selection_failed',
				selectionError: 'failed',
				unexpected: true,
			},
		] as const) {
			expect(
				bridgeProductWorktreeAnnotationEventSchema.safeParse(
					annotationProjectionEvent(invalidOutcome),
				).success,
			).toBe(false);
		}
	});

	test('keeps descriptor, identity, request, and surface strict and correlated', () => {
		const identity = bridgeProductContentIdentityFromDescriptor(markdownDescriptor);
		const request = {
			contentKind: 'annotation.output',
			contentRequestId: 'annotation-output-content-1',
			descriptor: markdownDescriptor,
			kind: 'content.open',
			leaseId: 'annotation-output-lease-1',
			paneSessionId: 'pane-session-1',
			wireVersion: 2,
			workerDerivationEpoch: 0,
			workerInstanceId: 'worker-instance-1',
		} as const;

		expect(bridgeProductAnnotationOutputContentDescriptorSchema.parse(markdownDescriptor)).toEqual(
			markdownDescriptor,
		);
		expect(bridgeProductAnnotationOutputContentIdentitySchema.parse(identity)).toEqual(identity);
		expect(bridgeProductContentRequestSchema.parse(request)).toEqual(request);
		expect(bridgeProductSurfaceForContentKind('annotation.output', identity)).toBe('file');
	});

	test('rejects unknown fields, unsupported versions, and inconsistent exact-byte metadata', () => {
		for (const invalidDescriptor of [
			{ ...markdownDescriptor, unexpected: true },
			{ ...markdownDescriptor, formatVersion: 2 },
			{ ...markdownDescriptor, declaredByteLength: 4 },
			{ ...markdownDescriptor, contentType: 'application/json; charset=utf-8' },
			{ ...markdownDescriptor, expectedSha256: 'not-a-digest' },
			{ ...markdownDescriptor, outputKind: 'json_file' },
		] as const) {
			expect(
				bridgeProductAnnotationOutputContentDescriptorSchema.safeParse(invalidDescriptor).success,
			).toBe(false);
		}
	});
});

function annotationProjectionEvent(outcome: unknown): Readonly<Record<string, unknown>> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes: [
				{
					requestId: 'annotation-output-request-1',
					sessionId: null,
					status: { kind: 'output', outcome },
					surface: 'file',
				},
			],
			outputHistory: [],
			recoveryStatus: 'available',
			revision: 1,
			sessions: [],
			worktreeId: 'worktree-1',
		},
	};
}
