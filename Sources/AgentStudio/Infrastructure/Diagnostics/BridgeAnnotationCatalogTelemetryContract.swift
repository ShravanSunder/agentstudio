import Foundation

enum BridgeAnnotationCatalogTelemetryContract {
    static let phaseValues: Set<String> = [
        "annotation_catalog_main_begin",
        "annotation_catalog_main_commit",
        "annotation_catalog_main_window",
    ]

    static let numericAttributeKeys: Set<String> = [
        "agentstudio.bridge.annotation.catalog.entry.count",
        "agentstudio.bridge.annotation.catalog.revision",
        "agentstudio.bridge.annotation.catalog.unit.byte_count",
        "agentstudio.bridge.annotation.catalog.window.count",
        "agentstudio.bridge.annotation.catalog.window.ordinal",
        "agentstudio.bridge.presentation.revision.after",
        "agentstudio.bridge.presentation.revision.before",
    ]
}
