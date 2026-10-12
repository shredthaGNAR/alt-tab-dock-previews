import Foundation
import Cocoa

let kPID: FourCharCode  = 0x70504944 // 'pPID'
let kWin: FourCharCode  = 0x6357696E // 'cWin'
let kCur: FourCharCode  = 0x63437572 // 'cCur'
let kMin: FourCharCode  = 0x634D696E // 'cMin'


func makeStatsRecord(
    countWindows: Int,
    countWindowsCurrentSpace: Int,
    countMinimizedWindowsCurrentSpace: Int
) -> NSAppleEventDescriptor {

    let record = NSAppleEventDescriptor.record()

    record.setDescriptor(
        NSAppleEventDescriptor(int32: Int32(countWindows)),
        forKeyword: kWin
    )

    record.setDescriptor(
        NSAppleEventDescriptor(int32: Int32(countWindowsCurrentSpace)),
        forKeyword: kCur
    )

    record.setDescriptor(
        NSAppleEventDescriptor(int32: Int32(countMinimizedWindowsCurrentSpace)),
        forKeyword: kMin
    )

    return record
}


class countWindowStatsScriptCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {

        guard
            let tarBID = (self.directParameter as? String),
            let tarApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: tarBID)
                .first
        else {
            return makeStatsRecord(
                countWindows: 0,
                countWindowsCurrentSpace: 0,
                countMinimizedWindowsCurrentSpace: 0
            )
        }

        let stats = DockAltTabActions.windowStats(tarApp.processIdentifier)
        return makeStatsRecord(
            countWindows: stats.all,
            countWindowsCurrentSpace: stats.currentSpace,
            countMinimizedWindowsCurrentSpace: stats.minimizedCurrentSpace
        )
    }
}
