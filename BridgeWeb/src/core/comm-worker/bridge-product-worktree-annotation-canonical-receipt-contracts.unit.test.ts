import { describe, expect, test } from 'vitest';
import type { z } from 'zod';

import { BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES } from './bridge-product-contract-primitives.js';
import {
	bridgeProductWorktreeAnnotationCommandOutcomeSchema,
	bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema,
} from './bridge-product-worktree-annotation-contracts.js';

const sessionId = '01890abc-def0-7abc-8def-0123456789ab';
const otherSessionId = '01890abc-def0-7abc-8def-0123456789ac';
const threadId = '01890abc-def0-7abc-8def-012345678901';
const otherThreadId = '01890abc-def0-7abc-8def-012345678902';
const messageId = '01890abc-def0-7abc-8def-012345678903';

type RawCommandOutcome = z.input<typeof bridgeProductWorktreeAnnotationCommandOutcomeSchema>;
type RawCommandReceipt = NonNullable<RawCommandOutcome['receipt']>;
type RawMessageReceipt = Extract<RawCommandReceipt, { kind: 'message' }>;

function rawMessageReceipt(): RawMessageReceipt;
function rawMessageReceipt(overrides: Record<string, unknown>): Record<string, unknown>;
function rawMessageReceipt(overrides: Record<string, unknown> = {}): Record<string, unknown> {
	return {
		context: {
			diffSide: 'additions',
			endLine: 9,
			path: 'Sources/Feature.swift',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'review-source-1',
			sourceRole: 'review_head',
			startLine: 7,
			threadId,
		},
		kind: 'message',
		message: {
			attentionState: 'not_applicable',
			authorKind: 'human',
			createdAtUnixMilliseconds: 1_700_000_000_000,
			draft: { activeEditToken: 'edit-token-1', body: 'Draft body', revision: 3 },
			handled: false,
			messageId,
			messageRevision: 5,
			ordinal: 0,
			savedBody: 'Saved body',
			savedRevision: 2,
			sessionId,
			sessionRevision: 8,
			status: 'editable',
			threadId,
			threadRevision: 6,
		},
		...overrides,
	};
}

function rawCommittedOutcome(): RawCommandOutcome;
function rawCommittedOutcome(receipt: unknown): Record<string, unknown>;
function rawCommittedOutcome(receipt: unknown = rawMessageReceipt()): Record<string, unknown> {
	return {
		receipt,
		requestId: 'annotation-command-1',
		sessionId,
		status: { kind: 'committed' },
		surface: 'review',
	};
}

