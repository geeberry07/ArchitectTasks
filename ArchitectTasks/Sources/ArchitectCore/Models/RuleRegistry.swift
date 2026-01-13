import Foundation

// MARK: - Rule Registry

/// Central registry of all available rules with their metadata.
/// Used for documentation, validation, and configuration generation.
public final class RuleRegistry: @unchecked Sendable {
    
    public static let shared = RuleRegistry()
    
    private var rules: [String: RuleMetadata] = [:]
    private let lock = NSLock()
    
    private init() {
        registerBuiltInRules()
    }
    
    // MARK: - Registration
    
    /// Register a rule with its metadata
    public func register(_ metadata: RuleMetadata) {
        lock.lock()
        defer { lock.unlock() }
        rules[metadata.id] = metadata
    }
    
    /// Get metadata for a rule
    public func metadata(for ruleId: String) -> RuleMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return rules[ruleId]
    }
    
    /// Get all registered rules
    public var allRules: [RuleMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return Array(rules.values).sorted { $0.id < $1.id }
    }
    
    /// Get rules by category
    public func rules(in category: RuleCategory) -> [RuleMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return rules.values.filter { $0.category == category }.sorted { $0.id < $1.id }
    }
    
    /// Get rules by tag
    public func rules(withTag tag: String) -> [RuleMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return rules.values.filter { $0.tags.contains(tag) }.sorted { $0.id < $1.id }
    }
    
    // MARK: - Built-in Rules
    
    private func registerBuiltInRules() {
        // SwiftUI Rules
        register(RuleMetadata(
            id: "swiftui.missing-state-object",
            name: "Missing @StateObject",
            description: "Detects ObservableObject properties that should use @StateObject wrapper",
            category: .swiftUI,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["swiftui", "property-wrapper", "memory"]
        ))
        
        register(RuleMetadata(
            id: "swiftui.missing-observed-object",
            name: "Missing @ObservedObject",
            description: "Detects ObservableObject properties that should use @ObservedObject wrapper",
            category: .swiftUI,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["swiftui", "property-wrapper"]
        ))
        
        register(RuleMetadata(
            id: "swiftui.missing-binding",
            name: "Missing @Binding",
            description: "Detects properties that should use @Binding wrapper",
            category: .swiftUI,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["swiftui", "property-wrapper"]
        ))
        
        // Complexity Rules
        register(RuleMetadata(
            id: "complexity.long-function",
            name: "Long Function",
            description: "Detects functions that exceed the maximum line count",
            category: .complexity,
            defaultSeverity: .warning,
            parameters: [
                ParameterMetadata(name: "maxLines", type: .int, defaultValue: .int(50), description: "Maximum lines per function")
            ],
            tags: ["complexity", "maintainability"]
        ))
        
        register(RuleMetadata(
            id: "complexity.deep-nesting",
            name: "Deep Nesting",
            description: "Detects code with excessive nesting depth",
            category: .complexity,
            defaultSeverity: .warning,
            parameters: [
                ParameterMetadata(name: "maxDepth", type: .int, defaultValue: .int(4), description: "Maximum nesting depth")
            ],
            tags: ["complexity", "readability"]
        ))
        
        register(RuleMetadata(
            id: "complexity.cyclomatic",
            name: "High Cyclomatic Complexity",
            description: "Detects functions with high cyclomatic complexity",
            category: .complexity,
            defaultSeverity: .warning,
            parameters: [
                ParameterMetadata(name: "maxComplexity", type: .int, defaultValue: .int(10), description: "Maximum cyclomatic complexity")
            ],
            tags: ["complexity", "testability"]
        ))
        
        register(RuleMetadata(
            id: "complexity.too-many-parameters",
            name: "Too Many Parameters",
            description: "Detects functions with too many parameters",
            category: .complexity,
            defaultSeverity: .warning,
            parameters: [
                ParameterMetadata(name: "maxParameters", type: .int, defaultValue: .int(5), description: "Maximum parameters per function")
            ],
            tags: ["complexity", "api-design"]
        ))
        
        register(RuleMetadata(
            id: "complexity.large-file",
            name: "Large File",
            description: "Detects files that exceed the maximum line count",
            category: .complexity,
            defaultSeverity: .info,
            parameters: [
                ParameterMetadata(name: "maxLines", type: .int, defaultValue: .int(500), description: "Maximum lines per file")
            ],
            tags: ["complexity", "organization"]
        ))
        
        // Security Rules
        register(RuleMetadata(
            id: "security.force-unwrap",
            name: "Force Unwrap",
            description: "Detects force unwrap (!) which can cause runtime crashes",
            category: .security,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["security", "safety", "crash"]
        ))
        
        register(RuleMetadata(
            id: "security.force-try",
            name: "Force Try",
            description: "Detects force try (try!) which can cause runtime crashes",
            category: .security,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["security", "safety", "crash"]
        ))
        
        register(RuleMetadata(
            id: "security.implicit-unwrap",
            name: "Implicitly Unwrapped Optional",
            description: "Detects implicitly unwrapped optionals which can cause runtime crashes",
            category: .security,
            defaultSeverity: .info,
            parameters: [],
            tags: ["security", "safety"]
        ))
        
        register(RuleMetadata(
            id: "security.hardcoded-secret",
            name: "Hardcoded Secret",
            description: "Detects potential hardcoded secrets and credentials",
            category: .security,
            defaultSeverity: .error,
            parameters: [
                ParameterMetadata(
                    name: "patterns",
                    type: .array,
                    defaultValue: .array([
                        .string("password"), .string("secret"), .string("api_key"),
                        .string("apikey"), .string("token"), .string("credential")
                    ]),
                    description: "Patterns to match for secret detection"
                )
            ],
            tags: ["security", "secrets"]
        ))
        
        register(RuleMetadata(
            id: "security.unsafe-api",
            name: "Unsafe API Usage",
            description: "Detects usage of unsafe APIs that require careful handling",
            category: .security,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["security", "memory"]
        ))
        
        // Dead Code Rules
        register(RuleMetadata(
            id: "deadcode.unreachable",
            name: "Unreachable Code",
            description: "Detects code that can never be executed",
            category: .deadCode,
            defaultSeverity: .warning,
            parameters: [],
            tags: ["deadcode", "cleanup"]
        ))
        
        register(RuleMetadata(
            id: "deadcode.unused-private",
            name: "Unused Private Member",
            description: "Detects private members that are never used",
            category: .deadCode,
            defaultSeverity: .info,
            parameters: [],
            tags: ["deadcode", "cleanup"]
        ))
        
        // Naming Rules
        register(RuleMetadata(
            id: "naming.type-case",
            name: "Type Naming Convention",
            description: "Ensures types use UpperCamelCase",
            category: .naming,
            defaultSeverity: .info,
            parameters: [],
            tags: ["naming", "style"]
        ))
        
        register(RuleMetadata(
            id: "naming.variable-case",
            name: "Variable Naming Convention",
            description: "Ensures variables use lowerCamelCase",
            category: .naming,
            defaultSeverity: .info,
            parameters: [],
            tags: ["naming", "style"]
        ))
        
        register(RuleMetadata(
            id: "naming.constant-case",
            name: "Constant Naming Convention",
            description: "Ensures constants follow naming conventions",
            category: .naming,
            defaultSeverity: .info,
            parameters: [],
            tags: ["naming", "style"]
        ))
        
        // Style Rules
        register(RuleMetadata(
            id: "style.line-length",
            name: "Line Length",
            description: "Detects lines that exceed the maximum length",
            category: .style,
            defaultSeverity: .info,
            parameters: [
                ParameterMetadata(name: "maxLength", type: .int, defaultValue: .int(120), description: "Maximum characters per line")
            ],
            tags: ["style", "formatting"]
        ))
        
        register(RuleMetadata(
            id: "style.trailing-whitespace",
            name: "Trailing Whitespace",
            description: "Detects trailing whitespace at end of lines",
            category: .style,
            defaultSeverity: .info,
            parameters: [],
            tags: ["style", "formatting"]
        ))
        
        register(RuleMetadata(
            id: "style.multiple-blank-lines",
            name: "Multiple Blank Lines",
            description: "Detects multiple consecutive blank lines",
            category: .style,
            defaultSeverity: .info,
            parameters: [],
            tags: ["style", "formatting"]
        ))
        
        register(RuleMetadata(
            id: "style.import-order",
            name: "Import Order",
            description: "Ensures imports are sorted alphabetically",
            category: .style,
            defaultSeverity: .info,
            parameters: [],
            tags: ["style", "organization"]
        ))
        
        register(RuleMetadata(
            id: "style.file-structure",
            name: "File Structure",
            description: "Ensures proper ordering of declarations (imports, types, extensions)",
            category: .style,
            defaultSeverity: .info,
            parameters: [],
            tags: ["style", "organization"]
        ))
        
        register(RuleMetadata(
            id: "style.trailing-newline",
            name: "Trailing Newline",
            description: "Ensures files end with a newline",
            category: .style,
            defaultSeverity: .info,
            parameters: [],
            tags: ["style", "formatting"]
        ))
    }
}

