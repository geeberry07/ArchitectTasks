import Foundation
import ArchitectCore

/// Defines how to transform a finding into a task
public struct TaskGenerationRule: Sendable {
    public var findingType: Finding.FindingType
    public var intentFactory: @Sendable (Finding) -> TaskIntent
    public var stepTemplate: [String]
    public var expectedDiffTypes: [TaskStep.DiffType]
    public var defaultScope: @Sendable (Finding) -> TaskScope
    public var confidenceThreshold: Double
    
    public init(
        findingType: Finding.FindingType,
        intentFactory: @escaping @Sendable (Finding) -> TaskIntent,
        stepTemplate: [String],
        expectedDiffTypes: [TaskStep.DiffType],
        defaultScope: @escaping @Sendable (Finding) -> TaskScope,
        confidenceThreshold: Double
    ) {
        self.findingType = findingType
        self.intentFactory = intentFactory
        self.stepTemplate = stepTemplate
        self.expectedDiffTypes = expectedDiffTypes
        self.defaultScope = defaultScope
        self.confidenceThreshold = confidenceThreshold
    }
}

// MARK: - Default Rules

extension TaskGenerationRule {
    
    public static let defaults: [TaskGenerationRule] = [
        missingStateObjectRule,
        missingBindingRule,
        longFunctionRule,
        deepNestingRule,
        tooManyParametersRule,
        largeFileRule,
        highComplexityRule
    ]
    
    /// Rule for missing @StateObject/@ObservedObject
    public static let missingStateObjectRule = TaskGenerationRule(
        findingType: .missingStateObject,
        intentFactory: { finding in
            .addStateObject(
                property: finding.context["property"] ?? "viewModel",
                type: finding.context["type"] ?? "ViewModel",
                in: finding.location.file
            )
        },
        stepTemplate: [
            "Locate the property declaration",
            "Add @StateObject or @ObservedObject wrapper",
            "Verify view updates correctly"
        ],
        expectedDiffTypes: [.modifyBody, .addWrapper, .modifyBody],
        defaultScope: { .file(path: $0.location.file) },
        confidenceThreshold: 0.85  // Higher base confidence for this rule
    )
    
    /// Rule for missing bindings
    public static let missingBindingRule = TaskGenerationRule(
        findingType: .missingBinding,
        intentFactory: { finding in
            .addBinding(
                property: finding.context["property"] ?? "value",
                in: finding.location.file
            )
        },
        stepTemplate: [
            "Locate view initializer",
            "Identify missing binding type",
            "Add @Binding property wrapper",
            "Update call sites to pass binding"
        ],
        expectedDiffTypes: [.modifyBody, .modifyBody, .addWrapper, .modifyBody],
        defaultScope: { .file(path: $0.location.file) },
        confidenceThreshold: 0.8
    )
    
    /// Rule for long functions (extract method refactoring)
    public static let longFunctionRule = TaskGenerationRule(
        findingType: .highComplexity,
        intentFactory: { finding in
            guard finding.context["metric"] == "functionLines" else {
                return .fixWarning(diagnostic: "complexity", in: finding.location.file)
            }
            return .extractFunction(
                from: finding.context["function"] ?? "unknown",
                in: finding.location.file
            )
        },
        stepTemplate: [
            "Identify logical sections in the function",
            "Extract cohesive code blocks into helper methods",
            "Update original function to call extracted methods",
            "Verify behavior is preserved"
        ],
        expectedDiffTypes: [.modifyBody, .addMethod, .modifyBody, .modifyBody],
        defaultScope: { .file(path: $0.location.file) },
        confidenceThreshold: 0.7
    )
    
    /// Rule for deep nesting (early return / guard refactoring)
    public static let deepNestingRule = TaskGenerationRule(
        findingType: .highComplexity,
        intentFactory: { finding in
            guard finding.context["metric"] == "nestingDepth" else {
                return .fixWarning(diagnostic: "complexity", in: finding.location.file)
            }
            return .reduceNesting(
                in: finding.location.file,
                at: finding.location.line
            )
        },
        stepTemplate: [
            "Identify nested conditions that can be inverted",
            "Apply guard statements for early returns",
            "Flatten remaining nested logic",
            "Verify control flow is preserved"
        ],
        expectedDiffTypes: [.modifyBody, .modifyBody, .modifyBody, .modifyBody],
        defaultScope: { .file(path: $0.location.file) },
        confidenceThreshold: 0.65
    )
    
    /// Rule for too many parameters (parameter object refactoring)
    public static let tooManyParametersRule = TaskGenerationRule(
        findingType: .highComplexity,
        intentFactory: { finding in
            guard finding.context["metric"] == "parameterCount" else {
                return .fixWarning(diagnostic: "complexity", in: finding.location.file)
            }
            return .reduceParameters(
                function: finding.context["function"] ?? "unknown",
                in: finding.location.file
            )
        },
        stepTemplate: [
            "Identify related parameters that form a concept",
            "Create a parameter object or struct",
            "Update function signature to use new type",
            "Update all call sites"
        ],
        expectedDiffTypes: [.modifyBody, .addType, .modifyBody, .modifyBody],
        defaultScope: { finding in
            // Parameter changes may affect multiple files
            .module(name: URL(fileURLWithPath: finding.location.file).deletingLastPathComponent().lastPathComponent)
        },
        confidenceThreshold: 0.6
    )
    
    /// Rule for large files (split file refactoring)
    public static let largeFileRule = TaskGenerationRule(
        findingType: .highComplexity,
        intentFactory: { finding in
            guard finding.context["metric"] == "fileLines" else {
                return .fixWarning(diagnostic: "complexity", in: finding.location.file)
            }
            return .splitFile(path: finding.location.file)
        },
        stepTemplate: [
            "Identify distinct responsibilities in the file",
            "Group related types and extensions",
            "Create new files for each responsibility",
            "Update imports in dependent files"
        ],
        expectedDiffTypes: [.modifyBody, .modifyBody, .addFile, .modifyBody],
        defaultScope: { .module(name: URL(fileURLWithPath: $0.location.file).deletingLastPathComponent().lastPathComponent) },
        confidenceThreshold: 0.55
    )
    
    /// Rule for high cyclomatic complexity
    public static let highComplexityRule = TaskGenerationRule(
        findingType: .highComplexity,
        intentFactory: { finding in
            guard finding.context["metric"] == "cyclomaticComplexity" else {
                return .fixWarning(diagnostic: "complexity", in: finding.location.file)
            }
            return .extractFunction(
                from: finding.context["function"] ?? "unknown",
                in: finding.location.file
            )
        },
        stepTemplate: [
            "Identify decision points (if/switch/loops)",
            "Extract conditional branches into separate methods",
            "Consider using strategy pattern for complex switches",
            "Verify all paths are covered"
        ],
        expectedDiffTypes: [.modifyBody, .addMethod, .modifyBody, .modifyBody],
        defaultScope: { .file(path: $0.location.file) },
        confidenceThreshold: 0.65
    )
}
