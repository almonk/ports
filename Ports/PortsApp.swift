//
//  PortsApp.swift
//  Ports
//
//  Created by al on 10/06/2025.
//

import SwiftUI

@main
struct PortsApp: App {
    @StateObject private var portMonitor = PortMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("Ports", systemImage: "network") {
            PortsPopoverView()
                .environmentObject(portMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var contextMenu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Set up context menu after a delay to ensure MenuBarExtra is created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupContextMenu()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Only handle reopen if no windows are visible
        if !flag {
            // Find and show the MenuBarExtra window
            for window in NSApp.windows {
                if window.className.contains("MenuBarExtra") {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
    
    private func setupContextMenu() {
        // Create context menu
        contextMenu = NSMenu()
        
        let aboutItem = NSMenuItem(title: "About Ports", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        contextMenu.addItem(aboutItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
        
        // Try to find the MenuBarExtra button and add right-click handling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.findAndConfigureMenuBarButton()
        }
    }
    
    private func findAndConfigureMenuBarButton() {
        // Look through all windows to find the MenuBarExtra button
        for window in NSApp.windows {
            if let button = self.findButtonInView(window.contentView) {
                // Add a right-click gesture recognizer without interfering with the original action
                let rightClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
                rightClickGesture.buttonMask = 0x2 // Right mouse button
                button.addGestureRecognizer(rightClickGesture)
                break
            }
        }
    }
    
    private func findButtonInView(_ view: NSView?) -> NSButton? {
        guard let view = view else { return nil }
        
        if let button = view as? NSButton {
            return button
        }
        
        for subview in view.subviews {
            if let button = findButtonInView(subview) {
                return button
            }
        }
        
        return nil
    }
    
    @objc private func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        if let button = gestureRecognizer.view as? NSButton {
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Ports"
        alert.informativeText = "A simple menu bar app for monitoring localhost ports.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
