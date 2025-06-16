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
    @State private var isGroupedView = UserDefaults.standard.bool(forKey: "PortsGroupedViewMode")
    @State private var wasGroupedBeforeSearch = false
    @State private var isKillingProcess = false
    
    private static let groupedViewModeKey = "PortsGroupedViewMode"
    
    private var selectedPortInfos: [PortInfo] {
        return portMonitor.ports.filter { selectedPorts.contains($0.id) }
    }
    
    private var shouldShowToolbar: Bool {
        return (!searchText.isEmpty && !filteredPorts.isEmpty) || !selectedPorts.isEmpty
    }
    
    private var shouldShowKillingBanner: Bool {
        return isKillingProcess
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
    
    private var groupedPorts: [(String, [PortInfo])] {
        let grouped = Dictionary(grouping: filteredPorts) { $0.process }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { Int($0.port) ?? 0 < Int($1.port) ?? 0 }) }
    }
    
    private var singleProcessGroups: [PortInfo] {
        return groupedPorts.filter { $0.1.count == 1 }.flatMap { $0.1 }.sorted { Int($0.port) ?? 0 < Int($1.port) ?? 0 }
    }
    
    private var multiProcessGroups: [(String, [PortInfo])] {
        return groupedPorts.filter { $0.1.count > 1 }
    }
    
    private var effectiveIsGroupedView: Bool {
        // Force flat view when searching
        return !searchText.isEmpty ? false : isGroupedView
    }
    
    private var animationValue: [String] {
        if effectiveIsGroupedView {
            return singleProcessGroups.map(\.id) + multiProcessGroups.flatMap { $0.1.map(\.id) }
        } else {
            return filteredPorts.map(\.id)
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
            searchBarView
            contentView
        }
        .frame(minWidth: 300, minHeight: 300)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowToolbar)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowKillingBanner)
        .onChange(of: searchText) { oldValue, newValue in
            // Clear selection when searching
            if !newValue.isEmpty {
                selectedPorts.removeAll()
                // Save current view mode and switch to flat view
                if oldValue.isEmpty && isGroupedView {
                    wasGroupedBeforeSearch = true
                }
            } else {
                // Restore previous view mode when search is cleared
                if oldValue != newValue && wasGroupedBeforeSearch {
                    isGroupedView = true
                    wasGroupedBeforeSearch = false
                }
            }
        }
    }
    
    private var searchBarView: some View {
        HStack {
            searchIcon
            searchTextField
            clearButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onAppear {
            isSearchFocused = true
        }
    }
    
    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
            .font(.system(size: 13))
            .opacity(0.7)
    }
    
    private var searchTextField: some View {
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
    }
    
    private var clearButton: some View {
        Group {
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            mainContentArea
            bottomToolbarArea
        }
    }
    
    private var mainContentArea: some View {
        Group {
            if portMonitor.isLoading {
                loadingView
            } else if filteredPorts.isEmpty && !portMonitor.ports.isEmpty {
                noMatchesView
            } else if portMonitor.ports.isEmpty {
                noPortsView
            } else {
                portsListView
            }
        }
    }
    
    private var loadingView: some View {
        VStack {
            Spacer()
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading ports...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }
    
    private var noMatchesView: some View {
        VStack {
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
        }
    }
    
    private var noPortsView: some View {
        VStack {
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
        }
    }
    
    private var portsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if effectiveIsGroupedView {
                    groupedPortsView
                } else {
                    flatPortsView
                }
            }
            .padding(.bottom, 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: animationValue)
        }
        .contextMenu {
            Button(action: {
                toggleViewMode()
            }) {
                HStack {
                    Image(systemName: isGroupedView ? "list.bullet" : "rectangle.3.group")
                    Text(isGroupedView ? "Show Flat View" : "Show Grouped View")
                }
            }
        }
    }
    
    private var groupedPortsView: some View {
        Group {
            // Single-process groups at top (flat style)
            ForEach(Array(singleProcessGroups.enumerated()), id: \.element.id) { index, port in
                VStack(spacing: 0) {
                    PortRowView(
                        port: port, 
                        portMonitor: portMonitor,
                        isSelected: selectedPorts.contains(port.id),
                        onSelectionToggle: { toggleSelection(for: port.id) },
                        isGroupedView: isGroupedView,
                        onViewToggle: { toggleViewMode() },
                        onKillProcess: { 
                            print("Killing process: \(port.process) with PID: \(port.pid) on port: \(port.port)")
                            killSingleProcess(pid: port.pid) 
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                        removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .leading))
                    ))
                    
                    if index < singleProcessGroups.count - 1 {
                        Divider()
                            .padding(.leading, 44) // Align with content after icon
                    }
                }
            }
            
            // Separator between single and multi-process groups
            if !singleProcessGroups.isEmpty && !multiProcessGroups.isEmpty {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 16)
            }
            
            // Multi-process groups with headers
            ForEach(Array(multiProcessGroups.enumerated()), id: \.offset) { groupIndex, group in
                let (processName, ports) = group
                
                VStack(spacing: 0) {
                    // Section header
                    HStack(spacing: 12) {
                        // App icon aligned with row icons
                        if let appIcon = ports.first?.appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .cornerRadius(3)
                        } else {
                            let terminalIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
                            Image(nsImage: terminalIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .cornerRadius(3)
                        }
                        
                        Text(processName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contextMenu {
                        Button("Kill all \(processName) processes") {
                            killProcessGroup(processName: processName, ports: ports)
                        }
                    }
                    
                    // Bottom separator
                    Rectangle()
                        .fill(.separator.opacity(0.3))
                        .frame(height: 0.5)
                    
                    // Ports for this process
                    ForEach(Array(ports.enumerated()), id: \.element.id) { portIndex, port in
                        VStack(spacing: 0) {
                            PortRowView(
                                port: port, 
                                portMonitor: portMonitor,
                                isSelected: selectedPorts.contains(port.id),
                                onSelectionToggle: { toggleSelection(for: port.id) },
                                isGroupedView: isGroupedView,
                                onViewToggle: { toggleViewMode() },
                                onKillProcess: { 
                            print("Killing process: \(port.process) with PID: \(port.pid) on port: \(port.port)")
                            killSingleProcess(pid: port.pid) 
                        }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .leading))
                            ))
                            
                            // Add divider between ports within the same group
                            if portIndex < ports.count - 1 {
                                Divider()
                                    .padding(.leading, 44) // Align with content after icon
                            }
                        }
                    }
                    
                    // Add spacing between groups
                    if groupIndex < multiProcessGroups.count - 1 {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 8)
                    }
                }
            }
        }
    }
    
    private var flatPortsView: some View {
        ForEach(Array(filteredPorts.enumerated()), id: \.element.id) { index, port in
            VStack(spacing: 0) {
                PortRowView(
                    port: port, 
                    portMonitor: portMonitor,
                    isSelected: selectedPorts.contains(port.id),
                    onSelectionToggle: { toggleSelection(for: port.id) },
                    isGroupedView: isGroupedView,
                    onViewToggle: { toggleViewMode() },
                    onKillProcess: { killSingleProcess(pid: port.pid) }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .leading))
                ))
                
                if index < filteredPorts.count - 1 {
                    Divider()
                        .padding(.leading, 44) // Align with content after icon
                }
            }
        }
    }
    
    private var bottomToolbarArea: some View {
        ZStack(alignment: .bottom) {
            // Bottom toolbar (appears when searching or selecting)
            if shouldShowToolbar {
                HStack {
                    Text(!selectedPorts.isEmpty ? 
                         "\(selectedPorts.count) selected port\(selectedPorts.count == 1 ? "" : "s")" :
                         "\(filteredPorts.count) matching port\(filteredPorts.count == 1 ? "" : "s")")
                        .foregroundColor(.secondary)
                        .font(.body)
                        .id("\(!selectedPorts.isEmpty)-\(selectedPorts.count)-\(filteredPorts.count)")
                        .transition(.opacity)
                    
                    Spacer()
                    
                    HStack {
                        if !selectedPorts.isEmpty {
                            Button("Clear") {
                                clearSelection()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            Button("Kill Selected") {
                                killAllSelected()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        } else {
                            Button("Kill All") {
                                killAllMatching()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPorts.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Rectangle())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Killing banner (appears when killing a process) - layered on top
            if shouldShowKillingBanner {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.small)
                    
                    Text("Killing...")
                        .foregroundColor(.secondary)
                        .font(.body)
                    
                    Spacer()
                }
                .padding(12)
                .background(.regularMaterial, in: Rectangle())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func closePopover() {
        // Find the current window and close it
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
    
    private func toggleViewMode() {
        isGroupedView.toggle()
        UserDefaults.standard.set(isGroupedView, forKey: Self.groupedViewModeKey)
    }
    
    private func toggleSelection(for portId: String) {
        if selectedPorts.contains(portId) {
            selectedPorts.remove(portId)
        } else {
            selectedPorts.insert(portId)
        }
    }
    
    private func killSingleProcess(pid: String) {
        isKillingProcess = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = ["-9", pid]
            
            do {
                try process.run()
                process.waitUntilExit()
                print("Successfully killed process with PID: \(pid)")
            } catch {
                print("Failed to kill process \(pid): \(error)")
            }
            
            // Hide banner after 1 second and refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isKillingProcess = false
                portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
    
    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedPorts.removeAll()
        }
    }
    
    private func killAllSelected() {
        isKillingProcess = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for port in self.selectedPortInfos {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", port.pid]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    print("Successfully killed process \(port.process) with PID: \(port.pid)")
                } catch {
                    // Continue with other processes even if one fails
                    print("Failed to kill process \(port.pid): \(error)")
                }
            }
            
            // Clear selection and refresh after killing all
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.selectedPorts.removeAll()
                self.isKillingProcess = false
                self.portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
    
    private func killAllMatching() {
        isKillingProcess = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for port in self.filteredPorts {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", port.pid]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    print("Successfully killed process \(port.process) with PID: \(port.pid)")
                } catch {
                    // Continue with other processes even if one fails
                    print("Failed to kill process \(port.pid): \(error)")
                }
            }
            
            // Clear search and refresh after killing all
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.searchText = ""
                self.isKillingProcess = false
                self.portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
    
    private func killProcessGroup(processName: String, ports: [PortInfo]) {
        isKillingProcess = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for port in ports {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", port.pid]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    print("Successfully killed process \(port.process) with PID: \(port.pid)")
                } catch {
                    // Continue with other processes even if one fails
                    print("Failed to kill process \(port.pid): \(error)")
                }
            }
            
            // Clear any selected ports from this group and refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let groupPortIds = Set(ports.map(\.id))
                self.selectedPorts.subtract(groupPortIds)
                self.isKillingProcess = false
                self.portMonitor.refreshPorts(showLoading: false)
            }
        }
    }
}

struct PortRowView: View {
    let port: PortInfo
    let portMonitor: PortMonitor
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let isGroupedView: Bool
    let onViewToggle: () -> Void
    let onKillProcess: () -> Void
    
    @State private var isContextMenuOpen = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Clickable area for selection (everything except buttons)
            HStack(spacing: 12) {
                // App icon
                if let appIcon = port.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                } else {
                    let terminalIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
                    Image(nsImage: terminalIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
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
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 1) { }  // Consume regular taps, do nothing
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.command)
                    .onEnded { _ in
                        onSelectionToggle()
                    }
            )
            
            // Action buttons (separate from clickable area)
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
                    print("Kill button clicked for port \(port.port), PID \(port.pid), process \(port.process)")
                    onKillProcess()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isSelected || isContextMenuOpen) ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.0001))
        .scaleEffect(isContextMenuOpen ? 0.98 : 1.0)
        .contextMenu {
            Button("Open in Safari") {
                openInBrowser(port: port.port)
            }
            
            Button("Kill Process") {
                onKillProcess()
            }
            
            Divider()
            
            Button(action: {
                onViewToggle()
            }) {
                HStack {
                    Image(systemName: isGroupedView ? "list.bullet" : "rectangle.3.group")
                    Text(isGroupedView ? "Show Flat View" : "Show Grouped View")
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 50) {
            // This triggers on the start of a long press (very short duration)
            // which includes right-clicks
            withAnimation(.easeInOut(duration: 0.1)) {
                isContextMenuOpen = true
            }
            
            // Auto-dismiss after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isContextMenuOpen = false
                }
            }
        }
    }
    
    private func openInBrowser(port: String) {
        let urlString = "http://localhost:\(port)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}


#Preview {
    PortsPopoverView()
        .environmentObject(PortMonitor())
}