describe('Bridge product worktree annotation canonical receipt contracts', () => {
	test('decodes one complete canonical message receipt exactly once', () => {
		const rawOutcome = rawCommittedOutcome();
		const decodedOutcome = bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(rawOutcome);

		expect(decodedOutcome).toEqual({
			...rawOutcome,
			receipt: {
				...rawMessageReceipt(),
				message: {
					...rawMessageReceipt().message,
					createdAt: 1_700_000_000_000,
					createdAtUnixMilliseconds: undefined,
				},
			},
		});
		expect(
			bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.parse(decodedOutcome),
		).toEqual(decodedOutcome);
		expect(
			bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.safeParse(rawOutcome).success,
		).toBe(false);
		expect(
			bridgeProductWorktreeAnnotationCommandOutcomeSchema.safeParse(decodedOutcome).success,
		).toBe(false);
	});

	test('rejects incomplete, extended, mismatched, and non-committed message receipts', () => {
		const completeReceipt = rawMessageReceipt();
		const { savedBody: _savedBody, ...messageWithoutSavedBody } = completeReceipt.message;

		for (const rejected of [
			rawCommittedOutcome({ ...completeReceipt, message: messageWithoutSavedBody }),
			rawCommittedOutcome({ ...completeReceipt, placement: 'exact' }),
			rawCommittedOutcome({
				...completeReceipt,
				context: { ...completeReceipt.context, placement: 'exact' },
			}),
			rawCommittedOutcome({ ...completeReceipt, messageRevision: 5 }),
			rawCommittedOutcome({
				...completeReceipt,
				message: { ...completeReceipt.message, threadId: otherThreadId },
			}),
			{ ...rawCommittedOutcome(), sessionId: otherSessionId },
			{ ...rawCommittedOutcome(), status: { code: 'conflict', kind: 'failed' } },
		] as const) {
			expect(bridgeProductWorktreeAnnotationCommandOutcomeSchema.safeParse(rejected).success).toBe(
				false,
			);
		}
	});

	test('accepts strict removal tombstones for removed and surviving threads', () => {
		for (const threadRevision of [null, 9] as const) {
			const outcome = rawCommittedOutcome({
				kind: 'message_removed',
				messageId,
				removedMessageRevision: 5,
				sessionId,
				sessionRevision: 10,
				threadId,
				threadRevision,
			});

			expect(bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(outcome)).toEqual(outcome);
			expect(bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.parse(outcome)).toEqual(
				outcome,
			);
		}
	});

	test('rejects incomplete, extended, mismatched, and synthetic removal tombstones', () => {
		const removal = {
			kind: 'message_removed',
			messageId,
			removedMessageRevision: 5,
			sessionId,
			sessionRevision: 10,
			threadId,
			threadRevision: null,
		} as const;
		const { threadRevision: _threadRevision, ...withoutThreadRevision } = removal;

		for (const rejected of [
			rawCommittedOutcome(withoutThreadRevision),
			rawCommittedOutcome({ ...removal, message: rawMessageReceipt().message }),
			rawCommittedOutcome({ ...removal, removedMessageRevision: -1 }),
			rawCommittedOutcome({ ...removal, messageRevision: 6 }),
			rawCommittedOutcome({ ...removal, sessionId: otherSessionId }),
			{ ...rawCommittedOutcome(removal), status: { code: 'not_found', kind: 'failed' } },
		] as const) {
			expect(bridgeProductWorktreeAnnotationCommandOutcomeSchema.safeParse(rejected).success).toBe(
				false,
			);
		}
	});

	test('rejects the revision-only legacy receipt', () => {
		expect(
			bridgeProductWorktreeAnnotationCommandOutcomeSchema.safeParse(
				rawCommittedOutcome({
					draftRevision: 3,
					kind: 'message',
					messageId,
					messageRevision: 5,
					savedRevision: 2,
					sessionRevision: 8,
					threadId,
					threadRevision: 6,
				}),
			).success,
		).toBe(false);
	});

	test('accepts worst-case escaped bodies and path within the generic control budget', () => {
		const receipt = rawMessageReceipt({
			context: {
				...rawMessageReceipt().context,
				path: '\u0001'.repeat(4096),
				sourceIdentity: 'a'.repeat(128),
			},
			message: {
				...rawMessageReceipt().message,
				draft: { activeEditToken: null, body: '\u0002'.repeat(16 * 1024), revision: 4 },
				savedBody: '\u0001'.repeat(16 * 1024),
			},
		});
		const rawOutcome = rawCommittedOutcome(receipt);
		const decodedOutcome = bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(rawOutcome);
		const rawEncodedLength = new TextEncoder().encode(JSON.stringify(rawOutcome)).byteLength;
		const decodedEncodedLength = new TextEncoder().encode(
			JSON.stringify(decodedOutcome),
		).byteLength;

		expect(
			bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.safeParse(decodedOutcome).success,
		).toBe(true);
		expect(rawEncodedLength).toBe(222_140);
		expect(rawEncodedLength).toBeLessThanOrEqual(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES);
		expect(decodedEncodedLength).toBe(222_124);
		expect(decodedEncodedLength).toBeLessThanOrEqual(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES);
	});

	test('accepts a new-root message with only its nonempty draft', () => {
		const rawOutcome = rawCommittedOutcome(
			rawMessageReceipt({
				message: {
					...rawMessageReceipt().message,
					draft: { activeEditToken: 'new-root-edit', body: 'Unsaved root', revision: 0 },
					messageRevision: 0,
					savedBody: null,
					savedRevision: null,
					threadRevision: 0,
				},
			}),
		);
		const decodedOutcome = bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(rawOutcome);

		expect(decodedOutcome).toMatchObject({
			receipt: {
				kind: 'message',
				message: { draft: { body: 'Unsaved root' }, savedBody: null, savedRevision: null },
			},
			status: { kind: 'committed' },
			surface: 'review',
		});
		expect(
			bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.safeParse(decodedOutcome).success,
		).toBe(true);
	});

	test('accepts a saved message with no remaining draft', () => {
		const rawOutcome = rawCommittedOutcome(
			rawMessageReceipt({
				message: {
					...rawMessageReceipt().message,
					draft: null,
					messageRevision: 6,
					savedBody: 'Current saved body',
					savedRevision: 3,
				},
			}),
		);
		const decodedOutcome = bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(rawOutcome);

		expect(decodedOutcome).toMatchObject({
			receipt: {
				kind: 'message',
				message: { draft: null, savedBody: 'Current saved body', savedRevision: 3 },
			},
			status: { kind: 'committed' },
			surface: 'review',
		});
		expect(
			bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.safeParse(decodedOutcome).success,
		).toBe(true);
	});

	test('preserves viewed, output, history, failure, and committed no-message outcomes', () => {
		const common = {
			requestId: 'annotation-command-2',
			sessionId,
			surface: 'file',
		} as const;
		const rawOutcomes = [
			{ ...common, status: { kind: 'committed' } },
			{ ...common, status: { code: 'conflict', kind: 'failed' } },
			{ ...common, status: { kind: 'history', summaries: [] } },
			{
				...common,
				status: { kind: 'output', outcome: { kind: 'destination_cancelled' } },
			},
			{
				...common,
				receipt: null,
				status: {
					kind: 'viewed',
					results: [
						{
							disposition: 'not_found',
							expectedSavedRevision: 1,
							kind: 'not_viewed',
							messageId,
						},
					],
				},
			},
		] as const;

		for (const outcome of rawOutcomes) {
			expect(bridgeProductWorktreeAnnotationCommandOutcomeSchema.safeParse(outcome).success).toBe(
				true,
			);
		}
	});
});
