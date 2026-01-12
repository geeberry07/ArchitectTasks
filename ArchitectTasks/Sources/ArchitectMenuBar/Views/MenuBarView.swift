import SwiftUI
import ArchitectCore
import ArchitectHost

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HeaderView()
            
            Divider()
            
            // Project Selection
            ProjectSection()
            
            Divider()
            
            // Status & Actions
            StatusSection()
            
            if !appState.pendingTasks.isEmpty {
                Divider()
                TasksSection()
            }
            
            Divider()
            
            // Footer
            FooterView()
        }
        .frame(width: 320)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack {
            Image(systemName: appState.statusIcon)
                .foregroundColor(statusColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ArchitectTasks")
                    .font(.headline)
                Text(appState.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    var statusColor: Color {
        if appState.isAnalyzing {
            return .blue
        } else if !appState.pendingTasks.isEmpty {
            return .orange
        }
        return .green
    }
}

// MARK: - Project Section

private struct ProjectSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = appState.selectedProject {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(project.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Change") {
                        appState.selectProject()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else {
                Button(action: { appState.selectProject() }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Select Project")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Status Section

private struct StatusSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    Task { await appState.analyze() }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Analyze")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.selectedProject == nil || appState.isAnalyzing)
                
                Spacer()
                
                Picker("Policy", selection: $appState.selectedPolicy) {
                    Text("Conservative").tag("conservative")
                    Text("Moderate").tag("moderate")
                    Text("Permissive").tag("permissive")
                    Text("Strict").tag("strict")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            if let result = appState.lastRunResult {
                HStack(spacing: 16) {
                    StatView(label: "Findings", value: result.findings.count)
                    StatView(label: "Tasks", value: result.tasksProposed)
                    StatView(label: "Succeeded", value: result.tasksSucceeded)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct StatView: View {
    let label: String
    let value: Int
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Tasks Section

private struct TasksSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pending Tasks")
                    .font(.headline)
                Spacer()
                Button("Approve All") {
                    Task { await appState.approveAll() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                
                Button("Reject All") {
                    appState.rejectAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.red)
            }
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.pendingTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct TaskRow: View {
    @EnvironmentObject var appState: AppState
    let task: AgentTask
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    CategoryBadge(category: task.intent.category)
                    Text("\(Int(task.confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Button(action: {
                    Task { await appState.approveTask(task) }
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    appState.rejectTask(task)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

private struct CategoryBadge: View {
    let category: IntentCategory
    
    var body: some View {
        Text(category.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.2))
            .foregroundColor(categoryColor)
            .cornerRadius(4)
    }
    
    var categoryColor: Color {
        switch category {
        case .documentation: return .blue
        case .quality: return .green
        case .dataFlow: return .orange
        case .structural: return .purple
        case .architecture: return .red
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    var body: some View {
        HStack {
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text("Quit")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            
            Spacer()
            
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
