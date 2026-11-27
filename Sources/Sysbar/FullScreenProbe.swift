import AppKit
import SysbarCore

// The window server's Space list, which has no public equivalent: it says whether the Space a display
// is showing belongs to a full-screen app. Present in every macOS release Sysbar supports.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?

/// Which displays are showing something full screen right now: reads the window list and the displays'
/// Spaces, and leaves the decision to `FullScreenDetection`. Neither needs a permission: window bounds,
/// layers and owners are readable without Screen Recording, which only guards window titles.
enum FullScreenProbe {
    /// The type of a Space that holds a full-screen app (a normal desktop is 0).
    private static let fullScreenSpaceType = 4

    @MainActor
    static func displays() -> Set<CGDirectDisplayID> {
        let inSpace = displaysInFullScreenSpace()
        let screens = NSScreen.screens.compactMap { screen -> FullScreenDisplay? in
            guard let id = screen.displayID else { return nil }
            return FullScreenDisplay(id: id, bounds: CGDisplayBounds(id), inFullScreenSpace: inSpace.contains(id))
        }
        return FullScreenDetection.displays(windows: windows(), screens: screens, ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    private static func windows() -> [FullScreenWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            return FullScreenWindow(pid: pid, layer: layer, bounds: bounds, alpha: alpha)
        }
    }

    /// The displays whose current Space is a full-screen app's. A display is named by its UUID there.
    private static func displaysInFullScreenSpace() -> Set<CGDirectDisplayID> {
        guard let managed = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return [] }
        let full = Set(managed.compactMap { entry -> String? in
            guard let current = entry["Current Space"] as? [String: Any],
                  current["type"] as? Int == fullScreenSpaceType,
                  let identifier = entry["Display Identifier"] as? String
            else { return nil }
            return identifier.lowercased()
        })
        guard !full.isEmpty else { return [] }
        return Set(NSScreen.screens.compactMap(\.displayID).filter { id in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let text = CFUUIDCreateString(nil, uuid) as String?
            else { return false }
            return full.contains(text.lowercased())
        })
    }
}
