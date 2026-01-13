import Foundation

// MARK: - Rule Presets

/// Built-in rule configuration presets for common use cases
public enum RulePresets {
    
    /// Default configuration - balanced settings
    public static let `default` = RuleConfiguration(
        name: "Default",
        description: "Balanced configuration suitable for most projects",
        version: "1.0.0",
        rules: [:],  // Uses all defaults from registry
        globalSettings: .default
    )
    
    /// Strict configuration - all rules enabled at higher severity
    public static let strict: RuleConfiguration = {
        var rules: [String: RuleSetting] = [:]
        
        // Elevate all security rules to error
        rules["security.force-unwrap"] = .enabled(severity: .error)
        rules["security.force-try"] = .enabled(severity: .error)
        rules["security.implicit-unwrap"] = .enabled(severity: .warning)
        rules["security.hardcoded-secret"] = .enabled(severity: .critical)
        rules["security.unsafe-api"] = .enabled(severity: .error)
        
        // Elevate complexity rules
        rules["complexity.long-function"] = RuleSetting(
            enabled: true,
            severity: .error,
            parameters: ["maxLines": .int(40)]  // Stricter threshold
        )
        rules["complexity.deep-nesting"] = RuleSetting(
            enabled: true,
            severity: .error,
            parameters: ["maxDepth": .int(3)]  // Stricter threshold
        )
        rules["complexity.cyclomatic"] = RuleSetting(
            enabled: true,
            severity: .error,
            parameters: ["maxComplexity": .int(8)]  // Stricter threshold
        )
        
        return RuleConfiguration(
            name: "Strict",
            description: "Strict configuration for high-quality codebases",
            version: "1.0.0",
            rules: rules,
            globalSettings: .strict
        )
    }()
    
    /// Lenient configuration - fewer rules, lower severity
    public static let lenient: RuleConfiguration = {
        var rules: [String: RuleSetting] = [:]
        
        // Disable info-level rules
        rules["security.implicit-unwrap"] = .disabled()
        rules["complexity.large-file"] = .disabled()
        rules["naming.type-case"] = .disabled()
        rules["naming.variable-case"] = .disabled()
        rules["naming.constant-case"] = .disabled()
        rules["deadcode.unused-private"] = .disabled()
        
        // Relax thresholds
        rules["complexity.long-function"] = RuleSetting(
            enabled: true,
            severity: .info,
            parameters: ["maxLines": .int(100)]
        )
        rules["complexity.deep-nesting"] = RuleSetting(
            enabled: true,
            severity: .info,
            parameters: ["maxDepth": .int(6)]
        )
        
        return RuleConfiguration(
            name: "Lenient",
            description: "Relaxed configuration for rapid development",
            version: "1.0.0",
            rules: rules,
            globalSettings: .lenient
        )
    }()
    
    /// Security-focused configuration
    public static let securityFocused: RuleConfiguration = {
        var rules: [String: RuleSetting] = [:]
        
        // Enable all security rules at high severity
        rules["security.force-unwrap"] = .enabled(severity: .error)
        rules["security.force-try"] = .enabled(severity: .error)
        rules["security.implicit-unwrap"] = .enabled(severity: .warning)
        rules["security.hardcoded-secret"] = .enabled(severity: .critical)
        rules["security.unsafe-api"] = .enabled(severity: .error)
        
        // Disable non-security rules
        rules["complexity.long-function"] = .disabled()
        rules["complexity.deep-nesting"] = .disabled()
        rules["complexity.cyclomatic"] = .disabled()
        rules["complexity.too-many-parameters"] = .disabled()
        rules["complexity.large-file"] = .disabled()
        rules["naming.type-case"] = .disabled()
        rules["naming.variable-case"] = .disabled()
        rules["naming.constant-case"] = .disabled()
        rules["deadcode.unreachable"] = .disabled()
        rules["deadcode.unused-private"] = .disabled()
        
        return RuleConfiguration(
            name: "Security Focused",
            description: "Configuration focused on security issues only",
            version: "1.0.0",
            rules: rules,
            globalSettings: GlobalSettings(
                minimumSeverity: .warning,
                failOnError: true,
                failOnCritical: true
            )
        )
    }()
    
    /// SwiftUI-focused configuration
    public static let swiftUIFocused: RuleConfiguration = {
        var rules: [String: RuleSetting] = [:]
        
        // Enable all SwiftUI rules at high severity
        rules["swiftui.missing-state-object"] = .enabled(severity: .error)
        rules["swiftui.missing-observed-object"] = .enabled(severity: .error)
        rules["swiftui.missing-binding"] = .enabled(severity: .warning)
        
        // Keep complexity rules but at lower severity
        rules["complexity.long-function"] = .enabled(severity: .info)
        rules["complexity.deep-nesting"] = .enabled(severity: .info)
        
        return RuleConfiguration(
            name: "SwiftUI Focused",
            description: "Configuration optimized for SwiftUI projects",
            version: "1.0.0",
            rules: rules,
            globalSettings: .default
        )
    }()
    
