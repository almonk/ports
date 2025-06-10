//
//  PortsPopoverView.swift
//  Ports
//
//  Created by al on 10/06/2025.
//

import SwiftUI

struct PortsPopoverView: View {
    @EnvironmentObject var portMonitor: PortMonitor
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedPorts: Set<String> = []
    
    private var selectedPortInfos: [PortInfo] {
        return portMonitor.ports.filter { selectedPorts.contains($0.id) }
    }
    
    private var shouldShowToolbar: Bool {
        return (!searchText.isEmpty && !filteredPorts.isEmpty) || !selectedPorts.isEmpty
    }
    
    private var filteredPorts: [PortInfo] {
        if searchText.isEmpty {
            return portMonitor.ports
        } else {
            return portMonitor.ports.filter { port in
                // Check for port range (e.g., "5000-7000")
                if let portRange = parsePortRange(searchText) {
                    if let portNumber = Int(port.port) {
                        return portNumber >= portRange.lowerBound && portNumber <= portRange.upperBound
                    }
                    return false
                }
                
                // Regular search for process name or exact port
                return port.process.localizedCaseInsensitiveContains(searchText) ||
                       port.port.contains(searchText)
            }
        }
    }
    
    private func parsePortRange(_ text: String) -> ClosedRange<Int>? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Handle open-ended range (e.g., "5000-")
        if trimmed.hasSuffix("-") {
            let startText = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            if let start = Int(startText) {
                return start...65535 // Max port number
            }
            return nil
        }
        
        // Handle closed range (e.g., "5000-7000")
        let components = trimmed.components(separatedBy: "-")
        guard components.count == 2,
              let start = Int(components[0].trimmingCharacters(in: .whitespaces)),
              let end = Int(components[1].trimmingCharacters(in: .whitespaces)),
              start <= end else {
            return nil
        }
        
        return start...end
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search ports or processes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onKeyPress(.escape) {
                        if !searchText.isEmpty {
                            // First escape - clear search text
                            searchText = ""
                            return .handled
                        } else {
                            // Second escape (or first if no text) - close popover
                            closePopover()
                            return .handled
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: Rectangle())
            .onAppear {
                isSearchFocused = true
            }
            
            // Content
            if portMonitor.isLoading {
                Spacer()
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading ports...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else if filteredPorts.isEmpty && !portMonitor.ports.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor.opacity(0.6))
                    Text("No ports match '\(searchText)'")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else if portMonitor.ports.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor.opacity(0.6))
                    Text("No localhost ports found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPorts) { port in
                            VStack(spacing: 0) {
                                PortRowView(
                                    port: port, 
                                    portMonitor: portMonitor,
                                    isSelected: selectedPorts.contains(port.id),
                                    onSelectionToggle: { toggleSelection(for: port.id) }
                                )
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom))
                                ))
                                
                                if port.id != filteredPorts.last?.id {
                                    Divider()
                                        .padding(.leading, 44) // Align with content after icon
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: filteredPorts.map(\.id))
                }
            }
            
            // Bottom toolbar (appears when searching or selecting)
            if shouldShowToolbar {
                HStack {
                    if !selectedPorts.isEmpty {
                        Text("\(selectedPorts.count) selected port\(selectedPorts.count == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("\(filteredPorts.count) matching port\(filteredPorts.count == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    if !selectedPorts.isEmpty {
                        Button("Clear selection") {
                            clearSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Kill all selected") {
                            killAllSelected()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Kill all matching") {
                            killAllMatching()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: Rectangle())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowToolbar)
        .onChange(of: searchText) { _,_ in
            // Clear selection when searching
            if !searchText.isEmpty {
                selectedPorts.removeAll()
            }
        }
    }
    
    private func closePopover() {
        // Find the current window and close it
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
    
    private func toggleSelection(for portId: String) {
        if selectedPorts.contains(portId) {
            selectedPorts.remove(portId)
        } else {
            selectedPorts.insert(portId)
        }
    }
    
    private func clearSelection() {
        selectedPorts.removeAll()
    }
    
    private func killAllSelected() {
        let alert = NSAlert()
        alert.messageText = "Kill All Selected Processes"
        alert.informativeText = "Are you sure you want to kill all \(selectedPorts.count) selected processes?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            for port in selectedPortInfos {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", port.pid]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    // Continue with other processes even if one fails
                    print("Failed to kill process \(port.pid): \(error)")
                }
            }
            
            // Clear selection and refresh after killing all
            selectedPorts.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
    
    private func killAllMatching() {
        let alert = NSAlert()
        alert.messageText = "Kill All Matching Processes"
        alert.informativeText = "Are you sure you want to kill all \(filteredPorts.count) matching processes?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            for port in filteredPorts {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", port.pid]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    // Continue with other processes even if one fails
                    print("Failed to kill process \(port.pid): \(error)")
                }
            }
            
            // Clear search and refresh after killing all
            searchText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
}

struct PortRowView: View {
    let port: PortInfo
    let portMonitor: PortMonitor
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let appIcon = port.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            
            // Port number
            Text(":\(port.port)")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(minWidth: 50, alignment: .leading)
            
            // Process name and PID
            HStack(spacing: 4) {
                Text(port.process)
                    .font(.body)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Open in browser button
                Button(action: {
                    openInBrowser(port: port.port)
                }) {
                    Image(systemName: "safari")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Kill process button
                Button(action: {
                    killProcess(pid: port.pid)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .gesture(
            TapGesture()
                .modifiers(.command)
                .onEnded { _ in
                    onSelectionToggle()
                }
        )
    }
    
    private func openInBrowser(port: String) {
        let urlString = "http://localhost:\(port)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func killProcess(pid: String) {
        let alert = NSAlert()
        alert.messageText = "Kill Process"
        alert.informativeText = "Are you sure you want to kill process \(port.process) (PID: \(pid))?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = ["-9", pid]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Refresh ports after killing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    portMonitor.refreshPorts(showLoading: false)
                }
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Failed to kill process"
                errorAlert.informativeText = "Error: \(error.localizedDescription)"
                errorAlert.runModal()
            }
        }
    }
}

#Preview {
    PortsPopoverView()
        .environmentObject(PortMonitor())
}
