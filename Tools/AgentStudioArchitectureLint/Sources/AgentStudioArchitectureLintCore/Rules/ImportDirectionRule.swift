struct ImportDirectionRule: ArchitectureRule {
    let id = "agentstudio_import_direction"
    let severity = ArchitectureSeverity.error
    let message = "AgentStudio source layers must follow the documented import direction"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let classifier = AgentStudioPathClassifier(path: context.normalizedPath)
        guard let layer = classifier.layer else {
            return []
        }

        let visitor = ImportCollectingVisitor()
        visitor.walk(context.sourceFile)

        return visitor.imports.compactMap { importRecord in
            guard let importedLayer = AgentStudioPathClassifier.importedLayer(importRecord.path),
                isViolation(
                    layer: layer,
                    currentFeature: classifier.featureName,
                    importPath: importRecord.path,
                    importedLayer: importedLayer
                )
            else {
                return nil
            }
            let importedPath = importRecord.path.joined(separator: ".")
            return diagnostic(
                context: context,
                position: importRecord.position,
                message: "Move this dependency to an allowed layer; \(layer) cannot import \(importedPath)"
            )
        }
    }

    private func isViolation(
        layer: String,
        currentFeature: String?,
        importPath: [String],
        importedLayer: String
    ) -> Bool {
        switch layer {
        case "App":
            return false
        case "Core":
            return importedLayer != "Infrastructure" && importedLayer != "SharedComponents"
        case "Infrastructure":
            return AgentStudioPathClassifier.internalLayers.contains(importedLayer)
        case "SharedComponents":
            return importedLayer != "Infrastructure"
        case "Features":
            if ["Core", "Infrastructure", "SharedComponents"].contains(importedLayer) {
                return false
            }
            if importedLayer == "Features",
                let importedFeature = importPath.drop(while: { $0 != "Features" }).dropFirst().first.map({ String($0) })
            {
                return importedFeature != currentFeature
            }
            return true
        default:
            return false
        }
    }
}
