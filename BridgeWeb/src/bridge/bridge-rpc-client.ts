import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';

export type BridgeRPCId = string | number;

export interface BridgeRPCCommand {
	readonly id?: BridgeRPCId;
	readonly method: string;
	readonly params?: unknown;
}

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
			const bridgeNonce = getBridgeNonce();
			if (bridgeNonce === null) {
				return false;
			}
			const traceContext = shouldAttachTraceContext(command) ? getTraceContext(command) : null;
			target.dispatchEvent(
				new CustomEvent('__bridge_command', {
					detail: makeCommandDetail(command, bridgeNonce, createCommandId(), traceContext),
				}),
			);
			if (shouldRecordRPCTelemetry(command)) {
				telemetryRecorder?.record({
					scope: 'web',
					name: 'performance.bridge.web.rpc_send',
					durationMilliseconds: null,
					traceContext,
					stringAttributes: {
						'agentstudio.bridge.phase': 'send',
						'agentstudio.bridge.plane': 'control',
						'agentstudio.bridge.priority': 'warm',
						'agentstudio.bridge.rpc.method_class': rpcMethodClass(command.method),
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
