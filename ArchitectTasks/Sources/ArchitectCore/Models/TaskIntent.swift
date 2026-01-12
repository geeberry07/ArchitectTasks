import Foundation

// MARK: - Intent Protocol (Extensible)

/// Protocol for custom task intents
public protocol TaskIntentProtocol: Codable, Sendable {
    var category: IntentCategory { get }
    var description: String { get }
}

public enum IntentCategory: String, Codable, Sendable {
    case structural
    case dataFlow
    case quality
    case architecture
    case documentation
}

// MARK: - Default Task Intents

/// Built-in task intents covering common scenarios
public enum TaskIntent: Codable, Hashable, Sendable, TaskIntentProtocol {
    
    // Structural
    case wireUI(source: String, target: String)
    case extractComponent(from: String)
    case injectDependency(type: String, into: String)
    
    // Data Flow
    case addBinding(property: String, in: String)
    case addStateObject(property: String, type: String, in: String)
    case createViewModel(for: String)
    case connectToStore(view: String, store: String)
    
    // Quality
    case addTest(for: String, type: TestType)
    case fixWarning(diagnostic: String, in: String)
    case removeDeadCode(in: String)
    case extractFunction(from: String, in: String)
    case reduceNesting(in: String, at: Int)
    case splitFile(path: String)
    case reduceParameters(function: String, in: String)
    
    // Architecture
    case enforceModuleBoundary(from: String, to: String)
    case applyPattern(pattern: ArchPattern, to: String)
    case refactorToProtocol(concrete: String)
    
    // Documentation
    case documentPublicAPI(in: String)
    case addInlineComment(at: String, reason: String)
    
    // MARK: - Nested Types
    
    public enum TestType: String, Codable, Sendable {
        case unit, integration, snapshot, ui
    }
    
    public enum ArchPattern: String, Codable, Sendable {
        case mvvm, coordinator, repository, factory, observer
    }
    
    // MARK: - Protocol Conformance
    
    public var category: IntentCategory {
        switch self {
        case .wireUI, .extractComponent, .injectDependency:
            return .structural
        case .addBinding, .addStateObject, .createViewModel, .connectToStore:
            return .dataFlow
        case .addTest, .fixWarning, .removeDeadCode, .extractFunction, .reduceNesting, .splitFile, .reduceParameters:
            return .quality
        case .enforceModuleBoundary, .applyPattern, .refactorToProtocol:
            return .architecture
        case .documentPublicAPI, .addInlineComment:
            return .documentation
        }
    }
    
    public var description: String {
        switch self {
        case .wireUI(let source, let target):
            return "Wire \(source) to \(target)"
        case .extractComponent(let from):
            return "Extract component from \(from)"
        case .injectDependency(let type, let into):
            return "Inject \(type) into \(into)"
        case .addBinding(let property, let view):
            return "Add binding '\(property)' to \(view)"
        case .addStateObject(let property, let type, let view):
            return "Add @StateObject '\(property): \(type)' to \(view)"
        case .createViewModel(let view):
            return "Create ViewModel for \(view)"
        case .connectToStore(let view, let store):
            return "Connect \(view) to \(store)"
        case .addTest(let target, let type):
            return "Add \(type.rawValue) test for \(target)"
        case .fixWarning(let diagnostic, let file):
            return "Fix '\(diagnostic)' in \(file)"
        case .removeDeadCode(let file):
            return "Remove dead code in \(file)"
        case .extractFunction(let function, let file):
            return "Extract function from '\(function)' in \(file)"
        case .reduceNesting(let file, let line):
            return "Reduce nesting depth at line \(line) in \(file)"
        case .splitFile(let path):
            return "Split large file \(path)"
        case .reduceParameters(let function, let file):
            return "Reduce parameters in '\(function)' in \(file)"
        case .enforceModuleBoundary(let from, let to):
            return "Enforce boundary: \(from) → \(to)"
        case .applyPattern(let pattern, let target):
            return "Apply \(pattern.rawValue) to \(target)"
        case .refactorToProtocol(let concrete):
            return "Extract protocol from \(concrete)"
        case .documentPublicAPI(let file):
            return "Document public API in \(file)"
        case .addInlineComment(let location, _):
            return "Add comment at \(location)"
        }
    }
}
