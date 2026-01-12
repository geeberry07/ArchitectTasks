import Foundation

// MARK: - Run Store Protocol

/// Protocol for persisting task runs.
/// Implementations: FileStore, SQLiteStore, SwiftDataStore, etc.
public protocol RunStore: Sendable {
    /// Save a task run
    func save(_ run: TaskRun) async throws
    
    /// Load a task run by ID
    func load(id: UUID) async throws -> TaskRun?
    
    /// Load all runs for a project
    func loadRuns(forProject path: String) async throws -> [TaskRun]
    
    /// Load recent runs
    func loadRecent(limit: Int) async throws -> [TaskRun]
    
    /// Query runs by outcome
    func loadRuns(withOutcome outcome: RunOutcome) async throws -> [TaskRun]
    
    /// Delete a run
    func delete(id: UUID) async throws
    
    /// Delete all runs older than date
    func deleteOlderThan(_ date: Date) async throws -> Int
}

// MARK: - File-Based Run Store

/// Simple file-based persistence using JSON.
/// Good for development and single-user scenarios.
public actor FileRunStore: RunStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(directory: URL) {
        self.directory = directory
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /// Default store location
    public static func `default`() throws -> FileRunStore {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let dir = appSupport.appendingPathComponent("ArchitectTasks/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        return FileRunStore(directory: dir)
    }
    
    // MARK: - RunStore Protocol
    
    public func save(_ run: TaskRun) async throws {
        let file = fileURL(for: run.id)
        let data = try encoder.encode(run)
        try data.write(to: file)
    }
    
    public func load(id: UUID) async throws -> TaskRun? {
        let file = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        let data = try Data(contentsOf: file)
        return try decoder.decode(TaskRun.self, from: data)
    }
    
    public func loadRuns(forProject path: String) async throws -> [TaskRun] {
        try await loadAll().filter { $0.projectPath == path }
    }
    
    public func loadRecent(limit: Int) async throws -> [TaskRun] {
        let all = try await loadAll()
        return Array(all.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }
    
    public func loadRuns(withOutcome outcome: RunOutcome) async throws -> [TaskRun] {
        try await loadAll().filter { $0.outcome == outcome }
    }
    
    public func delete(id: UUID) async throws {
        let file = fileURL(for: id)
        try FileManager.default.removeItem(at: file)
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let all = try await loadAll()
        var deleted = 0
        
        for run in all where run.startedAt < date {
            try await delete(id: run.id)
            deleted += 1
        }
        
        return deleted
    }
    
    // MARK: - Private
    
    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
    
    private func loadAll() throws -> [TaskRun] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let run = try? decoder.decode(TaskRun.self, from: data) else {
                return nil
            }
            return run
        }
    }
}

// MARK: - In-Memory Store (for testing)

public actor InMemoryRunStore: RunStore {
    private var runs: [UUID: TaskRun] = [:]
    
    public init() {}
    
    public func save(_ run: TaskRun) async throws {
        runs[run.id] = run
    }
    
    public func load(id: UUID) async throws -> TaskRun? {
        runs[id]
    }
    
    public func loadRuns(forProject path: String) async throws -> [TaskRun] {
        runs.values.filter { $0.projectPath == path }
    }
    
    public func loadRecent(limit: Int) async throws -> [TaskRun] {
        Array(runs.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }
    
    public func loadRuns(withOutcome outcome: RunOutcome) async throws -> [TaskRun] {
        runs.values.filter { $0.outcome == outcome }
    }
    
    public func delete(id: UUID) async throws {
        runs.removeValue(forKey: id)
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let toDelete = runs.values.filter { $0.startedAt < date }.map(\.id)
        for id in toDelete {
            runs.removeValue(forKey: id)
        }
        return toDelete.count
    }
}
