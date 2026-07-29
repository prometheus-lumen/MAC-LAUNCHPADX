import AppKit
import Foundation

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let searchSort = "searchSort"
        static let iconSize = "iconSize"
        static let columns = "gridColumns"
        static let rows = "gridRows"
        static let displayStrategy = "displayStrategy"
        static let fixedDisplayID = "fixedDisplayID"
        static let lastDisplayID = "lastDisplayID"
        static let backgroundKind = "backgroundKind"
        static let customBackgroundPath = "customBackgroundPath"
        static let hotKey = "hotKey"
        static let previousPageHotKey = "previousPageHotKey"
        static let nextPageHotKey = "nextPageHotKey"
        static let reversePageDirection = "reversePageDirection"
        static let focusSearch = "focusSearch"
        static let scanRoots = "scanRoots"
    }

    private let defaults: UserDefaults

    var searchSort: SearchSortOrder { didSet { defaults.set(searchSort.rawValue, forKey: Key.searchSort) } }
    var iconSize: Double { didSet { defaults.set(iconSize, forKey: Key.iconSize) } }
    var columns: Int { didSet { defaults.set(columns, forKey: Key.columns) } }
    var rows: Int { didSet { defaults.set(rows, forKey: Key.rows) } }
    var displayStrategy: DisplayStrategy { didSet { defaults.set(displayStrategy.rawValue, forKey: Key.displayStrategy) } }
    var fixedDisplayID: CGDirectDisplayID? { didSet { defaults.set(fixedDisplayID.map { Int($0) }, forKey: Key.fixedDisplayID) } }
    var lastDisplayID: CGDirectDisplayID? { didSet { defaults.set(lastDisplayID.map { Int($0) }, forKey: Key.lastDisplayID) } }
    var backgroundKind: LauncherBackgroundKind { didSet { defaults.set(backgroundKind.rawValue, forKey: Key.backgroundKind) } }
    var customBackgroundPath: String? { didSet { defaults.set(customBackgroundPath, forKey: Key.customBackgroundPath) } }
    var hotKey: HotKey { didSet { saveHotKey() } }
    var previousPageHotKey: HotKey { didSet { savePageHotKeys() } }
    var nextPageHotKey: HotKey { didSet { savePageHotKeys() } }
    var reversePageDirection: Bool { didSet { defaults.set(reversePageDirection, forKey: Key.reversePageDirection) } }
    var focusSearchOnShow: Bool { didSet { defaults.set(focusSearchOnShow, forKey: Key.focusSearch) } }
    var additionalScanRoots: [URL] { didSet { defaults.set(additionalScanRoots.map(\.path), forKey: Key.scanRoots) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        searchSort = SearchSortOrder(rawValue: defaults.string(forKey: Key.searchSort) ?? "") ?? .relevance
        iconSize = defaults.object(forKey: Key.iconSize) as? Double ?? 94
        columns = max(3, min(8, defaults.object(forKey: Key.columns) as? Int ?? 7))
        rows = max(3, min(6, defaults.object(forKey: Key.rows) as? Int ?? 5))
        displayStrategy = DisplayStrategy(rawValue: defaults.string(forKey: Key.displayStrategy) ?? "") ?? .cursor
        fixedDisplayID = defaults.object(forKey: Key.fixedDisplayID).map { CGDirectDisplayID(($0 as? NSNumber)?.uint32Value ?? 0) }
        lastDisplayID = defaults.object(forKey: Key.lastDisplayID).map { CGDirectDisplayID(($0 as? NSNumber)?.uint32Value ?? 0) }
        backgroundKind = LauncherBackgroundKind(rawValue: defaults.string(forKey: Key.backgroundKind) ?? "") ?? .wallpaper
        customBackgroundPath = defaults.string(forKey: Key.customBackgroundPath)
        if let data = defaults.data(forKey: Key.hotKey), let decoded = try? JSONDecoder().decode(HotKey.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .defaultLauncher
        }
        previousPageHotKey = Self.decodeHotKey(defaults.data(forKey: Key.previousPageHotKey)) ?? .defaultPreviousPage
        nextPageHotKey = Self.decodeHotKey(defaults.data(forKey: Key.nextPageHotKey)) ?? .defaultNextPage
        reversePageDirection = defaults.object(forKey: Key.reversePageDirection) as? Bool ?? false
        focusSearchOnShow = defaults.object(forKey: Key.focusSearch) as? Bool ?? true
        additionalScanRoots = (defaults.stringArray(forKey: Key.scanRoots) ?? []).map(URL.init(fileURLWithPath:))
    }

    var gridCapacity: Int { columns * rows }
    var allScanRoots: [URL] { Array(Set(ApplicationDiscoveryService.defaultRoots + additionalScanRoots)) }

    func resetLayoutPreferences() {
        iconSize = 94
        columns = 7
        rows = 5
    }

    private func saveHotKey() {
        defaults.set(try? JSONEncoder().encode(hotKey), forKey: Key.hotKey)
    }

    private func savePageHotKeys() {
        defaults.set(try? JSONEncoder().encode(previousPageHotKey), forKey: Key.previousPageHotKey)
        defaults.set(try? JSONEncoder().encode(nextPageHotKey), forKey: Key.nextPageHotKey)
    }

    private static func decodeHotKey(_ data: Data?) -> HotKey? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
}
