//
//  PortMonitor.swift
//  Ports
//
//  Created by al on 10/06/2025.
//

import Foundation
import SwiftUI
import AppKit

struct PortInfo: Identifiable, Equatable {
    let port: String
    let process: String
    let pid: String
    let `protocol`: String
    let appIcon: NSImage?
    
    var id: String {
        return "\(port)-\(`protocol`)"
    }
    
    static func == (lhs: PortInfo, rhs: PortInfo) -> Bool {
        return lhs.port == rhs.port && lhs.process == rhs.process && lhs.protocol == rhs.protocol && lhs.pid == rhs.pid
    }
}

class PortMonitor: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var isLoading = false
    
    private var timer: Timer?
    
    init() {
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startMonitoring() {
        refreshPorts(showLoading: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.refreshPorts(showLoading: false)
        }
    }
    
    func refreshPorts(showLoading: Bool = true) {
        if showLoading {
            isLoading = true
        }
        
        Task {
            let newPorts = await fetchPorts()
            
            await MainActor.run {
                self.updatePorts(with: newPorts)
                if showLoading {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func updatePorts(with newPorts: [PortInfo]) {
        // Only update if the arrays are actually different
        guard ports != newPorts else {
            return
        }
        
        // Create a smooth transition by maintaining order where possible
        let currentPortsDict = Dictionary(uniqueKeysWithValues: ports.map { ($0.id, $0) })
        let newPortsDict = Dictionary(uniqueKeysWithValues: newPorts.map { ($0.id, $0) })
        
        var updatedPorts: [PortInfo] = []
        
        // First, update existing ports in their current positions
        for currentPort in ports {
            if let newPort = newPortsDict[currentPort.id] {
                updatedPorts.append(newPort)
            }
        }
        
        // Then add any new ports that weren't in the original list
        for newPort in newPorts {
            if !currentPortsDict.keys.contains(newPort.id) {
                updatedPorts.append(newPort)
            }
        }
        
        // Sort by port number to maintain consistent ordering
        updatedPorts.sort { 
            Int($0.port) ?? 0 < Int($1.port) ?? 0
        }
        
        self.ports = updatedPorts
    }
    
    private func fetchPorts() async -> [PortInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-P", "-n", "+c0"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                print("No output from lsof")
                return []
            }
            
            let result = parseOutput(output)
            return result
        } catch {
            print("Error running lsof: \(error)")
            return []
        }
    }
    
    private func parseOutput(_ output: String) -> [PortInfo] {
        let lines = output.components(separatedBy: .newlines)
        var ports: [PortInfo] = []
        
        for line in lines.dropFirst() { // Skip header line
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            if components.count >= 9 {
                let rawProcess = components[0]
                let process = cleanProcessName(rawProcess)
                let pid = components[1]
                let connection = components[8]  // NAME column
                
                // Only process TCP connections (skip UDP)
                let protocolType: String
                if components[7] == "TCP" {
                    protocolType = "TCP"
                } else {
                    continue // Skip UDP and other protocols
                }
                
                // Extract port from connection string and check if it's localhost
                if let port = extractPort(from: connection), !port.isEmpty, isLocalhost(connection: connection) {
                    let appIcon = getAppIcon(for: process, pid: pid)
                    let portInfo = PortInfo(port: port, process: process, pid: pid, protocol: protocolType, appIcon: appIcon)
                    ports.append(portInfo)
                }
            }
        }
        
        // Remove duplicates and sort by port number
        let uniquePorts = Dictionary(grouping: ports) { "\($0.port)-\($0.protocol)" }
            .compactMapValues { $0.first }
            .values
        
        return Array(uniquePorts).sorted { 
            Int($0.port) ?? 0 < Int($1.port) ?? 0
        }
    }
    
    private func extractPort(from connection: String) -> String? {
        // Handle different connection formats:
        // "127.0.0.1:5173" -> "5173"
        // "*:5173" -> "5173" 
        // "localhost:5173" -> "5173"
        // "[::1]:5173" -> "5173"
        // "127.0.0.1:5173 (LISTEN)" -> "5173"
        // "192.0.0.2:62310->17.253.21.201:80" -> "62310" (local port)
        
        // Handle connection with -> (client connections)
        if connection.contains("->") {
            let localPart = connection.components(separatedBy: "->").first ?? connection
            return extractPortFromAddress(localPart)
        } else {
            return extractPortFromAddress(connection)
        }
    }
    
    private func extractPortFromAddress(_ address: String) -> String? {
        // Handle IPv6 format [::1]:5173
        if address.contains("]") {
            let parts = address.components(separatedBy: "]:")
            if parts.count == 2 {
                let portPart = parts[1].components(separatedBy: CharacterSet(charactersIn: " (")).first ?? parts[1]
                let cleanPort = portPart.trimmingCharacters(in: .whitespaces)
                if Int(cleanPort) != nil {
                    return cleanPort
                }
            }
        }
        
        // Handle regular IPv4 format
        let parts = address.components(separatedBy: ":")
        if let lastPart = parts.last {
            let portPart = lastPart.components(separatedBy: CharacterSet(charactersIn: " (")).first ?? lastPart
            let cleanPort = portPart.trimmingCharacters(in: .whitespaces)
            
            if Int(cleanPort) != nil {
                return cleanPort
            }
        }
        
        return nil
    }
    
    private func isLocalhost(connection: String) -> Bool {
        // Check if connection is bound to localhost addresses
        let localhostPatterns = [
            "127.0.0.1:",
            "localhost:",
            "[::1]:",
            "*:127.0.0.1:",
            "*:localhost:"
        ]
        
        // Handle connection with -> (client connections) - check local part only
        let connectionToCheck = connection.contains("->") ? 
            (connection.components(separatedBy: "->").first ?? connection) : connection
        
        // Check for localhost patterns
        for pattern in localhostPatterns {
            if connectionToCheck.contains(pattern) {
                return true
            }
        }
        
        // Also check for wildcard bind on localhost (just "*:" followed by port)
        // This catches services that bind to all interfaces but we want to include them
        // if they're accessible via localhost
        if connectionToCheck.hasPrefix("*:") && !connectionToCheck.contains("->") {
            return true
        }
        
        return false
    }
    
    private func getAppIcon(for processName: String, pid: String) -> NSImage? {
        // First try to get the running application by PID
        if let pidInt = Int(pid) {
            let runningApps = NSWorkspace.shared.runningApplications
            if let app = runningApps.first(where: { $0.processIdentifier == pidInt }) {
                return app.icon
            }
        }
        
        // Fallback: try to find app by process name
        let workspace = NSWorkspace.shared
        
        // Common process name mappings
        let processMapping: [String: String] = [
            "node": "Node.js",
            "python": "Python",
            "python3": "Python",
            "ruby": "Ruby",
            "java": "Java",
            "php": "PHP",
            "nginx": "nginx",
            "httpd": "Apache HTTP Server",
            "mongod": "MongoDB",
            "postgres": "PostgreSQL",
            "mysql": "MySQL",
            "redis-server": "Redis",
            "Docker": "Docker Desktop",
            "com.docker.vpnkit": "Docker Desktop"
        ]
        
        // Try mapped name first
        if let mappedName = processMapping[processName] {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.\(mappedName.lowercased())") ??
                           workspace.urlForApplication(withBundleIdentifier: "org.\(mappedName.lowercased())") {
                return workspace.icon(forFile: appURL.path)
            }
        }
        
        // Try to find by process name directly
        if let appURL = workspace.urlForApplication(withBundleIdentifier: processName) {
            return workspace.icon(forFile: appURL.path)
        }
        
        // Try to find application by name
        let possiblePaths = [
            "/Applications/\(processName).app",
            "/Applications/\(processName.capitalized).app",
            "/System/Applications/\(processName).app",
            "/System/Applications/\(processName.capitalized).app"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return workspace.icon(forFile: path)
            }
        }
        
        // Return Terminal.app icon for unknown processes
        if let terminalURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return workspace.icon(forFile: terminalURL.path)
        }
        
        // Fallback to system terminal symbol if Terminal.app not found
        return NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal Application")
    }
    
    private func cleanProcessName(_ processName: String) -> String {
        // lsof outputs process names with spaces escaped as \x20
        // Replace \x20 with actual spaces and return the full name
        return processName.replacingOccurrences(of: "\\x20", with: " ")
    }
}
