import Cocoa

/// private Dock APIs from ApplicationServices.HIServices; these persist the user's "Automatically hide and show the Dock" setting
@_silgen_name("CoreDockGetAutoHideEnabled")
func CoreDockGetAutoHideEnabled() -> DarwinBoolean

@_silgen_name("CoreDockSetAutoHideEnabled")
func CoreDockSetAutoHideEnabled(_ flag: DarwinBoolean)

enum DockPosition: String {
    case left
    case bottom
    case right
}

/// reads the Dock layout from its preferences, and converts Dock icon frames into the anchor the TilesPanel attaches to
enum DockGeometry {
    private(set) static var position = DockPosition.bottom
    private(set) static var magnification = false
    private static var magnificationSize = CGFloat(128)
    private static var tileSize = CGFloat(48)
    private static var lastRefresh = Date.distantPast

    static func refreshIfStale() {
        guard Date().timeIntervalSince(lastRefresh) > 2 else { return }
        lastRefresh = Date()
        let prefs = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        position = DockPosition(rawValue: prefs["orientation"] as? String ?? "") ?? .bottom
        magnification = (prefs["magnification"] as? NSNumber)?.boolValue ?? false
        magnificationSize = CGFloat((prefs["largesize"] as? NSNumber)?.doubleValue ?? 128)
        tileSize = CGFloat((prefs["tilesize"] as? NSNumber)?.doubleValue ?? 48)
    }

    /// cheap check to avoid AX hit-testing the Dock when the pointer is far from it
    static func isNearDock(_ location: CGPoint) -> Bool {
        guard let frame = cgScreenFrame(location) else { return false }
        let reach = (magnification ? max(magnificationSize, tileSize) : tileSize) + 40
        switch position {
            case .bottom: return frame.maxY - location.y <= reach
            case .left: return location.x - frame.minX <= reach
            case .right: return frame.maxX - location.x <= reach
        }
    }

    /// the screen edge pixels under the Dock report no element, even though the icons there are clickable
    static func awayFromScreenEdge(_ location: CGPoint) -> CGPoint {
        guard let frame = cgScreenFrame(location) else { return location }
        switch position {
            case .bottom: return CGPoint(x: location.x, y: min(location.y, frame.maxY - 5.1))
            case .left: return CGPoint(x: max(location.x, frame.minX + 14.1), y: location.y)
            case .right: return CGPoint(x: min(location.x, frame.maxX - 14.1), y: location.y)
        }
    }

    /// icon is in CG coordinates (top-left origin); the result is in Cocoa coordinates, like DockAltTabFORCEDX/Y
    static func previewAnchor(_ icon: CGRect, _ isPointerOnDock: Bool) -> NSPoint {
        let top = primaryScreenHeight() - icon.minY
        if isPointerOnDock && magnification { return magnifiedPreviewAnchor(icon, top) }
        switch position {
            case .bottom: return NSPoint(x: icon.midX, y: top - 12)
            case .left: return NSPoint(x: icon.maxX - 5, y: top - icon.height / 2)
            case .right: return NSPoint(x: icon.minX + 12, y: top - icon.height / 2)
        }
    }

    /// AX reports magnified icons with only one of their dimensions magnified; these offsets come from DockAltTab
    private static func magnifiedPreviewAnchor(_ icon: CGRect, _ top: CGFloat) -> NSPoint {
        let scale = magnificationSize / 128
        switch position {
            case .bottom: return NSPoint(x: icon.midX, y: magnificationSize + 2.7 / (scale * scale))
            case .left: return NSPoint(x: icon.width - 17 * scale, y: top - icon.height / 2)
            case .right: return NSPoint(x: icon.minX + 35 * scale, y: top - icon.height / 2)
        }
    }

    static func cocoaPoint(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenHeight() - point.y)
    }

    static func cocoaRect(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryScreenHeight() - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func primaryScreenHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func cgScreenFrame(_ location: CGPoint) -> CGRect? {
        let primaryHeight = primaryScreenHeight()
        return NSScreen.screens.lazy
            .map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
            .first { $0.insetBy(dx: -1, dy: -1).contains(location) }
    }
}

/// a running or non-running app icon in the Dock
struct DockItem {
    private static let dockBundleId = "com.apple.dock"
    private static var dock: AXUIElement?
    let element: AXUIElement
    let bundleId: String?
    let isRunning: Bool

    /// hit-tests the Dock process only, so we never message (and possibly block on) an unresponsive app, or AltTab itself
    static func under(_ location: CGPoint) -> DockItem? {
        DockGeometry.refreshIfStale()
        guard DockGeometry.isNearDock(location), let dock = dockElement() else { return nil }
        let point = DockGeometry.awayFromScreenEdge(location)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &element)
        if result == .invalidUIElement || result == .cannotComplete { Self.dock = nil }
        guard result == .success, let element else { return nil }
        return DockItem(element)
    }

    private static func dockElement() -> AXUIElement? {
        if let dock { return dock }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleId).first?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        dock = element
        return element
    }

    private init?(_ element: AXUIElement) {
        guard let attributes = try? element.attributes([kAXSubroleAttribute, kAXIsApplicationRunningAttribute, kAXURLAttribute]),
              attributes.subrole == "AXApplicationDockItem" else { return nil }
        self.element = element
        isRunning = attributes.appIsRunning ?? false
        bundleId = attributes.url.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    var runningApp: NSRunningApplication? {
        guard isRunning, let bundleId else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// the Dock adds a menu as child of the icon while its context menu is open
    var isShowingMenu: Bool {
        guard let attributes = try? element.attributes([kAXChildrenAttribute]) else { return false }
        return !(attributes.children ?? []).isEmpty
    }

    func frame() -> CGRect? {
        guard let attributes = try? element.attributes([kAXPositionAttribute, kAXSizeAttribute]),
              let position = attributes.position, let size = attributes.size else { return nil }
        return CGRect(origin: position, size: size)
    }
}

/// keeps an auto-hiding Dock visible while the pointer travels from a Dock icon to its previews
/// the hold is persisted, so that a crash or force-quit while holding doesn't leave the user's auto-hide setting off
enum DockAutohide {
    private static let heldKey = "dockPreviewsAutohideHeld"
    private(set) static var isHolding = false

    static func restoreIfLeftHeld() {
        guard UserDefaults.standard.bool(forKey: heldKey) else { return }
        UserDefaults.standard.removeObject(forKey: heldKey)
        CoreDockSetAutoHideEnabled(true)
    }

    static func hold() {
        guard !isHolding, CoreDockGetAutoHideEnabled().boolValue else { return }
        isHolding = true
        UserDefaults.standard.set(true, forKey: heldKey)
        CoreDockSetAutoHideEnabled(false)
    }

    static func release() {
        guard isHolding else { return }
        isHolding = false
        CoreDockSetAutoHideEnabled(true)
        UserDefaults.standard.removeObject(forKey: heldKey)
    }
}
