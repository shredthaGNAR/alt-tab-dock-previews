var DockAltTabFORCEDX = 0
var DockAltTabFORCEDY = 0
var DockAltTabDockPos = ""
var DockAltTabApp: NSRunningApplication? = nil
var DockAltTabRepositionTimer: Timer? = nil

func DockAltTabRadiusFix() {
    if (Preferences.theme != .macOs) {return}
    let num = 22.0
    TilesView.contentView.layer?.cornerRadius = CGFloat(num)
    TilesView.contentView.updateRoundedCorners(num)
    TilesView.scrollView.layer?.cornerRadius = CGFloat(num)
}
func startDockAltTabMode(app: NSRunningApplication) {
    DockAltTabMode = true
    DockAltTabRadiusFix()
    DockAltTabApp = app
}
func DockAltTabResetCachedThumbnailPreviewSetting() {
    DockAltTabWaitForWindow = 0
}
func DockAltTabReset() { //called on HideScriptCommand.swift, App.showUiOrCycleSelection (key shortcut)
    DockAltTabMode = false
    DockAltTabRadiusFix()
    DockAltTabFORCEDX = 0
    DockAltTabFORCEDY = 0
    DockAltTabResetCachedThumbnailPreviewSetting()
}

// used by DockAltTab - show window previews for a specific app (1st window highlighted), ignoring blacklist
import Foundation
import Cocoa

class showAppScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let tarBID = evaluatedArguments?["appBID"] as? String,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: tarBID.trimmingCharacters(in: .whitespacesAndNewlines)).first else { return self }
        let x = evaluatedArguments?["x"] as? Int
        let y = evaluatedArguments?["y"] as? Int
        let anchor = x == nil && y == nil ? nil : NSPoint(x: x ?? Int(NSEvent.mouseLocation.x) - 40, y: y ?? Int(NSEvent.mouseLocation.y) + 40)
        DockAltTabActions.showApp(app, anchor, evaluatedArguments?["dockPos"] as? String ?? "bottom")
        return self
    }
}
