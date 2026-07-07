import { z } from 'zod';

import { bridgeDemandLaneSchema } from '../core/models/bridge-demand-models.js';
import {
	worktreeFileDescriptorRequestSchema,
	worktreeFileSurfaceSourceSpecSchema,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';

export const bridgeRPCIdSchema = z.union([z.string(), z.number()]);

export const bridgeActiveViewerSourceSchema = z
	.object({
		protocol: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1),
		generation: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeActiveViewerModeUpdateSchema = z
	.object({
		sessionId: z.string().min(1),
		sequence: z.number().int().positive(),
		mode: z.enum(['file', 'review']),
		activeSource: bridgeActiveViewerSourceSchema.nullable(),
	})
	.strict();

export type BridgeActiveViewerSource = z.infer<typeof bridgeActiveViewerSourceSchema>;
export type BridgeActiveViewerModeUpdate = z.infer<typeof bridgeActiveViewerModeUpdateSchema>;

export const bridgeIntakeReadyParamsSchema = z
	.object({
		protocolId: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1).nullable().optional(),
		generation: z.number().int().nonnegative().optional(),
		reason: z.string().min(1).nullable().optional(),
	})
	.strict();

export const bridgeRPCCommandSchema = z.discriminatedUnion('method', [
	z.object({
		id: bridgeRPCIdSchema.optional(),
		method: z.literal('review.markFileViewed'),
		params: z.object({ fileId: z.string().min(1) }),
	}),
	z.object({
		id: bridgeRPCIdSchema.optional(),
		method: z.literal('bridge.metadata_interest.update'),
		params: z
			.object({
				protocol: z.literal('review'),
				streamId: z.string().min(1).optional(),
				generation: z.number().int().nonnegative().optional(),
				itemIds: z.array(z.string().min(1)).optional(),
				paths: z.array(z.string().min(1)).optional(),
				lane: bridgeDemandLaneSchema,
				loaded_by: z.enum(['foreground', 'visible', 'nearby', 'speculative', 'idle']).optional(),
			})
			.strict(),
	}),
	z.object({
		id: bridgeRPCIdSchema.optional(),
		method: z.literal('bridge.activeViewerMode.update'),
		params: bridgeActiveViewerModeUpdateSchema,
	}),
	z.object({
		id: bridgeRPCIdSchema.optional(),
		method: z.literal('bridge.intakeReady'),
		params: bridgeIntakeReadyParamsSchema,
	}),
	z.object({
		id: bridgeRPCIdSchema,
		method: z.literal('worktreeFileSurface.openSourceStream'),
		params: worktreeFileSurfaceSourceSpecSchema,
	}),
	z.object({
		id: bridgeRPCIdSchema,
		method: z.literal('worktreeFileSurface.requestFileDescriptor'),
		params: worktreeFileDescriptorRequestSchema,
	}),
]);

export type BridgeRPCCommand = z.infer<typeof bridgeRPCCommandSchema>;
export type BridgeRPCFetch = (
	input: RequestInfo | URL,
	init?: RequestInit,
) => Promise<Response> | Response;

export interface BridgeRPCClient {
	readonly sendCommand: (command: BridgeRPCCommand) => boolean;
	readonly sendCommandAndWait: (command: BridgeRPCCommand) => Promise<boolean>;
}

export interface BridgeRPCCommandDeliveryFailure {
	readonly command: BridgeRPCCommand;
	readonly commandId: string;
	readonly message: string;
}

export interface CreateBridgeRPCClientProps {
	readonly commandTimeoutMilliseconds?: number | undefined;
	readonly endpointUrl?: string | undefined;
	readonly fetch?: BridgeRPCFetch | undefined;
	readonly target?: EventTarget;
	readonly getBridgeNonce?: () => string | null;
	readonly createCommandId?: () => string;
	readonly getTraceContext?: (command: BridgeRPCCommand) => BridgeTraceContext | null;
	readonly onCommandDeliveryFailure?:
		| ((failure: BridgeRPCCommandDeliveryFailure) => void)
		| undefined;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
}

export function createBridgeRPCClient(props: CreateBridgeRPCClientProps = {}): BridgeRPCClient {
	const endpointUrl = props.endpointUrl ?? 'agentstudio://rpc/command';
	const fetchRPC = props.fetch ?? globalThis.fetch.bind(globalThis);
	const createCommandId = props.createCommandId ?? defaultCommandIdFactory;
	const getTraceContext = props.getTraceContext ?? (() => null);
	const commandTimeoutMilliseconds = props.commandTimeoutMilliseconds ?? 5000;
	const onCommandDeliveryFailure = props.onCommandDeliveryFailure;
	const telemetryRecorder = props.telemetryRecorder;

	return {
		sendCommand: (command: BridgeRPCCommand): boolean => {
			const validatedCommand = bridgeRPCCommandSchema.parse(command);
			const traceContext = shouldAttachTraceContext() ? getTraceContext(validatedCommand) : null;
			const commandId =
				validatedCommand.id === undefined ? createCommandId() : String(validatedCommand.id);
			const commandDetail = makeCommandDetail(validatedCommand, commandId, traceContext);
			try {
				void Promise.resolve(
					fetchRPC(endpointUrl, {
						body: JSON.stringify(commandDetail),
						headers: { 'Content-Type': 'application/json' },
						method: 'POST',
					}),
				).catch((error: unknown): void => {
					onCommandDeliveryFailure?.({
						command: validatedCommand,
						commandId,
						message: messageForBridgeRPCDeliveryFailure(error),
					});
				});
			} catch {
				return false;
			}
			if (shouldRecordRPCTelemetry()) {
				telemetryRecorder?.record({
					scope: 'web',
					name: 'performance.bridge.web.rpc_send',
					durationMilliseconds: null,
					traceContext,
					stringAttributes: {
						'agentstudio.bridge.phase': 'send',
						'agentstudio.bridge.plane': 'control',
						'agentstudio.bridge.priority': 'warm',
						'agentstudio.bridge.rpc.method_class': rpcMethodClass(validatedCommand.method),
						'agentstudio.bridge.slice': 'review_rpc',
						'agentstudio.bridge.transport': 'rpc',
					},
					numericAttributes: {},
					booleanAttributes: {},
				});
			}
			return true;
		},
		sendCommandAndWait: async (command: BridgeRPCCommand): Promise<boolean> => {
			const validatedCommand = bridgeRPCCommandSchema.parse(command);
			const traceContext = shouldAttachTraceContext() ? getTraceContext(validatedCommand) : null;
			const commandId =
				validatedCommand.id === undefined ? createCommandId() : String(validatedCommand.id);
			try {
				await sendBridgeRPCRequest({
					command: { ...validatedCommand, id: commandId },
					endpointUrl,
					fetch: fetchRPC,
					timeoutMilliseconds: commandTimeoutMilliseconds,
				});
			} catch {
				return false;
			}
			if (shouldRecordRPCTelemetry()) {
				telemetryRecorder?.record({
					scope: 'web',
					name: 'performance.bridge.web.rpc_send',
					durationMilliseconds: null,
					traceContext,
					stringAttributes: {
						'agentstudio.bridge.phase': 'send',
						'agentstudio.bridge.plane': 'control',
						'agentstudio.bridge.priority': 'warm',
						'agentstudio.bridge.rpc.method_class': rpcMethodClass(validatedCommand.method),
						'agentstudio.bridge.slice': 'review_rpc',
						'agentstudio.bridge.transport': 'rpc',
					},
					numericAttributes: {},
					booleanAttributes: {},
				});
			}
			return true;
		},
	};
}

export const bridgeRPCErrorPayloadSchema = z
	.object({
		code: z.number().int(),
		message: z.string(),
	})
	.strict();

export const bridgeRPCResponseEnvelopeSchema = z
	.object({
		jsonrpc: z.literal('2.0').optional(),
		id: bridgeRPCIdSchema,
		result: z.unknown().optional(),
		error: bridgeRPCErrorPayloadSchema.optional(),
	})
	.passthrough();

export class BridgeRPCResponseError extends Error {
	readonly code: number;
	readonly rpcMessage: string;

	constructor(error: z.infer<typeof bridgeRPCErrorPayloadSchema>) {
		super(error.message);
		this.name = 'BridgeRPCResponseError';
		this.code = error.code;
		this.rpcMessage = error.message;
	}
}

export class BridgeRPCRequestTimeoutError extends Error {
	constructor(readonly requestId: string) {
		super(`Bridge RPC request timed out: ${requestId}`);
		this.name = 'BridgeRPCRequestTimeoutError';
	}
}

export interface SendBridgeRPCRequestProps {
	readonly command: BridgeRPCCommand;
	readonly endpointUrl?: string | undefined;
	readonly fetch?: BridgeRPCFetch | undefined;
	readonly timeoutMilliseconds?: number;
}

export async function sendBridgeRPCRequest(props: SendBridgeRPCRequestProps): Promise<unknown> {
	const endpointUrl = props.endpointUrl ?? 'agentstudio://rpc/command';
	const fetchRPC = props.fetch ?? globalThis.fetch.bind(globalThis);
	const validatedCommand = bridgeRPCCommandSchema.parse(props.command);
	const requestId = String(validatedCommand.id ?? defaultCommandIdFactory());
	const abortController = new AbortController();
	const timeoutId =
		props.timeoutMilliseconds === undefined
			? null
			: globalThis.setTimeout((): void => {
					abortController.abort();
				}, props.timeoutMilliseconds);
	try {
		const response = await fetchRPC(endpointUrl, {
			body: JSON.stringify(
				makeCommandDetail({ ...validatedCommand, id: requestId }, requestId, null),
			),
			headers: { 'Content-Type': 'application/json' },
			method: 'POST',
			signal: abortController.signal,
		});
		if (response.status >= 400) {
			throw new Error(`Bridge RPC request failed with HTTP ${response.status.toString()}`);
		}
		const parsedResponse = bridgeRPCResponseEnvelopeSchema.parse(await response.json());
		if (String(parsedResponse.id) !== requestId) {
			throw new Error('Bridge RPC response id mismatch');
		}
		if (parsedResponse.error !== undefined) {
			throw new BridgeRPCResponseError(parsedResponse.error);
		}
		return parsedResponse.result;
	} catch (error) {
		if (abortController.signal.aborted) {
			throw new BridgeRPCRequestTimeoutError(requestId);
		}
		throw error;
	} finally {
		if (timeoutId !== null) {
			globalThis.clearTimeout(timeoutId);
		}
	}
}

function makeCommandDetail(
	command: BridgeRPCCommand,
	commandId: string,
	traceContext: BridgeTraceContext | null,
): Readonly<Record<string, unknown>> {
	return {
		jsonrpc: '2.0',
		...(command.id === undefined ? {} : { id: command.id }),
		method: command.method,
		...(command.params === undefined ? {} : { params: command.params }),
		...(traceContext === null ? {} : { __traceContext: traceContext }),
		__commandId: commandId,
	};
}

function shouldAttachTraceContext(): boolean {
	return true;
}

function shouldRecordRPCTelemetry(): boolean {
	return true;
}

function messageForBridgeRPCDeliveryFailure(error: unknown): string {
	if (error instanceof Error && error.message.length > 0) {
		return error.message;
	}
	if (typeof error === 'string' && error.length > 0) {
		return error;
	}
	return 'Bridge RPC delivery failed';
}

function rpcMethodClass(method: string): 'other' | 'review' {
	if (method.startsWith('review.')) {
		return 'review';
	}
	return 'other';
}

function defaultCommandIdFactory(): string {
	return `cmd_${crypto.randomUUID()}`;
}