// MARK: - Rule Metadata

/// Metadata describing a rule
public struct RuleMetadata: Codable, Sendable, Equatable {
    
    /// Unique identifier (e.g., "complexity.long-function")
    public let id: String
    
    /// Human-readable name
    public let name: String
    
    /// Detailed description
    public let description: String
    
    /// Category for grouping
    public let category: RuleCategory
    
    /// Default severity level
    public let defaultSeverity: SeverityLevel
    
    /// Configurable parameters
    public let parameters: [ParameterMetadata]
    
    /// Tags for filtering
    public let tags: [String]
    
    /// Whether this rule is enabled by default
    public let enabledByDefault: Bool
    
    /// Documentation URL
    public let documentationURL: String?
    
    public init(
        id: String,
        name: String,
        description: String,
        category: RuleCategory,
        defaultSeverity: SeverityLevel,
        parameters: [ParameterMetadata] = [],
        tags: [String] = [],
        enabledByDefault: Bool = true,
        documentationURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.defaultSeverity = defaultSeverity
        self.parameters = parameters
        self.tags = tags
        self.enabledByDefault = enabledByDefault
        self.documentationURL = documentationURL
    }
    
    /// Create default RuleSetting from metadata
    public func defaultSetting() -> RuleSetting {
        var params: [String: ParameterValue] = [:]
        for param in parameters {
            params[param.name] = param.defaultValue
        }
        return RuleSetting(
            enabled: enabledByDefault,
            severity: defaultSeverity,
            parameters: params
        )
    }
}

