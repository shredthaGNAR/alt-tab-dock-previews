// used by DockAltTab: deminimize the app's first window that was minimized on the current space
import Foundation
import Cocoa

class deminimizeFirstMinimizedWindowFromCurrentSpaceScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let tarBID = evaluatedArguments?["appBID"] as? String,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: tarBID.trimmingCharacters(in: .whitespacesAndNewlines)).first else { return 0 }
        DockAltTabActions.deminimizeFirstMinimizedWindowOnCurrentSpace(app.processIdentifier)
        return self
    }
}
