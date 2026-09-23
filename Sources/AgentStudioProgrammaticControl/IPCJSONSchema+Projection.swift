import Foundation

extension IPCJSONSchema {
    func documentValue() throws -> IPCSchemaValue {
        var properties: [String: IPCSchemaValue]
        switch self {
        case .object(let fields):
            var fieldSchemas: [String: IPCSchemaValue] = [:]
            var required: [IPCSchemaValue] = []
            for field in fields {
                guard case .object(var fieldSchema) = try field.schema.documentValue() else {
                    throw failure(.invalidDefinition, path: "$", expected: "object schema document")
                }
                fieldSchema["description"] = .string(field.description)
                switch field.presence {
                case .required: required.append(.string(field.name))
                case .optional: break
                case .defaultValue(let data):
                    fieldSchema["default"] = try JSONDecoder().decode(IPCSchemaValue.self, from: data)
                }
                fieldSchemas[field.name] = .object(fieldSchema)
            }
            return .object([
                "type": .string("object"), "properties": .object(fieldSchemas),
                "required": .array(required), "additionalProperties": .boolean(false),
            ])
        case .array(let item, let minimum, let maximum):
            properties = ["type": .string("array"), "items": try item.documentValue()]
            properties["minItems"] = .number(Decimal(minimum))
            if let maximum { properties["maxItems"] = .number(Decimal(maximum)) }
        case .dictionary(let value):
            properties = ["type": .string("object"), "additionalProperties": try value.documentValue()]
        case .string(let constraints):
            properties = stringDocumentProperties(constraints)
        case .integer(let minimum, let maximum):
            properties = ["type": .string("integer")]
            if let minimum { properties["minimum"] = .number(Decimal(minimum)) }
            if let maximum { properties["maximum"] = .number(Decimal(maximum)) }
        case .number(let minimum, let maximum):
            properties = ["type": .string("number")]
            if let minimum { properties["minimum"] = .number(Decimal(minimum)) }
            if let maximum { properties["maximum"] = .number(Decimal(maximum)) }
        case .boolean: properties = ["type": .string("boolean")]
        case .booleanConstant(let value):
            properties = ["type": .string("boolean"), "const": .boolean(value)]
        case .literalValue(let literal):
            properties = ["const": try literal.value()]
        case .null: properties = ["type": .string("null")]
        case .oneOf(let alternatives):
            properties = ["oneOf": .array(try alternatives.map { try $0.documentValue() })]
        case .schemaDocument:
            properties = ["$ref": .string(Self.metaSchemaURI)]
        }
        return .object(properties)
    }

    private func stringDocumentProperties(_ constraints: IPCStringSchema) -> [String: IPCSchemaValue] {
        var properties: [String: IPCSchemaValue] = [
            "type": .string("string"), "minLength": .number(Decimal(constraints.minimumLength)),
        ]
        if let values = constraints.allowedValues { properties["enum"] = .array(values.map(IPCSchemaValue.string)) }
        if let maximum = constraints.maximumLength { properties["maxLength"] = .number(Decimal(maximum)) }
        if let pattern = constraints.pattern { properties["pattern"] = .string(pattern) }
        if let maximumUTF16Length = constraints.maximumUTF16Length {
            // Catalog-specific constraint, not the standard character-count
            // assertion. Generic JSON Schema tools may treat it as annotation.
            properties["x-maxUTF16Length"] = .number(Decimal(maximumUTF16Length))
        }
        return properties
    }

}
