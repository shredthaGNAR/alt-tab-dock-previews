import Foundation
import Cocoa

class countAllWindowStatsScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let list = NSAppleEventDescriptor.list()
        for app in Applications.list {
            let stats = DockAltTabActions.windowStats(app.pid)
            guard stats.all > 0 else { continue }
            let record = makeStatsRecord(countWindows: stats.all, countWindowsCurrentSpace: stats.currentSpace, countMinimizedWindowsCurrentSpace: stats.minimizedCurrentSpace)
            record.setDescriptor(NSAppleEventDescriptor(int32: Int32(app.pid)), forKeyword: kPID)
            list.insert(record, at: list.numberOfItems + 1)
        }
        return list
    }
}
