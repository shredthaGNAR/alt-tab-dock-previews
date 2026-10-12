// call hideUI()
import Foundation
import Cocoa

class HideScriptCommand: NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
        DockAltTabActions.hide()
        return self
	}
}
