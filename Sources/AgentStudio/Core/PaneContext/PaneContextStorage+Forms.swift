import Foundation
import GRDB

extension PaneContextStorage {
    static func formFields(_ form: AskForm) -> [String: DatabaseValue] {
        switch form {
        case .choice(_, let multiple):
            ["form_kind": sqlValue("choice"), "allows_multiple": sqlValue(multiple ? 1 : 0)]
        case .freeText(let placeholder):
            ["form_kind": sqlValue("freeText"), "placeholder": sqlValue(placeholder)]
        case .elicitation:
            ["form_kind": sqlValue("elicitation")]
        }
    }

    static func saveForm(_ form: AskForm, database: Database, requestId: UUID) throws {
        switch form {
        case .freeText: break
        case .choice(let options, _):
            for (ordinal, choice) in options.enumerated() {
                try insert(
                    database, table: "pane_request_choice",
                    fields: [
                        "request_id": sqlValue(requestId.uuidString), "ordinal": sqlValue(ordinal),
                        "choice_id": sqlValue(choice.id.value), "label": sqlValue(choice.label),
                    ])
            }
        case .elicitation(let schema):
            for (ordinal, property) in schema.properties.enumerated() {
                var fields: [String: DatabaseValue] = [
                    "request_id": sqlValue(requestId.uuidString), "ordinal": sqlValue(ordinal),
                    "name": sqlValue(property.name), "title": sqlValue(property.title),
                    "description": sqlValue(property.description),
                ]
                switch property.type {
                case .boolean: fields["property_kind"] = sqlValue("boolean")
                case .number(let constraints), .integer(let constraints):
                    if case .number = property.type {
                        fields["property_kind"] = sqlValue("number")
                    } else {
                        fields["property_kind"] = sqlValue("integer")
                    }
                    fields["minimum"] = sqlValue(constraints.minimum.map { String($0) })
                    fields["maximum"] = sqlValue(constraints.maximum.map { String($0) })
                case .string(let constraints):
                    fields["property_kind"] = sqlValue("string")
                    fields["min_length"] = sqlValue(constraints.minLength)
                    fields["max_length"] = sqlValue(constraints.maxLength)
                    fields["format"] = sqlValue(constraints.format.map(formatName))
                    fields["enum_present"] = sqlValue(constraints.choices == nil ? 0 : 1)
                }
                try insert(database, table: "pane_request_property", fields: fields)
                if case .string(let constraints) = property.type, let choices = constraints.choices {
                    for (choiceOrdinal, choice) in choices.enumerated() {
                        try insert(
                            database, table: "pane_request_property_choice",
                            fields: [
                                "request_id": sqlValue(requestId.uuidString), "property_ordinal": sqlValue(ordinal),
                                "ordinal": sqlValue(choiceOrdinal), "value": sqlValue(choice),
                            ])
                    }
                }
            }
            for (ordinal, name) in schema.required.enumerated() {
                try insert(
                    database, table: "pane_request_required",
                    fields: [
                        "request_id": sqlValue(requestId.uuidString), "ordinal": sqlValue(ordinal),
                        "name": sqlValue(name),
                    ])
            }
        }
    }

    static func form(_ row: Row, database: Database) throws -> AskForm {
        let requestId = try uuid(row, "id")
        let kind: String = try required(row, "form_kind")
        switch kind {
        case "freeText": return .freeText(placeholder: try optional(row, "placeholder"))
        case "choice":
            let options = try Row.fetchAll(
                database, sql: "SELECT * FROM pane_request_choice WHERE request_id = ? ORDER BY ordinal",
                arguments: [requestId.uuidString]
            ).map { choice in
                do {
                    return AskChoice(
                        id: try AskChoiceId(required(choice, "choice_id")), label: try required(choice, "label"))
                } catch { throw PaneContextStorageFailure.decode("choice") }
            }
            return .choice(options: options, allowsMultiple: try flag(row, "allows_multiple"))
        case "elicitation":
            let rows = try Row.fetchAll(
                database, sql: "SELECT * FROM pane_request_property WHERE request_id = ? ORDER BY ordinal",
                arguments: [requestId.uuidString])
            let properties = try rows.map { try property($0, database: database, requestId: requestId) }
            let requiredNames = try String.fetchAll(
                database, sql: "SELECT name FROM pane_request_required WHERE request_id = ? ORDER BY ordinal",
                arguments: [requestId.uuidString])
            return .elicitation(ElicitationSchema(properties: properties, required: requiredNames))
        default: throw PaneContextStorageFailure.decode("form_kind")
        }
    }

    private static func property(_ row: Row, database: Database, requestId: UUID) throws -> ElicitationProperty {
        let kind: String = try required(row, "property_kind")
        let type: ElicitationPropertyType
        switch kind {
        case "boolean": type = .boolean
        case "number", "integer":
            let constraints = ElicitationNumberConstraints(
                minimum: try decimal(row, "minimum"), maximum: try decimal(row, "maximum"))
            type = kind == "number" ? .number(constraints) : .integer(constraints)
        case "string":
            let ordinal: Int = try required(row, "ordinal")
            let choices = try String.fetchAll(
                database,
                sql:
                    "SELECT value FROM pane_request_property_choice WHERE request_id = ? AND property_ordinal = ? ORDER BY ordinal",
                arguments: [requestId.uuidString, ordinal])
            let format: String? = try optional(row, "format")
            type = .string(
                ElicitationStringConstraints(
                    choices: try flag(row, "enum_present") ? choices : nil, minLength: try optional(row, "min_length"),
                    maxLength: try optional(row, "max_length"), format: try format.map(parseFormat)))
        default: throw PaneContextStorageFailure.decode("property_kind")
        }
        return ElicitationProperty(
            name: try required(row, "name"), title: try optional(row, "title"),
            description: try optional(row, "description"), type: type)
    }

    private static func decimal(_ row: Row, _ field: String) throws -> Double? {
        let text: String? = try optional(row, field)
        guard let text else { return nil }
        guard let value = Double(text), value.isFinite else { throw PaneContextStorageFailure.decode(field) }
        return value
    }

    private static func formatName(_ format: ElicitationStringFormat) -> String {
        switch format {
        case .email: "email"
        case .uri: "uri"
        case .date: "date"
        }
    }

    private static func parseFormat(_ name: String) throws -> ElicitationStringFormat {
        switch name {
        case "email": return .email
        case "uri": return .uri
        case "date": return .date
        default: throw PaneContextStorageFailure.decode("format")
        }
    }
}
