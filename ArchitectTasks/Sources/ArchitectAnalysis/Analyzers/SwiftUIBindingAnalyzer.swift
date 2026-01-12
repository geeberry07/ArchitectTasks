import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

/// Analyzes SwiftUI views for missing state management patterns
public final class SwiftUIBindingAnalyzer: Analyzer, Sendable {
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.missingBinding, .missingStateObject, .missingEnvironmentObject]
    }
    
    public init() {}
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        let sourceFile = Parser.parse(source: content)
        let visitor = SwiftUIVisitor(filePath: path)
        visitor.walk(sourceFile)
        return visitor.findings
    }
}

// MARK: - Syntax Visitor

private final class SwiftUIVisitor: SyntaxVisitor {
    let filePath: String
    var findings: [Finding] = []
    
    // Track what we find in each struct
    private var currentStructName: String?
    private var currentStructProperties: [PropertyInfo] = []
    private var currentStructUsedIdentifiers: Set<String> = []
    
    struct PropertyInfo {
        let name: String
        let type: String?
        let hasStateWrapper: Bool
        let hasBindingWrapper: Bool
        let hasObservedWrapper: Bool
        let hasEnvironmentWrapper: Bool
        let line: Int
    }
    
    init(filePath: String) {
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this struct conforms to View
        let isView = node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "View"
        } ?? false
        
        if isView {
            currentStructName = node.name.text
            currentStructProperties = []
            currentStructUsedIdentifiers = []
        }
        
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        guard let structName = currentStructName else { return }
        
        // Analyze the collected data
        analyzeViewStruct(name: structName)
        
        // Reset
        currentStructName = nil
        currentStructProperties = []
        currentStructUsedIdentifiers = []
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard currentStructName != nil else { return .visitChildren }
        
        // Check for property wrappers
        let attributes = node.attributes
        let hasState = hasAttribute(attributes, named: "State")
        let hasBinding = hasAttribute(attributes, named: "Binding")
        let hasObserved = hasAttribute(attributes, named: "ObservedObject") || 
                          hasAttribute(attributes, named: "StateObject")
        let hasEnvironment = hasAttribute(attributes, named: "EnvironmentObject") ||
                             hasAttribute(attributes, named: "Environment")
        
        // Extract property info
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription
                let line = node.startLocation(converter: SourceLocationConverter(
                    fileName: filePath,
                    tree: node.root
                )).line
                
                currentStructProperties.append(PropertyInfo(
                    name: pattern.identifier.text,
                    type: typeAnnotation,
                    hasStateWrapper: hasState,
                    hasBindingWrapper: hasBinding,
                    hasObservedWrapper: hasObserved,
                    hasEnvironmentWrapper: hasEnvironment,
                    line: line
                ))
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard currentStructName != nil else { return .visitChildren }
        currentStructUsedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    // MARK: - Analysis Logic
    
    private func analyzeViewStruct(name: String) {
        // Find properties that look like they should be observed but aren't
        for prop in currentStructProperties {
            // Heuristic: property type ends with "ViewModel" or "Store" but has no wrapper
            if let type = prop.type {
                let needsObservation = type.hasSuffix("ViewModel") || 
                                       type.hasSuffix("Store") ||
                                       type.hasSuffix("Model")
                
                let hasAnyWrapper = prop.hasStateWrapper || 
                                    prop.hasBindingWrapper || 
                                    prop.hasObservedWrapper ||
                                    prop.hasEnvironmentWrapper
                
                if needsObservation && !hasAnyWrapper {
                    findings.append(Finding(
                        type: .missingStateObject,
                        location: SourceLocation(file: filePath, line: prop.line),
                        severity: .warning,
                        context: [
                            "property": prop.name,
                            "type": type,
                            "view": name
                        ],
                        message: "Property '\(prop.name)' of type '\(type)' in \(name) may need @StateObject or @ObservedObject"
                    ))
                }
            }
        }
    }
    
    private func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == name
            }
            return false
        }
    }
}