    /// CI/CD configuration - fail on important issues
    public static let ci: RuleConfiguration = {
        var rules: [String: RuleSetting] = [:]
        
        // Security issues should fail CI
        rules["security.hardcoded-secret"] = .enabled(severity: .critical)
        rules["security.force-unwrap"] = .enabled(severity: .warning)
        rules["security.force-try"] = .enabled(severity: .warning)
        
        // SwiftUI issues should fail CI
        rules["swiftui.missing-state-object"] = .enabled(severity: .error)
        
        // Complexity as warnings only
        rules["complexity.long-function"] = .enabled(severity: .warning)
        rules["complexity.cyclomatic"] = .enabled(severity: .warning)
        
        // Disable style/naming in CI
        rules["naming.type-case"] = .disabled()
        rules["naming.variable-case"] = .disabled()
        rules["naming.constant-case"] = .disabled()
        
        return RuleConfiguration(
            name: "CI/CD",
            description: "Configuration for continuous integration pipelines",
            version: "1.0.0",
            rules: rules,
            globalSettings: GlobalSettings(
                minimumSeverity: .warning,
                failOnError: true,
                failOnCritical: true,
                parallelAnalysis: true
            )
        )
    }()
    
    /// Get all available presets
    public static var all: [RuleConfiguration] {
        [Self.default, Self.strict, Self.lenient, Self.securityFocused, Self.swiftUIFocused, Self.ci]
    }
    
    /// Resolve a preset by name
    public static func resolve(_ name: String) -> RuleConfiguration? {
        switch name.lowercased() {
        case "default": return Self.default
        case "strict": return Self.strict
        case "lenient": return Self.lenient
        case "security", "security-focused", "securityfocused": return Self.securityFocused
        case "swiftui", "swiftui-focused", "swiftuifocused": return Self.swiftUIFocused
        case "ci", "ci-cd", "cicd": return Self.ci
        default: return nil
        }
    }
}

// MARK: - Configuration Loading

extension RuleConfiguration {
    
    /// Load configuration from a JSON file
    public static func load(from url: URL) throws -> RuleConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuleConfiguration.self, from: data)
    }
    
    /// Save configuration to a JSON file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    /// Export to JSON data
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Resolve configuration from name or path
    public static func resolve(_ nameOrPath: String) throws -> RuleConfiguration {
        // Try preset first
        if let preset = RulePresets.resolve(nameOrPath) {
            return preset
        }
        
        // Try loading from file
        let url = URL(fileURLWithPath: nameOrPath)
        if FileManager.default.fileExists(atPath: url.path) {
            return try load(from: url)
        }
        
        throw ConfigurationError.notFound(nameOrPath)
    }
    
    /// Merge with another configuration (other takes precedence)
    public func merged(with other: RuleConfiguration) -> RuleConfiguration {
        var mergedRules = self.rules
        for (key, value) in other.rules {
            mergedRules[key] = value
        }
        
        return RuleConfiguration(
            id: other.id,
            name: other.name,
            description: other.description,
            version: other.version,
            rules: mergedRules,
            globalSettings: other.globalSettings,
            includePatterns: other.includePatterns.isEmpty ? self.includePatterns : other.includePatterns,
            excludePatterns: other.excludePatterns.isEmpty ? self.excludePatterns : other.excludePatterns
        )
    }
    
    /// Get effective setting for a rule (with defaults)
    public func effectiveSetting(for ruleId: String) -> RuleSetting {
        if let setting = rules[ruleId] {
            return setting
        }
        
        // Fall back to registry default
        if let metadata = RuleRegistry.shared.metadata(for: ruleId) {
            return metadata.defaultSetting()
        }
        
        // Ultimate fallback
        return RuleSetting()
    }
    
    /// Check if a rule is enabled
    public func isEnabled(_ ruleId: String) -> Bool {
        effectiveSetting(for: ruleId).enabled
    }
    
    /// Get severity for a rule
    public func severity(for ruleId: String) -> SeverityLevel {
        effectiveSetting(for: ruleId).severity
    }
    
    /// Get parameter value for a rule
    public func parameter(_ name: String, for ruleId: String) -> ParameterValue? {
        effectiveSetting(for: ruleId).parameters[name]
    }
}

// MARK: - Configuration Error

public enum ConfigurationError: Error, LocalizedError {
    case notFound(String)
    case invalidFormat(String)
    case validationFailed([String])
    
    public var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Configuration not found: \(name)"
        case .invalidFormat(let reason):
            return "Invalid configuration format: \(reason)"
        case .validationFailed(let errors):
            return "Configuration validation failed:\n" + errors.joined(separator: "\n")
        }
    }
}

// MARK: - Configuration Validation

extension RuleConfiguration {
    
    /// Validate the configuration
    public func validate() -> [String] {
        var errors: [String] = []
        
        // Check for unknown rules
        for ruleId in rules.keys {
            if RuleRegistry.shared.metadata(for: ruleId) == nil {
                errors.append("Unknown rule: \(ruleId)")
            }
        }
        
        // Validate parameters
        for (ruleId, setting) in rules {
            guard let metadata = RuleRegistry.shared.metadata(for: ruleId) else { continue }
            
            for (paramName, _) in setting.parameters {
                if !metadata.parameters.contains(where: { $0.name == paramName }) {
                    errors.append("Unknown parameter '\(paramName)' for rule '\(ruleId)'")
                }
            }
        }
        
        return errors
    }
    
    /// Generate a default configuration with all rules
    public static func generateDefault() -> RuleConfiguration {
        var rules: [String: RuleSetting] = [:]
        
        for metadata in RuleRegistry.shared.allRules {
            rules[metadata.id] = metadata.defaultSetting()
        }
        
        return RuleConfiguration(
            name: "Generated Default",
            description: "Auto-generated configuration with all rules at default settings",
            version: "1.0.0",
            rules: rules,
            globalSettings: .default
        )
    }
}
