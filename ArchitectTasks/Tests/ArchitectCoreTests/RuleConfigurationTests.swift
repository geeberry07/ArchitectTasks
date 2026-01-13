import XCTest
@testable import ArchitectCore

final class RuleConfigurationTests: XCTestCase {
    
    // MARK: - RuleConfiguration Tests
    
    func testDefaultConfiguration() {
        let config = RulePresets.default
        XCTAssertEqual(config.name, "Default")
        XCTAssertTrue(config.rules.isEmpty)  // Uses registry defaults
        XCTAssertEqual(config.globalSettings.minimumSeverity, .info)
    }
    
    func testStrictConfiguration() {
        let config = RulePresets.strict
        XCTAssertEqual(config.name, "Strict")
        
        // Check elevated security rules
        let forceUnwrap = config.effectiveSetting(for: "security.force-unwrap")
        XCTAssertTrue(forceUnwrap.enabled)
        XCTAssertEqual(forceUnwrap.severity, .error)
        
        // Check stricter thresholds
        let longFunction = config.effectiveSetting(for: "complexity.long-function")
        XCTAssertEqual(longFunction.parameters["maxLines"]?.intValue, 40)
    }
    
    func testLenientConfiguration() {
        let config = RulePresets.lenient
        XCTAssertEqual(config.name, "Lenient")
        
        // Check disabled rules
        XCTAssertFalse(config.isEnabled("security.implicit-unwrap"))
        XCTAssertFalse(config.isEnabled("naming.type-case"))
        
        // Check relaxed thresholds
        let longFunction = config.effectiveSetting(for: "complexity.long-function")
        XCTAssertEqual(longFunction.parameters["maxLines"]?.intValue, 100)
    }
    
    func testSecurityFocusedConfiguration() {
        let config = RulePresets.securityFocused
        
        // Security rules enabled
        XCTAssertTrue(config.isEnabled("security.force-unwrap"))
        XCTAssertTrue(config.isEnabled("security.hardcoded-secret"))
        
        // Non-security rules disabled
        XCTAssertFalse(config.isEnabled("complexity.long-function"))
        XCTAssertFalse(config.isEnabled("naming.type-case"))
    }
    
    func testConfigurationMerge() {
        let base = RulePresets.default
        let overlay = RuleConfiguration(
            name: "Overlay",
            rules: [
                "security.force-unwrap": .enabled(severity: .critical)
            ]
        )
        
        let merged = base.merged(with: overlay)
        
        XCTAssertEqual(merged.name, "Overlay")
        XCTAssertEqual(merged.severity(for: "security.force-unwrap"), .critical)
    }
    
    func testEffectiveSettingFallback() {
        let config = RuleConfiguration(name: "Empty", rules: [:])
        
        // Should fall back to registry default
        let setting = config.effectiveSetting(for: "complexity.long-function")
        XCTAssertTrue(setting.enabled)
        XCTAssertEqual(setting.severity, .warning)
    }
    
    func testConfigurationValidation() {
        let config = RuleConfiguration(
            name: "Invalid",
            rules: [
                "unknown.rule": .enabled(severity: .error),
                "complexity.long-function": RuleSetting(
                    enabled: true,
                    severity: .warning,
                    parameters: ["unknownParam": .int(10)]
                )
            ]
        )
        
        let errors = config.validate()
        XCTAssertTrue(errors.contains { $0.contains("unknown.rule") })
        XCTAssertTrue(errors.contains { $0.contains("unknownParam") })
    }
    
    func testPresetResolution() {
        XCTAssertNotNil(RulePresets.resolve("strict"))
        XCTAssertNotNil(RulePresets.resolve("STRICT"))
        XCTAssertNotNil(RulePresets.resolve("security-focused"))
        XCTAssertNotNil(RulePresets.resolve("ci"))
        XCTAssertNil(RulePresets.resolve("nonexistent"))
    }
    
    // MARK: - RuleSetting Tests
    
    func testRuleSettingDisabled() {
        let setting = RuleSetting.disabled()
        XCTAssertFalse(setting.enabled)
    }
    
    func testRuleSettingEnabled() {
        let setting = RuleSetting.enabled(severity: .error)
        XCTAssertTrue(setting.enabled)
        XCTAssertEqual(setting.severity, .error)
    }
    
    // MARK: - SeverityLevel Tests
    
    func testSeverityLevelComparison() {
        XCTAssertTrue(SeverityLevel.info < SeverityLevel.warning)
        XCTAssertTrue(SeverityLevel.warning < SeverityLevel.error)
        XCTAssertTrue(SeverityLevel.error < SeverityLevel.critical)
        XCTAssertTrue(SeverityLevel.ignore < SeverityLevel.info)
    }
    
