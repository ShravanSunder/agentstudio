import { describe, expect, test } from 'vitest';

import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import {
	bridgeProductCallRequestSchema,
	bridgeProductCallResultSchema,
	bridgeProductFileSourceCurrentRequestSchema,
	bridgeProductFileSourceCurrentResultSchema,
	bridgeProductWorktreeAnnotationOutputInspectResultSchema,
	bridgeProductReviewComparisonUpdateRequestSchema,
	bridgeProductReviewComparisonTargetsQueryResultSchema,
	bridgeProductReviewIntakeReadyRequestSchema,
	bridgeProductReviewPublicationAppliedRequestSchema,
	bridgeProductReviewPublicationInstallAdmissionRequestSchema,
	bridgeProductReviewPublicationInstallAdmissionResultSchema,
} from './bridge-product-call-contracts.js';
import { BRIDGE_PRODUCT_MAXIMUM_REVIEW_COMPARISON_TARGET_BYTES } from './bridge-product-content-contracts.js';

const currentFileSource = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: '00000000-0000-4000-8000-000000000001',
	rootPathToken: 'root-token-1',
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge product call contracts', () => {
	test('returns current source authority instead of a generic stale projection error', () => {
		for (const method of [
			'file.annotations.projection.query',
			'review.annotations.projection.query',
		] as const) {
			const result = {
				method,
				result: { currentSourceGeneration: 12, kind: 'source_stale' },
			} as const;

			expect(bridgeProductCallResultSchema.parse(result)).toEqual(result);
			expect(
				bridgeProductCallResultSchema.safeParse({
					...result,
					result: { currentSourceGeneration: -1, kind: 'source_stale' },
				}).success,
			).toBe(false);
		}
	});

	test('defines paired strict annotation commands with no delete operation', () => {
		for (const method of ['file.annotations.command', 'review.annotations.command'] as const) {
			const request = { method, request: { operation: { kind: 'session.discover' } } } as const;
			const result = {
				method,
				result: {
					kind: 'completed',
					outcome: {
						requestId: 'annotation-product-call-1',
						sessionId: null,
						status: { kind: 'committed' },
						surface: method === 'file.annotations.command' ? 'file' : 'review',
					},
				},
			} as const;

			expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
			expect(bridgeProductCallResultSchema.parse(result)).toEqual(result);
			expect(
				bridgeProductCallResultSchema.safeParse({
					method,
					result: { kind: 'completed' },
				}).success,
			).toBe(false);
			expect(
				bridgeProductCallRequestSchema.safeParse({
					...request,
					request: { ...request.request, unexpected: true },
				}).success,
			).toBe(false);
			expect(
				bridgeProductCallRequestSchema.safeParse({
					...request,
					request: { operation: { kind: 'thread.delete' } },
				}).success,
			).toBe(false);
		}
	});

	test('covers the complete PR1 annotation operation vocabulary', () => {
		const sessionId = '00000000-0000-7000-8000-000000000011';
		const threadId = '00000000-0000-7000-8000-000000000012';
		const messageId = '00000000-0000-7000-8000-000000000013';
		const attemptId = '00000000-0000-7000-8000-000000000015';
		const operations = [
			{ kind: 'session.discover' },
			{ kind: 'demand.acquire', sessionId },
			{ kind: 'demand.release', sessionId },
			{
				admission: { kind: 'implicitOrSingle' },
				body: 'Durable draft',
				editToken: 'edit-token-1',
				kind: 'root.create',
				origin: {
					diffSide: 'additions',
					endLine: 14,
					kind: 'located',
					path: 'Sources/Feature.swift',
					sourceIdentity: 'source-1',
					sourceRole: 'reviewHead',
					startLine: 12,
				},
			},
			{
				body: 'Reply draft',
				editToken: 'edit-token-2',
				expectedThreadRevision: 4,
				kind: 'reply.create',
				sessionId,
				threadId,
			},
			{
				body: 'Updated draft',
				editToken: 'edit-token-1',
				expectedDraftRevision: 2,
				expectedMessageRevision: 4,
				kind: 'draft.flush',
				messageId,
				sessionId,
			},
			{
				body: '',
				editToken: 'edit-token-1',
				expectedDraftRevision: 3,
				expectedMessageRevision: 4,
				kind: 'draft.flush',
				messageId,
				sessionId,
			},
			{
				editToken: 'edit-token-1',
				expectedDraftRevision: 3,
				expectedMessageRevision: 4,
				kind: 'draft.edit.acquire',
				messageId,
				sessionId,
			},
			{
				editToken: 'edit-token-1',
				expectedDraftRevision: 3,
				expectedMessageRevision: 4,
				kind: 'draft.edit.release',
				messageId,
				sessionId,
			},
			{
				editToken: 'edit-token-1',
				expectedDraftRevision: 3,
				expectedMessageRevision: 4,
				kind: 'draft.save',
				messageId,
				sessionId,
			},
			{
				editToken: 'edit-token-1',
				expectedDraftRevision: 3,
				expectedMessageRevision: 4,
				kind: 'draft.revert',
				messageId,
				sessionId,
			},
			{
				expectedThreadRevision: 4,
				kind: 'thread.resolution.set',
				resolution: 'resolved',
				sessionId,
				threadId,
			},
			{
				decision: 'acceptCurrentSource',
				expectedSessionRevision: 4,
				kind: 'continuity.choose',
				sessionId,
			},
			{ kind: 'source.refresh', sessionId, sourceEpoch: 5 },
			{
				displayedProjectionRevision: 9,
				expectedSessionRevision: 4,
				kind: 'output.scope.commit',
				outputKind: 'clipboardMarkdown',
				scope: 'new',
				sessionId,
				sourceGeneration: 7,
			},
			{ attemptId, expectedSessionRevision: 4, kind: 'output.handled.clear' },
			{ kind: 'output.history', sessionId },
			{ attemptId, kind: 'output.repeat' },
			{ kind: 'recovery.acknowledge' },
		] as const;

		for (const operation of operations) {
			expect(
				bridgeProductCallRequestSchema.safeParse({
					method: 'review.annotations.command',
					request: { operation },
				}).success,
			).toBe(true);
		}

		for (const operation of [
			{ attemptId, kind: 'output.inspect' },
			{
				kind: 'output.selection.begin',
				outputKind: 'clipboardMarkdown',
				selectionMode: 'explicit',
				sessionId,
				transferId: 'transfer-1',
			},
			{
				confirmsUnresolvedWork: true,
				expectedOpenThreadCount: 2,
				expectedSessionRevision: 4,
				kind: 'session.lifecycle.set',
				lifecycle: 'completed',
				sessionId,
			},
			{
				displayedProjectionRevision: 9,
				expectedSessionRevision: 4,
				kind: 'output.scope.commit',
				outputKind: 'clipboardMarkdown',
				scope: 'new',
				sessionId,
			},
			{
				kind: 'output.selection.begin',
				outputKind: 'clipboardMarkdown',
				selectionMode: 'explicit',
				selectedVersions: [{ messageId, versionId: messageId }],
				sessionId,
				transferId: 'transfer-1',
			},
			{ kind: 'source.refresh', sessionId, sourceEpoch: -1 },
			{ kind: 'source.refresh', sessionId, sourceEpoch: 5, unexpected: true },
		] as const) {
			expect(
				bridgeProductCallRequestSchema.safeParse({
					method: 'review.annotations.command',
					request: { operation },
				}).success,
			).toBe(false);
		}
	});

	test('defines paired surface-bound annotation output inspection calls', () => {
		const attemptId = '00000000-0000-7000-8000-000000000015';
		const descriptor = {
			attemptId,
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

		for (const [method, surface] of [
			['file.annotations.output.inspect', 'file'],
			['review.annotations.output.inspect', 'review'],
		] as const) {
			const surfaceDescriptor = { ...descriptor, surface } as const;
			const request = { method, request: { attemptId } } as const;
			const result = { method, result: { descriptor: surfaceDescriptor } } as const;

			expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
			expect(bridgeProductCallResultSchema.parse(result)).toEqual(result);
			expect(bridgeProductWorktreeAnnotationOutputInspectResultSchema.parse(result.result)).toEqual(
				result.result,
			);
			expect(
				bridgeProductCallResultSchema.safeParse({
					...result,
					result: {
						descriptor: {
							...surfaceDescriptor,
							surface: surface === 'file' ? 'review' : 'file',
						},
					},
				}).success,
			).toBe(false);
		}
	});

	test('defines paired bounded annotation output candidate query calls', () => {
		const sessionId = '00000000-0000-7000-8000-000000000011';
		const candidate = {
			authoredAt: 1,
			endLine: 12,
			excerpt: 'Keep the owner',
			flatOrdinal: 0,
			location: 'current',
			messageId: '00000000-0000-7000-8000-000000000013',
			path: 'Sources/Feature.swift',
			placement: 'exact',
			startLine: 12,
			state: 'eligible',
			threadId: '00000000-0000-7000-8000-000000000012',
		} as const;
		for (const method of [] as const) {
			const request = {
				method,
				request: {
					cursor: { kind: 'start' as const },
					expectedSessionRevision: 4,
					limit: 16,
					sessionId,
				},
			};
			const result = {
				method,
				result: {
					candidates: [candidate],
					eligibleMessageCount: 1,
					eligibleWithoutInlinePlacementCount: 0,
					nextCursor: null,
					sessionId,
					sessionRevision: 4,
				},
			};
			expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
			expect(bridgeProductCallResultSchema.parse(result)).toEqual(result);
		}
	});

	test('defines a strict closed File source discovery call', () => {
		const request = { method: 'file.source.current', request: {} } as const;
		const availableResult = {
			method: 'file.source.current',
			result: { source: currentFileSource, status: 'available' },
		} as const;
		const unavailableResult = {
			method: 'file.source.current',
			result: { reason: 'no-file-source-authority', status: 'unavailable' },
		} as const;

		expect(bridgeProductFileSourceCurrentRequestSchema.parse(request.request)).toEqual({});
		expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
		expect(bridgeProductFileSourceCurrentResultSchema.parse(availableResult.result)).toEqual(
			availableResult.result,
		);
		expect(bridgeProductFileSourceCurrentResultSchema.parse(unavailableResult.result)).toEqual(
			unavailableResult.result,
		);
		expect(bridgeProductCallResultSchema.parse(availableResult)).toEqual(availableResult);
		expect(bridgeProductCallResultSchema.parse(unavailableResult)).toEqual(unavailableResult);

		for (const invalidRequest of [{ extra: true }, { source: currentFileSource }, null]) {
			expect(bridgeProductFileSourceCurrentRequestSchema.safeParse(invalidRequest).success).toBe(
				false,
			);
		}
		for (const invalidResult of [
			{ status: 'available' },
			{ source: { ...currentFileSource, freshness: 'cached' }, status: 'available' },
			{ reason: 'temporarily-unavailable', status: 'unavailable' },
			{ reason: 'no-file-source-authority', source: currentFileSource, status: 'unavailable' },
		]) {
			expect(bridgeProductFileSourceCurrentResultSchema.safeParse(invalidResult).success).toBe(
				false,
			);
		}
	});

	test('parses the shared File source discovery corpus through the closed call schemas', () => {
		for (const testCase of validProductSessionCorpus.fileSourceCurrentCases) {
			expect(bridgeProductCallRequestSchema.parse(testCase.request)).toEqual(testCase.request);
			expect(bridgeProductCallResultSchema.parse(testCase.result)).toEqual(testCase.result);
		}
	});

	test('defines strict Review intake readiness request and null result contracts', () => {
		for (const testCase of validProductSessionCorpus.reviewIntakeReadyCases) {
			expect(bridgeProductCallRequestSchema.parse(testCase.request)).toEqual(testCase.request);
			expect(bridgeProductCallResultSchema.parse(testCase.result)).toEqual(testCase.result);
		}
		for (const invalidRequest of [
			{ reason: null },
			{ streamId: null },
			{ extra: true, reason: null, streamId: null },
			{ reason: '', streamId: null },
			{ reason: 'contains spaces', streamId: null },
			{ reason: null, streamId: '' },
			{ reason: null, streamId: 'contains spaces' },
		]) {
			expect(bridgeProductReviewIntakeReadyRequestSchema.safeParse(invalidRequest).success).toBe(
				false,
			);
		}
		expect(
			bridgeProductCallResultSchema.safeParse({
				method: 'review.intake.ready',
				result: {},
			}).success,
		).toBe(false);
	});

	test('defines an exact strict Review publication application receipt', () => {
		for (const testCase of validProductSessionCorpus.reviewPublicationAppliedCases) {
			expect(
				bridgeProductReviewPublicationAppliedRequestSchema.parse(testCase.request.request),
			).toEqual(testCase.request.request);
			expect(bridgeProductCallRequestSchema.parse(testCase.request)).toEqual(testCase.request);
			expect(bridgeProductCallResultSchema.parse(testCase.result)).toEqual(testCase.result);
		}
		for (const invalidRequest of [
			{},
			{ publicationId: '' },
			{ publicationId: 'contains spaces' },
			{ publicationId: '00000000-0000-7000-8000-00000000001A' },
			{ publicationId: '00000000-0000-4000-8000-000000000017' },
			{ publicationId: '00000000-0000-9000-8000-000000000017' },
			{ publicationId: '00000000-0000-7000-7000-000000000017' },
			{ extra: true, publicationId: '00000000-0000-7000-8000-000000000017' },
		]) {
			expect(
				bridgeProductReviewPublicationAppliedRequestSchema.safeParse(invalidRequest).success,
			).toBe(false);
		}
	});

	test('defines exact strict Review publication install admission contracts', () => {
		for (const testCase of validProductSessionCorpus.reviewPublicationInstallAdmissionCases) {
			expect(
				bridgeProductReviewPublicationInstallAdmissionRequestSchema.parse(testCase.request.request),
			).toEqual(testCase.request.request);
			expect(bridgeProductCallRequestSchema.parse(testCase.request)).toEqual(testCase.request);
			expect(
				bridgeProductReviewPublicationInstallAdmissionResultSchema.parse(testCase.result.result),
			).toEqual(testCase.result.result);
			expect(bridgeProductCallResultSchema.parse(testCase.result)).toEqual(testCase.result);
		}

		for (const invalidRequest of [
			{},
			{ candidatePublicationId: '00000000-0000-7000-8000-000000000018' },
			{ candidatePublicationId: '', expectedDisplayedPublicationId: null },
			{
				candidatePublicationId: '00000000-0000-4000-8000-000000000018',
				expectedDisplayedPublicationId: null,
			},
			{
				candidatePublicationId: '00000000-0000-7000-8000-000000000018',
				expectedDisplayedPublicationId: '',
			},
			{
				candidatePublicationId: '00000000-0000-7000-8000-000000000018',
				expectedDisplayedPublicationId: null,
				extra: true,
			},
		]) {
			expect(
				bridgeProductReviewPublicationInstallAdmissionRequestSchema.safeParse(invalidRequest)
					.success,
			).toBe(false);
		}

		for (const invalidResult of [{}, { status: 'unknown' }, { extra: true, status: 'admitted' }]) {
			expect(
				bridgeProductReviewPublicationInstallAdmissionResultSchema.safeParse(invalidResult).success,
			).toBe(false);
		}
	});

	test('defines a strict target-only Review comparison update with a null result', () => {
		const targets = [
			{ basis: 'commonCommit', branchName: 'main', kind: 'localDefaultBranch' },
			{
				basis: 'commonCommit',
				branchName: 'main',
				kind: 'originDefaultBranch',
				remoteName: 'origin',
			},
			{ basis: 'commonCommit', kind: 'branch', name: 'feature/review' },
			{ kind: 'commit', oid: '0123456789abcdef0123456789abcdef01234567' },
			{ basis: 'commonCommit', kind: 'ref', name: 'refs/tags/v1.0.0' },
		] as const;

		for (const target of targets) {
			const request = { method: 'review.comparison.update', request: { target } } as const;
			expect(bridgeProductReviewComparisonUpdateRequestSchema.parse(request.request)).toEqual(
				request.request,
			);
			expect(bridgeProductCallRequestSchema.parse(request)).toEqual(request);
			expect(
				bridgeProductCallResultSchema.parse({ method: 'review.comparison.update', result: null }),
			).toEqual({ method: 'review.comparison.update', result: null });
		}

		for (const invalidRequest of [
			{},
			{ target: null },
			{ target: { kind: 'localDefaultBranch', name: 'main' } },
			{ target: { branchName: 'main', kind: 'originDefaultBranch' } },
			{ target: { kind: 'branch', name: '' } },
			{ target: { kind: 'commit', oid: '' } },
			{ target: { kind: 'commit', oid: 'abc123' } },
			{ target: { kind: 'commit', oid: 'g'.repeat(40) } },
			{ target: { kind: 'commit', name: '0123456789abcdef0123456789abcdef01234567' } },
			{ target: { extra: true, kind: 'ref', name: 'HEAD' } },
			{ extra: true, target: { kind: 'ref', name: 'HEAD' } },
		]) {
			expect(
				bridgeProductReviewComparisonUpdateRequestSchema.safeParse(invalidRequest).success,
			).toBe(false);
		}
	});

	test('uses an authorization-only descriptor for comparison-target query results', () => {
		const descriptor = {
			contentKind: 'review.comparisonTargets',
			descriptorId: '00000000-0000-7000-8000-000000000017',
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_COMPARISON_TARGET_BYTES,
		} as const;

		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({ descriptor }).success,
		).toBe(true);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: { ...descriptor, capturedAtUnixMilliseconds: 2_000 },
			}).success,
		).toBe(false);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: { ...descriptor, declaredByteLength: descriptor.maximumBytes },
			}).success,
		).toBe(false);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: { ...descriptor, cutoffUnixMilliseconds: 1_000 },
			}).success,
		).toBe(false);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: { ...descriptor, encoding: 'utf-8' },
			}).success,
		).toBe(false);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: { ...descriptor, expectedSha256: 'a'.repeat(64) },
			}).success,
		).toBe(false);
		expect(
			bridgeProductReviewComparisonTargetsQueryResultSchema.safeParse({
				descriptor: {
					...descriptor,
					maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_COMPARISON_TARGET_BYTES + 1,
				},
			}).success,
		).toBe(false);
	});
});
