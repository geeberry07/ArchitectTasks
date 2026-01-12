import Foundation

/// Defines the boundary of what a task can touch
public enum TaskScope: Codable, Hashable, Sendable {
    case file(path: String)
    case module(name: String)
    case feature(name: String)
    case project
    
    public var allowedPaths: [String] {
        switch self {
        case .file(let path):
            return [path]
        case .module(let name):
            return ["Sources/\(name)/**"]
        case .feature(let name):
            return ["Features/\(name)/**"]
        case .project:
            return ["**"]
        }
    }
    
    public var description: String {
        switch self {
        case .file(let path): return "file: \(path)"
        case .module(let name): return "module: \(name)"
        case .feature(let name): return "feature: \(name)"
        case .project: return "project-wide"
        }
    }
}
