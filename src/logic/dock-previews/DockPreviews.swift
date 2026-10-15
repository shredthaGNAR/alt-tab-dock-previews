import Cocoa

/// built-in port of DockAltTab (https://github.com/steventheworker/DockAltTab)
/// hovering a running app's Dock icon shows its windows in the TilesPanel, anchored to the icon
/// optionally, clicking a Dock icon toggles its app like on Windows, without switching Spaces
class DockPreviews {
    private static var eventTap: CFMachPort?
    private static var hoveredBundleId: String?
    private static var shownIconFrame: NSRect?
    private static var pointer = CGPoint.zero
    private static var isPointerOnDock = false
    private static var clickTarget: (bundleId: String?, wasActive: Bool)?
    private static var previewedWindowId: CGWindowID?
    private static var windowPreviewWorkItem: DispatchWorkItem?
    private static var activationDelayMs = 30

    static func observe() {
        DockAutohide.restoreIfLeftHeld()
        let eventMask = [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // a HID-level tap sees clicks before CursorEvents' session-level tap, which swallows clicks while the UI is open
        eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventMask, callback: handleEvent, userInfo: nil)
        guard let eventTap else { return Logger.error { "Failed to create the Dock previews event tap" } }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, eventTap, 0), .commonModes)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        DockPreviewShortcuts.observe()
        toggle(Preferences.dockPreviewsEnabled)
    }

    static func toggle(_ enabled: Bool) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
        guard !enabled else { return }
        hoveredBundleId = nil
        hide()
        DockAutohide.release()
    }

    static func restoreDock() {
        DockAutohide.release()
    }

    @objc private static func activeSpaceChanged() {
        // activating right after unhiding switches Spaces; Space transitions need a longer wait
        activationDelayMs = 100
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
            case .mouseMoved: handleMouseMoved(cgEvent.location)
            case .leftMouseDown, .rightMouseDown: return handleMouseDown(type, cgEvent)
            case .leftMouseUp: return handleLeftMouseUp(cgEvent)
            case .tapDisabledByTimeout, .tapDisabledByUserInput: reEnableTap()
            default: break
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private static func reEnableTap() {
        guard let eventTap, Preferences.dockPreviewsEnabled else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static var isShowingDockPreview: Bool { App.appIsBeingUsed && DockAltTabMode }

    /// the user summoned AltTab with a keyboard shortcut; we leave it alone
    private static var isShowingRegularUi: Bool { App.appIsBeingUsed && !DockAltTabMode }

    /// our tap runs before the WindowServer moves the cursor, so NSEvent.mouseLocation lags; we use the event location instead
    private static func visibleTilesPanelFrame() -> NSRect? {
        guard isShowingDockPreview, let panel = TilesPanel.shared, panel.isVisible else { return nil }
        return panel.frame
    }

    private static func isPointerOnTilesPanel() -> Bool {
        visibleTilesPanelFrame()?.contains(DockGeometry.cocoaPoint(pointer)) ?? false
    }

    /// the strip between the icon and the panel (e.g. above a magnified icon) belongs to neither; we treat it as part of the preview
    private static func isPointerBetweenIconAndPanel() -> Bool {
        guard let panelFrame = visibleTilesPanelFrame(), let shownIconFrame else { return false }
        return shownIconFrame.union(panelFrame).contains(DockGeometry.cocoaPoint(pointer))
    }

    /// mouse move

    private static func handleMouseMoved(_ location: CGPoint) {
        pointer = location
        guard !isShowingRegularUi else { return }
        if isPointerOnTilesPanel() { return pointerOnTilesPanel() }
        if let item = DockItem.under(location) { return pointerOnDockIcon(item) }
        if isPointerBetweenIconAndPanel() { return pointerBetweenIconAndPanel() }
        pointerOffDockAndPanel()
    }

    private static func pointerBetweenIconAndPanel() {
        isPointerOnDock = false
        if Preferences.dockPreviewsKeepDockShowing { DockAutohide.hold() }
    }

    private static func pointerOnDockIcon(_ item: DockItem) {
        isPointerOnDock = true
        guard let app = item.runningApp else { return hideAndForgetHover() }
        guard item.bundleId != hoveredBundleId else { return }
        hoveredBundleId = item.bundleId
        showWhenIconSettles(item, app)
    }

    /// Dock icons move while magnification animates; we wait for the icon and pointer to stop before anchoring the panel
    private static func showWhenIconSettles(_ item: DockItem, _ app: NSRunningApplication) {
        let frame = item.frame()
        let pointerBefore = pointer
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            guard hoveredBundleId == item.bundleId, let frame, let settledFrame = item.frame() else { return }
            guard distance(frame, settledFrame) <= 2 && distance(pointer, pointerBefore) <= 2 else { return showWhenIconSettles(item, app) }
            showPreview(item, app, settledFrame)
        }
    }

    private static func showPreview(_ item: DockItem, _ app: NSRunningApplication, _ iconFrame: CGRect) {
        guard !isShowingRegularUi else { return }
        cancelWindowPreview()
        shownIconFrame = DockGeometry.cocoaRect(iconFrame)
        DockAltTabActions.showApp(app, DockGeometry.previewAnchor(iconFrame, isPointerOnDock), DockGeometry.position.rawValue)
        DockPreviewShortcuts.toggle(isShowingDockPreview)
        if isShowingDockPreview { DockPreviewFocus.take() }
    }

    private static func pointerOnTilesPanel() {
        isPointerOnDock = false
        if Preferences.dockPreviewsKeepDockShowing { DockAutohide.hold() }
        guard Preferences.previewSelectedWindow else { return }
        // CursorEvents updates the hovered tile after us; we read the selection once it has
        DispatchQueue.main.async { scheduleWindowPreview() }
    }

    private static func pointerOffDockAndPanel() {
        isPointerOnDock = false
        hideAndForgetHover()
        releaseDockAutohideIfPointerStaysAway()
    }

    private static func hideAndForgetHover() {
        hoveredBundleId = nil
        hide()
    }

    private static func hide() {
        cancelWindowPreview()
        shownIconFrame = nil
        DockPreviewShortcuts.toggle(false)
        guard isShowingDockPreview else { return DockPreviewFocus.giveBackIfStillFrontmost() }
        DockAltTabActions.hide()
        DockPreviewFocus.giveBack()
    }

    private static func releaseDockAutohideIfPointerStaysAway() {
        guard DockAutohide.isHolding else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(333)) {
            guard !isPointerOnDock && !isPointerOnTilesPanel() && !isPointerBetweenIconAndPanel() else { return }
            DockAutohide.release()
        }
    }

    /// window preview: with "Preview selected window" on, hovering a tile shows the window full-size after a short delay

    private static func scheduleWindowPreview() {
        guard isPointerOnTilesPanel(), let id = Windows.selectedWindow()?.cgWindowId, id != previewedWindowId else { return }
        windowPreviewWorkItem?.cancel()
        guard previewedWindowId == nil else { return previewWindow(id) }
        let workItem = DispatchWorkItem { previewWindow(id) }
        windowPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Preferences.dockPreviewsWindowPreviewDelay), execute: workItem)
    }

    private static func previewWindow(_ id: CGWindowID) {
        guard isPointerOnTilesPanel(), Windows.selectedWindow()?.cgWindowId == id else { return }
        previewedWindowId = id
        DockAltTabActions.previewSelectedWindow()
    }

    private static func cancelWindowPreview() {
        windowPreviewWorkItem?.cancel()
        windowPreviewWorkItem = nil
        previewedWindowId = nil
    }

    /// clicks

    private static func handleMouseDown(_ type: CGEventType, _ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        clickTarget = nil
        guard !isShowingRegularUi, let item = DockItem.under(cgEvent.location), let app = item.runningApp else { return Unmanaged.passUnretained(cgEvent) }
        let wasActive = app.processIdentifier == DockPreviewFocus.effectiveFrontmostApp?.processIdentifier
        hide()
        guard type == .leftMouseDown, Preferences.dockPreviewsClickToggles, !hasModifiers(cgEvent), !item.isShowingMenu,
              DockAltTabActions.windowStats(app.processIdentifier).all > 0 else { return Unmanaged.passUnretained(cgEvent) }
        clickTarget = (app.bundleIdentifier, wasActive)
        return nil
    }

    /// we swallowed the matching mouse-down, so we swallow this mouse-up too
    private static func handleLeftMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let target = clickTarget else { return Unmanaged.passUnretained(cgEvent) }
        clickTarget = nil
        guard let app = DockItem.under(cgEvent.location)?.runningApp, app.bundleIdentifier == target.bundleId else { return nil }
        DockClick.toggle(app, target.wasActive)
        return nil
    }

    private static func hasModifiers(_ cgEvent: CGEvent) -> Bool {
        !cgEvent.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
    }

    fileprivate static func consumeActivationDelay() -> Int {
        let delay = activationDelayMs
        activationDelayMs = 30
        return delay
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        distance(a.origin, b.origin) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}