    func testSeverityToFindingSeverity() {
        XCTAssertEqual(SeverityLevel.critical.toFindingSeverity, .critical)
        XCTAssertEqual(SeverityLevel.error.toFindingSeverity, .error)
        XCTAssertEqual(SeverityLevel.warning.toFindingSeverity, .warning)
        XCTAssertEqual(SeverityLevel.info.toFindingSeverity, .info)
    }
    
    // MARK: - ParameterValue Tests
    
    func testParameterValueInt() {
        let value = ParameterValue.int(42)
        XCTAssertEqual(value.intValue, 42)
        XCTAssertEqual(value.doubleValue, 42.0)
        XCTAssertNil(value.stringValue)
    }
    
    func testParameterValueDouble() {
        let value = ParameterValue.double(3.14)
        XCTAssertEqual(value.doubleValue, 3.14)
        XCTAssertNil(value.intValue)
    }
    
    func testParameterValueString() {
        let value = ParameterValue.string("test")
        XCTAssertEqual(value.stringValue, "test")
        XCTAssertNil(value.intValue)
    }
    
    func testParameterValueBool() {
        let value = ParameterValue.bool(true)
        XCTAssertEqual(value.boolValue, true)
        XCTAssertNil(value.intValue)
    }
    
    // MARK: - RuleRegistry Tests
    
    func testRuleRegistryBuiltInRules() {
        let registry = RuleRegistry.shared
        
        // Check some built-in rules exist
        XCTAssertNotNil(registry.metadata(for: "security.force-unwrap"))
        XCTAssertNotNil(registry.metadata(for: "complexity.long-function"))
        XCTAssertNotNil(registry.metadata(for: "swiftui.missing-state-object"))
    }
    
    func testRuleRegistryCategories() {
        let registry = RuleRegistry.shared
        
        let securityRules = registry.rules(in: .security)
        XCTAssertFalse(securityRules.isEmpty)
        XCTAssertTrue(securityRules.allSatisfy { $0.category == .security })
        
        let complexityRules = registry.rules(in: .complexity)
        XCTAssertFalse(complexityRules.isEmpty)
    }
    
    func testRuleRegistryTags() {
        let registry = RuleRegistry.shared
        
        let crashRules = registry.rules(withTag: "crash")
        XCTAssertFalse(crashRules.isEmpty)
        XCTAssertTrue(crashRules.allSatisfy { $0.tags.contains("crash") })
    }
    
    func testRuleMetadataDefaultSetting() {
        let metadata = RuleRegistry.shared.metadata(for: "complexity.long-function")!
        let setting = metadata.defaultSetting()
        
        XCTAssertTrue(setting.enabled)
        XCTAssertEqual(setting.severity, .warning)
        XCTAssertEqual(setting.parameters["maxLines"]?.intValue, 50)
    }
    
    // MARK: - GlobalSettings Tests
    
    func testGlobalSettingsDefault() {
        let settings = GlobalSettings.default
        XCTAssertEqual(settings.minimumSeverity, .info)
        XCTAssertFalse(settings.failOnError)
        XCTAssertTrue(settings.failOnCritical)
    }
    
    func testGlobalSettingsStrict() {
        let settings = GlobalSettings.strict
        XCTAssertTrue(settings.failOnError)
        XCTAssertTrue(settings.failOnCritical)
    }
    
    // MARK: - JSON Serialization Tests
    
    func testConfigurationJSONRoundTrip() throws {
        let original = RulePresets.strict
        let json = try original.toJSON()
        let decoded = try JSONDecoder().decode(RuleConfiguration.self, from: json)
        
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.rules.count, original.rules.count)
    }
    
    func testParameterValueJSONRoundTrip() throws {
        let values: [ParameterValue] = [
            .int(42),
            .double(3.14),
            .string("test"),
            .bool(true),
            .array([.int(1), .int(2), .int(3)])
        ]
        
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }
    
    // MARK: - Generate Default Tests
    
    func testGenerateDefaultConfiguration() {
        let config = RuleConfiguration.generateDefault()
        
        // Should have all registered rules
        let allRules = RuleRegistry.shared.allRules
        XCTAssertEqual(config.rules.count, allRules.count)
        
        // Each rule should have its default setting
        for metadata in allRules {
            let setting = config.rules[metadata.id]
            XCTAssertNotNil(setting)
            XCTAssertEqual(setting?.enabled, metadata.enabledByDefault)
            XCTAssertEqual(setting?.severity, metadata.defaultSeverity)
        }
    }
}
