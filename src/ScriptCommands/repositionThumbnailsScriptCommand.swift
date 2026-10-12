import Foundation
import Cocoa

class repositionThumbnailsScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let position = directParameter as? [NSNumber], position.count >= 2 else { return self }
        DockAltTabActions.reposition(NSPoint(x: position[0].intValue, y: position[1].intValue))
        return self
    }
}
