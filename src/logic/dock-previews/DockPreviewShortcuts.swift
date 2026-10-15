import Cocoa

/// AltTab's "shortcuts when active" (W close, M minimize, F fullscreen, Q quit, H hide, ...) for the Dock preview
/// the Dock preview opens from a hover, so the frontmost app usually keeps keyboard focus and AltTab's local key monitor never sees these keys
/// we listen for them with an event tap that only runs while a Dock preview is showing, so typing elsewhere is never slowed down
enum DockPreviewShortcuts {
    /// search needs the panel to have keyboard focus to type into, so it's left out
    private static let shortcutIds = [
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut",
        "focusWindowShortcut", "cancelShortcut", "→", "←", "↑", "↓", "vimCycleRight", "vimCycleLeft", "vimCycleUp", "vimCycleDown",
    ]
    private static var eventTap: CFMachPort?
    private static var swallowedKeyCodes = Set<Int64>()

    static func observe() {
        let eventMask = [CGEventType.keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // session level, not HID level: keys synthesized by apps like BetterTouchTool are posted to the session, and never pass HID-level taps
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventMask, callback: handleEvent, userInfo: nil)
        guard let eventTap else { return Logger.error { "Failed to create the Dock preview shortcuts event tap" } }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, eventTap, 0), .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: false)
    }

    static func toggle(_ enabled: Bool) {
        guard let eventTap, CGEvent.tapIsEnabled(tap: eventTap) != enabled else { return }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
        if !enabled { swallowedKeyCodes.removeAll() }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
            case .keyDown: return handleKeyDown(cgEvent)
            case .keyUp: return handleKeyUp(cgEvent)
            case .tapDisabledByTimeout, .tapDisabledByUserInput: reEnableTapIfPreviewing()
            default: break
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private static func handleKeyDown(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard App.appIsBeingUsed, DockAltTabMode, !TilesView.isSearchModeOn, let shortcut = matchingShortcut(cgEvent) else { return Unmanaged.passUnretained(cgEvent) }
        swallowedKeyCodes.insert(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        shortcut.executeAction(cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return nil
    }

    /// the frontmost app never saw the key-down we handled, so it shouldn't see the key-up either
    private static func handleKeyUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard swallowedKeyCodes.remove(cgEvent.getIntegerValueField(.keyboardEventKeycode)) != nil else { return Unmanaged.passUnretained(cgEvent) }
        return nil
    }

    private static func matchingShortcut(_ cgEvent: CGEvent) -> ATShortcut? {
        let keyCode = UInt32(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
        return shortcutIds.lazy.compactMap { ControlsTab.shortcuts[$0] }.first { $0.matches(nil, nil, keyCode, modifiers) && $0.shouldTrigger() }
    }

    private static func reEnableTapIfPreviewing() {
        guard let eventTap, App.appIsBeingUsed, DockAltTabMode else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}

/// makes AltTab the frontmost app while a Dock preview shows, so app-specific triggers in other tools fire
/// (e.g. BetterTouchTool trackpad gestures set up for AltTab only run while AltTab is frontmost, which the hover-opened preview never makes it)
/// when the preview closes without a window being chosen, focus goes back to the app the user was in
enum DockPreviewFocus {
    private static var previousApp: NSRunningApplication?

    /// the app the user considers active: the one they were in before AltTab took focus for the preview
    static var effectiveFrontmostApp: NSRunningApplication? { previousApp ?? NSWorkspace.shared.frontmostApplication }

    static func take() {
        guard Preferences.dockPreviewsActivateAltTab, previousApp == nil, !NSApp.isActive,
              let frontmost = NSWorkspace.shared.frontmostApplication, let panel = TilesPanel.shared, panel.windowNumber > 0 else { return }
        previousApp = frontmost
        var psn = ProcessSerialNumber()
        GetProcessForPID(ProcessInfo.processInfo.processIdentifier, &psn)
        _SLPSSetFrontProcessWithOptions(&psn, CGWindowID(panel.windowNumber), SLPSMode.userGenerated.rawValue)
    }

    static func giveBack() {
        guard let app = previousApp else { return }
        previousApp = nil
        guard NSApp.isActive else { return }
        activate(app)
    }

    /// AltTab closed the preview itself (Esc, or focusing a window); focusing a window finishes asynchronously and takes focus away from AltTab
    /// we only give focus back if AltTab still has it once that's done
    static func giveBackIfStillFrontmost() {
        guard previousApp != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
            guard !App.appIsBeingUsed else { return }
            giveBack()
        }
    }

    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate(from: NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current, options: [])
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
}
