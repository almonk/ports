# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ports is a macOS menu bar application that monitors localhost ports using the `lsof` command. It provides a clean interface to view and manage processes listening on local ports.

## Build and Development Commands

**Build the app:**
```bash
xcodebuild -project Ports.xcodeproj -scheme Ports build
```

**Run from Xcode:**
Open `Ports.xcodeproj` in Xcode and press Cmd+R to build and run.

## Architecture Overview

### Core Components

1. **PortsApp.swift** - Main app entry point and menu bar setup
   - Configures as menu bar only app (no dock icon) using `.prohibited` activation policy
   - Creates status bar item with network icon
   - Handles left/right click on menu bar icon (popover vs context menu)
   - Manages popover lifecycle and makes it resizable
   - Provides launch-at-login functionality using `SMAppService` (macOS 13+) with fallback

2. **PortMonitor.swift** - Core data layer and process monitoring
   - Executes `lsof -i -P -n` every 5 seconds to gather port information
   - Parses lsof output to extract localhost-only TCP connections
   - Creates `PortInfo` structs with port, process name, PID, protocol, and app icon
   - Filters for localhost addresses (127.0.0.1, ::1, localhost, and wildcard binds)
   - Retrieves app icons by PID using `NSWorkspace.shared.runningApplications`

3. **ContentView.swift** - SwiftUI interface
   - **PortsPopoverView**: Main container with search, port list, and toolbars
   - **PortRowView**: Individual port row with app icon, port number, process name, and action buttons
   - **ModernButton**: Custom button component with simplified styling and hover effects
   - Supports grouped view (by process) and flat view modes
   - Provides search functionality with port range support (e.g., "5000-7000")
   - Implements selection via Cmd+click for bulk operations

### Key Data Flow

1. PortMonitor runs lsof command every 5 seconds
2. Output is parsed to extract localhost TCP connections only
3. Each connection becomes a PortInfo with unique ID format: `"{port}-{protocol}"`
4. UI updates reactively via SwiftUI @Published properties
5. Process termination uses `/bin/kill -9 {pid}` for individual processes

### UI Behavior

- **Regular click on menu bar**: Shows/hides popover
- **Right click on menu bar**: Shows context menu (Launch at Login, About, Quit)
- **Regular click on port row**: No action (buttons only)
- **Cmd+click on port row content**: Toggles selection
- **Click action buttons**: Opens browser or kills process (shows "Killing..." banner for 1 second)
- **Search supports**: Process names, exact ports, and port ranges

### Process Management

- Individual kills target specific PID only, not process name
- Bulk operations available for selected ports or search results
- Kill operations show confirmation dialogs except for single process kills
- App icons retrieved by matching PID to running applications, with fallbacks for common tools

### Development Notes

- Uses modern SwiftUI with computed properties to avoid compiler expression complexity limits
- Implements smooth port list updates that maintain order and minimize UI flicker
- All process operations run on background queues to avoid blocking UI
- Selection clearing operations include smooth animations for better UX
- Custom ModernButton component provides consistent styling across the interface
- Extensive debugging output available via console for troubleshooting kill operations