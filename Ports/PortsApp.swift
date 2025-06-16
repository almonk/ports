//
//  PortsApp.swift
//  Ports
//
//  Created by al on 10/06/2025.
//

import SwiftUI
import ServiceManagement

@main
struct PortsApp: App {
    @StateObject private var portMonitor = PortMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// LaunchAtLogin helper
class LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older macOS versions
                let bundleIdentifier = Bundle.main.bundleIdentifier!
                let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: AnyObject]]
                return jobs?.contains { $0["Label"] as? String == bundleIdentifier } ?? false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to \(newValue ? "register" : "unregister") launch at login: \(error)")
                }
            } else {
                // Fallback for older macOS versions
                let bundleIdentifier = Bundle.main.bundleIdentifier!
                SMLoginItemSetEnabled(bundleIdentifier as CFString, newValue)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var portMonitor = PortMonitor()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app (no dock icon)
        NSApp.setActivationPolicy(.prohibited)
        
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Try to load custom menu bar icon first, fallback to system icon
            if let customIcon = loadCustomMenuBarIcon() {
                button.image = customIcon
                print("Using custom menu bar icon")
            } else {
                button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Ports")
                print("Using system network icon (custom icon not found)")
            }
            
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            print("Status item button configured")
        } else {
            print("Failed to get status item button")
        }
        
        // Create popover
        setupPopover()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // With .prohibited policy, this won't be called, but keeping for completeness
        togglePopover()
        return true
    }
    
    private func loadCustomMenuBarIcon() -> NSImage? {
        // Try to load custom menu bar icon from bundle
        // Look for "MenuBarIcon" in the app bundle
        if let image = NSImage(named: "MenuBarIcon") {
            // Configure the image for menu bar use
            image.isTemplate = true // This makes it adapt to light/dark mode
            image.size = NSSize(width: 18, height: 18) // Standard menu bar icon size
            return image
        }
        
        // Alternative: try loading from specific file names
        let iconNames = ["MenuBarIcon", "menubar-icon", "StatusIcon", "ports-icon"]
        for iconName in iconNames {
            if let image = NSImage(named: iconName) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }
        
        return nil
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 370)
        popover?.behavior = .transient
        popover?.animates = false
    
        
        // Create hosting controller
        let hostingController = NSHostingController(
            rootView: PortsPopoverView()
                .environmentObject(portMonitor)
        )
        
        popover?.contentViewController = hostingController
        
        print("Popover setup completed")
        
        // Make resizable after showing
        NotificationCenter.default.addObserver(
            forName: NSPopover.didShowNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            self?.makePopoverResizable()
        }
    }
    
    private func makePopoverResizable() {
        // Try multiple times to get the window reference as it might not be available immediately
        var attempts = 0
        let maxAttempts = 10
        
        func tryMakeResizable() {
            guard let window = popover?.contentViewController?.view.window else {
                attempts += 1
                if attempts < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        tryMakeResizable()
                    }
                } else {
                    print("Failed to get popover window after \(maxAttempts) attempts")
                }
                return
            }
            
            print("Making popover resizable")
            // Make the window resizable
            window.styleMask.insert(.resizable)
            
            // Set minimum and maximum size constraints
            window.minSize = NSSize(width: 300, height: 250)
            window.maxSize = NSSize(width: 1000, height: 1000)
            
            print("Popover made resizable with constraints")
        }
        
        tryMakeResizable()
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            print("Right click detected - showing menu")
            showContextMenu()
        } else {
            print("Left click detected - showing popover")
            togglePopover()
        }
    }
    
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "About Ports", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    private func togglePopover() {
        print("togglePopover called")
        guard let popover = popover, let button = statusItem?.button else { 
            print("Popover or button is nil")
            return 
        }
        
        print("Popover is shown: \(popover.isShown)")
        
        if popover.isShown {
            print("Closing popover")
            popover.performClose(nil)
        } else {
            print("Showing popover")
            // Use simple positioning first to debug
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    private func showPopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        if !popover.isShown {
            // Position popover anchored to top center of the button
            let buttonRect = button.bounds
            let anchorRect = NSRect(
                x: buttonRect.midX - 1, // Center horizontally (small width for precise positioning)
                y: buttonRect.maxY,     // Top of the button
                width: 2,
                height: 1
            )
            popover.show(relativeTo: anchorRect, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    
    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }
    
    @objc private func showAbout() {
        // Create attributed string for credits with clickable link
        let creditsText = NSMutableAttributedString(string: "A simple menu bar app for monitoring localhost ports.\n\nAn app by @almonk")
        
        // Add link to @almonk
        let linkRange = (creditsText.string as NSString).range(of: "@almonk")
        if linkRange.location != NSNotFound {
            creditsText.addAttribute(.link, value: "https://alasdairmonk.com", range: linkRange)
            creditsText.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: linkRange)
            creditsText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkRange)
        }
        
        // Set font for better readability
        creditsText.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 0, length: creditsText.length))
        
        NSApp.orderFrontStandardAboutPanel([
            NSApplication.AboutPanelOptionKey.applicationName: "Ports",
            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0",
            NSApplication.AboutPanelOptionKey.version: "1.0",
            NSApplication.AboutPanelOptionKey.credits: creditsText
        ])
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