// MARK: - Parameter Metadata

/// Metadata for a rule parameter
public struct ParameterMetadata: Codable, Sendable, Equatable {
    
    public let name: String
    public let type: ParameterType
    public let defaultValue: ParameterValue
    public let description: String
    public let minimum: ParameterValue?
    public let maximum: ParameterValue?
    
    public init(
        name: String,
        type: ParameterType,
        defaultValue: ParameterValue,
        description: String,
        minimum: ParameterValue? = nil,
        maximum: ParameterValue? = nil
    ) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
        self.minimum = minimum
        self.maximum = maximum
    }
}

public enum ParameterType: String, Codable, Sendable {
    case int
    case double
    case string
    case bool
    case array
}

// MARK: - Rule Category

/// Categories for organizing rules
public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case swiftUI = "swiftui"
    case complexity = "complexity"
    case security = "security"
    case deadCode = "deadcode"
    case naming = "naming"
    case style = "style"
    case performance = "performance"
    case documentation = "documentation"
    case custom = "custom"
    
    public var displayName: String {
        switch self {
        case .swiftUI: return "SwiftUI"
        case .complexity: return "Complexity"
        case .security: return "Security"
        case .deadCode: return "Dead Code"
        case .naming: return "Naming"
        case .style: return "Style"
        case .performance: return "Performance"
        case .documentation: return "Documentation"
        case .custom: return "Custom"
        }
    }
}
