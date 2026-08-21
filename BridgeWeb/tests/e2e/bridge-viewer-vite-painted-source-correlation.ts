export interface PaintedSourceCorrelation {
	readonly descriptorId: string;
	readonly disposition: string;
	readonly itemId: string;
	readonly observedSha256: string;
	readonly pierreItemId: string;
	readonly position: string;
	readonly publicationId: string;
	readonly requestId: string;
	readonly role: string;
	readonly semanticItemId: string;
	readonly sourceGeneration: number;
	readonly sourceIdentity: string;
	readonly surface: string;
}

export function decodePaintedSourceCorrelations(
	encodedValue: string,
): readonly PaintedSourceCorrelation[] {
	const parsedValue: unknown = JSON.parse(encodedValue);
	if (!Array.isArray(parsedValue)) throw new Error('Painted source correlations must be an array.');
	return parsedValue.map((value, valueIndex): PaintedSourceCorrelation => {
		if (!isUnknownRecord(value)) {
			throw new Error(`Painted source correlation ${valueIndex} must be an object.`);
		}
		return {
			descriptorId: requiredStringField({ fieldName: 'descriptorId', value, valueIndex }),
			disposition: requiredStringField({ fieldName: 'disposition', value, valueIndex }),
			itemId: requiredStringField({ fieldName: 'itemId', value, valueIndex }),
			observedSha256: requiredStringField({ fieldName: 'observedSha256', value, valueIndex }),
			pierreItemId: requiredStringField({ fieldName: 'pierreItemId', value, valueIndex }),
			position: requiredStringField({ fieldName: 'position', value, valueIndex }),
			publicationId: requiredStringField({ fieldName: 'publicationId', value, valueIndex }),
			requestId: requiredStringField({ fieldName: 'requestId', value, valueIndex }),
			role: requiredStringField({ fieldName: 'role', value, valueIndex }),
			semanticItemId: requiredStringField({ fieldName: 'semanticItemId', value, valueIndex }),
			sourceGeneration: requiredNumberField({
				fieldName: 'sourceGeneration',
				value,
				valueIndex,
			}),
			sourceIdentity: requiredStringField({ fieldName: 'sourceIdentity', value, valueIndex }),
			surface: requiredStringField({ fieldName: 'surface', value, valueIndex }),
		};
	});
}

function requiredStringField(props: {
	readonly fieldName: string;
	readonly value: Readonly<Record<string, unknown>>;
	readonly valueIndex: number;
}): string {
	const fieldValue = props.value[props.fieldName];
	if (typeof fieldValue !== 'string') {
		throw new Error(
			`Painted source correlation ${props.valueIndex} has invalid ${props.fieldName}.`,
		);
	}
	return fieldValue;
}

function requiredNumberField(props: {
	readonly fieldName: string;
	readonly value: Readonly<Record<string, unknown>>;
	readonly valueIndex: number;
}): number {
	const fieldValue = props.value[props.fieldName];
	if (typeof fieldValue !== 'number') {
		throw new Error(
			`Painted source correlation ${props.valueIndex} has invalid ${props.fieldName}.`,
		);
	}
	return fieldValue;
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