/// Windows-like Dock clicks: activate, or hide if already active; never switch Space to reach an app's windows
private enum DockClick {
    static func toggle(_ app: NSRunningApplication, _ wasActive: Bool) {
        let stats = DockAltTabActions.windowStats(app.processIdentifier)
        if stats.currentSpace == 0 { return toggleWithWindowsOnOtherSpaces(app) }
        if stats.currentSpace == 1 && stats.minimizedCurrentSpace == 1 { return deminimize(app) }
        guard wasActive else { return activate(app) }
        app.hide()
    }

    private static func toggleWithWindowsOnOtherSpaces(_ app: NSRunningApplication) {
        if app.isHidden { return unhideThenActivate(app) }
        if app.bundleIdentifier == "com.apple.finder" { return openFinderWindow() }
        app.hide()
    }

    private static func unhideThenActivate(_ app: NSRunningApplication) {
        app.unhide()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(DockPreviews.consumeActivationDelay())) { activate(app) }
    }

    private static func deminimize(_ app: NSRunningApplication) {
        activate(app)
        DockAltTabActions.deminimizeFirstMinimizedWindowOnCurrentSpace(app.processIdentifier)
    }

    private static func openFinderWindow() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        NSWorkspace.shared.open(desktop)
    }

    static func activate(_ app: NSRunningApplication) {
        DockPreviewFocus.activate(app)
    }
}
