import Foundation
import ArchitectCore
import ArchitectAnalysis

/// Agent A: Generates tasks from findings
public final class TaskGenerator: TaskEmitter, @unchecked Sendable {
    private let scanner: ProjectScanner
    private let rules: [TaskGenerationRule]
    private let config: TaskGenerationConfig
    
    public init(
        scanner: ProjectScanner = ProjectScanner(),
        rules: [TaskGenerationRule] = TaskGenerationRule.defaults,
        config: TaskGenerationConfig = .default
    ) {
        self.scanner = scanner
        self.rules = rules
        self.config = config
    }
    
    // MARK: - TaskEmitter Protocol
    
    public func analyze(projectPath: String) async throws -> [Finding] {
        try await scanner.scan(projectPath: projectPath)
    }
    
    public func generateTasks(from findings: [Finding]) -> [AgentTask] {
        var tasks: [AgentTask] = []
        
        for finding in findings {
            // Find matching rules (may have multiple for same finding type)
            let matchingRules = rules.filter { $0.findingType == finding.type }
            
            for rule in matchingRules {
                // Generate intent and check if it's a valid match
                let intent = rule.intentFactory(finding)
                
                // Skip if this rule's intent doesn't match the finding's context
                // (e.g., longFunctionRule only applies when metric == "functionLines")
                if case .fixWarning = intent {
                    // This is the fallback intent, skip it
                    continue
                }
                
                // Check if this intent category is enabled
                guard config.enabledIntentCategories.contains(intent.category) else {
                    continue
                }
                
                // Generate steps from template
                let steps = rule.stepTemplate.enumerated().map { index, description in
                    TaskStep(
                        description: description,
                        allowedFiles: [finding.location.file],
                        expectedDiffType: rule.expectedDiffTypes[safe: index] ?? .modifyBody
                    )
                }
                
                // Create task
                var task = AgentTask(
                    title: intent.description,
                    intent: intent,
                    scope: rule.defaultScope(finding),
                    steps: steps,
                    requiresApproval: config.requireApprovalForCategories.contains(intent.category),
                    sourceFindings: [finding.id]
                )
                
                // Set confidence factors
                task.confidenceFactors = [
                    "rulePrecision": rule.confidenceThreshold,
                    "severityWeight": Double(finding.severity.rawValue) / 3.0,
                    "contextCompleteness": finding.context.isEmpty ? 0.5 : 0.9
                ]
                
                // Only include if confidence meets threshold
                if task.confidence >= config.minimumConfidence {
                    tasks.append(task)
                    break // Only generate one task per finding
                }
            }
        }
        
        // Limit number of tasks
        return Array(tasks.prefix(config.maxTasksPerRun))
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
