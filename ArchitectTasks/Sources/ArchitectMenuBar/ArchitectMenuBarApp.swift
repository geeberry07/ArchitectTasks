import SwiftUI
import ArchitectCore
import ArchitectHost

// MARK: - Menu Bar App

@main
struct ArchitectMenuBarApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Architect", systemImage: appState.statusIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastRunResult: HostRunResult?
    @Published var pendingTasks: [AgentTask] = []
    @Published var recentFindings: [Finding] = []
    @Published var selectedProject: URL?
    @Published var selectedPolicy: String = "moderate"
    @Published var autoAnalyze: Bool = false
    
    private var host: LocalHost?
    private var fileWatcher: FileWatcher?
    
    var statusIcon: String {
        if isAnalyzing {
            return "arrow.triangle.2.circlepath"
        } else if !pendingTasks.isEmpty {
            return "exclamationmark.triangle.fill"
        } else if lastRunResult?.tasksProposed == 0 {
            return "checkmark.circle.fill"
        }
        return "hammer.fill"
    }
    
    var statusText: String {
        if isAnalyzing {
            return "Analyzing..."
        } else if !pendingTasks.isEmpty {
            return "\(pendingTasks.count) task(s) pending"
        } else if let result = lastRunResult {
            return "Last run: \(result.tasksSucceeded)/\(result.tasksProcessed) succeeded"
        }
        return "Ready"
    }
    
    // MARK: - Actions
    
    func selectProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Swift project to analyze"
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedProject = url
            setupHost()
        }
    }
    
    func analyze() async {
        guard let host = host else { return }
        
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        do {
            let findings = try await host.analyze()
            recentFindings = findings
            
            let tasks = host.proposeTasks(from: findings)
            pendingTasks = tasks
        } catch {
            print("Analysis error: \(error)")
        }
    }
    
    func approveTask(_ task: AgentTask) async {
        guard let host = host else { return }
        
        var mutableTask = task
        mutableTask.approve()
        
        do {
            let result = try await host.execute(task: mutableTask)
            await host.didComplete(task: mutableTask, result: result)
            
            // Remove from pending
            pendingTasks.removeAll { $0.id == task.id }
            
            // Update last result
            if lastRunResult == nil {
                lastRunResult = HostRunResult(
                    findings: recentFindings,
                    tasksProposed: 1,
                    tasksProcessed: 1,
                    tasksSucceeded: result.success ? 1 : 0,
                    results: [task.id: result]
                )
            }
        } catch {
            print("Execution error: \(error)")
        }
    }
    
    func rejectTask(_ task: AgentTask) {
        pendingTasks.removeAll { $0.id == task.id }
    }
    
    func approveAll() async {
        for task in pendingTasks {
            await approveTask(task)
        }
    }
    
    func rejectAll() {
        pendingTasks.removeAll()
    }
    
    // MARK: - Private
    
    private func setupHost() {
        guard let projectURL = selectedProject else { return }
        
        let policy = try? ApprovalPolicy.resolve(selectedPolicy)
        
        host = LocalHost(
            projectRoot: projectURL,
            config: .default,
            policy: policy,
            approvalHandler: { task in
                // Menu bar uses manual approval via UI
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        
        // Setup file watcher if auto-analyze is enabled
        if autoAnalyze {
            setupFileWatcher()
        }
    }
    
    private func setupFileWatcher() {
        guard let projectURL = selectedProject else { return }
        
        fileWatcher = FileWatcher(directory: projectURL) { [weak self] in
            Task { @MainActor in
                await self?.analyze()
            }
        }
    }
}

// MARK: - File Watcher

final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let callback: () -> Void
    
    init(directory: URL, callback: @escaping () -> Void) {
        self.callback = callback
        
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        
        source?.setEventHandler { [weak self] in
            self?.callback()
        }
        
        source?.setCancelHandler {
            close(fd)
        }
        
        source?.resume()
    }
    
    deinit {
        source?.cancel()
    }
}
