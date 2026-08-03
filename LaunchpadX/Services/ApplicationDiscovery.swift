import AppKit
import CoreServices
import Foundation

protocol ApplicationDiscovering: Sendable {
    func scan(roots: [URL]) async -> [InstalledApplication]
}

struct ApplicationDiscoveryService: ApplicationDiscovering {
    static var defaultRoots: [URL] {
        let manager = FileManager.default
        let paths = [
            "/Applications",
            "/System/Applications",
            "/System/Cryptexes/App/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        return paths.map(URL.init(fileURLWithPath:)).filter { manager.fileExists(atPath: $0.path) }
    }

    nonisolated func scan(roots: [URL]) async -> [InstalledApplication] {
        await Task.detached(priority: .background) {
            Self.scanSynchronously(roots: roots)
        }.value
    }

    nonisolated private static func scanSynchronously(roots: [URL]) -> [InstalledApplication] {
        let manager = FileManager.default
        let ownURL = Bundle.main.bundleURL.standardizedFileURL
        var result: [InstalledApplication] = []
        var seenPaths = Set<String>()
        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isExecutableKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let standardized = url.standardizedFileURL
                guard standardized != ownURL,
                      let app = parseApplication(at: standardized, root: root),
                      seenPaths.insert(app.normalizedPath).inserted else { continue }
                result.append(app)
            }
        }
        return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    nonisolated private static func parseApplication(at url: URL, root: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let localizedInfo = bundle.localizedInfoDictionary ?? [:]
        guard info["LSUIElement"] as? Bool != true,
              info["LSBackgroundOnly"] as? Bool != true else { return nil }
        let name = localizedMetadataName(for: url)
            ?? (localizedInfo["CFBundleDisplayName"] as? String)
            ?? (localizedInfo["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: name,
            bundleURL: url,
            version: info["CFBundleShortVersionString"] as? String,
            isSystemApplication: root.path.hasPrefix("/System")
        )
    }

    nonisolated private static func localizedMetadataName(for url: URL) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String else { return nil }
        let displayName = (name as NSString).deletingPathExtension
        return displayName.isEmpty ? nil : displayName
    }
}

protocol ApplicationLaunching: Sendable {
    func launch(_ application: InstalledApplication) async throws
}

struct ApplicationLauncherService: ApplicationLaunching {
    func launch(_ application: InstalledApplication) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: application.bundleURL, configuration: configuration)
    }
}

protocol IconProviding: Sendable {
    func icon(for application: InstalledApplication) -> NSImage
    func prewarm(_ applications: [InstalledApplication]) async
    func clearCache()
}

final class IconProvider: IconProviding, @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()

    func icon(for application: InstalledApplication) -> NSImage {
        let key = application.normalizedPath as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: application.bundleURL.path)
        icon.size = NSSize(width: 256, height: 256)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func prewarm(_ applications: [InstalledApplication]) async {
        for application in applications {
            guard !Task.isCancelled else { return }
            let key = application.normalizedPath as NSString
            guard cache.object(forKey: key) == nil else { continue }
            _ = icon(for: application)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    func clearCache() { cache.removeAllObjects() }
}
