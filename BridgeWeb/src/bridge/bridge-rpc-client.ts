import { z } from 'zod';

import { bridgeDemandLaneSchema } from '../core/models/bridge-demand-models.js';
import { bridgeTelemetryBatchSchema } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';

export const bridgeRPCIdSchema = z.union([z.string(), z.number()]);

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
		method: z.literal('system.bridgeTelemetry'),
		params: bridgeTelemetryBatchSchema,
	}),
]);

export type BridgeRPCCommand = z.infer<typeof bridgeRPCCommandSchema>;

export interface BridgeRPCClient {
	readonly sendCommand: (command: BridgeRPCCommand) => boolean;
}

export interface CreateBridgeRPCClientProps {
	readonly target?: EventTarget;
	readonly getBridgeNonce?: () => string | null;
	readonly createCommandId?: () => string;
	readonly getTraceContext?: (command: BridgeRPCCommand) => BridgeTraceContext | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
}

export function createBridgeRPCClient(props: CreateBridgeRPCClientProps = {}): BridgeRPCClient {
	const target = props.target ?? document;
	const getBridgeNonce = props.getBridgeNonce ?? defaultBridgeNonceReader;
	const createCommandId = props.createCommandId ?? defaultCommandIdFactory;
	const getTraceContext = props.getTraceContext ?? (() => null);
	const telemetryRecorder = props.telemetryRecorder;

	return {
		sendCommand: (command: BridgeRPCCommand): boolean => {
			const validatedCommand = bridgeRPCCommandSchema.parse(command);
			const bridgeNonce = getBridgeNonce();
			if (bridgeNonce === null) {
				return false;
			}
			const traceContext = shouldAttachTraceContext(validatedCommand)
				? getTraceContext(validatedCommand)
				: null;
			target.dispatchEvent(
				new CustomEvent('__bridge_command', {
					detail: makeCommandDetail(validatedCommand, bridgeNonce, createCommandId(), traceContext),
				}),
			);
			if (shouldRecordRPCTelemetry(validatedCommand)) {
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
				telemetryRecorder?.flush({ force: true });
			}
			return true;
		},
	};
}

function makeCommandDetail(
	command: BridgeRPCCommand,
	bridgeNonce: string,
	commandId: string,
	traceContext: BridgeTraceContext | null,
): Readonly<Record<string, unknown>> {
	return {
		jsonrpc: '2.0',
		...(command.id === undefined ? {} : { id: command.id }),
		method: command.method,
		...(command.params === undefined ? {} : { params: command.params }),
		...(traceContext === null ? {} : { __traceContext: traceContext }),
		__nonce: bridgeNonce,
		__commandId: commandId,
	};
}

function shouldAttachTraceContext(command: BridgeRPCCommand): boolean {
	return command.method !== 'system.bridgeTelemetry';
}

function shouldRecordRPCTelemetry(command: BridgeRPCCommand): boolean {
	return command.method !== 'system.bridgeTelemetry';
}

function rpcMethodClass(method: string): 'other' | 'review' | 'telemetry' {
	if (method === 'system.bridgeTelemetry') {
		return 'telemetry';
	}
	if (method.startsWith('review.')) {
		return 'review';
	}
	return 'other';
}

function defaultBridgeNonceReader(): string | null {
	return document.documentElement.getAttribute('data-bridge-nonce');
}

function defaultCommandIdFactory(): string {
	return `cmd_${crypto.randomUUID()}`;
}
