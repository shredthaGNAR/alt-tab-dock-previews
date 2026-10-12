import Cocoa

struct DockAltTabWindowStats {
    var all = 0
    var currentSpace = 0
    var minimizedCurrentSpace = 0
}

/// the actions DockAltTab used to request over AppleScript; the script commands and the built-in DockPreviews share them
enum DockAltTabActions {
    static let shortcutIndex = 2

    static func showApp(_ app: NSRunningApplication, _ anchor: NSPoint?, _ dockPos: String) {
        DockAltTabResetCachedThumbnailPreviewSetting()
        anchor == nil ? DockAltTabReset() : startDockAltTabMode(app: app)
        let origin = anchor ?? NSPoint(x: NSEvent.mouseLocation.x - 40, y: NSEvent.mouseLocation.y + 40)
        DockAltTabFORCEDX = Int(origin.x)
        DockAltTabFORCEDY = Int(origin.y)
        DockAltTabDockPos = dockPos
        App.appIsBeingUsed = true
        prepareFirstSummon()
        guard Windows.updatesBeforeShowing() else { return hide() }
        markWindowsToShow(app.processIdentifier)
        guard Windows.list.contains(where: { $0.shouldShowTheUser }) else { return hide() }
        Windows.setInitialSelectedAndHoveredWindowIndex()
        displayPanel()
    }

    static func hide() {
        App.hideUi()
        DockAltTabReset()
    }

    static func previewSelectedWindow() {
        guard App.appIsBeingUsed, let window = Windows.selectedWindow(), window.cgWindowId != nil else { return }
        DockAltTabThumbnailPreviewRequestHD(window: window)
        Windows.previewSelectedWindowIfNeeded()
    }

    static func windowStats(_ pid: pid_t) -> DockAltTabWindowStats {
        var stats = DockAltTabWindowStats()
        for window in Windows.list where window.application.pid == pid && !window.isWindowlessApp {
            stats.all += 1
            guard isOnVisibleSpace(window) else { continue }
            stats.currentSpace += 1
            if window.isMinimized { stats.minimizedCurrentSpace += 1 }
        }
        return stats
    }

    static func deminimizeFirstMinimizedWindowOnCurrentSpace(_ pid: pid_t) {
        Windows.list.first { $0.application.pid == pid && $0.isMinimized && isOnVisibleSpace($0) }?.minDemin()
    }

    static func reposition(_ target: NSPoint) {
        guard TilesPanel.shared.isVisible else { return }
        DockAltTabRepositionTimer?.invalidate()
        let start = NSPoint(x: DockAltTabFORCEDX, y: DockAltTabFORCEDY)
        let steps = floor(222 / (16.67 * 2))
        var step = 0.0
        DockAltTabRepositionTimer = Timer.scheduledTimer(withTimeInterval: 16.67 / 1000 * 2 / steps, repeats: true) { timer in
            step += 1
            let progress = min(step / steps, 1)
            DockAltTabFORCEDX = Int(start.x + (target.x - start.x) * progress)
            DockAltTabFORCEDY = Int(start.y + (target.y - start.y) * progress)
            TilesPanel.shared.screen?.repositionPanel(TilesPanel.shared)
            guard progress >= 1 else { return }
            timer.invalidate()
            DockAltTabRepositionTimer = nil
        }
    }

    static func isOnVisibleSpace(_ window: Window) -> Bool {
        window.spaceIds.contains { Spaces.visibleSpaces.contains($0) }
    }

    private static func prepareFirstSummon() {
        NSScreen.updatePreferred()
        if App.isVeryFirstSummon {
            Windows.sortByLevel()
            App.isVeryFirstSummon = false
        }
        App.isFirstSummon = false
        App.shortcutIndex = shortcutIndex
    }

    /// follows Windows.refreshWhichWindowsToShowTheUser, but only keeps the target app and ignores the blacklist
    private static func markWindowsToShow(_ pid: pid_t) {
        for window in Windows.list {
            window.shouldShowTheUser = window.application.pid == pid && shouldShow(window)
        }
    }

    private static func shouldShow(_ window: Window) -> Bool {
        if Preferences.showHiddenWindows[shortcutIndex] == .hide && window.isHidden { return false }
        if window.isWindowlessApp { return Preferences.showWindowlessApps[shortcutIndex] != .hide }
        if Preferences.showFullscreenWindows[shortcutIndex] == .hide && window.isFullscreen { return false }
        if Preferences.showMinimizedWindows[shortcutIndex] == .hide && window.isMinimized { return false }
        if Preferences.spacesToShow[shortcutIndex] == .visible && !isOnVisibleSpace(window) { return false }
        if Preferences.screensToShow[shortcutIndex] == .showingAltTab && !window.isOnScreen(NSScreen.preferred) { return false }
        return Preferences.showTabsAsWindows || !window.isTabbed
    }

    private static func displayPanel() {
        guard Preferences.windowDisplayDelay != DispatchTimeInterval.milliseconds(0) else { return App.buildUiAndShowPanel() }
        App.delayedDisplayScheduled += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Preferences.windowDisplayDelay) {
            if App.delayedDisplayScheduled == 1 { App.buildUiAndShowPanel() }
            App.delayedDisplayScheduled -= 1
        }
    }
}
